import Foundation
import Testing
@testable import GolfgutuCore

/// Maksimumscore (Golfreglene 2019, regel 21.2) og match som konkurranser på runden. Tallene:
/// Fixtures/maks-og-match.json (regnet uavhengig av motoren, se «kilde»). Golfgutu-oppsettet er uendret:
/// rundens matcher (`MatchPlay`) regner som før.
struct MaksOgMatchTests {
    struct Fil: Decodable { let runder: [Runde] }
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
        let stilling: Stilling?
    }
    struct Forventet: Decodable { let id: String; let stottet: Bool; let rader: [Rad] }
    struct Runde: Decodable {
        let id: String
        let gameType: String
        let regelsett: String
        let laast: Bool
        let spillehandicap: [String: Double]
        let scorer: [String: [Int?]]
        let konkurranser: [RoundCompetition]
        let forventet: [Forventet]
    }

    let fil: Fil

    init() throws {
        fil = try Fixture.load(Fil.self, "maks-og-match")
    }

    static let course = Course(id: "bane", name: "Testbanen", par: 72, courseRating: 72, slopeRating: 113,
                               holes: (0..<18).map { CourseHole(par: 4, si: $0 + 1) })

    static func rules(_ name: String) -> Ruleset {
        var r = Ruleset.golfgutu
        switch name {
        case "fastTak7": r.formPlay.maximumScore = .fixed(7)
        case "fulltHandicap": r.formats.matchStrokes = .fullHandicap
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
                     holeScores: scores, locked: r.laast, playingHandicaps: r.spillehandicap)
    }

    @Test func konkurranseneRegnes() {
        for r in fil.runder {
            let results = RoundCompetitions.evaluate(Self.round(r), roster: [], competitions: r.konkurranser,
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
                    if let s = w.stilling {
                        #expect(row.match == MatchStanding(up: s.opp, played: s.spilt, remaining: s.igjen,
                                                           decided: s.avgjort, opponents: s.motstandere),
                                "\(id) \(row.players): stilling")
                    } else {
                        #expect(row.match == nil, "\(id) \(row.players)")
                    }
                }
            }
        }
    }

    // MARK: Maksimumscore

    @Test func maksimumscoreErStottet() {
        #expect(RoundCompetitions.supports(FormAxes(teamForm: .individual, scoring: .maximumScore())))
        #expect(RoundCompetitions.supports(FormAxes(teamForm: .pairs(.fourball), scoring: .maximumScore(net: false))))
    }

    /// Taket uten eget i konkurransen kommer fra regelsettet: standard netto dobbel bogey, og Golfgutu
    /// skriver det ikke (JSON-en er som før).
    @Test func taketLiggerIRegelsettet() throws {
        #expect(Ruleset.golfgutu.formPlay.maximumScore == .netDoubleBogey)
        let plain = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Ruleset.golfgutu)) as? [String: Any]
        #expect(plain?["formPlay"] == nil)

        var fixed = Ruleset.golfgutu
        fixed.formPlay.maximumScore = .fixed(7)
        let back = try JSONDecoder().decode(Ruleset.self, from: JSONEncoder().encode(fixed))
        #expect(back.formPlay.maximumScore == .fixed(7))
        #expect(fixed.changedFields(from: .golfgutu) == ["formPlay"])
        #expect(fixed.validate().isEmpty)

        var off = Ruleset.golfgutu
        off.formPlay.maximumScore = .off
        #expect(off.validate().contains { $0.field == "formPlay.maximumScore" })
        var big = Ruleset.golfgutu
        big.formPlay.maximumScore = .fixed(21)
        #expect(big.validate().contains { $0.field == "formPlay.maximumScore" })
    }

    @Test func poengtellingenSomJSON() throws {
        let cases: [(ScoringMethod, String)] = [
            (.maximumScore(), #"{"net":true,"type":"maximumScore"}"#),
            (.maximumScore(net: false, maxStrokes: .fixed(8)), #"{"maxStrokes":{"strokes":8,"type":"fixed"},"net":false,"type":"maximumScore"}"#),
            (.maximumScore(net: true, maxStrokes: .netDoubleBogey), #"{"maxStrokes":{"type":"netDoubleBogey"},"net":true,"type":"maximumScore"}"#),
        ]
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        for (scoring, json) in cases {
            #expect(String(data: try encoder.encode(scoring), encoding: .utf8) == json)
            #expect(try JSONDecoder().decode(ScoringMethod.self, from: Data(json.utf8)) == scoring)
        }
        // Katalogens «maks-score» er netto med regelsettets tak, også fra den korte JSON-en.
        let short = try JSONDecoder().decode(ScoringMethod.self, from: Data(#"{"type":"maximumScore"}"#.utf8))
        #expect(short == CompetitionForm.form(id: "maks-score").axes.scoring)
        #expect(!ScoringMethod.maximumScore(net: false).higherIsBetter)
    }

    // MARK: Match

    @Test func matchStottesMedEgneBallerOgEnBall() {
        #expect(RoundCompetitions.supports(FormAxes(teamForm: .individual, scoring: .matchPlay)))
        #expect(RoundCompetitions.supports(FormAxes(teamForm: .pairs(.fourball), scoring: .matchPlay)))
        // Én ball per lag: se EnBallMatchTests (runden må spilles i lagformen; her er den stableford).
        #expect(RoundCompetitions.supports(FormAxes(teamForm: .pairs(.foursome), scoring: .matchPlay)))
        #expect(RoundCompetitions.supports(FormAxes(teamForm: .scramble(size: 2), scoring: .matchPlay)))
        #expect(!RoundCompetitions.supports(FormAxes(teamForm: .pairs(.aggregate), scoring: .matchPlay)))
    }

    /// Matchen som konkurranse bruker de samme hullvinnerne som rundens matcher (`MatchPlay`), men stopper
    /// når den er avgjort. Rundens match fortsetter som i PWA-en (`matchHullDiff` teller alle hull).
    @Test func sammeHullSomRundensMatch() throws {
        let r = try #require(fil.runder.first { $0.id == "match" })
        var round = Self.round(r)
        round.matches = [Match(matchNo: 1, playerA: "a", playerB: "b")]
        // Rundens matcher slår opp spillerne i troppen (det frosne handicapet er deres).
        let roster = ["a", "b", "c", "d"].map { Player(id: $0) }
        let comp = try #require(RoundCompetitions.evaluate(round, roster: roster, competitions: [r.konkurranser[0]],
                                                           rules: .golfgutu).first)
        let a = try #require(comp.rows.first { $0.players == ["a"] })
        for h in 0..<16 {
            #expect(MatchPlay.holeWinner(round.matches[0], hole: h, in: round, roster: roster).map(Double.init) == a.holeValues[h], "hull \(h + 1)")
        }
        // Konkurransen: «Vunnet 3&2». Rundens match (PWA-en): 1 opp etter 18.
        #expect(MatchPlay.text(a.match) == "Vunnet 3&2")
        let pwa = MatchPlay.standing(round.matches[0], from: "a", in: round, roster: roster)
        #expect(pwa?.up == 1)
        #expect(pwa?.played == 18)
    }

    @Test func stillingenSomTekst() throws {
        let r = try #require(fil.runder.first { $0.id == "match" })
        let results = RoundCompetitions.evaluate(Self.round(r), roster: [], competitions: r.konkurranser, rules: .golfgutu)
        func text(_ id: String, _ player: String) -> String? {
            let row = results.first { $0.id == id }?.rows.first { $0.players.contains(player) }
            return row.map { MatchPlay.text($0.match) }
        }
        #expect(text("a-mot-b", "b") == "Tapt 3&2")
        #expect(text("a-mot-b-forste-ni", "a") == "Vunnet 2 opp")
        #expect(text("c-mot-d", "c") == "2 opp etter 9")
        #expect(text("c-mot-d", "d") == "2 ned etter 9")
        #expect(text("side-mot-side", "c") == "Vunnet 6&4")
    }

    @Test func likeIMatchDelerPlass() {
        let round = Round(id: "r", gameType: "stableford", holeCount: 18, holeStart: 0, course: Self.course, hcpAllowance: 1,
                          holeScores: ["a": [0: 4, 1: 5], "b": [0: 5, 1: 4]], locked: false,
                          playingHandicaps: ["a": 0, "b": 0])
        let comp = RoundCompetition(id: "m", teamForm: .individual, scoring: .matchPlay, entrants: [["a"], ["b"]])
        let result = RoundCompetitions.evaluate(round, roster: [], competitions: [comp], rules: .golfgutu)[0]
        #expect(result.rows.map(\.rank) == [1, 1])
        #expect(result.rows.map(\.score) == [0, 0])
        #expect(MatchPlay.text(result.rows[0].match) == "Delt etter 2")
        // Samme spiller på begge sider: ingen rader.
        let same = RoundCompetition(id: "s", teamForm: .individual, scoring: .matchPlay, entrants: [["a"], ["a", "b"]])
        #expect(RoundCompetitions.evaluate(round, roster: [], competitions: [same], rules: .golfgutu)[0].rows.isEmpty)
    }
}
