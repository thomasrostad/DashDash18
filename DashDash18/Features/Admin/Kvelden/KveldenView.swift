import GolfgutuCore
import SwiftUI

/// Kvelden: alt som hører til én kveld, i kveldens rekkefølge (fase 21). Øverst stegrekka og knappen
/// for neste steg, så «Før kvelden» (tid, sted, sosialkomité, påmelding og purring), «Under kvelden»
/// (rundene) og «Etter kvelden» (avslutt kvelden, resultatet og melding til alle).
/// Åpnes fra tidslinja og kortet på arrangørsiden, og fra arrangørknappen på Hjem.
struct KveldenView: View {
    let eventID: UUID
    @State private var terminliste: TerminlisteModel
    @State private var admin: RundeAdminModel
    @State private var actions: RoundAdminActions
    /// Av i skjermprøven, som ikke har nett.
    private let loads: Bool
    @State private var editing: EventEditItem?
    @State private var announcement: VarslerModel?
    @Environment(\.showRound) private var showRound
    @Environment(\.dayTerm) private var dayTerm
    @Environment(\.selectTab) private var selectTab

    init(eventID: UUID, terminliste: TerminlisteModel, admin: RundeAdminModel, loads: Bool = true) {
        self.eventID = eventID
        _terminliste = State(initialValue: terminliste)
        _admin = State(initialValue: admin)
        _actions = State(initialValue: RoundAdminActions(model: admin))
        self.loads = loads
    }

    private var event: EventRow? {
        terminliste.events.first { $0.id == eventID } ?? admin.events.first { $0.id == eventID }
    }

    var body: some View {
        content
            .navigationTitle(event.map { EveningDates.longText($0.eventDate, capitalized: true) } ?? DayTerm.capitalized(dayTerm.the))
            .navigationBarTitleDisplayMode(.inline)
            .ddNavigationChrome()
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Endre") {
                        if let event { editing = EventEditItem(draft: terminliste.draft(for: event)) }
                    }
                    .disabled(event == nil || terminliste.state != .loaded)
                }
            }
            .task { if loads && terminliste.state != .loaded { await terminliste.load() } }
            .task { if loads && admin.state != .loaded { await admin.load() } }
            .refreshable {
                await terminliste.load()
                await admin.load()
            }
            .sheet(item: $editing) { item in
                NavigationStack {
                    EventEditor(model: terminliste, draft: item.draft) {
                        editing = nil
                        // Dato og sted vises også på arrangørsiden.
                        if loads { Task { await admin.load() } }
                    }
                }
            }
            .sheet(isPresented: Binding(get: { announcement != nil }, set: { if !$0 { announcement = nil } })) {
                if let announcement { AnnouncementSheet(model: announcement) }
            }
            .roundAdminActions(actions)
    }

    @ViewBuilder
    private var content: some View {
        if let event {
            list(event)
        } else if terminliste.state == .loading || admin.state == .loading {
            ProgressView("Henter \(dayTerm.the) …")
        } else if case .failed(let text) = terminliste.state {
            ContentUnavailableView {
                Label("Fikk ikke hentet \(dayTerm.the)", systemImage: "wifi.exclamationmark")
            } description: {
                Text(text)
            } actions: {
                Button("Prøv igjen") { Task { await terminliste.load() } }
                    .buttonStyle(.dd(.primary))
            }
        } else {
            ContentUnavailableView("\(DayTerm.capitalized(dayTerm.the)) finnes ikke lenger", systemImage: "calendar",
                                   description: Text("Den kan være slettet."))
        }
    }

    private var today: String { EveningDates.today() }

    /// Siste rad, for skjermprøven rullet ned.
    static let afterAnchor = "etter"

    private func progress(_ event: EventRow) -> EveningProgress {
        Tonight.progress(event: event, rounds: admin.allRounds, activeRound: admin.activeRound,
                         activeComplete: admin.activeComplete,
                         notAnswered: Nudge.targets(terminliste.signupSummary(for: event.id)).count, today: today)
    }

    /// Seksjonsoverskriften, med «nå» på delen kvelden er i.
    private func header(_ part: EveningPart, current: EveningPart?) -> some View {
        DDHeader(part == current ? "\(part.title(dayTerm)) · nå" : part.title(dayTerm))
    }

    private func list(_ event: EventRow) -> some View {
        let rounds = admin.rounds(on: event.id)
        let progress = progress(event)
        let current = EveningPart.current(progress.stage)
        let summary = terminliste.signupSummary(for: event.id)
        return DDList {
            // Stegrekka og neste steg, som øverst på arrangørsiden.
            Section {
                VStack(alignment: .leading, spacing: DDSpacing.l) {
                    EveningStepsBar(progress: progress)
                    DDPill(Tonight.statusText(action: progress.action, rounds: rounds,
                                              activeTitle: admin.activeRound.map(admin.title), term: dayTerm),
                           tone: EveningStatusTone.tone(progress.action))
                    if admin.state == .loaded {
                        EveningNextStepButton(
                            action: progress.action, rounds: roundsToClose(rounds), title: admin.title,
                            nudgeNames: Nudge.targets(summary).map(\.name), isBusy: actions.isBusy,
                            nudge: { () async throws(DataError) -> String in try await terminliste.nudge(event) },
                            perform: { perform($0, event: event) },
                            onMessage: { text in
                                if loads { await admin.load(); await terminliste.load() }
                                actions.message = text
                            })
                    }
                }
                .padding(.vertical, DDSpacing.s)
            }

            // Før: tid og sted, sosialkomité, påmelding og purring.
            Section {
                KveldenDetails(event: event, committee: terminliste.committeeNames(for: event.id))
            } header: {
                header(.before, current: current)
            }
            signupSection(event, hidesNudge: progress.action == .nudge(Nudge.targets(summary).count))

            // Under: rundene.
            Section {
                if admin.state != .loaded {
                    ProgressView().frame(maxWidth: .infinity)
                } else if rounds.isEmpty {
                    Text("Ingen runder ennå.")
                        .foregroundStyle(Color.ddInkSecondary)
                }
                ForEach(rounds) { round in
                    RoundAdminRow(round: round, actions: actions)
                }
                if TournamentCoreFeature.isActive, admin.state == .loaded, rounds.contains(where: { $0.status != .locked }) {
                    // Fase 23 (sql/032): tid, starthull, bås og funksjonær per gruppe.
                    NavigationLink {
                        StartListView(model: startListModel(event, rounds: rounds))
                    } label: {
                        Label("Startliste", systemImage: "list.number")
                            .labelStyle(DDIconLabelStyle())
                            .foregroundStyle(Color.ddInk)
                    }
                }
                if admin.state == .loaded, admin.allowsNewRound(event), progress.action != .setUp {
                    Button {
                        actions.newRound(on: event)
                    } label: {
                        Label(rounds.isEmpty ? "Sett opp runden" : "Sett opp en runde til", systemImage: "plus")
                            .foregroundStyle(Color.ddForestInk)
                    }
                }
            } header: {
                header(.during, current: current)
            } footer: {
                DDFooter("Kladder ser bare arrangørene. Én runde kan gå om gangen i klubben.")
            }

            // Etter: avslutt kvelden, resultatet og melding til alle.
            Section {
                if case .closeEvening = progress.action {
                    EmptyView()
                } else if rounds.contains(where: { $0.status == .active }) {
                    AvsluttKveldenButton(rounds: rounds, title: admin.title, prominent: false) { text in
                        if loads { await admin.load() }
                        actions.message = text
                    }
                } else if !rounds.contains(where: { $0.status == .locked }) {
                    Text("Når rundene er spilt, avslutter du \(dayTerm.the) her.")
                        .foregroundStyle(Color.ddInkSecondary)
                }
                if rounds.contains(where: { $0.status == .locked }), progress.action != .seeResult {
                    Button {
                        selectTab(.tavla)
                    } label: {
                        Label("Se resultatet", systemImage: "trophy")
                            .labelStyle(DDIconLabelStyle())
                            .foregroundStyle(Color.ddInk)
                    }
                }
                Button {
                    announcement = VarslerModel(context: admin.clubContext)
                } label: {
                    Label("Melding til alle", systemImage: "megaphone")
                        .labelStyle(DDIconLabelStyle())
                        .foregroundStyle(Color.ddInk)
                }
                .id(Self.afterAnchor)
            } header: {
                header(.after, current: current)
            } footer: {
                DDFooter("Avslutt \(dayTerm.the) låser rundene som går. Melding til alle går til alle i klubben og står i varslene.")
            }
        }
        .disabled(actions.isBusy)
        .overlay { if actions.isBusy { ProgressView() } }
    }

    /// Startlista for rundene som ikke er låst.
    private func startListModel(_ event: EventRow, rounds: [RoundRow]) -> StartListModel {
        StartListModel(client: admin.clubContext.client, event: event,
                       rounds: rounds.filter { $0.status != .locked }.map { ($0, admin.title($0)) },
                       memberNames: Dictionary(admin.members.map { ($0.id, $0.displayName) },
                                               uniquingKeysWith: { first, _ in first }))
    }

    /// Kveldens runder, med runden som går selv om den hører til en annen kveld.
    private func roundsToClose(_ rounds: [RoundRow]) -> [RoundRow] {
        guard let active = admin.activeRound, !rounds.contains(where: { $0.id == active.id }) else { return rounds }
        return rounds + [active]
    }

    private func perform(_ action: TonightAction, event: EventRow) {
        switch action {
        case .noEvening, .nudge, .closeEvening, .notPlayed:
            break  // Knappen selv tar purring og avslutning.
        case .setUp:
            actions.newRound(on: event)
        case .continueDraft(let id):
            if let round = admin.allRounds.first(where: { $0.id == id }) { actions.edit(round) }
        case .goToRound:
            showRound()
        case .seeResult:
            selectTab(.tavla)
        }
    }

    private func signupSection(_ event: EventRow, hidesNudge: Bool) -> some View {
        let summary = terminliste.signupSummary(for: event.id)
        return Section {
            Text(Tonight.signupText(terminliste.signups[event.id] ?? [], rosterCount: terminliste.members.count))
                .font(.ddBodyEmphasis)
                .foregroundStyle(Color.ddInk)
            ForEach(EveningSignup.groups(summary), id: \.title) { group in
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(group.title) (\(group.names.count))")
                        .foregroundStyle(Color.ddInk)
                    Text(NorwegianList.join(group.names))
                        .font(.ddCaption)
                        .foregroundStyle(Color.ddInkSecondary)
                }
            }
            if !hidesNudge,
               EveningSignup.offersNudge(eventDate: event.eventDate, today: EveningDates.today(), summary: summary) {
                NudgeSection(targets: Nudge.targets(summary)) { () async throws(DataError) -> String in
                    try await terminliste.nudge(event)
                }
            }
        } header: {
            DDHeader("Påmelding")
        }
    }
}

/// Tid og sted, notat og sosialkomité, med nedtelling for en kommende kveld.
private struct KveldenDetails: View {
    let event: EventRow
    let committee: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label(EveningDates.timeText(event.startTime).map { "Kl. \($0)" } ?? "Klokkeslett ikke satt",
                      systemImage: "clock")
                Spacer()
                if let days = EveningDates.daysBetween(EveningDates.today(), event.eventDate), days >= 0 {
                    DDPill(EveningDates.countdownText(days: days), tone: .sun)
                        .fixedSize()
                }
            }
            Label(event.venue ?? "Sted ikke satt", systemImage: "mappin.and.ellipse")
            Label(committee.isEmpty ? "Ingen sosialkomité" : "Sosialkomité: \(NorwegianList.join(committee))",
                  systemImage: "person.2")
            if let note = event.note {
                Label(note, systemImage: "text.alignleft")
            }
        }
        .labelStyle(DDIconLabelStyle())
        .foregroundStyle(Color.ddInk)
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
/// Kvelden i dag med én runde som går og én kladd (`-DDDesignScreen kvelden`, rullet ned: `kveldenbunn`).
struct KveldenSample: View {
    var scrolledDown = false

    var body: some View {
        let admin = RundeAdminModel.sample(.liveEvening)
        ScrollViewReader { proxy in
            KveldenView(eventID: admin.selectedEventID ?? UUID(), terminliste: .sample(from: admin), admin: admin,
                        loads: false)
                .task {
                    guard scrolledDown else { return }
                    try? await Task.sleep(for: .milliseconds(300))
                    proxy.scrollTo(KveldenView.afterAnchor, anchor: .bottom)
                }
        }
    }
}
#endif
