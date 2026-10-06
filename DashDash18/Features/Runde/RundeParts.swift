import GolfgutuCore
import SwiftUI

/// Hullprikkene: ferdig, delvis, kommende, nåværende, LD/KP og båsens hull.
struct HullprikkerView: View {
    let dots: [HoleDot]
    let onSelect: (Int) -> Void

    var body: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 9)
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(dots) { dot in
                Button { onSelect(dot.index) } label: {
                    ZStack {
                        Circle()
                            .fill(fill(dot))
                        if dot.isPending {
                            Circle().strokeBorder(.orange, style: StrokeStyle(lineWidth: 2, dash: [3, 2]))
                        }
                        if dot.isCurrent {
                            Circle().strokeBorder(.primary, lineWidth: 2)
                        }
                        Text("\(dot.number)")
                            .font(.caption2.monospacedDigit().weight(dot.isCurrent ? .bold : .regular))
                            .foregroundStyle(dot.state == .done ? .white : .primary)
                    }
                    .frame(height: 30)
                    .overlay(alignment: .topTrailing) {
                        if dot.isLongestDrive || dot.isClosestToPin {
                            Circle().fill(dot.isLongestDrive ? .yellow : .blue).frame(width: 7, height: 7)
                        }
                    }
                    .overlay(alignment: .bottom) {
                        if dot.isBayHole {
                            Circle().fill(.orange).frame(width: 5, height: 5).offset(y: 5)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(dot.accessibilityLabel)
                .accessibilityAddTraits(dot.isCurrent ? .isSelected : [])
            }
        }
    }

    private func fill(_ dot: HoleDot) -> Color {
        switch dot.state {
        case .done: .green
        case .partial: .green.opacity(0.35)
        case .upcoming: .secondary.opacity(0.15)
        }
    }
}

/// «Bayen nå»: alle i kvelden, flest poeng først.
struct BayenNaaSection: View {
    let rows: [StandingRow]
    let onSelect: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Bayen nå")
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                    Button { onSelect(row.memberID) } label: {
                        HStack(spacing: 10) {
                            Text("\(i + 1).")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 28, alignment: .leading)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(row.name + (row.isMe ? " (deg)" : ""))
                                    .font(.body.weight(row.isMe ? .semibold : .regular))
                                Text("thru \(row.thru)" + (row.bay.map { " · bås \($0)" } ?? ""))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(row.total)")
                                .font(.title3.monospacedDigit().bold())
                        }
                        .padding(.vertical, 8)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityHint("Åpner scorekortet")
                    if i < rows.count - 1 { Divider() }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
            .background(.background.secondary, in: .rect(cornerRadius: 16))
        }
    }
}

/// Scorekortet til én spiller: Ut/Inn, par, slag og poeng per hull, sum.
struct ScorekortSheet: View {
    let game: RoundGame
    let memberID: UUID
    @State private var inward = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let card = game.scorecard(for: memberID, inward: inward)
        NavigationStack {
            List {
                if game.hasInward {
                    Picker("Side", selection: $inward) {
                        Text("Ut · \(game.holeNumber(0))–\(game.holeNumber(8))").tag(false)
                        Text("Inn · \(game.holeNumber(9))–\(game.holeNumber(min(17, game.holeCount - 1)))").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                }
                Section {
                    row("Hull", "Par", "Slag", nil, header: true)
                    ForEach(card.lines) { line in
                        row("\(line.number)", "\(line.par)", line.strokes.map(String.init) ?? "—", line)
                    }
                    row("Sum", "\(card.sumPar)", card.sumStrokes > 0 ? "\(card.sumStrokes)" : "—", nil,
                        sum: card.sumPoints)
                } header: {
                    Text((game.snapshot.course?.name ?? "Runden") + " · " + (card.inward ? "Inn" : "Ut"))
                }
                Section {
                    LabeledContent("Totalt i runden", value: "\(game.total(memberID)) poeng")
                }
            }
            .navigationTitle(card.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ferdig") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func row(_ hole: String, _ par: String, _ strokes: String, _ line: Scorecard.Line?,
                     header: Bool = false, sum: Int? = nil) -> some View {
        HStack {
            Text(hole).frame(width: 44, alignment: .leading)
            Text(par).frame(width: 40)
            Text(strokes).frame(width: 44)
            Spacer()
            if header {
                Text("Poeng")
            } else if let sum {
                Text("\(sum)").bold()
            } else if let line, let name = line.scoreName, let points = line.points {
                ScoreChip(name: name, text: "\(points)")
            } else {
                Text("—").foregroundStyle(.secondary)
            }
        }
        .font(header ? .caption.weight(.semibold) : .body.monospacedDigit())
        .foregroundStyle(header ? .secondary : .primary)
        .accessibilityElement(children: .combine)
    }
}

/// «Stemmer dette med skjermen?» før første hull.
struct ParBekreftelseCard: View {
    let game: RoundGame
    let canConfirm: Bool
    let onConfirm: () async throws -> Void
    @State private var isBusy = false
    @State private var error: String?

    var body: some View {
        let holes = game.holes
        let odd = Course.holesWithOddLength(holes)
        VStack(alignment: .leading, spacing: 10) {
            Text("Før dere begynner")
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            Text("Stemmer dette med skjermen?")
                .font(.title2.bold())
            Text(summary(holes))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 9), spacing: 4) {
                ForEach(holes.indices, id: \.self) { i in
                    VStack(spacing: 0) {
                        Text("\(game.holeNumber(i))").font(.caption2).foregroundStyle(.secondary)
                        Text("\(holes[i].par)").font(.body.monospacedDigit().bold())
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .background(.secondary.opacity(0.1), in: .rect(cornerRadius: 6))
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Hull \(game.holeNumber(i)), par \(holes[i].par)")
                }
            }
            if !odd.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text(odd.count == 1 ? "Se på dette hullet først:" : "Se på disse hullene først:")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.orange)
                    ForEach(odd, id: \.number) { h in
                        Text("Hull \(game.holeNumber(h.number - 1)) står som par \(h.par ?? 0) på \(HoleMath.meters(h.meters ?? 0)) m")
                            .font(.subheadline)
                    }
                }
            }
            if canConfirm {
                Button {
                    Task {
                        isBusy = true
                        defer { isBusy = false }
                        do { try await onConfirm(); error = nil } catch { self.error = DataError.from(error).message }
                    }
                } label: {
                    Text("Stemmer · start føringen").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isBusy)
            } else {
                Text("En arrangør sjekker parene først · du ser det live.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
            if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .padding(16)
        .background(.background.secondary, in: .rect(cornerRadius: 16))
    }

    private func summary(_ holes: [PlayedHole]) -> String {
        var parts = [game.snapshot.course?.name ?? "Ingen bane", "\(game.holeCount) hull"]
        if game.holeCount == 9 {
            parts.append("hull \(game.holeNumber(0))–\(game.holeNumber(8))")
        }
        parts.append("par \(holes.reduce(0) { $0 + $1.par })")
        var text = parts.joined(separator: " · ")
            + ". Sammenlign med banen som er lastet i båsen. Står det noe annet der, er det skjermen som har rett."
        if let external = game.snapshot.course?.externalName, !external.isEmpty {
            text += " På simulatoren heter banen «\(external)»."
        }
        return text
    }
}
