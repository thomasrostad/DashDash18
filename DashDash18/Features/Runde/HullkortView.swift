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
            .font(.caption.weight(.semibold))
            .textCase(.uppercase)
            .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                ForEach(card.rows) { row in
                    HullRadView(row: row, isPending: isPending, onStep: onStep, onConfirm: onConfirm,
                                onName: { onScorecard(row.memberID) })
                    if row.id != card.rows.last?.id { Divider() }
                }
            }

            if card.showsParHint {
                Text("Stiplet tall er par. Trykk tallet for å bekrefte det.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let outside = card.outsideTruncation {
                Text(outside)
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            if isPending {
                Label("Hullet er ikke lagret ennå. Det sendes når du har dekning.", systemImage: "icloud.and.arrow.up")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
            if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            actionView
            if let hint = card.viewerHint {
                Text(hint)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if card.holeIndex > 0 {
                Button("‹ Forrige hull") { onGoTo(card.holeIndex - 1) }
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(16)
        .background(.background.secondary, in: .rect(cornerRadius: 16))
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(card.title)
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                Text(card.detail)
                    .font(.title3.bold())
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                if card.isLongestDrive {
                    Label("Longest drive", systemImage: "ruler")
                        .modifier(TagStyle())
                }
                if card.isClosestToPin {
                    Label("Nærmest pinnen", systemImage: "scope")
                        .modifier(TagStyle())
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
                    if isSaving { ProgressView() } else { Text(title) }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!enabled || isSaving)
            if let blocker {
                Text(blocker)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        case .next(let title, let hole):
            Button(title) { onGoTo(hole) }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
        case .scorecard:
            Button("Alle hull er lagret · se scorekortet →") { onScorecard(nil) }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
        case .none:
            EmptyView()
        }
    }
}

private struct TagStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.yellow.opacity(0.3), in: .capsule)
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
            VStack(alignment: .leading, spacing: 3) {
                Button(action: onName) {
                    HStack(spacing: 6) {
                        Text(row.name).font(.body.weight(.semibold))
                        if row.isMe {
                            Text("deg")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(.green.opacity(0.18), in: .capsule)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Scorekortet til \(row.name)")

                if row.editable || row.saved != nil {
                    Text("\(row.strokesReceived) slag fått")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                result
                if let calculation = row.calculation {
                    Text(calculation)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 4)
            if row.editable {
                stepper
            } else {
                Text(row.saved.map(String.init) ?? "—")
                    .font(.title2.monospacedDigit().bold())
                    .foregroundStyle(row.saved == nil ? .secondary : .primary)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, row.isMe ? 8 : 0)
        .background(row.isMe ? AnyShapeStyle(.green.opacity(0.06)) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 10))
    }

    @ViewBuilder
    private var result: some View {
        if let name = row.scoreName {
            HStack(spacing: 6) {
                ScoreChip(name: name)
                if let points = row.points {
                    Text("\(points) p").font(.caption.monospacedDigit().weight(.semibold))
                }
                if isPending && !row.editable {
                    Text("ikke lagret ennå").font(.caption).foregroundStyle(.orange)
                }
            }
        } else if !row.editable {
            Text("ikke lagret ennå")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var stepper: some View {
        HStack(spacing: 6) {
            Button {
                onStep(-1, row.memberID)
            } label: {
                Image(systemName: "minus")
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .accessibilityLabel("Ett slag mindre for \(row.name)")

            Button {
                onConfirm(row.memberID)
            } label: {
                Text("\(row.value)")
                    .font(.title2.monospacedDigit().bold())
                    .frame(width: 44, height: 44)
                    .foregroundStyle(row.confirmed ? .primary : .secondary)
                    .overlay {
                        if !row.confirmed {
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                                .foregroundStyle(.secondary)
                        }
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(row.confirmed ? "\(row.value) slag" : "Bekreft par \(row.value)")

            Button {
                onStep(1, row.memberID)
            } label: {
                Image(systemName: "plus")
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .accessibilityLabel("Ett slag mer for \(row.name)")
        }
        .sensoryFeedback(.selection, trigger: row.value)
    }
}

/// Eagle, Birdie, Par, Bogey, Dobbel, Blowup.
struct ScoreChip: View {
    let name: ScoreName
    var text: String?

    var body: some View {
        Text(text ?? name.label)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(color.opacity(0.22), in: .capsule)
    }

    private var color: Color {
        switch name {
        case .eagle: .yellow
        case .birdie: .green
        case .par: .gray
        case .bogey: .orange
        case .dobbel: .red
        case .blowup: .purple
        }
    }
}
