import GolfgutuCore
import Supabase
import SwiftUI

struct RootView: View {
    let config: AppConfig
    let user: AuthUser
    let membership: Membership
    @State private var selectedTab: AppTab = .hjem
    @Environment(\.clubContext) private var context
    @Environment(ClubModel.self) private var club: ClubModel?
    /// Hjem-feeden (fase 19). Bor her, så bjella teller i alle fanene. Ny når medlemskapene byttes.
    @State private var home: HomeFeedModel?
    @State private var homeKey: String?
    @State private var router = HjemRouter()
    /// «Kveld» eller «spilledag» for klubbens hovedturnering (`DayTerm`). Arrangørsiden bruker den valgte.
    @State private var dayTerm: DayTerm = .evening
    /// De som venter på godkjenning (sql/067): merket på Arrangør-fanen. nil når flagget er av.
    @State private var pendingMembers: PendingMembersModel?
    /// Troppen på Arrangør-fanen, fra et trykk på varselet om et ventende medlem.
    @State private var showsRoster = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView(selection: $selectedTab) {
            ForEach(AppTab.tabs(isOrganizer: context?.isOrganizer ?? false)) { tab in
                Tab(tab.title, systemImage: tab.systemImage, value: tab) {
                    NavigationStack {
                        content(for: tab)
                            .navigationTitle(tab.title)
                            .ddNavigationChrome()
                            .toolbar {
                                // Klubbvalget på Hjem når du er med i flere klubber (planen 4.1).
                                if tab == .hjem, let club, memberships.count > 1 {
                                    ToolbarItem(placement: .topBarLeading) {
                                        HjemClubMenu(memberships: memberships, current: membership.clubID) {
                                            club.select($0)
                                        }
                                    }
                                }
                                // Høyst to: miljømerket (ikke prod)
                                // og bjella.
                                if config.environment != .prod {
                                    ToolbarItem(placement: .topBarTrailing) {
                                        EnvironmentBadge(environment: config.environment)
                                            .tint(Color.ddForestInk)
                                    }
                                }
                                if let home {
                                    ToolbarItem(placement: .topBarTrailing) {
                                        // Skog i systemets glass (utbedringsplanen K3).
                                        HjemBell(model: home)
                                            .tint(Color.ddForestInk)
                                    }
                                }
                            }
                    }
                    // Knapper og lenker i innholdet er skoggrønne; gult er bare aktiv fane.
                    .tint(Color.ddForestInk)
                    .environment(\.currentTab, tab)
                    .ddReadableWidth()
                    .ddScreenBackground()
                }
                .badge(tab == .arrangor ? pendingMembers?.badge ?? 0 : 0)
            }
        }
        // Runden som pågår over fanelinja, på alle fanene (utbedringsplanen V1).
        .hjemLiveAccessory(home?.feed.live ?? [], open: openLive)
        // Aktiv fane i skog: gult er bare hovedknappen (utbedringsplanen 1.1).
        .tint(Color.ddForestInk)
        .environment(\.selectTab) { selectedTab = $0 }
        .environment(\.showRound) { roundID in
            selectedTab = .hjem
            router.showRound(roundID)
        }
        .onReceive(NotificationCenter.default.publisher(for: RoundRequests.show)) { note in
            selectedTab = .hjem
            router.showRound(note.object as? UUID)
        }
        .task(id: memberships.map(\.id)) { makeHome() }
        // Trykk på en push: også det som kom før innloggingen var klar (kald oppstart).
        .onChange(of: PushTapInbox.shared.pending, initial: true) { openPush() }
        .onChange(of: membership.clubID) { openPush() }
        .environment(\.dayTerm, dayTerm)
        .task(id: context?.clubID) {
            guard let context else { return }
            dayTerm = await DayTermQueries.main(client: context.client, clubID: context.clubID)
        }
        // Ventende medlemmer (sql/067): nytt tall når klubben eller rettigheten byttes, appen blir
        // aktiv, en push kommer eller fanen byttes.
        .environment(pendingMembers)
        .task(id: PendingMembersKey(clubID: context?.clubID, canManage: context?.can(.members) ?? false)) {
            await makePendingMembers()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await pendingMembers?.load() } }
        }
        .onChange(of: selectedTab) { Task { await pendingMembers?.load() } }
        .onReceive(NotificationCenter.default.publisher(for: PushInbox.received)) { _ in
            Task { await pendingMembers?.load() }
        }
    }

    private func makePendingMembers() async {
        guard PendingMembersFeature.isEnabled, let context, context.can(.members) else {
            pendingMembers = nil
            return
        }
        let model = PendingMembersModel(client: context.client, clubID: context.clubID, canManage: true)
        pendingMembers = model
        await model.load()
    }

    /// Baren over fanelinja: føringen åpnes på Hjem, som før fra «Pågår nå».
    private func openLive(_ live: HomeLive) {
        selectedTab = .hjem
        if live.isLoose {
            router.showLooseRound(live.roundID)
        } else {
            router.showRound(live.roundID)
        }
    }

    /// Velger fanen og ber Hjem åpne skjermen. Sier pushen hvilken klubb, byttes det dit først.
    private func openPush() {
        guard let pending = PushTapInbox.shared.pending else { return }
        if let clubID = pending.clubID, clubID != membership.clubID,
           memberships.contains(where: { $0.clubID == clubID }) {
            club?.select(clubID: clubID)
            return
        }
        guard let tap = PushTapInbox.shared.take() else { return }
        // Troppen: bare for dem med Medlemmer og invitasjon (ellers Hjem).
        if tap.destination == .roster {
            guard context?.can(.members) == true,
                  AppTab.tabs(isOrganizer: context?.isOrganizer ?? false).contains(.arrangor) else {
                selectedTab = .hjem
                return
            }
            selectedTab = .arrangor
            showsRoster = true
            return
        }
        selectedTab = tap.destination.tab
        if tap.destination.tab == .hjem { router.open(tap.destination) }
    }

    private var memberships: [Membership] {
        club?.memberships.filter { $0.status == .active } ?? [membership]
    }

    /// Én `HomeFeedModel` per innlogging og sett med medlemskap.
    private func makeHome() {
        guard let context else { home = nil; homeKey = nil; return }
        let key = user.id.uuidString + memberships.map(\.id.uuidString).sorted().joined()
        guard key != homeKey else { return }
        let old = home
        Task { await old?.stopRealtime() }
        home = HomeFeedModel(client: context.client, userID: user.id,
                             memberships: memberships.isEmpty ? [membership] : memberships)
        homeKey = key
    }

    @ViewBuilder
    private func content(for tab: AppTab) -> some View {
        switch tab {
        case .hjem: HjemView(home: home, router: router)
        case .spill:
            if let context {
                SpillView(model: SpillModel(client: context.client, userID: user.id))
            }
        case .tavla: TavlaView()
        case .arrangor:
            AdminHubView()
                .navigationDestination(isPresented: $showsRoster) { TroppAdminView() }
        case .deg: DegView(config: config, user: user, membership: membership)
        }
    }
}

/// Når merket for ventende medlemmer må lages på nytt: ny klubb, eller rettigheten endres.
private struct PendingMembersKey: Hashable {
    let clubID: UUID?
    let canManage: Bool
}

extension EnvironmentValues {
    /// Bytter fane fra et view inne i en fane.
    @Entry var selectTab: (AppTab) -> Void = { _ in }

    /// Fanen et view ligger i.
    @Entry var currentTab: AppTab? = nil

    /// Åpner runden som går, på Hjem (arrangørsidens «Gå til runden»).
    /// Åpner runden som går på Hjem. Med id: den runden (flere kan gå samtidig, sql/034).
    @Entry var showRound: (UUID?) -> Void = { _ in }
}

/// «Åpne runden på Hjem» fra et ark utenfor `RootView` (turneringen fra en lenke): arket lukkes,
/// og `RootView` tar imot runde-id-en (`object`, nil: runden som går).
nonisolated enum RoundRequests {
    static let show = Notification.Name("DashDash18.showRound")
}

/// Merke i verktøylinjen så det aldri er tvil om at appen ikke kjører mot prod.
struct EnvironmentBadge: View {
    let environment: AppEnvironment

    var body: some View {
        // Gull på grønt, som rundechipen i PWA-ens header.
        DDPill(environment.displayName, tone: .gold)
            .fixedSize()
            .accessibilityLabel("Miljø: \(environment.displayName)")
    }
}

#if DEBUG
#Preview {
    RootView(config: .preview, user: .preview, membership: .preview)
}
#endif

extension AuthUser {
    static let preview = AuthUser(id: UUID(), email: "deg@epost.no")
}

extension Membership {
    static let preview = Membership(
        id: UUID(), clubID: UUID(), displayName: "Thomas", status: .active,
        isOrganizer: true, isTreasurer: false,
        club: ClubInfo(name: "Golfgutu Invitational", joinCode: "A1B2C3D4E5")
    )
}

#if DEBUG
/// Bare for skjermprøvene, som `*Samples.swift`.
extension AppConfig {
    static let preview = try! AppConfig(
        plistData: try! PropertyListSerialization.data(
            fromPropertyList: [
                "Environment": "test",
                "SupabaseURL": "https://forhandsvisning.supabase.co",
                "SupabasePublishableKey": "sb_publishable_forhandsvisning",
            ],
            format: .xml,
            options: 0
        ),
        expecting: .test
    )
}
#endif

/// Ordet for en dag i klubbens hovedturnering (`DayTerm`).
enum DayTermQueries {
    /// Hovedturneringen (`MainTournament.tableSeason`), ellers den sist opprettede. «Kveld» når ingen
    /// finnes eller hentingen feiler.
    static func main(client: SupabaseClient, clubID: UUID) async -> DayTerm {
        async let fetched: [SeasonRow]? = try? await SeasonQuery.select(client)
            .eq("club_id", value: clubID)
            .order("created_at", ascending: false)
            .execute().value
        async let mains = MainTournament.seasonIDs(client: client, clubID: clubID)
        guard let rows = await fetched else { return .evening }
        return (MainTournament.tableSeason(rows, mainSeasonIDs: await mains) ?? rows.first)?.rules.day ?? .evening
    }
}
