import SwiftUI

/// Arrangørsiden. Øverst neste steg: «Kom i gang» når noe mangler (turnering, baner, tropp, neste kveld),
/// så neste kveld med én hovedknapp og raden «Kveldene». Overskriften sier «I kveld» bare når kvelden
/// er i dag, og trykk på kortet åpner Kvelden. Under ligger det som gjøres sjeldnere: oppsettet
/// (turneringen, troppen, banene) og varsler og rapporter. Vises bare for arrangører, fra Deg og
/// fra verktøylinja i Kveld.
struct AdminHubView: View {
    @Environment(\.clubContext) private var context

    var body: some View {
        if let context {
            AdminHubContent(model: RundeAdminModel(context: context))
        } else {
            ContentUnavailableView("Ingen klubb", systemImage: "slider.horizontal.3")
        }
    }
}

#if DEBUG
/// Arrangørsiden med en oppdiktet kveld (`-DDDesignScreen arrangor`, og `arrangorstart` for «Kom i gang»).
struct AdminHubSample: View {
    @State private var model: RundeAdminModel

    init(_ variant: RundeAdminModel.SampleVariant = .tonight) {
        _model = State(initialValue: RundeAdminModel.sample(variant))
    }

    var body: some View {
        AdminHubContent(model: model)
    }
}
#endif

private struct AdminHubContent: View {
    @State private var model: RundeAdminModel
    @State private var actions: RoundAdminActions
    /// «Gå til runden»: Hjem-fanen åpner runden (fase 19), også når arrangørsiden står over Hjem.
    @Environment(\.showRound) private var showRound

    @State private var showsKveldene = false
    @State private var showsKvelden = false
    @State private var showsNewTournament = false

    init(model: RundeAdminModel) {
        _model = State(initialValue: model)
        _actions = State(initialValue: RoundAdminActions(model: model))
    }

    var body: some View {
        DDList {
            if model.state == .loaded, GettingStarted.isVisible(gettingStarted) {
                gettingStartedSection
            }
            tonightSection
            DDSection("Oppsett") {
                NavigationLink { SesongAdminView() } label: {
                    AdminHubRow("Turneringen", "Hovedturneringen, reglene og alle turneringer.",
                                systemImage: "trophy")
                }
                NavigationLink { TroppAdminView() } label: {
                    AdminHubRow("Troppen", "Spillerne, handicap, roller og nye som venter på godkjenning.",
                                systemImage: "person.3")
                }
                NavigationLink { BanerAdminView() } label: {
                    AdminHubRow("Banene", "Par, indeks og lengde for banene dere spiller.", systemImage: "map")
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
        }
        .navigationTitle("Arrangørsiden")
        .ddNavigationChrome()
        .task { await model.load() }
        .refreshable { await model.load() }
        .navigationDestination(isPresented: $showsKveldene) { KveldeneView() }
        .navigationDestination(isPresented: $showsKvelden) {
            if let event = model.selectedEvent {
                KveldenView(eventID: event.id, terminliste: TerminlisteModel(context: model.clubContext), admin: model)
            }
        }
        .roundAdminActions(actions)
        .sheet(isPresented: $showsNewTournament, onDismiss: { Task { await model.load() } }) {
            NavigationStack {
                NyTurneringView(model: NewTournamentModel(list: CompetitionsModel(context: model.clubContext),
                                                          seasons: SesongAdminModel(context: model.clubContext),
                                                          offersPrivate: false)) {
                    showsNewTournament = false
                }
            }
        }
    }

    // MARK: Kom i gang

    private var gettingStarted: [GettingStarted.Step] {
        GettingStarted.steps(GettingStarted.input(
            seasons: model.seasons, readyCourses: model.courses.count, activeMembers: model.members.count,
            events: model.events, today: EveningDates.today()))
    }

    private var gettingStartedSection: some View {
        let steps = gettingStarted
        return Section {
            ForEach(steps) { step in
                if step.isDone {
                    GettingStartedRow(step: step)
                } else if GettingStarted.opensNewTournament(step) {
                    Button { showsNewTournament = true } label: {
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
                } else {
                    NavigationLink { destination(for: step.item) } label: {
                        GettingStartedRow(step: step)
                    }
                }
            }
        } header: {
            DDHeader("Kom i gang · " + GettingStarted.progressText(steps))
        } footer: {
            DDFooter("Når alt er på plass, kan du sette opp runden. Lista forsvinner av seg selv.")
        }
    }

    @ViewBuilder
    private func destination(for item: GettingStarted.Item) -> some View {
        switch item {
        case .season: SesongAdminView()
        case .courses: BanerAdminView()
        case .roster: TroppAdminView()
        case .evening: KveldeneView()
        }
    }

    // MARK: Neste kveld

    private var daysUntil: Int? {
        model.selectedEvent.flatMap { EveningDates.daysBetween(EveningDates.today(), $0.eventDate) }
    }

    private var action: TonightAction {
        Tonight.action(event: model.selectedEvent, rounds: model.rounds, activeRound: model.activeRound,
                       activeComplete: model.activeComplete)
    }

    private var tonightSection: some View {
        Section {
            switch model.state {
            case .loading:
                ProgressView("Henter kvelden …")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DDSpacing.l)
            case .failed(let text):
                VStack(alignment: .leading, spacing: DDSpacing.m) {
                    Label("Fikk ikke hentet kvelden", systemImage: "wifi.exclamationmark")
                        .font(.ddBodyEmphasis)
                    Text(text)
                        .font(.ddCallout)
                        .foregroundStyle(Color.ddInkSecondary)
                    Button("Prøv igjen") { Task { await model.load() } }
                        .buttonStyle(.dd(.secondary))
                }
                .padding(.vertical, DDSpacing.s)
            case .loaded:
                VStack(alignment: .leading, spacing: DDSpacing.l) {
                    if model.selectedEvent != nil {
                        // Kortet åpner Kvelden; knappen under er en egen knapp i samme rad.
                        Button { showsKvelden = true } label: {
                            TonightCard(model: model, action: action)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Åpner kvelden")
                    } else {
                        TonightCard(model: model, action: action)
                    }
                    primaryButton
                }
                .padding(.vertical, DDSpacing.s)
            }
            NavigationLink { KveldeneView() } label: {
                AdminHubRow("Kveldene", "Terminlista: påmelding, runder og sosialkomité for hver kveld.",
                            systemImage: "calendar")
            }
        } header: {
            DDHeader(Tonight.sectionTitle(daysUntil: daysUntil))
        }
    }

    @ViewBuilder
    private var primaryButton: some View {
        let action = action
        switch action {
        case .closeEvening(let id):
            AvsluttKveldenButton(rounds: roundsToClose(activeID: id), title: model.title, prominent: true) { text in
                await model.load()
                actions.message = text
            }
        default:
            Button {
                perform(action)
            } label: {
                HStack(spacing: 8) {
                    Text(action.buttonTitle)
                    if actions.isBusy { ProgressView() }
                }
            }
            .buttonStyle(.dd(.primary, fullWidth: true))
            .disabled(actions.isBusy)
        }
    }

    /// Kveldens runder, med runden som går selv om den hører til en annen kveld.
    private func roundsToClose(activeID: UUID) -> [RoundRow] {
        if model.rounds.contains(where: { $0.id == activeID }) { return model.rounds }
        return model.activeRound.map { [$0] } ?? []
    }

    private func perform(_ action: TonightAction) {
        switch action {
        case .noEvening:
            showsKveldene = true
        case .setUp:
            actions.newRound(on: model.selectedEvent)
        case .continueDraft(let id):
            actions.continueDraft(id: id)
        case .goToRound:
            showRound()
        case .closeEvening:
            break
        }
    }
}

/// Neste kveld: dato, tid og sted, hvem som kommer, og hvor langt oppsettet har kommet.
private struct TonightCard: View {
    let model: RundeAdminModel
    let action: TonightAction

    var body: some View {
        if let event = model.selectedEvent {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(EveningDates.longText(event.eventDate, capitalized: true))
                        .font(.ddTitle)
                        .foregroundStyle(Color.ddForestInk)
                    Spacer()
                    if let days = EveningDates.daysBetween(EveningDates.today(), event.eventDate), days >= 0 {
                        DDPill(EveningDates.countdownText(days: days), tone: .sun)
                            .fixedSize()
                    }
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.ddInkSecondary)
                }
                if let line = timeAndPlace(event) {
                    Label(line, systemImage: "clock")
                }
                Label(Tonight.signupText(model.signups, rosterCount: model.members.count), systemImage: "person.2")
                DDPill(statusText, tone: statusTone)
            }
            .labelStyle(DDIconLabelStyle())
            .contentShape(.rect)
            .accessibilityElement(children: .combine)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("Ingen kveld i terminlista")
                    .font(.ddTitle)
                    .foregroundStyle(Color.ddForestInk)
                Text("Legg inn neste kveld under «Kveldene». Da kan du sette opp runden herfra.")
                    .font(.ddCallout)
                    .foregroundStyle(Color.ddInkSecondary)
            }
        }
    }

    private var statusText: String {
        Tonight.statusText(action: action, rounds: model.rounds, activeTitle: model.activeRound.map(model.title))
    }

    private var statusTone: DDTone {
        switch action {
        case .goToRound, .closeEvening: .lime
        case .continueDraft: .sun
        case .setUp, .noEvening: .earth
        }
    }

    private func timeAndPlace(_ event: EventRow) -> String? {
        let parts = [EveningDates.timeText(event.startTime).map { "Kl. \($0)" }, event.venue].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// Et punkt i «Kom i gang»: ✓ når det er i orden, ellers en lenke dit det fikses.
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
            Image(systemName: step.isDone ? "checkmark.circle.fill" : "circle")
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
