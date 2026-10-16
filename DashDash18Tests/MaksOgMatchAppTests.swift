import Foundation
import GolfgutuCore
import Testing
@testable import DashDash18

// Maksimumscore og match som konkurranser i runden: oppskriftene, oppsettet og stillingen. Motoren er
// testet i GolfgutuCore (MaksOgMatchTests, Fixtures/maks-og-match.json).

private typealias F = ForingFixture

private func draft(formID: String = "stableford") -> RoundDraft {
    var d = RoundDraft.new(eventID: F.eventID, roundNo: 1, teeTime: nil, participants: [1, 2, 3, 4].map(F.id),
                           source: .signups, rules: .golfgutu)
    d.formID = formID
    return d
}

private func competition(_ n: Int, name: String, main: Bool = false, sort: Int, config: CompetitionConfig?) -> RoundCompetitionRow {
    RoundCompetitionRow(id: F.id(n), roundID: F.roundID, name: name, isMain: main, config: config, sortOrder: sort)
}

struct MaksOgMatchOppsettTests {
    @Test func maksimumscoreTarTaketFraRegelsettet() {
        let standard = CompetitionRecipe.maximumScore.make(for: draft()).config
        #expect(standard == CompetitionConfig(teamForm: .individual, scoring: .maximumScore(net: true, maxStrokes: .netDoubleBogey)))
        var rules = Ruleset.golfgutu
        rules.formPlay.maximumScore = .fixed(7)
        #expect(CompetitionRecipe.maximumScore.make(for: draft(), rules: rules).config.scoring
                == .maximumScore(net: true, maxStrokes: .fixed(7)))
        // Én ball per lag: lagene spiller maksimumscore.
        #expect(CompetitionRecipe.maximumScore.make(for: draft(formID: "foursome")).config.teamForm == .pairs(.foursome))
    }

    @Test func maksimumscoreInnstillinger() {
        var c = CompetitionRecipe.maximumScore.make(for: draft())
        #expect(c.maximumScore?.net == true)
        c.setMaximumScore(net: false, cap: .fixed(8))
        #expect(c.config.scoring == .maximumScore(net: false, maxStrokes: .fixed(8)))
        #expect(c.config.form == nil)
        #expect(CompetitionSetup.summary(c, holeCount: 18, firstHole: 1) == "Maksimumscore brutto · tak 8 slag")
        var d = draft()
        c.setMaximumScore(net: true, cap: .fixed(30))
        d.competitions = [c]
        #expect(CompetitionSetup.problem(d) == "Maksimumscore: taket må være 3–20 slag.")
        d.competitions[0].setMaximumScore(net: true, cap: .fixed(20))
        #expect(CompetitionSetup.problem(d) == nil)
    }

    @Test func matchMedToSpillere() {
        var d = draft()
        var c = CompetitionRecipe.matchPlay.make(for: d)
        #expect(c.isMatch && !c.matchIsSides)
        #expect(c.config.entrants == [[F.id(1).uuidString], [F.id(2).uuidString]])
        c.setMatchPlayer(1, to: F.id(4))
        #expect(c.matchPlayer(0) == F.id(1))
        #expect(c.matchPlayer(1) == F.id(4))
        d.competitions = [c]
        #expect(CompetitionSetup.problem(d) == nil)
        d.competitions[0].setMatchPlayer(1, to: F.id(1))
        #expect(CompetitionSetup.problem(d) == "Match: velg to forskjellige spillere.")
        // En spiller som ikke er med i runden.
        d.competitions[0].setMatchPlayer(1, to: F.id(9))
        #expect(CompetitionSetup.problem(d) == "Match: velg to forskjellige spillere.")
    }

    @Test func matchSideMotSide() {
        var d = draft()
        d.sides = [F.id(1): 1, F.id(2): 2, F.id(3): 1, F.id(4): 2]
        var c = CompetitionRecipe.matchPlay.make(for: d)
        #expect(c.matchIsSides)
        #expect(c.config.entrants == nil)
        #expect(CompetitionSetup.summary(c, holeCount: 18, firstHole: 1) == "Matchspill · side 1 mot side 2")
        d.competitions = [c]
        #expect(CompetitionSetup.problem(d) == nil)
        // Uten lag mot lag må det være to spillere.
        d.sides = [:]
        #expect(CompetitionSetup.problem(d) == "Match: slå på lag mot lag, eller velg to spillere.")
        c.setMatchSides(false, participants: d.participants)
        #expect(c.config.entrants == [[F.id(1).uuidString], [F.id(2).uuidString]])
        c.setMatchSides(true, participants: d.participants)
        #expect(c.config.entrants == nil)
    }

    @Test func oppskrifteneHarBareNoklerSomI048() throws {
        var d = draft()
        d.sides = [F.id(1): 1, F.id(2): 2]
        for recipe in [CompetitionRecipe.maximumScore, .matchPlay] {
            for draft in [d, draft()] {
                let data = try JSONEncoder().encode(recipe.make(for: draft).config)
                let keys = Set((try JSONSerialization.jsonObject(with: data) as? [String: Any])?.keys.map { $0 } ?? [])
                #expect(keys.isSubset(of: CompetitionConfig.allowedKeys), "\(recipe)")
            }
        }
    }
}

struct MaksOgMatchKonkurranseTests {
    /// Anders (0) og Bjørn (18 slag, ett per hull), side 1 og 2. Anders: par, men 9 på hull 1 og birdie på
    /// hull 2. Bjørn: bogey, men 10 på hull 1. Netto dobbel bogey: Anders 6 på hull 1, Bjørn 7.
    private func snapshot(sides: Bool = true) -> RoundSnapshot {
        let players = [F.P(n: 1, name: "Anders", playing: 0), F.P(n: 2, name: "Bjørn", playing: 18)]
        var scores: [(Int, Int, Int)] = []
        for h in 0..<18 {
            scores.append((1, h, h == 0 ? 9 : F.par[h] - (h == 1 ? 1 : 0)))
            scores.append((2, h, h == 0 ? 10 : F.par[h] + 1))
        }
        var s = F.snapshot(players, round: F.round(status: .locked), scores: scores)
        if sides { for i in s.players.indices { s.players[i].side = i + 1 } }
        s.competitions = [
            competition(60, name: "Stableford", main: true, sort: 0, config: CompetitionConfig(form: "stableford")),
            competition(61, name: "Maks", sort: 1, config: CompetitionConfig(teamForm: .individual,
                                                                             scoring: .maximumScore(net: true, maxStrokes: .netDoubleBogey))),
            competition(62, name: "Maks brutto", sort: 2, config: CompetitionConfig(teamForm: .individual,
                                                                                    scoring: .maximumScore(net: false))),
            competition(63, name: "Lagmatch", sort: 3, config: CompetitionConfig(teamForm: .individual, scoring: .matchPlay)),
            competition(64, name: "Anders mot Bjørn", sort: 4,
                        config: CompetitionConfig(teamForm: .individual, scoring: .matchPlay,
                                                  entrants: [[F.id(1).uuidString], [F.id(2).uuidString]], holes: HoleRange(first: 0, last: 8))),
        ]
        return s
    }

    @Test func maksimumscoreISlag() {
        let boards = RoundCompetitionBoard.boards(RoundGame(snapshot()))
        let names = boards.map { $0.name }
        #expect(names == ["Stableford", "Maks", "Maks brutto", "Lagmatch", "Anders mot Bjørn"])
        #expect(boards.allSatisfy { $0.supported })
        // Anders: 72 − 1 (birdie) − 4 + 6 (9 kappet til 6) = 73. Bjørn: 90 − 5 + 7 = 92, netto 74.
        #expect(boards[1].lines.map(\.names) == ["Anders", "Bjørn"])
        #expect(boards[1].lines.map(\.score) == ["73 slag", "74 slag"])
        #expect(boards[1].detail == "Maksimumscore · tak netto dobbel bogey")
        // Brutto: taket er fortsatt netto dobbel bogey. Anders 73, Bjørn 92.
        #expect(boards[2].lines.map(\.score) == ["73 slag", "92 slag"])
        #expect(boards[2].detail == "Maksimumscore brutto · tak netto dobbel bogey")
    }

    @Test func matchStillingen() {
        let boards = RoundCompetitionBoard.boards(RoundGame(snapshot()))
        // Laveste spiller fra scratch: Bjørn får 18 slag. Hull 1: 9 mot 10 − 1 = delt. Hull 2: Anders birdie
        // (4) mot 6 − 1 = 5. Resten: par mot netto par. Anders 1 opp etter 18.
        #expect(boards[3].lines.map(\.names) == ["Anders", "Bjørn"])
        #expect(boards[3].lines.map(\.score) == ["Vunnet 1 opp", "Tapt 1 ned"])
        #expect(boards[3].lines.map(\.rank) == [1, 2])
        // Bare første ni: samme hull, 1 opp etter 9.
        #expect(boards[4].lines.map(\.score) == ["Vunnet 1 opp", "Tapt 1 ned"])
        #expect(boards[4].lines.map(\.holes) == [9, 9])
        #expect(boards[4].detail == "Matchspill (individuelt) · hull 1–9")
    }

    @Test func matchUtenSider() {
        let boards = RoundCompetitionBoard.boards(RoundGame(snapshot(sides: false)))
        #expect(boards[3].supported)
        #expect(boards[3].lines.isEmpty)
        #expect(boards[3].emptyText == "Mangler to spillere eller lag mot lag.")
        // De to valgte spillerne trenger ikke sider.
        #expect(boards[4].lines.count == 2)
    }

    @Test func tekstene() {
        #expect(RoundCompetitionBoard.scoreText(73, scoring: .maximumScore()) == "73 slag")
        #expect(RoundCompetitionBoard.capText(.fixed(8)) == "tak 8 slag")
        #expect(RoundCompetitionBoard.formName(FormAxes(teamForm: .individual, scoring: .maximumScore(net: false))) == "Maksimumscore brutto")
        #expect(RoundCompetitionBoard.formName(FormAxes(teamForm: .individual, scoring: .maximumScore())) == "Maksimumscore")
    }
}
