import GolfgutuCore
import Observation
import SwiftUI

/// Det «Ny konkurranse» trenger: utkastet, troppen og folk du kjenner.
@Observable
final class NewCompetitionModel {
    var draft: CompetitionDraft
    private(set) var members: [ClubMemberRow] = []
    private(set) var friends: [ProfileRow] = []
    let list: CompetitionsModel

    init(list: CompetitionsModel) {
        self.list = list
        draft = CompetitionDraft(clubID: list.canCreateInClub ? list.clubID : nil, today: EveningDates.today())
    }

    #if DEBUG
    init(preview list: CompetitionsModel, draft: CompetitionDraft, members: [ClubMemberRow], friends: [ProfileRow]) {
        self.list = list
        self.draft = draft
        self.members = members
        self.friends = friends
    }
    #endif

    func load() async {
        guard let client = list.client else { return }
        if let club = list.clubID {
            members = (try? await CompetitionQueries.activeMembers(client: client, clubID: club)) ?? []
        }
        if let me = list.access.profileID {
            friends = (try? await LooseRoundQueries.friends(client: client, userID: me)) ?? []
        }
    }

    var participantsSummary: String {
        let count = draft.memberIDs.count + draft.profileIDs.count
        switch draft.entry {
        case .club: return "Hele troppen er med"
        case .open: return "Alle som spiller en runde som teller"
        case .listed:
            let you = draft.clubID == nil ? " pluss deg" : ""
            return count == 0 ? "Ingen valgt\(you)" : (count == 1 ? "1 valgt\(you)" : "\(count) valgt\(you)")
        }
    }
}

/// «Ny konkurranse»: navn, type, periode, regler, hvem som er med, påmelding og klubb eller privat.
struct NewCompetitionView: View {
    @State private var model: NewCompetitionModel
    let onDone: () -> Void

    @State private var isSaving = false

    init(model list: CompetitionsModel, onDone: @escaping () -> Void) {
        _model = State(initialValue: NewCompetitionModel(list: list))
        self.onDone = onDone
    }

    init(prepared: NewCompetitionModel, onDone: @escaping () -> Void) {
        _model = State(initialValue: prepared)
        self.onDone = onDone
    }

    private var draft: CompetitionDraft { model.draft }

    var body: some View {
        DDForm {
            basics
            ownerSection
            periodSection
            rulesSection
            entrySection
        }
        .navigationTitle("Ny konkurranse")
        .navigationBarTitleDisplayMode(.inline)
        .ddNavigationChrome()
        .disabled(isSaving)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Avbryt", action: onDone)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Lag") { save() }
                    .disabled(!draft.issues().isEmpty || isSaving)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let issue = draft.issues().first ?? model.list.error {
                Label(issue, systemImage: "exclamationmark.triangle")
                    .font(.ddCallout)
                    .foregroundStyle(Color.ddRustText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .glassEffect(.regular, in: .rect(cornerRadius: DDRadius.cardLarge))
                    .padding(.horizontal, DDSpacing.s)
            }
        }
        .task { await model.load() }
        .onChange(of: model.draft.kind) { _, _ in model.draft.normalize() }
        .onChange(of: model.draft.clubID) { _, _ in model.draft.normalize() }
        .onChange(of: model.draft.entry) { _, _ in model.draft.normalize() }
    }

    // MARK: Navn og type

    private var basics: some View {
        Section {
            TextField("Navn, f.eks. Høstcupen", text: $model.draft.name)
                .textInputAutocapitalization(.sentences)
            Picker("Type", selection: $model.draft.kind) {
                ForEach(CompetitionDraft.kinds, id: \.self) { Text(CompetitionText.kind($0)).tag($0) }
            }
            .pickerStyle(.segmented)
        } header: {
            DDHeader("Konkurransen")
        } footer: {
            DDFooter(CompetitionText.kindHelp(draft.kind))
        }
    }

    @ViewBuilder
    private var ownerSection: some View {
        if model.list.canCreateInClub, let club = model.list.clubID {
            Section {
                Picker("Hvem eier den?", selection: $model.draft.clubID) {
                    Text(model.list.clubName ?? "Klubben").tag(Optional(club))
                    Text("Privat").tag(UUID?.none)
                }
                .pickerStyle(.segmented)
            } header: {
                DDHeader("Klubb eller privat")
            } footer: {
                DDFooter(draft.clubID == nil
                         ? "Privat: du er eier og første påmeldte. Bare de påmeldte ser den."
                         : "Klubbens: alle i troppen ser den, og arrangørene styrer den.")
            }
        }
    }

    private var periodSection: some View {
        Section {
            Toggle("Har en periode", isOn: $model.draft.hasPeriod)
            if draft.hasPeriod {
                DatePicker("Fra", selection: dateBinding(\.startsOn), displayedComponents: .date)
                DatePicker("Til", selection: dateBinding(\.endsOn), displayedComponents: .date)
            }
        } header: {
            DDHeader("Periode")
        } footer: {
            DDFooter(draft.kind == .fun
                     ? "Kvelder i perioden merkes med navnet på Kveld."
                     : "Valgfritt. Rundene som teller, velger du når runden settes opp («Teller også i …»).")
        }
    }

    private func dateBinding(_ key: WritableKeyPath<CompetitionDraft, String>) -> Binding<Date> {
        Binding(get: { EveningDates.date(from: model.draft[keyPath: key]) ?? .now },
                set: { model.draft[keyPath: key] = EveningDates.dateString(from: $0) })
    }

    // MARK: Regler

    @ViewBuilder
    private var rulesSection: some View {
        Section {
            if draft.clubID != nil, model.list.main != nil {
                Picker("Regler for rundene", selection: $model.draft.rulesSource) {
                    Text("Malen").tag(CompetitionDraft.RulesSource.template)
                    Text("Som \(model.list.main?.name ?? "hovedturneringen")").tag(CompetitionDraft.RulesSource.copyMain)
                }
            }
            switch draft.kind {
            case .cup:
                Picker("Seeding", selection: $model.draft.cup.seeding) {
                    ForEach(CupRules.Seeding.allCases, id: \.self) { Text(CompetitionText.seeding($0)).tag($0) }
                }
                Picker("Likt etter siste hull", selection: $model.draft.cup.tie) {
                    ForEach(CupRules.Tie.allCases, id: \.self) { Text(CompetitionText.tie($0)).tag($0) }
                }
            default:
                Picker("Poeng per runde", selection: $model.draft.leagueRules.scoring) {
                    ForEach(LeagueRules.Scoring.allCases, id: \.self) { Text(CompetitionText.scoring($0)).tag($0) }
                }
                Toggle("Bare de beste rundene teller", isOn: Binding(
                    get: { model.draft.leagueRules.bestRounds != nil },
                    set: { model.draft.leagueRules.bestRounds = $0 ? 5 : nil }
                ))
                if let best = draft.leagueRules.bestRounds {
                    Stepper("Beste \(best) runder", value: Binding(
                        get: { best },
                        set: { model.draft.leagueRules.bestRounds = max(1, $0) }
                    ), in: 1...30)
                }
            }
        } header: {
            DDHeader("Regler")
        } footer: {
            DDFooter(rulesFooter)
        }
    }

    private var rulesFooter: String {
        switch draft.kind {
        case .cup:
            return "Kampene spilles som matchspill i en runde som teller i cupen. Spillerne fører vinneren selv, med forslag fra runden, og arrangøren kan rette."
        default:
            let r = draft.leagueRules
            let base = r.scoring == .placement
                ? "Plass 1, 2, 3 … gir \(r.placementPoints.prefix(4).map(LeagueStandings.points).joined(separator: ", ")) …"
                : "Stablefordpoengene i runden teller rett fram."
            let extra = r.participationPoints > 0 ? " Pluss \(LeagueStandings.points(r.participationPoints)) for å spille." : ""
            return base + extra + " Handicap, slag og sidepremier følger reglene for rundene."
        }
    }

    // MARK: Hvem er med

    private var entrySection: some View {
        Section {
            if draft.entryOptions.count > 1 {
                Picker("Hvem står i tabellen?", selection: $model.draft.entry) {
                    ForEach(draft.entryOptions, id: \.self) { Text(CompetitionText.entry($0)).tag($0) }
                }
            }
            if draft.entry == .listed {
                NavigationLink {
                    EntrantsPickerView(model: model)
                } label: {
                    LabeledContent("Påmeldte", value: model.participantsSummary)
                }
                Toggle("Åpen påmelding", isOn: $model.draft.signupOpen)
            }
        } header: {
            DDHeader("Hvem er med")
        } footer: {
            DDFooter(draft.entry == .listed && draft.signupOpen
                     ? "Med åpen påmelding kan de som ser konkurransen, melde seg på selv («Meld meg på»)."
                     : "Bare de du velger er med. Du kan åpne påmeldingen senere.")
        }
    }

    private func save() {
        isSaving = true
        Task {
            defer { isSaving = false }
            if await model.list.create(model.draft) != nil { onDone() }
        }
    }
}

/// Velg påmeldte: troppen (klubbkonkurranse) og folk du kjenner.
struct EntrantsPickerView: View {
    @Bindable var model: NewCompetitionModel

    var body: some View {
        DDList {
            if model.draft.clubID != nil, !model.members.isEmpty {
                Section {
                    ForEach(model.members) { m in
                        row(m.displayName, chosen: model.draft.memberIDs.contains(m.id)) {
                            toggle(&model.draft.memberIDs, m.id)
                        }
                    }
                } header: {
                    DDHeader("Troppen")
                }
            }
            if model.draft.clubID == nil {
                Section {
                    if model.friends.isEmpty {
                        Text("Ingen ennå. Folk du deler en klubb, runde eller konkurranse med, står her.")
                            .foregroundStyle(Color.ddInkSecondary)
                    }
                    ForEach(model.friends) { f in
                        let name = LooseRoundInfo.name(f.displayName)
                        row(name, chosen: model.draft.profileIDs.contains(f.id)) {
                            toggle(&model.draft.profileIDs, f.id)
                        }
                    }
                } header: {
                    DDHeader("Folk du kjenner")
                } footer: {
                    DDFooter("Du er med selv som eier.")
                }
            }
        }
        .navigationTitle("Påmeldte")
        .ddNavigationChrome()
        .navigationBarTitleDisplayMode(.inline)
    }

    private func toggle(_ set: inout Set<UUID>, _ id: UUID) {
        if set.contains(id) { set.remove(id) } else { set.insert(id) }
    }

    private func row(_ name: String, chosen: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                DDAvatar(name: name)
                Text(name).foregroundStyle(Color.ddInk)
                Spacer()
                Image(systemName: chosen ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(chosen ? Color.ddForestInk : Color.ddInkSecondary)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }
}
