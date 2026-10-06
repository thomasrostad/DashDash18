import SwiftUI

/// Kveld under spill: markørlinja, sol-stripa, hullprikkene, hullkortet og «Bayen nå».
struct RundeView: View {
    @Bindable var model: RundeModel
    @State private var scorecardFor: ScorecardTarget?

    var body: some View {
        ScrollView {
            if let game = model.game {
                VStack(alignment: .leading, spacing: 14) {
                    if model.needsParConfirmation {
                        ParBekreftelseCard(game: game, canConfirm: model.canConfirmPar) {
                            try await model.confirmPar()
                        }
                    } else {
                        playing(game)
                    }
                    BayenNaaSection(rows: game.standings(viewer: model.viewer)) { member in
                        scorecardFor = ScorecardTarget(memberID: member)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .refreshable { await model.load() }
        .navigationTitle(model.game?.snapshot.course?.name ?? "Kvelden")
        .sheet(item: $scorecardFor) { target in
            if let game = model.game {
                ScorekortSheet(game: game, memberID: target.memberID)
            }
        }
        .overlay {
            if let celebration = model.celebration {
                FeiringOverlay(celebration: celebration) {
                    model.celebration = nil
                }
            }
        }
    }

    @ViewBuilder
    private func playing(_ game: RoundGame) -> some View {
        if let line = game.markerLine(for: model.viewer) {
            Text(line)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(.green.opacity(0.12), in: .rect(cornerRadius: 12))
        }
        if let stripe = game.bayStripe(currentHole: model.currentHole, viewer: model.viewer) {
            HStack {
                Text(stripe.text)
                    .font(.subheadline)
                Spacer(minLength: 8)
                Button(stripe.button) { model.goTo(hole: stripe.hole) }
                    .font(.subheadline.weight(.semibold))
            }
            .padding(12)
            .background(.yellow.opacity(0.25), in: .rect(cornerRadius: 12))
            .accessibilityElement(children: .contain)
        }
        HullprikkerView(dots: game.dots(currentHole: model.currentHole, viewer: model.viewer,
                                        pending: model.pendingHoles)) { model.goTo(hole: $0) }
        if let card = model.card {
            HullkortView(
                card: card,
                isPending: model.pendingHoles.contains(card.holeIndex),
                isSaving: model.isSaving,
                error: model.saveError,
                onStep: { model.step($0, member: $1) },
                onConfirm: { model.confirm(member: $0) },
                onSave: { Task { await model.saveCurrentHole() } },
                onGoTo: { model.goTo(hole: $0) },
                onScorecard: { scorecardFor = ScorecardTarget(memberID: $0 ?? model.viewer.memberID) }
            )
        } else {
            Text("Du er ikke med i denne runden. Du ser stillingen under.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

struct ScorecardTarget: Identifiable {
    let memberID: UUID
    var id: UUID { memberID }
}
