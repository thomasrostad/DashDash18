import Foundation
import Testing
@testable import GolfgutuCore

/// WHS (Rules of Handicapping, 2024). Tall: Fixtures/whs.json, regnet for hånd fra reglene.
struct WHSTests {
    struct Fil: Decodable {
        let banehandicap: [CH]
        let slagFatt: [Slag]
        let hoyesteHullscore: [Maks]
        let differential: [Diff]
        let utvalg: [Utvalg]
        let nettoDobbelBogey: [NDB]
        let historikk: [Historikk]
        let lavesteIndeks: Laveste
    }
    struct CH: Decodable { let index: Double; let slope: Double; let courseRating: Double; let par: Int; let forventet: Int }
    struct Slag: Decodable { let banehandicap: Int; let indeks: Int; let forventet: Int }
    struct Maks: Decodable { let par: Int; let indeks: Int; let banehandicap: Int?; let forventet: Int }
    struct Diff: Decodable { let justert: Int; let courseRating: Double; let slope: Double; let forventet: Double }
    struct Utvalg: Decodable { let scorer: Int; let laveste: Int?; let justering: Double? }
    struct NDB: Decodable { let navn: String; let score: WHS.Score; let banehandicap: Int?; let justert: Int; let differential: Double }
    struct Historikk: Decodable {
        let navn: String
        let scorer: [WHS.Score]
        let indekser: [Double?]
        let reduksjon: [Double]
        let grense: [Bool]
    }
    struct Laveste: Decodable {
        struct Etablert: Decodable { let date: String; let index: Double }
        struct Sak: Decodable { let sisteScore: String; let forventet: Double? }
        let etablert: [Etablert]
        let saker: [Sak]
    }

    let fil: Fil

    init() throws {
        fil = try Fixture.load(Fil.self, "whs")
    }

    @Test func banehandicap() {
        for c in fil.banehandicap {
            #expect(WHS.courseHandicap(index: c.index, slope: c.slope, courseRating: c.courseRating, par: c.par) == c.forventet,
                    "indeks \(c.index)")
        }
    }

    @Test func slagFattOgPlusshandicap() {
        for s in fil.slagFatt {
            #expect(WHS.strokesReceived(courseHandicap: s.banehandicap, strokeIndex: s.indeks) == s.forventet,
                    "CH \(s.banehandicap), indeks \(s.indeks)")
        }
    }

    @Test func hoyesteHullscore() {
        for m in fil.hoyesteHullscore {
            #expect(WHS.maximumHoleScore(par: m.par, strokeIndex: m.indeks, courseHandicap: m.banehandicap) == m.forventet)
        }
    }

    @Test func scoreDifferential() {
        for d in fil.differential {
            #expect(WHS.scoreDifferential(adjustedGross: d.justert, courseRating: d.courseRating, slope: d.slope) == d.forventet)
        }
    }

    @Test func tabellenForFaerreEnn20() {
        for u in fil.utvalg {
            let sel = WHS.selection(forScores: u.scorer)
            #expect(sel?.lowest == u.laveste, "\(u.scorer) scorer")
            #expect(sel?.adjustment == u.justering, "\(u.scorer) scorer")
        }
    }

    @Test func nettoDobbelBogey() {
        for n in fil.nettoDobbelBogey {
            let rev = WHS.history([n.score])
            #expect(rev.count == 1)
            #expect(rev.first?.courseHandicap == n.banehandicap, "\(n.navn)")
            #expect(rev.first?.adjustedGross == n.justert, "\(n.navn)")
            #expect(rev.first?.differential == n.differential, "\(n.navn)")
        }
    }

    @Test func indeksenRundeForRunde() {
        for h in fil.historikk {
            let rev = WHS.history(h.scorer)
            #expect(rev.map(\.index) == h.indekser, "\(h.navn)")
            #expect(rev.map(\.exceptionalReduction) == h.reduksjon, "\(h.navn)")
            #expect(rev.map(\.capped) == h.grense, "\(h.navn)")
        }
    }

    /// Rekkefølgen inn spiller ingen rolle: rundene sorteres på dato.
    @Test func sortertPaaDato() throws {
        let h = try #require(fil.historikk.first)
        #expect(WHS.history(h.scorer.reversed()).map(\.index) == h.indekser)
    }

    @Test func nihullOgUtenSlopeGirIngenDifferential() throws {
        var s = try #require(fil.nettoDobbelBogey.first).score
        s.holes = Array(s.holes.prefix(9))
        #expect(WHS.history([s]).isEmpty)
    }

    @Test func lavesteIndeksSer365DagerBakover() {
        let est = fil.lavesteIndeks.etablert.map { (date: $0.date, index: $0.index) }
        for sak in fil.lavesteIndeks.saker {
            #expect(WHS.lowHandicapIndex(est, mostRecentScore: sak.sisteScore) == sak.forventet, "\(sak.sisteScore)")
        }
    }

    @Test func avrundingTilTidel() {
        #expect(WHS.roundTenth(12.25) == 12.3)
        #expect(WHS.roundTenth(-0.05) == -0.1)
        #expect(WHS.roundTenth(5.424) == 5.4)
    }
}
