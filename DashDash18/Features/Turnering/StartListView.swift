import Observation
import Supabase
import SwiftUI

/// Startlista for en spilledag (sql/031 `round_start_groups`, lagres med `save_start_list` i 032):
/// per runde puljen og gruppene med starttid, starthull, bås/tee og funksjonær. Gruppene er
/// båsene eller flightene fra runde-oppsettet.
@Observable
final class StartListModel {
    enum LoadState: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    struct RoundStart: Identifiable, Equatable {
        let round: RoundRow
        let title: String
        var wave: Int
        var groups: [StartGroupDraft]
        var id: UUID { round.id }
    }

    private(set) var state: LoadState = .loading
    var rounds: [RoundStart] = []
    /// Staben i turneringen spilledagen hører til, til funksjonærvalget.
    private(set) var staff: [CompetitionStaffRow] = []
    private(set) var staffNames: [UUID: String] = [:]
    private(set) var isSaving = false
    var error: String?

    let event: EventRow
    private let source: [(RoundRow, String)]
    private let memberNames: [UUID: String]
    private let client: SupabaseClient?

    init(client: SupabaseClient, event: EventRow, rounds: [(RoundRow, String)], memberNames: [UUID: String]) {
        self.client = client
        self.event = event
        source = rounds
        self.memberNames = memberNames
    }

    #if DEBUG
    init(preview event: EventRow, rounds: [RoundStart], memberNames: [UUID: String],
         staff: [CompetitionStaffRow], staffNames: [UUID: String]) {
        client = nil
        self.event = event
        source = []
        self.memberNames = memberNames
        self.rounds = rounds
        self.staff = staff
        self.staffNames = staffNames
        state = .loaded
    }
    #endif

    func name(_ memberID: UUID) -> String { memberNames[memberID] ?? "Ukjent" }

    func names(_ group: StartGroupDraft) -> String {
        StartList.namesText(group.memberIDs.map(name))
    }

    /// Funksjonærene og arrangørene i staben, etter navn.
    var scorers: [(id: UUID, name: String)] {
        StaffList.sorted(staff) { self.staffNames[$0] ?? "" }
            .map { (id: $0.profileID, name: staffNames[$0.profileID] ?? "Uten navn") }
    }

    func load() async {
        guard let client else { return }
        do {
            let ids = source.map(\.0.id)
            async let players = TournamentCoreQueries.players(client: client, roundIDs: ids)
            async let saved = TournamentCoreQueries.startGroups(client: client, roundIDs: ids)
            async let waves = TournamentCoreQueries.waves(client: client, roundIDs: ids)
            async let competition = TournamentCoreQueries.eventCompetition(client: client, eventID: event.id)
            let allPlayers = try await players
            let allSaved = try await saved
            let waveByRound = try await waves
            if let competitionID = try await competition {
                staff = (try? await TournamentCoreQueries.staff(client: client, competitionID: competitionID)) ?? []
                staffNames = (try? await TournamentCoreQueries.profileNames(client: client, ids: staff.map(\.profileID))) ?? [:]
            }
            rounds = source.map { round, title in
                RoundStart(round: round, title: title, wave: waveByRound[round.id] ?? 1,
                           groups: StartList.groups(players: allPlayers.filter { $0.roundID == round.id },
                                                    saved: allSaved.filter { $0.roundID == round.id },
                                                    venue: round.venue))
            }
            state = .loaded
        } catch is CancellationError {
        } catch {
            if case .loaded = state { return }
            state = .failed(DataError.from(error).message)
        }
    }

    func update(_ roundID: UUID, _ group: StartGroupDraft) {
        guard let r = rounds.firstIndex(where: { $0.id == roundID }),
              let g = rounds[r].groups.firstIndex(where: { $0.groupNo == group.groupNo }) else { return }
        rounds[r].groups[g] = group
    }

    func fillTimes(_ roundID: UUID, first: String, interval: Int) {
        guard let r = rounds.firstIndex(where: { $0.id == roundID }) else { return }
        rounds[r].groups = StartList.fillTimes(rounds[r].groups, first: first, intervalMinutes: interval)
    }

    func shotgun(_ roundID: UUID) {
        guard let r = rounds.firstIndex(where: { $0.id == roundID }) else { return }
        rounds[r].groups = StartList.shotgun(rounds[r].groups, holeCount: rounds[r].round.holeCount)
    }

    /// Lagrer hver runde i én transaksjon hver. Gir `true` når alle er lagret.
    func save() async -> Bool {
        let staffIDs = Set(staff.map(\.profileID))
        for r in rounds {
            if let issue = StartList.issues(r.groups, wave: r.wave, holeCount: r.round.holeCount, staffIDs: staffIDs).first {
                error = "\(r.title): \(issue)"
                return false
            }
        }
        guard let client, !isSaving else { return false }
        isSaving = true
        defer { isSaving = false }
        do {
            for r in rounds {
                try await TournamentCoreQueries.saveStartList(
                    client: client, StartList.params(roundID: r.round.id, wave: r.wave, groups: r.groups))
            }
            return true
        } catch {
            let failure = DataError.from(error)
            self.error = failure == .duplicate ? "En runde går allerede i denne puljen." : failure.message
            return false
        }
    }
}

struct StartListView: View {
    @State var model: StartListModel
    var loads = true
    @Environment(\.dismiss) private var dismiss
    @State private var editing: EditItem?
    @State private var timing: UUID?

    struct EditItem: Identifiable {
        let roundID: UUID
        let group: StartGroupDraft
        let holeCount: Int
        var id: String { "\(roundID)-\(group.groupNo)" }
    }

    var body: some View {
        content
            .navigationTitle("Startliste")
            .navigationBarTitleDisplayMode(.inline)
            .ddNavigationChrome()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lagre") {
                        Task { if await model.save() { dismiss() } }
                    }
                    .disabled(model.state != .loaded || model.isSaving || model.rounds.isEmpty)
                }
            }
            .task { if loads { await model.load() } }
            .sheet(item: $editing) { item in
                NavigationStack {
                    StartGroupSheet(group: item.group, holeCount: item.holeCount, scorers: model.scorers,
                                    names: model.names(item.group)) { group in
                        model.update(item.roundID, group)
                        editing = nil
                    }
                }
                .presentationDetents([.medium, .large])
            }
            .sheet(item: Binding(get: { timing.map(TimingItem.init) }, set: { timing = $0?.id })) { item in
                NavigationStack {
                    TeeTimesSheet { first, interval in
                        model.fillTimes(item.id, first: first, interval: interval)
                        timing = nil
                    }
                }
                .presentationDetents([.medium])
            }
            .messageAlert("Det gikk ikke", text: $model.error)
    }

    private struct TimingItem: Identifiable {
        let id: UUID
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ProgressView("Henter startlista …")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let text):
            ContentUnavailableView {
                Label("Fikk ikke hentet startlista", systemImage: "wifi.exclamationmark")
            } description: {
                Text(text)
            } actions: {
                Button("Prøv igjen") { Task { await model.load() } }
                    .buttonStyle(.dd(.primary))
            }
        case .loaded:
            if model.rounds.isEmpty {
                ContentUnavailableView("Ingen runder å sette opp", systemImage: "list.number",
                                       description: Text("Sett opp en runde først. Startlista bygger på båsene eller flightene i oppsettet."))
            } else {
                list
            }
        }
    }

    private var list: some View {
        DDList {
            ForEach($model.rounds) { $round in
                Section {
                    Stepper(value: $round.wave, in: 1...20) {
                        LabeledContent("Pulje", value: "\(round.wave)")
                    }
                    if round.groups.isEmpty {
                        Text("Ingen båser eller flighter i oppsettet. Fordel spillerne i runde-oppsettet først.")
                            .foregroundStyle(Color.ddInkSecondary)
                    }
                    ForEach(round.groups) { group in
                        Button {
                            editing = EditItem(roundID: round.id, group: group, holeCount: round.round.holeCount)
                        } label: {
                            StartGroupRowView(group: group, venue: round.round.venue, names: model.names(group),
                                              scorer: group.scorerID.map { model.staffNames[$0] ?? "Funksjonær" })
                        }
                        .buttonStyle(.plain)
                    }
                    if !round.groups.isEmpty {
                        Button("Fyll inn tee-tider", systemImage: "clock") { timing = round.id }
                        Button("Kanonstart", systemImage: "flag.2.crossed") { model.shotgun(round.id) }
                    }
                } header: {
                    DDHeader(round.title)
                }
            }
            Section {
            } footer: {
                DDFooter("Gruppene er båsene eller flightene fra runde-oppsettet. Spillerne ser gruppa si på Kveld. "
                         + "En funksjonær fører for gruppa si mens runden pågår.")
            }
        }
        .disabled(model.isSaving)
    }
}

/// Én gruppe i startlista: bås eller flight, tid og starthull, spillerne og funksjonæren.
struct StartGroupRowView: View {
    let group: StartGroupDraft
    let venue: String?
    let names: String
    let scorer: String?

    var body: some View {
        HStack(alignment: .top, spacing: DDSpacing.m) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.ddBodyEmphasis)
                    .foregroundStyle(Color.ddInk)
                Text(names)
                    .font(.ddCaption)
                    .foregroundStyle(Color.ddInkSecondary)
                if let scorer {
                    Label("Funksjonær: \(scorer)", systemImage: "pencil.and.list.clipboard")
                        .font(.ddCaption)
                        .foregroundStyle(Color.ddForestInk)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                Text(group.startsAt ?? "–")
                    .font(.ddBodyEmphasis.monospacedDigit())
                    .foregroundStyle(group.startsAt == nil ? Color.ddInkSecondary : Color.ddInk)
                Text("Hull \(group.startHole ?? 1)")
                    .font(.ddCaption)
                    .foregroundStyle(Color.ddInkSecondary)
            }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        let label = group.resourceLabel.trimmingCharacters(in: .whitespaces)
        if !label.isEmpty { return label }
        return venue == "course" ? "Flight \(group.groupNo)" : "Bås \(group.groupNo)"
    }
}

/// Endre én gruppe: starttid, starthull, bås/tee og funksjonær.
private struct StartGroupSheet: View {
    @State var group: StartGroupDraft
    let holeCount: Int
    let scorers: [(id: UUID, name: String)]
    let names: String
    let onDone: (StartGroupDraft) -> Void
    @State private var hasTime: Bool
    @State private var time: Date
    @Environment(\.dismiss) private var dismiss

    init(group: StartGroupDraft, holeCount: Int, scorers: [(id: UUID, name: String)], names: String,
         onDone: @escaping (StartGroupDraft) -> Void) {
        _group = State(initialValue: group)
        self.holeCount = holeCount
        self.scorers = scorers
        self.names = names
        self.onDone = onDone
        _hasTime = State(initialValue: group.startsAt != nil)
        _time = State(initialValue: StartGroupSheetTime.date(group.startsAt ?? "18:00"))
    }

    var body: some View {
        DDList {
            Section {
                TextField("Bås, simulator eller tee", text: $group.resourceLabel)
                Toggle("Starttid", isOn: $hasTime)
                if hasTime {
                    DatePicker("Tid", selection: $time, displayedComponents: .hourAndMinute)
                }
                Picker("Starthull", selection: Binding(get: { group.startHole ?? 1 }, set: { group.startHole = $0 })) {
                    ForEach(1...max(holeCount, 1), id: \.self) { Text("Hull \($0)").tag($0) }
                }
            } header: {
                DDHeader("Gruppe \(group.groupNo)")
            } footer: {
                DDFooter(names)
            }
            Section {
                Picker("Funksjonær", selection: $group.scorerID) {
                    Text("Ingen").tag(UUID?.none)
                    ForEach(scorers, id: \.id) { Text($0.name).tag(UUID?.some($0.id)) }
                }
            } footer: {
                DDFooter(scorers.isEmpty
                         ? "Legg til funksjonærer under «Stab» for turneringen."
                         : "Funksjonæren fører for spillerne i gruppa mens runden pågår.")
            }
        }
        .navigationTitle("Gruppe \(group.groupNo)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Avbryt") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Ferdig") {
                    var g = group
                    g.startsAt = hasTime ? StartGroupSheetTime.text(time) : nil
                    onDone(g)
                }
            }
        }
    }

}

/// Tee-tider med fast mellomrom.
private struct TeeTimesSheet: View {
    let onApply: (String, Int) -> Void
    @State private var first = StartGroupSheetTime.date("18:00")
    @State private var interval = 10
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        DDList {
            Section {
                DatePicker("Første start", selection: $first, displayedComponents: .hourAndMinute)
                Stepper(value: $interval, in: 0...30) {
                    LabeledContent("Mellomrom", value: "\(interval) min")
                }
            } footer: {
                DDFooter("Gruppene får tider i rekkefølge fra første start.")
            }
        }
        .navigationTitle("Tee-tider")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Avbryt") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Fyll inn") { onApply(StartGroupSheetTime.text(first), interval) }
            }
        }
    }
}

/// Klokkeslett ↔ dato for DatePicker.
private enum StartGroupSheetTime {
    static func date(_ text: String) -> Date {
        let m = StartList.minutes(text) ?? 18 * 60
        return Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: .now) ?? .now
    }

    static func text(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return StartList.clock((c.hour ?? 0) * 60 + (c.minute ?? 0))
    }
}

// MARK: - Min gruppe (spilleren, på Kveld)

/// Gruppa mi på spilledagen: bås eller flight, tid, starthull og hvem jeg spiller med.
@Observable
final class MyStartGroupModel {
    struct Mine: Equatable {
        let summary: String
        let mates: String?
    }

    private(set) var mine: Mine?
    private let client: SupabaseClient?
    private let clubID: UUID
    private let memberID: UUID
    private let eventID: UUID

    init(client: SupabaseClient, clubID: UUID, memberID: UUID, eventID: UUID) {
        self.client = client
        self.clubID = clubID
        self.memberID = memberID
        self.eventID = eventID
    }

    #if DEBUG
    init(preview mine: Mine) {
        client = nil
        clubID = UUID()
        memberID = UUID()
        eventID = UUID()
        self.mine = mine
    }
    #endif

    /// En feil viser ingenting (kortet er et tillegg).
    func load() async {
        guard let client else { return }
        do {
            let rounds: [RoundRow] = try await client.from("rounds")
                .select(RoundRow.columns)
                .eq("event_id", value: eventID)
                .neq("status", value: RoundStatus.draft.rawValue)
                .order("round_no")
                .execute().value
            let ids = rounds.map(\.id)
            let players = try await TournamentCoreQueries.players(client: client, roundIDs: ids)
            guard let round = rounds.first(where: { r in
                players.contains { $0.roundID == r.id && $0.memberID == memberID && $0.bayNo != nil }
            }) else { mine = nil; return }
            async let saved = TournamentCoreQueries.startGroups(client: client, roundIDs: [round.id])
            async let waves = TournamentCoreQueries.waves(client: client, roundIDs: [round.id])
            async let roster: [ClubMemberRow] = client.from("club_members")
                .select(ClubMemberRow.columns)
                .eq("club_id", value: clubID)
                .execute().value
            let mineInRound = players.filter { $0.roundID == round.id }
            guard let group = StartList.myGroup(memberID: memberID, players: mineInRound, saved: try await saved) else {
                mine = nil
                return
            }
            let names = Dictionary(try await roster.map { ($0.id, $0.displayName) }, uniquingKeysWith: { first, _ in first })
            mine = Mine(summary: StartList.summary(groupNo: group.groupNo, saved: group.saved,
                                                   wave: try await waves[round.id] ?? 1, venue: round.venue),
                        mates: StartList.matesText(group.mates.map { names[$0] ?? "Ukjent" }))
        } catch {
            // Står som sist.
        }
    }
}

struct MyStartGroupCard: View {
    @State var model: MyStartGroupModel

    var body: some View {
        Group {
            if let mine = model.mine {
                DDInfoStripe(tone: .lime) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Din gruppe")
                            .ddEyebrow()
                        Text(mine.summary)
                            .font(.ddBodyEmphasis)
                        if let mates = mine.mates {
                            Text(mates)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .task { await model.load() }
    }
}
