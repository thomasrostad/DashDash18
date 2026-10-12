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
    /// Turneringen er laget, men noe gjenstår (kjøpet ble ikke koblet). Arket står til brukeren har
    /// lest det.
    private(set) var notice: String?
    /// Turneringsmalene (sql/049): klubbens for arrangøren, ellers dine egne. nil: 049 mangler eller
    /// ikke hentet, og malene skjules.
    private(set) var templateStore: SetupTemplateStore?
    /// Turneringsraden som ble laget (for «Lag serie» etterpå). Bare for klubbens turneringer.
    private(set) var createdCompetitionID: UUID?
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
        TournamentSetup.activatesNewSeason(existing: seasons?.seasons ?? [], mainSeasonIDs: seasons?.mainSeasonIDs ?? [])
    }

    /// Hovedturneringen som er i gang, når en ny blir planlagt.
    var activeSeasonName: String? {
        guard let seasons else { return nil }
        return (MainTournament.activeSeason(seasons.seasons, mainSeasonIDs: seasons.mainSeasonIDs)
            ?? seasons.seasons.first { $0.status == .active })?.name
    }

    func load() async {
        await seasons?.load()
        if CompetitionsFeature.isActive { await list.load() }
        guard let client = list.client else { return }
        if templateStore == nil {
            let store = SetupTemplateStore(client: client, clubID: canCreateInClub ? list.clubID : nil, kind: .tournament)
            await store.load()
            templateStore = store
        }
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

    /// Lager turneringen: en sesong (klubbens serie) eller en konkurranse. `true` når den er laget;
    /// da står eventuelt en melding i `notice`.
    func create(_ draft: TournamentDraft, purchases: PurchaseService?) async -> Bool {
        notice = nil
        error = draft.issues().first
        guard error == nil else { return false }
        switch draft.target {
        case .season:
            guard let seasons else {
                error = "Bare arrangøren kan lage klubbens turneringer."
                return false
            }
            do {
                let season = try await seasons.create(name: draft.trimmedName, rules: draft.seasonRules,
                                                      activate: activatesNewSeason)
                if draft.schedule != nil, let client = list.client {
                    createdCompetitionID = await ReuseService.competitionID(client: client, seasonID: season.id)
                }
                if CompetitionsFeature.isActive { await list.load() }
                return true
            } catch {
                self.error = error.message
                return false
            }
        case .competition:
            list.error = nil
            if let created = await list.create(draft.competitionDraft, purchases: purchases) {
                notice = Self.notice(for: created)
                if draft.clubID != nil { createdCompetitionID = created.id }
                return true
            }
            error = list.error
            list.error = nil
            return false
        }
    }
}

// MARK: Maler og serie (sql/049)

extension NewTournamentModel {
    /// Malene finnes (049 er kjørt).
    var supportsTemplates: Bool { templateStore?.isAvailable == true }

    /// Utkastet fra en lagret mal, med et ledig navn. nil når malen ikke kan leses eller ikke passer
    /// (en matchspill-serie uten klubb).
    func draft(from row: SetupTemplateRow) -> TournamentDraft? {
        guard let payload = row.decode(TournamentTemplatePayload.self),
              templates.contains(payload.template) else { return nil }
        let base = draft(for: payload.template)
        return payload.draft(name: base.name, clubID: base.clubID, today: EveningDates.today())
    }

    func saveTemplate(_ draft: TournamentDraft, name: String) async throws(DataError) {
        guard let templateStore else { throw .notAllowed }
        try await templateStore.save(name: name, payload: TournamentTemplatePayload(draft: draft))
    }

    /// Tilbys «Lag serie» etter «Lag»? En klubbturnering med fast plan.
    func offersSeries(_ draft: TournamentDraft) -> Bool {
        supportsTemplates && draft.schedule != nil && draft.clubID != nil && createdCompetitionID != nil
    }

    func createSeries(firstDate: String, plan: SeriesPlan) async throws(DataError) -> CreateSeriesResult {
        guard let client = list.client, let id = createdCompetitionID else { throw .notAllowed }
        return try await ReuseService.createSeries(client: client, competitionID: id, firstDate: firstDate, plan: plan)
    }
}

extension NewTournamentModel {
    /// Meldingen etter «Lag», eller nil når alt gikk som det skulle.
    nonisolated static func notice(for created: CompetitionsModel.Created) -> String? {
        created.creditLinked ? nil : CompetitionPurchase.creditNotLinkedNotice
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
                if let store = model.templateStore, let rows = store.templates, !rows.isEmpty {
                    savedTemplates(rows, store: store)
                }
            }
            .padding(.horizontal, DDSpacing.gutter)
            .padding(.vertical, DDSpacing.l)
        }
        .navigationTitle("Ny turnering")
        .navigationBarTitleDisplayMode(.inline)
        .ddNavigationChrome()
        .toolbar {
            DDCancelToolbarItem {
                Button("Avbryt", action: onDone)
            }
        }
        .navigationDestination(for: RulesetTemplate.self) { template in
            NyTurneringDetailsView(model: model, draft: model.draft(for: template), onDone: onDone)
        }
        .navigationDestination(for: SavedTemplateRoute.self) { route in
            if let row = model.templateStore?.templates?.first(where: { $0.id == route.id }),
               let draft = model.draft(from: row) {
                NyTurneringDetailsView(model: model, draft: draft, onDone: onDone)
            } else {
                ContentUnavailableView("Malen passer ikke her", systemImage: "doc.questionmark")
            }
        }
        .task { await model.load() }
    }

    /// «Egne maler» under oppsettene: reglene og planen fra en tidligere turnering.
    private func savedTemplates(_ rows: [SetupTemplateRow], store: SetupTemplateStore) -> some View {
        VStack(alignment: .leading, spacing: DDSpacing.cardGap) {
            HStack {
                Text("Egne maler")
                    .font(.ddBodyEmphasis)
                    .foregroundStyle(Color.ddForestInk)
                Spacer()
                NavigationLink("Endre") { TemplateListView(store: store) }
                    .font(.ddCallout)
            }
            .padding(.top, DDSpacing.l)
            ForEach(rows) { row in
                NavigationLink(value: SavedTemplateRoute(id: row.id)) {
                    SavedTemplateCard(row: row)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// En lagret mal i steg 1.
private struct SavedTemplateRoute: Hashable {
    let id: UUID
}

private struct SavedTemplateCard: View {
    let row: SetupTemplateRow

    var body: some View {
        let payload = row.decode(TournamentTemplatePayload.self)
        HStack(spacing: 14) {
            Image(systemName: "doc.on.doc")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.ddForestInk)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(row.name)
                    .font(.ddBodyEmphasis)
                    .foregroundStyle(Color.ddInk)
                if let payload {
                    Text(SavedTemplateCard.subtitle(payload))
                        .font(.ddCallout)
                        .foregroundStyle(Color.ddInkSecondary)
                }
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

    /// «Matchspill-serie · Hver torsdag kl. 18:00».
    static func subtitle(_ payload: TournamentTemplatePayload) -> String {
        var parts = [payload.template.title]
        if let plan = payload.schedule {
            parts.append(SeriesText.summary(weekday: plan.weekday, everyWeeks: plan.everyWeeks, startTime: plan.startTime))
        }
        return parts.joined(separator: " · ")
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
    @State private var showsSaveTemplate = false
    /// «Lag serie» etter «Lag», med planen fra utkastet (sql/049).
    @State private var seriesOffer: SeriesSheetItem?
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
            if draft.competition.allowsPlayWhenItSuits, case .competition = draft.target {
                TimeWindowSection(draft: $draft.competition)
            }
            if draft.showsPeriod {
                periodSection
            }
            if draft.target == .season {
                DayTermSection(term: $draft.dayTerm)
            }
            rulesSection
            if model.supportsTemplates {
                if draft.clubID != nil {
                    SchedulePlanSection(plan: $draft.schedule)
                }
                Section {
                    Button("Lagre som mal", systemImage: "square.and.arrow.down") { showsSaveTemplate = true }
                        .foregroundStyle(Color.ddForestInk)
                } footer: {
                    DDFooter("Neste gang kan du starte fra malen under «Egne maler».")
                }
            }
        }
        .saveTemplatePrompt(isPresented: $showsSaveTemplate, suggestion: draft.trimmedName) { name async throws(DataError) in
            try await model.saveTemplate(draft, name: name)
        }
        .sheet(item: $seriesOffer) { item in
            NavigationStack {
                EventSeriesSheet(plan: item.plan, taken: [],
                                 create: { (first, plan) async throws(DataError) -> CreateSeriesResult in
                                     try await model.createSeries(firstDate: first, plan: plan)
                                 },
                                 done: {
                                     seriesOffer = nil
                                     onDone()
                                 })
            }
            .environment(\.dayTerm, draft.target == .season ? draft.dayTerm : .playingDay)
            .interactiveDismissDisabled()
        }
        .navigationTitle(draft.template.title)
        .navigationBarTitleDisplayMode(.inline)
        .ddNavigationChrome()
        .disabled(isSaving || model.notice != nil)
        .toolbar {
            DDConfirmToolbarItem {
                if model.notice != nil {
                    // Turneringen er laget: ikke «Lag» en gang til.
                    Button("Ferdig", action: onDone)
                } else {
                    Button("Lag") { save() }
                        .disabled(!draft.issues().isEmpty || isSaving)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let issue = model.notice ?? draft.issues().first ?? model.error {
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
                        .labelStyle(.titleAndIcon)
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
            guard await model.create(draft, purchases: purchases), model.notice == nil else { return }
            if model.offersSeries(draft) {
                seriesOffer = SeriesSheetItem(plan: draft.schedule)
            } else {
                onDone()
            }
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
            DDConfirmToolbarItem {
                Button("Ferdig") { dismiss() }
            }
        }
    }
}
