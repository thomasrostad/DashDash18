import SwiftUI

/// Arrangørsiden som tidslinje (fase 21), i datorekkefølge fra topp til bunn: tidligere kvelder,
/// så «nå» (kvelden som står for tur med stegrekka og én knapp for neste steg, eller «Kom i gang»
/// før sesongen er klar), så kommende kvelder. Siden åpnes rullet til «nå». Under ligger det som
/// gjøres sjelden: oppsettet (sammenfoldet), varsler og rapporter, og rundearkivet.
/// Viser én turnering: den valgte, ellers hovedturneringen. Vises bare for arrangører, fra
/// verktøylinja på Hjem og fra Deg.
struct AdminHubView: View {
    /// nil: hovedturneringen. Klar for en turneringsvelger.
    var tournamentID: UUID?
    @Environment(\.clubContext) private var context

    var body: some View {
        if let context {
            AdminHubContent(model: RundeAdminModel(context: context, tournamentID: tournamentID),
                            terminliste: TerminlisteModel(context: context, tournamentID: tournamentID))
        } else {
            ContentUnavailableView("Ingen klubb", systemImage: "slider.horizontal.3")
        }
    }
}

/// Hvor arrangørsiden står rullet når den åpnes.
enum AdminHubScroll: Hashable {
    /// Kvelden som står for tur (eller «Kom i gang»).
    case now
    /// Øverst, med de tidligere kveldene (skjermprøven `kveldene`).
    case top
    /// Oppsett, varsler og arkiv (skjermprøven `arrangorbunn`).
    case bottom
}

#if DEBUG
/// Arrangørsiden med oppdiktede kvelder (`-DDDesignScreen arrangor`, `arrangorstart`, `arrangorpagar`,
/// `arrangorferdig`, `kveldene`, `arrangorbunn`).
struct AdminHubSample: View {
    @State private var model: RundeAdminModel
    @State private var terminliste: TerminlisteModel
    let scroll: AdminHubScroll

    init(_ variant: RundeAdminModel.SampleVariant = .tonight, scroll: AdminHubScroll = .now) {
        let model = RundeAdminModel.sample(variant)
        _model = State(initialValue: model)
        _terminliste = State(initialValue: .sample(from: model))
        self.scroll = scroll
    }

    var body: some View {
        AdminHubContent(model: model, terminliste: terminliste, loads: false, scroll: scroll)
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
    @State private var showsSetup = false
    @State private var didScroll = false
    @State private var error: String?
    @State private var isBusy = false

    init(model: RundeAdminModel, terminliste: TerminlisteModel, loads: Bool = true, scroll: AdminHubScroll = .now) {
        _model = State(initialValue: model)
        _terminliste = State(initialValue: terminliste)
        _actions = State(initialValue: RoundAdminActions(model: model))
        self.loads = loads
        self.scroll = scroll
    }

    var body: some View {
        ScrollViewReader { proxy in
            DDList {
                switch model.state {
                case .loading:
                    ProgressView("Henter kveldene …")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DDSpacing.l)
                case .failed(let text):
                    failed(text)
                case .loaded:
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
            ToolbarItem(placement: .primaryAction) {
                Button("Ny kveld", systemImage: "plus") { newEvening() }
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
            "Slette kvelden?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { event in
            Button("Slett \(EveningDates.longText(event.eventDate))", role: .destructive) { delete(event) }
        } message: { _ in
            Text("Påmeldingene og sosialkomiteen for kvelden slettes også.")
        }
        .messageAlert("Det gikk ikke", text: $error)
    }

    private func reload() async {
        async let a: Void = terminliste.load()
        async let b: Void = model.load()
        _ = await (a, b)
    }

    private func failed(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: DDSpacing.m) {
            Label("Fikk ikke hentet kveldene", systemImage: "wifi.exclamationmark")
                .font(.ddBodyEmphasis)
            Text(text)
                .font(.ddCallout)
                .foregroundStyle(Color.ddInkSecondary)
            Button("Prøv igjen") { Task { await reload() } }
                .buttonStyle(.dd(.secondary))
        }
        .padding(.vertical, DDSpacing.s)
    }

    // MARK: Tidslinja

    private var today: String { EveningDates.today() }
    private static let lastPastAnchor = "sist"

    private var gettingStarted: [GettingStarted.Step] {
        GettingStarted.steps(GettingStarted.input(
            seasons: model.tournament.map { [$0] } ?? [], readyCourses: model.courses.count,
            activeMembers: model.members.count, events: model.events, today: today))
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
        if !parts.past.isEmpty {
            Section {
                ForEach(parts.past) { event in
                    eveningRow(event, referenceYear: year, isPast: true)
                        .id(event.id == parts.past.last?.id ? AnyHashable(Self.lastPastAnchor) : AnyHashable(event.id))
                }
            } header: {
                DDHeader(timelineTitle("Tidligere kvelder"))
            }
        }

        if showsGettingStarted {
            gettingStartedSection
        } else if let event = parts.focus {
            nowSection(event)
        }

        Section {
            if parts.upcoming.isEmpty {
                Text(parts.focus == nil ? "Ingen kommende kvelder." : "Ingen flere kvelder etter denne.")
                    .foregroundStyle(Color.ddInkSecondary)
            }
            ForEach(parts.upcoming) { event in
                eveningRow(event, referenceYear: year, isPast: false)
            }
            Button { newEvening() } label: {
                Label("Ny kveld", systemImage: "plus")
                    .foregroundStyle(Color.ddForestInk)
            }
            .disabled(terminliste.state != .loaded)
        } header: {
            DDHeader(timelineTitle(parts.past.isEmpty && parts.focus == nil ? "Kveldene" : "Kommende kvelder"))
        } footer: {
            if model.tournament == nil {
                DDFooter("Ingen turnering er i gang. Kvelder kan likevel legges inn, uten turnering.")
            }
        }

        let missingCommittee = (parts.upcoming + [parts.focus].compactMap { $0 })
            .filter { $0.eventDate >= today }
            .contains { (terminliste.committees[$0.id] ?? []).count < perEvening }
        if terminliste.state == .loaded && missingCommittee {
            Section {
                Stepper("Per kveld: \(perEvening)", value: $perEvening, in: 1...6)
                Button("Trekk sosialkomité", systemImage: "dice") { draw() }
                    .disabled(terminliste.members.count < perEvening)
            } header: {
                DDHeader("Sosialkomité")
            } footer: {
                DDFooter("Fyller kommende kvelder som mangler komité. De med færrest turer trekkes først.")
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
            ? Tonight.statusText(action: progress.action, rounds: own, activeTitle: nil)
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
                                                              activeTitle: model.activeRound.map(model.title)))
                }
                .buttonStyle(.plain)
                .accessibilityHint("Åpner kvelden")
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
            DDHeader(Tonight.sectionTitle(daysUntil: EveningDates.daysBetween(today, event.eventDate)))
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
            }
        } header: {
            DDHeader("Kom i gang · " + GettingStarted.progressText(steps))
        } footer: {
            DDFooter("Når alt er klart, står neste kveld her med knappen for neste steg.")
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
        // Før sesongen er klar, dekker «Kom i gang» oppsettet.
        if !showsGettingStarted {
            Section {
                DisclosureGroup(isExpanded: $showsSetup) {
                    setupRows
                } label: {
                    AdminHubRow("Oppsett", "Turneringen, troppen og banene.", systemImage: "gearshape")
                }
                .id(AdminHubScroll.bottom)
            }
        }
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
        Section {
            NavigationLink { RundeAdminView() } label: {
                AdminHubRow("Alle runder", "Nyeste først, også fra tidligere turneringer.",
                            systemImage: "archivebox")
            }
        } header: {
            DDHeader("Arkiv")
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
    }

    // MARK: Handlinger

    private func scrollToStart(_ proxy: ScrollViewProxy) {
        let parts = parts
        let target: AnyHashable? = switch scroll {
        // Den siste tidligere kvelden øverst, så «nå» står rett under med overskriften.
        case .now: parts.past.count < 2 ? nil : AnyHashable(Self.lastPastAnchor)
        case .top: nil
        case .bottom:
            AnyHashable(AdminHubScroll.bottom)
        }
        guard let target else { return }
        if scroll == .bottom { showsSetup = true }
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
            error = "Fant ingen kvelder å fylle. Er det nok medlemmer i troppen?"
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
                Text(step.item.title)
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
