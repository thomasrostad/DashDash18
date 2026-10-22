import GolfgutuCore
import Observation
import Supabase
import SwiftUI

// Inngangene til veddemålene: runden (klubbrunder og løse runder), Kveld, Tavla og turneringssiden.
// Vises bare med `BetsFeature.isEnabled`, og med 052 bare der veddemål er slått på.

/// Bankene en runde kan vedde i (052). `options == nil`: 052 mangler, og hovedturneringen gjelder
/// som før (bare i en klubb).
@Observable
final class RoundBetsModel {
    private(set) var options: [BetScopeOption]?
    private(set) var isLoaded = false
    var selected: BetScope?

    let client: SupabaseClient
    let viewer: BetViewer
    let round: RoundRow
    let roundName: String

    init(client: SupabaseClient, viewer: BetViewer, round: RoundRow, roundName: String) {
        self.client = client
        self.viewer = viewer
        self.round = round
        self.roundName = roundName
    }

    func load() async {
        guard BetsFeature.isEnabled else { return }
        do {
            options = try await BetsQueries.scopes(client: client, round: round, roundName: roundName)
        } catch is CancellationError {
            return
        } catch {
            options = []
        }
        if let options, selected == nil || !options.contains(where: { $0.scope == selected }) {
            selected = options.first?.scope
        }
        isLoaded = true
    }

    /// Modellen for banken som er valgt.
    func betsModel(fallback context: ClubContext?) -> BetsModel? {
        if let selected {
            let target: BetsModel.Target = switch selected {
            case .competition(let id): .competition(id)
            case .round(let id): .round(id)
            }
            return BetsModel(client: client, viewer: viewer, target: target)
        }
        if options == nil, let context { return BetsModel(context: context) }
        return nil
    }

    /// Vises «Vedd»? Med 052: når en bank har veddemål på. Uten: i en klubbrunde.
    func showsButton(hasClub: Bool) -> Bool {
        guard isLoaded else { return false }
        guard let options else { return hasClub }
        return !options.isEmpty
    }
}

/// Under runden: «Vedd» med spillerne i runden og deg selv, og veien til alle veddemål. Hører runden
/// til flere turneringer med veddemål, velges banken i menyen.
struct VeddKnapp: View {
    let game: RoundGame
    /// Din id i runden.
    let me: UUID
    @State var model: RoundBetsModel
    /// Bryteren for rundens egen bank: bare eieren av en løs runde som ikke er avsluttet.
    @State private var roundSwitch: BetsSwitchModel?
    @Environment(\.clubContext) private var context
    @State private var target: VeddTarget?

    init(game: RoundGame, me: UUID, client: SupabaseClient, viewer: BetViewer, ownsRound: Bool = false) {
        self.game = game
        self.me = me
        _model = State(initialValue: RoundBetsModel(client: client, viewer: viewer, round: game.snapshot.round,
                                                    roundName: game.snapshot.course?.name ?? "Runden"))
        let open = game.snapshot.round.status != .locked
        _roundSwitch = State(initialValue: ownsRound && open
                             ? BetsSwitchModel(client: client, scope: .round(game.snapshot.round.id)) : nil)
    }

    var body: some View {
        VStack(spacing: DDSpacing.s) {
            if BetsFeature.isEnabled, let roundSwitch {
                BetsSwitchRow(model: roundSwitch, subtitle: "Egen poengbank for runden. Av som standard.")
                    .ddCard()
                    .onChange(of: roundSwitch.enabled) { _, _ in Task { await model.load() } }
            }
            buttons
        }
        .task(id: game.snapshot.round.id) { await model.load() }
    }

    @ViewBuilder
    private var buttons: some View {
        Group {
            if BetsFeature.isEnabled, model.showsButton(hasClub: game.snapshot.round.clubID != nil) {
                HStack(spacing: DDSpacing.s) {
                    Menu {
                        if let options = model.options, options.count > 1 {
                            Picker("Poengbank", selection: $model.selected) {
                                ForEach(options) { Text($0.name).tag(Optional($0.scope)) }
                            }
                        }
                        Button("Om meg selv") { target = VeddTarget(against: nil) }
                        Section("Vedd på") {
                            ForEach(opponents, id: \.self) { id in
                                Button(game.name(id)) { target = VeddTarget(against: id) }
                            }
                        }
                    } label: {
                        Label("Vedd", systemImage: "die.face.5")
                    }
                    NavigationLink {
                        if let bets = model.betsModel(fallback: context) {
                            BetsView(model: bets)
                        }
                    } label: {
                        Label("Alle veddemål", systemImage: "list.bullet")
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                .buttonStyle(.dd(.secondary, fullWidth: true, compact: true))
                .navigationDestination(item: $target) { t in
                    if let bets = model.betsModel(fallback: context) {
                        BetsView(model: bets, against: t.against ?? me, roundID: game.snapshot.round.id)
                    }
                }
            }
        }
    }

    /// Spillerne i runden, uten deg. I en løs runde bare de med profil: gjester er ikke med i banken.
    private var opponents: [UUID] {
        let guests = Set(game.snapshot.loose?.guests.map(\.playerID) ?? [])
        return game.snapshot.players.map(\.memberID)
            .filter { $0 != me && !guests.contains($0) }
            .sorted { NorwegianSort.areInIncreasingOrder(game.name($0), game.name($1)) }
    }
}

/// Hvem arket skal åpnes for. `against == me` betyr «om meg selv» i `BetsView`.
struct VeddTarget: Identifiable, Hashable {
    let against: UUID?
    var id: String { against?.uuidString ?? "meg" }
}

/// Er veddemål på i hovedturneringen? `enabled == nil`: 052 mangler (da som før: på).
@Observable
final class MainBetsStatus {
    private(set) var enabled: Bool?
    private(set) var isLoaded = false

    func load(context: ClubContext) async {
        guard BetsFeature.isEnabled else { return }
        if let season = try? await TavlaQueries.mainSeason(client: context.client, clubID: context.clubID),
           let rows: [MainRow] = try? await context.client.from("competitions").select("bets_enabled")
               .eq("season_id", value: season.id).execute().value {
            enabled = rows.first?.betsEnabled
        }
        isLoaded = true
    }

    private struct MainRow: Decodable {
        let betsEnabled: Bool
        enum CodingKeys: String, CodingKey { case betsEnabled = "bets_enabled" }
    }

    /// Kortet vises når veddemål er på (eller 052 mangler), og for den som kan slå det på.
    func shows(canToggle: Bool) -> Bool {
        guard isLoaded else { return false }
        return enabled != false || canToggle
    }
}

/// Kortet på Kveld før runden.
struct BetsKveldCard: View {
    @Environment(\.dayTerm) private var dayTerm
    @Environment(\.clubContext) private var context
    @State private var status = MainBetsStatus()

    var body: some View {
        Group {
            if BetsFeature.isEnabled, status.shows(canToggle: canToggle) {
                NavigationLink {
                    BetsView()
                } label: {
                    HStack(spacing: DDSpacing.m) {
                        Image(systemName: "die.face.5")
                            .font(.title3)
                            .foregroundStyle(Color.ddForestInk)
                            .frame(width: 32)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Veddemål")
                                .font(.ddBodyEmphasis)
                                .foregroundStyle(Color.ddInk)
                            Text(status.enabled == false ? "Av. Trykk for å slå på." : "Vedd poeng på \(dayTerm.the) og hverandre")
                                .font(.ddCallout)
                                .foregroundStyle(Color.ddInkSecondary)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color.ddInkSecondary)
                    }
                    .contentShape(.rect)
                    .ddCard()
                    .accessibilityElement(children: .combine)
                }
                .buttonStyle(.plain)
            }
        }
        .task {
            if let context { await status.load(context: context) }
        }
    }

    private var canToggle: Bool {
        guard let context else { return false }
        return context.can(.money) || context.can(.tournaments)
    }
}

/// Tavla: veien til poengtabellen for veddemål, under jakketabellen.
struct BetsTavlaLink: View {
    @Environment(\.clubContext) private var context
    @State private var status = MainBetsStatus()

    var body: some View {
        Group {
            if BetsFeature.isEnabled, status.shows(canToggle: false) {
                NavigationLink {
                    BetsTableScreen()
                } label: {
                    HStack {
                        Label("Poengtabell for veddemål", systemImage: "die.face.5")
                            .font(.ddBodyEmphasis)
                            .foregroundStyle(Color.ddForestInk)
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color.ddInkSecondary)
                    }
                    .contentShape(.rect)
                    .ddCard()
                }
                .buttonStyle(.plain)
            }
        }
        .task {
            if let context { await status.load(context: context) }
        }
    }
}

/// Turneringssiden (liga, cup, morro, private): veien til veddemålene når de er på, og bryteren for
/// den som styrer turneringen. Vises ikke uten 052.
struct CompetitionBetsCard: View {
    @State var switchModel: BetsSwitchModel
    let viewer: BetViewer
    let competitionID: UUID
    let isAdmin: Bool

    init(client: SupabaseClient, viewer: BetViewer, competitionID: UUID, isAdmin: Bool) {
        _switchModel = State(initialValue: BetsSwitchModel(client: client, scope: .competition(competitionID)))
        self.viewer = viewer
        self.competitionID = competitionID
        self.isAdmin = isAdmin
    }

    var body: some View {
        Group {
            if BetsFeature.isEnabled, let enabled = switchModel.enabled, enabled || isAdmin {
                VStack(alignment: .leading, spacing: DDSpacing.m) {
                    if enabled {
                        NavigationLink {
                            BetsView(model: BetsModel(client: switchModel.client, viewer: viewer,
                                                      target: .competition(competitionID)))
                        } label: {
                            HStack(spacing: DDSpacing.m) {
                                Image(systemName: "die.face.5")
                                    .font(.title3)
                                    .foregroundStyle(Color.ddForestInk)
                                    .frame(width: 32)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Veddemål")
                                        .font(.ddBodyEmphasis)
                                        .foregroundStyle(Color.ddInk)
                                    Text("Vedd poeng på rundene og hverandre")
                                        .font(.ddCallout)
                                        .foregroundStyle(Color.ddInkSecondary)
                                }
                                Spacer(minLength: 8)
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(Color.ddInkSecondary)
                            }
                            .contentShape(.rect)
                            .accessibilityElement(children: .combine)
                        }
                        .buttonStyle(.plain)
                    }
                    if isAdmin {
                        BetsSwitchRow(model: switchModel, subtitle: BetTexts.toggleFooter)
                    }
                }
                .ddCard()
            }
        }
        .task(id: competitionID) { await switchModel.load() }
    }
}

/// Poengtabellen som egen skjerm fra Tavla.
private struct BetsTableScreen: View {
    @Environment(\.clubContext) private var context

    var body: some View {
        if let context {
            BetsTableContent(model: BetsModel(context: context))
        }
    }
}

private struct BetsTableContent: View {
    @State var model: BetsModel

    var body: some View {
        Group {
            if let board = model.board {
                BetPointsTableView(board: board)
            } else if model.state == .disabled {
                ContentUnavailableView("Veddemål kommer", systemImage: "die.face.5",
                                       description: Text("Veddemål med poeng slås på når databasen er klar."))
            } else if case .failed(let message) = model.state {
                ContentUnavailableView {
                    Label("Fikk ikke hentet tabellen", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(message)
                } actions: {
                    Button("Prøv igjen") { Task { await model.load() } }.buttonStyle(.dd(.primary))
                }
            } else {
                ProgressView("Henter tabellen …")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task { await model.load() }
        .refreshable { await model.load() }
    }
}
