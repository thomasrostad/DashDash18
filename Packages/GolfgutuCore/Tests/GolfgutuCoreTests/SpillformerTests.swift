import Foundation
import Testing
@testable import GolfgutuCore

/// Scramble, foursome, greensome, chapman og par/bogey som konkurranser på runden. Tallene:
/// Fixtures/spillformer.json (regnet uavhengig av motoren). Lagshandicap etter WHS «Rules of Handicapping»
/// Appendix C, par/bogey etter Golfreglene 2019 regel 21.3. Golfgutu-oppsettet er uendret.
struct SpillformerTests {
    struct Fil: Decodable {
        let indeks: [String: Double]
        let lagshandicap: [Lagshandicap]
        let runder: [Runde]
    }
    struct Lagshandicap: Decodable {
        let form: String
        let hull: Int
        let spillere: [String]
        let golfgutu: Double
        let whs: Double
    }
    struct Rad: Decodable {
        let spillere: [String]
        let score: Double
        let hull: Int
        let plass: Int
        let perHull: [Double?]
    }
    struct Forventet: Decodable { let id: String; let stottet: Bool; let rader: [Rad] }
    struct Runde: Decodable {
        let id: String
        let gameType: String
        let regelsett: String
        let laast: Bool
        let lag: [String: Int]
        let spillehandicap: [String: Double]?
        let lagshandicap: [String: Double]?
        let scorer: [String: [Int?]]
        let konkurranser: [RoundCompetition]
        let forventet: [Forventet]
    }

    let fil: Fil

    init() throws {
        fil = try Fixture.load(Fil.self, "spillformer")
    }

    /// 18 hull, par 4, indeks 1–18, CR 72 og slope 113: banehandicapet er indeksen.
    static let course = Course(id: "bane", name: "Testbanen", par: 72, courseRating: 72, slopeRating: 113,
                               holes: (0..<18).map { CourseHole(par: 4, si: $0 + 1) })

    var roster: [Player] { fil.indeks.map { Player(id: $0.key, name: $0.key, handicap: $0.value) }.sorted { $0.id < $1.id } }

    static var whs: Ruleset {
        var r = Ruleset.golfgutu
        r.handicap.useWHSTeamHandicap()
        return r
    }

    func rules(_ name: String) -> Ruleset { name == "whs" ? Self.whs : .golfgutu }

    func round(_ r: Runde) -> Round {
        var scores: [String: HoleScores] = [:]
        for (p, list) in r.scorer {
            scores[p] = Dictionary(uniqueKeysWithValues: list.enumerated().compactMap { i, g in g.map { (i, $0) } })
        }
        return Round(id: r.id, gameType: r.gameType, holeCount: 18, holeStart: 0, course: Self.course, hcpAllowance: 1,
                     teams: r.lag, holeScores: scores, locked: r.laast, playingHandicaps: r.spillehandicap ?? [:])
    }

    // MARK: Handicapfordeling

    @Test func lagshandicapGolfgutuOgWHS() {
        for c in fil.lagshandicap {
            let r = Round(gameType: c.form, holeCount: c.hull, course: Self.course, hcpAllowance: 1)
            #expect(Handicap.teamHandicap(in: r, memberIDs: c.spillere, roster: roster, rules: .golfgutu) == c.golfgutu,
                    "\(c.form) \(c.spillere) golfgutu")
            #expect(Handicap.teamHandicap(in: r, memberIDs: c.spillere, roster: roster, rules: Self.whs) == c.whs,
                    "\(c.form) \(c.spillere) whs")
        }
    }

    @Test func whsTalleneLiggerIRegelsettet() {
        let w = Ruleset.TeamHandicapRule.whsRecommended
        #expect(w["foursome"]?.weights == [0.5, 0.5])
        #expect(w["greensome"]?.weights == [0.6, 0.4])
        #expect(w["chapman"]?.weights == [0.6, 0.4])
        #expect(w["scramble-2"]?.weights == [0.35, 0.15])
        #expect(w["scramble-4"]?.weights == [0.25, 0.20, 0.15, 0.10])
        #expect(!Ruleset.golfgutu.handicap.usesWHSTeamHandicap)
        #expect(Self.whs.handicap.usesWHSTeamHandicap)
        #expect(Self.whs.validate().isEmpty)
        // Bare formene med én ball endres.
        #expect(Self.whs.changedFields(from: .golfgutu) == [
            "handicap.teamHandicap.chapman.method", "handicap.teamHandicap.chapman.weights",
            "handicap.teamHandicap.foursome.method", "handicap.teamHandicap.foursome.weights",
            "handicap.teamHandicap.greensome.method", "handicap.teamHandicap.greensome.weights",
            "handicap.teamHandicap.scramble-2.method", "handicap.teamHandicap.scramble-2.weights",
        ])
    }

    @Test func lagshandicapIRunden() {
        for r in fil.runder {
            guard let want = r.lagshandicap else { continue }
            let rnd = round(r)
            for (p, h) in want {
                #expect(Handicap.effective(for: roster.first { $0.id == p }, in: rnd, roster: roster, rules: rules(r.regelsett)) == h,
                        "\(r.id) \(p)")
            }
        }
    }

    // MARK: Poeng per hull, sum og uavgjort

    @Test func konkurranseneRegnes() {
        for r in fil.runder {
            let results = RoundCompetitions.evaluate(round(r), roster: roster, competitions: r.konkurranser,
                                                     rules: rules(r.regelsett))
            #expect(results.map(\.id) == r.forventet.map(\.id), "\(r.id)")
            for (got, want) in zip(results, r.forventet) {
                let id = "\(r.id)/\(want.id)"
                #expect(got.supported == want.stottet, "\(id)")
                #expect(got.rows.map(\.players) == want.rader.map(\.spillere), "\(id): rekkefølge")
                #expect(got.rows.map(\.score) == want.rader.map(\.score), "\(id): sum")
                #expect(got.rows.map(\.holes) == want.rader.map(\.hull), "\(id): hull")
                #expect(got.rows.map(\.rank) == want.rader.map(\.plass), "\(id): plass")
                for (row, w) in zip(got.rows, want.rader) {
                    let perHole = (0..<18).map { row.holeValues[$0] }
                    #expect(perHole == w.perHull, "\(id) \(row.players): per hull")
                }
            }
        }
    }

    @Test func uavgjortDelerPlass() {
        let foursome = fil.runder.first { $0.id == "foursome" }!
        let main = RoundCompetitions.evaluate(round(foursome), roster: roster, competitions: [foursome.konkurranser[0]],
                                              rules: Self.whs)[0]
        #expect(main.rows.map(\.rank) == [1, 1])
    }

    /// Hovedkonkurransen gir de samme poengene som tabellen (`Scoring.roundPoints`), som fører lagets
    /// score med lagets handicap.
    @Test func hovedkonkurransenErTabellpoengene() {
        for r in fil.runder where r.gameType != "par-bogey" {
            let rnd = round(r)
            let rs = rules(r.regelsett)
            let main = RoundCompetitions.evaluate(rnd, roster: roster, competitions: [r.konkurranser[0]], rules: rs)[0]
            let points = Scoring.roundPoints(rnd, roster: roster, rules: rs)
            for row in main.rows {
                for p in row.players where points[p] != nil {
                    #expect(Double(points[p]!) == row.score, "\(r.id) \(p)")
                }
            }
        }
    }

    @Test func enBallKreverAtRundenSpillesILagformen() {
        // Scramble på en individuell runde: scorene er hver spillers egne.
        let r = fil.runder.first { $0.id == "scramble-2" }!
        var rnd = round(r)
        rnd.gameType = "stableford"
        let comp = RoundCompetition(id: "s", teamForm: .scramble(size: 2), scoring: .stableford(net: true))
        #expect(!RoundCompetitions.evaluate(rnd, roster: roster, competitions: [comp], rules: Self.whs)[0].supported)
        // Et lag som ikke er ett av rundens lag.
        let mixed = RoundCompetition(id: "m", teamForm: .scramble(size: 2), scoring: .stableford(net: true),
                                     entrants: [["a", "c"]])
        #expect(!RoundCompetitions.evaluate(round(r), roster: roster, competitions: [mixed], rules: Self.whs)[0].supported)
        #expect(RoundCompetitions.supports(FormAxes(teamForm: .scramble(size: 2), scoring: .parBogey)))
        // Match med én ball (EnBallMatchTests): støttet når runden spilles i lagformen.
        #expect(RoundCompetitions.supports(FormAxes(teamForm: .pairs(.foursome), scoring: .matchPlay)))
    }

    // MARK: Par/bogey

    @Test func parBogeyHull() {
        let s = ParBogeyRules.standard
        #expect(ParBogey.holeValue(net: 3, par: 4, rules: s) == 1)
        #expect(ParBogey.holeValue(net: 4, par: 4, rules: s) == 0)
        #expect(ParBogey.holeValue(net: 6, par: 4, rules: s) == -1)
        #expect(ParBogey.holeValue(net: nil, par: 4, rules: s) == -1)
    }

    @Test func parBogeyITabellen() {
        let r = fil.runder.first { $0.id == "par-bogey" }!
        let want = r.forventet[0].rader
        let points = FormPlay.tablePoints(round(r), roster: roster, rules: .golfgutu)
        #expect(points == Dictionary(uniqueKeysWithValues: want.map { ($0.spillere[0], $0.score) }))
    }

    @Test func parBogeyVerdierFraRegelsettet() throws {
        var rules = Ruleset.golfgutu
        rules.formPlay.parBogey = ParBogeyRules(win: 2, halve: 1, loss: 0)
        let r = fil.runder.first { $0.id == "par-bogey" }!
        let got = RoundCompetitions.evaluate(round(r), roster: roster, competitions: [r.konkurranser[0]], rules: rules)[0]
        // Med 2/1/0 er summen 18 + standardsummen (hvert hull flyttes én opp).
        for row in got.rows {
            let std = r.forventet[0].rader.first { $0.spillere == row.players }!
            #expect(row.score == std.score + Double(std.hull), "\(row.players)")
        }
        // Skrives bare når den ikke er standard, og leses tilbake.
        let data = try JSONEncoder().encode(rules)
        let back = try JSONDecoder().decode(Ruleset.self, from: data)
        #expect(back.formPlay.parBogey == rules.formPlay.parBogey)
        let plain = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Ruleset.golfgutu)) as? [String: Any]
        #expect(plain?["formPlay"] == nil)
        var other = Ruleset.golfgutu
        other.formPlay.skinPoints = 2
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(other)) as? [String: Any]
        #expect((json?["formPlay"] as? [String: Any])?["parBogey"] == nil)

        var bad = Ruleset.golfgutu
        bad.formPlay.parBogey = ParBogeyRules(win: -1, halve: 0, loss: 1)
        #expect(bad.validate().contains { $0.field == "formPlay.parBogey" })
    }
}
