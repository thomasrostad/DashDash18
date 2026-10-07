import GolfgutuCore
import SwiftUI

/// Hullprikkene: ferdig, delvis, kommende, nåværende, LD/KP og båsens hull.
struct HullprikkerView: View {
    let dots: [HoleDot]
    let onSelect: (Int) -> Void

    var body: some View {
        // Loddrette streker som i PWA-en (`.gg-holedots`), én per hull.
        HStack(spacing: 3) {
            ForEach(dots) { dot in
                Button { onSelect(dot.index) } label: {
                    DDHoleTick(
                        state: progress(dot),
                        isCurrent: dot.isCurrent,
                        marker: dot.isLongestDrive ? .longestDrive : (dot.isClosestToPin ? .closestToPin : .none),
                        isPending: dot.isPending,
                        isBayHole: dot.isBayHole
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(dot.accessibilityLabel)
                .accessibilityAddTraits(dot.isCurrent ? .isSelected : [])
            }
        }
    }

    private func progress(_ dot: HoleDot) -> DDHoleTick.Progress {
        switch dot.state {
        case .done: .played
        case .partial: .partial
        case .upcoming: .upcoming
        }
    }
}

/// «Bayen nå»: alle i kvelden, flest poeng først.
struct BayenNaaSection: View {
    let rows: [StandingRow]
    let onSelect: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            DDSectionLabel("Bayen nå")
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                    Button { onSelect(row.memberID) } label: {
                        HStack(spacing: 10) {
                            Text("\(i + 1).")
                                .font(.ddCallout).monospacedDigit()
                                .foregroundStyle(Color.ddStatSecondary)
                                .frame(width: 28, alignment: .leading)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(row.name + (row.isMe ? " (deg)" : ""))
                                    .font(row.isMe ? .ddBodyEmphasis : .ddBody)
                                    .foregroundStyle(Color.ddStatText)
                                Text("thru \(row.thru)" + (row.bay.map { " · bås \($0)" } ?? ""))
                                    .font(.ddCaption)
                                    .foregroundStyle(Color.ddStatSecondary)
                            }
                            Spacer()
                            Text("\(row.total)")
                                .font(.ddNumberLarge).monospacedDigit()
                                .foregroundStyle(row.isMe ? Color.ddYellow : Color.ddStatText)
                        }
                        .padding(.vertical, 8)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityHint("Åpner scorekortet")
                    if i < rows.count - 1 {
                        Rectangle().fill(Color.ddStatText.opacity(0.12)).frame(height: 1)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .ddCard(.stat, padding: 0)
        }
    }
}

/// Scorekortet til én spiller: Ut/Inn, par, slag og poeng per hull, sum.
/// Svart statistikk-kort med hvite tall og fargede poeng (golfee + PWA-ens score-merker).
struct ScorekortSheet: View {
    let game: RoundGame
    let memberID: UUID
    @State private var inward = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let card = game.scorecard(for: memberID, inward: inward)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DDSpacing.m) {
                    if game.hasInward {
                        DDSegmentedControl([
                            (false, "Ut · \(game.holeNumber(0))–\(game.holeNumber(8))"),
                            (true, "Inn · \(game.holeNumber(9))–\(game.holeNumber(min(17, game.holeCount - 1)))"),
                        ], selection: $inward)
                        .accessibilityLabel("Side")
                    }
                    DDSectionLabel((game.snapshot.course?.name ?? "Runden") + " · " + (card.inward ? "Inn" : "Ut"))
                        .padding(.top, DDSpacing.s)
                    VStack(spacing: 0) {
                        row("Hull", "Par", "Slag", nil, header: true)
                        ForEach(card.lines) { line in
                            rule
                            row("\(line.number)", "\(line.par)", line.strokes.map(String.init) ?? "—", line)
                        }
                        rule
                        row("Sum", "\(card.sumPar)", card.sumStrokes > 0 ? "\(card.sumStrokes)" : "—", nil,
                            sum: card.sumPoints)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .ddCard(.stat, padding: 0)
                    HStack {
                        Text("Totalt i runden")
                        Spacer()
                        Text("\(game.total(memberID)) poeng")
                            .font(.ddNumber)
                            .monospacedDigit()
                            .foregroundStyle(Color.ddForestInk)
                    }
                    .ddCard(.glass)
                    .accessibilityElement(children: .combine)
                }
                .padding(.horizontal, DDSpacing.gutter)
                .padding(.vertical, DDSpacing.l)
            }
            .navigationTitle(card.name)
            .ddNavigationChrome()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ferdig") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Color.ddBackground)
    }

    private var rule: some View {
        Rectangle().fill(Color.ddStatText.opacity(0.12)).frame(height: 1)
    }

    private func row(_ hole: String, _ par: String, _ strokes: String, _ line: Scorecard.Line?,
                     header: Bool = false, sum: Int? = nil) -> some View {
        HStack {
            Text(hole).frame(width: 44, alignment: .leading)
                .font(header ? .ddEyebrow : .ddNumber)
            Text(par).frame(width: 40)
                .foregroundStyle(header ? Color.ddStatSecondary : Color.ddStatSecondary)
            Text(strokes).frame(width: 44)
            Spacer()
            if header {
                Text("Poeng")
            } else if let sum {
                Text("\(sum)")
                    .font(.ddNumberLarge)
                    .foregroundStyle(Color.ddYellow)
            } else if let line, let name = line.scoreName, let points = line.points {
                DDPointsBadge(points: points, name: name)
            } else {
                DDPointsBadge(points: nil, name: nil)
            }
        }
        .font(header ? .ddEyebrow : .ddBody)
        .monospacedDigit()
        .textCase(header ? .uppercase : nil)
        .tracking(header ? 1.2 : 0)
        .foregroundStyle(header ? Color.ddStatSecondary : Color.ddStatText)
        .frame(minHeight: header ? 32 : 46)
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
                .ddEyebrow()
            Text("Stemmer dette med skjermen?")
                .font(.ddTitle)
                .foregroundStyle(Color.ddForestInk)
            Text(summary(holes))
                .font(.dd(.sans, size: 14, relativeTo: .subheadline))
                .foregroundStyle(Color.ddInkSecondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 9), spacing: 4) {
                ForEach(holes.indices, id: \.self) { i in
                    VStack(spacing: 0) {
                        Text("\(game.holeNumber(i))").font(.dd(.sans, size: 11, relativeTo: .caption2)).foregroundStyle(Color.ddInkSecondary)
                        Text("\(holes[i].par)").font(.dd(.sans, size: 16, weight: .bold, relativeTo: .body)).monospacedDigit()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Color.ddEarth, in: .rect(cornerRadius: 10))
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Hull \(game.holeNumber(i)), par \(holes[i].par)")
                }
            }
            if !odd.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text(odd.count == 1 ? "Se på dette hullet først:" : "Se på disse hullene først:")
                        .font(.dd(.sans, size: 14, weight: .semibold, relativeTo: .subheadline))
                        .foregroundStyle(Color.ddRustText)
                    ForEach(odd, id: \.number) { h in
                        Text("Hull \(game.holeNumber(h.number - 1)) står som par \(h.par ?? 0) på \(HoleMath.meters(h.meters ?? 0)) m")
                            .font(.dd(.sans, size: 14, relativeTo: .subheadline))
                    }
                }
            }
            if canConfirm {
                Button {
                    guard !isBusy else { return }
                    isBusy = true
                    Task {
                        defer { isBusy = false }
                        do {
                            try await onConfirm()
                            error = nil
                        } catch {
                            self.error = ParConfirmation.message(DataError.from(error))
                        }
                    }
                } label: {
                    Text("Stemmer · start føringen")
                }
                .buttonStyle(.ddPrimary)
                .disabled(isBusy)
            } else {
                Text("Markøren eller arrangøren sjekker parene først · du ser det live.")
                    .font(.dd(.sans, size: 13, relativeTo: .footnote))
                    .foregroundStyle(Color.ddInkSecondary)
                    .frame(maxWidth: .infinity)
            }
            if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.dd(.sans, size: 13, relativeTo: .footnote))
                    .foregroundStyle(Color.ddError)
            }
        }
        .ddCard(.large)
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
