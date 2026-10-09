import GolfgutuCore
import SwiftUI

/// Arrangørsiden (fase 21), egen fane for arrangører siden 09.10.2026. Fra topp til bunn: oppsettet
/// (turneringen, troppen og banene, alltid åpent), «nå» (kvelden som står for tur med stegrekka og
/// én knapp for neste steg, eller «Kom i gang» før sesongen er klar), kommende kvelder, tidligere
/// kvelder, og til slutt varsler og rapporter og rundearkivet.
/// Viser én turnering: den valgte, ellers hovedturneringen. Vises bare for arrangører.
struct AdminHubView: View {
    /// nil: hovedturneringen. Klar for en turneringsvelger.
    var tournamentID: UUID?
    @Environment(\.clubContext) private var context

    var body: some View {
        if let context {
            if TournamentCoreFeature.isActive {
                TournamentAdminHub(context: context, seasonID: tournamentID)
            } else {
                AdminHubContent(model: RundeAdminModel(context: context, tournamentID: tournamentID),
                                terminliste: TerminlisteModel(context: context, tournamentID: tournamentID))
            }
        } else {
            ContentUnavailableView("Ingen klubb", systemImage: "slider.horizontal.3")
        }
    }
}

/// Fase 23: arrangørsiden med turneringsvelger øverst (`TournamentCoreFeature`). En turnering med
/// kvelder (sesongen) får tidslinja som før; de andre får påmelding, stab og tabell. Med én
/// turnering vises ingen velger.
private struct TournamentAdminHub: View {
    let context: ClubContext
    let seasonID: UUID?
    @State private var picker: TournamentPickerModel
    /// Turneringen arrangøren har valgt i velgeren. nil: den arrangørsiden ble åpnet med.
    @State private var chosen: UUID?

    init(context: ClubContext, seasonID: UUID?) {
        self.context = context
        self.seasonID = seasonID
        _picker = State(initialValue: TournamentPickerModel(client: context.client, clubID: context.clubID))
    }

    private var selected: TournamentOption? {
        if let chosen, let option = picker.options.first(where: { $0.id == chosen }) { return option }
        return TournamentPicker.initial(picker.options, seasonID: seasonID)
    }

    var body: some View {
        let selected = selected
        let header = TournamentHeader(options: picker.options, selectedID: selected?.id,
                                      competition: picker.row(selected?.id), context: context) { chosen = $0.id }
        Group {
            if let selected, !selected.hasEvenings {
                CompetitionAdminPanel(header: header)
            } else {
                let season = chosen == nil ? seasonID : selected?.seasonID
                AdminHubContent(model: RundeAdminModel(context: context, tournamentID: season),
                                terminliste: TerminlisteModel(context: context, tournamentID: season),
                                header: header)
                    .id(chosen)
            }
        }
        .task { await picker.load() }
    }
}

/// Hvor arrangørsiden står rullet når den åpnes.
enum AdminHubScroll: Hashable {
    /// Øverst: oppsettet og kvelden som står for tur (eller «Kom i gang»).
    case now
    /// Også øverst (skjermprøven `kveldene`).
    case top
    /// Varsler, rapporter og arkiv (skjermprøven `arrangorbunn`).
    case bottom
}

#if DEBUG
/// Arrangørsiden med oppdiktede kvelder (`-DDDesignScreen arrangor`, `arrangorstart`, `arrangorpagar`,
/// `arrangorferdig`, `kveldene`, `arrangorbunn`).
struct AdminHubSample: View {
    @State private var model: RundeAdminModel
    @State private var terminliste: TerminlisteModel
    let scroll: AdminHubScroll

    /// Turneringsvelgeren (fase 23, `turneringvelger`).
    private let picker: TournamentPickerModel?

    init(_ variant: RundeAdminModel.SampleVariant = .tonight, scroll: AdminHubScroll = .now,
         picker: TournamentPickerModel? = nil) {
        let model = RundeAdminModel.sample(variant)
        _model = State(initialValue: model)
        _terminliste = State(initialValue: .sample(from: model))
        self.scroll = scroll
        self.picker = picker
    }

    var body: some View {
        AdminHubContent(model: model, terminliste: terminliste, loads: false, scroll: scroll,
                        header: picker.map { picker in
                            TournamentHeader(options: picker.options, selectedID: picker.options.first?.id,
                                             competition: picker.rows.first { $0.id == picker.options.first?.id },
                                             context: model.clubContext) { _ in }
                        })
    }
}
#endif

private struct AdminHubContent: View {
    @State private var model: RundeAdminModel
    @State private var terminliste: TerminlisteModel
    @State private var actions: RoundAdminActions
    /// Av i skjermprøven, som ikke har nett.
    private let loads: Bool
    private let scroll: AdminHubScroll
    /// «Gå til runden»: Hjem-fanen åpner runden (fase 19), også når arrangørsiden står over Hjem.
    @Environment(\.showRound) private var showRound
    @Environment(\.selectTab) private var selectTab

    @State private var openEvent: UUID?
    @State private var showsNewTournament = false
    @State private var creating: EventEditItem?
    @State private var pendingDelete: EventRow?
    @State private var drawPlan: IdentifiedPlan?
    @State private var perEvening = 2
    @State private var didScroll = false
    @State private var error: String?
    @State private var isBusy = false

    /// Turneringsvelgeren og turneringens påmelding og stab (fase 23). nil: som før.
    private let header: TournamentHeader?

    init(model: RundeAdminModel, terminliste: TerminlisteModel, loads: Bool = true, scroll: AdminHubScroll = .now,
         header: TournamentHeader? = nil) {
        _model = State(initialValue: model)
        _terminliste = State(initialValue: terminliste)
        _actions = State(initialValue: RoundAdminActions(model: model))
        self.loads = loads
        self.scroll = scroll
        self.header = header
    }

    var body: some View {
        ScrollViewReader { proxy in
            DDList {
                if let header {
                    TournamentPickerSection(header: header)
                }
                if let invite {
                    Section {
                        InvitePlayersRow(clubName: clubName, invite: invite,
                                         subtitle: ClubInvite.organizerSubtitle(
                                            activeMembers: model.state == .loaded ? model.members.count : nil))
                    }
                }
                switch model.state {
                case .loading:
                    ProgressView("Henter \(term.theMany) …")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DDSpacing.l)
                case .failed(let text):
                    failed(text)
                case .loaded:
                    setupSection
                    timeline
                    rareSections
                }
            }
            .disabled(isBusy || actions.isBusy)
            .onChange(of: model.state, initial: true) { _, state in
                guard state == .loaded, !didScroll else { return }
                didScroll = true
                scrollToStart(proxy)
            }
        }
        .navigationTitle("Arrangørsiden")
        .ddNavigationChrome()
        .toolbar {
            // Alltid synlig, også når siden åpnes rullet ned til kvelden.
            if let invite {
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: invite.shareText(clubName: clubName)) {
                        Label("Inviter spillere", systemImage: "person.badge.plus")
                    }
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Ny \(term.one)", systemImage: "plus") { newEvening() }
                    .disabled(terminliste.state != .loaded)
            }
        }
        // Også tilbake fra Kvelden: svar, runder og komité kan være endret.
        .task { if loads { await terminliste.load() } }
        .task { if loads { await model.load() } }
        .refreshable { await reload() }
        .navigationDestination(item: $openEvent) { id in
            KveldenView(eventID: id, terminliste: terminliste, admin: model, loads: loads)
        }
        .roundAdminActions(actions)
        .sheet(isPresented: $showsNewTournament, onDismiss: { Task { await reload() } }) {
            NavigationStack {
                NyTurneringView(model: NewTournamentModel(list: CompetitionsModel(context: model.clubContext),
                                                          seasons: SesongAdminModel(context: model.clubContext),
                                                          offersPrivate: false)) {
                    showsNewTournament = false
                }
            }
        }
        .sheet(item: $creating) { item in
            NavigationStack {
                EventEditor(model: terminliste, draft: item.draft) {
                    creating = nil
                    if loads { Task { await model.load() } }
                }
            }
        }
        .sheet(item: $drawPlan) { item in
            NavigationStack {
                CommitteeDrawSheet(model: terminliste, plan: item.plan, perEvening: perEvening) { drawPlan = nil }
            }
        }
        .confirmationDialog(
            "Slette \(term.the)?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { event in
            Button("Slett \(EveningDates.longText(event.eventDate))", role: .destructive) { delete(event) }
        } message: { _ in
            Text("Påmeldingene og sosialkomiteen for \(term.the) slettes også.")
        }
        .messageAlert("Det gikk ikke", text: $error)
        // Kvelden, oppsettet og knappene under bruker samme ord.
        .environment(\.dayTerm, term)
    }

    private func reload() async {
        async let a: Void = terminliste.load()
        async let b: Void = model.load()
        _ = await (a, b)
    }

    private func failed(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: DDSpacing.m) {
            Label("Fikk ikke hentet \(term.theMany)", systemImage: "wifi.exclamationmark")
                .font(.ddBodyEmphasis)
            Text(text)
                .font(.ddCallout)
                .foregroundStyle(Color.ddInkSecondary)
            Button("Prøv igjen") { Task { await reload() } }
                .buttonStyle(.dd(.secondary))
        }
        .padding(.vertical, DDSpacing.s)
    }

    // MARK: Invitasjon

    private var clubName: String { model.clubContext.membership.club.name }

    /// Lenken og koden til klubben (`clubs.join_code`). nil når klubben ikke har noen kode.
    private var invite: ClubInvite? { TroppInvite.invite(model.clubContext.membership.club.joinCode) }

    // MARK: Tidslinja

    private var today: String { EveningDates.today() }

    /// «Kveld» eller «spilledag», fra turneringens regelsett (`DayTerm`). Uten turnering: «kveld».
    private var term: DayTerm { model.tournament?.rules.day ?? .evening }

    private var gettingStarted: [GettingStarted.Step] {
        GettingStarted.steps(GettingStarted.input(
            seasons: model.tournament.map { [$0] } ?? [], readyCourses: model.courses.count,
            activeMembers: model.members.count, events: model.events, today: today, term: term))
    }

    private var showsGettingStarted: Bool { GettingStarted.isVisible(gettingStarted) }

    private var focus: EventRow? {
        Tonight.focusEvent(model.events, today: today, activeRound: model.activeRound)
    }

    private var parts: EveningTimeline.Parts {
        EveningTimeline.parts(model.events, focus: showsGettingStarted ? nil : focus, today: today)
    }

    private func progress(_ event: EventRow?) -> EveningProgress {
        let notAnswered = event.map { Nudge.targets(terminliste.signupSummary(for: $0.id)).count } ?? 0
        return Tonight.progress(event: event, rounds: model.allRounds, activeRound: model.activeRound,
                                activeComplete: model.activeComplete, notAnswered: notAnswered, today: today)
    }

    @ViewBuilder
    private var timeline: some View {
        let parts = parts
        let year = EveningDates.year(of: today)
        if showsGettingStarted {
            gettingStartedSection
        } else if let event = parts.focus {
            nowSection(event)
        }

        Section {
            if parts.upcoming.isEmpty {
                Text(parts.focus == nil ? "Ingen kommende \(term.many)." : "Ingen flere \(term.many) etter denne.")
                    .foregroundStyle(Color.ddInkSecondary)
            }
            ForEach(parts.upcoming) { event in
                eveningRow(event, referenceYear: year, isPast: false)
            }
            Button { newEvening() } label: {
                Label("Ny \(term.one)", systemImage: "plus")
                    .foregroundStyle(Color.ddForestInk)
            }
            .disabled(terminliste.state != .loaded)
        } header: {
            DDHeader(timelineTitle(parts.focus == nil ? DayTerm.capitalized(term.theMany) : "Kommende \(term.many)"))
        } footer: {
            if model.tournament == nil {
                DDFooter("Ingen turnering er i gang. \(DayTerm.capitalized(term.many)) kan likevel legges inn, uten turnering.")
            }
        }

        let missingCommittee = (parts.upcoming + [parts.focus].compactMap { $0 })
            .filter { $0.eventDate >= today }
            .contains { (terminliste.committees[$0.id] ?? []).count < perEvening }
        if terminliste.state == .loaded && missingCommittee {
            Section {
                Stepper("Per \(term.one): \(perEvening)", value: $perEvening, in: 1...6)
                Button("Trekk sosialkomité", systemImage: "dice") { draw() }
                    .disabled(terminliste.members.count < perEvening)
            } header: {
                DDHeader("Sosialkomité")
            } footer: {
                DDFooter("Fyller kommende \(term.many) som mangler komité. De med færrest turer trekkes først.")
            }
        }

        if !parts.past.isEmpty {
            Section {
                // Nyeste først, rett under kommende kvelder.
                ForEach(parts.past.reversed()) { event in
                    eveningRow(event, referenceYear: year, isPast: true)
                }
            } header: {
                DDHeader(timelineTitle("Tidligere \(term.many)"))
            }
        }
    }

    /// «Kveldene · Høst 2026».
    private func timelineTitle(_ title: String) -> String {
        model.tournament.map { "\(title) · \($0.name)" } ?? title
    }

    private func eveningRow(_ event: EventRow, referenceYear: Int?, isPast: Bool) -> some View {
        let own = model.rounds(on: event.id)
        let progress = progress(event)
        let status: String = switch progress.action {
        case .seeResult, .notPlayed: Tonight.result(own) { model.course($0.courseID)?.course.name }
        default: own.isEmpty
            ? Tonight.statusText(action: progress.action, rounds: own, activeTitle: nil, term: term)
            : EveningRounds.text(own)
        }
        return Button { openEvent = event.id } label: {
            HStack {
                EveningRowLabel(event: event, referenceYear: referenceYear, isPast: isPast,
                                committee: terminliste.committeeNames(for: event.id),
                                signups: Tonight.signupText(terminliste.signups[event.id] ?? [],
                                                            rosterCount: terminliste.members.count),
                                action: progress.action, status: status)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.ddInkSecondary)
                    .accessibilityHidden(true)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .swipeActions {
            Button("Slett", systemImage: "trash", role: .destructive) { pendingDelete = event }
        }
    }

    // MARK: Nå

    private func nowSection(_ event: EventRow) -> some View {
        let progress = progress(event)
        let own = model.rounds(on: event.id)
        let summary = terminliste.signupSummary(for: event.id)
        return Section {
            VStack(alignment: .leading, spacing: DDSpacing.l) {
                // Kortet åpner Kvelden; knappen under er en egen knapp i samme rad.
                Button { openEvent = event.id } label: {
                    EveningNowCard(event: event,
                                   signups: Tonight.signupText(terminliste.signups[event.id] ?? [],
                                                               rosterCount: terminliste.members.count),
                                   progress: progress,
                                   status: Tonight.statusText(action: progress.action, rounds: own,
                                                              activeTitle: model.activeRound.map(model.title),
                                                              term: term))
                }
                .buttonStyle(.plain)
                .accessibilityHint("Åpner \(term.the)")
                EveningNextStepButton(
                    action: progress.action, rounds: own, title: model.title,
                    nudgeNames: Nudge.targets(summary).map(\.name), isBusy: actions.isBusy,
                    nudge: { () async throws(DataError) -> String in try await terminliste.nudge(event) },
                    perform: { perform($0, event: event) },
                    onMessage: { text in
                        await reload()
                        actions.message = text
                    })
            }
            .padding(.vertical, DDSpacing.s)
        } header: {
            DDHeader(Tonight.sectionTitle(daysUntil: EveningDates.daysBetween(today, event.eventDate), term: term))
        }
    }

    private func perform(_ action: TonightAction, event: EventRow) {
        switch action {
        case .noEvening:
            newEvening()
        case .setUp:
            actions.newRound(on: event)
        case .continueDraft(let id):
            if let round = model.allRounds.first(where: { $0.id == id }) { actions.edit(round) }
        case .goToRound:
            showRound()
        case .seeResult:
            selectTab(.tavla)
        case .nudge, .closeEvening, .notPlayed:
            break  // Knappen selv tar purring og avslutning.
        }
    }

    // MARK: Kom i gang

    private var gettingStartedSection: some View {
        let steps = gettingStarted
        return Section {
            ForEach(steps) { step in
                switch step.item {
                case .season where !step.isDone:
                    linkButton(step) { showsNewTournament = true }
                case .evening:
                    if step.isDone {
                        GettingStartedRow(step: step)
                    } else {
                        linkButton(step) { newEvening() }
                    }
                default:
                    NavigationLink { destination(for: step.item) } label: {
                        GettingStartedRow(step: step)
                    }
                }
                if GettingStarted.showsInvite(after: step), let invite {
                    InvitePlayersRow(clubName: clubName, invite: invite,
                                     subtitle: "Send lenken til gjengen, så kommer de rett inn i troppen.")
                }
            }
        } header: {
            DDHeader("Kom i gang · " + GettingStarted.progressText(steps))
        } footer: {
            DDFooter("Når alt er klart, står neste \(term.one) her med knappen for neste steg.")
        }
    }

    private func linkButton(_ step: GettingStarted.Step, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                GettingStartedRow(step: step)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.ddInkSecondary)
                    .accessibilityHidden(true)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func destination(for item: GettingStarted.Item) -> some View {
        switch item {
        case .season: SesongAdminView()
        case .roster: TroppAdminView()
        case .courses: BanerAdminView()
        case .evening: EmptyView()
        }
    }

    // MARK: Sjeldent

    @ViewBuilder
    private var rareSections: some View {
        DDSection("Varsler og rapporter") {
            ForEach(ClubTools.hubRows(moderationEnabled: ModerationFeature.isEnabled), id: \.self) { row in
                switch row {
                case .notices:
                    NavigationLink { VarslerTilTroppenView() } label: {
                        AdminHubRow("Varsler til troppen", ClubTools.noticesSubtitle(pushEnabled: PushFeature.isEnabled),
                                    systemImage: "megaphone")
                    }
                case .reports:
                    NavigationLink { ClubReportsView() } label: {
                        AdminHubRow("Rapporter", "Innhold som noen har meldt fra om.",
                                    systemImage: "flag.badge.ellipsis")
                    }
                }
            }
        }
        .id(AdminHubScroll.bottom)
        Section {
            NavigationLink { RundeAdminView() } label: {
                AdminHubRow("Alle runder", "Nyeste først, også fra tidligere turneringer.",
                            systemImage: "archivebox")
            }
        } header: {
            DDHeader("Arkiv")
        }
    }

    /// Oppsettet øverst og alltid åpent. Før sesongen er klar, dekker «Kom i gang» det.
    @ViewBuilder
    private var setupSection: some View {
        if !showsGettingStarted {
            Section {
                setupRows
            } header: {
                DDHeader("Oppsett")
            }
        }
    }

    @ViewBuilder
    private var setupRows: some View {
        NavigationLink { SesongAdminView() } label: {
            AdminHubRow("Turneringen", "Hovedturneringen, reglene og alle turneringer.", systemImage: "trophy")
        }
        NavigationLink { TroppAdminView() } label: {
            AdminHubRow("Troppen", "Spillerne, handicap, roller og nye som venter på godkjenning.",
                        systemImage: "person.3")
        }
        NavigationLink { BanerAdminView() } label: {
            AdminHubRow("Banene", "Par, indeks og lengde for banene dere spiller.", systemImage: "map")
        }
        if let header, let competition = header.competition {
            TournamentSetupRows(competition: competition, context: header.context)
        }
    }

    // MARK: Handlinger

    private func scrollToStart(_ proxy: ScrollViewProxy) {
        // Oppsettet og «nå» står øverst, så siden åpnes uten å rulle.
        let target: AnyHashable? = switch scroll {
        case .now, .top: nil
        case .bottom: AnyHashable(AdminHubScroll.bottom)
        }
        guard let target else { return }
        // Etter at lista har lagt ut radene.
        Task { @MainActor in
            await Task.yield()
            proxy.scrollTo(target, anchor: .top)
        }
    }

    private func newEvening() {
        creating = EventEditItem(draft: terminliste.draft(for: nil))
    }

    private func draw() {
        let plan = terminliste.proposeCommittees(perEvening: perEvening)
        if plan.isEmpty {
            error = "Fant ingen \(term.many) å fylle. Er det nok medlemmer i troppen?"
        } else {
            drawPlan = IdentifiedPlan(plan: plan)
        }
    }

    private func delete(_ event: EventRow) {
        isBusy = true
        Task {
            defer { isBusy = false }
            do throws(DataError) {
                try await terminliste.delete(event)
                await model.load()
            } catch {
                self.error = error.message
            }
        }
    }
}

/// Et punkt i «Kom i gang»: nummer, eller ✓ når det er i orden.
private struct GettingStartedRow: View {
    let step: GettingStarted.Step

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(step.title)
                    .foregroundStyle(Color.ddInk)
                Text(step.detail)
                    .font(.ddCaption)
                    .foregroundStyle(Color.ddInkSecondary)
            }
        } icon: {
            Image(systemName: step.isDone ? "checkmark.circle.fill" : "\(step.number).circle")
                .foregroundStyle(step.isDone ? Color.ddLimeInk : Color.ddInkSecondary)
        }
        .labelStyle(DDIconLabelStyle())
        .accessibilityElement(children: .combine)
        .accessibilityValue(step.isDone ? "I orden" : "Mangler")
    }
}

/// Rad på arrangørsiden og i «Varsler til troppen»: tittel og en undertekst i klart språk.
struct AdminHubRow: View {
    let title: String
    let subtitle: String
    let systemImage: String

    init(_ title: String, _ subtitle: String, systemImage: String) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
    }

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(Color.ddInk)
                Text(subtitle)
                    .font(.ddCaption)
                    .foregroundStyle(Color.ddInkSecondary)
            }
        } icon: {
            Image(systemName: systemImage)
        }
        .labelStyle(DDIconLabelStyle())
    }
}
