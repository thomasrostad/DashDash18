import Foundation
import GolfgutuCore
import Testing
@testable import DashDash18

private typealias F = ForingFixture
private func id(_ n: Int) -> UUID { F.id(n) }

/// brutto-test.js: brutto inn, stableford ut. Anders hcp 18, Bjørn 0, Cato 7, på en bane med
/// stroke index i en annen rekkefølge enn hullene. Alt går gjennom radene → GolfgutuCore.
struct ForingBruttoTests {
    static let players = [F.P(n: 1, name: "Anders", handicap: 18), F.P(n: 2, name: "Bjørn", handicap: 0),
                          F.P(n: 3, name: "Cato", handicap: 7)]
    let game = RoundGame(F.snapshot(players, si: F.bruttoSI))

    @Test func handicapFraRadene() {
        #expect(game.handicap(id(1)) == 18)
        #expect(game.handicap(id(2)) == 0)
        #expect(game.handicap(id(3)) == 7)
    }

    @Test func slagenePaaDeVanskeligsteHullene() {
        let card = game.card(hole: 0, drafts: HoleDrafts(), viewer: Viewer(memberID: id(1), isOrganizer: false))
        #expect(card.rows[0].strokesReceived == 1)
        let withStroke = game.holes.filter {
            Scoring.handicapStrokes(handicap: game.handicap(id(3)), strokeIndex: $0.strokeIndex, holes: 18) == 1
        }.map(\.strokeIndex).sorted()
        #expect(withStroke == Array(1...7))
    }

    @Test func regnestykketPaaHull2() {
        // Hull 2: par 5, indeks 1. Cato får ett slag. 6 brutto = netto par = 2 poeng.
        #expect(game.holes[1].par == 5 && game.holes[1].strokeIndex == 1)
        let cato = Viewer(memberID: id(3), isOrganizer: false)
        var drafts = HoleDrafts()
        drafts[1, id(3)] = 6
        let row = game.card(hole: 1, drafts: drafts, viewer: cato).rows[0]
        #expect(row.strokesReceived == 1)
        #expect(row.calculation == "6 brutto − 1 = 5 netto")
        #expect(row.scoreName == .par)
        #expect(row.points == 2)
        drafts[1, id(3)] = 5
        #expect(game.card(hole: 1, drafts: drafts, viewer: cato).rows[0].points == 3)
        drafts[1, id(3)] = 8
        #expect(game.card(hole: 1, drafts: drafts, viewer: cato).rows[0].points == 0)
    }

    @Test func hull11UtenSlag() {
        let cato = Viewer(memberID: id(3), isOrganizer: false)
        #expect(game.holes[10].par == 3 && game.holes[10].strokeIndex == 18)
        var drafts = HoleDrafts()
        drafts[10, id(3)] = 3
        let row = game.card(hole: 10, drafts: drafts, viewer: cato).rows[0]
        #expect(row.strokesReceived == 0 && row.points == 2)
        #expect(row.calculation == "3 brutto − 0 = 3 netto")
        drafts[10, id(3)] = 4
        #expect(game.card(hole: 10, drafts: drafts, viewer: cato).rows[0].points == 1)
    }

    @Test func parRundtBruttoGir43() {
        let scores = F.par.indices.map { (3, $0, F.par[$0]) }
        let g = RoundGame(F.snapshot(Self.players, si: F.bruttoSI, scores: scores))
        #expect(g.total(id(3)) == 43)
        // Scorekortet: Ut 22 + Inn 21. Par 36 ut.
        let ut = g.scorecard(for: id(3), inward: false)
        let inn = g.scorecard(for: id(3), inward: true)
        #expect(ut.sumPar == 36 && ut.sumPoints == 22)
        #expect(inn.sumPoints == 21 && inn.lines.first?.number == 10)
        #expect(ut.sumStrokes == 36)
    }

    @Test func gammelTrackmanRundeRegnesSomFoer() {
        let scores = F.par.indices.map { (3, $0, F.par[$0]) }
        let g = RoundGame(F.snapshot(Self.players, round: F.round(externalHandicap: true), si: F.bruttoSI, scores: scores))
        #expect(g.handicap(id(3)) == 0)
        #expect(g.total(id(3)) == 36)
        let card = g.card(hole: 1, drafts: HoleDrafts(), viewer: Viewer(memberID: id(3), isOrganizer: false))
        #expect(card.strokesLabel == "Slag · netto")
        #expect(card.rows[0].calculation == nil)
        #expect(!card.detail.contains("indeks"))
        #expect(game.card(hole: 1, drafts: HoleDrafts(), viewer: Viewer(memberID: id(3), isOrganizer: false))
            .strokesLabel == "Slag · brutto")
    }

    @Test func niHullGirHalveSlag() {
        let ni = RoundGame(F.snapshot(Self.players, round: F.round(holeCount: 9), si: F.bruttoSI))
        #expect(ni.handicap(id(1)) == 9)
    }

    /// `playing_handicap` er fasiten når den er lagret.
    @Test func lagretSpillehandicapVinner() {
        var players = Self.players
        players[2].playing = 10
        let g = RoundGame(F.snapshot(players, si: F.bruttoSI))
        #expect(g.handicap(id(3)) == 10)
    }

    @Test func hullinjaMedParMeterOgIndeks() {
        let card = game.card(hole: 1, drafts: HoleDrafts(), viewer: Viewer(memberID: id(3), isOrganizer: false))
        #expect(card.detail == "Par 5 · indeks 1")
    }
}

/// Båsens hull (`baasensHull`) og hva «Lagre» sender.
struct ForingLagringTests {
    let bay = [F.anders, F.bjorn, F.cato, F.dag]

    @Test func baasensHullErFoersteHullDerIkkeAlleErFoert() {
        let tom = RoundGame(F.snapshot(F.markorPlayers()))
        #expect(tom.bayHole(for: F.viewer(F.bjorn)) == 0)

        let to = bay.flatMap { p in [(p, 0, 4), (p, 1, 5)] } + [(F.anders, 2, 3)]
        let g = RoundGame(F.snapshot(F.markorPlayers(), scores: to))
        #expect(g.bayHole(for: F.viewer(F.bjorn)) == 2)
        #expect(g.bayHole(for: F.viewer(F.erik)) == 0)    // bås 2 har ikke begynt

        let alle = bay.flatMap { p in (0..<18).map { (p, $0, 4) } }
        #expect(RoundGame(F.snapshot(F.markorPlayers(), scores: alle)).bayHole(for: F.viewer(F.anders)) == 17)
    }

    @Test func hullprikkene() {
        let scores = bay.map { ($0, 0, 4) } + [(F.anders, 1, 5)]
        let g = RoundGame(F.snapshot(F.markorPlayers(), scores: scores))
        let dots = g.dots(currentHole: 1, viewer: F.viewer(F.bjorn), pending: [1])
        #expect(dots.count == 18)
        #expect(dots[0].state == .done)
        #expect(dots[1].state == .partial && dots[1].isCurrent && dots[1].isPending && dots[1].isBayHole)
        #expect(dots[2].state == .upcoming)
        // Forslagene: LD på første par 5 fra hull 4 (hull 7), KP på første par 3 fra hull 4 (hull 6).
        #expect(dots[6].isLongestDrive && dots[5].isClosestToPin)
    }

    @Test func bareEndredeRaderSendes() {
        let g = RoundGame(F.snapshot(F.markorPlayers(), scores: [(F.anders, 0, 4), (F.bjorn, 0, 5)]))
        var drafts = HoleDrafts()
        drafts[0, id(F.anders)] = 4    // som lagret
        drafts[0, id(F.bjorn)] = 6     // endret
        drafts[0, id(F.cato)] = 4      // ny, par
        drafts[0, id(F.dag)] = 5
        let at = Date(timeIntervalSince1970: 1_000)
        let sub = g.submission(hole: 0, drafts: drafts, viewer: F.viewer(F.anders), recordedAt: at)
        #expect(sub?.roundID == F.roundID && sub?.holeIndex == 0 && sub?.recordedAt == at)
        #expect(sub?.entries == [
            HoleSubmission.Entry(memberID: id(F.bjorn), strokes: 6),
            HoleSubmission.Entry(memberID: id(F.cato), strokes: 4),
            HoleSubmission.Entry(memberID: id(F.dag), strokes: 5),
        ])
    }

    @Test func ingentingEndretSenderIngenting() {
        let scores = bay.map { ($0, 0, 4) }
        let g = RoundGame(F.snapshot(F.markorPlayers(), scores: scores))
        #expect(g.submission(hole: 0, drafts: HoleDrafts(), viewer: F.viewer(F.anders), recordedAt: Date()) == nil)
        var drafts = HoleDrafts()
        drafts[0, id(F.bjorn)] = 4
        #expect(g.submission(hole: 0, drafts: drafts, viewer: F.viewer(F.anders), recordedAt: Date()) == nil)
    }

    @Test func seerSenderIngenting() {
        let g = RoundGame(F.snapshot(F.markorPlayers()))
        var drafts = HoleDrafts()
        drafts[0, id(F.bjorn)] = 3
        #expect(g.submission(hole: 0, drafts: drafts, viewer: F.viewer(F.bjorn), recordedAt: Date()) == nil)
        #expect(g.submission(hole: 0, drafts: drafts, viewer: F.viewer(F.gunnar), recordedAt: Date()) == nil)
    }

    /// `saveHoleScore`: spiller laget én ball, skrives samme tall på hele laget.
    @Test func ettKortPerLagSkriverPaaHeleLaget() {
        var players = F.markorPlayers()
        players[0].team = 1
        players[1].team = 1
        let round = F.round(format: "scramble-2")
        let g = RoundGame(F.snapshot(players, round: round))
        let uten = RoundGame(F.snapshot(F.markorPlayers(bays: false).map { var p = $0; p.team = $0.n <= 2 ? 1 : nil; return p },
                                        round: round))
        var drafts = HoleDrafts()
        drafts[0, id(F.anders)] = 3
        let sub = uten.submission(hole: 0, drafts: drafts, viewer: F.viewer(F.gunnar), recordedAt: Date())
        // Arrangøren uten bås fører bare sin egen rad, og Gunnar er ikke på laget.
        #expect(sub?.entries.map(\.memberID) == [id(F.gunnar)])
        #expect(g.recipients(for: id(F.anders)) == [id(F.anders), id(F.bjorn)])
        #expect(g.recipients(for: id(F.cato)) == [id(F.cato)])
    }

    /// Scramble med markør: laget står én gang på kortet, og tallet går til alle fire.
    @Test func scrambleViserLagetSomEnRad() {
        let players = F.markorPlayers().map { var p = $0; p.team = p.n <= 4 ? 1 : 2; return p }
        let g = RoundGame(F.snapshot(players, round: F.round(format: "scramble-4")))
        let viewer = F.viewer(F.anders)
        #expect(g.cardRows(for: viewer) == [id(F.anders)])
        let card = g.card(hole: 0, drafts: HoleDrafts(), viewer: viewer)
        #expect(card.rows.map(\.name) == ["Anders, Bjørn, Cato og Dag"])
        #expect(!card.mustConfirm)

        var drafts = HoleDrafts()
        drafts[0, id(F.anders)] = 3
        let sub = g.submission(hole: 0, drafts: drafts, viewer: viewer, recordedAt: Date())
        #expect(sub?.entries.map(\.memberID) == [F.anders, F.bjorn, F.cato, F.dag].map(id))
        #expect(sub?.entries.allSatisfy { $0.strokes == 3 } == true)
    }

    /// To lag i samme flight: én rad per lag, og hvert lag får sitt eget tall.
    @Test func toScrambleLagIFlightenFaarHverSinRad() {
        let players = F.markorPlayers().map { var p = $0; p.team = (p.n + 1) / 2; return p }
        let g = RoundGame(F.snapshot(players, round: F.round(format: "scramble-2")))
        let viewer = F.viewer(F.anders)
        #expect(g.cardRows(for: viewer) == [id(F.anders), id(F.cato)])
        #expect(g.card(hole: 0, drafts: HoleDrafts(), viewer: viewer).rows.map(\.name)
                == ["Anders og Bjørn", "Cato og Dag"])

        var drafts = HoleDrafts()
        drafts[0, id(F.cato)] = 5
        let sub = g.submission(hole: 0, drafts: drafts, viewer: viewer, recordedAt: Date())
        let strokes = Dictionary(uniqueKeysWithValues: (sub?.entries ?? []).map { ($0.memberID, $0.strokes) })
        let par = g.holes[0].par
        #expect(strokes == [id(F.anders): par, id(F.bjorn): par, id(F.cato): 5, id(F.dag): 5])
    }

    /// Funksjonæren for flight 2 spiller ikke selv, men fører hele flighten (sql/032 og 058).
    @Test func funksjonaerForerGruppaSi() {
        let g = RoundGame(F.snapshot(F.markorPlayers()))
        let viewer = Viewer(memberID: id(99), isOrganizer: false, scorerGroups: [2])
        let flight = [F.erik, F.frode, F.gunnar, F.halvor].map(id)
        #expect(Set(g.cardPlayers(for: viewer)) == Set(flight))
        #expect(flight.allSatisfy { g.cardRowEditable($0, for: viewer) })
        #expect(!g.canScore(viewer, for: id(F.anders)))
        #expect(g.canConfirmPar(viewer))

        var drafts = HoleDrafts()
        drafts[0, id(F.frode)] = 6
        let sub = g.submission(hole: 0, drafts: drafts, viewer: viewer, recordedAt: Date())
        #expect(Set(sub?.entries.map(\.memberID) ?? []) == Set(flight))
        #expect(sub?.entries.first { $0.memberID == id(F.frode) }?.strokes == 6)
    }

    @Test func utenFunksjonaerrolleIngentingAaFore() {
        let g = RoundGame(F.snapshot(F.markorPlayers()))
        let viewer = Viewer(memberID: id(99), isOrganizer: false)
        #expect(g.cardPlayers(for: viewer).isEmpty)
        #expect(!g.canConfirmPar(viewer))
        // En gruppe som ikke finnes i runden gir heller ikke noe kort.
        #expect(g.cardPlayers(for: Viewer(memberID: id(99), isOrganizer: false, scorerGroups: [7])).isEmpty)
    }

    @Test func lagreRettEtterHullbytteSperres() {
        let changed = Date(timeIntervalSince1970: 100)
        #expect(!SaveTapGuard.allows(now: changed.addingTimeInterval(0.2), holeChangedAt: changed))
        #expect(SaveTapGuard.allows(now: changed.addingTimeInterval(0.6), holeChangedAt: changed))
        #expect(SaveTapGuard.allows(now: changed, holeChangedAt: .distantPast))
    }

    @Test func steppereHolderSegInnenforGrensa() {
        #expect(StrokeInput.clamp(0) == 1)
        #expect(StrokeInput.clamp(13) == 12)
        #expect(StrokeInput.clamp(5) == 5)
    }

    @Test func koOgSvarLeggesInn() {
        var s = F.snapshot(F.markorPlayers(), scores: [(F.anders, 0, 4)])
        let queued = [QueuedHole(hole: 0, entries: [HoleSubmission.Entry(memberID: id(F.anders), strokes: 5),
                                                    HoleSubmission.Entry(memberID: id(F.bjorn), strokes: 3)])]
        let g = RoundGame(s.overlaying(queued))
        #expect(g.scores(id(F.anders))[0] == 5 && g.scores(id(F.bjorn))[0] == 3)

        let row = HoleScoreRow(roundID: F.roundID, memberID: id(F.bjorn), holeIndex: 0, strokes: 4,
                               recordedAt: nil, updatedBy: nil, updatedAt: nil)
        s.apply(saved: [row], hole: 0, members: [id(F.anders), id(F.bjorn)])
        let after = RoundGame(s)
        #expect(after.scores(id(F.anders))[0] == nil)   // tømt på serveren
        #expect(after.scores(id(F.bjorn))[0] == 4)
    }

    /// Hull i kø står også etter omstart: båsen er videre, og hullet er ført (ikke par med «Lagre»).
    @Test func hullIKoStaarEtterOmstart() {
        let s = F.snapshot(F.markorPlayers())
        let bay = [F.anders, F.bjorn, F.cato, F.dag]
        let queued = HoleSubmission(roundID: F.roundID, holeIndex: 0,
                                    entries: bay.map { HoleSubmission.Entry(memberID: id($0), strokes: 5) },
                                    recordedAt: Date(timeIntervalSince1970: 0))
        let anders = F.viewer(F.anders)
        #expect(RoundGame(s).bayHole(for: anders) == 0)

        let g = RoundGame(s.overlaying([QueuedHole(queued)]))
        #expect(g.bayHole(for: anders) == 1)
        let card = g.card(hole: 0, drafts: HoleDrafts(), viewer: anders)
        #expect(card.rows.allSatisfy { $0.saved == 5 })
        #expect(card.action == .next(title: "Neste hull → hull 2", hole: 1))
        #expect(g.submission(hole: 0, drafts: HoleDrafts(), viewer: anders, recordedAt: .now) == nil)
    }
}

/// Mapping rader → GolfgutuCore.
struct ForingMappingTests {
    @Test func sisteNiStarterPaaBanensHull10() {
        let g = RoundGame(F.snapshot(F.markorPlayers(), round: F.round(holeCount: 9, firstHole: 10), si: F.bruttoSI))
        #expect(g.round.holeStart == 9 && g.round.numberOfHoles == 9)
        #expect(g.holes.map(\.par) == Array(F.par[9...]))
        #expect(g.holes[0].cardIndex == 8)
    }

    @Test func rundensEgneHullOverstyrerBanen() {
        var s = F.snapshot(F.markorPlayers())
        s.roundHoles = [RoundHoleRow(roundID: F.roundID, holeIndex: 0, par: 5, strokeIndex: 18, lengthM: 480)]
        let g = RoundGame(s)
        #expect(g.holes[0].par == 5 && g.holes[0].cardIndex == 18 && g.holes[0].meters == 480)
        #expect(g.card(hole: 0, drafts: HoleDrafts(), viewer: F.viewer(F.anders)).detail == "Par 5 · 480 m · indeks 18")
    }

    @Test func ufullstendigBaneGirStandardpar() {
        var s = F.snapshot(F.markorPlayers())
        s.courseHoles = Array(s.courseHoles.prefix(5))
        let g = RoundGame(s)
        #expect(g.round.course?.holes == nil)
        #expect(g.holes.map(\.par) == Course.defaultPar)
    }

    @Test func banensParErSummenAvHullene() {
        let g = RoundGame(F.snapshot(F.markorPlayers()))
        #expect(g.round.course?.par == 72 && g.round.course?.slopeRating == 113)
    }

    @Test func avkortingLagOgMatcher() {
        var round = F.round()
        round.cutRule = "net_par"
        round.cutAfter = 9
        var s = F.snapshot(F.markorPlayers(), round: round)
        s.players[0].teamNo = 2
        s.matches = [RoundMatchRow(roundID: F.roundID, matchNo: 2, playerA: id(3), playerB: id(4), playerC: nil,
                                   teamA: nil, teamB: nil, result: "halved"),
                     RoundMatchRow(roundID: F.roundID, matchNo: 1, playerA: id(1), playerB: id(2), playerC: nil,
                                   teamA: nil, teamB: nil, result: nil)]
        let g = RoundGame(s)
        #expect(g.round.avkortRegel == "nettopar" && g.round.avkortetEtter == 9)
        #expect(Truncation.rule(g.round) == .netPar)
        #expect(g.round.teams == [id(1).uuidString: 2])
        #expect(g.round.matches.map(\.matchNo) == [1, 2])
        #expect(g.round.matches[1].result == .halved)
        #expect(RoundGame.cutRule("common") == .common && RoundGame.cutRule("zero") == .zero && RoundGame.cutRule(nil) == nil)
        // I en match vises ikke poengene på hullkortet.
        #expect(g.card(hole: 0, drafts: HoleDrafts(), viewer: F.viewer(F.anders)).rows[0].points == nil)
    }

    @Test func laastRundeOgDato() {
        var s = F.snapshot(F.markorPlayers(), round: F.round(status: .locked))
        s.eventDate = "2026-10-06"
        let g = RoundGame(s)
        #expect(g.round.locked && g.round.date == "2026-10-06")
        #expect(g.round.id == F.roundID.uuidString)
    }

    @Test func regelsettetStyrerPoengene() {
        var s = F.snapshot([F.P(n: 1, name: "Anders", handicap: 0)], scores: [(1, 0, 4)])
        s.rules.scoring.netParPoints = 3
        let g = RoundGame(s)
        #expect(g.total(id(1)) == 3)
    }
}

/// Feiringen (`celebrationFor`, `samletFeiring`) og «Bayen nå».
struct ForingFeiringTests {
    static let players = [F.P(n: 1, name: "Anders", handicap: 18), F.P(n: 2, name: "Bjørn", handicap: 0),
                          F.P(n: 3, name: "Cato", handicap: 7)]

    @Test func nivaaene() {
        #expect(CelebrationLevel.level(gross: 1, net: 1, par: 3) == .ace)
        #expect(CelebrationLevel.level(gross: 2, net: 2, par: 5) == .albatross)
        #expect(CelebrationLevel.level(gross: 3, net: 3, par: 5) == .eagle)
        #expect(CelebrationLevel.level(gross: 4, net: 3, par: 4) == .birdie)
        #expect(CelebrationLevel.level(gross: 4, net: 4, par: 4) == nil)
        #expect(CelebrationLevel.birdie.duration == .milliseconds(1500))
        #expect(CelebrationLevel.eagle.duration == .milliseconds(2300))
        #expect(CelebrationLevel.albatross.duration == .milliseconds(2900))
        #expect(CelebrationLevel.ace.duration == .milliseconds(5200))
    }

    @Test func nettoMotPar() {
        // Hull 2 er par 5 og indeks 1: Cato (hcp 7) slår 4 brutto = 3 netto = eagle.
        let g = RoundGame(F.snapshot(Self.players, si: F.bruttoSI, scores: [(3, 1, 4)]))
        let c = g.celebration(hole: 1, saved: [(id(3), 4)])
        #expect(c?.level == .eagle)
        #expect(c?.eyebrow == "HULL 2 · PAR 5")
        #expect(c?.points == 4)
        #expect(c?.place == 1)
        #expect(c?.nextHole == 3)
        #expect(g.celebration(hole: 1, saved: [(id(2), 5)]) == nil)
    }

    @Test("K2: eagle på par 4 og par 5, albatross, og 1 slag på par 3 er hole in one")
    func nivaaenePerPar() {
        #expect(CelebrationLevel.level(gross: 2, net: 2, par: 4) == .eagle)
        #expect(CelebrationLevel.level(gross: 3, net: 3, par: 5) == .eagle)
        #expect(CelebrationLevel.level(gross: 2, net: 2, par: 5) == .albatross)
        #expect(CelebrationLevel.level(gross: 1, net: 1, par: 4) == .ace)
        #expect(CelebrationLevel.level(gross: 1, net: 0, par: 3) == .ace)   // ikke eagle, selv med slag fått
    }

    @Test("K2: feiringen viser hullet og paret fra hullet som ble lagret")
    func feiringenFolgerHullet() {
        // Hull 3 er par 3. Bjørn (hcp 0) slår 1: hole in one på «HULL 3 · PAR 3».
        let g = RoundGame(F.snapshot(Self.players, si: F.bruttoSI, scores: [(2, 2, 1)]))
        let c = g.celebration(hole: 2, saved: [(id(2), 1)])
        #expect(c?.level == .ace)
        #expect(c?.eyebrow == "HULL 3 · PAR \(g.holes[2].par)")
        #expect(g.holes[2].par == 3)
    }

    @Test func enFeiringPerHullHoeyesteVinner() {
        let g = RoundGame(F.snapshot(Self.players, si: F.bruttoSI, scores: [(1, 2, 1), (3, 2, 2)]))
        // Hull 3: par 3, indeks 15. Anders 1 brutto (hole in one), Cato 2 = birdie.
        let c = g.celebration(hole: 2, saved: [(id(3), 2), (id(1), 1)])
        #expect(c?.level == .ace)
        #expect(c?.text == "Anders hole in one · Cato birdie")
        #expect(c?.points == nil)
    }

    @Test func bayenNaaFlestPoengFoerst() {
        let g = RoundGame(F.snapshot(Self.players, si: F.bruttoSI, scores: [(2, 0, 4), (3, 0, 4), (3, 1, 6)]))
        let rows = g.standings(viewer: Viewer(memberID: id(2), isOrganizer: false))
        #expect(rows.map(\.name) == ["Cato", "Bjørn", "Anders"])
        #expect(rows.map(\.total) == [5, 2, 0])
        #expect(rows.map(\.thru) == [2, 1, 0])
        #expect(rows[1].isMe)
    }

    /// Scratchspillere: Anders har tre bogeyer (3 p etter 3 hull), Bjørn par på første (2 p etter 1),
    /// Cato har ikke ført noe.
    static let pacePlayers = [F.P(n: 1, name: "Anders", handicap: 0), F.P(n: 2, name: "Bjørn", handicap: 0),
                              F.P(n: 3, name: "Cato", handicap: 0)]
    static let paceScores = [(1, 0, 5), (1, 1, 6), (1, 2, 4), (2, 0, 4)]

    @Test func underveisRangeresPaaPoengMotPar() {
        let g = RoundGame(F.snapshot(Self.pacePlayers, scores: Self.paceScores))
        #expect(g.ranksByPace)
        let viewer = Viewer(memberID: id(1), isOrganizer: false)
        #expect(g.standings(viewer: viewer).map(\.name) == ["Bjørn", "Anders", "Cato"])
        let rows = g.bayenNaa(viewer: viewer)
        #expect(rows.map(\.name) == ["Bjørn", "Anders", "Cato"])
        #expect(rows.map(\.total) == [2, 3, 0])
        #expect(rows.map(\.paceText) == ["på par", "3 p under par", nil])
    }

    @Test func laastRundeRangeresPaaSummen() {
        let g = RoundGame(F.snapshot(Self.pacePlayers, round: F.round(status: .locked), scores: Self.paceScores))
        #expect(!g.ranksByPace)
        let rows = g.bayenNaa(viewer: Viewer(memberID: id(1), isOrganizer: false))
        #expect(rows.map(\.name) == ["Anders", "Bjørn", "Cato"])
        #expect(rows.allSatisfy { $0.paceText == nil })
    }

    @Test func overskriftenFoelgerStedet() {
        #expect(GroupTerm.bay.standingsTitle == "Bayen nå")
        #expect(GroupTerm.flight.standingsTitle == "Flighten nå")
    }
}
