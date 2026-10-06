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
        #expect(game(tidligKveld, checkpoints: [2]).eventsAfterSaving(hole: 1, fresh: [])
                == [.leadChanged(afterHole: 2, leaders: [anders, bjorn], points: 4, outcome: .shares)])
        // Tom liste: ledelsen meldes aldri.
        #expect(game(tidligKveld, checkpoints: []).eventsAfterSaving(hole: 2, fresh: [])
                .allSatisfy { if case .leadChanged = $0 { false } else { true } })
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
