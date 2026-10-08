import Foundation
import Testing
@testable import DashDash18

// Bjella som «det som angår deg» (fase 19) og «sist sett» på tvers av klubbene.

struct HjemBjelleRegelTests {
    private let v = H.viewer

    private func reason(_ event: ActivityEvent, club: UUID = H.clubA, actor: UUID? = H.anders, round: UUID? = nil,
                        recipients: [UUID]? = nil, myRounds: Set<UUID> = []) -> HomeBellReason? {
        HomeBell.reason(H.row(1, club: club, event, actor: actor, round: round, at: H.now, recipients: recipients),
                        viewer: v, myRounds: myRounds)
    }

    @Test func detSomAngårDeg() {
        #expect(reason(.announcement(text: "Hei")) == .announcement)
        #expect(reason(.nudge(eventDate: nil), recipients: [H.me, H.bjorn]) == .nudged)
        #expect(reason(.nudge(eventDate: nil), recipients: [H.bjorn]) == nil)
        #expect(reason(.nudge(eventDate: nil)) == .nudged)
        #expect(reason(.betChallenge(question: "Q", against: H.me, side: "yes", points: 5)) == .challenged)
        #expect(reason(.betChallenge(question: "Q", against: H.bjorn, side: "yes", points: 5)) == nil)
        #expect(reason(.bigScore(member: H.me, hole: 3, holeIndex: 2, name: .eagle, strokes: 1, par: 3)) == .myFeat)
        #expect(reason(.bigScore(member: H.anders, hole: 3, holeIndex: 2, name: .eagle, strokes: 1, par: 3)) == nil)
        #expect(reason(.roundLocked(roundNo: 1, courseName: nil), round: H.clubRound, myRounds: [H.clubRound]) == .myRound)
        #expect(reason(.roundDeleted(roundNo: 1, courseName: nil), round: H.clubRound, myRounds: [H.clubRound]) == .myRound)
        #expect(reason(.roundLocked(roundNo: 1, courseName: nil), round: H.clubRound) == nil)
        #expect(reason(.sidePrize(kind: .kp, member: H.anders, hole: 3, meters: 2, passed: H.me, passedMeters: 3)) == .passed)
        #expect(reason(.sidePrize(kind: .kp, member: H.anders, hole: 3, meters: 2, passed: nil, passedMeters: nil)) == nil)
        #expect(reason(.scoreCorrected(member: H.me, hole: 1, from: 5, to: 4, roundNo: 1, courseName: nil)) == .corrected)
        #expect(reason(.tipsKing(members: [H.me], correct: 4, possible: 5, eventDate: nil)) == .tipsKing)
        #expect(reason(.committeeDrawn(eventDate: nil, members: [H.anders, H.me])) == .committee)
    }

    @Test func tabellen() {
        func table(_ from: Int, _ to: Int) -> ActivityEvent {
            .tableChanged(competition: H.jakke.id, competitionName: "Jakkeracet", roundNo: 2,
                          table: [ActivityTableSpot(member: H.anders, place: 1, from: 1),
                                  ActivityTableSpot(member: H.me, place: to, from: from)])
        }
        #expect(reason(table(2, 4)) == .passed)
        #expect(reason(table(4, 2)) == .climbed)
        #expect(reason(table(3, 3)) == nil)
        #expect(reason(.tableChanged(competition: H.jakke.id, competitionName: "J", roundNo: 2,
                                     table: [ActivityTableSpot(member: H.anders, place: 1, from: 2)])) == nil)
    }

    @Test func ikkeDetSomBareStårIFeeden() {
        #expect(reason(.signup(member: H.anders, status: .yes, eventDate: nil)) == nil)
        #expect(reason(.leadChanged(afterHole: 9, leaders: [H.me], points: 20, outcome: .leads)) == nil)
        #expect(reason(.reminder(eventDate: nil, coming: 3, unsure: 0)) == nil)
        #expect(reason(.betCreated(question: "Q", side: nil, points: nil)) == nil)
        #expect(reason(.memberJoined(member: H.me)) == nil)
        #expect(reason(.roundStarted(roundNo: 1, courseName: nil, holeCount: 18, bays: nil, ldHole: nil, kpHole: nil),
                       round: H.clubRound, myRounds: [H.clubRound]) == nil)
    }

    @Test func medlemmetDittIRiktigKlubb() {
        // I klubb B er du et annet medlem.
        #expect(reason(.bigScore(member: H.meB, hole: 3, holeIndex: 2, name: .eagle, strokes: 1, par: 3), club: H.clubB) == .myFeat)
        #expect(reason(.bigScore(member: H.me, hole: 3, holeIndex: 2, name: .eagle, strokes: 1, par: 3), club: H.clubB) == nil)
        #expect(reason(.announcement(text: "x"), club: H.id(777)) == nil)
    }

    @Test func nevntITråden() {
        func message(_ from: UUID, _ mentions: [UUID], club: UUID = H.clubA, at: Date = H.now) -> ThreadMessageRow {
            ThreadMessageRow(id: UUID(), clubID: club, eventID: H.id(950), memberID: from, body: "Hei", mentions: mentions,
                             imagePath: nil, createdAt: at)
        }
        #expect(HomeBell.mentionsMe(message(H.anders, [H.me]), viewer: v))
        #expect(!HomeBell.mentionsMe(message(H.anders, [H.bjorn]), viewer: v))
        #expect(!HomeBell.mentionsMe(message(H.me, [H.me]), viewer: v))
        #expect(HomeBell.mentionsMe(message(H.kari, [H.meB], club: H.clubB), viewer: v))

        let rows = [
            H.row(1, .announcement(text: "a"), actor: H.anders, at: H.ago(minutes: 5)),
            H.row(2, .announcement(text: "b"), actor: H.me, at: H.ago(minutes: 4)),  // din egen
            H.row(3, .signup(member: H.anders, status: .yes, eventDate: nil), actor: H.anders, at: H.ago(minutes: 3)),
            H.row(4, .announcement(text: "c"), actor: H.anders, at: H.ago(days: 2)),  // sett
        ]
        let mentions = [message(H.anders, [H.me], at: H.ago(minutes: 2)), message(H.anders, [H.me], at: H.ago(days: 3))]
        #expect(HomeBell.unreadCount(rows, mentions: mentions, lastSeen: H.ago(days: 1), viewer: v) == 2)
        #expect(HomeBell.unreadCount(rows, mentions: mentions, lastSeen: nil, viewer: v) == 4)
        #expect(HomeBell.rows(rows, viewer: v).map(\.id) == [H.id(10_002), H.id(10_001), H.id(10_004)])
        #expect(HomeBell.label(0) == nil)
        #expect(HomeBell.label(4) == "4")
        #expect(HomeBell.label(12) == "9+")
    }
}

struct HjemSistSettTests {
    private func store(_ clock: HomeSeenStore.Clock, suite: String) -> HomeSeenStore {
        HomeSeenStore(userID: H.profile, clock: clock, suite: suite)
    }

    private func freshSuite() -> String {
        let suite = "hjem-test-\(UUID().uuidString)"
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        return suite
    }

    @Test func flytterBareFram() {
        let suite = freshSuite()
        let feed = store(.feed, suite: suite)
        #expect(feed.lastSeen() == nil)
        feed.markSeen(upTo: H.ago(minutes: 10))
        feed.markSeen(upTo: H.ago(minutes: 30))
        #expect(feed.lastSeen() == H.ago(minutes: 10))
        feed.markSeen(upTo: H.ago(minutes: 1))
        #expect(feed.lastSeen() == H.ago(minutes: 1))
    }

    @Test func toKlokkerPerInnlogging() {
        let suite = freshSuite()
        store(.feed, suite: suite).markSeen(upTo: H.ago(minutes: 10))
        #expect(store(.bell, suite: suite).lastSeen() == nil)
        #expect(HomeSeenStore(userID: H.anders, clock: .feed, suite: suite).lastSeen() == nil)
        #expect(store(.feed, suite: suite).key == "hjem.sistSett.\(H.profile.uuidString.lowercased())")
        #expect(store(.bell, suite: suite).key.hasPrefix("bjelle.sistSett."))
    }

    @Test func førsteGangBrukesDetNyesteFraVarslerIKlubbene() {
        let suite = freshSuite()
        ActivitySeenStore(clubID: H.clubA, suite: suite).markSeen(upTo: H.ago(days: 2))
        ActivitySeenStore(clubID: H.clubB, suite: suite).markSeen(upTo: H.ago(days: 1))
        let bell = store(.bell, suite: suite)
        #expect(bell.lastSeen(fallbackClubs: [H.clubA, H.clubB]) == H.ago(days: 1))
        #expect(bell.lastSeen(fallbackClubs: []) == nil)
        bell.markSeen(upTo: H.ago(days: 3))
        #expect(bell.lastSeen(fallbackClubs: [H.clubA, H.clubB]) == H.ago(days: 3))  // egen verdi går foran
        bell.clear()
        #expect(bell.lastSeen() == nil)
    }
}
