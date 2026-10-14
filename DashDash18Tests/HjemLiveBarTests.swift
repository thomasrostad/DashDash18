import Foundation
import GolfgutuCore
import Testing
@testable import DashDash18

// Utbedringsplanen V1, V2, P2 og 4.1 på Hjem: baren over fanelinja, fristen under svaret og bragd-
// og tabellkortene.

struct HjemLiveBarTests {
    private func row(_ name: String, me: Bool = false, thru: Int = 9, place: Int? = 3, total: Int = 21,
                     value: String = "21") -> BayenRow {
        BayenRow(members: [H.id(70)], name: name, isMe: me, thru: thru, bay: 2, place: place, total: total, match: nil,
                 value: value, tone: .neutral)
    }

    @Test func linjaUnderTittelen() {
        #expect(HomeLiveBar.detail(bay: "Bås 2", mine: row("Thomas", me: true), leader: nil) == "Bås 2 · du er 3. med 21 p")
        // Hull for hull: stillingen, ikke plass.
        #expect(HomeLiveBar.detail(bay: "Bås 1", mine: row("Thomas", me: true, place: nil, value: "1 opp"), leader: nil)
                == "Bås 1 · du står 1 opp")
        // Før første hull: bare båsen.
        #expect(HomeLiveBar.detail(bay: "Bås 2", mine: row("Thomas", me: true, thru: 0), leader: nil) == "Bås 2")
        // Arrangøren som ikke spiller: lederen.
        #expect(HomeLiveBar.detail(bay: nil, mine: nil, leader: row("Bjørn", place: 1, total: 23)) == "Bjørn leder med 23 p")
        #expect(HomeLiveBar.detail(bay: nil, mine: nil, leader: nil) == nil)
        #expect(HomeLiveBar.capitalized("bås 2") == "Bås 2")
    }

    @Test func flereRunderSamtidig() {
        #expect(HomeLiveBar.moreText(count: 1) == nil)
        #expect(HomeLiveBar.moreText(count: 2) == "+1 runde til")
        #expect(HomeLiveBar.moreText(count: 3) == "+2 runder til")
    }

    @Test func løseRunderUtenKlubb() throws {
        let rounds = [H.myLooseRound(status: .active), H.myLooseRound(status: .locked)]
        let live = LiveRoundsModel.live(rounds, userID: H.profile, now: H.now)
        let first = try #require(live.first)
        #expect(live.count == 1)
        #expect(first.isLoose)
        #expect(first.barTitle == "Oslo GK · hull 2 av 18")
        #expect(first.barDetail?.hasPrefix("Bås 1 · du er ") == true)
        // Ikke deltaker: ingen bar.
        #expect(LiveRoundsModel.live(rounds, userID: H.id(999), now: H.now).isEmpty)
    }

    @Test func arrangørenSomIkkeSpillerFølger() throws {
        let s = H.snapshot(H.roundRow(H.clubRound, club: H.clubA, status: .active, roundNo: 4, started: H.ago(minutes: 60)),
                           players: [(H.anders, "Anders Berg", 1), (H.bjorn, "Bjørn", 1)],
                           scores: [(H.anders, 0, 3, nil), (H.bjorn, 0, 4, nil)])
        var input = H.input()
        input.live = [HomeLiveInput(snapshot: s, viewer: Viewer(memberID: H.me, isOrganizer: true))]
        let live = try #require(HomeFeed.build(input).live.first)
        #expect(live.barAction == "Følg")
        #expect(live.barDetail?.contains("leder med") == true)
    }
}

struct HjemSvarfristTests {
    private let now = H.now
    private var tomorrow: Date { now.addingTimeInterval(86_400) }

    @Test func fristenErstatterAngre() {
        // Kommer: avmeldingsfristen gjelder.
        let note = HomeAnswerNote.text(answer: .yes, signupDeadline: nil, withdrawDeadline: tomorrow, now: now)
        #expect(note.hasPrefix("Du kan endre svaret fram til fredag 9. oktober kl. "))
        // Kommer ikke: påmeldingsfristen gjelder, ikke avmeldingsfristen.
        #expect(HomeAnswerNote.text(answer: .no, signupDeadline: nil, withdrawDeadline: tomorrow, now: now)
                == "Du kan endre svaret når som helst.")
        #expect(HomeAnswerNote.text(answer: nil, signupDeadline: tomorrow, withdrawDeadline: nil, now: now)
                .hasPrefix("Svar innen fredag 9. oktober"))
    }

    @Test func utenFristOgEtterFristen() {
        #expect(HomeAnswerNote.text(answer: nil, signupDeadline: nil, withdrawDeadline: nil, now: now)
                == "Svar, så vet arrangøren hvem som kommer.")
        let past = now.addingTimeInterval(-60)
        #expect(HomeAnswerNote.text(answer: .yes, signupDeadline: nil, withdrawDeadline: past, now: now)
                == "Fristen for å melde av er ute.")
        #expect(HomeAnswerNote.text(answer: .maybe, signupDeadline: past, withdrawDeadline: nil, now: now)
                == "Påmeldingen er stengt.")
    }

    @Test func fristenKommerFraKvelden() throws {
        var input = H.input()
        let event = EventRow(id: H.id(950), clubID: H.clubA, seasonID: nil, eventDate: "2026-10-15", startTime: "18:00:00",
                             venue: nil, note: nil)
        var evening = HomeEveningInput(clubID: H.clubA, clubName: "Golfgutu Invitational", event: event,
                                       today: "2026-10-08", answer: .yes, coming: 6, isOrganizer: false)
        evening.withdrawDeadline = tomorrow
        evening.comingNames = ["Anders", "Bjørn"]
        input.evening = evening
        let e = try #require(HomeFeed.build(input).evening)
        #expect(e.answerNote?.hasPrefix("Du kan endre svaret fram til") == true)
        #expect(e.comingNames == ["Anders", "Bjørn"])
    }
}

struct HjemKortTests {
    @Test func bragdenSomI41() throws {
        let feed = HomeFeed.build(H.input([
            H.row(1, .bigScore(member: H.anders, hole: 5, holeIndex: 4, name: .eagle, strokes: 3, par: 5),
                  actor: H.anders, round: H.clubRound, at: H.ago(minutes: 3)),
        ]))
        let card = try #require(feed.sections.first?.cards.first)
        guard case .feat(let feat) = card.content else { Issue.record("ikke bragd"); return }
        #expect(HjemDisplay.featTitle(feat) == "Anders Berg slo eagle")
        #expect(HjemDisplay.featLine(feat).hasPrefix("Hull 5, par 5"))
        // Dobbel sirkel: to under par brutto.
        #expect(ScoreShape.forGross(feat.strokes, par: feat.par) == .doubleCircle)
    }

    @Test func bevegelseMedTrekanter() {
        let up = HomeTableRow(id: H.id(1), place: 1, name: "Bjørn", points: "41", move: 1, isMe: false)
        let down = HomeTableRow(id: H.id(2), place: 2, name: "Anders", points: "39", move: -1, isMe: false)
        let still = HomeTableRow(id: H.id(3), place: 3, name: "Thomas", points: "36", move: 0, isMe: true)
        #expect([up, down, still].map(\.moveText) == ["▲1", "▼1", nil])
    }
}
