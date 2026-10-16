import Foundation
import GolfgutuCore
import Testing
@testable import DashDash18

private typealias F = ForingFixture

/// Par/bogey på hullkortet (regel 21.3): «+», «0» eller «−» mot banen i stedet for stablefordpoeng.
struct HullkortParBogeyTests {
    let game = RoundGame(F.snapshot(F.markorPlayers(), round: F.round(format: "par-bogey")))

    private func row(gross offset: Int) -> HoleCard.Row {
        let me = F.id(F.anders)
        let first = game.card(hole: 2, drafts: HoleDrafts(), viewer: F.viewer(F.anders)).rows.first { $0.memberID == me }!
        var drafts = HoleDrafts()
        drafts[2, me] = 3 + first.strokesReceived + offset   // hull 3 er par 3
        return game.card(hole: 2, drafts: drafts, viewer: F.viewer(F.anders)).rows.first { $0.memberID == me }!
    }

    @Test func tegnetMotBanen() {
        #expect(row(gross: -1).parBogey == "+")
        #expect(row(gross: 0).parBogey == "0")
        #expect(row(gross: 2).parBogey == "−")
        #expect(row(gross: 0).points == nil)
        #expect(StrokeAccessibility.value(row(gross: -1)) == "hullet vunnet")
    }

    @Test func stablefordHarPoengUtenTegn() {
        let stableford = RoundGame(F.snapshot(F.markorPlayers()))
        let card = stableford.card(hole: 2, drafts: HoleDrafts(), viewer: F.viewer(F.anders))
        let me = card.rows.first { $0.memberID == F.id(F.anders) }!
        #expect(me.parBogey == nil)
        #expect(me.points != nil)
    }

    @Test func tegnetFraNetto() {
        #expect(HoleMath.parBogeyMark(net: 3, par: 4) == "+")
        #expect(HoleMath.parBogeyMark(net: 4, par: 4) == "0")
        #expect(HoleMath.parBogeyMark(net: 6, par: 4) == "−")
    }
}

/// Par/bogey på scorekortet: tegnet per hull, summen med fortegn og «mot banen» totalt.
struct ScorekortParBogeyTests {
    private let me = F.id(F.anders)

    /// Netto par + `offset` på hull 1–3, med slagene spilleren får.
    private func game(_ offsets: [Int], format: String) -> RoundGame {
        let base = RoundGame(F.snapshot(F.markorPlayers(), round: F.round(format: format)))
        let scores = offsets.enumerated().map { i, offset in
            let h = base.holes[i]
            let received = Scoring.handicapStrokes(handicap: base.handicap(me), strokeIndex: h.strokeIndex,
                                                   holes: base.holeCount)
            return (F.anders, i, h.par + received + offset)
        }
        return RoundGame(F.snapshot(F.markorPlayers(), round: F.round(format: format), scores: scores))
    }

    @Test func tegnOgSum() {
        let g = game([-1, 0, 2], format: "par-bogey")
        let card = g.scorecard(for: me, inward: false)
        #expect(card.lines.prefix(3).map(\.parBogey) == ["+", "0", "−"])
        #expect(card.lines[0].points == nil)
        #expect(card.parBogeySum == 0)
        #expect(g.scorecardTotal(for: me) == "0 mot banen")
        let opp = game([-1, -1, 0], format: "par-bogey")
        #expect(opp.scorecard(for: me, inward: false).parBogeySum == 2)
        #expect(opp.scorecardTotal(for: me) == "+2 mot banen")
    }

    @Test func stablefordSomFoer() {
        let g = game([0], format: "stableford")
        let card = g.scorecard(for: me, inward: false)
        #expect(card.lines[0].parBogey == nil && card.lines[0].points == 2)
        #expect(card.parBogeySum == nil)
        #expect(g.scorecardTotal(for: me) == "2 poeng")
    }
}
