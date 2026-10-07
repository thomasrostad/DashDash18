import SwiftUI

/// Arrangørsiden: «I kveld» øverst med neste kveld og én hovedknapp, og det som gjøres sjeldnere under
/// (sesongen, klubben, push). Vises bare for arrangører.
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
/// Arrangørsiden med en oppdiktet kveld (`-DDDesignScreen arrangor`).
struct AdminHubSample: View {
    @State private var model = RundeAdminModel.sample()

    var body: some View {
        AdminHubContent(model: model)
    }
}
#endif

/// Runden som settes opp i arket.
private struct SetupItem: Identifiable {
    let id = UUID()
    let draft: RoundDraft
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
            if PushFeature.isEnabled {
                DDSection("Push") {
                    NavigationLink { ClubPushSettingsView() } label: {
                        AdminHubRow("Hva blir push", "Hvilke hendelser som sendes som varsel til alle.",
                                    systemImage: "bell.badge")
                    }
                    NavigationLink { PushStatusView() } label: {
                        AdminHubRow("Hvem har push", "Hvem som får varsler på telefonen, og hvem som ikke gjør det.",
                                    systemImage: "iphone.radiowaves.left.and.right")
                    }
                }
            }
        }
        .navigationTitle("Arrangørsiden")
        .ddNavigationChrome()
        .task { await model.load() }
        .refreshable { await model.load() }
        .navigationDestination(isPresented: $showsTerminliste) { TerminlisteAdminView() }
        .sheet(item: $setup) { item in
            RoundSetupFlow(model: model, draft: item.draft) { result in
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

    // MARK: I kveld

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
                AdminHubRow("Alle runder", "Kladder, runden som går og låste runder. Avkort, lås og rett hull.",
                            systemImage: "flag.2.crossed")
            }
        } header: {
            DDHeader("I kveld")
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
