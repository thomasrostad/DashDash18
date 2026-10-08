import GolfgutuCore
import Observation
import SwiftUI

/// Det «Ny turnering» trenger: konkurransene (for liga, cup og morro, og navn som er tatt), sesongene
/// i klubben (for en serie), troppen og folk du kjenner. Samme flyt fra arrangørsiden og fra lista
/// over turneringer.
@Observable
final class NewTournamentModel {
    let list: CompetitionsModel
    /// Klubbens sesonger. Tom når du ikke er arrangør i klubben (da kan du bare lage private).
    let seasons: SesongAdminModel?
    /// Kan turneringen være privat? Fra lista over turneringer, som «Ny konkurranse» før. Fra
    /// arrangørsiden er den alltid klubbens.
    let offersPrivate: Bool
    private(set) var members: [ClubMemberRow] = []
    private(set) var friends: [ProfileRow] = []
    var error: String?
    private let now: Date

    init(list: CompetitionsModel, seasons: SesongAdminModel?, offersPrivate: Bool, now: Date = .now) {
        self.list = list
        self.seasons = seasons
        self.offersPrivate = offersPrivate
        self.now = now
    }

    #if DEBUG
    /// Skjermprøve uten nett.
    init(preview list: CompetitionsModel, seasons: SesongAdminModel?, offersPrivate: Bool, members: [ClubMemberRow],
         now: Date) {
        self.list = list
        self.seasons = seasons
        self.offersPrivate = offersPrivate
        self.members = members
        self.now = now
    }
    #endif

    /// Arrangør i klubben: kan lage klubbens turneringer.
    var canCreateInClub: Bool { seasons != nil && list.canCreateInClub }

    var templates: [RulesetTemplate] {
        let all = TournamentSetup.templates(inClub: canCreateInClub)
        // Uten konkurranser (flagget av) er det bare seriene i klubben.
        return CompetitionsFeature.isActive ? all : all.filter { TournamentSetup.target($0, clubID: list.clubID) == .season }
    }

    func showsOwnerChoice(_ template: RulesetTemplate) -> Bool {
        TournamentSetup.showsOwnerChoice(template, canCreateInClub: canCreateInClub, offersPrivate: offersPrivate)
    }

    /// Utkastet for oppsettet: navneforslag, klubbens når du kan, ellers privat.
    func draft(for template: RulesetTemplate) -> TournamentDraft {
        let taken = (seasons?.seasons.map(\.name) ?? []) + list.overview.competitions.map(\.name)
        let name = TournamentSetup.suggestedName(template, taken: taken, now: now)
        return TournamentDraft(template: template, clubID: canCreateInClub ? list.clubID : nil, name: name,
                               today: EveningDates.today())
    }

    /// Blir en ny sesong startet med en gang?
    var activatesNewSeason: Bool {
        TournamentSetup.activatesNewSeason(existing: seasons?.seasons ?? [])
    }

    /// Sesongen som er i gang, når en ny blir planlagt.
    var activeSeasonName: String? {
        seasons?.seasons.first { $0.status == .active }?.name
    }

    func load() async {
        await seasons?.load()
        if CompetitionsFeature.isActive { await list.load() }
        guard let client = list.client else { return }
        if let club = list.clubID, canCreateInClub {
            members = (try? await CompetitionQueries.activeMembers(client: client, clubID: club)) ?? []
        }
        if let me = list.access.profileID {
            friends = (try? await LooseRoundQueries.friends(client: client, userID: me)) ?? []
        }
    }

    /// Krever turneringen kjøp som ikke er gjort (vis betalingsveggen)?
    func needsPurchase(_ draft: TournamentDraft, purchases: PurchaseService?) -> Bool {
        guard case .competition = draft.target else { return false }
        return list.needsPurchase(draft.competitionDraft, purchases: purchases)
    }

    /// Lager turneringen: en sesong (klubbens serie) eller en konkurranse. `true` når den er laget.
    func create(_ draft: TournamentDraft, purchases: PurchaseService?) async -> Bool {
        error = draft.issues().first
        guard error == nil else { return false }
        switch draft.target {
        case .season:
            guard let seasons else {
                error = "Bare arrangøren kan lage klubbens turneringer."
                return false
            }
            do {
                try await seasons.create(name: draft.trimmedName, rules: draft.rules, activate: activatesNewSeason)
                if CompetitionsFeature.isActive { await list.load() }
                return true
            } catch {
                self.error = error.message
                return false
            }
        case .competition:
            list.error = nil
            if await list.create(draft.competitionDraft, purchases: purchases) != nil { return true }
            error = list.error
            list.error = nil
            return false
        }
    }
}

/// «Ny turnering», steg 1: «Hvordan vil dere spille?» med oppsettene som kort. Steg 2 er
/// `NyTurneringDetailsView`. Vises i et ark med egen `NavigationStack`.
struct NyTurneringView: View {
    @State var model: NewTournamentModel
    let onDone: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DDSpacing.cardGap) {
                Text("Hvordan vil dere spille?")
                    .font(.ddTitle)
                    .foregroundStyle(Color.ddForestInk)
                    .padding(.bottom, DDSpacing.s)
                ForEach(model.templates, id: \.self) { template in
                    NavigationLink(value: template) {
                        TemplateCard(template: template)
                    }
                    .buttonStyle(.plain)
                }
                Text("Du kan tilpasse reglene i neste steg.")
                    .font(.ddCaption)
                    .foregroundStyle(Color.ddInkSecondary)
            }
            .padding(.horizontal, DDSpacing.gutter)
            .padding(.vertical, DDSpacing.l)
        }
        .navigationTitle("Ny turnering")
        .navigationBarTitleDisplayMode(.inline)
        .ddNavigationChrome()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Avbryt", action: onDone)
            }
        }
        .navigationDestination(for: RulesetTemplate.self) { template in
            NyTurneringDetailsView(model: model, draft: model.draft(for: template), onDone: onDone)
        }
        .task { await model.load() }
    }
}

/// Et oppsett i steg 1: symbol, navn og én setning.
private struct TemplateCard: View {
    let template: RulesetTemplate

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: TournamentSetup.icon(template))
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.ddForestInk)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(template.title)
                    .font(.ddBodyEmphasis)
                    .foregroundStyle(Color.ddInk)
                Text(template.summary)
                    .font(.ddCallout)
                    .foregroundStyle(Color.ddInkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.ddInkSecondary)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
        .ddCard()
        .accessibilityElement(children: .combine)
    }
}

/// «Ny turnering», steg 2: navn (forslaget er utfylt), klubb eller privat der det er et valg, periode
/// for morro i klubben, og reglene kort med «Tilpass reglene». «Lag» lager turneringen.
struct NyTurneringDetailsView: View {
    let model: NewTournamentModel
    let onDone: () -> Void
    @State private var draft: TournamentDraft
    @State private var isSaving = false
    @State private var showsPaywall = false
    @Environment(PurchaseService.self) private var purchases: PurchaseService?

    init(model: NewTournamentModel, draft: TournamentDraft, onDone: @escaping () -> Void) {
        self.model = model
        self.onDone = onDone
        _draft = State(initialValue: draft)
    }

    var body: some View {
        DDForm {
            Section {
                TextField("Navn", text: $draft.name)
                    .textInputAutocapitalization(.sentences)
            } header: {
                DDHeader("Navn")
            }
            if model.showsOwnerChoice(draft.template), let club = model.list.clubID {
                Section {
                    Picker("Hvem eier den?", selection: $draft.clubID) {
                        Text(model.list.clubName ?? "Klubben").tag(Optional(club))
                        Text("Privat").tag(UUID?.none)
                    }
                    .pickerStyle(.segmented)
                } header: {
                    DDHeader("Klubb eller privat")
                } footer: {
                    DDFooter(draft.clubID == nil
                             ? "Privat: du er eier, og bare de påmeldte ser den."
                             : "Klubbens: alle i troppen ser den, og arrangørene styrer den.")
                }
            }
            if draft.showsPeriod {
                periodSection
            }
            rulesSection
        }
        .navigationTitle(draft.template.title)
        .navigationBarTitleDisplayMode(.inline)
        .ddNavigationChrome()
        .disabled(isSaving)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Lag") { save() }
                    .disabled(!draft.issues().isEmpty || isSaving)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let issue = draft.issues().first ?? model.error {
                Label(issue, systemImage: "exclamationmark.triangle")
                    .font(.ddCallout)
                    .foregroundStyle(Color.ddRustText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .glassEffect(.regular, in: .rect(cornerRadius: DDRadius.cardLarge))
                    .padding(.horizontal, DDSpacing.s)
            }
        }
        .sheet(isPresented: $showsPaywall) {
            PaywallView(service: purchases, competitionID: nil,
                        competitionName: draft.trimmedName.isEmpty ? draft.template.title : draft.trimmedName,
                        clubID: draft.clubID)
        }
    }

    private var periodSection: some View {
        Section {
            Toggle("Har en periode", isOn: $draft.competition.hasPeriod)
            if draft.competition.hasPeriod {
                DatePicker("Fra", selection: dateBinding(\.startsOn), displayedComponents: .date)
                DatePicker("Til", selection: dateBinding(\.endsOn), displayedComponents: .date)
            }
        } header: {
            DDHeader("Periode")
        } footer: {
            DDFooter("Kvelder i perioden merkes med navnet på Kveld.")
        }
    }

    private func dateBinding(_ key: WritableKeyPath<CompetitionDraft, String>) -> Binding<Date> {
        Binding(get: { EveningDates.date(from: draft.competition[keyPath: key]) ?? .now },
                set: { draft.competition[keyPath: key] = EveningDates.dateString(from: $0) })
    }

    private var rulesSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                let kind = draft.target.kind
                let isTemplate = RulesetSummary.isTemplate(draft.rules, kind: kind)
                DDPill(RulesetSummary.badge(for: draft.rules, kind: kind), tone: isTemplate ? .lime : .sun,
                       systemImage: isTemplate ? "checkmark.seal" : "slider.horizontal.3")
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(TournamentSetup.ruleLines(draft), id: \.self) { line in
                        Label {
                            Text(line)
                        } icon: {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 5))
                                .foregroundStyle(Color.ddForestInk)
                        }
                    }
                }
                .font(.dd(.sans, size: 15, relativeTo: .callout))
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
            NavigationLink("Tilpass reglene") { customize }
        } header: {
            DDHeader("Reglene")
        } footer: {
            if let footer = rulesFooter { DDFooter(footer) }
        }
    }

    @ViewBuilder
    private var customize: some View {
        switch draft.target {
        case .season:
            RulesetCustomizeView(rules: $draft.rules, base: draft.template)
        case .competition:
            CompetitionRulesCustomizeView(draft: $draft.competition, members: model.members, friends: model.friends)
        }
    }

    /// Én linje: når serien starter, eller om typen krever kjøp.
    private var rulesFooter: String? {
        switch draft.target {
        case .season:
            if model.activatesNewSeason { return "Turneringen starter med en gang." }
            return model.activeSeasonName.map { "Blir planlagt, fordi «\($0)» er i gang. Du starter den selv." }
        case .competition(let kind):
            return CompetitionPurchase.requiresPurchase(kind) ? CompetitionPurchase.note(kind) : nil
        }
    }

    /// Liga og cup uten kjøp: betalingsveggen først. Etter kjøpet trykker du «Lag» igjen.
    private func save() {
        if model.needsPurchase(draft, purchases: purchases) {
            showsPaywall = true
            return
        }
        isSaving = true
        Task {
            defer { isSaving = false }
            if await model.create(draft, purchases: purchases) { onDone() }
        }
    }
}

/// «Tilpass reglene» for liga, cup og morro: reglene for typen og hvem som er med.
private struct CompetitionRulesCustomizeView: View {
    @Binding var draft: CompetitionDraft
    let members: [ClubMemberRow]
    let friends: [ProfileRow]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        DDForm {
            Section {
                switch draft.kind {
                case .cup:
                    Picker("Seeding", selection: $draft.cup.seeding) {
                        ForEach(CupRules.Seeding.allCases, id: \.self) { Text(CompetitionText.seeding($0)).tag($0) }
                    }
                    Picker("Likt etter siste hull", selection: $draft.cup.tie) {
                        ForEach(CupRules.Tie.allCases, id: \.self) { Text(CompetitionText.tie($0)).tag($0) }
                    }
                default:
                    Picker("Poeng per runde", selection: $draft.leagueRules.scoring) {
                        ForEach(LeagueRules.Scoring.allCases, id: \.self) { Text(CompetitionText.scoring($0)).tag($0) }
                    }
                    Toggle("Bare de beste rundene teller", isOn: Binding(
                        get: { draft.leagueRules.bestRounds != nil },
                        set: { draft.leagueRules.bestRounds = $0 ? 5 : nil }
                    ))
                    if let best = draft.leagueRules.bestRounds {
                        Stepper("Beste \(best) runder", value: Binding(
                            get: { best },
                            set: { draft.leagueRules.bestRounds = max(1, $0) }
                        ), in: 1...30)
                    }
                }
            } header: {
                DDHeader("Poeng")
            } footer: {
                DDFooter(draft.kind == .cup
                         ? "Kampene spilles som matchspill i en runde som teller."
                         : "Handicap og sidepremier følger reglene for rundene.")
            }
            Section {
                if draft.entryOptions.count > 1 {
                    Picker("Hvem står i tabellen?", selection: $draft.entry) {
                        ForEach(draft.entryOptions, id: \.self) { Text(CompetitionText.entry($0)).tag($0) }
                    }
                }
                if draft.entry == .listed {
                    NavigationLink {
                        EntrantsPickerView(draft: $draft, members: members, friends: friends)
                    } label: {
                        LabeledContent("Påmeldte", value: draft.participantsSummary)
                    }
                    Toggle("Åpen påmelding", isOn: $draft.signupOpen)
                }
            } header: {
                DDHeader("Hvem er med")
            } footer: {
                DDFooter(draft.entry == .listed && draft.signupOpen
                         ? "De som ser turneringen, kan melde seg på selv."
                         : "Bare de du velger, er med.")
            }
        }
        .navigationTitle("Tilpass reglene")
        .navigationBarTitleDisplayMode(.inline)
        .ddNavigationChrome()
        .onChange(of: draft.entry) { _, _ in draft.normalize() }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Ferdig") { dismiss() }
            }
        }
    }
}
