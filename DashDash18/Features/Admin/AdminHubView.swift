import SwiftUI

/// Arrangørsiden: «Kom i gang» når noe mangler (sesong, baner, tropp, neste kveld), så neste kveld
/// med én hovedknapp, og det som gjøres sjeldnere under (sesongen, klubben, push). Overskriften sier
/// «I kveld» bare når kvelden er i dag. Vises bare for arrangører.
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

/// Runden som settes opp (pushet hurtigstart).
private struct SetupItem: Hashable {
    let id = UUID()
    let draft: RoundDraft

    static func == (lhs: SetupItem, rhs: SetupItem) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

private struct AdminHubContent: View {
    @State var model: RundeAdminModel
    @Environment(\.selectTab) private var selectTab

    @State private var setup: SetupItem?
    @State private var showsTerminliste = false
    @State private var message: String?
    @State private var error: String?
    @State private var isBusy = false

    var body: some View {
        DDList {
            if model.state == .loaded, GettingStarted.isVisible(gettingStarted) {
                gettingStartedSection
            }
            tonightSection
            DDSection("Sesongen") {
                NavigationLink { TerminlisteAdminView() } label: {
                    AdminHubRow("Terminliste", "Kveldene i sesongen: dato, tid, sted og sosialkomité.",
                                systemImage: "calendar")
                }
                NavigationLink { SesongAdminView() } label: {
                    AdminHubRow("Sesong og regler", "Antall kvelder, hva som teller, poeng, handicap og former.",
                                systemImage: "list.number")
                }
            }
            DDSection("Klubben") {
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
        .navigationDestination(isPresented: $showsTerminliste) { TerminlisteAdminView() }
        .navigationDestination(item: $setup) { item in
            RundeQuickStartView(model: model, draft: item.draft) { result in
                setup = nil
                message = result
            }
        }
        .alert("Det gikk ikke", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(error ?? "")
        }
        .alert("Ferdig", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message ?? "")
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
        case .evening: TerminlisteAdminView()
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
                    TonightCard(model: model, action: action)
                    primaryButton
                }
                .padding(.vertical, DDSpacing.s)
            }
            NavigationLink { RundeAdminView() } label: {
                AdminHubRow("Runder", "Alle kveldenes runder. Trykk en runde for å starte, avkorte, låse eller rette hull.",
                            systemImage: "flag.2.crossed")
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
                message = text
            }
        default:
            Button {
                perform(action)
            } label: {
                HStack(spacing: 8) {
                    Text(action.buttonTitle)
                    if isBusy { ProgressView() }
                }
            }
            .buttonStyle(.dd(.primary, fullWidth: true))
            .disabled(isBusy)
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
            showsTerminliste = true
        case .setUp:
            if let draft = model.newDraft() { setup = SetupItem(draft: draft) }
        case .continueDraft(let id):
            isBusy = true
            Task {
                defer { isBusy = false }
                do {
                    if let draft = try await model.draft(id: id) { setup = SetupItem(draft: draft) }
                } catch {
                    self.error = DataError.from(error).message
                }
            }
        case .goToRound:
            selectTab(.kveld)
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
                }
                if let line = timeAndPlace(event) {
                    Label(line, systemImage: "clock")
                }
                Label(Tonight.signupText(model.signups, rosterCount: model.members.count), systemImage: "person.2")
                DDPill(statusText, tone: statusTone)
            }
            .labelStyle(DDIconLabelStyle())
            .accessibilityElement(children: .combine)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("Ingen kveld i terminlista")
                    .font(.ddTitle)
                    .foregroundStyle(Color.ddForestInk)
                Text("Legg inn kveldene i sesongen først. Da kan du sette opp runden herfra.")
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

/// Rad på arrangørsiden: tittel og en undertekst i klart språk.
private struct AdminHubRow: View {
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
