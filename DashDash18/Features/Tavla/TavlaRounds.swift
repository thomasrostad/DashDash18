import GolfgutuCore
import SwiftUI

/// «Alle runder» (09.10.2026, Thomas: «se hva de andre har slått på rundene sine, slik som i PGA» og
/// «den må være perfekt»): tabellens spillere nedover, turneringens runder bortover, poeng eller slag
/// i hver rute, og scorekortet bak hver rute. Samme for Tavla (sesongen) og for liga og morro.
nonisolated struct RoundsGrid: Equatable, Sendable {
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
        /// Spiller-id-en i rundene (medlem, eller personen bak i liga og morro).
        let playerID: UUID
        let name: String
        let place: String
        let isMe: Bool
        /// Stablefordpoeng per kolonne, nil når spilleren ikke var med.
        let points: [Int?]
        /// Slag per kolonne (bare førte hull).
        let strokes: [Int?]
        /// Slag i forhold til par på de førte hullene, per kolonne.
        let toPar: [Int?]
        /// Teller runden i tabellen? (Liga og morro med «beste N».) nil: alle teller.
        let counted: [Bool]?
        var id: UUID { playerID }
        var pointsTotal: Int { points.compactMap(\.self).reduce(0, +) }
        var strokesTotal: Int { strokes.compactMap(\.self).reduce(0, +) }
        var toParTotal: Int { toPar.compactMap(\.self).reduce(0, +) }
    }

    let columns: [Column]
    let rows: [Row]

    /// Beste poeng og laveste slag per kolonne (uthevet i lista). nil uten verdier.
    var bestPoints: [Int?] { columns.indices.map { n in rows.compactMap { $0.points[n] }.max() } }
    var bestStrokes: [Int?] { columns.indices.map { n in rows.compactMap { $0.strokes[n] }.min() } }

    /// «+3», «E», «−2» (PGA-skrivemåten).
    static func toParText(_ x: Int) -> String {
        x == 0 ? "E" : x > 0 ? "+\(x)" : "−\(-x)"
    }

    /// «2026-10-08» → «8.10».
    static func shortDate(_ date: String) -> String {
        let parts = date.split(separator: "-")
        guard parts.count == 3, let d = Int(parts[2]), let m = Int(parts[1]) else { return date }
        return "\(d).\(m)"
    }

    /// Bygger rutenettet fra rundene (samme rekkefølge som regelmotorens `Season`), poengene per runde
    /// og tabellens rader.
    static func make(snapshots: [RoundSnapshot], season: Season, title: (Int) -> String,
                     rows: [(playerID: UUID, name: String, place: String, isMe: Bool, counted: Set<UUID>?)]) -> RoundsGrid {
        let order = snapshots.indices.sorted { a, b in
            let (sa, sb) = (snapshots[a], snapshots[b])
            if (sa.eventDate ?? "") != (sb.eventDate ?? "") { return (sa.eventDate ?? "") < (sb.eventDate ?? "") }
            return sa.round.roundNo < sb.round.roundNo
        }
        let columns = order.enumerated().map { n, i in
            let s = snapshots[i]
            return Column(roundID: s.round.id, label: "\(n + 1)", date: s.eventDate.map(shortDate),
                          title: title(i), isOngoing: s.round.status == .active)
        }
        let gridRows = rows.map { row in
            let pid = row.playerID.uuidString
            var strokes: [Int?] = []
            var toPar: [Int?] = []
            for i in order {
                let round = season.rounds[i]
                let scores = round.holeScores[pid] ?? [:]
                if scores.isEmpty {
                    strokes.append(nil); toPar.append(nil)
                } else {
                    let holes = round.courseHoles()
                    let par = scores.keys.reduce(0) { $0 + ($1 >= 0 && $1 < holes.count ? holes[$1].par : 0) }
                    let sum = scores.values.reduce(0, +)
                    strokes.append(sum); toPar.append(sum - par)
                }
            }
            return Row(playerID: row.playerID, name: row.name, place: row.place, isMe: row.isMe,
                       points: order.map { season.roundPoints($0)[pid] }, strokes: strokes, toPar: toPar,
                       counted: row.counted.map { set in order.map { set.contains(snapshots[$0].round.id) } })
        }
        return RoundsGrid(columns: columns, rows: gridRows)
    }
}

nonisolated extension TavlaStandings {
    var roundGrid: RoundsGrid {
        RoundsGrid.make(snapshots: snapshots, season: season, title: roundTitle,
                        rows: rows.map { ($0.memberID, $0.name, "\($0.place).", $0.isMe, nil) })
    }

    /// Runden bak en rute, til scorekortet.
    func game(_ roundID: UUID) -> RoundGame? {
        snapshots.first { $0.round.id == roundID }.map(RoundGame.init)
    }
}

/// Hvilken spiller i hvilken runde scorekortet viser.
struct RoundScorecardTarget: Identifiable {
    let roundID: UUID
    let memberID: UUID
    var id: String { roundID.uuidString + memberID.uuidString }
}

/// Tavla: «Alle runder» for sesongen.
struct TavlaRoundsView: View {
    let standings: TavlaStandings

    var body: some View {
        RoundsLeaderboardView(grid: standings.roundGrid, game: standings.game)
    }
}

/// Leaderboardet. Plass og navn står fast til venstre; rundene rulles sideveis. Poeng, slag eller
/// i forhold til par. Beste resultat i hver runde er uthevet, din rad er markert, en runde som
/// pågår har en prikk, og runder som ikke teller (beste N) er dempet.
struct RoundsLeaderboardView: View {
    enum Mode: Hashable { case points, strokes, toPar }

    let grid: RoundsGrid
    let game: (UUID) -> RoundGame?
    @State private var mode: Mode = .points
    @State private var scorecard: RoundScorecardTarget?

    private let rowHeight: CGFloat = 44
    private let cellWidth: CGFloat = 50

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DDSpacing.m) {
                DDSegmentedControl([(Mode.points, "Poeng"), (.strokes, "Slag"), (.toPar, "Mot par")], selection: $mode)
                    .accessibilityLabel("Vis")
                if grid.columns.isEmpty {
                    Text("Rundene dukker opp her når den første er spilt.")
                        .font(.ddCallout)
                        .foregroundStyle(Color.ddInkSecondary)
                        .frame(maxWidth: .infinity)
                        .ddCard(.empty)
                } else {
                    table
                        .ddCard(padding: DDSpacing.m)
                    DDFooter(footer)
                }
            }
            .padding(.horizontal, DDSpacing.gutter)
            .padding(.vertical, DDSpacing.l)
        }
        .navigationTitle("Alle runder")
        .ddNavigationChrome()
        .sheet(item: $scorecard) { target in
            if let game = game(target.roundID) {
                ScorekortSheet(game: game, memberID: target.memberID)
            }
        }
    }

    private var footer: String {
        var text = "Trykk på en rute for scorekortet: slag og poeng hull for hull."
        if grid.rows.contains(where: { $0.counted != nil }) { text += " Dempede runder teller ikke i tabellen." }
        if mode != .points { text += " Slag gjelder hullene som er ført." }
        return text
    }

    private var table: some View {
        HStack(alignment: .top, spacing: 0) {
            // Fast kolonne: plass og navn.
            VStack(alignment: .leading, spacing: 0) {
                Text("Spiller")
                    .ddEyebrow()
                    .frame(maxWidth: .infinity, minHeight: rowHeight, alignment: .leading)
                ForEach(grid.rows) { row in
                    HStack(spacing: 6) {
                        Text(row.place)
                            .font(.ddMonoSmall)
                            .monospacedDigit()
                            .foregroundStyle(Color.ddInkSecondary)
                            .frame(width: 28, alignment: .trailing)
                        Text(row.name)
                            .font(row.isMe ? .ddBodyEmphasis : .ddBody)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    .frame(maxWidth: .infinity, minHeight: rowHeight, alignment: .leading)
                    .background(row.isMe ? Color.ddYouRow : .clear)
                }
            }
            .frame(width: 112, alignment: .leading)
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 0) {
                        ForEach(grid.columns) { column in
                            VStack(spacing: 1) {
                                HStack(spacing: 3) {
                                    Text(column.label).font(.ddChip)
                                    if column.isOngoing {
                                        Circle().fill(Color.ddRust).frame(width: 6, height: 6)
                                            .accessibilityLabel("pågår")
                                    }
                                }
                                Text(column.date ?? "").font(.ddCaption).foregroundStyle(Color.ddInkSecondary)
                            }
                            .frame(width: cellWidth, height: rowHeight)
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel(column.title + (column.isOngoing ? ", pågår" : ""))
                        }
                    }
                    ForEach(grid.rows) { row in
                        HStack(spacing: 0) {
                            ForEach(Array(grid.columns.enumerated()), id: \.element.id) { n, column in
                                cell(row: row, n: n, column: column)
                            }
                        }
                        .background(row.isMe ? Color.ddYouRow : .clear)
                    }
                }
            }
            // Fast kolonne til høyre: summen står alltid synlig, som på et leaderboard.
            VStack(spacing: 0) {
                Text("Sum")
                    .ddEyebrow()
                    .frame(width: 56, height: rowHeight)
                ForEach(grid.rows) { row in
                    Text(total(row))
                        .font(.ddBodyEmphasis)
                        .monospacedDigit()
                        .frame(width: 56, height: rowHeight)
                        .background(row.isMe ? Color.ddYouRow : .clear)
                }
            }
            .overlay(alignment: .leading) {
                Rectangle().fill(Color.ddRule).frame(width: 1).accessibilityHidden(true)
            }
        }
    }

    private func total(_ row: RoundsGrid.Row) -> String {
        switch mode {
        case .points: "\(row.pointsTotal)"
        case .strokes: row.strokes.contains { $0 != nil } ? "\(row.strokesTotal)" : "–"
        case .toPar: row.toPar.contains { $0 != nil } ? RoundsGrid.toParText(row.toParTotal) : "–"
        }
    }

    private func value(_ row: RoundsGrid.Row, _ n: Int) -> (text: String, best: Bool)? {
        switch mode {
        case .points:
            guard let p = row.points[n] else { return nil }
            return ("\(p)", p == grid.bestPoints[n])
        case .strokes:
            guard let s = row.strokes[n] else { return nil }
            return ("\(s)", s == grid.bestStrokes[n])
        case .toPar:
            guard let t = row.toPar[n] else { return nil }
            return (RoundsGrid.toParText(t), row.strokes[n] == grid.bestStrokes[n])
        }
    }

    @ViewBuilder
    private func cell(row: RoundsGrid.Row, n: Int, column: RoundsGrid.Column) -> some View {
        if let value = value(row, n) {
            let counts = row.counted?[n] ?? true
            Button {
                scorecard = RoundScorecardTarget(roundID: column.roundID, memberID: row.playerID)
            } label: {
                Text(value.text)
                    .font(value.best ? .ddBodyEmphasis : .ddNumber)
                    .monospacedDigit()
                    .foregroundStyle(Color.ddInk)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    // Beste i runden: gul markering, som birdie-merket på scorekortet.
                    .background(value.best ? Color.ddGold : .clear, in: .capsule)
                    .opacity(counts ? 1 : 0.4)
                    .frame(width: cellWidth, height: rowHeight)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(row.name), \(column.title): \(value.text)"
                                + (value.best ? ", best i runden" : "") + (counts ? "" : ", teller ikke"))
            .accessibilityHint("Viser scorekortet")
        } else {
            Text("–")
                .foregroundStyle(Color.ddInkSecondary)
                .frame(width: cellWidth, height: rowHeight)
                .accessibilityLabel("\(row.name), \(column.title): ikke med")
        }
    }
}
