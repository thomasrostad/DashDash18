import Foundation
import GolfgutuCore
import Testing
@testable import DashDash18

/// «Alle runder»: hver spiller i tabellen, hver runde i rekkefølge, poengene fra regelmotoren.
@MainActor struct TavlaRoundsTests {
    @Test func rutenettetFølgerTabellenOgRundene() throws {
        let standings = TavlaSamples.standings()
        let grid = standings.roundGrid
        #expect(grid.rows.map(\.playerID) == standings.rows.map(\.memberID))
        #expect(grid.columns.count == standings.snapshots.count)
        #expect(grid.columns.map(\.label) == (1...grid.columns.count).map(String.init))
        for row in grid.rows {
            #expect(row.points.count == grid.columns.count && row.strokes.count == grid.columns.count)
            // Samme poeng som regelmotoren gir for runden.
            for (n, column) in grid.columns.enumerated() {
                let i = try #require(standings.snapshots.firstIndex { $0.round.id == column.roundID })
                #expect(row.points[n] == standings.season.roundPoints(i)[row.playerID.uuidString])
            }
        }
        let first = try #require(grid.columns.first)
        #expect(standings.game(first.roundID) != nil)
    }

    @Test func kortDato() {
        #expect(RoundsGrid.shortDate("2026-10-08") == "8.10")
        #expect(RoundsGrid.shortDate("x") == "x")
    }
}

@MainActor struct LigaRoundsTests {
    static func standings() throws -> LeagueStandings {
        guard case .league(let s)? = KonkurranseSamples.league().content else { throw CancellationError() }
        return s
    }

    @Test func ligaenFårSammeLeaderboard() throws {
        let s = try Self.standings()
        let grid = s.roundGrid
        #expect(grid.columns.count == s.roundCount)
        #expect(grid.rows.map(\.name) == s.rows.map(\.name))
        for row in grid.rows {
            for (n, column) in grid.columns.enumerated() {
                let i = try #require(s.snapshots.firstIndex { $0.round.id == column.roundID })
                #expect(row.points[n] == s.season.roundPoints(i)[row.playerID.uuidString])
                // Scorekortet finnes for den som spilte.
                if row.points[n] != nil { #expect(s.game(column.roundID) != nil) }
            }
        }
    }

    @Test func motParOgBeste() {
        #expect(RoundsGrid.toParText(0) == "E" && RoundsGrid.toParText(3) == "+3" && RoundsGrid.toParText(-2) == "−2")
        let col = RoundsGrid.Column(roundID: UUID(), label: "1", date: nil, title: "R1", isOngoing: false)
        func row(_ p: Int?, _ s: Int?) -> RoundsGrid.Row {
            RoundsGrid.Row(playerID: UUID(), name: "x", place: "1.", isMe: false, points: [p], strokes: [s],
                           toPar: [s.map { $0 - 72 }], counted: nil)
        }
        let grid = RoundsGrid(columns: [col], rows: [row(36, 80), row(40, 76), row(nil, nil)])
        #expect(grid.bestPoints == [40] && grid.bestStrokes == [76])
        #expect(grid.rows[1].toParTotal == 4)
    }
}
