import Foundation
import Testing
@testable import GolfgutuCore

/// Tilleggspoeng: poeng arrangøren gir for hånd (sql/072). Tall: Fixtures/tilleggspoeng.json, med
/// rundene fra sesong-stableford.json, regnet for hånd (forklaringen står i fila).
struct PointAdjustmentTests {
    struct Fil: Decodable {
        let tillegg: [PointAdjustment]
        let saker: [Sak]
    }
    struct Sak: Decodable {
        let navn: String
        let regelsett: StablefordTableTests.AnyJSON
        let tavle: [Rad]
    }
    struct Rad: Decodable { let id: String; let total, tillegg: Double }

    @Test func fixturen() throws {
        let fil = try Fixture.load(Fil.self, "tilleggspoeng")
        let sesong = try Fixture.load(StablefordTableTests.Fil.self, "sesong-stableford")
        let rounds = StablefordTableTests.rounds(sesong)
        for sak in fil.saker {
            let rules = sak.regelsett.ruleset
            #expect(rules.validate().isEmpty, "\(sak.navn)")
            let season = Season(players: sesong.spillere, rounds: rounds, claims: sesong.claims, ruleset: rules,
                                adjustments: fil.tillegg)
            let board = season.jacketBoard()
            #expect(board.map(\.player.id) == sak.tavle.map(\.id), "\(sak.navn)")
            for (row, want) in zip(board, sak.tavle) {
                #expect(row.total == want.total, "\(sak.navn) \(want.id) total")
                #expect(row.adjustment == want.tillegg, "\(sak.navn) \(want.id) tillegg")
            }
        }
    }

    /// Spillerens tilleggspoeng med grunnen, i lagret rekkefølge. Ukjente spillere får ingenting.
    @Test func perSpiller() throws {
        let fil = try Fixture.load(Fil.self, "tilleggspoeng")
        let sesong = try Fixture.load(StablefordTableTests.Fil.self, "sesong-stableford")
        let season = Season(players: sesong.spillere, rounds: StablefordTableTests.rounds(sesong),
                            claims: sesong.claims, adjustments: fil.tillegg)
        #expect(season.adjustments(for: "a").map(\.reason) == ["CP knockout challenge"])
        #expect(season.adjustmentPoints(for: "c") == -2)
        #expect(season.adjustmentPoints(for: "ukjent") == 5)
        #expect(!season.jacketBoard().contains { $0.player.id == "ukjent" })
    }

    /// Golfgutu-oppsettet (matcher): uten tillegg er tabellen som før, og med tillegg er totalen
    /// den gamle totalen pluss tillegget, avrundet til nærmeste halve. Ingen andre felt endres.
    @Test func golfgutuUendretUtenTillegg() throws {
        let fil = try Fixture.load(Fil.self, "tilleggspoeng")
        let sesong = try Fixture.load(StablefordTableTests.Fil.self, "sesong-stableford")
        let rounds = StablefordTableTests.rounds(sesong)
        let before = Season(players: sesong.spillere, rounds: rounds, claims: sesong.claims)
        let empty = Season(players: sesong.spillere, rounds: rounds, claims: sesong.claims, adjustments: [])
        #expect(before.jacketBoard() == empty.jacketBoard())
        #expect(before.standings() == empty.standings())
        #expect(before.jacketBoard().allSatisfy { $0.adjustment == 0 })

        let with = Season(players: sesong.spillere, rounds: rounds, claims: sesong.claims, adjustments: fil.tillegg)
        for old in before.jacketBoard() {
            let new = try #require(with.jacketBoard().first { $0.player.id == old.player.id })
            let extra = with.adjustmentPoints(for: old.player.id)
            #expect(new.total == Ruleset.golfgutu.roundTablePoints(old.total + extra))
            #expect(new.adjustment == extra)
            #expect(new.duel == old.duel && new.side == old.side && new.matches == old.matches
                    && new.holes == old.holes && new.stableford == old.stableford && new.evenings == old.evenings
                    && new.qualified == old.qualified)
        }
    }
}
