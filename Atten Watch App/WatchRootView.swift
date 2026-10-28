import SwiftUI

/// Runden som går: føringen av hullet, og «Bayen nå» under (vertikale sider). Uten runde: hvor den
/// kommer fra.
struct WatchRootView: View {
    let model: WatchModel

    var body: some View {
        NavigationStack {
            if let round = model.round, let hole = model.currentHole {
                TabView {
                    WatchHoleView(model: model, round: round, hole: hole)
                    WatchStandingsView(round: round)
                }
                .tabViewStyle(.verticalPage)
            } else {
                WatchNoRoundView()
            }
        }
    }
}

struct WatchNoRoundView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "figure.golf")
                .font(.title2)
                .foregroundStyle(WatchPalette.yellow)
            Text("Ingen runde nå")
                .font(.headline)
            Text("Åpne runden i Atten på telefonen, så kommer den hit.")
                .font(.footnote)
                .foregroundStyle(WatchPalette.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

/// Hullet: én rad per spiller du fører for. Trykk velger raden, Digital Crown endrer tallet, og
/// knappen (eller dobbelttrykk med fingrene) lagrer og går videre.
struct WatchHoleView: View {
    let model: WatchModel
    let round: WatchRound
    let hole: WatchRound.Hole

    @State private var crown = 0.0

    private var selectedRow: WatchRound.Row? {
        hole.rows.first { $0.memberID == model.selected && $0.editable }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(WatchPalette.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if model.waitingCount > 0 {
                    Text(model.waitingCount == 1 ? "1 hull venter på telefonen" : "\(model.waitingCount) hull venter på telefonen")
                        .font(.caption2)
                        .foregroundStyle(WatchPalette.rust)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(hole.rows) { row in
                    Button {
                        if row.editable { model.selected = row.memberID }
                    } label: {
                        WatchHoleRow(row: row, value: model.value(row), isDefault: model.isDefault(row),
                                     isSelected: row.memberID == selectedRow?.memberID)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("Hull \(hole.number)")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { model.go(to: hole.index - 1) } label: { Image(systemName: "chevron.left") }
                    .disabled(hole.index == round.holes.first?.index)
                    .accessibilityLabel("Forrige hull")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { model.go(to: hole.index + 1) } label: { Image(systemName: "chevron.right") }
                    .disabled(hole.index == round.holes.last?.index)
                    .accessibilityLabel("Neste hull")
            }
            // Alltid synlig, også når båsen har fire rader: Digital Crown endrer tallet, ikke siden.
            if hole.rows.contains(where: \.editable) {
                ToolbarItem(placement: .bottomBar) {
                    Button { model.primaryAction() } label: {
                        Label(model.primaryTitle, systemImage: model.isCurrentHoleDone && model.drafts.isEmpty
                              ? "arrow.right" : "checkmark")
                    }
                    .tint(WatchPalette.yellow)
                    .handGestureShortcut(.primaryAction)
                }
            }
        }
        .focusable()
        .digitalCrownRotation($crown, from: Double(selectedRow?.options.first?.strokes ?? 1),
                              through: Double(selectedRow?.options.last?.strokes ?? 12), by: 1,
                              sensitivity: .low, isContinuous: false, isHapticFeedbackEnabled: true)
        .onChange(of: crown) { _, new in
            guard let row = selectedRow, Int(new.rounded()) != model.value(row) else { return }
            model.set(Int(new.rounded()), for: row)
        }
        .onChange(of: model.selected, initial: true) { syncCrown() }
        .onChange(of: hole.index) { syncCrown() }
    }

    /// «Par 4 · indeks 11», som på hullkortet.
    private var detail: String {
        hole.strokeIndex.map { "Par \(hole.par) · indeks \($0)" } ?? "Par \(hole.par)"
    }

    private func syncCrown() {
        if let row = selectedRow { crown = Double(model.value(row)) }
    }
}

struct WatchHoleRow: View {
    let row: WatchRound.Row
    let value: Int
    let isDefault: Bool
    let isSelected: Bool

    var body: some View {
        let option = row.option(value)
        HStack(alignment: .center, spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 3) {
                    Text(row.name)
                        .font(.footnote.weight(row.isMe ? .semibold : .regular))
                        .lineLimit(1)
                    if row.strokesReceived > 0 {
                        Text(String(repeating: "•", count: min(row.strokesReceived, 3)))
                            .font(.caption2)
                            .foregroundStyle(WatchPalette.rust)
                            .accessibilityLabel(row.strokesReceived == 1 ? "1 slag" : "\(row.strokesReceived) slag")
                    }
                }
                Text(isDefault ? "forvalgt par" : (option?.text ?? ""))
                    .font(.caption2)
                    .foregroundStyle(isDefault ? WatchPalette.secondary : WatchPalette.tone(option?.tone))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
            Text("\(value)")
                .font(.title2.monospacedDigit().weight(.semibold))
                .foregroundStyle(isDefault ? WatchPalette.secondary : .primary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(isSelected ? WatchPalette.youRow : Color.white.opacity(0.08), in: .rect(cornerRadius: 10))
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 10).strokeBorder(WatchPalette.yellow, lineWidth: 1.5)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue("\(value) slag")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// «Bayen nå» for båsen din, slik telefonen regner den.
struct WatchStandingsView: View {
    let round: WatchRound

    var body: some View {
        List(round.standings) { standing in
            HStack(spacing: 6) {
                Text(standing.place.map { "\($0)." } ?? "–")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(WatchPalette.secondary)
                    .frame(width: 22, alignment: .leading)
                VStack(alignment: .leading, spacing: 1) {
                    Text(standing.name)
                        .font(.footnote.weight(standing.isMe ? .semibold : .regular))
                        .foregroundStyle(standing.isMe ? WatchPalette.yellow : .primary)
                        .lineLimit(1)
                    Text(standing.thru == 1 ? "1 hull" : "\(standing.thru) hull")
                        .font(.caption2)
                        .foregroundStyle(WatchPalette.secondary)
                }
                Spacer(minLength: 0)
                Text(standing.value)
                    .font(.footnote.monospacedDigit().weight(.semibold))
            }
        }
        .navigationTitle("Bayen nå")
    }
}
