import Foundation
import GolfgutuCore
import Testing
@testable import DashDash18

// Scramble, foursome, greensome og par/bogey i appen: oppsettet, konkurransene i runden, «Bayen nå» og
// lagshandicapet i reglene. Motoren er testet i GolfgutuCore (SpillformerTests, Fixtures/spillformer.json).

private typealias F = ForingFixture

private func competition(_ n: Int, name: String, main: Bool = false, sort: Int, config: CompetitionConfig?) -> RoundCompetitionRow {
    RoundCompetitionRow(id: F.id(n), roundID: F.roundID, name: name, isMain: main, config: config, sortOrder: sort)
}

private func draft(formID: String) -> RoundDraft {
    var d = RoundDraft.new(eventID: F.eventID, roundNo: 1, teeTime: nil, participants: [1, 2, 3, 4].map(F.id),
                           source: .signups, rules: .golfgutu)
    d.formID = formID
    return d
}

struct SpillformerOppsettTests {
    @Test func parBogeyOppskriften() {
        #expect(CompetitionRecipe.parBogey.make(for: draft(formID: "stableford")).config == CompetitionConfig(form: "par-bogey"))
        // Spilles runden med én ball per lag, spiller lagene mot banen.
        let foursome = CompetitionRecipe.parBogey.make(for: draft(formID: "foursome")).config
        #expect(foursome == CompetitionConfig(teamForm: .pairs(.foursome), scoring: .parBogey))
    }

    @Test func enBallBrukerRundensLag() {
        var d = draft(formID: "greensome")
        let front = CompetitionRecipe.frontNine.make(for: d)
        #expect(!front.isPairs)
        d.competitions = [front]
        #expect(CompetitionSetup.problem(d) == nil)
        // Bestball i par har fortsatt egne par.
        #expect(CompetitionRecipe.bestBallPairs.make(for: d).isPairs)
    }

    @Test func parBogeyErFerdigIFormvalget() {
        #expect(RundeSetupStep.completedForms.contains("par-bogey"))
        #expect(RoundCompetitions.supports(CompetitionForm.form(id: "par-bogey").axes))
    }
}

struct SpillformerKonkurranseTests {
    /// Scramble 2 med fire spillere (to lag), lagets handicap frosset ved start: lag 1 7, lag 2 3.
    /// Laget fører ett tall, skrevet på begge (`ForingLogic.recipients`).
    private func scramble() -> RoundSnapshot {
        let players = [F.P(n: 1, name: "Anders", team: 1, playing: 7), F.P(n: 2, name: "Bjørn", team: 1, playing: 7),
                       F.P(n: 3, name: "Cato", team: 2, playing: 3), F.P(n: 4, name: "Dag", team: 2, playing: 3)]
        var scores: [(Int, Int, Int)] = []
        for h in 0..<18 {
            let par = F.par[h]
            for p in [1, 2] { scores.append((p, h, par)) }
            for p in [3, 4] { scores.append((p, h, par + (h < 2 ? 1 : 0))) }
        }
        var s = F.snapshot(players, round: F.round(status: .locked, format: "scramble-2"), scores: scores)
        s.competitions = [
            competition(50, name: "Scramble", main: true, sort: 0, config: CompetitionConfig(form: "scramble-2")),
            competition(51, name: "Par/bogey", sort: 1, config: CompetitionConfig(teamForm: .scramble(size: 2), scoring: .parBogey)),
            competition(52, name: "Foursome", sort: 2, config: CompetitionConfig(form: "foursome")),
        ]
        return s
    }

    @Test func scrambleOgParBogeyRegnes() {
        let boards = RoundCompetitionBoard.boards(RoundGame(scramble()))
        #expect(boards.map(\.name) == ["Scramble", "Par/bogey", "Foursome"])
        #expect(boards[0].supported && boards[1].supported)
        // Lag 1: par overalt, slag på indeks 1–7 → 7 birdier netto. Lag 2: bogey på hull 1–2 (to slag der),
        // par ellers, slag på indeks 1–3 → par, par, birdie, så par.
        #expect(boards[1].lines.map(\.names) == ["Anders og Bjørn", "Cato og Dag"])
        #expect(boards[1].lines.map(\.score) == ["+7", "+1"])
        #expect(boards[0].lines.map(\.score) == ["43 p", "37 p"])
        // Foursome er en annen lagform enn runden: scorene er ikke foursome-scorer.
        #expect(!boards[2].supported)
        #expect(boards[2].lines.isEmpty)
    }

    @Test func fortegnITeksten() {
        #expect(RoundCompetitionBoard.scoreText(3, scoring: .parBogey) == "+3")
        #expect(RoundCompetitionBoard.scoreText(0, scoring: .parBogey) == "0")
        #expect(RoundCompetitionBoard.scoreText(-2, scoring: .parBogey) == "−2")
        #expect(RoundCompetitionBoard.formName(FormAxes(teamForm: .scramble(size: 2), scoring: .parBogey)) == "Scramble 2 · Par/bogey")
    }

    @Test func bayenNaaViserParBogey() {
        // Anders 0 i handicap: par overalt bortsett fra birdie på hull 1 → +1. Bjørn bogey på hull 1 → −1.
        let players = [F.P(n: 1, name: "Anders", playing: 0), F.P(n: 2, name: "Bjørn", playing: 0)]
        var scores: [(Int, Int, Int)] = []
        for h in 0..<3 {
            scores.append((1, h, F.par[h] - (h == 0 ? 1 : 0)))
            scores.append((2, h, F.par[h] + (h == 0 ? 1 : 0)))
        }
        let g = RoundGame(F.snapshot(players, round: F.round(format: "par-bogey"), scores: scores))
        let rows = g.bayenNaa(viewer: F.viewer(1))
        #expect(rows.map(\.name) == ["Anders", "Bjørn"])
        #expect(rows.map(\.value) == ["+1", "−1"])
        #expect(rows.map(\.place) == [1, 2])
    }
}

struct SpillformerReglerTests {
    @Test func whsAnbefalingen() {
        var draft = RulesetDraft(.golfgutu)
        #expect(!draft.usesWHSTeamHandicap)
        draft.useWHSTeamHandicap()
        #expect(draft.usesWHSTeamHandicap)
        #expect(draft.teamWeights(CompetitionForm.form(id: "greensome")) == [0.6, 0.4])
        #expect(draft.teamWeights(CompetitionForm.form(id: "scramble-2")) == [0.35, 0.15])
        // Fourball er ikke en form med én ball og er som før.
        #expect(draft.teamMethod(CompetitionForm.form(id: "fourball")) == .average)
    }

    @Test func lagshandicapVisesForFormerMedEnBall() {
        var rules = RulesetTemplate.stablefordSeries.rules
        rules.formats.allowedFormIDs = ["stableford"]
        #expect(!RulesetDraft(rules).showsTeamHandicap)
        rules.formats.allowedFormIDs = ["stableford", "scramble-2"]
        #expect(RulesetDraft(rules).showsTeamHandicap)
        #expect(RulesetDraft(.golfgutu).showsTeamHandicap)
    }
}
