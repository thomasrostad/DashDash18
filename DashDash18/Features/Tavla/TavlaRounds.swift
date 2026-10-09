import GolfgutuCore
import SwiftUI

/// «Alle runder» (09.10.2026, Thomas: «se hva de andre har slått på rundene sine, slik som i PGA»):
/// tabellens spillere nedover, turneringens runder bortover, stablefordpoengene i hver rute og
/// scorekortet bak hver rute.
nonisolated struct TavlaRoundGrid: Equatable, Sendable {
    struct Column: Identifiable, Hashable, Sendable {
        let roundID: UUID
        /// «1», «2», … i rekkefølge.
        let label: String
        /// «8.10».
        let date: String?
        let title: String
        let isOngoing: Bool
        var id: UUID { roundID }
    }

    struct Row: Identifiable, Hashable, Sendable {
        let memberID: UUID
        let name: String
        let place: Int
        /// Stablefordpoeng per kolonne, nil når spilleren ikke var med.
        let points: [Int?]
        let slag: [Int?]
        var id: UUID { memberID }
        var total: Int { points.compactMap { $0 }.reduce(0, +) }
    }

    let columns: [Column]
    let rows: [Row]
}

nonisolated extension TavlaStandings {
    /// Rundene i rekkefølge (dato, så rundenummer) med poeng og slag for hver spiller i tabellen.
    var roundGrid: TavlaRoundGrid {
        let order = snapshots.indices.sorted { a, b in
            let (sa, sb) = (snapshots[a], snapshots[b])
            if (sa.eventDate ?? "") != (sb.eventDate ?? "") { return (sa.eventDate ?? "") < (sb.eventDate ?? "") }
            return sa.round.roundNo < sb.round.roundNo
        }
        let columns = order.enumerated().map { n, i in
            let s = snapshots[i]
            return TavlaRoundGrid.Column(roundID: s.round.id, label: "\(n + 1)", date: s.eventDate.map(Self.shortDate),
                                         title: roundTitle(i), isOngoing: s.round.status == .active)
        }
        let gridRows = rows.map { row in
            let pid = row.memberID.uuidString
            return TavlaRoundGrid.Row(
                memberID: row.memberID, name: row.name, place: row.place,
                points: order.map { season.roundPoints($0)[pid] },
                slag: order.map { i in
                    let scores = season.rounds[i].holeScores[pid] ?? [:]
                    return scores.isEmpty ? nil : scores.values.reduce(0, +)
                })
        }
        return TavlaRoundGrid(columns: columns, rows: gridRows)
    }

    /// Runden bak en rute, til scorekortet.
    func game(_ roundID: UUID) -> RoundGame? {
        snapshots.first { $0.round.id == roundID }.map(RoundGame.init)
    }

    /// «2026-10-08» → «8.10».
    static func shortDate(_ date: String) -> String {
        let parts = date.split(separator: "-")
        guard parts.count == 3, let d = Int(parts[2]), let m = Int(parts[1]) else { return date }
        return "\(d).\(m)"
    }
}

/// Hvilken spiller i hvilken runde scorekortet viser.
struct RoundScorecardTarget: Identifiable {
    let roundID: UUID
    let memberID: UUID
    var id: String { roundID.uuidString + memberID.uuidString }
}

/// «Alle runder»: leaderboardet. Navnene står fast til venstre; rundene rulles sideveis.
struct TavlaRoundsView: View {
    let standings: TavlaStandings
    @State private var showsStrokes = false
    @State private var scorecard: RoundScorecardTarget?

    var body: some View {
        let grid = standings.roundGrid
        ScrollView {
            VStack(alignment: .leading, spacing: DDSpacing.m) {
                DDSegmentedControl([(false, "Poeng"), (true, "Slag")], selection: $showsStrokes)
                    .accessibilityLabel("Vis")
                if grid.columns.isEmpty {
                    Text("Rundene dukker opp her når den første er spilt.")
                        .font(.ddCallout)
                        .foregroundStyle(Color.ddInkSecondary)
                        .frame(maxWidth: .infinity)
                        .ddCard(.empty)
                } else {
                    HStack(alignment: .top, spacing: 0) {
                        // Fast kolonne: plass og navn.
                        VStack(alignment: .leading, spacing: 0) {
                            headerCell("Spiller", alignment: .leading)
                            ForEach(grid.rows) { row in
                                HStack(spacing: 6) {
                                    Text("\(row.place).")
                                        .font(.ddMonoSmall)
                                        .foregroundStyle(Color.ddInkSecondary)
                                        .frame(width: 26, alignment: .trailing)
                                    Text(row.name)
                                        .font(.ddBody)
                                        .lineLimit(1)
                                }
                                .frame(height: 44, alignment: .leading)
                            }
                        }
                        .frame(width: 124, alignment: .leading)
                        ScrollView(.horizontal, showsIndicators: false) {
                            VStack(alignment: .leading, spacing: 0) {
                                HStack(spacing: 0) {
                                    ForEach(grid.columns) { column in
                                        VStack(spacing: 0) {
                                            Text(column.label).font(.ddChip)
                                            Text(column.date ?? "").font(.ddCaption)
                                                .foregroundStyle(Color.ddInkSecondary)
                                        }
                                        .frame(width: 52, height: 44)
                                        .accessibilityLabel(column.title)
                                    }
                                    headerCell("Sum", alignment: .center).frame(width: 56)
                                }
                                ForEach(grid.rows) { row in
                                    HStack(spacing: 0) {
                                        ForEach(Array(grid.columns.enumerated()), id: \.element.id) { n, column in
                                            cell(row: row, n: n, column: column)
                                        }
                                        Text(showsStrokes ? "" : "\(row.total)")
                                            .font(.ddBodyEmphasis)
                                            .monospacedDigit()
                                            .frame(width: 56, height: 44)
                                    }
                                }
                            }
                        }
                    }
                    .ddCard(padding: DDSpacing.m)
                    DDFooter("Trykk på en rute for scorekortet: slag og poeng hull for hull.")
                }
            }
            .padding(.horizontal, DDSpacing.gutter)
            .padding(.vertical, DDSpacing.l)
        }
        .navigationTitle("Alle runder")
        .ddNavigationChrome()
        .sheet(item: $scorecard) { target in
            if let game = standings.game(target.roundID) {
                ScorekortSheet(game: game, memberID: target.memberID)
            }
        }
    }

    private func headerCell(_ text: String, alignment: Alignment) -> some View {
        Text(text)
            .ddEyebrow()
            .frame(maxWidth: .infinity, minHeight: 44, alignment: alignment)
    }

    @ViewBuilder
    private func cell(row: TavlaRoundGrid.Row, n: Int, column: TavlaRoundGrid.Column) -> some View {
        let value = showsStrokes ? row.slag[n] : row.points[n]
        if let value {
            Button {
                scorecard = RoundScorecardTarget(roundID: column.roundID, memberID: row.memberID)
            } label: {
                Text("\(value)")
                    .font(.ddNumber)
                    .monospacedDigit()
                    .foregroundStyle(column.isOngoing ? Color.ddForestInk : Color.ddInk)
                    .frame(width: 52, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(row.name), \(column.title): \(value) \(showsStrokes ? "slag" : "poeng")")
        } else {
            Text("–")
                .foregroundStyle(Color.ddInkSecondary)
                .frame(width: 52, height: 44)
                .accessibilityLabel("\(row.name), \(column.title): ikke med")
        }
    }
}
