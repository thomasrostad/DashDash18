import Foundation
import Testing
@testable import GolfgutuCore

/// Match med én ball per lag (foursome, greensome, chapman, scramble) som konkurranse på runden. Tallene:
/// Fixtures/en-ball-match.json (regnet uavhengig av motoren, se «kilde»). Lagshandicap etter regelsettet
/// (`handicap.teamHandicap`, WHS Appendix C eller Golfgutu), matchslag etter `formats.matchStrokes`.
/// Golfgutu-oppsettet er uendret: rundens matcher (`MatchPlay`) regner som før.
struct EnBallMatchTests {
    struct Fil: Decodable {
        let indeks: [String: Double]
        let runder: [Runde]
    }
    struct Stilling: Decodable {
        let opp: Int
        let spilt: Int
        let igjen: Int
        let avgjort: Bool
        let motstandere: [String]
    }
    struct Rad: Decodable {
        let spillere: [String]
        let score: Double
        let hull: Int
        let plass: Int
        let perHull: [Double?]
        let stilling: Stilling
        let tekst: String
    }
    struct Forventet: Decodable { let id: String; let stottet: Bool; let rader: [Rad] }
    struct Runde: Decodable {
        let id: String
        let gameType: String
        let regelsett: String
        let laast: Bool
        let lag: [String: Int]
        let lagshandicap: [String: Double]
        let scorer: [String: [Int?]]
        let konkurranser: [RoundCompetition]
        let forventet: [Forventet]
    }

    let fil: Fil

    init() throws {
        fil = try Fixture.load(Fil.self, "en-ball-match")
    }

    /// 18 hull, par 4, indeks 1–18, CR 72 og slope 113: banehandicapet er indeksen.
    static let course = Course(id: "bane", name: "Testbanen", par: 72, courseRating: 72, slopeRating: 113,
                               holes: (0..<18).map { CourseHole(par: 4, si: $0 + 1) })

    var roster: [Player] { fil.indeks.map { Player(id: $0.key, name: $0.key, handicap: $0.value) }.sorted { $0.id < $1.id } }

    static func rules(_ name: String) -> Ruleset {
        var r = Ruleset.golfgutu
        switch name {
        case "whs": r.handicap.useWHSTeamHandicap()
        case "whsFulltHandicap":
            r.handicap.useWHSTeamHandicap()
            r.formats.matchStrokes = .fullHandicap
        default: break
        }
        return r
    }

    static func round(_ r: Runde) -> Round {
        var scores: [String: HoleScores] = [:]
        for (p, list) in r.scorer {
            scores[p] = Dictionary(uniqueKeysWithValues: list.enumerated().compactMap { i, g in g.map { (i, $0) } })
        }
        return Round(id: r.id, gameType: r.gameType, holeCount: 18, holeStart: 0, course: course, hcpAllowance: 1,
                     teams: r.lag, holeScores: scores, locked: r.laast)
    }

    @Test func lagshandicapetErRegelsettets() {
        for r in fil.runder {
            let rnd = Self.round(r)
            for (p, h) in r.lagshandicap {
                #expect(Handicap.effective(for: roster.first { $0.id == p }, in: rnd, roster: roster,
                                           rules: Self.rules(r.regelsett)) == h, "\(r.id) \(p)")
            }
        }
    }

    @Test func konkurranseneRegnes() {
        for r in fil.runder {
            let results = RoundCompetitions.evaluate(Self.round(r), roster: roster, competitions: r.konkurranser,
                                                     rules: Self.rules(r.regelsett))
            #expect(results.map(\.id) == r.forventet.map(\.id), "\(r.id)")
            for (got, want) in zip(results, r.forventet) {
                let id = "\(r.id)/\(want.id)"
                #expect(got.supported == want.stottet, "\(id)")
                #expect(got.rows.map(\.players) == want.rader.map(\.spillere), "\(id): rekkefølge")
                #expect(got.rows.map(\.score) == want.rader.map(\.score), "\(id): sum")
                #expect(got.rows.map(\.holes) == want.rader.map(\.hull), "\(id): hull")
                #expect(got.rows.map(\.rank) == want.rader.map(\.plass), "\(id): plass")
                for (row, w) in zip(got.rows, want.rader) {
                    #expect((0..<18).map { row.holeValues[$0] } == w.perHull, "\(id) \(row.players): per hull")
                    let s = w.stilling
                    #expect(row.match == MatchStanding(up: s.opp, played: s.spilt, remaining: s.igjen,
                                                       decided: s.avgjort, opponents: s.motstandere),
                            "\(id) \(row.players): stilling")
                    #expect(MatchPlay.text(row.match) == w.tekst, "\(id) \(row.players): tekst")
                }
            }
        }
    }

    /// Fra øyeblikksbildet (appen): det frosne spillehandicapet er lagshandicapet, og svaret er det samme.
    @Test func fraOyeblikksbildet() throws {
        for r in fil.runder {
            let rnd = Self.round(r)
            let rules = Self.rules(r.regelsett)
            let frozen = FrozenRound.start(rnd, roster: roster, ruleset: rules)
            let live = RoundCompetitions.evaluate(rnd, roster: roster, competitions: r.konkurranser, rules: rules)
            let snap = RoundCompetitions.evaluate(frozen, scores: rnd.holeScores, locked: r.laast, competitions: r.konkurranser)
            #expect(live == snap, "\(r.id)")
        }
    }

    @Test func matchStottesMedEnBall() {
        for form in [TeamForm.pairs(.foursome), .pairs(.greensome), .pairs(.chapman), .scramble(size: 2), .scramble(size: 4)] {
            #expect(RoundCompetitions.supports(FormAxes(teamForm: form, scoring: .matchPlay)), "\(form)")
        }
        // Sammenlagt match er ikke en del av dette.
        #expect(!RoundCompetitions.supports(FormAxes(teamForm: .pairs(.aggregate), scoring: .matchPlay)))
    }

    /// Hullvinnerne er de samme som rundens lagmatch (`MatchPlay`, lag mot lag i PWA-en), men konkurransen
    /// stopper når matchen er avgjort.
    @Test func sammeHullSomRundensLagmatch() throws {
        let r = try #require(fil.runder.first { $0.id == "foursome" })
        var rnd = Self.round(r)
        rnd.matches = [Match(matchNo: 1, teamA: 1, teamB: 2)]
        let rules = Self.rules(r.regelsett)
        let comp = try #require(RoundCompetitions.evaluate(rnd, roster: roster, competitions: [r.konkurranser[0]],
                                                           rules: rules).first)
        let ab = try #require(comp.rows.first { $0.players == ["a", "b"] })
        for h in 0..<16 {
            #expect(MatchPlay.holeWinner(rnd.matches[0], hole: h, in: rnd, roster: roster, rules: rules).map(Double.init)
                    == ab.holeValues[h], "hull \(h + 1)")
        }
        #expect(ab.holeValues[16] == nil)
        #expect(MatchPlay.text(ab.match) == "Tapt 3&2")
    }

    /// Uten egne lag: rundens to lag. Andre lagformer enn rundens, og lag som ikke er rundens, regnes ikke.
    @Test func lageneIRunden() throws {
        let r = try #require(fil.runder.first { $0.id == "greensome-whs" })
        let rnd = Self.round(r)
        #expect(RoundCompetitions.twoTeams(rnd) == [["a", "b"], ["c", "d"]])
        var three = rnd
        three.teams["e"] = 3
        #expect(RoundCompetitions.twoTeams(three).isEmpty)
        // Samme spillere på stableford-runde: scorene er hver spillers egne.
        var individual = rnd
        individual.gameType = "stableford"
        let comp = RoundCompetition(id: "m", teamForm: .pairs(.greensome), scoring: .matchPlay)
        #expect(!RoundCompetitions.evaluate(individual, roster: roster, competitions: [comp], rules: Self.rules("whs"))[0].supported)
        // Et lag som er en del av et av rundens lag, er greit (som én ball i #114).
        let part = RoundCompetition(id: "p", teamForm: .pairs(.greensome), scoring: .matchPlay, entrants: [["a"], ["c", "d"]])
        #expect(RoundCompetitions.evaluate(rnd, roster: roster, competitions: [part], rules: Self.rules("whs"))[0].rows.count == 2)
    }
}
