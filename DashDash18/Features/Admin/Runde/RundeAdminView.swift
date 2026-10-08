import GolfgutuCore
import SwiftUI

/// Runder: alle rundene i klubben, gruppert per kveld, nyeste først. Kladder åpner oppsettet,
/// startede og låste runder åpner rundens skjerm, der avkorting, låsing, sletting og retting ligger.
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

#if DEBUG
/// Runder med oppdiktede kvelder (`-DDDesignScreen runder`).
struct RundeAdminSample: View {
    @State private var model = RundeAdminModel.sample()

    var body: some View {
        RundeAdminContent(model: model)
    }
}
#endif

/// Utkastet som vises i hurtigstarten (eller veiviseren).
private struct WizardItem: Identifiable {
    let id = UUID()
    let draft: RoundDraft
}

/// Kladden som skal slettes, med det som følger med.
private struct PendingDelete: Identifiable {
    let round: RoundRow
    let summary: RoundDeleteSummary
    var id: UUID { round.id }
}

private struct RundeAdminContent: View {
    @State var model: RundeAdminModel
    @State private var wizard: WizardItem?
    @State private var pendingDelete: PendingDelete?
    @State private var message: String?
    @State private var error: String?
    @State private var isBusy = false

    var body: some View {
        content
            .navigationTitle("Runder")
            .ddNavigationChrome()
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Ny runde", systemImage: "plus") { newRound(on: model.selectedEvent) }
                        .disabled(model.state != .loaded || model.selectedEvent == nil || isBusy)
                }
            }
            .task { await model.load() }
            .refreshable { await model.load() }
            .sheet(item: $wizard) { item in
                RoundSetupFlow(model: model, draft: item.draft) { result in
                    wizard = nil
                    message = result
                }
            }
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
                    .buttonStyle(.dd(.primary))
            }
        case .loaded:
            if model.events.isEmpty && model.allRounds.isEmpty {
                ContentUnavailableView {
                    Label("Ingen kvelder i terminlista", systemImage: "calendar")
                } description: {
                    Text("Legg inn en kveld under «Terminliste» først. Da kan du sette opp runden her.")
                }
            } else {
                list
            }
        }
    }

    private var list: some View {
        DDList {
            ForEach(model.groups) { group in
                groupSection(group)
                if group.hasActive {
                    AvsluttKveldenSection(rounds: group.rounds, title: model.title) { text in
                        await model.load()
                        message = text
                    }
                }
            }
        }
        .disabled(isBusy)
        .overlay { if isBusy { ProgressView() } }
    }

    private func groupSection(_ group: RoundGroup) -> some View {
        let isNext = group.event?.id == model.selectedEventID
        let allowsNew = group.event.map(model.allowsNewRound) ?? false
        return Section {
            if group.rounds.isEmpty {
                Text("Ingen runder ennå.")
                    .foregroundStyle(Color.ddInkSecondary)
            }
            ForEach(group.rounds) { round in
                row(round)
            }
            if allowsNew, let event = group.event {
                Button {
                    newRound(on: event)
                } label: {
                    Label("Ny runde på denne kvelden", systemImage: "plus")
                        .foregroundStyle(Color.ddForestInk)
                }
            }
        } header: {
            DDHeader(group.title + (isNext ? " · står for tur" : ""))
        } footer: {
            if isNext {
                DDFooter("Kladder ser bare arrangørene. Én runde kan gå om gangen i klubben.")
            }
        }
    }

    /// En kladd åpner oppsettet. En startet eller låst runde åpner rundens skjerm.
    @ViewBuilder
    private func row(_ round: RoundRow) -> some View {
        switch round.status {
        case .draft:
            Button {
                edit(round)
            } label: {
                rowLabel(round)
            }
            .swipeActions {
                Button("Slett", systemImage: "trash", role: .destructive) { askDelete(round) }
            }
        case .active, .locked:
            NavigationLink {
                RoundTableView(round: round, title: model.title(round), admin: model) { text in
                    message = text
                }
            } label: {
                rowLabel(round)
            }
        }
    }

    private func rowLabel(_ round: RoundRow) -> some View {
        let players = model.playersByRound[round.id] ?? []
        let bays = Set(players.compactMap(\.bayNo)).count
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.title(round))
                    .foregroundStyle(Color.ddInk)
                Text(subtitle(round, players: players.count, bays: bays))
                    .font(.dd(.sans, size: 13, relativeTo: .footnote))
                    .foregroundStyle(Color.ddInkSecondary)
            }
            Spacer()
            StatusBadge(status: round.status)
        }
        .contentShape(.rect)
    }

    private func subtitle(_ round: RoundRow, players: Int, bays: Int) -> String {
        var parts = ["\(round.holeCount) hull" + (round.firstHole == 10 ? " fra hull 10" : "")]
        parts.append(CompetitionForm.form(id: round.format).name)
        if players > 0 { parts.append("\(players) med") }
        if bays > 0 { parts.append(GroupTerm.for(stored: round.venue).count(bays)) }
        if let tee = EveningDates.timeText(round.teeTime) { parts.append(tee) }
        return parts.joined(separator: " · ")
    }

    /// Ny runde på kvelden: velger kvelden først, så påmeldingen og rundenummeret stemmer.
    private func newRound(on event: EventRow?) {
        guard let event else { return }
        run {
            if event.id != model.selectedEventID {
                try await model.select(eventID: event.id)
            }
            if let draft = model.newDraft() { wizard = WizardItem(draft: draft) }
        }
    }

    private func edit(_ round: RoundRow) {
        run {
            if let eventID = round.eventID, eventID != model.selectedEventID {
                try await model.select(eventID: eventID)
            }
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
            .font(.dd(.sans, size: 12, weight: .semibold, relativeTo: .caption))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(background, in: Capsule())
            .foregroundStyle(color)
    }

    private var color: Color {
        switch status {
        case .draft: Color.ddInkSecondary
        case .active: Color.ddLimeInk
        case .locked: Color.ddInkSecondary
        }
    }

    private var background: Color {
        switch status {
        case .draft: Color.ddEarth
        case .active: Color.ddLimeBackground
        case .locked: Color.ddEarthDeep
        }
    }
}
