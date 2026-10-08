import SwiftUI

/// Kveldene: terminlista for arrangøren. Kommende kvelder øverst, tidligere bak en bryter, med
/// påmeldte og hvor langt rundene har kommet. Trykk en kveld for å åpne Kvelden, der tid og sted,
/// påmelding, runder og «Avslutt kvelden» ligger. «Alle runder» nederst er arkivet.
struct KveldeneView: View {
    @Environment(\.clubContext) private var context

    var body: some View {
        if let context {
            KveldeneContent(terminliste: TerminlisteModel(context: context), admin: RundeAdminModel(context: context))
        } else {
            ContentUnavailableView("Ingen klubb", systemImage: "calendar")
        }
    }
}

#if DEBUG
/// Kveldene med oppdiktede data (`-DDDesignScreen kveldene`).
struct KveldeneSample: View {
    var body: some View {
        let admin = RundeAdminModel.sample(.liveEvening)
        KveldeneContent(terminliste: .sample(from: admin), admin: admin, loads: false)
    }
}
#endif

private struct KveldeneContent: View {
    @State private var terminliste: TerminlisteModel
    @State private var admin: RundeAdminModel
    /// Av i skjermprøven, som ikke har nett.
    private let loads: Bool
    @State private var creating: EventEditItem?
    @State private var showPast = false
    @State private var pendingDelete: EventRow?
    @State private var drawPlan: IdentifiedPlan?
    @State private var perEvening = 2
    @State private var error: String?
    @State private var isBusy = false

    init(terminliste: TerminlisteModel, admin: RundeAdminModel, loads: Bool = true) {
        _terminliste = State(initialValue: terminliste)
        _admin = State(initialValue: admin)
        self.loads = loads
    }

    var body: some View {
        content
            .navigationTitle("Kveldene")
            .ddNavigationChrome()
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Ny kveld", systemImage: "plus") {
                        creating = EventEditItem(draft: terminliste.draft(for: nil))
                    }
                    .disabled(terminliste.state != .loaded)
                }
            }
            // Også tilbake fra Kvelden: svar, runder og komité kan være endret.
            .task { if loads { await terminliste.load() } }
            .task { if loads { await admin.load() } }
            .refreshable {
                await terminliste.load()
                await admin.load()
            }
            .sheet(item: $creating) { item in
                NavigationStack {
                    EventEditor(model: terminliste, draft: item.draft) { creating = nil }
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
                Button("Slett \(EveningDates.longText(event.eventDate))", role: .destructive) {
                    delete(event)
                }
            } message: { _ in
                Text("Påmeldingene og sosialkomiteen for kvelden slettes også.")
            }
            .messageAlert("Det gikk ikke", text: $error)
    }

    @ViewBuilder
    private var content: some View {
        switch terminliste.state {
        case .loading:
            ProgressView("Henter kveldene …")
        case .failed(let message):
            ContentUnavailableView {
                Label("Fikk ikke hentet kveldene", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Prøv igjen") { Task { await terminliste.load() } }
                    .buttonStyle(.dd(.primary))
            }
        case .loaded:
            list
        }
    }

    private var list: some View {
        let today = EveningDates.today()
        let (upcoming, past) = Terminliste.split(terminliste.events, today: today)
        let year = EveningDates.year(of: today)
        let missingCommittee = upcoming.contains { (terminliste.committees[$0.id] ?? []).count < perEvening }
        return DDList {
            Section {
                if let season = terminliste.activeSeason {
                    LabeledContent("Turnering", value: season.name)
                } else {
                    Label {
                        Text("Ingen aktiv turnering. Lag en under «Turneringen». Kvelder kan likevel legges inn, uten turnering.")
                    } icon: {
                        Image(systemName: "info.circle")
                    }
                    .foregroundStyle(Color.ddInkSecondary)
                }
            }

            DDSection("Kommende") {
                if upcoming.isEmpty {
                    Text("Ingen kvelder satt opp. Trykk + for å legge inn en.")
                        .foregroundStyle(Color.ddInkSecondary)
                }
                ForEach(upcoming) { event in
                    row(event, referenceYear: year, isUpcoming: true)
                }
            }

            if !upcoming.isEmpty && missingCommittee {
                Section {
                    Stepper("Per kveld: \(perEvening)", value: $perEvening, in: 1...6)
                    Button("Trekk sosialkomité", systemImage: "dice") { draw() }
                        .disabled(terminliste.members.count < perEvening)
                } footer: {
                    DDFooter("Fyller kommende kvelder som mangler komité. De med færrest turer trekkes først. Kvelder som har komité, røres ikke.")
                }
            }

            if !past.isEmpty {
                Section {
                    Toggle("Vis tidligere (\(past.count))", isOn: $showPast.animation())
                    if showPast {
                        ForEach(past) { event in
                            row(event, referenceYear: year, isUpcoming: false)
                        }
                    }
                }
            }

            Section {
                NavigationLink { RundeAdminView() } label: {
                    Label("Alle runder", systemImage: "flag.2.crossed")
                        .labelStyle(DDIconLabelStyle())
                }
            } footer: {
                DDFooter("Alle rundene klubben har spilt, også fra tidligere turneringer.")
            }
        }
        .disabled(isBusy)
    }

    private func row(_ event: EventRow, referenceYear: Int?, isUpcoming: Bool) -> some View {
        let rounds = admin.state == .loaded ? admin.rounds(on: event.id) : nil
        return NavigationLink {
            KveldenView(eventID: event.id, terminliste: terminliste, admin: admin, loads: loads)
        } label: {
            EveningRowLabel(
                event: event,
                committee: terminliste.committeeNames(for: event.id),
                signups: isUpcoming ? Tonight.signupText(terminliste.signups[event.id] ?? [],
                                                         rosterCount: terminliste.members.count) : nil,
                rounds: rounds,
                referenceYear: referenceYear
            )
        }
        .swipeActions {
            Button("Slett", systemImage: "trash", role: .destructive) { pendingDelete = event }
        }
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
            } catch {
                self.error = error.message
            }
        }
    }
}

/// En kveld i lista: dato og rundestatus, tid og sted, påmeldte og sosialkomité.
private struct EveningRowLabel: View {
    let event: EventRow
    let committee: [String]
    /// «9 av 14 kommer · 1 usikker». Bare for kommende kvelder.
    let signups: String?
    /// nil til rundene er hentet.
    let rounds: [RoundRow]?
    let referenceYear: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(EveningDates.longText(event.eventDate, referenceYear: referenceYear, capitalized: true))
                .font(.dd(.sans, size: 17, weight: .semibold, relativeTo: .headline))
                .foregroundStyle(Color.ddInk)
            let details = [EveningDates.timeText(event.startTime), event.venue].compactMap { $0 }
            if !details.isEmpty {
                Text(details.joined(separator: " · "))
                    .font(.dd(.sans, size: 14, relativeTo: .subheadline))
                    .foregroundStyle(Color.ddInkSecondary)
            }
            if let signups {
                Text(signups)
                    .font(.dd(.sans, size: 13, relativeTo: .footnote))
                    .foregroundStyle(Color.ddInkSecondary)
            }
            Text(committee.isEmpty ? "Ingen sosialkomité" : "Sosialkomité: \(NorwegianList.join(committee))")
                .font(.dd(.sans, size: 13, relativeTo: .footnote))
                .foregroundStyle(committee.isEmpty ? Color.ddRustText : Color.ddInkSecondary)
            if let rounds {
                DDPill(EveningRounds.text(rounds), tone: EveningRoundsTone.tone(EveningRounds.phase(rounds)))
                    .fixedSize()
                    .padding(.top, 4)
            }
        }
        .padding(.vertical, 2)
    }
}

/// Fargen på rundestatusen: grønn når en runde går, gul for kladd.
enum EveningRoundsTone {
    static func tone(_ phase: EveningRounds.Phase) -> DDTone {
        switch phase {
        case .active: .lime
        case .draft: .sun
        case .done: .earthDeep
        case .none: .earth
        }
    }
}

/// Forslaget fra trekningen, som arrangøren godtar eller trekker på nytt.
private struct CommitteeDrawSheet: View {
    let model: TerminlisteModel
    @State var plan: [CommitteeDraw.Assignment]
    let perEvening: Int
    let done: () -> Void
    @State private var error: String?
    @State private var isBusy = false

    var body: some View {
        DDList {
            Section {
                ForEach(plan, id: \.eventID) { assignment in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(EveningDates.longText(assignment.date, capitalized: true)).font(.dd(.sans, size: 17, weight: .semibold, relativeTo: .headline))
                        Text(NorwegianList.join(assignment.memberIDs.map(model.memberName)))
                            .foregroundStyle(Color.ddInkSecondary)
                    }
                }
            } footer: {
                DDFooter("Ingenting er lagret ennå.")
            }
            if let error {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(Color.ddError)
                }
            }
        }
        .navigationTitle("Sosialkomité")
        .ddNavigationChrome()
        .navigationBarTitleDisplayMode(.inline)
        .disabled(isBusy)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Avbryt", action: done)
            }
            ToolbarItem(placement: .confirmationAction) {
                if isBusy {
                    ProgressView()
                } else {
                    Button("Lagre", action: save)
                }
            }
            ToolbarItem(placement: .bottomBar) {
                Button("Trekk på nytt", systemImage: "dice") {
                    plan = model.proposeCommittees(perEvening: perEvening)
                }
            }
        }
    }

    private func save() {
        isBusy = true
        error = nil
        Task {
            defer { isBusy = false }
            do throws(DataError) {
                try await model.apply(plan)
                done()
            } catch {
                self.error = error.message
            }
        }
    }
}

private struct IdentifiedPlan: Identifiable {
    let id = UUID()
    let plan: [CommitteeDraw.Assignment]
}

