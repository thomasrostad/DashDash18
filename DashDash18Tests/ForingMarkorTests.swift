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

    @Test func parErForvalgtOgLagreErAlltidAktiv() {
        // K1: ett trykk per hull når alle går par.
        var drafts = HoleDrafts()
        let start = game.card(hole: 0, drafts: drafts, viewer: F.viewer(F.anders))
        #expect(start.rows.allSatisfy { $0.isDefault && $0.value == 4 })
        #expect(start.rows.allSatisfy { $0.scoreName == .par && $0.points != nil })   // poengene vises med en gang
        #expect(start.action == .save(title: "Lagre hull 1 og gå videre", enabled: true, status: "0 av 4 endret fra par"))
        let alleParLagres = game.submission(hole: 0, drafts: drafts, viewer: F.viewer(F.anders), recordedAt: .now)
        #expect(alleParLagres?.entries.count == 4)
        #expect(alleParLagres?.entries.allSatisfy { $0.strokes == 4 } == true)

        // Pluss justerer; raden er ikke lenger forvalgt.
        drafts[0, id(F.cato)] = StrokeInput.clamp(4 + 1)
        let endret = game.card(hole: 0, drafts: drafts, viewer: F.viewer(F.anders))
        #expect(endret.rows[2].value == 5 && !endret.rows[2].isDefault)
        #expect(endret.rows.filter(\.isDefault).count == 3)
        #expect(endret.action == .save(title: "Lagre hull 1 og gå videre", enabled: true, status: "1 av 4 endret fra par"))

        // Et tall satt tilbake til par teller som rørt, men ikke som endret fra par.
        drafts[0, id(F.dag)] = 4
        let tilbake = game.card(hole: 0, drafts: drafts, viewer: F.viewer(F.anders))
        #expect(!tilbake.rows[3].isDefault)
        #expect(tilbake.action == .save(title: "Lagre hull 1 og gå videre", enabled: true, status: "1 av 4 endret fra par"))
    }

    @Test func sisteHullHarIkkeGaaVidere() {
        let card = game.card(hole: 17, drafts: HoleDrafts(), viewer: F.viewer(F.anders))
        #expect(card.action == .save(title: "Lagre hull 18", enabled: true, status: "0 av 4 endret fra par"))
    }

    @Test("K6: synkstatus for hullene på kortet")
    func synkstatus() {
        let viewer = F.viewer(F.anders)
        #expect(game.syncStatus(viewer: viewer, pending: []) == nil)
        let fire = [F.anders, F.bjorn, F.cato, F.dag]
        let seks = RoundGame(F.snapshot(F.markorPlayers(), scores: (0..<6).flatMap { h in fire.map { ($0, h, 4) } }))
        #expect(seks.syncStatus(viewer: viewer, pending: []) == SyncStatus(text: "Hull 1–6 er synket", isPending: false))
        #expect(seks.syncStatus(viewer: viewer, pending: [6])
            == SyncStatus(text: "Lagret på telefonen · sendes når du får dekning", isPending: true))
        let ett = RoundGame(F.snapshot(F.markorPlayers(), scores: fire.map { ($0, 0, 4) }))
        #expect(ett.syncStatus(viewer: viewer, pending: []) == SyncStatus(text: "Hull 1 er synket", isPending: false))
        // Seeren fører ikke og får ingen linje.
        #expect(seks.syncStatus(viewer: F.viewer(F.bjorn), pending: []) == nil)
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
        #expect(card.action == .save(title: "Lagre hull 1 og gå videre", enabled: true, status: nil))
        #expect(uten.markerLine(for: F.viewer(F.bjorn)) == nil)
        #expect(card.header == "Ditt kort")
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
            == .save(title: "Lagre endringen · hull 1", enabled: true, status: "1 av 4 endret fra par"))
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

/// sql/071: i en form med ett kort per lag fører alle på laget lagets kort, også med markør i båsen.
struct ForingLagkameratTests {
    /// Scramble-4 med markør: Anders, Bjørn, Cato og Dag er lag 1 i bås 1, resten lag 2 i bås 2.
    fileprivate static func players(team: (Int) -> Int?) -> [F.P] {
        F.markorPlayers().map { p in
            var p = p
            p.team = team(p.n)
            return p
        }
    }

    let game = RoundGame(F.snapshot(ForingLagkameratTests.players { $0 <= 4 ? 1 : 2 },
                                    round: F.round(format: "scramble-4")))

    @Test func lagkameratenFoererHeleLaget() {
        for p in [F.anders, F.bjorn, F.cato, F.dag] {
            #expect(game.canScore(F.viewer(F.bjorn), for: id(p)))
        }
        for p in [F.erik, F.frode, F.halvor] {
            #expect(!game.canScore(F.viewer(F.bjorn), for: id(p)))
        }
        #expect(game.isOnTeamCard(id(F.bjorn), with: id(F.anders)))
        #expect(!game.isOnTeamCard(id(F.bjorn), with: id(F.erik)))
    }

    @Test func kortetErRedigerbartForLagkameraten() {
        let viewer = F.viewer(F.bjorn)
        #expect(game.cardRows(for: viewer) == [id(F.bjorn)])
        let card = game.card(hole: 0, drafts: HoleDrafts(), viewer: viewer)
        #expect(card.rows.map(\.name) == ["Anders, Bjørn, Cato og Dag"])
        #expect(card.rows.allSatisfy { $0.editable })
        #expect(!card.mustConfirm)
        #expect(game.scoringTitle(viewer: viewer).subtitle == "Du fører for laget ditt")
        // Markøren fører fortsatt for båsen.
        #expect(game.scoringTitle(viewer: F.viewer(F.anders)).subtitle == "Du fører for bås 1")
    }

    @Test func lagreHullSkriverPaaHeleLaget() {
        var drafts = HoleDrafts()
        drafts[0, id(F.bjorn)] = 3
        let sub = game.submission(hole: 0, drafts: drafts, viewer: F.viewer(F.bjorn), recordedAt: Date())
        #expect(Set(sub?.entries.map(\.memberID) ?? []) == Set([F.anders, F.bjorn, F.cato, F.dag].map(id)))
        #expect(sub?.entries.allSatisfy { $0.strokes == 3 } == true)
    }

    /// To lag i samme bås: du fører ditt eget lag, ikke det andre.
    @Test func detAndreLagetIBaasenFoererDuIkke() {
        let g = RoundGame(F.snapshot(Self.players { ($0 + 1) / 2 }, round: F.round(format: "scramble-2")))
        let viewer = F.viewer(F.bjorn)
        #expect(g.cardRows(for: viewer) == [id(F.bjorn), id(F.cato)])
        #expect(g.cardRowEditable(id(F.bjorn), for: viewer))
        #expect(!g.cardRowEditable(id(F.cato), for: viewer))
        #expect(!g.canScore(viewer, for: id(F.cato)))

        var drafts = HoleDrafts()
        drafts[0, id(F.bjorn)] = 4
        drafts[0, id(F.cato)] = 5
        let sub = g.submission(hole: 0, drafts: drafts, viewer: viewer, recordedAt: Date())
        #expect(Set(sub?.entries.map(\.memberID) ?? []) == Set([F.anders, F.bjorn].map(id)))
    }

    /// Ett kort per spiller (fourball), sql/074: lagkameratene fører for hverandre, også med markør i
    /// båsen. Lag 1 er Anders og Bjørn, lag 2 Cato og Dag, i bås 1 med Anders som markør.
    @Test func fourballLagkameraterFoererForHverandre() {
        let g = RoundGame(F.snapshot(Self.players { ($0 + 1) / 2 }, round: F.round(format: "fourball")))
        let viewer = F.viewer(F.bjorn)
        #expect(g.canScore(viewer, for: id(F.anders)))
        #expect(g.canScore(viewer, for: id(F.bjorn)))
        #expect(!g.canScore(viewer, for: id(F.cato)))
        #expect(!g.isOnTeamCard(id(F.bjorn), with: id(F.anders)))
        #expect(g.isTeamScorer(id(F.bjorn), for: id(F.anders)))
        #expect(g.scoringTitle(viewer: viewer).subtitle == "Du fører for laget ditt")
        // Én rad per spiller i båsen; Bjørn fører sin egen og lagkameratens.
        let card = g.card(hole: 0, drafts: HoleDrafts(), viewer: viewer)
        #expect(card.rows.filter(\.editable).map(\.memberID) == [id(F.bjorn), id(F.anders)])
        var drafts = HoleDrafts()
        drafts[0, id(F.anders)] = 5
        drafts[0, id(F.bjorn)] = 4
        let sub = g.submission(hole: 0, drafts: drafts, viewer: viewer, recordedAt: Date())
        #expect(Set(sub?.entries.map(\.memberID) ?? []) == Set([F.anders, F.bjorn].map(id)))
        #expect(sub?.entries.first { $0.memberID == id(F.anders) }?.strokes == 5)
        // Markøren fører fortsatt hele båsen.
        #expect(g.canScore(F.viewer(F.anders), for: id(F.cato)))
    }

    /// `play.teammatesScore` av: markøren fører som før, lagkameraten ikke.
    @Test func fourballUtenLagkameraterSomFoer() {
        var s = F.snapshot(Self.players { ($0 + 1) / 2 }, round: F.round(format: "fourball"))
        s.rules.play.teammatesScore = false
        let g = RoundGame(s)
        #expect(!g.canScore(F.viewer(F.bjorn), for: id(F.anders)))
        #expect(!g.canScore(F.viewer(F.bjorn), for: id(F.bjorn)))
        #expect(!g.isTeamScorer(id(F.bjorn), for: id(F.anders)))
        #expect(g.scoringTitle(viewer: F.viewer(F.bjorn)).subtitle == "Bås 1 · Anders fører")
    }

    /// En-mot-en (stableford med lagnummer, som Ryder Cup-singler): ingen lagkamerater, markøren som før.
    @Test func enMotEnHarIngenLagkamerater() {
        let g = RoundGame(F.snapshot(Self.players { ($0 + 1) / 2 }, round: F.round(format: "stableford")))
        #expect(!g.isTeamScorer(id(F.bjorn), for: id(F.anders)))
        #expect(!g.canScore(F.viewer(F.bjorn), for: id(F.anders)))
    }

    /// Lag med én ball (sql/071) fører lagets kort uansett valget.
    @Test func lagkortetUansettValget() {
        var s = F.snapshot(Self.players { $0 <= 4 ? 1 : 2 }, round: F.round(format: "scramble-4"))
        s.rules.play.teammatesScore = false
        #expect(RoundGame(s).canScore(F.viewer(F.bjorn), for: id(F.anders)))
    }

    /// Scramble uten lag (team_no mangler): markøren som før.
    @Test func utenLagMarkoerenSomFoer() {
        let g = RoundGame(F.snapshot(F.markorPlayers(), round: F.round(format: "scramble-2")))
        #expect(!g.canScore(F.viewer(F.bjorn), for: id(F.bjorn)))
        #expect(!g.canScore(F.viewer(F.bjorn), for: id(F.anders)))
    }

    /// Runden går ikke: bare arrangøren, også for laget.
    @Test(arguments: [RoundStatus.draft, .locked])
    func kladdOgLaastSomFoer(status: RoundStatus) {
        let g = RoundGame(F.snapshot(Self.players { $0 <= 4 ? 1 : 2 },
                                     round: F.round(status: status, format: "scramble-4")))
        #expect(!g.canScore(F.viewer(F.bjorn), for: id(F.anders)))
        #expect(!g.cardRowEditable(id(F.bjorn), for: F.viewer(F.bjorn)))
    }

    /// Levert kort (sql/057) går foran: bare arrangøren.
    @Test func levertKortGaarForan() {
        var s = game.snapshot
        s.players = s.players.map { p in
            var p = p
            if p.teamNo == 1 { p.cardSubmittedAt = Date(timeIntervalSince1970: 1) }
            return p
        }
        let g = RoundGame(s)
        #expect(!g.canScore(F.viewer(F.bjorn), for: id(F.anders)))
        #expect(!g.cardRowEditable(id(F.bjorn), for: F.viewer(F.bjorn)))
        #expect(g.canScore(F.viewer(F.bjorn), for: id(F.anders), ignoringSubmission: true))
        #expect(g.canScore(F.viewer(F.gunnar), for: id(F.anders)))
    }
}
