import GolfgutuCore
import Supabase
import SwiftUI

// Runden som pågår, som baren over fanelinja (utbedringsplanen V1): ute av feeden, synlig på alle
// fanene. Flere runder samtidig (sql/034): den første, og «+1 runde til» som åpner et valg.

/// Tekstene i baren. Ren, med tester (HjemLiveBarTests).
nonisolated enum HomeLiveBar {
    /// «bås 2» → «Bås 2».
    static func capitalized(_ text: String) -> String {
        text.prefix(1).uppercased() + text.dropFirst()
    }

    /// «Bås 2 · du er 3. med 21 p». Hull for hull: «du står 1 opp». Spiller du ikke (arrangøren):
    /// «Bjørn leder med 23 p». Før første hull står bare båsen.
    static func detail(bay: String?, mine: BayenRow?, leader: BayenRow?) -> String? {
        var parts: [String] = []
        if let bay { parts.append(bay) }
        if let mine {
            if mine.thru > 0 { parts.append(standing(mine)) }
        } else if let leader, leader.thru > 0, leader.match == nil, leader.place != nil {
            parts.append("\(leader.name) leder med \(leader.total) p")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private static func standing(_ row: BayenRow) -> String {
        if row.match == nil, let place = row.place { return "du er \(place). med \(row.total) p" }
        return "du står \(row.value.lowercased())"
    }

    /// Baren vises når en runde går og ingen føring står åpen: inne i runden er «Fortsett» unødvendig,
    /// den er for å komme tilbake til føringen.
    static func isShown(liveCount: Int, openRoundScreens: Int) -> Bool {
        liveCount > 0 && openRoundScreens == 0
    }

    /// «+1 runde til», «+2 runder til». nil når bare én går.
    static func moreText(count: Int) -> String? {
        let others = count - 1
        guard others > 0 else { return nil }
        return others == 1 ? "+1 runde til" : "+\(others) runder til"
    }
}

/// Baren for rundene som pågår. Tom liste: ingenting (tilbehøret er da skrudd av).
struct HjemLiveRoundBar: View {
    let live: [HomeLive]
    let open: (HomeLive) -> Void

    var body: some View {
        if let first = live.first {
            DDLiveRoundBar(title: first.barTitle.isEmpty ? first.title : first.barTitle, detail: first.barDetail,
                           actionTitle: first.barAction, open: { open(first) }) {
                if let more = HomeLiveBar.moreText(count: live.count) {
                    Menu {
                        ForEach(live, id: \.roundID) { round in
                            Button(round.barTitle.isEmpty ? round.title : round.barTitle) { open(round) }
                        }
                    } label: {
                        DDLiveRoundMoreLabel(text: "+\(live.count - 1)")
                    }
                    .accessibilityLabel(more)
                    .accessibilityHint("Velg hvilken runde du vil åpne.")
                }
            }
        }
    }
}

/// Tilbehøret over fanelinja og krympingen ved rulling (iOS 26). `tabViewBottomAccessory(isEnabled:)`
/// kom i 26.1; på 26.0 ville tilbehøret stått tomt uten runde, så der står runden i feeden i stedet
/// (`HjemLiveBarPlacement.inFeed`).
struct HjemLiveAccessory: ViewModifier {
    let live: [HomeLive]
    let open: (HomeLive) -> Void
    /// Føringene som står framme (`hidesLiveRoundBar`). Fanelinja skjules der, men tilbehøret over
    /// den gjør ikke det av seg selv.
    @State private var openRoundScreens: Set<UUID> = []

    func body(content: Content) -> some View {
        let marked = content.environment(\.markRoundScreen) { id, isOpen in
            if isOpen { openRoundScreens.insert(id) } else { openRoundScreens.remove(id) }
        }
        if #available(iOS 26.1, *) {
            marked
                .tabViewBottomAccessory(isEnabled: HomeLiveBar.isShown(liveCount: live.count,
                                                                      openRoundScreens: openRoundScreens.count)) {
                    HjemLiveRoundBar(live: live, open: open)
                }
                .tabBarMinimizeBehavior(.onScrollDown)
        } else {
            marked
                .tabBarMinimizeBehavior(.onScrollDown)
                .environment(\.liveBarInFeed, true)
        }
    }
}

/// Melder fra til `HjemLiveAccessory` at føringen står framme, så baren over fanelinja skjules.
private struct HidesLiveRoundBar: ViewModifier {
    @Environment(\.markRoundScreen) private var mark
    @State private var id = UUID()

    func body(content: Content) -> some View {
        content
            .onAppear { mark(id, true) }
            .onDisappear { mark(id, false) }
    }
}

extension View {
    /// Runden som pågår over fanelinja (V1).
    func hjemLiveAccessory(_ live: [HomeLive], open: @escaping (HomeLive) -> Void) -> some View {
        modifier(HjemLiveAccessory(live: live, open: open))
    }

    /// Føringen: ingen «Fortsett»-bar over fanelinja mens den står framme.
    func hidesLiveRoundBar() -> some View {
        modifier(HidesLiveRoundBar())
    }
}

extension EnvironmentValues {
    /// iOS 26.0: tilbehøret over fanelinja kan ikke skrus av, så runden står øverst i feeden.
    @Entry var liveBarInFeed = false

    /// Føringen står framme (true) eller er borte (false). Fra `hidesLiveRoundBar`.
    @Entry var markRoundScreen: (UUID, Bool) -> Void = { _, _ in }
}

/// Rundene som pågår uten klubb (`FriendsRootView`): de løse rundene du spiller i. Med klubb kommer
/// de fra Hjem-feeden (`HomeFeedModel`).
@Observable
final class LiveRoundsModel {
    private(set) var live: [HomeLive] = []
    private let client: SupabaseClient?
    private let userID: UUID

    init(client: SupabaseClient?, userID: UUID) {
        self.client = client
        self.userID = userID
    }

    func load() async {
        guard let client, let rounds = try? await LooseRoundQueries.myRounds(client: client) else { return }
        live = Self.live(rounds, userID: userID)
    }

    /// Rundene som går og som du spiller i, som baren viser dem.
    nonisolated static func live(_ rounds: [RoundSnapshot], userID: UUID, now: Date = .now) -> [HomeLive] {
        let viewer = HomeViewer(profileID: userID, memberships: [:])
        let input = HomeFeedInput(now: now, viewer: viewer)
        let context = HomeFeedContext(input)
        return HomeFeed.liveInputs(focused: nil, rounds: rounds, viewer: viewer, club: nil)
            .map { HomeFeed.live($0, context: context) }
    }
}
