import Observation
import Supabase
import SwiftUI

/// Staben i én turnering (sql/031, rettighetene i 032): arrangører og funksjonærer. Hvilke grupper
/// en funksjonær fører for, velges i startlista for runden.
@Observable
final class StaffModel {
    enum LoadState: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    private(set) var state: LoadState = .loading
    private(set) var staff: [CompetitionStaffRow] = []
    /// Profil → navn: staben og troppen.
    private(set) var names: [UUID: String] = [:]
    /// Folk med innlogging i klubben (profil-id og navn), til «Legg til».
    private(set) var people: [(profileID: UUID, name: String)] = []
    private(set) var isWorking = false
    var error: String?

    let competition: CompetitionRow
    private let client: SupabaseClient?
    private let me: UUID?

    init(client: SupabaseClient, competition: CompetitionRow, me: UUID) {
        self.client = client
        self.competition = competition
        self.me = me
    }

    #if DEBUG
    init(preview competition: CompetitionRow, staff: [CompetitionStaffRow], names: [UUID: String],
         people: [(profileID: UUID, name: String)]) {
        client = nil
        me = nil
        self.competition = competition
        self.staff = staff
        self.names = names
        self.people = people
        state = .loaded
    }
    #endif

    var sorted: [CompetitionStaffRow] { StaffList.sorted(staff) { self.name($0) } }

    var candidates: [(profileID: UUID, name: String)] {
        StaffList.candidates(people.filter { $0.profileID != me }, staff: staff)
    }

    func name(_ profileID: UUID) -> String { names[profileID] ?? "Uten navn" }

    func load() async {
        guard let client else { return }
        do {
            let rows = try await TournamentCoreQueries.staff(client: client, competitionID: competition.id)
            var roster: [ClubMemberRow] = []
            if let clubID = competition.clubID {
                roster = try await client.from("club_members")
                    .select(ClubMemberRow.columns)
                    .eq("club_id", value: clubID)
                    .eq("status", value: MemberStatus.active.rawValue)
                    .execute().value
            }
            let fromRoster = roster.compactMap { m in m.userID.map { (profileID: $0, name: m.displayName) } }
            var names = Dictionary(fromRoster.map { ($0.profileID, $0.name) }, uniquingKeysWith: { first, _ in first })
            let unknown = rows.map(\.profileID).filter { names[$0] == nil }
            if let extra = try? await TournamentCoreQueries.profileNames(client: client, ids: unknown) {
                names.merge(extra) { first, _ in first }
            }
            staff = rows
            self.names = names
            people = fromRoster
            state = .loaded
        } catch is CancellationError {
        } catch {
            if case .loaded = state { return }
            state = .failed(DataError.from(error).message)
        }
    }

    func add(_ profileID: UUID, role: StaffRole) async {
        await run { client in
            try await TournamentCoreQueries.addStaff(client: client, competitionID: self.competition.id,
                                                     profileID: profileID, role: role)
        }
    }

    func setRole(_ row: CompetitionStaffRow, _ role: StaffRole) async {
        await run { client in
            try await TournamentCoreQueries.setStaffRole(client: client, competitionID: self.competition.id,
                                                         profileID: row.profileID, role: role)
        }
    }

    func remove(_ row: CompetitionStaffRow) async {
        await run { client in
            try await TournamentCoreQueries.removeStaff(client: client, competitionID: self.competition.id,
                                                        profileID: row.profileID)
        }
    }

    private func run(_ action: (SupabaseClient) async throws -> Void) async {
        guard let client, !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await action(client)
            await load()
        } catch {
            self.error = DataError.from(error).message
        }
    }
}

struct StaffView: View {
    @State var model: StaffModel
    var loads = true
    @State private var adding = false

    var body: some View {
        content
            .navigationTitle("Stab")
            .navigationBarTitleDisplayMode(.inline)
            .ddNavigationChrome()
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Legg til", systemImage: "plus") { adding = true }
                        .disabled(model.state != .loaded || model.candidates.isEmpty)
                }
            }
            .task { if loads { await model.load() } }
            .refreshable { await model.load() }
            .sheet(isPresented: $adding) {
                NavigationStack {
                    AddStaffSheet(candidates: model.candidates) { profileID, role in
                        adding = false
                        Task { await model.add(profileID, role: role) }
                    }
                }
                .presentationDetents([.medium, .large])
            }
            .messageAlert("Det gikk ikke", text: $model.error)
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ProgressView("Henter staben …")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let text):
            ContentUnavailableView {
                Label("Fikk ikke hentet staben", systemImage: "wifi.exclamationmark")
            } description: {
                Text(text)
            } actions: {
                Button("Prøv igjen") { Task { await model.load() } }
                    .buttonStyle(.dd(.primary))
            }
        case .loaded:
            list
        }
    }

    private var list: some View {
        DDList {
            ForEach(StaffRole.allCases, id: \.self) { role in
                let rows = model.sorted.filter { $0.role == role }
                Section {
                    if rows.isEmpty {
                        Text(role == .organizer ? "Ingen ekstra arrangører." : "Ingen funksjonærer.")
                            .foregroundStyle(Color.ddInkSecondary)
                    }
                    ForEach(rows) { row in
                        StaffRowView(name: model.name(row.profileID), role: row.role)
                            .swipeActions {
                                Button("Ta ut", systemImage: "person.badge.minus", role: .destructive) {
                                    Task { await model.remove(row) }
                                }
                            }
                            .contextMenu {
                                ForEach(StaffRole.allCases, id: \.self) { other in
                                    if other != row.role {
                                        Button("Gjør til \(other.title.lowercased())") {
                                            Task { await model.setRole(row, other) }
                                        }
                                    }
                                }
                                Button("Ta ut av staben", role: .destructive) { Task { await model.remove(row) } }
                            }
                    }
                } header: {
                    DDHeader(role == .organizer ? "Arrangører" : "Funksjonærer")
                } footer: {
                    DDFooter(role == .organizer
                             ? "\(role.help) Klubbens arrangører styrer alle klubbens turneringer i tillegg."
                             : "\(role.help) Gruppene velger du i startlista for runden.")
                }
            }
        }
        .disabled(model.isWorking)
    }
}

private struct StaffRowView: View {
    let name: String
    let role: StaffRole

    var body: some View {
        Label {
            Text(name)
                .foregroundStyle(Color.ddInk)
        } icon: {
            Image(systemName: role == .organizer ? "person.badge.key" : "pencil.and.list.clipboard")
        }
        .labelStyle(DDIconLabelStyle())
        .accessibilityValue(role.title)
    }
}

/// Velg person og rolle.
private struct AddStaffSheet: View {
    let candidates: [(profileID: UUID, name: String)]
    let onAdd: (UUID, StaffRole) -> Void
    @State private var role: StaffRole = .scorer
    @State private var picked: UUID?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        DDList {
            Section {
                Picker("Rolle", selection: $role) {
                    ForEach(StaffRole.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            } footer: {
                DDFooter(role.help)
            }
            Section {
                ForEach(candidates, id: \.profileID) { person in
                    Button {
                        picked = person.profileID
                    } label: {
                        HStack {
                            Text(person.name)
                                .foregroundStyle(Color.ddInk)
                            Spacer()
                            if picked == person.profileID {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.ddForestInk)
                            }
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                DDHeader("Fra troppen")
            } footer: {
                DDFooter("Bare folk som har logget inn i appen, kan stå i staben.")
            }
        }
        .navigationTitle("Legg til i staben")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Avbryt") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Legg til") { if let picked { onAdd(picked, role) } }
                    .disabled(picked == nil)
            }
        }
    }
}
