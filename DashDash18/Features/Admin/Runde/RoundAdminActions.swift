import GolfgutuCore
import Observation
import SwiftUI

/// Runden som settes opp (pushet hurtigstart).
struct RoundSetupItem: Hashable {
    let id = UUID()
    let draft: RoundDraft

    static func == (lhs: RoundSetupItem, rhs: RoundSetupItem) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Kladden som skal slettes, med det som følger med.
struct RoundPendingDelete: Identifiable {
    let round: RoundRow
    let summary: RoundDeleteSummary
    var id: UUID { round.id }
}

/// Handlingene på rundene fra en liste (arrangørsiden, Kvelden, Alle runder): ny runde, fortsett
/// en kladd, slett en kladd. Oppsettet pushes, og meldinger og feil vises med `.roundAdminActions(_:)`.
@Observable
final class RoundAdminActions {
    let model: RundeAdminModel
    var setup: RoundSetupItem?
    var pendingDelete: RoundPendingDelete?
    /// Det som skjedde («Kladden er lagret.»). Vises som en melding.
    var message: String?
    var error: String?
    private(set) var isBusy = false

    init(model: RundeAdminModel) {
        self.model = model
    }

    /// Ny runde på kvelden: velger kvelden først, så påmeldingen og rundenummeret stemmer.
    func newRound(on event: EventRow?) {
        guard let event else { return }
        run { [model] in
            if event.id != model.selectedEventID {
                try await model.select(eventID: event.id)
            }
            if let draft = model.newDraft() { self.setup = RoundSetupItem(draft: draft) }
        }
    }

    /// «Fortsett kladd» fra hovedknappen: kladden på den valgte kvelden.
    func continueDraft(id: UUID) {
        run { [model] in
            if let draft = try await model.draft(id: id) { self.setup = RoundSetupItem(draft: draft) }
        }
    }

    /// Åpner kladden i oppsettet.
    func edit(_ round: RoundRow) {
        run { [model] in
            if let eventID = round.eventID, eventID != model.selectedEventID {
                try await model.select(eventID: eventID)
            }
            let draft = try await model.draft(for: round)
            self.setup = RoundSetupItem(draft: draft)
        }
    }

    /// Teller hva som forsvinner, og spør.
    func askDelete(_ round: RoundRow) {
        run { [model] in
            let summary = try await model.deleteSummary(round)
            self.pendingDelete = RoundPendingDelete(round: round, summary: summary)
        }
    }

    func delete(_ round: RoundRow) {
        run { [model] in self.message = try await model.delete(round) }
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

extension View {
    /// Oppsettet (pushet), spørsmålet før sletting, og meldinger og feil fra rundehandlingene.
    func roundAdminActions(_ actions: RoundAdminActions) -> some View {
        modifier(RoundAdminActionsModifier(actions: actions))
    }
}

private struct RoundAdminActionsModifier: ViewModifier {
    @Bindable var actions: RoundAdminActions

    func body(content: Content) -> some View {
        content
            .navigationDestination(item: $actions.setup) { item in
                RundeQuickStartView(model: actions.model, draft: item.draft) { result in
                    actions.setup = nil
                    actions.message = result
                }
            }
            .confirmationDialog(
                actions.pendingDelete.map { "Slett \($0.summary.noun) · \(actions.model.title($0.round))" } ?? "",
                isPresented: Binding(get: { actions.pendingDelete != nil },
                                     set: { if !$0 { actions.pendingDelete = nil } }),
                titleVisibility: .visible,
                presenting: actions.pendingDelete
            ) { item in
                Button(item.summary.buttonTitle, role: .destructive) { actions.delete(item.round) }
            } message: { item in
                Text(item.summary.message)
            }
            .alert("Det gikk ikke", isPresented: Binding(get: { actions.error != nil },
                                                         set: { if !$0 { actions.error = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(actions.error ?? "")
            }
            .alert("Ferdig", isPresented: Binding(get: { actions.message != nil },
                                                  set: { if !$0 { actions.message = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(actions.message ?? "")
            }
    }
}

/// En runde i lista. En kladd åpner oppsettet (sveip for å slette). En startet eller låst runde
/// åpner rundens skjerm, der avkorting, låsing, sletting og retting ligger.
struct RoundAdminRow: View {
    let round: RoundRow
    let actions: RoundAdminActions

    var body: some View {
        switch round.status {
        case .draft:
            Button {
                actions.edit(round)
            } label: {
                label
            }
            .swipeActions {
                Button("Slett", systemImage: "trash", role: .destructive) { actions.askDelete(round) }
            }
        case .active, .locked:
            NavigationLink {
                RoundTableView(round: round, title: actions.model.title(round), admin: actions.model) { text in
                    actions.message = text
                }
            } label: {
                label
            }
        }
    }

    private var label: some View {
        let model = actions.model
        let players = model.playersByRound[round.id] ?? []
        let bays = Set(players.compactMap(\.bayNo)).count
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.title(round))
                    .foregroundStyle(Color.ddInk)
                Text(RoundListing.subtitle(round, players: players.count, bays: bays))
                    .font(.dd(.sans, size: 13, relativeTo: .footnote))
                    .foregroundStyle(Color.ddInkSecondary)
            }
            Spacer()
            StatusBadge(status: round.status)
        }
        .contentShape(.rect)
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
