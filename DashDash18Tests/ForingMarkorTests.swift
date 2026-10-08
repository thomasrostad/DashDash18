import Foundation
import GolfgutuCore
import Testing
@testable import DashDash18

private typealias F = ForingFixture
private func id(_ n: Int) -> UUID { F.id(n) }

/// markor-test.js: markør per bås (`kanFore`), hullkortet og seer-modus.
struct ForingKanForeTests {
    let game = RoundGame(F.snapshot(F.markorPlayers()))

    @Test func baasene() {
        #expect(game.hasBays)
        #expect(game.bays[1]?.players.count == 4)
        #expect(game.bays[1]?.marker == id(F.anders))
        #expect(game.bays[2]?.marker == id(F.erik))
    }

    @Test func markoerenFoererForHeleBaasenSin() {
        for p in [F.anders, F.bjorn, F.cato, F.dag] {
            #expect(game.canScore(F.viewer(F.anders), for: id(p)))
        }
    }

    @Test func markoerenRekkerIkkeOverINabobaasen() {
        for p in [F.erik, F.frode, F.halvor] {
            #expect(!game.canScore(F.viewer(F.anders), for: id(p)))
        }
        #expect(game.canScore(F.viewer(F.erik), for: id(F.frode)))
        #expect(!game.canScore(F.viewer(F.erik), for: id(F.bjorn)))
    }

    @Test func deAndreSkriverIngenting() {
        #expect(!game.canScore(F.viewer(F.bjorn), for: id(F.bjorn)))
        #expect(!game.canScore(F.viewer(F.bjorn), for: id(F.cato)))
        #expect(!game.canScore(F.viewer(F.frode), for: id(F.frode)))
    }

    @Test func arrangoerenStaarOver() {
        #expect(game.canScore(F.viewer(F.gunnar), for: id(F.bjorn)))
        #expect(game.canScore(F.viewer(F.gunnar), for: id(F.anders)))
        let locked = RoundGame(F.snapshot(F.markorPlayers(), round: F.round(status: .locked)))
        #expect(locked.canScore(F.viewer(F.gunnar), for: id(F.bjorn)))
        #expect(!locked.canScore(F.viewer(F.anders), for: id(F.bjorn)))
    }

    /// Innstramming i `can_score`: en kladd føres bare av arrangøren (PWA-en tillot det).
    @Test func kladdFoeresBareAvArrangoeren() {
        let draft = RoundGame(F.snapshot(F.markorPlayers(), round: F.round(status: .draft)))
        #expect(!draft.canScore(F.viewer(F.anders), for: id(F.bjorn)))
        #expect(!draft.canScore(F.viewer(F.anders), for: id(F.anders)))
        #expect(draft.canScore(F.viewer(F.gunnar), for: id(F.bjorn)))
    }

    @Test func utenBaasoppsettSomFoer() {
        let uten = RoundGame(F.snapshot(F.markorPlayers(bays: false)))
        #expect(!uten.hasBays)
        #expect(uten.canScore(F.viewer(F.bjorn), for: id(F.bjorn)))
        #expect(!uten.canScore(F.viewer(F.bjorn), for: id(F.cato)))
        #expect(uten.canScore(F.viewer(F.gunnar), for: id(F.bjorn)))
    }

    @Test func baasUtenMarkoerFallerTilbakePaaDinEgen() {
        let players = [F.P(n: F.anders, name: "Anders", bay: 1), F.P(n: F.bjorn, name: "Bjørn", bay: 1)]
        let g = RoundGame(F.snapshot(players))
        #expect(g.canScore(F.viewer(F.bjorn), for: id(F.bjorn)))
        #expect(!g.canScore(F.viewer(F.bjorn), for: id(F.anders)))
    }
}

struct ForingHullkortTests {
    let game = RoundGame(F.snapshot(F.markorPlayers()))

    @Test func markoerenSerHeleBaasenMedSegSelvFoerst() {
        let card = game.card(hole: 0, drafts: HoleDrafts(), viewer: F.viewer(F.anders))
        #expect(card.rows.map(\.name) == ["Anders", "Bjørn", "Cato", "Dag"])
        #expect(card.rows.allSatisfy { $0.editable })
        #expect(card.rows.first?.isMe == true)
        #expect(game.markerLine(for: F.viewer(F.anders)) == "Du er markør i bås 1 · Bjørn, Cato, Dag og deg")
    }

    @Test func lagreErLaastTilAlleErBekreftet() {
        var drafts = HoleDrafts()
        let start = game.card(hole: 0, drafts: drafts, viewer: F.viewer(F.anders))
        #expect(start.rows.allSatisfy { !$0.confirmed })
        #expect(start.rows.allSatisfy { $0.value == 4 })   // stiplet par
        #expect(start.showsParHint)
        #expect(start.action == .save(title: "Lagre hull 1", enabled: false,
                                      blocker: "Bekreft Anders, Bjørn, Cato og Dag først · 0 av 4 klare"))

        // Trykk på tallet bekrefter par; pluss justerer og bekrefter samtidig.
        drafts[0, id(F.anders)] = 4
        drafts[0, id(F.bjorn)] = 4
        drafts[0, id(F.cato)] = StrokeInput.clamp(4 + 1)
        let treAv = game.card(hole: 0, drafts: drafts, viewer: F.viewer(F.anders))
        #expect(treAv.action == .save(title: "Lagre hull 1", enabled: false, blocker: "Bekreft Dag først · 3 av 4 klare"))
        #expect(treAv.rows[2].value == 5 && treAv.rows[2].confirmed)
        #expect(treAv.rows.filter { !$0.confirmed }.count == 1)

        drafts[0, id(F.dag)] = 4
        let alle = game.card(hole: 0, drafts: drafts, viewer: F.viewer(F.anders))
        #expect(alle.action == .save(title: "Lagre hull 1 → hull 2", enabled: true, blocker: nil))
        #expect(!alle.showsParHint)
    }

    @Test func seerModus() {
        let viewer = F.viewer(F.bjorn)
        let card = game.card(hole: 0, drafts: HoleDrafts(), viewer: viewer)
        #expect(card.rows.count == 4)
        #expect(card.rows.allSatisfy { !$0.editable })
        #expect(card.rows.first?.isMe == true && card.rows.first?.name == "Bjørn")
        #expect(card.rows.allSatisfy { $0.scoreName == nil && $0.saved == nil })   // «ikke lagret ennå»
        #expect(card.action == .none)
        #expect(card.viewerHint == "Feil tall? Si det til Anders.")
        #expect(game.markerLine(for: viewer) == "Bås 1 · Anders fører · du ser det live")
    }

    @Test func seerSerFoerteTall() {
        let g = RoundGame(F.snapshot(F.markorPlayers(), scores: [(F.anders, 0, 3), (F.bjorn, 0, 4)]))
        let card = g.card(hole: 0, drafts: HoleDrafts(), viewer: F.viewer(F.bjorn))
        #expect(card.rows.first { $0.name == "Anders" }?.scoreName == .birdie)
        #expect(card.rows.first { $0.name == "Anders" }?.points == 3)
        #expect(card.rows.first { $0.name == "Cato" }?.saved == nil)
    }

    @Test func arrangoerenSomIkkeErMarkoerFoererIkkePaaKortet() {
        let card = game.card(hole: 0, drafts: HoleDrafts(), viewer: F.viewer(F.gunnar))
        #expect(card.rows.allSatisfy { !$0.editable })
        #expect(card.action == .none)
    }

    @Test func utenBaaserStaarBareDuOgIngenBekreftelse() {
        let uten = RoundGame(F.snapshot(F.markorPlayers(bays: false)))
        let card = uten.card(hole: 0, drafts: HoleDrafts(), viewer: F.viewer(F.bjorn))
        #expect(card.rows.map(\.name) == ["Bjørn"])
        #expect(!card.mustConfirm && card.rows[0].confirmed)
        #expect(card.action == .save(title: "Lagre hull 1 → hull 2", enabled: true, blocker: nil))
        #expect(uten.markerLine(for: F.viewer(F.bjorn)) == nil)
        #expect(card.header == "Deg")
    }

    @Test func ikkeMedIRundenIngenRader() {
        let g = RoundGame(F.snapshot(Array(F.markorPlayers().prefix(4))))
        #expect(g.cardPlayers(for: F.viewer(F.gunnar)).isEmpty)
    }

    @Test func hullnummerPaaSisteNi() {
        let siste = RoundGame(F.snapshot(F.markorPlayers(), round: F.round(holeCount: 9, firstHole: 10)))
        #expect(siste.card(hole: 0, drafts: HoleDrafts(), viewer: F.viewer(F.anders)).title == "Hull 10 · 1 av 9 i runden")
        #expect(siste.holeNumber(8) == 18)
        #expect(game.card(hole: 0, drafts: HoleDrafts(), viewer: F.viewer(F.anders)).title == "Hull 1 av 18")
    }

    @Test func lagretOgUroertGaarVidereUtenAaLagre() {
        let scores = [F.anders, F.bjorn, F.cato, F.dag].map { ($0, 0, 4) }
        let g = RoundGame(F.snapshot(F.markorPlayers(), scores: scores))
        let card = g.card(hole: 0, drafts: HoleDrafts(), viewer: F.viewer(F.anders))
        #expect(card.action == .next(title: "Neste hull → hull 2", hole: 1))
        var drafts = HoleDrafts()
        drafts[0, id(F.cato)] = 5
        #expect(g.card(hole: 0, drafts: drafts, viewer: F.viewer(F.anders)).action
            == .save(title: "Lagre endringen · hull 1 → hull 2", enabled: true, blocker: nil))
    }

    @Test func solStripa() {
        let viewer = F.viewer(F.bjorn)
        #expect(game.bayStripe(currentHole: 0, viewer: viewer) == nil)
        let stripe = game.bayStripe(currentHole: 3, viewer: viewer)
        #expect(stripe?.text == "Du ser på hull 4. Båsen er på hull 1.")
        #expect(stripe?.button == "Til hull 1 →")
        #expect(stripe?.hole == 0)
        let siste = RoundGame(F.snapshot(F.markorPlayers(), round: F.round(holeCount: 9, firstHole: 10)))
        #expect(siste.bayStripe(currentHole: 4, viewer: viewer)?.text == "Du ser på hull 14. Båsen er på hull 10.")
        let laast = RoundGame(F.snapshot(F.markorPlayers(), round: F.round(status: .locked)))
        #expect(laast.bayStripe(currentHole: 3, viewer: viewer) == nil)
    }
}
