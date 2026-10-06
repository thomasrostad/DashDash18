import GolfgutuCore
import SwiftUI

/// Kveldens runder for arrangøren: kladd, pågår og låst, med veiviseren for nye runder.
struct RundeAdminView: View {
    @Environment(\.clubContext) private var context

    var body: some View {
        if let context {
            RundeAdminContent(model: RundeAdminModel(context: context))
        } else {
            ContentUnavailableView("Ingen klubb", systemImage: "flag.2.crossed")
        }
    }
}

/// Utkastet som vises i veiviseren.
private struct WizardItem: Identifiable {
    let id = UUID()
    let draft: RoundDraft
}

/// Runden som skal slettes, med det som følger med.
private struct PendingDelete: Identifiable {
    let round: RoundRow
    let summary: RoundDeleteSummary
    var id: UUID { round.id }
}

private struct RundeAdminContent: View {
    @State var model: RundeAdminModel
    @State private var wizard: WizardItem?
    @State private var pendingDelete: PendingDelete?
    @State private var pendingLock: RoundRow?
    @State private var reviewing: RoundRow?
    @State private var cutting: RoundRow?
    @State private var message: String?
    @State private var error: String?
    @State private var isBusy = false

    var body: some View {
        withDialogs
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

    private var withDialogs: some View {
        base
            .confirmationDialog(
                pendingDelete.map { "Slett \($0.summary.noun) · \(model.title($0.round))" } ?? "",
                isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                titleVisibility: .visible,
                presenting: pendingDelete
            ) { item in
                Button(item.summary.buttonTitle, role: .destructive) { delete(item.round) }
            } message: { item in
                Text(item.summary.message)
            }
            .confirmationDialog(
                "Låse runden?",
                isPresented: Binding(get: { pendingLock != nil }, set: { if !$0 { pendingLock = nil } }),
                titleVisibility: .visible,
                presenting: pendingLock
            ) { round in
                Button("Lås \(model.title(round))") { lock(round) }
            } message: { _ in
                Text("Runden er ferdig og teller i sesongen. En låst runde kan ikke bli kladd igjen eller slettes herfra.")
            }
    }

    private var base: some View {
        content
            .navigationTitle("Runder")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Ny runde", systemImage: "plus") {
                        if let draft = model.newDraft() { wizard = WizardItem(draft: draft) }
                    }
                    .disabled(model.state != .loaded || model.selectedEvent == nil)
                }
            }
            .task { await model.load() }
            .refreshable { await model.load() }
            .navigationDestination(isPresented: Binding(get: { reviewing != nil }, set: { if !$0 { reviewing = nil } })) {
                if let round = reviewing {
                    RoundTableView(round: round, title: model.title(round))
                }
            }
            .sheet(item: $cutting, onDismiss: { Task { await model.load() } }) { round in
                NavigationStack {
                    AvkortSheet(round: round, title: model.title(round)) { message = $0 }
                }
            }
            .sheet(item: $wizard) { item in
                NavigationStack {
                    RundeWizardView(model: model, draft: item.draft) { result in
                        wizard = nil
                        message = result
                    }
                }
                .interactiveDismissDisabled()
            }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ProgressView("Henter rundene …")
        case .failed(let text):
            ContentUnavailableView {
                Label("Fikk ikke hentet rundene", systemImage: "wifi.exclamationmark")
            } description: {
                Text(text)
            } actions: {
                Button("Prøv igjen") { Task { await model.load() } }
                    .buttonStyle(.borderedProminent)
            }
        case .loaded:
            list
        }
    }

    private var list: some View {
        List {
            Section {
                if model.events.isEmpty {
                    Text("Ingen kvelder i terminlista. Legg inn en under «Terminliste» først.")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Kveld", selection: Binding(
                        get: { model.selectedEventID },
                        set: { id in if let id { Task { await model.select(eventID: id) } } }
                    )) {
                        ForEach(model.events) { event in
                            Text(EveningDates.longText(event.eventDate, capitalized: true)).tag(Optional(event.id))
                        }
                    }
                }
            }

            if let active = model.activeRound, active.eventID != model.selectedEventID {
                Section {
                    Label("\(model.title(active)) går på en annen kveld. Lås den før du starter en ny.",
                          systemImage: "exclamationmark.circle")
                        .foregroundStyle(.secondary)
                }
            }

            if model.selectedEvent != nil {
                Section {
                    if model.rounds.isEmpty {
                        Text("Ingen runder ennå. Trykk + for å sette opp kveldens første.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(model.rounds) { round in
                        row(round)
                    }
                } header: {
                    Text("Kveldens runder")
                } footer: {
                    Text("Kladder ser bare arrangørene. Én runde kan gå om gangen i klubben.")
                }

                AvsluttKveldenSection(rounds: model.rounds, title: model.title) { text in
                    await model.load()
                    message = text
                }
            }

            Section {
                NavigationLink { RundeneView() } label: {
                    Label("Rundene", systemImage: "tablecells")
                }
            } footer: {
                Text("Hele runden som tabell, og retting av hull, også i låste runder.")
            }
        }
        .disabled(isBusy)
        .overlay { if isBusy { ProgressView() } }
    }

    private func row(_ round: RoundRow) -> some View {
        let players = model.playersByRound[round.id] ?? []
        let bays = Set(players.compactMap(\.bayNo)).count
        return Menu {
            switch round.status {
            case .draft:
                Button("Rediger kladden", systemImage: "pencil") { edit(round) }
                Button("Start runden", systemImage: "play") { run { try await model.start(round) } }
            case .active:
                Button("Se hele runden", systemImage: "tablecells") { reviewing = round }
                Button("Avkort runden …", systemImage: "scissors") { cutting = round }
                Button("Lås runden", systemImage: "lock") { pendingLock = round }
            case .locked:
                Button("Se hele runden", systemImage: "tablecells") { reviewing = round }
            }
            if round.status != .locked {
                Button(round.status == .draft ? "Slett kladden" : "Slett runden", systemImage: "trash", role: .destructive) {
                    askDelete(round)
                }
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.title(round))
                        .foregroundStyle(.primary)
                    Text(subtitle(round, players: players.count, bays: bays))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                StatusBadge(status: round.status)
            }
        }
    }

    private func subtitle(_ round: RoundRow, players: Int, bays: Int) -> String {
        var parts = ["\(round.holeCount) hull" + (round.firstHole == 10 ? " fra hull 10" : "")]
        parts.append(CompetitionForm.form(id: round.format).name)
        if players > 0 { parts.append("\(players) med") }
        if bays > 0 { parts.append(bays == 1 ? "1 bås" : "\(bays) båser") }
        if let tee = EveningDates.timeText(round.teeTime) { parts.append(tee) }
        return parts.joined(separator: " · ")
    }

    private func edit(_ round: RoundRow) {
        run {
            let draft = try await model.draft(for: round)
            wizard = WizardItem(draft: draft)
        }
    }

    private func askDelete(_ round: RoundRow) {
        run {
            let summary = try await model.deleteSummary(round)
            pendingDelete = PendingDelete(round: round, summary: summary)
        }
    }

    private func lock(_ round: RoundRow) {
        run { try await model.lock(round) }
    }

    private func delete(_ round: RoundRow) {
        run { message = try await model.delete(round) }
    }

    private func run(_ action: @escaping () async throws -> Void) {
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                try await action()
            } catch {
                self.error = DataError.from(error).message
            }
        }
    }
}

/// Kladd / Pågår / Låst.
struct StatusBadge: View {
    let status: RoundStatus

    var body: some View {
        Text(RoundListing.statusText(status))
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    private var color: Color {
        switch status {
        case .draft: .secondary
        case .active: .green
        case .locked: .blue
        }
    }
}
