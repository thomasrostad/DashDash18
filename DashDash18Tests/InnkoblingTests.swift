import Foundation
import GolfgutuCore
import Testing
@testable import DashDash18

// Innkoblingen i fase 7: hva runden logger og når, purringen, kortene på Kveld og frosset
// spillehandicap i matchene. Poengene er stableford: med handicap 0 er poeng = par − brutto + 2.
// Par på de første hullene: 4, 5, 3 | 4, 4, 3.

private typealias F = ForingFixture
private let anders = F.id(1), bjorn = F.id(2), cato = F.id(3)

private func card(_ n: Int, _ strokes: [Int]) -> [(Int, Int, Int)] {
    strokes.enumerated().map { (n, $0.offset, $0.element) }
}

private func game(_ cards: [(Int, Int, Int)], status: RoundStatus = .active,
                  checkpoints: [Int]? = nil) -> RoundGame {
    let ps = [F.P(n: 1, name: "Anders"), F.P(n: 2, name: "Bjørn"), F.P(n: 3, name: "Cato")]
    var s = F.snapshot(ps, round: F.round(status: status), scores: cards)
    if let checkpoints { s.rules.leadCheckpoints = checkpoints }
    return RoundGame(s)
}

/// Anders hole in one på hull 3 (par 3): 2 + 2 + 4 = 8. Bjørn 6, Cato 5.
private let tidligKveld = card(1, [4, 5, 1]) + card(2, [4, 5, 3]) + card(3, [4, 6, 3])

struct InnkoblingRundeLoggTests {
    @Test func storScoreOgLedelsenPåSjekkpunktet() {
        let events = game(tidligKveld).eventsAfterSaving(hole: 2, fresh: [(anders, 1)])
        #expect(events == [
            .bigScore(member: anders, hole: 3, holeIndex: 2, name: .holeInOne, strokes: 1, par: 3),
            .leadChanged(afterHole: 3, leaders: [anders], points: 8, outcome: .leads),
        ])
    }

    @Test func mellomSjekkpunkteneBareStoreScorer() {
        // Eagle på hull 2 (par 5): 3 slag.
        let g = game(card(1, [4, 3]) + card(2, [4, 5]))
        #expect(g.eventsAfterSaving(hole: 1, fresh: [(anders, 3)])
                == [.bigScore(member: anders, hole: 2, holeIndex: 1, name: .eagle, strokes: 3, par: 5)])
        // En retting (ikke ført for første gang) gir ingen stor score.
        #expect(g.eventsAfterSaving(hole: 1, fresh: []).isEmpty)
    }

    @Test func kladdOgLåstRundeLoggerIkke() {
        #expect(game(tidligKveld, status: .draft).eventsAfterSaving(hole: 2, fresh: [(anders, 1)]).isEmpty)
        #expect(game(tidligKveld, status: .locked).eventsAfterSaving(hole: 2, fresh: [(anders, 1)]).isEmpty)
    }

    @Test func sjekkpunkteneKommerFraRegelsettet() {
        // Etter to hull: Anders 2 + 2, Bjørn 2 + 2, Cato 2 + 1. Golfgutu melder ikke hull 2.
        #expect(game(tidligKveld).eventsAfterSaving(hole: 1, fresh: []).isEmpty)
        #expect(game(tidligKveld, checkpoints: [2]).eventsAfterSaving(hole: 1, fresh: [(cato, 6)])
                == [.leadChanged(afterHole: 2, leaders: [anders, bjorn], points: 4, outcome: .shares)])
        // Tom liste: ledelsen meldes aldri.
        #expect(game(tidligKveld, checkpoints: []).eventsAfterSaving(hole: 2, fresh: [])
                .allSatisfy { if case .leadChanged = $0 { false } else { true } })
    }

    @Test func rettingMelderIkkeLedelsenPåNytt() {
        // Hull 3 lagres igjen uten at noen førte det for første gang: ingen ny linje.
        let g = game(tidligKveld)
        #expect(g.eventsAfterSaving(hole: 2, fresh: []).isEmpty)
        #expect(!g.shouldCheckLead(afterSaving: 2, fresh: []))
        #expect(g.shouldCheckLead(afterSaving: 2, fresh: [(cato, 3)]))
        // Ikke et sjekkpunkt (Golfgutu: 3, 6, 9 …), eller runden går ikke.
        #expect(!g.shouldCheckLead(afterSaving: 1, fresh: [(cato, 6)]))
        #expect(!game(tidligKveld, status: .locked).shouldCheckLead(afterSaving: 2, fresh: [(cato, 3)]))
        #expect(game(tidligKveld, status: .locked).leadEventIfActive(afterSaving: 2) == nil)
    }

    @Test func ledelsenRegnesPåRundenSlikServerenHarDen() {
        // Cato lagrer hull 3 sist. Telefonen hans har ikke fått Bjørns hull 3 ennå: ingen ledelse.
        let local = game(card(1, [4, 5, 1]) + card(2, [4, 5]) + card(3, [4, 6, 3]))
        #expect(local.shouldCheckLead(afterSaving: 2, fresh: [(cato, 3)]))
        #expect(local.leadEventIfActive(afterSaving: 2) == nil)
        // Serveren har alle tre: Anders leder (PWA: refresh() før loggLedelseHvisEndret).
        #expect(game(tidligKveld).leadEventIfActive(afterSaving: 2)
                == .leadChanged(afterHole: 3, leaders: [anders], points: 8, outcome: .leads))
    }

    @Test func hullIKøLoggesBareMedTalleneServerenHar() {
        let server = game(tidligKveld)
        // Anders' hole in one er lagret; Bjørns 2 på hull 3 ble rettet til 3 før køen gikk.
        let fresh = server.confirmed([(anders, 1), (bjorn, 2)], hole: 2)
        #expect(fresh.map(\.member) == [anders])
        #expect(server.eventsAfterSaving(hole: 2, fresh: fresh) == [
            .bigScore(member: anders, hole: 3, holeIndex: 2, name: .holeInOne, strokes: 1, par: 3),
            .leadChanged(afterHole: 3, leaders: [anders], points: 8, outcome: .leads),
        ])
        // Serveren har ikke hullet i det hele tatt (avvist): ingenting.
        #expect(server.confirmed([(anders, 4)], hole: 5).isEmpty)
        #expect(server.eventsAfterSaving(hole: 5, fresh: []).isEmpty)
    }

    @Test func sidepremieIKladdLoggerIkke() throws {
        func claimGame(_ status: RoundStatus, _ claims: [SideClaimRow]) -> RoundGame {
            var s = F.snapshot([F.P(n: 1, name: "Anders"), F.P(n: 2, name: "Bjørn")], round: F.round(status: status))
            s.sideClaims = claims
            return RoundGame(s)
        }
        let ld = try #require(claimGame(.active, []).longestDriveHole)
        let claim = SideClaimRow(id: F.id(801), roundID: F.roundID, memberID: anders, kind: .drive, meters: 231,
                                 holeIndex: ld)
        #expect(claimGame(.active, [claim]).sidePrizeEventAfterClaim(.drive, member: anders, before: claimGame(.active, []))
                == .sidePrize(kind: .drive, member: anders, hole: 7, meters: 231, passed: nil, passedMeters: nil))
        #expect(claimGame(.draft, [claim]).sidePrizeEventAfterClaim(.drive, member: anders,
                                                                    before: claimGame(.draft, [])) == nil)
    }

    @Test func rundeStartetOgLåst() {
        #expect(RoundGame(F.snapshot(F.markorPlayers(), round: F.round(status: .draft))).startedEventIfActive == nil)
        guard case .roundStarted(roundNo: 1, courseName: "Testbanen", holeCount: 18, bays: 2, ldHole: 7, kpHole: _)?
            = RoundGame(F.snapshot(F.markorPlayers())).startedEventIfActive else {
            Issue.record("Ny runde mangler"); return
        }
        #expect(RoundActivity.locked(F.round(status: .locked), courseName: "Testbanen")
                == .roundLocked(roundNo: 1, courseName: "Testbanen"))
        #expect(RoundActivity.locked(F.round(status: .active), courseName: "Testbanen") == nil)
        #expect(!RoundActivity.isLoggable(.draft))
        #expect(RoundActivity.isLoggable(.active) && RoundActivity.isLoggable(.locked))
    }
}

// MARK: - Én gang per hendelse

struct InnkoblingEnGangTests {
    let round = F.roundID
    let eagle = ActivityEvent.bigScore(member: anders, hole: 2, holeIndex: 1, name: .eagle, strokes: 3, par: 5)
    let started = ActivityEvent.roundStarted(roundNo: 1, courseName: "Testbanen", holeCount: 18, bays: 2,
                                             ldHole: 7, kpHole: nil)

    @Test func nøklerSomDeUnikeIndeksene() {
        let r = round.uuidString
        #expect(ActivityOnce.key(eagle, roundID: round) == "big_score:\(r):\(anders.uuidString):i1")
        #expect(ActivityOnce.key(.leadChanged(afterHole: 9, leaders: [bjorn], points: 19, outcome: .tookLead),
                                 roundID: round) == "lead_changed:\(r):9")
        #expect(ActivityOnce.key(started, roundID: round) == "round_started:\(r)")
        // Kan stå flere ganger: låst, sidepremie, retting. Uten runde: ingen grense.
        #expect(ActivityOnce.key(.roundLocked(roundNo: 1, courseName: nil), roundID: round) == nil)
        #expect(ActivityOnce.key(.sidePrize(kind: .drive, member: anders, hole: 7, meters: 231, passed: nil,
                                            passedMeters: nil), roundID: round) == nil)
        #expect(ActivityOnce.key(eagle, roundID: nil) == nil)
    }

    @Test func sammeHendelseSlippesBareGjennomÉnGang() {
        var log = ActivityOnceLog()
        let lead = ActivityEvent.leadChanged(afterHole: 3, leaders: [anders], points: 8, outcome: .leads)
        #expect(log.admit([eagle, lead], roundID: round) == [eagle, lead])
        // Hullet kommer tilbake fra køen, eller lagres igjen: ingenting nytt.
        #expect(log.admit([eagle], roundID: round).isEmpty)
        // Ledelsen etter hull 3 er meldt, selv om utfallet nå regnes annerledes.
        #expect(log.admit([.leadChanged(afterHole: 3, leaders: [bjorn], points: 8, outcome: .shares)],
                          roundID: round).isEmpty)
        // Neste sjekkpunkt, et annet hull og en annen runde går.
        let next = ActivityEvent.leadChanged(afterHole: 6, leaders: [anders], points: 14, outcome: .leads)
        let otherHole = ActivityEvent.bigScore(member: anders, hole: 3, holeIndex: 2, name: .holeInOne, strokes: 1, par: 3)
        #expect(log.admit([next, otherHole], roundID: round) == [next, otherHole])
        #expect(log.admit([eagle], roundID: F.id(999)) == [eagle])
        // To like i samme kall: bare den første.
        var fresh = ActivityOnceLog()
        #expect(fresh.admit([started, started], roundID: round) == [started])
        // Det som kan stå flere ganger, slippes alltid gjennom.
        let locked = ActivityEvent.roundLocked(roundNo: 1, courseName: nil)
        #expect(fresh.admit([locked, locked], roundID: round) == [locked, locked])
    }
}

// MARK: - Purring

private func member(_ n: Int, _ name: String, status: MemberStatus = .active) -> ClubMemberRow {
    ClubMemberRow(id: F.id(n), clubID: F.club, userID: nil, displayName: name, handicapIndex: nil, seedGroup: nil,
                  isOrganizer: false, isTreasurer: false, status: status, avatarPath: nil)
}

private func signup(_ n: Int, _ status: SignupStatus) -> SignupRow {
    SignupRow(eventID: F.eventID, memberID: F.id(n), clubID: F.club, status: status, comment: nil)
}

struct InnkoblingPurringTests {
    let members = [member(1, "Anders"), member(2, "Bjørn"), member(3, "Cato"), member(4, "Dag"),
                   member(5, "Erik", status: .archived)]

    @Test func purrerBareDeAktiveSomIkkeHarSvart() {
        let summary = SignupSummary(members: members, signups: [signup(1, .yes), signup(3, .no)])
        let targets = Nudge.targets(summary)
        #expect(targets.map(\.memberID) == [bjorn, F.id(4)])
        #expect(Nudge.buttonTitle(count: targets.count) == "Purr de 2 som ikke har svart …")
        #expect(Nudge.confirmMessage(names: targets.map(\.name)) == "Purre på de 2 som ikke har svart? Bjørn, Dag.")
        #expect(Nudge.doneText(count: targets.count) == "Purret på 2.")
        #expect(Nudge.isOffered(isOrganizer: true, summary: summary))
        #expect(!Nudge.isOffered(isOrganizer: false, summary: summary))
    }

    @Test func denEne() {
        let summary = SignupSummary(members: members, signups: [signup(1, .yes), signup(2, .maybe), signup(3, .no)])
        #expect(Nudge.buttonTitle(count: Nudge.targets(summary).count) == "Purr den ene som ikke har svart …")
        #expect(Nudge.confirmMessage(names: ["Dag"]) == "Purre på den ene som ikke har svart? Dag.")
    }

    @Test func alleHarSvartGirIngenKnapp() {
        let summary = SignupSummary(members: members, signups: (1...4).map { signup($0, .yes) })
        #expect(Nudge.targets(summary).isEmpty)
        #expect(!Nudge.isOffered(isOrganizer: true, summary: summary))
    }
}

// MARK: - Kortene på Kveld

struct InnkoblingKortTests {
    private func line(_ author: String, _ text: String) -> TradSummary.Line {
        TradSummary.Line(id: UUID(), memberID: UUID(), author: author, preview: text, createdAt: .now)
    }

    @Test func trådkortet() {
        let empty = TradSummary(count: 0, unread: 0, recent: [])
        #expect(KveldThreadStatus.subtitle(empty) == "Ingen meldinger ennå")
        #expect(KveldThreadStatus.lastLine(empty) == nil)
        #expect(KveldThreadStatus.short(empty) == "0")

        let one = TradSummary(count: 1, unread: 0, recent: [line("Anders", "Ses kl. 17")])
        #expect(KveldThreadStatus.subtitle(one) == "1 melding")
        #expect(KveldThreadStatus.lastLine(one) == "Anders: Ses kl. 17")

        let many = TradSummary(count: 5, unread: 2, recent: [line("Bjørn", "Hei"), line("Cato", TradSummary.imageOnlyText)])
        #expect(KveldThreadStatus.subtitle(many) == "5 meldinger · 2 uleste")
        #expect(KveldThreadStatus.lastLine(many) == "Cato: 📷 Bilde")
        #expect(KveldThreadStatus.short(many) == "2 uleste")
        #expect(KveldThreadStatus.unreadText(1) == "1 ulest")
    }

    @Test func tippekortet() {
        let frist = "torsdag 8. oktober kl. 17:00"
        func text(_ phase: TipsBoard.Phase, mine: Bool = false, submitted: Int = 0, winners: String = "") -> String {
            KveldTipsStatus.text(phase: phase, deadlineText: frist, hasMyCoupon: mine, submitted: submitted,
                                 winners: winners, best: 4, possible: 5)
        }
        #expect(text(.open) == "Åpen til torsdag 8. oktober kl. 17:00")
        #expect(text(.open, mine: true) == "Levert · åpen til torsdag 8. oktober kl. 17:00")
        #expect(text(.locked, submitted: 6) == "Låst · 6 levert")
        #expect(text(.locked) == "Låst · ingen leverte")
        #expect(text(.finished, winners: "Anders og Cato") == "Resultat: Anders og Cato med 4 av 5 riktige")
        #expect(text(.finished) == "Resultat: ingen leverte")
        #expect([TipsBoard.Phase.open, .locked, .finished].map(KveldTipsStatus.short) == ["Åpen", "Låst", "Resultat"])
    }
}

// MARK: - Frosset spillehandicap

/// Anders og Bjørn har indeks 0, men Anders startet med lagret spillehandicap 18: ett slag på
/// hvert hull. Begge spiller bogey på de tre første hullene, så Anders vinner alle tre netto.
struct InnkoblingFrossetHandicapTests {
    static func game(anders playing: Int?) -> RoundGame {
        let bogeys = Array(F.par.prefix(3)).map { $0 + 1 }
        var s = F.snapshot([F.P(n: 1, name: "Anders", handicap: 0, playing: playing),
                            F.P(n: 2, name: "Bjørn", handicap: 0)],
                           round: F.round(format: "match"), scores: card(1, bogeys) + card(2, bogeys))
        s.matches = [RoundMatchRow(roundID: F.roundID, matchNo: 1, playerA: anders, playerB: bjorn, playerC: nil,
                                   teamA: nil, teamB: nil, result: nil)]
        return RoundGame(s)
    }

    @Test func rundenBærerDetLagredeSpillehandicapet() {
        let g = Self.game(anders: 18)
        #expect(g.round.playingHandicaps == [anders.uuidString: 18])
        #expect(g.handicap(anders) == 18)
        #expect(Self.game(anders: nil).round.playingHandicaps.isEmpty)
    }

    @Test func matchresultatetFølgerLagretSpillehandicap() {
        #expect(Self.game(anders: 18).holeMatchStanding(anders).map(MatchPlay.shortText) == "3 opp")
        #expect(Self.game(anders: 18).holeMatchStanding(bjorn).map(MatchPlay.shortText) == "3 ned")
        // Uten lagret tall: indeks 0 mot 0, alle hullene delt.
        #expect(Self.game(anders: nil).holeMatchStanding(anders).map(MatchPlay.shortText) == "Delt")
    }
}
