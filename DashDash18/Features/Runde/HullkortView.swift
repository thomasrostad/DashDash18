import GolfgutuCore
import SwiftUI

/// Hullkortet for hele båsen: én rad per spiller, og «Lagre hull» for markøren.
struct HullkortView: View {
    let card: HoleCard
    let isPending: Bool
    let isSaving: Bool
    let error: String?
    let onStep: (Int, UUID) -> Void
    let onConfirm: (UUID) -> Void
    let onSave: () -> Void
    let onGoTo: (Int) -> Void
    /// Åpner scorekortet til spilleren (nil: ditt eget).
    let onScorecard: (UUID?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            HStack {
                Text(card.header)
                Spacer()
                Text(card.strokesLabel)
            }
            .ddEyebrow()
            .padding(.top, 6)

            VStack(spacing: 0) {
                DDDivider()
                ForEach(card.rows) { row in
                    HullRadView(row: row, isPending: isPending, onStep: onStep, onConfirm: onConfirm,
                                onName: { onScorecard(row.memberID) })
                    if row.id != card.rows.last?.id { DDDivider() }
                }
            }

            if card.showsParHint {
                Text("Stiplet tall er par. Trykk tallet for å bekrefte det.")
                    .font(.ddCaption)
                    .foregroundStyle(Color.ddInkSecondary)
            }
            if let outside = card.outsideTruncation {
                Text(outside)
                    .font(.ddCaption)
                    .ddWarningStyle()
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            if isPending {
                Label("Hullet er ikke lagret ennå. Det sendes når du har dekning.", systemImage: "icloud.and.arrow.up")
                    .font(.ddCaption)
                    .ddWarningStyle()
            }
            if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .ddErrorStyle()
            }
            actionView
                .padding(.top, 4)
            if let hint = card.viewerHint {
                Text(hint)
                    .font(.ddCaption)
                    .foregroundStyle(Color.ddInkSecondary)
            }
            if card.holeIndex > 0 {
                Button("‹ Forrige hull") { onGoTo(card.holeIndex - 1) }
                    .buttonStyle(.ddText)
                    .frame(maxWidth: .infinity)
            }
        }
        .ddCard(.large)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(card.title)
                    .ddEyebrow()
                Text(card.detail)
                    .font(.dd(.sans, size: 15, relativeTo: .subheadline))
                    .monospacedDigit()
                    .foregroundStyle(Color.ddInkSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                if card.isLongestDrive {
                    DDSidePrizeTag(kind: .longestDrive)
                }
                if card.isClosestToPin {
                    DDSidePrizeTag(kind: .closestToPin)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var actionView: some View {
        switch card.action {
        case .save(let title, let enabled, let blocker):
            Button(action: onSave) {
                Group {
                    if isSaving { ProgressView().tint(DDToken.buttonPrimaryText.color) } else { Text(title) }
                }
            }
            .buttonStyle(.ddPrimary)
            .disabled(!enabled || isSaving)
            if let blocker {
                Text(blocker)
                    .font(.ddCaption)
                    .foregroundStyle(Color.ddInkSecondary)
                    .frame(maxWidth: .infinity)
            }
        case .next(let title, let hole):
            Button(title) { onGoTo(hole) }
                .buttonStyle(.dd(.secondary, fullWidth: true))
        case .scorecard:
            Button("Alle hull er lagret · se scorekortet →") { onScorecard(nil) }
                .buttonStyle(.dd(.secondary, fullWidth: true))
        case .none:
            EmptyView()
        }
    }
}

/// Én spiller: navn, slag fått, resultat, og tallet med steppere når raden kan føres.
struct HullRadView: View {
    let row: HoleCard.Row
    let isPending: Bool
    let onStep: (Int, UUID) -> Void
    let onConfirm: (UUID) -> Void
    let onName: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Button(action: onName) {
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text(row.name)
                            .font(.ddName)
                            .foregroundStyle(Color.ddForestInk)
                            .lineLimit(1)
                        if row.isMe {
                            Text("deg").ddEyebrow()
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Scorekortet til \(row.name)")

                if row.editable || row.saved != nil {
                    Text("\(row.strokesReceived) slag fått")
                        .font(.ddMonoSmall)
                        .foregroundStyle(Color.ddInkSecondary)
                }
                result
                if let calculation = row.calculation {
                    Text(calculation)
                        .font(.ddMonoSmall)
                        .monospacedDigit()
                        .foregroundStyle(Color.ddInkSecondary)
                }
            }
            Spacer(minLength: 4)
            if row.editable {
                stepper
            } else {
                Text(row.saved.map(String.init) ?? "—")
                    .font(.ddStrokes)
                    .monospacedDigit()
                    .foregroundStyle(row.saved == nil ? Color.ddHairline : Color.ddForestInk)
                    .frame(minWidth: 46, alignment: .trailing)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, row.isMe ? 10 : 0)
        // Din rad har en svak gulltone, som i PWA-en.
        .background(row.isMe ? Color.ddYouRow : Color.clear, in: .rect(cornerRadius: 16))
        .padding(.horizontal, row.isMe ? -10 : 0)
    }

    @ViewBuilder
    private var result: some View {
        if let name = row.scoreName {
            HStack(spacing: 8) {
                ScoreChip(name: name)
                if let points = row.points {
                    Text("\(points) p")
                        .font(.ddCallout)
                        .monospacedDigit()
                        .foregroundStyle(Color.ddInkSecondary)
                }
                if isPending && !row.editable {
                    Text("ikke lagret ennå").font(.ddCaption).ddWarningStyle()
                }
            }
        } else if row.editable && !row.confirmed {
            DDChip("Par? trykk tallet", tone: .earth, compact: true)
                .foregroundStyle(Color.ddInkSecondary)
                .accessibilityHidden(true)
        } else if !row.editable {
            Text("ikke lagret ennå")
                .font(.ddCaption)
                .foregroundStyle(Color.ddInkSecondary)
        }
    }

    private var stepper: some View {
        HStack(spacing: 6) {
            Button {
                onStep(-1, row.memberID)
            } label: {
                Image(systemName: "minus")
            }
            .buttonStyle(DDStepperButtonStyle(kind: .minus))
            .accessibilityLabel("Ett slag mindre for \(row.name)")

            Button {
                onConfirm(row.memberID)
            } label: {
                DDStrokeValue(value: "\(row.value)", confirmed: row.confirmed)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(row.confirmed ? "\(row.value) slag" : "Bekreft par \(row.value)")

            Button {
                onStep(1, row.memberID)
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(DDStepperButtonStyle(kind: .plus))
            .accessibilityLabel("Ett slag mer for \(row.name)")
        }
        .sensoryFeedback(.selection, trigger: row.value)
    }
}

/// Eagle, Birdie, Par, Bogey, Dobbel, Blowup (fargene fra designsystemet).
struct ScoreChip: View {
    let name: ScoreName
    var text: String?

    var body: some View {
        DDChip(text ?? name.label, tone: name.tone, compact: true)
    }
}
