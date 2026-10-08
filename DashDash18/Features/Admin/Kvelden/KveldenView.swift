import SwiftUI

/// Kvelden: alt som hører til én kveld, samlet. Tid, sted og sosialkomité (Endre), påmeldingen med
/// purring, kveldens runder med «Ny runde», «Avslutt kvelden» når en runde går, og «Melding til alle».
/// Åpnes fra «Kveldene» og fra kortet på arrangørsiden.
struct KveldenView: View {
    let eventID: UUID
    @State private var terminliste: TerminlisteModel
    @State private var admin: RundeAdminModel
    @State private var actions: RoundAdminActions
    /// Av i skjermprøven, som ikke har nett.
    private let loads: Bool
    @State private var editing: EventEditItem?
    @State private var announcement: VarslerModel?

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
            .navigationTitle(event.map { EveningDates.longText($0.eventDate, capitalized: true) } ?? "Kvelden")
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
            ProgressView("Henter kvelden …")
        } else if case .failed(let text) = terminliste.state {
            ContentUnavailableView {
                Label("Fikk ikke hentet kvelden", systemImage: "wifi.exclamationmark")
            } description: {
                Text(text)
            } actions: {
                Button("Prøv igjen") { Task { await terminliste.load() } }
                    .buttonStyle(.dd(.primary))
            }
        } else {
            ContentUnavailableView("Kvelden finnes ikke lenger", systemImage: "calendar",
                                   description: Text("Den kan være slettet."))
        }
    }

    private func list(_ event: EventRow) -> some View {
        let rounds = admin.rounds(on: event.id)
        return DDList {
            Section {
                KveldenDetails(event: event, committee: terminliste.committeeNames(for: event.id))
            } header: {
                DDHeader("Tid og sted")
            }

            signupSection(event)

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
                if admin.state == .loaded, admin.allowsNewRound(event) {
                    Button {
                        actions.newRound(on: event)
                    } label: {
                        Label("Ny runde", systemImage: "plus")
                            .foregroundStyle(Color.ddForestInk)
                    }
                }
            } header: {
                DDHeader("Runder")
            } footer: {
                DDFooter("Kladder ser bare arrangørene. Én runde kan gå om gangen i klubben.")
            }

            AvsluttKveldenSection(rounds: rounds, title: admin.title) { text in
                await admin.load()
                actions.message = text
            }

            Section {
                Button {
                    announcement = VarslerModel(context: admin.clubContext)
                } label: {
                    Label("Melding til alle", systemImage: "megaphone")
                        .labelStyle(DDIconLabelStyle())
                        .foregroundStyle(Color.ddInk)
                }
            } footer: {
                DDFooter("Går til alle i klubben og står i varslene.")
            }
        }
        .disabled(actions.isBusy)
        .overlay { if actions.isBusy { ProgressView() } }
    }

    private func signupSection(_ event: EventRow) -> some View {
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
            if EveningSignup.offersNudge(eventDate: event.eventDate, today: EveningDates.today(), summary: summary) {
                NudgeSection(targets: Nudge.targets(summary)) { () async throws(DataError) -> String in
                    let text = try await terminliste.nudge(event)
                    return text
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
/// Kvelden i dag med én runde som går og én kladd (`-DDDesignScreen kvelden`).
struct KveldenSample: View {
    var body: some View {
        let admin = RundeAdminModel.sample(.liveEvening)
        KveldenView(eventID: admin.selectedEventID ?? UUID(), terminliste: .sample(from: admin), admin: admin,
                    loads: false)
    }
}
#endif
