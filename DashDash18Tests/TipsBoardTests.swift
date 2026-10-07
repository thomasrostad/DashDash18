import Foundation
import GolfgutuCore
import Testing
@testable import DashDash18

/// Tippekupongen bygd av rader, slik de kommer fra databasen. Tall fra tippekupong-test.js
/// (regnet av db-nytt.js, se også GolfgutuCore/Tests/Fixtures/tips.json).
private enum T {
    static func id(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))! }

    static let club = id(990)
    static let courseID = id(991)
    static let eventID = id(993)
    static let anders = 1, bjorn = 2, cato = 3, dag = 4

    /// PAR fra tippekupong-test.js.
    static let par = [4, 5, 3, 4, 4, 3, 5, 4, 4, 4, 3, 5, 4, 4, 3, 4, 5, 4]

    static func member(_ n: Int, _ name: String, hcp: Double? = 0) -> ClubMemberRow {
        ClubMemberRow(id: id(n), clubID: club, userID: nil, displayName: name, handicapIndex: hcp, seedGroup: nil,
                      isOrganizer: false, isTreasurer: false, status: .active, avatarPath: nil)
    }

    static let four = [member(anders, "Anders"), member(bjorn, "Bjørn"), member(cato, "Cato"), member(dag, "Dag")]

    static let event = TipsEventRow(id: eventID, clubID: club, seasonID: nil, eventDate: "2026-10-08",
                                    startTime: "17:00:00", stakePoints: 50, line: 2.5)

    static let course = CourseRow(id: courseID, clubID: club, name: "Testbanen", externalName: nil, courseRating: 72,
                                  slopeRating: 113, inUse: true, confirmedBy: nil, confirmedAt: nil)
    static let courseHoles = par.enumerated().map { i, p in
        CourseHoleRecord(courseID: courseID, holeNumber: i + 1, par: p, strokeIndex: i + 1, lengthM: nil)
    }

    /// En 9-hullsrunde på kvelden, ført netto fra simulatoren. `strokes[spiller]` er slagene.
    static func round(_ n: Int, firstHole: Int, status: RoundStatus = .active, holeCount: Int = 9,
                      external: Bool = true, format: String = "fourball",
                      strokes: [Int: [Int]], playing: [Int: Int] = [:]) -> RoundSnapshot {
        let rid = id(100 + n)
        let row = RoundRow(id: rid, clubID: club, eventID: eventID, courseID: courseID, roundNo: n, name: nil,
                           status: status, holeCount: holeCount, firstHole: firstHole, teeTime: nil, format: format,
                           handicapAllowance: 1, externalHandicap: external, weight: 1,
                           ldEnabled: false, ldHoleIndex: nil, kpEnabled: false, kpHoleIndex: nil,
                           cutRule: nil, cutAfter: nil, parConfirmedBy: nil, parConfirmedAt: nil,
                           startedAt: nil, lockedAt: nil)
        var s = RoundSnapshot(round: row)
        s.eventDate = event.eventDate
        s.course = course
        s.courseHoles = courseHoles
        s.players = strokes.keys.sorted().map { p in
            RoundPlayerRow(roundID: rid, memberID: id(p), clubID: club, handicapIndex: p == 5 ? 18 : 0, seedGroup: nil,
                           playingHandicap: playing[p], bayNo: 1, isMarker: false, teamNo: nil)
        }
        s.scores = strokes.flatMap { p, holes in
            holes.enumerated().map { h, g in
                HoleScoreRow(roundID: rid, memberID: id(p), holeIndex: h, strokes: g, recordedAt: nil, updatedBy: nil, updatedAt: nil)
            }
        }
        return s
    }

    /// Kvelden i tippekupong-test.js: første ni og siste ni.
    static func evening(status: RoundStatus = .active) -> [RoundSnapshot] {
        [
            round(1, firstHole: 1, status: status, strokes: [
                anders: [4, 5, 3, 4, 4, 3, 5, 4, 4], bjorn: [3, 5, 3, 4, 5, 3, 5, 4, 4],
                cato: [5, 6, 4, 5, 5, 4, 6, 5, 5], dag: [4, 5, 3, 4, 4, 3, 5, 4, 3],
            ]),
            round(2, firstHole: 10, status: status, strokes: [
                anders: [4, 3, 5, 4, 4, 3, 4, 5, 4], bjorn: [5, 4, 6, 5, 5, 4, 5, 6, 5],
                cato: [4, 3, 5, 4, 4, 3, 4, 5, 4], dag: [5, 3, 5, 4, 4, 3, 4, 5, 4],
            ]),
        ]
    }

    static func coupon(_ p: Int, _ w: Int, _ n: Int, _ par: Int, _ birdie: Bool, _ over: Bool) -> TipsRow {
        TipsRow(eventID: eventID, memberID: id(p), clubID: club, winner: id(w), frontNine: id(n), mostPars: id(par),
                birdie: birdie, overLine: over, updatedAt: nil)
    }

    /// Kupongene i tippekupong-test.js: Anders 4, Bjørn 2, Cato 4, Dag 1.
    static let coupons = [
        coupon(anders, anders, anders, anders, true, false),
        coupon(bjorn, bjorn, dag, bjorn, true, true),
        coupon(cato, dag, dag, anders, true, true),
        coupon(dag, cato, cato, cato, false, false),
    ]

    static func signup(_ p: Int, _ status: SignupStatus) -> SignupRow {
        SignupRow(eventID: eventID, memberID: id(p), clubID: club, status: status, comment: nil)
    }

    static func at(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }
}

struct TipsBoardTests {
    @Test func laastKveldAllesKupongerUtenMerker() {
        var input = TipsInput(event: T.event, members: T.four, rounds: T.evening(), coupons: T.coupons)
        input.serverOpen = false
        let b = TipsBoard(input, me: T.id(T.bjorn), isOrganizer: false)
        #expect(b.phase == .locked)
        #expect(b.statusText == "Låst · kvelden er i gang")
        #expect(b.result.winners.isEmpty, "ingen kåret før kvelden er ferdig")
        let winner = b.groups(.winner)
        #expect(winner.map(\.memberIDs.count) == [1, 1, 1, 1])
        #expect(winner.allSatisfy { $0.correct == nil })
        let birdie = b.groups(.birdie)
        #expect(birdie.map(\.text) == ["Ja", "Nei"] && birdie.first?.memberIDs.count == 3)
    }

    @Test func ferdigKveldFasitOgTippekongen() {
        var input = TipsInput(event: T.event, members: T.four, rounds: T.evening(status: .locked), coupons: T.coupons)
        input.serverOpen = false
        let b = TipsBoard(input, me: T.id(T.anders), isOrganizer: false)
        #expect(b.phase == .finished)
        let f = b.answerKey
        #expect(f.winner == [T.id(T.anders), T.id(T.dag)].map(\.uuidString) && f.winnerPoints == 36)
        #expect(f.frontNine == [T.id(T.dag).uuidString] && f.frontNineNet == 35)
        #expect(f.mostPars == [T.id(T.anders).uuidString] && f.mostParsHoles == 18)
        #expect(f.birdie == true && f.average == 2.25 && f.over == false)
        #expect(b.answerKeyText(.winner) == "Anders og Dag · 36 poeng")
        #expect(b.answerKeyText(.frontNine) == "Dag · 35 netto")
        #expect(b.answerKeyText(.mostPars) == "Anders · 18 hull")
        #expect(b.answerKeyText(.birdie) == "Ja")
        #expect(b.answerKeyText(.over) == "Under · snittet ble +2,25 mot +2,5")

        #expect(b.result.rows.map(\.points) == [4, 4, 2, 1])
        #expect(b.result.rows.map(\.playerID) == [T.anders, T.cato, T.bjorn, T.dag].map { T.id($0).uuidString })
        #expect(b.result.winners == [T.anders, T.cato].map { T.id($0).uuidString })
        #expect(b.place(of: b.result.rows[1]) == 1 && b.place(of: b.result.rows[2]) == 3)
        #expect(b.pot.total == 200 && b.pot.entries == 4)
        #expect(b.kingText == "4 av 5 riktige · deler potten på 200 poeng")
        #expect(b.nameList(b.result.winners) == "Anders og Cato")
        #expect(b.groups(.winner).first { $0.text == "Anders" }?.correct == true)
        #expect(b.groups(.winner).first { $0.text == "Bjørn" }?.correct == false)
    }

    /// Kladden teller ikke i fasiten, men kvelden er ikke ferdig så lenge den finnes.
    @Test func kladdTellerIkke() {
        var rounds = T.evening(status: .locked)
        rounds.append(T.round(3, firstHole: 10, status: .draft, strokes: [T.anders: [1, 1, 1, 1, 1, 1, 1, 1, 1]]))
        var input = TipsInput(event: T.event, members: T.four, rounds: rounds, coupons: T.coupons)
        input.serverOpen = false
        let b = TipsBoard(input, me: T.id(T.anders), isOrganizer: true)
        #expect(b.answerKey.winnerPoints == 36)
        #expect(b.phase == .locked)
    }

    @Test func aapenKupong() {
        var input = TipsInput(event: T.event, members: T.four)
        input.signups = [T.signup(T.cato, .yes), T.signup(T.dag, .yes), T.signup(T.bjorn, .no)]
        input.coupons = [T.coupon(T.anders, T.anders, T.dag, T.anders, true, false)]
        input.submitted = [TipsSubmittedRow(memberID: T.id(T.cato), submittedAt: nil)]
        let b = TipsBoard(input, me: T.id(T.anders), isOrganizer: true, now: T.at("2026-10-08T14:59:00Z"))
        #expect(b.phase == .open)
        #expect(b.deadline == T.at("2026-10-08T15:00:00Z"))
        #expect(b.deadlineText == "torsdag 8. oktober kl. 17:00")
        #expect(b.statusText == "Låses torsdag 8. oktober kl. 17:00, eller når første slag føres")
        #expect(b.firstCandidates.map(\.name) == ["Cato", "Dag"])
        #expect(b.otherCandidates.map(\.name) == ["Anders", "Bjørn"], "ikke svart før kommer ikke")
        #expect(b.submitted == [T.id(T.anders), T.id(T.cato)])
        #expect(b.missing == [T.id(T.dag)])
        #expect(b.potText == "2 levert · 100 poeng i potten")
        #expect(b.stakeText == "Innsats 50 poeng")
        #expect(b.myCoupon?.frontNine == T.id(T.dag).uuidString)
        #expect(!b.canEditSettings, "står fast når noen har levert")
        #expect(b.title(.over) == "Over eller under +2,5?")

        let closed = TipsBoard(input, me: T.id(T.anders), isOrganizer: true, now: T.at("2026-10-08T15:00:00Z"))
        #expect(closed.phase == .locked, "låst i det fristen kommer")
    }

    /// Første slag låser, også før fristen. Databasens svar går foran klokka på telefonen.
    @Test func foersteSlagOgServerensLaas() {
        var input = TipsInput(event: T.event, members: T.four)
        input.rounds = [T.round(1, firstHole: 1, strokes: [T.anders: [4]])]
        #expect(TipsBoard(input, me: T.id(T.anders), isOrganizer: false, now: T.at("2026-10-08T12:00:00Z")).phase == .locked)
        input.rounds = []
        input.serverOpen = false
        #expect(TipsBoard(input, me: T.id(T.anders), isOrganizer: false, now: T.at("2026-10-08T12:00:00Z")).phase == .locked)
        input.serverOpen = true
        input.serverDeadline = T.at("2026-10-08T16:30:00Z")
        let b = TipsBoard(input, me: T.id(T.anders), isOrganizer: false, now: T.at("2026-10-08T16:00:00Z"))
        #expect(b.phase == .open && b.deadlineText == "torsdag 8. oktober kl. 18:30")
    }

    /// Skjermen står åpen over fristen: den henter på nytt like etter, så kupongen låses der også.
    @Test func hentesPaaNyttVedFristen() throws {
        let input = TipsInput(event: T.event, members: T.four)
        let b = TipsBoard(input, me: T.id(T.anders), isOrganizer: false, now: T.at("2026-10-08T14:00:00Z"))
        #expect(b.phase == .open)
        let wait = try #require(b.secondsUntilLockCheck(now: T.at("2026-10-08T14:59:00Z")))
        #expect(wait == 60 + TipsBoard.lockCheckMargin)
        // Telefonens klokke foran serveren: serveren sa åpen etter fristen, prøv igjen senere.
        var skewed = input
        skewed.serverOpen = true
        let late = TipsBoard(skewed, me: T.id(T.anders), isOrganizer: false, now: T.at("2026-10-08T15:00:10Z"))
        #expect(late.secondsUntilLockCheck(now: T.at("2026-10-08T15:00:10Z")) == TipsBoard.lockRecheckInterval)
        // Låst: ingen ny henting.
        let locked = TipsBoard(input, me: T.id(T.anders), isOrganizer: false, now: T.at("2026-10-08T15:00:00Z"))
        #expect(locked.secondsUntilLockCheck(now: T.at("2026-10-08T15:00:00Z")) == nil)
    }

    @Test func resultatlinjaForVoiceOver() {
        #expect(TipsBoard.resultAccessibilityLabel(place: 1, name: "Anders", isWinner: true, points: 4, possible: 5)
                == "1. plass, Anders, tippekonge, 4 av 5 riktige")
        #expect(TipsBoard.resultAccessibilityLabel(place: 3, name: "Deg", isWinner: false, points: 2, possible: 4)
                == "3. plass, Deg, 2 av 4 riktige")
    }

    /// Ingen påmeldt: hele troppen står først.
    @Test func ingenPaameldt() {
        let b = TipsBoard(TipsInput(event: T.event, members: T.four), me: T.id(T.anders), isOrganizer: true,
                          now: T.at("2026-10-01T12:00:00Z"))
        #expect(b.firstCandidates.count == 4 && b.otherCandidates.isEmpty)
        #expect(b.canEditSettings)
        #expect(b.potText == "0 levert")
    }

    /// Kvelden uten innsats og linje får regelsettets standard; 0 er for æra.
    @Test func innsatsOgLinjeFraRegelsettet() {
        var event = T.event
        event.stakePoints = nil
        event.line = nil
        var rules = Ruleset.golfgutu
        rules.tips.defaultStakePoints = 20
        rules.tips.defaultLine = 1.5
        var input = TipsInput(event: event, rules: rules, members: T.four)
        var b = TipsBoard(input, me: T.id(T.anders), isOrganizer: false, now: T.at("2026-10-01T12:00:00Z"))
        #expect(b.stake == 20 && b.line == 1.5)
        input.event.stakePoints = 0
        b = TipsBoard(input, me: T.id(T.anders), isOrganizer: false, now: T.at("2026-10-01T12:00:00Z"))
        #expect(b.stake == 0 && b.stakeText == "For æra · ingen poeng")
        input.event.startTime = nil
        rules.tips.defaultStartTime = "18:00"
        input.rules = rules
        b = TipsBoard(input, me: T.id(T.anders), isOrganizer: false, now: T.at("2026-10-01T12:00:00Z"))
        #expect(b.deadline == T.at("2026-10-08T16:00:00Z"))
    }

    /// Lagret spillehandicap går foran: 18 hull, handicap 18, slagene fra appen.
    @Test func lagretSpillehandicap() {
        let erik = T.member(5, "Erik", hcp: 18)
        let strokes = [5, 6, 4, 5, 5, 4, 6, 5, 4, 5, 4, 6, 5, 5, 4, 5, 6, 5]
        var input = TipsInput(event: T.event, members: T.four + [erik])
        input.serverOpen = false
        input.rounds = [T.round(1, firstHole: 1, holeCount: 18, external: false, format: "stableford", strokes: [5: strokes])]
        var b = TipsBoard(input, me: T.id(T.anders), isOrganizer: false)
        // tippekupong-test.js, «Netto med appens slag»: 18 par-hull, birdie, 35 på første ni, −0,5.
        #expect(b.answerKey.mostParsHoles == 18 && b.answerKey.birdie == true)
        #expect(b.answerKey.frontNineNet == 35 && b.answerKey.average == -0.5)
        input.rounds = [T.round(1, firstHole: 1, holeCount: 18, external: false, format: "stableford",
                                strokes: [5: strokes], playing: [5: 0])]
        b = TipsBoard(input, me: T.id(T.anders), isOrganizer: false)
        #expect(b.answerKey.frontNineNet == 44)
    }

    @Test func kortNavn() {
        let members = [T.member(1, "Anders Hansen"), T.member(2, "Anders Berg"), T.member(3, "Cato Lie"), T.member(4, "")]
        let n = TipsBoard.shortNames(members)
        #expect(n[T.id(1)] == "Anders H." && n[T.id(2)] == "Anders B.")
        #expect(n[T.id(3)] == "Cato")
        #expect(n[T.id(4)] == "")
    }
}

struct TipsDraftTests {
    @Test func knappenOgEndringer() {
        let me = T.id(T.anders)
        var d = TipsDraft(me: me, saved: nil)
        #expect(d.buttonTitle(saved: nil) == "Send inn kupongen")
        #expect(!d.canSubmit(saved: nil))
        d.choose(.winner, player: T.id(T.anders))
        d.choose(.frontNine, player: T.id(T.dag))
        d.choose(.mostPars, player: T.id(T.anders))
        d.set(.birdie, true)
        #expect(!d.canSubmit(saved: nil), "fire av fem")
        d.set(.over, false)
        #expect(d.canSubmit(saved: nil))
        let saved = d.coupon
        #expect(d.buttonTitle(saved: saved) == "Levert" && !d.canSubmit(saved: saved))
        d.set(.over, true)
        #expect(d.buttonTitle(saved: saved) == "Lagre endringene" && d.canSubmit(saved: saved))
        d.choose(.birdie, player: T.id(T.cato))
        #expect(d.coupon.birdie == true, "spiller på et ja/nei-spørsmål ignoreres")
    }
}

struct TipsRowsTests {
    @Test func upsertSkriverAlleSvarOgSjekkes() throws {
        let coupon = TipsCoupon(playerID: T.id(T.bjorn).uuidString, winner: T.id(T.anders).uuidString, birdie: true)
        let row = TipsUpsert(eventID: T.eventID, memberID: T.id(T.bjorn), clubID: T.club, coupon: coupon)
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(row)) as? [String: Any]
        #expect(Set(json.map { Array($0.keys) } ?? []) == ["event_id", "member_id", "club_id", "winner", "front_nine", "most_pars", "birdie", "over_line"])
        #expect(json?["front_nine"] is NSNull && json?["over_line"] is NSNull)
        let back = TipsRow(eventID: T.eventID, memberID: T.id(T.bjorn), clubID: T.club, winner: T.id(T.anders),
                           frontNine: nil, mostPars: nil, birdie: true, overLine: nil, updatedAt: nil)
        #expect(row.matches(back))
        var other = back
        other.birdie = false
        #expect(!row.matches(other))
        #expect(back.coupon == coupon)
    }

    @Test func oppsettSkriverNull() throws {
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(TipsSettingsUpdate(stakePoints: nil, line: 1.5))) as? [String: Any]
        #expect(json?["tips_stake_points"] is NSNull && json?["tips_line"] as? Double == 1.5)
    }

    @Test func kveldsradenLeses() throws {
        let data = Data("""
        {"id":"\(T.eventID)","club_id":"\(T.club)","season_id":null,"event_date":"2026-10-08",
         "start_time":"17:00:00","tips_stake_points":0,"tips_line":-1.5}
        """.utf8)
        let row = try JSONDecoder().decode(TipsEventRow.self, from: data)
        #expect(row.stakePoints == 0 && row.line == -1.5 && row.startTime == "17:00:00")
    }

    @Test func tidspunktFraPostgres() {
        let want = T.at("2026-10-08T15:00:00Z")
        #expect(TipsQueries.parseTimestamp("2026-10-08T15:00:00+00:00") == want)
        #expect(TipsQueries.parseTimestamp("2026-10-08T15:00:00.000+00:00") == want)
        #expect(TipsQueries.parseTimestamp("2026-10-08 15:00:00+00") == want)
        #expect(TipsQueries.parseTimestamp("ikke en tid") == nil)
    }

    @Test func laastFeilmelding() {
        #expect(TipsModel.mapLocked(.notAllowed) == TipsModel.locked)
        #expect(TipsModel.mapLocked(.offline) == .offline)
    }
}
