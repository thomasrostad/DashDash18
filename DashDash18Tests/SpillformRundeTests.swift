import Foundation
import GolfgutuCore
import Testing
@testable import DashDash18

private typealias F = ForingFixture

/// Slagspill, stableford brutto og maksimumscore i runden (Golfreglene regel 21): hullkortet, scorekortet
/// og «Bayen nå» regner etter formen, ikke som netto stableford. Anders har spillehandicap 18 (ett slag
/// per hull), så brutto og netto skiller seg.
struct SpillformRundeTests {
    private let me = F.id(F.anders)

    private func players() -> [F.P] {
        var ps = F.markorPlayers()
        ps[0].handicap = 18
        ps[0].playing = 18
        return ps
    }

    private func game(_ format: String, scores: [(Int, Int, Int)] = []) -> RoundGame {
        RoundGame(F.snapshot(players(), round: F.round(format: format), scores: scores))
    }

    /// Anders sin rad på hull 3 (par 3) med `gross` slag.
    private func row(_ g: RoundGame, gross: Int) -> HoleCard.Row {
        var drafts = HoleDrafts()
        drafts[2, me] = gross
        return g.card(hole: 2, drafts: drafts, viewer: F.viewer(F.anders)).rows.first { $0.memberID == me }!
    }

    @Test func slagNettoViserNettoNavn() {
        let r = row(game("slag-netto"), gross: 4)
        #expect(r.strokesReceived == 1)
        #expect(r.points == nil)
        #expect(r.formText == "netto par")
        #expect(StrokeAccessibility.value(r) == "netto par")
    }

    /// Brutto ser bort fra handicapet: ingen slag, ingen utregning, navnet mot par.
    @Test func slagBruttoUtenSlag() {
        let r = row(game("slag-brutto"), gross: 4)
        #expect(r.strokesReceived == 0)
        #expect(r.calculation == nil)
        #expect(r.formText == "brutto bogey")
    }

    @Test func stablefordBruttoGirBruttopoeng() {
        let r = row(game("stableford-brutto"), gross: 3)
        #expect(r.points == 2)
        #expect(r.formText == "2 p · brutto par")
    }

    /// Maksimumscore (regel 21.2): stepperen stopper ved netto dobbel bogey (par 3 + 2 + 1 slag = 6).
    @Test func maksimumscoreStopperVedTaket() {
        let r = row(game("maks-score"), gross: 12)
        #expect(r.maxStrokes == 6)
        #expect(r.value == 6)
        #expect(r.formText == "tak 6 slag")
        #expect(row(game("maks-score"), gross: 4).formText == "netto par")
    }

    @Test func nettoStablefordSomFoer() {
        let r = row(game("stableford"), gross: 4)
        #expect(r.points == 2)
        #expect(r.formText == "2 p · netto par")
    }

    /// Scorekortet i slagspill netto: nettoslag per hull, sum og «N slag» totalt.
    @Test func scorekortetISlagspill() {
        // Hull 1–3 er par 4, 5, 3: Anders går 5, 6, 4 (netto par på alle med ett slag per hull).
        let g = game("slag-netto", scores: [(F.anders, 0, 5), (F.anders, 1, 6), (F.anders, 2, 4)])
        let card = g.scorecard(for: me, inward: false)
        #expect(card.valueTitle == "Netto")
        #expect(card.lines.prefix(3).map(\.formValue) == [4, 5, 3])
        #expect(card.lines[0].points == nil)
        #expect(card.formSum == 12)
        #expect(g.scorecardTotal(for: me) == "12 slag")
    }

    /// Deling, «Mine runder», Hjem og Live Activity viser summen i formen («15 slag»), ikke stablefordpoeng.
    @Test func flateneViserFormensSum() {
        let g = game("slag-brutto", scores: [(F.anders, 0, 5), (F.anders, 1, 6), (F.anders, 2, 4),
                                             (F.bjorn, 0, 4), (F.bjorn, 1, 5), (F.bjorn, 2, 3)])
        let rows = g.bayenNaa(viewer: F.viewer(F.anders))
        #expect(rows[0].resultText == "12 slag")
        #expect(MyRounds.value(rows[1]) == "15 slag")
        let live = g.liveActivityContent(for: F.viewer(F.anders))
        #expect(live?.valueText == "15 slag")
        #expect(live?.bayPlace == 2)
        // Netto stableford: ingen egen tekst, poengene som før.
        let stableford = game("stableford", scores: [(F.anders, 0, 5)])
        #expect(stableford.liveActivityContent(for: F.viewer(F.anders))?.valueText == nil)
        #expect(stableford.bayenNaa(viewer: F.viewer(F.anders)).first { $0.isMe }?.resultText.hasSuffix(" p") == true)
    }

    /// «Bayen nå» i slagspill brutto: lavest sum først, og verdien i slag.
    @Test func bayenNaaLavestFoerst() {
        let g = game("slag-brutto", scores: [(F.anders, 0, 5), (F.anders, 1, 6), (F.anders, 2, 4),
                                             (F.bjorn, 0, 4), (F.bjorn, 1, 5), (F.bjorn, 2, 3)])
        let rows = g.bayenNaa(viewer: F.viewer(F.anders))
        #expect(rows[0].members == [F.id(F.bjorn)])
        #expect(rows[0].value == "12 slag")
        #expect(rows[1].members == [me])
        #expect(rows[1].value == "15 slag")
    }
}
