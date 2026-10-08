import Foundation
import GolfgutuCore
import Testing
@testable import DashDash18

// Når noe skal logges: store scorer (loggStorScore), ledelsen ved sjekkpunktene
// (loggLedelseHvisEndret, README «Varsler underveis i en runde»), ny leder på longest drive og
// nærmest pinnen (handleMeldLongestDrive, handleMeldKp) og påmeldingslinja (svarLinje).
// Poengene er stableford fra GolfgutuCore: med handicap 0 er poeng = par − brutto + 2 (minst 0).

private typealias F = ForingFixture
private let anders = F.id(1), bjorn = F.id(2), cato = F.id(3)

/// Brutto per hull fra rundens første hull.
private func card(_ n: Int, _ strokes: [Int]) -> [(Int, Int, Int)] {
    strokes.enumerated().map { (n, $0.offset, $0.element) }
}

private func game(_ cards: [(Int, Int, Int)], holeCount: Int = 18, players: [F.P]? = nil,
                  matches: [RoundMatchRow] = []) -> RoundGame {
    let ps = players ?? [F.P(n: 1, name: "Anders"), F.P(n: 2, name: "Bjørn"), F.P(n: 3, name: "Cato")]
    var s = F.snapshot(ps, round: F.round(holeCount: holeCount), scores: cards)
    s.matches = matches
    return RoundGame(s)
}

struct AktivitetStorScoreTests {
    @Test(arguments: [
        (1, 3, BigScoreName.holeInOne), (1, 4, .holeInOne), (1, 5, .holeInOne),
        (2, 5, .albatross), (3, 6, .albatross), (2, 6, .albatross),
        (2, 4, .eagle), (3, 5, .eagle), (4, 6, .eagle),
    ])
    func terskelenErBrutto(gross: Int, par: Int, expected: BigScoreName) {
        #expect(BigScore.detect(gross: gross, par: par) == expected)
    }

    @Test func birdieOgParErIkkeStoreScorer() {
        #expect(BigScore.detect(gross: 3, par: 4) == nil)
        #expect(BigScore.detect(gross: 4, par: 4) == nil)
        #expect(BigScore.detect(gross: 2, par: 3) == nil)
    }

    @Test func hendelserForHulletSomBleLagret() {
        // Hull 2 er par 5.
        let g = game([])
        let events = g.bigScoreEvents(hole: 1, saved: [(anders, 3), (bjorn, 5), (cato, 2)])
        #expect(events == [
            .bigScore(member: anders, hole: 2, holeIndex: 1, name: .eagle, strokes: 3, par: 5),
            .bigScore(member: cato, hole: 2, holeIndex: 1, name: .albatross, strokes: 2, par: 5),
        ])
        #expect(g.bigScoreEvents(hole: 99, saved: [(anders, 1)]).isEmpty)
    }

    @Test func sisteNiBrukerHullnummeretPåKortet() {
        var s = F.snapshot([F.P(n: 1, name: "Anders")], round: F.round(holeCount: 9, firstHole: 10))
        s.scores = []
        let g = RoundGame(s)
        let par = g.holes[0].par
        let events = g.bigScoreEvents(hole: 0, saved: [(anders, 1)])
        #expect(events == [.bigScore(member: anders, hole: 10, holeIndex: 0, name: .holeInOne, strokes: 1, par: par)])
    }
}

struct AktivitetLederTests {
    // Par på de første hullene: 4, 5, 3 | 4, 4, 3 | 5, 4, 4.

    @Test func førsteSjekkpunktMelderLederen() {
        let g = game(card(1, [4, 5, 3]) + card(2, [3, 5, 3]) + card(3, [4, 6, 3]))  // 6, 7, 5
        #expect(g.leadEvent(afterSaving: 2) == .leadChanged(afterHole: 3, leaders: [bjorn], points: 7, outcome: .leads))
    }

    @Test func venterTilAlleHarFørtHullet() {
        // Cato har ikke ført hull 3: den første som kom dit, leder bare trivielt.
        let g = game(card(1, [4, 5, 3]) + card(2, [3, 5, 3]) + card(3, [4, 6]))
        #expect(g.leadEvent(afterSaving: 2) == nil)
    }

    @Test func bareVedSjekkpunktene() {
        let g = game(card(1, [4, 5, 3, 4]) + card(2, [3, 5, 3, 4]))
        #expect(g.leadEvent(afterSaving: 1) == nil)
        #expect(g.leadEvent(afterSaving: 3) == nil)
    }

    @Test func minstToSpillere() {
        let g = game(card(1, [4, 5, 3]))
        #expect(g.leadEvent(afterSaving: 2) == nil)
    }

    @Test func nyLederEtterSeksHull() {
        // Etter 3: Bjørn 7, Anders 6, Cato 6. Etter 6: Anders 6+3+3+2 = 14, Bjørn 7+2+2+2 = 13.
        let g = game(card(1, [4, 5, 3, 3, 3, 3]) + card(2, [3, 5, 3, 4, 4, 3]) + card(3, [4, 5, 3, 4, 4, 3]))
        #expect(g.leadEvent(afterSaving: 5) == .leadChanged(afterHole: 6, leaders: [anders], points: 14, outcome: .tookLead))
    }

    @Test func sammeLederMeldesIkkeUnderveis() {
        let g = game(card(1, [4, 5, 3, 4, 4, 3]) + card(2, [3, 5, 3, 4, 4, 3]))
        #expect(g.leadEvent(afterSaving: 5) == nil)
    }

    @Test func deltLedelseMeldesSomDeling() {
        // Etter 6: Anders 6+3+2+2 = 13, Bjørn 7+2+2+2 = 13. Navnesortert.
        let g = game(card(2, [3, 5, 3, 4, 4, 3]) + card(1, [4, 5, 3, 3, 4, 3]) + card(3, [4, 5, 3, 4, 4, 3]))
        #expect(g.leadEvent(afterSaving: 5)
                == .leadChanged(afterHole: 6, leaders: [anders, bjorn], points: 13, outcome: .shares))
    }

    @Test func måletOverDeFørsteHulleneIkkeOverHvorLangtHverHarKommet() {
        // Bjørn har spilt ett hull til og leder på sum, men etter 3 hull leder Anders.
        let g = game(card(1, [3, 5, 3]) + card(2, [4, 5, 3, 2]))
        #expect(g.leadEvent(afterSaving: 2) == .leadChanged(afterHole: 3, leaders: [anders], points: 7, outcome: .leads))
    }

    @Test func handicapTellerMed() {
        // Cato har spillehandicap 18: ett slag på hvert hull. 4, 6, 4 → netto 3, 5, 3 → 3 + 2 + 2 = 7.
        let players = [F.P(n: 1, name: "Anders"), F.P(n: 2, name: "Bjørn"), F.P(n: 3, name: "Cato", playing: 18)]
        let g = game(card(1, [4, 5, 3]) + card(2, [4, 6, 3]) + card(3, [4, 6, 4]), players: players)
        #expect(g.leadEvent(afterSaving: 2) == .leadChanged(afterHole: 3, leaders: [cato], points: 7, outcome: .leads))
    }

    @Test func matchrundeMelderIkkePoengleder() {
        // matchrunde-test.js: «ingen leder med N poeng i en matchrunde».
        let match = RoundMatchRow(roundID: F.roundID, matchNo: 1, playerA: anders, playerB: bjorn, playerC: nil,
                                  teamA: nil, teamB: nil, result: nil)
        let g = game(card(1, [4, 5, 3]) + card(2, [3, 5, 3]), matches: [match])
        #expect(g.leadEvent(afterSaving: 2) == nil)
    }

    // Ni hull: siste hull er 9, og det meldes alltid (slik endte runden).

    @Test func niHullSammeLederVantRunden() {
        // Etter 6: Anders 13, Bjørn 12. Etter 9: Anders 19, Bjørn 18.
        let g = game(card(1, [3, 5, 3, 4, 4, 3, 5, 4, 4]) + card(2, [4, 5, 3, 4, 4, 3, 5, 4, 4]), holeCount: 9)
        #expect(g.leadEvent(afterSaving: 8) == .leadChanged(afterHole: 9, leaders: [anders], points: 19, outcome: .won))
    }

    @Test func niHullNyLederSnappetRunden() {
        // Etter 6: Anders 13, Bjørn 12. Etter 9: Anders 16, Bjørn 18.
        let g = game(card(1, [3, 5, 3, 4, 4, 3, 6, 5, 5]) + card(2, [4, 5, 3, 4, 4, 3, 5, 4, 4]), holeCount: 9)
        #expect(g.leadEvent(afterSaving: 8) == .leadChanged(afterHole: 9, leaders: [bjorn], points: 18, outcome: .snatched))
    }

    @Test func niHullLiktEndteLikt() {
        // Etter 9: Anders 13 + 2 + 2 + 1 = 18, Bjørn 18.
        let g = game(card(1, [3, 5, 3, 4, 4, 3, 5, 4, 5]) + card(2, [4, 5, 3, 4, 4, 3, 5, 4, 4]), holeCount: 9)
        #expect(g.leadEvent(afterSaving: 8)
                == .leadChanged(afterHole: 9, leaders: [anders, bjorn], points: 18, outcome: .tiedFinish))
    }

    @Test func attenHullSisteHullMeldesSelvMedSammeLeder() {
        let anders18 = [3] + Array(F.par.dropFirst())  // én birdie, resten par: 37
        let g = game(card(1, anders18) + card(2, F.par))
        #expect(g.leadEvent(afterSaving: 17) == .leadChanged(afterHole: 18, leaders: [anders], points: 37, outcome: .won))
        #expect(g.leadEvent(afterSaving: 14) == nil)  // hull 15: samme som etter 12
    }

    // Kjernen, uten runde.

    @Test func egneSjekkpunkterFraRegelsettet() {
        let entries = [LeadTracker.Entry(member: anders, points: [0: 2, 1: 3]),
                       LeadTracker.Entry(member: bjorn, points: [0: 2, 1: 2])]
        #expect(LeadTracker.change(entries, afterHoles: 2, holeCount: 4, checkpoints: [2, 4])
                == LeadTracker.Change(afterHole: 2, leaders: .init(ids: [anders], points: 5), outcome: .leads))
        #expect(LeadTracker.change(entries, afterHoles: 2, holeCount: 4) == nil)  // 2 er ikke et Golfgutu-sjekkpunkt
    }

    @Test func spillerUtenScoreErIkkeMed() {
        let entries = [LeadTracker.Entry(member: anders, points: [0: 2, 1: 3, 2: 2]),
                       LeadTracker.Entry(member: bjorn, points: [0: 2, 1: 2, 2: 2]),
                       LeadTracker.Entry(member: cato, points: [:])]
        #expect(LeadTracker.change(entries, afterHoles: 3, holeCount: 18)?.leaders == .init(ids: [anders], points: 7))
    }
}

struct AktivitetSidepremieTests {
    private func claim(_ n: Int, _ member: UUID, _ kind: SideClaimKind, _ meters: Double, hole: Int) -> SideClaimRow {
        SideClaimRow(id: F.id(800 + n), roundID: F.roundID, memberID: member, kind: kind, meters: meters, holeIndex: hole)
    }

    private func game(_ claims: [SideClaimRow]) -> RoundGame {
        var s = F.snapshot([F.P(n: 1, name: "Anders"), F.P(n: 2, name: "Bjørn"), F.P(n: 3, name: "Cato")])
        s.sideClaims = claims
        return RoundGame(s)
    }

    @Test func nyLederPåLongestDriveForbiDenForrige() throws {
        let ld = try #require(game([]).longestDriveHole)
        #expect(ld == 6)  // første par 5 fra og med hull 4: hull 7
        let before = game([claim(1, anders, .drive, 231, hole: ld)])
        let after = game([claim(1, anders, .drive, 231, hole: ld), claim(2, bjorn, .drive, 245, hole: ld)])
        #expect(after.sidePrizeLeadEvent(.drive, member: bjorn, before: before)
                == .sidePrize(kind: .drive, member: bjorn, hole: 7, meters: 245, passed: anders, passedMeters: 231))
    }

    @Test func førsteInnmeldingLederUtenForbi() throws {
        let ld = try #require(game([]).longestDriveHole)
        let after = game([claim(1, anders, .drive, 231, hole: ld)])
        #expect(after.sidePrizeLeadEvent(.drive, member: anders, before: game([]))
                == .sidePrize(kind: .drive, member: anders, hole: 7, meters: 231, passed: nil, passedMeters: nil))
    }

    @Test func ingenMeldingNårLedelsenIkkeSkifter() throws {
        let ld = try #require(game([]).longestDriveHole)
        let before = game([claim(1, anders, .drive, 231, hole: ld)])
        // Bjørn kom ikke forbi.
        let shorter = game([claim(1, anders, .drive, 231, hole: ld), claim(2, bjorn, .drive, 220, hole: ld)])
        #expect(shorter.sidePrizeLeadEvent(.drive, member: bjorn, before: before) == nil)
        // Anders forbedret sin egen: han ledet fra før.
        let better = game([claim(1, anders, .drive, 250, hole: ld)])
        #expect(better.sidePrizeLeadEvent(.drive, member: anders, before: before) == nil)
    }

    @Test func nærmestPinnenErKortestFørst() throws {
        let kp = try #require(game([]).closestToPinHole)
        let before = game([claim(1, anders, .kp, 3.4, hole: kp)])
        let after = game([claim(1, anders, .kp, 3.4, hole: kp), claim(2, cato, .kp, 1.2, hole: kp)])
        #expect(after.sidePrizeLeadEvent(.kp, member: cato, before: before)
                == .sidePrize(kind: .kp, member: cato, hole: after.holeNumber(kp), meters: 1.2, passed: anders,
                              passedMeters: 3.4))
    }
}

struct AktivitetRundeOgPåmeldingTests {
    @Test func nyRundeFraRunden() {
        let g = RoundGame(F.snapshot(F.markorPlayers()))
        guard case let .roundStarted(no, course, holes, bays, ld, _) = g.startedEvent else {
            Issue.record("feil type"); return
        }
        #expect(no == 1 && course == "Testbanen" && holes == 18 && bays == 2 && ld == 7)
        // Uten båser: ingen telling.
        guard case let .roundStarted(_, _, _, noBays, _, _) = RoundGame(F.snapshot(F.markorPlayers(bays: false))).startedEvent
        else { Issue.record("feil type"); return }
        #expect(noBays == nil)
    }

    @Test func påmeldingslinjaBareVedNyheter() {
        let d = "2026-10-08"
        #expect(SignupNews.event(member: anders, from: nil, to: .yes, eventDate: d) == .signup(member: anders, status: .yes, eventDate: d))
        #expect(SignupNews.event(member: anders, from: .maybe, to: .yes, eventDate: d) == .signup(member: anders, status: .yes, eventDate: d))
        #expect(SignupNews.event(member: anders, from: .yes, to: .no, eventDate: d) == .signup(member: anders, status: .no, eventDate: d))
        #expect(SignupNews.event(member: anders, from: .yes, to: .maybe, eventDate: d) == .signup(member: anders, status: .maybe, eventDate: d))
        // «Kommer ikke» uten å ha sagt ja, og samme svar igjen, er ingen nyhet.
        #expect(SignupNews.event(member: anders, from: nil, to: .no, eventDate: d) == nil)
        #expect(SignupNews.event(member: anders, from: nil, to: .maybe, eventDate: d) == nil)
        #expect(SignupNews.event(member: anders, from: .no, to: .maybe, eventDate: d) == nil)
        #expect(SignupNews.event(member: anders, from: .yes, to: .yes, eventDate: d) == nil)
    }
}
