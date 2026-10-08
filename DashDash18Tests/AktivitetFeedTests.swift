import Foundation
import Testing
@testable import DashDash18

// «I dag / Tidligere» i Europe/Oslo, tid ved linja, uleste og reaksjonsbrikker.

private func id(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))! }
private let club = id(900), me = id(9), anders = id(1), bjorn = id(2), aase = id(3)

private func at(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

private func row(_ n: Int, _ iso: String, actor: UUID? = nil) -> ActivityRow {
    let event = ActivityEvent.memberJoined(member: anders)
    return ActivityRow(id: id(n), clubID: club, kind: event.kind, category: event.category, data: event.data,
                       actorMemberID: actor, createdAt: at(iso))
}

struct AktivitetGrupperingTests {
    @Test func iDagErKalenderdagenIOslo() {
        // 23:30 i Oslo 6. oktober (sommertid, UTC+2).
        let now = at("2026-10-06T21:30:00Z")
        let rows = [
            row(1, "2026-10-05T22:30:00Z"),  // 00:30 Oslo 6. okt. (5. okt. i UTC)
            row(2, "2026-10-05T21:45:00Z"),  // 23:45 Oslo 5. okt.
            row(3, "2026-10-06T20:00:00Z"),  // 22:00 Oslo 6. okt.
        ]
        let sections = ActivityFeed.sections(rows, now: now)
        #expect(sections.map(\.title) == ["I dag", "Tidligere"])
        #expect(sections[0].rows.map(\.id) == [id(3), id(1)])  // nyeste først
        #expect(sections[1].rows.map(\.id) == [id(2)])
    }

    @Test func etterMidnattIOsloErGårsdagenTidligere() {
        // 00:30 Oslo 7. oktober, men fortsatt 6. oktober i UTC.
        let now = at("2026-10-06T22:30:00Z")
        let sections = ActivityFeed.sections([row(1, "2026-10-06T21:00:00Z")], now: now)
        #expect(sections.map(\.title) == ["Tidligere"])
    }

    @Test func vintertid() {
        // 00:30 Oslo 10. desember = 23:30 UTC 9. desember (UTC+1).
        let now = at("2026-12-10T08:00:00Z")
        let sections = ActivityFeed.sections([row(1, "2026-12-09T23:30:00Z"), row(2, "2026-12-09T22:59:00Z")], now: now)
        #expect(sections.map(\.title) == ["I dag", "Tidligere"])
        #expect(sections[0].rows.map(\.id) == [id(1)])
    }

    @Test func tomListeGirIngenSeksjoner() {
        #expect(ActivityFeed.sections([], now: .now).isEmpty)
    }
}

struct AktivitetTidTests {
    // 21:00 i Oslo 6. oktober.
    let now = at("2026-10-06T19:00:00Z")

    @Test func nåMinutterOgTimer() {
        #expect(ActivityFeed.relativeTime(now.addingTimeInterval(-30), now: now) == "nå")
        #expect(ActivityFeed.relativeTime(now.addingTimeInterval(5), now: now) == "nå")
        #expect(ActivityFeed.relativeTime(now.addingTimeInterval(-3 * 60), now: now) == "3 min")
        #expect(ActivityFeed.relativeTime(now.addingTimeInterval(-59 * 60), now: now) == "59 min")
        #expect(ActivityFeed.relativeTime(now.addingTimeInterval(-2 * 3600 - 60), now: now) == "2 t")
    }

    @Test func iGårMedKlokkeslettIOslo() {
        #expect(ActivityFeed.relativeTime(at("2026-10-05T19:04:00Z"), now: now) == "i går 21:04")
        // 30 minutter siden, men før midnatt i Oslo.
        let afterMidnight = at("2026-10-06T22:10:00Z")  // 00:10 Oslo 7. okt.
        #expect(ActivityFeed.relativeTime(at("2026-10-06T21:40:00Z"), now: afterMidnight) == "30 min")
        #expect(ActivityFeed.relativeTime(at("2026-10-06T20:00:00Z"), now: afterMidnight) == "i går 22:00")
    }

    @Test func eldreGirDato() {
        #expect(ActivityFeed.relativeTime(at("2026-10-03T10:00:00Z"), now: now) == "3. okt.")
        #expect(ActivityFeed.relativeTime(at("2026-05-17T10:00:00Z"), now: now) == "17. mai")
        #expect(ActivityFeed.relativeTime(at("2025-10-03T10:00:00Z"), now: now) == "3. okt. 2025")
    }

    @Test func vintertidIGår() {
        let winter = at("2026-12-10T12:00:00Z")
        #expect(ActivityFeed.relativeTime(at("2026-12-09T20:04:00Z"), now: winter) == "i går 21:04")
    }
}

struct AktivitetUlestTests {
    let rows = [
        row(1, "2026-10-06T18:00:00Z", actor: anders),
        row(2, "2026-10-06T18:30:00Z", actor: me),  // egen
        row(3, "2026-10-06T19:00:00Z"),               // systemet
        row(4, "2026-10-06T17:00:00Z", actor: bjorn),
    ]

    @Test func nyereEnnSistSettOgIkkeEgne() {
        #expect(ActivityFeed.unreadCount(rows, lastSeen: at("2026-10-06T17:30:00Z"), me: me) == 2)
        #expect(ActivityFeed.unreadCount(rows, lastSeen: at("2026-10-06T19:00:00Z"), me: me) == 0)
        #expect(ActivityFeed.isUnread(rows[0], lastSeen: at("2026-10-06T17:59:59Z"), me: me))
        #expect(!ActivityFeed.isUnread(rows[0], lastSeen: at("2026-10-06T18:00:00Z"), me: me))
    }

    @Test func aldriSettErAltUlestUnntattEgne() {
        #expect(ActivityFeed.unreadCount(rows, lastSeen: nil, me: me) == 3)
        #expect(ActivityFeed.unreadCount(rows, lastSeen: nil, me: nil) == 4)
    }

    @Test func sistSettFlyttesBareFramOgErPerKlubb() throws {
        let suite = "aktivitet-test-\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let store = ActivitySeenStore(clubID: club, suite: suite)
        #expect(store.lastSeen == nil)
        store.markSeen(rows)
        #expect(store.lastSeen == at("2026-10-06T19:00:00Z"))
        store.markSeen(upTo: at("2026-10-06T10:00:00Z"))
        #expect(store.lastSeen == at("2026-10-06T19:00:00Z"))
        store.markSeen([])
        #expect(store.lastSeen == at("2026-10-06T19:00:00Z"))
        #expect(ActivitySeenStore(clubID: id(901), suite: suite).lastSeen == nil)
    }

    @Test func bjellaTellerOgViserNiPluss() {
        #expect(ActivityFeed.unreadCount(rows, lastSeen: nil, me: me) == 3)
        #expect(HomeBell.label(0) == nil)
        #expect(HomeBell.label(3) == "3")
        #expect(HomeBell.label(12) == "9+")
    }
}

struct AktivitetReaksjonTests {
    let activity = id(100)
    let names = [anders: "Anders", bjorn: "Bjørn", aase: "Åse", me: "Thomas"]

    func r(_ member: UUID, _ emoji: ActivityReaction, on act: UUID? = nil) -> ActivityReactionRow {
        ActivityReactionRow(activityID: act ?? activity, memberID: member, clubID: club, emoji: emoji)
    }

    @Test func brikkeneIFastRekkefølgeMedAntallOgNavn() {
        let rows = [r(aase, .heart), r(anders, .fire), r(me, .fire), r(bjorn, .thumbsUp), r(anders, .heart),
                    r(bjorn, .laugh, on: id(101))]
        let chips = ActivityReactions.chips(for: activity, in: rows, me: me) { names[$0] }
        #expect(chips.map(\.reaction) == [.thumbsUp, .fire, .heart])
        #expect(chips.map(\.count) == [1, 2, 2])
        #expect(chips.map(\.isMine) == [false, true, false])
        #expect(chips[2].names == ["Anders", "Åse"])
        #expect(chips[1].names == ["Anders", "Thomas"])
    }

    @Test func trykkSetterOgFjernerBareMin() {
        let start = [r(anders, .fire)]
        let added = ActivityReactions.toggled(.fire, on: activity, by: me, club: club, in: start)
        #expect(added.count == 2)
        #expect(ActivityReactions.has(.fire, on: activity, by: me, in: added))
        let removed = ActivityReactions.toggled(.fire, on: activity, by: me, club: club, in: added)
        #expect(removed.map(\.memberID) == [anders])
        // Andre emojier på samme linje er lov.
        let two = ActivityReactions.toggled(.heart, on: activity, by: me, club: club, in: added)
        #expect(ActivityReactions.chips(for: activity, in: two, me: me) { names[$0] }.map(\.reaction) == [.fire, .heart])
    }

    @Test func ingenReaksjonerIngenBrikker() {
        #expect(ActivityReactions.chips(for: activity, in: [], me: me) { names[$0] }.isEmpty)
    }
}
