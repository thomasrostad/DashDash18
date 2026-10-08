import Foundation
import Testing
@testable import GolfgutuCore

/// Tabellen når den teller stableford (`table.pointsSource = .stableford`, fase 18). Tall:
/// Fixtures/sesong-stableford.json, regnet for hånd (forklaringen står i fila).
struct StablefordTableTests {
    struct Fil: Decodable {
        let spillere: [Player]
        let runder: [Runde]
        let claims: [SideClaim]
        let saker: [Sak]
    }
    struct Runde: Decodable {
        let id: String
        let dato: String
        let vekt: Double
        let poeng: [String: Int]
        let matcher: [Match]?
    }
    struct Rad: Decodable { let id: String; let total, runder, side: Double; let spilte, stableford: Int }
    struct Per: Decodable {
        let tellende, strøket, tellendeSide, strøketSide: [String]
    }
    struct Sak: Decodable {
        let navn: String
        let regelsett: AnyJSON
        let tavle: [Rad]
        let per: [String: Per]
    }
    /// Regelsettet slik det står i fila, lest som `Ruleset` for seg.
    struct AnyJSON: Decodable {
        let ruleset: Ruleset
        init(from decoder: Decoder) throws { ruleset = try Ruleset(from: decoder) }
    }

    /// 18 hull par 4, stroke index 1–18, slope 113 og CR = par: handicap 0 gir 0 slag.
    static let course = Course(id: "bane", name: "Testbanen", par: 72, courseRating: 72, slopeRating: 113,
                               holes: (1...18).map { CourseHole(par: 4, si: $0) })

    /// Scorer som gir `points` stablefordpoeng med handicap 0: 2 poeng per hull (par), så opp eller ned.
    static func scores(for points: Int) -> HoleScores {
        precondition((0...72).contains(points))
        var perHole = Array(repeating: 2, count: 18)
        var rest = points - 36
        var i = 0
        while rest != 0 {
            if rest > 0, perHole[i] < 4 { perHole[i] += 1; rest -= 1 } else if rest < 0, perHole[i] > 0 { perHole[i] -= 1; rest += 1 } else { i += 1 }
        }
        // poeng = max(0, par − netto + 2) = 6 − slag for par 4.
        return Dictionary(uniqueKeysWithValues: perHole.enumerated().map { ($0.offset, 6 - $0.element) })
    }

    static func rounds(_ fil: Fil) -> [Round] {
        fil.runder.map { r in
            Round(id: r.id, gameType: "stableford", holeCount: 18, holeStart: 0, course: course, hcpAllowance: 1,
                  holeScores: r.poeng.mapValues(scores(for:)), matches: r.matcher ?? [],
                  weight: r.vekt, date: r.dato, locked: true)
        }
    }

    @Test func fixturen() throws {
        let fil = try Fixture.load(Fil.self, "sesong-stableford")
        let rounds = Self.rounds(fil)
        for sak in fil.saker {
            let rules = sak.regelsett.ruleset
            #expect(rules.table.pointsSource == .stableford, "\(sak.navn)")
            #expect(rules.validate().isEmpty, "\(sak.navn)")
            let season = Season(players: fil.spillere, rounds: rounds, claims: fil.claims, ruleset: rules)
            // Scorene gir poengene i fila.
            for (i, r) in fil.runder.enumerated() { #expect(season.roundPoints(i) == r.poeng) }

            let board = season.jacketBoard()
            #expect(board.map(\.player.id) == sak.tavle.map(\.id), "\(sak.navn)")
            for (row, want) in zip(board, sak.tavle) {
                #expect(row.total == want.total, "\(sak.navn) \(want.id) total")
                #expect(row.roundPoints == want.runder, "\(sak.navn) \(want.id) runder")
                #expect(row.side == want.side, "\(sak.navn) \(want.id) side")
                #expect(row.played == want.spilte, "\(sak.navn) \(want.id) spilte")
                #expect(row.stableford == want.stableford, "\(sak.navn) \(want.id) stableford")
                // Matcher gir ingenting.
                #expect(row.duel == 0 && row.matches == 0 && row.holes == 0)
            }
            for (pid, want) in sak.per {
                let sel = season.tableSelection(for: pid)
                #expect(sel.matches.counting.isEmpty && sel.matches.dropped.isEmpty)
                #expect(sel.rounds.counting.map { $0.roundID ?? "" } == want.tellende, "\(sak.navn) \(pid)")
                #expect(sel.rounds.dropped.map { $0.roundID ?? "" } == want.strøket, "\(sak.navn) \(pid)")
                func key(_ s: Season.SidePrizeResult) -> String { "\(s.roundID ?? ""):\(s.kind.rawValue)" }
                #expect(sel.sidePrizes.counting.map(key) == want.tellendeSide, "\(sak.navn) \(pid)")
                #expect(sel.sidePrizes.dropped.map(key) == want.strøketSide, "\(sak.navn) \(pid)")
            }
        }
    }

    /// Samme runder med Golfgutu-oppsettet: matchen i r1 teller, og runder står tomme i utvalget.
    @Test func golfgutuTellerMatcherSomFør() throws {
        let fil = try Fixture.load(Fil.self, "sesong-stableford")
        let season = Season(players: fil.spillere, rounds: Self.rounds(fil), claims: fil.claims)
        let bjorn = season.tableSelection(for: "b")
        #expect(bjorn.matches.counting.count == 1)
        #expect(bjorn.rounds.counting.isEmpty && bjorn.rounds.dropped.isEmpty)
        let row = try #require(season.jacketBoard().first { $0.player.id == "b" })
        #expect(row.roundPoints == 0)
        #expect(row.duel == 1)
    }

    /// `match` gir ingen mening med stableford: valideringen sier fra, og motoren regner det som runder.
    @Test func matchSomEnhetRegnesSomRunde() throws {
        let fil = try Fixture.load(Fil.self, "sesong-stableford")
        var rules = RulesetTemplate.stablefordSeries.rules
        rules.table.counting = .init(unit: .match, best: 2)
        #expect(rules.validate().map(\.field) == ["table.counting.unit"])
        var perRound = rules
        perRound.table.counting = .init(unit: .round, best: 2)
        let a = Season(players: fil.spillere, rounds: Self.rounds(fil), claims: fil.claims, ruleset: rules)
        let b = Season(players: fil.spillere, rounds: Self.rounds(fil), claims: fil.claims, ruleset: perRound)
        #expect(a.jacketBoard() == b.jacketBoard())
        // Anne: r2 40 og r4 40 (de to beste rundene).
        #expect(a.jacketBoard().first { $0.player.id == "a" }?.total == 80)
    }

    /// Stableford-serien: beste 5 av 7 kvelder, ingen sidepremier, selv om det er meldt inn premier.
    @Test func stablefordSerien() throws {
        let fil = try Fixture.load(Fil.self, "sesong-stableford")
        let season = Season(players: fil.spillere, rounds: Self.rounds(fil), claims: fil.claims,
                            ruleset: RulesetTemplate.stablefordSeries.rules)
        let board = season.jacketBoard()
        // Færre enn 5 kvelder spilt: alt teller. Anne 155, Bjørn 158, Cato 132.
        #expect(board.map(\.player.id) == ["b", "a", "c", "d"])
        #expect(board.map(\.total) == [158, 155, 132, 0])
        #expect(board.map(\.side) == [0, 0, 0, 0])
        #expect(board.map(\.stableford) == [158, 155, 132, 0])
    }
}
