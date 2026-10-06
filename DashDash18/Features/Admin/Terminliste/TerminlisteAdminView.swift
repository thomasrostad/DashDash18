import SwiftUI

/// Terminlista for arrangøren: kveldene i sesongen, med sted, tid og sosialkomité.
struct TerminlisteAdminView: View {
    @Environment(\.clubContext) private var context

    var body: some View {
        if let context {
            TerminlisteContent(model: TerminlisteModel(context: context))
        } else {
            ContentUnavailableView("Ingen klubb", systemImage: "calendar")
        }
    }
}

private struct TerminlisteContent: View {
    @State var model: TerminlisteModel
    @State private var editing: IdentifiedDraft?
    @State private var showPast = false
    @State private var pendingDelete: EventRow?
    @State private var drawPlan: IdentifiedPlan?
    @State private var perEvening = 2
    @State private var error: String?
    @State private var isBusy = false

    var body: some View {
        content
            .navigationTitle("Terminliste")
            .ddNavigationChrome()
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Ny kveld", systemImage: "plus") { editing = IdentifiedDraft(draft: model.draft(for: nil)) }
                        .disabled(model.state != .loaded)
                }
            }
            .task { await model.load() }
            .refreshable { await model.load() }
            .sheet(item: $editing) { item in
                NavigationStack {
                    EventEditor(model: model, draft: item.draft) { editing = nil }
                }
            }
            .sheet(item: $drawPlan) { item in
                NavigationStack {
                    CommitteeDrawSheet(model: model, plan: item.plan, perEvening: perEvening) { drawPlan = nil }
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
            .alert("Det gikk ikke", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(error ?? "")
            }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ProgressView("Henter terminlista …")
        case .failed(let message):
            ContentUnavailableView {
                Label("Fikk ikke hentet terminlista", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Prøv igjen") { Task { await model.load() } }
                    .buttonStyle(.dd(.primary))
            }
        case .loaded:
            list
        }
    }

    private var list: some View {
        let today = EveningDates.today()
        let (upcoming, past) = Terminliste.split(model.events, today: today)
        let year = EveningDates.year(of: today)
        let missingCommittee = upcoming.contains { (model.committees[$0.id] ?? []).count < perEvening }
        return DDList {
            Section {
                if let season = model.activeSeason {
                    LabeledContent("Sesong", value: season.name)
                } else {
                    Label {
                        Text("Ingen aktiv sesong. Lag en under «Sesong og regler». Kvelder kan likevel legges inn, uten sesong.")
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
                    row(event, referenceYear: year)
                }
            }

            if !upcoming.isEmpty && missingCommittee {
                Section {
                    Stepper("Per kveld: \(perEvening)", value: $perEvening, in: 1...6)
                    Button("Trekk sosialkomité", systemImage: "dice") { draw() }
                        .disabled(model.members.count < perEvening)
                } footer: {
                    DDFooter("Fyller kommende kvelder som mangler komité. De med færrest turer trekkes først. Kvelder som har komité, røres ikke.")
                }
            }

            if !past.isEmpty {
                Section {
                    Toggle("Vis tidligere (\(past.count))", isOn: $showPast.animation())
                    if showPast {
                        ForEach(past) { event in
                            row(event, referenceYear: year)
                        }
                    }
                }
            }
        }
        .disabled(isBusy)
    }

    private func row(_ event: EventRow, referenceYear: Int?) -> some View {
        Button {
            editing = IdentifiedDraft(draft: model.draft(for: event))
        } label: {
            EventRowLabel(
                event: event,
                committee: model.committeeNames(for: event.id),
                referenceYear: referenceYear
            )
        }
        .tint(Color.ddInk)
        .swipeActions {
            Button("Slett", systemImage: "trash", role: .destructive) { pendingDelete = event }
        }
    }

    private func draw() {
        let plan = model.proposeCommittees(perEvening: perEvening)
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
                try await model.delete(event)
            } catch {
                self.error = error.message
            }
        }
    }
}

private struct EventRowLabel: View {
    let event: EventRow
    let committee: [String]
    let referenceYear: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(EveningDates.longText(event.eventDate, referenceYear: referenceYear, capitalized: true))
                .font(.dd(.sans, size: 17, weight: .semibold, relativeTo: .headline))
            let details = [EveningDates.timeText(event.startTime), event.venue].compactMap { $0 }
            if !details.isEmpty {
                Text(details.joined(separator: " · "))
                    .font(.dd(.sans, size: 14, relativeTo: .subheadline))
                    .foregroundStyle(Color.ddInkSecondary)
            }
            Text(committee.isEmpty ? "Ingen sosialkomité" : "Sosialkomité: \(NorwegianList.join(committee))")
                .font(.dd(.sans, size: 13, relativeTo: .footnote))
                .foregroundStyle(committee.isEmpty ? Color.ddRustText : Color.ddInkSecondary)
        }
        .padding(.vertical, 2)
    }
}

/// Ny eller endre kveld.
private struct EventEditor: View {
    let model: TerminlisteModel
    @State var draft: EventDraft
    let done: () -> Void
    @State private var error: String?
    @State private var isBusy = false
    @State private var confirmDelete = false

    var body: some View {
        DDForm {
            Section {
                DatePicker("Dato", selection: $draft.date, displayedComponents: .date)
                Toggle("Klokkeslett", isOn: $draft.hasTime)
                if draft.hasTime {
                    DatePicker("Starter", selection: $draft.time, displayedComponents: .hourAndMinute)
                }
                TextField("Sted", text: $draft.venue)
                    .textInputAutocapitalization(.words)
                TextField("Notat (valgfritt)", text: $draft.note, axis: .vertical)
                    .lineLimit(2...5)
            } footer: {
                DDFooter("Én kveld per dato.")
            }

            Section {
                ForEach(model.members) { member in
                    Button {
                        toggle(member.id)
                    } label: {
                        HStack {
                            Text(member.displayName)
                            Spacer()
                            if draft.committee.contains(member.id) {
                                Image(systemName: "checkmark").foregroundStyle(.tint)
                            }
                        }
                    }
                    .tint(Color.ddInk)
                    .accessibilityAddTraits(draft.committee.contains(member.id) ? .isSelected : [])
                }
            } header: {
                DDHeader("Sosialkomité (\(draft.committee.count))")
            }

            if let error {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(Color.ddError)
                }
            }

            if draft.id != nil {
                Section {
                    Button("Slett kvelden", role: .destructive) { confirmDelete = true }
                }
            }
        }
        .environment(\.timeZone, EveningDates.osloTimeZone)
        .navigationTitle(draft.id == nil ? "Ny kveld" : "Endre kveld")
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
        }
        .confirmationDialog("Slette kvelden?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Slett", role: .destructive, action: delete)
        } message: {
            Text("Påmeldingene og sosialkomiteen for kvelden slettes også.")
        }
    }

    private func toggle(_ id: UUID) {
        if draft.committee.contains(id) {
            draft.committee.remove(id)
        } else {
            draft.committee.insert(id)
        }
    }

    private func save() {
        run { () async throws(DataError) in try await model.save(draft) }
    }

    private func delete() {
        guard let id = draft.id, let event = model.events.first(where: { $0.id == id }) else { return }
        run { () async throws(DataError) in try await model.delete(event) }
    }

    private func run(_ action: @escaping () async throws(DataError) -> Void) {
        isBusy = true
        error = nil
        Task {
            defer { isBusy = false }
            do throws(DataError) {
                try await action()
                done()
            } catch {
                self.error = error.message
            }
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

/// Identifiserbar innpakning, så et utkast kan styre et ark.
private struct IdentifiedDraft: Identifiable {
    let id = UUID()
    let draft: EventDraft
}

private struct IdentifiedPlan: Identifiable {
    let id = UUID()
    let plan: [CommitteeDraw.Assignment]
}

#Preview {
    NavigationStack {
        TerminlisteAdminView()
    }
}
