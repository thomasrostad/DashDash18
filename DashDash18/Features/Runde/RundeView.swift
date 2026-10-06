import SwiftUI

/// Kveld under spill: markørlinja, sol-stripa, hullprikkene, hullkortet og «Bayen nå».
struct RundeView: View {
    @Bindable var model: RundeModel
    @State private var scorecardFor: ScorecardTarget?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                    let matches = game.matchCard(viewer: model.viewer)
                    if game.isDecidedHoleByHole, let matches {
                        MatchkortSection(card: matches)
                    }
                    BayenNaaListe(rows: game.bayenNaa(viewer: model.viewer)) { member in
                        scorecardFor = ScorecardTarget(memberID: member)
                    }
                    if !game.isDecidedHoleByHole, let matches {
                        MatchkortSection(card: matches)
                    }
                    let eventID = game.snapshot.round.eventID
                    KveldExtrasButtons(model: KveldExtrasModel(context: model.clubContext, eventID: eventID))
                        .id(eventID)
                }
                .padding(.horizontal, DDSpacing.gutter)
                .padding(.vertical, DDSpacing.l)
                .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: model.currentHole)
            }
        }
        .refreshable { await model.load() }
        .navigationTitle(model.game?.snapshot.course?.name ?? "Kvelden")
        .ddNavigationChrome()
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
        .animation(reduceMotion ? nil : .smooth(duration: 0.32), value: model.celebration?.id)
    }

    @ViewBuilder
    private func playing(_ game: RoundGame) -> some View {
        if let line = game.markerLine(for: model.viewer) {
            // Beige info-stripe, som «Du er markør i bås 1 · …» i PWA-en.
            DDInfoStripe(line)
        }
        if let stripe = game.bayStripe(currentHole: model.currentHole, viewer: model.viewer) {
            DDInfoStripe(tone: .sun) {
                HStack {
                    Text(stripe.text)
                    Spacer(minLength: 8)
                    Button(stripe.button) { model.goTo(hole: stripe.hole) }
                        .buttonStyle(.dd(.primary, compact: true))
                }
            }
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
            DDInfoStripe("Du er ikke med i denne runden. Du ser stillingen under.")
        }
        let lines = game.holeMatchLines(hole: model.currentHole, viewer: model.viewer)
        if !lines.isEmpty {
            HullMatchLinjer(lines: lines)
        }
        ForEach([SideClaimKind.drive, .kp], id: \.self) { kind in
            if let box = game.sidePrizeBox(kind, hole: model.currentHole, viewer: model.viewer) {
                SidepremieBoks(
                    box: box,
                    viewer: model.viewer.memberID,
                    names: game.snapshot.names,
                    existing: { game.sideClaim(kind, for: $0)?.meters },
                    onSubmit: { try await model.submitSideClaim(kind, member: $0, text: $1) },
                    onDelete: { try await model.deleteSideClaim($0) }
                )
            }
        }
    }
}

struct ScorecardTarget: Identifiable {
    let memberID: UUID
    var id: UUID { memberID }
}
