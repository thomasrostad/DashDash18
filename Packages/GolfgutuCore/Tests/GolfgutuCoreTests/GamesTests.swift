import Foundation
import Testing
@testable import GolfgutuCore

/// Spill på runden (fase 14). Tall: Fixtures/spill.json, regnet for hånd fra regeldefinisjonene
/// og malene (utledningen står i hvert scenario).
struct GamesTests {
    struct Fil: Decodable {
        let fordeling: [Fordeling]
        let scenarier: [Scenario]
    }
    struct Fordeling: Decodable {
        let navn: String
        let total: Double
        let vekter: [String: Double]
        let forventet: [String: Double]
    }
    struct Scenario: Decodable {
        let navn: String
        let runde: Round
        let spill: GameSetup
        let markeringer: GameMarks?
        let forventet: Forventet
    }
    struct Forventet: Decodable {
        let hull: [Hull]
        let veddemaal: [Veddemaal]?
        let poeng: [String: Double]?
        let oppgjor: [String: Int]
        let ferdig: Bool
        let carry: Int?
    }
    struct Hull: Decodable {
        let status: GameHole.State
        let vinnere: [String]?
        let verdi: Int?
        let opp: Int?
        let wolf: String?
        let poeng: [String: Int]?
    }
    struct Veddemaal: Decodable {
        let del: GameBet.Segment
        let status: GameBet.State
        let forste: Int
        let siste: Int
        let margin: Int
        let vinner: Int?
        let verdi: Int?
        let pressPaa: GameBet.Segment?
    }

    static let fil: Fil = try! Fixture.load(Fil.self, "spill")

    @Test(arguments: fil.scenarier.indices)
    func scenario(_ i: Int) {
        let s = GamesTests.fil.scenarier[i]
        let roster = s.spill.players.map { Player(id: $0, name: $0) }
        let r = Games.evaluate(s.spill, round: s.runde, roster: roster, marks: s.markeringer ?? GameMarks())
        let f = s.forventet

        #expect(r.holes.count == f.hull.count, "\(s.navn): antall hull")
        for (h, (got, want)) in zip(r.holes, f.hull).enumerated() {
            #expect(got.hole == h, "\(s.navn): hull \(h)")
            #expect(got.state == want.status, "\(s.navn): status hull \(h + 1)")
            if let v = want.vinnere { #expect(got.winners == v, "\(s.navn): vinnere hull \(h + 1)") }
            if let v = want.verdi { #expect(got.value == v, "\(s.navn): verdi hull \(h + 1)") }
            if let v = want.opp { #expect(got.up == v, "\(s.navn): opp etter hull \(h + 1)") }
            if let v = want.wolf { #expect(got.wolf == v, "\(s.navn): wolf hull \(h + 1)") }
            if let v = want.poeng { #expect(got.points == v, "\(s.navn): poeng hull \(h + 1)") }
        }
        if let bets = f.veddemaal {
            #expect(r.bets.count == bets.count, "\(s.navn): antall veddemål")
            for (got, want) in zip(r.bets, bets) {
                #expect(got.segment == want.del, "\(s.navn): del")
                #expect(got.state == want.status, "\(s.navn): status \(want.del)")
                #expect(got.firstHole == want.forste && got.lastHole == want.siste, "\(s.navn): hull i \(want.del)")
                #expect(got.margin == want.margin, "\(s.navn): margin \(want.del)")
                #expect(got.winner == want.vinner, "\(s.navn): vinner \(want.del)")
                if let v = want.verdi { #expect(got.value == v, "\(s.navn): verdi \(want.del)") }
                #expect(got.pressOf == want.pressPaa, "\(s.navn): press på")
            }
        }
        if let poeng = f.poeng {
            #expect(Set(r.scores.keys) == Set(poeng.keys), "\(s.navn): spillere i poengene")
            for (p, v) in poeng {
                #expect(abs((r.scores[p] ?? .nan) - v) < 1e-9, "\(s.navn): poeng \(p)")
            }
        }
        #expect(r.settlement == f.oppgjor, "\(s.navn): oppgjør")
        #expect(r.settlement.values.reduce(0, +) == 0, "\(s.navn): oppgjøret går i null")
        #expect(r.isFinished == f.ferdig, "\(s.navn): ferdig")
        if let c = f.carry { #expect(r.carry == c, "\(s.navn): carry") }
    }

    @Test(arguments: fil.fordeling.indices)
    func fordeling(_ i: Int) {
        let f = GamesTests.fil.fordeling[i]
        let got = PointSplit.apportion(f.total, weights: f.vekter.map { ($0.key, $0.value) })
        #expect(got == f.forventet, "\(f.navn)")
        #expect(got.values.reduce(0, +) == f.total, "\(f.navn): summen")
    }

    // MARK: Malene og innstillingene

    @Test func malenesStandardverdier() {
        #expect(SkinsRules.standard.valuePerSkin == 10)
        #expect(SkinsRules.standard.carryOver)
        #expect(SkinsRules.standard.leftover == .lapse)
        #expect(NassauRules.standard.front == 10 && NassauRules.standard.back == 10 && NassauRules.standard.total == 10)
        #expect(!NassauRules.standard.press && NassauRules.standard.pressTrigger == 2)
        #expect(WolfRules.standard.partnerWin == 2 && WolfRules.standard.opponentsWin == 3)
        #expect(WolfRules.standard.loneWin == 4 && WolfRules.standard.loneLoss == 1)
        #expect(WolfRules.standard.blindWin == 6 && WolfRules.standard.blindLoss == 2)
        #expect(BingoBangoBongoRules.standard == BingoBangoBongoRules(bingo: 1, bango: 1, bongo: 1, pointValue: 1))
        #expect(BestBallRules.standard.matchHandicap.allowance == 0.9)
        #expect(BestBallRules.standard.stablefordHandicap.allowance == 0.85)
    }

    @Test func tommeInnstillingerGirMalen() throws {
        for kind in GameKind.allCases {
            let s = try GameSettings.decode(kind, from: Data("{}".utf8))
            #expect(s == GameSettings.standard(kind), "\(kind)")
        }
    }

    @Test func delvisHandicapArverMalen() throws {
        // Nassau-malen spiller fra laveste; et spill som bare slår av netto beholder det.
        let s = try GameSettings.decode(.nassau, from: Data(#"{"handicap":{"net":false},"front":7}"#.utf8))
        guard case .nassau(let r) = s else { Issue.record("feil type"); return }
        #expect(r.handicap == GameHandicap(net: false, allowance: 1, fromLowest: true))
        #expect(r.front == 7 && r.back == 10)
    }

    @Test func innstillingerTurRetur() throws {
        var wolf = WolfRules.standard
        wolf.loneWin = 5
        wolf.handicap.allowance = 0.5
        for s in [GameSettings.wolf(wolf), .skins(.standard), .nassau(.standard), .bestBall(.standard),
                  .bingoBangoBongo(.standard)] {
            #expect(try GameSettings.decode(s.kind, from: s.encoded()) == s)
        }
        let setup = GameSetup(settings: .wolf(wolf), players: ["a", "b", "c", "d"])
        let data = try JSONEncoder().encode(setup)
        #expect(try JSONDecoder().decode(GameSetup.self, from: data) == setup)
    }

    // MARK: Oppsettet

    @Test func oppsettSjekkes() {
        let ok = GameSetup(settings: .bestBall(.standard), players: ["a", "b", "c", "d"],
                           sides: ["a": 1, "b": 1, "c": 2, "d": 2])
        #expect(Games.problems(ok, roundPlayers: ["a", "b", "c", "d", "e"]).isEmpty)

        var skjeve = ok
        skjeve.sides = ["a": 1, "b": 1, "c": 1, "d": 2]
        #expect(Games.problems(skjeve) == [.sides])

        let wolfTo = GameSetup(settings: .wolf(.standard), players: ["a", "b"])
        #expect(Games.problems(wolfTo) == [.playerCount(.wolf, 3...5)])

        let dobbel = GameSetup(settings: .skins(.standard), players: ["a", "a", "b"])
        #expect(Games.problems(dobbel, roundPlayers: ["a", "b"]) == [.duplicatePlayer])

        let fremmed = GameSetup(settings: .skins(.standard), players: ["a", "x"])
        #expect(Games.problems(fremmed, roundPlayers: ["a", "b"]) == [.notInRound("x")])

        var negativ = SkinsRules.standard
        negativ.valuePerSkin = -1
        #expect(Games.problems(GameSetup(settings: .skins(negativ), players: ["a", "b"])) == [.invalidValue])

        let nassau1mot2 = GameSetup(settings: .nassau(.standard), players: ["a", "b", "c"],
                                    sides: ["a": 1, "b": 2, "c": 2])
        #expect(Games.problems(nassau1mot2).isEmpty)
    }

    @Test func wolfRotasjon() {
        let p = ["a", "b", "c", "d"]
        #expect((0..<9).map { Games.wolf(on: $0, players: p)! } == ["a", "b", "c", "d", "a", "b", "c", "d", "a"])
        #expect(Games.wolf(on: 4, players: ["a", "b", "c"]) == "b")
        #expect(Games.wolf(on: 0, players: []) == nil)
    }

    @Test func tommeRunderGirIngenPoeng() {
        let round = Round(holeCount: 18)
        for kind in GameKind.allCases {
            let players = Array(["a", "b", "c", "d"].prefix(max(kind.playerRange.lowerBound, 2)))
            let setup = GameSetup(settings: .standard(kind), players: players,
                                  sides: kind.hasSides ? ["a": 1, "b": 2, "c": 1, "d": 2] : [:])
            let r = Games.evaluate(setup, round: round, roster: [])
            #expect(r.settlement.values.allSatisfy { $0 == 0 }, "\(kind)")
            #expect(Set(r.settlement.keys) == Set(players), "\(kind)")
            #expect(!r.isFinished, "\(kind)")
            #expect(r.holes.count == 18, "\(kind)")
        }
    }

    @Test func avkortingKutterHullene() {
        var round = Round(holeCount: 18, avkortRegel: "nettopar", avkortetEtter: 11)
        #expect(Games.countingHoles(round) == 11)
        #expect(Games.isFinal(round))
        round.avkortRegel = nil
        #expect(Games.countingHoles(round) == 18)
        #expect(!Games.isFinal(round))
        round.locked = true
        #expect(Games.isFinal(round))
        #expect(Games.countingHoles(Round(holeCount: 9)) == 9)
    }

    /// Handicapet i spillet: rundens frosne handicap, andelen rundet som JS, og laveste fra scratch.
    @Test func spillehandicap() {
        let round = Round(holeCount: 18, playingHandicaps: ["a": 5, "b": 15, "c": 25])
        let setup = GameSetup(settings: .skins(.standard), players: ["a", "b", "c"])
        let ctx = GameContext(setup: setup, round: round, roster: [], rules: .golfgutu)
        #expect(ctx.handicaps(GameHandicap(net: true, allowance: 1, fromLowest: false)) == ["a": 5, "b": 15, "c": 25])
        // 5 · 0,9 = 4,5 → 5; 15 · 0,9 = 13,5 → 14; 25 · 0,9 = 22,5 → 23.
        #expect(ctx.handicaps(GameHandicap(net: true, allowance: 0.9, fromLowest: false)) == ["a": 5, "b": 14, "c": 23])
        #expect(ctx.handicaps(GameHandicap(net: true, allowance: 0.9, fromLowest: true)) == ["a": 0, "b": 9, "c": 18])
        #expect(ctx.handicaps(.gross) == ["a": 0, "b": 0, "c": 0])
    }

    /// Simulatoren deler ut slagene (`hcpExtern`): spillet gir ingen slag.
    @Test func eksterntHandicapGirIngenSlag() {
        let round = Round(holeCount: 9, hcpExtern: true, holeScores: ["a": [0: 4], "b": [0: 5]],
                          playingHandicaps: ["b": 18])
        let setup = GameSetup(settings: .skins(.standard), players: ["a", "b"])
        let r = Games.evaluate(setup, round: round, roster: [])
        #expect(r.holes[0].state == .won && r.holes[0].winners == ["a"])
    }

    /// `Bets.payouts` bruker samme fordeling som spillene: 100 på tre like innsatser gir 34, 33, 33.
    @Test func veddemaalOgSpillDelerLikt() {
        let bet = Bet(id: "x", status: .resolved, resolution: .yes,
                      stakes: [BetStake(playerID: "a", side: .yes, points: 50),
                               BetStake(playerID: "b", side: .yes, points: 50),
                               BetStake(playerID: "c", side: .yes, points: 50),
                               BetStake(playerID: "d", side: .no, points: 100)])
        let pay = Bets.payouts(bet)
        let split = PointSplit.apportion(100, weights: [("a", 50), ("b", 50), ("c", 50)])
        for p in ["a", "b", "c"] { #expect(pay[p] == split[p]) }
        #expect(pay["d"] == -100)
    }
}
