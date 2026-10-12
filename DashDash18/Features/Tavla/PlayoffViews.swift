import GolfgutuCore
import Observation
import Supabase
import SwiftUI

// MARK: - Kortet på Tavla

/// Playoff om førsteplassen på Tavla (sql/047): «Start playoff» når førsteplassen er delt, ellers
/// status og veien til føringen.
struct PlayoffCard: View {
    let standings: TavlaStandings
    var onChange: (() async -> Void)?
    @Environment(\.clubContext) private var context
    @State private var showsStart = false
    @State private var openRound: PlayoffRoundRef?

    var body: some View {
        if let playoff = standings.playoff {
            Button { openRound = PlayoffRoundRef(id: playoff.snapshot.round.id) } label: {
                HStack(spacing: 12) {
                    Image(systemName: "flag.2.crossed")
                        .foregroundStyle(Color.ddForestInk)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(playoff.isLocked ? "Playoff ferdig" : "Playoff pågår")
                            .font(.ddBodyEmphasis)
                        Text(playoff.statusText(name: name))
                            .font(.ddCallout)
                            .foregroundStyle(Color.ddInkSecondary)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.ddInkSecondary)
                        .accessibilityHidden(true)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .ddCard()
            .sheet(item: $openRound) { ref in screen(ref.id) }
        } else if canStart {
            Button("Start playoff", systemImage: "flag.2.crossed") { showsStart = true }
                .buttonStyle(.dd(.primary, fullWidth: true))
                .sheet(isPresented: $showsStart) {
                    if let context {
                        NavigationStack {
                            PlayoffStartView(model: PlayoffStartModel(client: context.client, standings: standings)) { id in
                                showsStart = false
                                openRound = PlayoffRoundRef(id: id)
                                Task { await onChange?() }
                            }
                        }
                    }
                }
                .sheet(item: $openRound) { ref in screen(ref.id) }
        }
    }

    private var canStart: Bool {
        guard RoundRulesFeature.isAvailable, let context, standings.tiedForFirst.count > 1 else { return false }
        return PlayoffRules.canStart(rights: context.rights)
    }

    private func name(_ id: UUID) -> String {
        standings.row(id)?.name ?? "Ukjent"
    }

    @ViewBuilder
    private func screen(_ id: UUID) -> some View {
        if let context {
            NavigationStack {
                PlayoffScreen(model: PlayoffModel(client: context.client, roundID: id, tied: standings.tiedForFirst,
                                                  viewer: Viewer(memberID: context.memberID,
                                                                 isOrganizer: context.can(.rounds)),
                                                  canManage: PlayoffRules.canStart(rights: context.rights)))
            }
            .onDisappear { Task { await onChange?() } }
        }
    }
}

/// Runden som skal åpnes (en `sheet(item:)` trenger `Identifiable`).
struct PlayoffRoundRef: Identifiable, Hashable {
    let id: UUID
}

// MARK: - Start

@Observable
final class PlayoffStartModel {
    struct Candidate: Identifiable, Hashable {
        let id: UUID
        let name: String
    }

    let candidates: [Candidate]
    var selected: Set<UUID>
    var holes: [Int]
    /// Hullene på banen å velge blant: indeks → «Hull 18 · par 4».
    let holeChoices: [(index: Int, title: String)]
    let holeCount: Int
    private(set) var isWorking = false
    var error: String?

    private let client: SupabaseClient
    private let seasonID: UUID

    init(client: SupabaseClient, standings: TavlaStandings) {
        self.client = client
        seasonID = standings.seasonID
        candidates = standings.tiedForFirst.map { Candidate(id: $0, name: standings.row($0)?.name ?? "Ukjent") }
        selected = Set(standings.tiedForFirst)
        // Samme bane og antall hull som den siste runden (create_playoff_round gjør det samme).
        let template = standings.snapshots.last.map(RoundGame.init)
        holeCount = template?.holeCount ?? 18
        holes = template.map { Playoff.suggestedHoles($0.round) } ?? [17, 0, 17]
        holeChoices = (0..<(template?.holeCount ?? 18)).map { i in
            guard let game = template else { return (i, "Hull \(i + 1)") }
            return (i, "Hull \(game.holeNumber(i)) · par \(game.holes[i].par)")
        }
    }

    var canStart: Bool { selected.count >= 2 && !holes.isEmpty && !isWorking }

    func addHole() {
        guard holes.count < holeCount else { return }
        holes = PlayoffState.extended(holes, holeCount: holeCount)
    }

    func removeHole(at index: Int) {
        guard holes.count > 1, holes.indices.contains(index) else { return }
        holes.remove(at: index)
    }

    /// Lager playoffen. Gir runde-id-en.
    func start() async -> UUID? {
        guard canStart else { return nil }
        isWorking = true
        defer { isWorking = false }
        do {
            guard let competition = try await PlayoffQueries.competitionID(client: client, seasonID: seasonID) else {
                error = "Fant ikke turneringen."
                return nil
            }
            let players = candidates.map(\.id).filter(selected.contains)
            return try await PlayoffQueries.create(client: client, competitionID: competition, memberIDs: players,
                                                   holes: holes)
        } catch {
            self.error = DataError.from(error).message
            return nil
        }
    }
}

struct PlayoffStartView: View {
    @Bindable var model: PlayoffStartModel
    let started: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                ForEach(model.candidates) { c in
                    Toggle(c.name, isOn: Binding(
                        get: { model.selected.contains(c.id) },
                        set: { on in if on { model.selected.insert(c.id) } else { model.selected.remove(c.id) } }))
                }
            } header: {
                Text("Spillere")
            } footer: {
                Text("De som deler førsteplassen.")
            }
            Section {
                ForEach(Array(model.holes.enumerated()), id: \.offset) { position, hole in
                    Picker("Playoff-hull \(position + 1)", selection: Binding(
                        get: { hole },
                        set: { model.holes[position] = $0 })) {
                        ForEach(model.holeChoices, id: \.index) { choice in
                            Text(choice.title).tag(choice.index)
                        }
                    }
                }
                .onDelete { offsets in offsets.sorted(by: >).forEach(model.removeHole) }
                if model.holes.count < model.holeCount {
                    Button("Legg til hull", systemImage: "plus") { model.addHole() }
                }
            } header: {
                Text("Hullene")
            } footer: {
                Text("Spilles i denne rekkefølgen. Første hull med én beste score avgjør.")
            }
            if let error = model.error {
                Section { Text(error).foregroundStyle(Color.ddRust) }
            }
        }
        .navigationTitle("Start playoff")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Avbryt") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Start") {
                    Task { if let id = await model.start() { started(id) } }
                }
                .disabled(!model.canStart)
            }
        }
    }
}

// MARK: - Føringen

/// Playoff-runden: hullene i rekkefølge, scorene, og føringen av neste hull. Bruker samme lagring
/// som hullkortet (`ScoreSubmitting`, `save_hole`), med posisjonen som hull (`hole_index = posisjon`).
@Observable
final class PlayoffModel {
    enum LoadState: Equatable { case loading, loaded, failed(String) }

    private(set) var state: LoadState = .loading
    private(set) var playoff: PlayoffState?
    private(set) var isSaving = false
    var drafts: [UUID: Int] = [:]
    var error: String?

    private let canManageRight: Bool
    private let client: SupabaseClient
    private let roundID: UUID
    private let tied: [UUID]
    private let clubViewer: Viewer?
    private let userID: UUID?

    /// - Parameters:
    ///   - viewer: den som ser på i en klubbrunde. nil for en løs playoff (uten klubb): da gjelder `userID`.
    init(client: SupabaseClient, roundID: UUID, tied: [UUID], viewer: Viewer?, userID: UUID? = nil, canManage: Bool) {
        self.client = client
        self.roundID = roundID
        self.tied = tied
        clubViewer = viewer
        self.userID = userID
        canManageRight = canManage
    }

    /// Arrangøren (klubb), eller eieren av en løs playoff. Serveren sjekker selv.
    var canManage: Bool {
        canManageRight || (playoff?.snapshot.isLoose == true && viewer?.isOrganizer == true)
    }

    var viewer: Viewer? {
        guard let snapshot = playoff?.snapshot else { return clubViewer }
        if snapshot.isLoose, let userID { return LooseRoundRights.viewer(info: snapshot.loose, userID: userID) }
        return clubViewer
    }

    func load() async {
        do {
            guard let snapshot = try await PlayoffQueries.snapshot(client: client, roundID: roundID) else {
                state = .failed("Fant ikke playoffen.")
                return
            }
            playoff = PlayoffState(snapshot: snapshot, tied: tied)
            state = .loaded
        } catch is CancellationError {
        } catch {
            if playoff == nil { state = .failed(DataError.from(error).message) }
        }
    }

    func name(_ id: UUID) -> String { playoff?.snapshot.names[id] ?? "Ukjent" }

    /// Kan du føre for spilleren (samme regel som hullkortet, `can_score`)?
    func canScore(_ member: UUID) -> Bool {
        guard let playoff, let viewer, !playoff.isLocked else { return false }
        return RoundGame(playoff.snapshot).canScore(viewer, for: member)
    }

    func value(_ member: UUID) -> Int {
        guard let playoff, let next = playoff.nextPosition else { return 0 }
        return drafts[member] ?? playoff.strokes(member, at: next) ?? playoff.hole(at: next)?.par ?? 4
    }

    func step(_ delta: Int, member: UUID) {
        drafts[member] = StrokeInput.clamp(value(member) + delta)
    }

    var canSave: Bool {
        guard let playoff, playoff.nextPosition != nil, !isSaving else { return false }
        return playoff.remaining.contains(where: canScore)
    }

    /// Lagrer neste playoff-hull for dem som fortsatt er med (og som du kan føre for).
    func save(using submitter: (any ScoreSubmitting)?) async {
        guard let playoff, let position = playoff.nextPosition, canSave else { return }
        let entries = playoff.remaining.filter(canScore).map { HoleSubmission.Entry(memberID: $0, strokes: value($0)) }
        isSaving = true
        error = nil
        defer { isSaving = false }
        do {
            let submitter = submitter ?? DirectScoreSubmitter(client: client)
            _ = try await submitter.submit(HoleSubmission(roundID: roundID, holeIndex: position, entries: entries,
                                                          recordedAt: .now))
            drafts = [:]
            await load()
        } catch {
            self.error = "Hullet ble ikke lagret: \(DataError.from(error).message)"
        }
    }

    /// «Legg til hull» når det fortsatt står likt (`playoff_set_holes`).
    func addHole() async {
        guard let playoff, canManage else { return }
        do {
            try await PlayoffQueries.setHoles(client: client, roundID: roundID,
                                              holes: PlayoffState.extended(playoff.snapshot.round.playoffHoles ?? [],
                                                                           holeCount: playoff.snapshot.round.holeCount))
            await load()
        } catch {
            self.error = DataError.from(error).message
        }
    }

    func lock() async {
        guard canManage else { return }
        do {
            try await PlayoffQueries.lock(client: client, roundID: roundID)
            await load()
        } catch {
            self.error = DataError.from(error).message
        }
    }
}

struct PlayoffScreen: View {
    @State var model: PlayoffModel
    /// «Lukk» i et ark; ikke når skjermen er dyttet inn i en navigasjon.
    var showsClose = true
    @Environment(\.scoreSubmitter) private var submitter
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        content
            .navigationTitle("Playoff")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if showsClose {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Lukk") { dismiss() }
                    }
                }
            }
            .task { await model.load() }
            .refreshable { await model.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ContentUnavailableView("Fikk ikke hentet playoffen", systemImage: "wifi.exclamationmark",
                                   description: Text(message))
        case .loaded:
            if let playoff = model.playoff { list(playoff) }
        }
    }

    private func list(_ playoff: PlayoffState) -> some View {
        List {
            Section {
                Text(playoff.statusText(name: model.name))
                    .font(.ddBodyEmphasis)
            }
            if let next = playoff.nextPosition, let hole = playoff.hole(at: next), !playoff.isLocked {
                Section {
                    ForEach(playoff.remaining, id: \.self) { member in entryRow(member) }
                    Button("Lagre playoff-hull \(next + 1)") { Task { await model.save(using: submitter) } }
                        .disabled(!model.canSave)
                } header: {
                    Text("Playoff-hull \(next + 1) · hull \(hole.number) · par \(hole.par)")
                }
            }
            Section("Hullene") {
                ForEach(playoff.holes) { hole in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Playoff-hull \(hole.position + 1) · hull \(hole.number) · par \(hole.par)")
                            .font(.ddBodyEmphasis)
                        Text(scoreLine(playoff, position: hole.position))
                            .font(.ddCallout)
                            .foregroundStyle(Color.ddInkSecondary)
                    }
                }
            }
            if model.canManage, !playoff.isLocked {
                Section {
                    if playoff.needsMoreHoles, playoff.holes.count < playoff.snapshot.round.holeCount {
                        Button("Legg til hull", systemImage: "plus") { Task { await model.addHole() } }
                    }
                    if playoff.winner != nil {
                        Button("Lås playoffen", systemImage: "lock") { Task { await model.lock() } }
                    }
                }
            }
            if let error = model.error {
                Section { Text(error).foregroundStyle(Color.ddRust) }
            }
        }
    }

    private func entryRow(_ member: UUID) -> some View {
        HStack(spacing: 12) {
            Text(model.name(member))
                .font(.ddBody)
            Spacer(minLength: 8)
            if model.canScore(member) {
                Button { model.step(-1, member: member) } label: { Image(systemName: "minus") }
                    .buttonStyle(DDStepperButtonStyle(kind: .minus, size: 40))
                    .accessibilityLabel("Ett slag mindre")
                DDStrokeValue(value: "\(model.value(member))", confirmed: model.drafts[member] != nil, size: 24)
                Button { model.step(1, member: member) } label: { Image(systemName: "plus") }
                    .buttonStyle(DDStepperButtonStyle(kind: .plus, size: 40))
                    .accessibilityLabel("Ett slag mer")
            } else {
                Text("Venter")
                    .font(.ddCallout)
                    .foregroundStyle(Color.ddInkSecondary)
            }
        }
    }

    private func scoreLine(_ playoff: PlayoffState, position: Int) -> String {
        let parts = playoff.players.compactMap { member in
            playoff.strokes(member, at: position).map { "\(model.name(member)) \($0)" }
        }
        return parts.isEmpty ? "Ikke spilt" : parts.joined(separator: " · ")
    }
}

