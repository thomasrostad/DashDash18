import Foundation
import Testing
@testable import GolfgutuCore

/// Statistikkmotoren (fase 16). Tall: Fixtures/statistikk.json, regnet for hånd fra hullene.
///
/// r1: klubb, Bjaavann, 18 hull, spillehandicap 18 (ett slag per hull). Bogey, birdie, trippel og
///     dobbel på hull 1–4, resten par: 77 brutto, 59 netto, 49 stableford. 35 putter. WHS: CH 17,
///     justert 77, (113/125)·(77 − 71) = 5,4.
/// r2: løs, samme bane: birdie på hull 6 og eagle på hull 7: 69, 51, 57. WHS −1,8.
/// r3: klubb, Larvik, 9 hull, bogey på alle: 45, 36, 18. Ingen differential (9 hull).
/// r4: klubb, Bjaavann, bare hull 1–9 ført (par): ikke fullført. r5: ingenting ført.
struct PlayerStatsTests {
    struct Fil: Decodable {
        let runder: [StatsRound]
        let forventet: Forventet
    }
    struct Forventet: Decodable {
        struct Linje: Decodable {
            let id: String; let hullFort: Int; let fullfort: Bool; let brutto: Int; let par: Int
            let netto: Int; let stableford: Int; let putter: Int?; let differential: Double?
        }
        struct Snitt: Decodable {
            let hull: Int; let runder: Int; let brutto: Double; let motPar: Double; let netto: Double; let stableford: Double
        }
        struct ParType: Decodable { let par: Int; let hull: Int; let brutto: Int }
        struct Rekord: Decodable { let bane: String; let hull: String; let runder: Int; let bestBrutto: String; let bestNetto: String }
        struct HCP: Decodable { let id: String; let differential: Double; let indeks: Double? }
        struct Filter: Decodable { let navn: String; let filter: StatsFilter; let runder: [String]; let handicap: [String] }
        let linjer: [Linje]
        let rekkefolge: [String]
        let snitt: [Snitt]
        let parTyper: [ParType]
        let fordeling: [String: Int]
        let slag: ShotStats
        let rekorder: [Rekord]
        let handicap: [HCP]
        let beststableford: [String]
        let bestbrutto: [String]
        let filtre: [Filter]
    }

    let fil: Fil
    let summary: StatsSummary

    init() throws {
        fil = try Fixture.load(Fil.self, "statistikk")
        summary = PlayerStats.summary(fil.runder)
    }

    @Test func rundeForRunde() throws {
        #expect(summary.rounds.map(\.id) == fil.forventet.rekkefolge)
        for f in fil.forventet.linjer {
            let l = try #require(summary.rounds.first { $0.id == f.id })
            #expect(l.holesPlayed == f.hullFort, "\(f.id)")
            #expect(l.isComplete == f.fullfort, "\(f.id)")
            #expect(l.gross == f.brutto, "\(f.id)")
            #expect(l.par == f.par, "\(f.id)")
            #expect(l.net == f.netto, "\(f.id)")
            #expect(l.stableford == f.stableford, "\(f.id)")
            #expect(l.putts == f.putter, "\(f.id)")
            #expect(l.differential == f.differential, "\(f.id)")
        }
    }

    @Test func snittPerAntallHull() throws {
        #expect(summary.averages.count == fil.forventet.snitt.count)
        for f in fil.forventet.snitt {
            let a = try #require(summary.averages[f.hull])
            #expect(a.rounds == f.runder)
            #expect(a.gross == f.brutto)
            #expect(a.toPar == f.motPar)
            #expect(a.net == f.netto)
            #expect(a.stableford == f.stableford)
        }
    }

    @Test func perParType() {
        #expect(summary.parTypes.map(\.par) == fil.forventet.parTyper.map(\.par))
        for (p, f) in zip(summary.parTypes, fil.forventet.parTyper) {
            #expect(p.holes == f.hull)
            #expect(abs(p.averageGross - Double(f.brutto) / Double(f.hull)) < 1e-12)
        }
    }

    @Test func fordeling() {
        for bucket in ScoreBucket.allCases {
            #expect(summary.distribution.count(bucket) == fil.forventet.fordeling[bucket.rawValue], "\(bucket)")
        }
        #expect(summary.distribution.total == 54)
    }

    /// Fairway på par 3 (hull 3 i r1) telles ikke.
    @Test func fairwayGreenOgPutter() {
        #expect(summary.shots == fil.forventet.slag)
        #expect(summary.shots.fairwayShare == 1.0 / 3.0)
        #expect(summary.shots.girShare == 0.25)
        #expect(summary.shots.puttsPerRound == 35)
        #expect(summary.shots.sandSaveShare == 0.5)
    }

    @Test func banerekorder() {
        let r = summary.courseRecords
        #expect(r.map { $0.courseID ?? "" } == fil.forventet.rekorder.map(\.bane))
        for (rec, f) in zip(r, fil.forventet.rekorder) {
            #expect(rec.layoutKey == f.hull)
            #expect(rec.rounds == f.runder)
            #expect(rec.bestGross.id == f.bestBrutto)
            #expect(rec.bestNet.id == f.bestNetto)
        }
    }

    @Test func handicaputvikling() {
        #expect(summary.handicap.map(\.scoreID) == fil.forventet.handicap.map(\.id))
        #expect(summary.handicap.map(\.differential) == fil.forventet.handicap.map(\.differential))
        #expect(summary.handicap.map(\.index) == fil.forventet.handicap.map(\.indeks))
        #expect(summary.currentIndex == nil)
    }

    @Test func besteRunder() {
        #expect(summary.bestByStableford(5, holes: 18).map(\.id) == fil.forventet.beststableford)
        #expect(summary.bestByStableford(5).map(\.id) == ["r2", "r1", "r3"])
        #expect(summary.bestByGross(3, holes: 9).map(\.id) == ["r3"])
        #expect(summary.bestByGross(3).map(\.id) == fil.forventet.bestbrutto)
        #expect(summary.trend.map(\.id) == ["r1", "r2", "r3"])
    }

    @Test func filtre() {
        for f in fil.forventet.filtre {
            let s = PlayerStats.summary(fil.runder, filter: f.filter)
            #expect(s.rounds.map(\.id) == f.runder, "\(f.navn)")
            #expect(s.handicap.map(\.scoreID) == f.handicap, "\(f.navn)")
        }
    }

    /// Stablefordregelen fra regelsettet: netto par gir 3 i stedet for 2 → 18 poeng mer.
    @Test func stablefordFraRegelsettet() throws {
        var r1 = try #require(fil.runder.first { $0.id == "r1" })
        r1.scoring = Ruleset.ScoringRules(netParPoints: 3, minimumPoints: 0)
        #expect(PlayerStats.line(r1).stableford == 67)
    }

    @Test func tomtGrunnlag() {
        let s = PlayerStats.summary([])
        #expect(s.rounds.isEmpty)
        #expect(s.averages.isEmpty)
        #expect(s.distribution.share(.par) == nil)
        #expect(!s.shots.hasAny)
        #expect(s.courseRecords.isEmpty)
    }

    @Test func glidendeSnitt() {
        #expect(PlayerStats.movingAverage([1, 2, 3, 4], window: 2) == [1, 1.5, 2.5, 3.5])
        #expect(PlayerStats.movingAverage([4], window: 5) == [4])
    }
}
