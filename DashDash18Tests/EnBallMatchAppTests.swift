import Foundation
import GolfgutuCore
import Testing
@testable import DashDash18

// Match med én ball per lag (foursome, greensome, chapman, scramble) i appen: oppskriften, valg av lag og
// stillingen i runden. Motoren er testet i GolfgutuCore (EnBallMatchTests, Fixtures/en-ball-match.json).

private typealias F = ForingFixture

/// Kladd i formen med lagene: spiller 1 og 2 på lag 1, 3 og 4 på lag 2, 5 og 6 på lag 3.
private func draft(formID: String = "foursome", players: Int = 4) -> RoundDraft {
    var d = RoundDraft.new(eventID: F.eventID, roundNo: 1, teeTime: nil, participants: (1...players).map(F.id),
                           source: .signups, rules: .golfgutu)
    d.formID = formID
    d.teams = Dictionary(uniqueKeysWithValues: (1...players).map { (F.id($0), ($0 + 1) / 2) })
    return d
}

private func team(_ numbers: Int...) -> [String] { numbers.map { F.id($0).uuidString }.sorted() }

private func competition(_ n: Int, name: String, main: Bool = false, sort: Int, config: CompetitionConfig?) -> RoundCompetitionRow {
    RoundCompetitionRow(id: F.id(n), roundID: F.roundID, name: name, isMain: main, config: config, sortOrder: sort)
}

struct EnBallMatchOppsettTests {
    @Test func oppskriftenErLagMotLagIRundensLagform() {
        let c = CompetitionRecipe.matchPlay.make(for: draft())
        #expect(c.isOneBallMatch && c.matchIsSides)
        #expect(c.config == CompetitionConfig(teamForm: .pairs(.foursome), scoring: .matchPlay))
        #expect(CompetitionSetup.summary(c, holeCount: 18, firstHole: 1) == "Foursome · Match · rundens to lag")
        var d = draft()
        d.competitions = [c]
        #expect(CompetitionSetup.problem(d) == nil)
        // Scramble 2 og greensome likedan; stableford er fortsatt to spillere.
        #expect(CompetitionRecipe.matchPlay.make(for: draft(formID: "scramble-2")).config.teamForm == .scramble(size: 2))
        #expect(CompetitionRecipe.matchPlay.make(for: draft(formID: "greensome")).config.teamForm == .pairs(.greensome))
        #expect(!CompetitionRecipe.matchPlay.make(for: draft(formID: "stableford")).isOneBallMatch)
    }

    @Test func toBestemteLagNarRundenHarFlere() {
        var d = draft(players: 6)
        var c = CompetitionRecipe.matchPlay.make(for: d)
        #expect(!c.matchIsSides)
        #expect(c.config.entrants == [team(1, 2), team(3, 4)])
        #expect(c.matchTeam(0, teams: d.teams) == 1)
        #expect(c.matchTeam(1, teams: d.teams) == 2)
        c.setMatchTeam(1, to: 3, participants: d.participants, teams: d.teams)
        #expect(c.config.entrants == [team(1, 2), team(5, 6)])
        #expect(CompetitionSetup.summary(c, holeCount: 18, firstHole: 1) == "Foursome · Match · to lag")
        d.competitions = [c]
        #expect(CompetitionSetup.problem(d) == nil)
        d.competitions[0].setMatchTeam(1, to: 1, participants: d.participants, teams: d.teams)
        #expect(CompetitionSetup.problem(d) == "Match: velg to forskjellige lag.")
        // «Rundens to lag» med tre lag går ikke.
        d.competitions[0].setMatchSides(true, participants: d.participants, teams: d.teams)
        #expect(CompetitionSetup.problem(d) == "Match: velg to lag.")
        d.competitions[0].setMatchSides(false, participants: d.participants, teams: d.teams)
        #expect(d.competitions[0].config.entrants == [team(1, 2), team(3, 4)])
        // Lagene trekkes på nytt: valget må gjøres igjen.
        d.teams[F.id(4)] = 3
        #expect(CompetitionSetup.problem(d) == "Match: lagene er endret, velg lagene på nytt.")
    }

    @Test func rundenMaSpillesILagformen() {
        var d = draft()
        d.competitions = [CompetitionRecipe.matchPlay.make(for: d)]
        d.formID = "stableford"
        #expect(CompetitionSetup.problem(d) == "Match: runden må spilles i Foursome (én ball per lag).")
    }

    @Test func oppskriftenHarBareNoklerSomI048() throws {
        for d in [draft(), draft(players: 6), draft(formID: "scramble-2")] {
            let data = try JSONEncoder().encode(CompetitionRecipe.matchPlay.make(for: d).config)
            let keys = Set((try JSONSerialization.jsonObject(with: data) as? [String: Any])?.keys.map { $0 } ?? [])
            #expect(keys.isSubset(of: CompetitionConfig.allowedKeys))
        }
    }
}

struct EnBallMatchKonkurranseTests {
    /// Foursome med tre lag, lagshandicapet frosset ved start: lag 1 15, lag 2 6, lag 3 16. Laget fører ett
    /// tall, skrevet på begge. Lag 1: bogey overalt. Lag 2: par overalt. Lag 3: bogey, men dobbel bogey på
    /// hull 1.
    private func snapshot(teams: Int = 3, sides: Bool = false) -> RoundSnapshot {
        let playing = [1: 15, 2: 6, 3: 16]
        let names = ["Anders", "Bjørn", "Cato", "Dag", "Erik", "Frode"]
        let players = (1...(teams * 2)).map { n in
            F.P(n: n, name: names[n - 1], team: (n + 1) / 2, playing: playing[(n + 1) / 2])
        }
        var scores: [(Int, Int, Int)] = []
        for h in 0..<18 {
            let par = F.par[h]
            for p in players {
                let extra = switch p.team! { case 1: 1; case 2: 0; default: h == 0 ? 2 : 1 }
                scores.append((p.n, h, par + extra))
            }
        }
        var s = F.snapshot(players, round: F.round(status: .locked, format: "foursome"), scores: scores)
        if sides { for i in s.players.indices { s.players[i].side = s.players[i].teamNo } }
        s.competitions = [
            competition(70, name: "Foursome", main: true, sort: 0, config: CompetitionConfig(form: "foursome")),
            competition(71, name: "Rundens to lag", sort: 1, config: CompetitionConfig(teamForm: .pairs(.foursome), scoring: .matchPlay)),
            competition(72, name: "Lag 1 mot lag 3", sort: 2,
                        config: CompetitionConfig(teamForm: .pairs(.foursome), scoring: .matchPlay, entrants: [team(1, 2), team(5, 6)])),
            competition(73, name: "Greensome-match", sort: 3,
                        config: CompetitionConfig(teamForm: .pairs(.greensome), scoring: .matchPlay)),
        ]
        return s
    }

    @Test func toLagIRunden() {
        let boards = RoundCompetitionBoard.boards(RoundGame(snapshot(teams: 2)))
        #expect(boards[1].supported)
        #expect(boards[1].detail == "Foursome · Match")
        // Lag 1 får 9 slag (15 − 6) på indeks 1–9: netto par, delt. Fra hull 10 vinner lag 2 hvert hull og er
        // 5 opp etter 14 med 4 igjen.
        #expect(boards[1].lines.map(\.names) == ["Cato og Dag", "Anders og Bjørn"])
        #expect(boards[1].lines.map(\.score) == ["Vunnet 5&4", "Tapt 5&4"])
        #expect(boards[1].lines.map(\.holes) == [14, 14])
    }

    @Test func lagMotLagMedSiderErRundensToLag() {
        let boards = RoundCompetitionBoard.boards(RoundGame(snapshot(teams: 2, sides: true)))
        #expect(boards[1].lines.map(\.score) == ["Vunnet 5&4", "Tapt 5&4"])
    }

    @Test func toValgteLagAvTre() {
        let boards = RoundCompetitionBoard.boards(RoundGame(snapshot()))
        // Lag 3 får 1 slag (16 − 15) på indeks 1: dobbel bogey blir netto bogey, delt. Resten delt: «Delt».
        #expect(boards[2].supported)
        #expect(boards[2].lines.map(\.score) == ["Delt", "Delt"])
        #expect(boards[2].lines.map(\.rank) == [1, 1])
        #expect(boards[2].lines.map(\.holes) == [18, 18])
        // Uten valgte lag og tre lag i runden: ingen rader.
        #expect(boards[1].supported)
        #expect(boards[1].lines.isEmpty)
        #expect(boards[1].emptyText == "Mangler to lag.")
        // Greensome i en foursome-runde: scorene er foursome-scorer.
        #expect(!boards[3].supported)
    }
}
