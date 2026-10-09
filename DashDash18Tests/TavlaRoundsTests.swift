import Foundation
import GolfgutuCore
import Testing
@testable import DashDash18

/// «Alle runder»: hver spiller i tabellen, hver runde i rekkefølge, poengene fra regelmotoren.
@MainActor struct TavlaRoundsTests {
    @Test func rutenettetFølgerTabellenOgRundene() throws {
        let standings = TavlaSamples.standings()
        let grid = standings.roundGrid
        #expect(grid.rows.map(\.memberID) == standings.rows.map(\.memberID))
        #expect(grid.columns.count == standings.snapshots.count)
        #expect(grid.columns.map(\.label) == (1...grid.columns.count).map(String.init))
        for row in grid.rows {
            #expect(row.points.count == grid.columns.count && row.slag.count == grid.columns.count)
            // Samme poeng som regelmotoren gir for runden.
            for (n, column) in grid.columns.enumerated() {
                let i = try #require(standings.snapshots.firstIndex { $0.round.id == column.roundID })
                #expect(row.points[n] == standings.season.roundPoints(i)[row.memberID.uuidString])
            }
        }
        let first = try #require(grid.columns.first)
        #expect(standings.game(first.roundID) != nil)
    }

    @Test func kortDato() {
        #expect(TavlaStandings.shortDate("2026-10-08") == "8.10")
        #expect(TavlaStandings.shortDate("x") == "x")
    }
}
