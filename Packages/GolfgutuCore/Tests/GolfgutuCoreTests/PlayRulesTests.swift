import Foundation
import Testing
@testable import GolfgutuCore

/// Føring og visning (`play`): maks slag per hull, låst kort etter levering og antall skjulte hull.
/// Tall: Fixtures/maks-slag.json (regnet for hånd).
struct PlayRulesTests {
    struct Fil: Decodable {
        let spillere: [Player]
        let slag: [String: [Int]]
        let grense: [Grense]
        let saker: [Sak]
        let json: [JSONSak]
        let ugyldig: [Ugyldig]
        let skjul: [Skjul]
    }
    struct Grense: Decodable { let regel: Ruleset.MaxStrokes; let par: Int; let slagFatt: Int; let grense: Int? }
    struct Sak: Decodable {
        let navn: String
        let regel: Ruleset.MaxStrokes
        let kappet: [String: [Int]]
        let stableford: [String: Int]
        let brutto: [String: Int]
        let matchHull1: String
    }
    struct JSONSak: Decodable {
        let maxStrokes: Ruleset.MaxStrokes
        let lockSubmittedCards: Bool
        let hiddenHoles: Int
        let shankPosts: Bool
        let teammatesScore: Bool
    }
    struct Ugyldig: Decodable { let play: Ruleset.PlayRules; let felt: String }
    struct Skjul: Decodable { let navn: String; let holeCount: Int; let holeStart: Int; let hideLastHoles: Int; let skjulte: [Int] }

    static func fil() throws -> Fil { try Fixture.load(Fil.self, "maks-slag") }

    static func scores(_ list: [Int]) -> HoleScores {
        Dictionary(uniqueKeysWithValues: list.enumerated().map { ($0.offset, $0.element) })
    }

    static func round(_ fil: Fil, gameType: String = "stableford") -> Round {
        Round(id: "r1", gameType: gameType, holeCount: 18, holeStart: 0, course: StablefordTableTests.course,
              hcpAllowance: 1, holeScores: fil.slag.mapValues(scores), weight: 1, date: "2026-10-15", locked: true)
    }

    static func rules(_ max: Ruleset.MaxStrokes) -> Ruleset {
        var r = Ruleset.golfgutu
        r.play.maxStrokes = max
        return r
    }

    // MARK: Grensen

    @Test func grensenPerHull() throws {
        for g in try Self.fil().grense {
            #expect(g.regel.limit(par: g.par, strokesReceived: g.slagFatt) == g.grense, "\(g.regel) par \(g.par)")
        }
    }

    @Test func kappetRundeOgPoeng() throws {
        let fil = try Self.fil()
        let round = Self.round(fil)
        for sak in fil.saker {
            let rules = Self.rules(sak.regel)
            let capped = round.cappingStrokes(roster: fil.spillere, rules: rules)
            #expect(capped.holeScores == sak.kappet.mapValues(Self.scores), "\(sak.navn)")
            #expect(Scoring.roundPoints(capped, roster: fil.spillere, rules: rules) == sak.stableford, "\(sak.navn)")
            let gross = capped.holeScores.mapValues { $0.values.reduce(0, +) }
            #expect(gross == sak.brutto, "\(sak.navn)")
        }
    }

    @Test func grensenForEnSpiller() throws {
        let fil = try Self.fil()
        let round = Self.round(fil)
        #expect(round.strokeLimit(hole: 0, playerID: "A", roster: fil.spillere, rules: .golfgutu) == nil)
        #expect(round.strokeLimit(hole: 0, playerID: "A", roster: fil.spillere, rules: Self.rules(.netDoubleBogey)) == 7)
        #expect(round.strokeLimit(hole: 0, playerID: "B", roster: fil.spillere, rules: Self.rules(.netDoubleBogey)) == 6)
        #expect(round.strokeLimit(hole: 0, playerID: "B", roster: fil.spillere, rules: Self.rules(.fixed(6))) == 6)
        #expect(round.strokeLimit(hole: 99, playerID: "B", roster: fil.spillere, rules: Self.rules(.fixed(6))) == nil)
    }

    /// Sesongen regner med de kappede scorene: uten grense vinner A første hull i matchen (9 − 1 = 8
    /// netto mot 9), med netto dobbel bogey blir det delt (7 − 1 = 6 mot 6), og med fast 6 vinner A igjen.
    @Test func sesongenBrukerGrensen() throws {
        let fil = try Self.fil()
        let base = Self.round(fil, gameType: "match")
        var round = base
        round.matches = [Match(matchNo: 1, playerA: "A", playerB: "B")]
        for sak in fil.saker {
            let season = Season(players: fil.spillere, rounds: [round], ruleset: Self.rules(sak.regel))
            #expect(season.rounds[0].holeScores == sak.kappet.mapValues(Self.scores), "\(sak.navn)")
            let winner = MatchPlay.holeWinner(season.rounds[0].matches[0], hole: 0, in: season.rounds[0],
                                              roster: fil.spillere, rules: season.ruleset)
            #expect(winner == ["A": 1, "delt": 0, "B": -1][sak.matchHull1], "\(sak.navn)")
        }
    }

    @Test func golfgutuErUendret() throws {
        let fil = try Self.fil()
        let round = Self.round(fil)
        #expect(Ruleset.golfgutu.play == .standard)
        #expect(round.cappingStrokes(roster: fil.spillere, rules: .golfgutu) == round)
        #expect(Season(players: fil.spillere, rounds: [round]).rounds == [round])
    }

    // MARK: JSON og gyldighet

    @Test func jsonLesesOgSkrives() throws {
        let fil = try Self.fil()
        let raw = try JSONSerialization.jsonObject(with: Fixture.data("maks-slag")) as! [String: Any]
        let inputs = (raw["json"] as! [[String: Any]]).map { $0["inn"]! }
        for (sak, inn) in zip(fil.json, inputs) {
            let play = try JSONSerialization.data(withJSONObject: inn)
            let text = #"{"version":2,"play":"# + String(decoding: play, as: UTF8.self) + "}"
            let rules = try JSONDecoder().decode(Ruleset.self, from: Data(text.utf8))
            #expect(rules.play == Ruleset.PlayRules(maxStrokes: sak.maxStrokes, lockSubmittedCards: sak.lockSubmittedCards,
                                                    hiddenHoles: sak.hiddenHoles, shankPosts: sak.shankPosts,
                                                    teammatesScore: sak.teammatesScore))
            let back = try JSONDecoder().decode(Ruleset.self, from: JSONEncoder().encode(rules))
            #expect(back == rules)
            let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(rules)) as! [String: Any]
            #expect((object["play"] != nil) == (rules.play != .standard))
        }
    }

    @Test func golfgutuSkriverIkkePlay() throws {
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Ruleset.golfgutu)) as! [String: Any]
        #expect(object["play"] == nil)
        #expect(Ruleset.golfgutu.validate().isEmpty)
    }

    @Test func ugyldigeVerdier() throws {
        for sak in try Self.fil().ugyldig {
            var rules = Ruleset.golfgutu
            rules.play = sak.play
            #expect(rules.validate().map(\.field) == [sak.felt])
        }
    }

    // MARK: Skjul de siste N hullene

    @Test func skjulDeSisteNHullene() throws {
        for sak in try Self.fil().skjul {
            let round = Round(id: "r", holeCount: sak.holeCount, holeStart: sak.holeStart,
                              course: StablefordTableTests.course, hideLastHoles: sak.hideLastHoles)
            #expect(Array(round.hiddenHoleIndices) == sak.skjulte, "\(sak.navn)")
        }
    }
}
