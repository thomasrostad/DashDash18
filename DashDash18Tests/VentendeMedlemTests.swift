import Foundation
import Testing
@testable import DashDash18

// Noen vil bli med i klubben (1.0.1, sql/067): hendelsen member_pending, teksten (samme som
// push-send), trykk på varselet, bjella, gruppen og merket. Ingen nettverk.

struct VentendeMedlemHendelseTests {
    private let ola = UUID(uuidString: "00000000-0000-0000-0000-000000000067")!

    @Test func lesesFraRadenSomServerenSkriver() throws {
        // Slik 067 skriver data (jsonb_build_object: member, name, club_name).
        let json = """
        {"id": "aaaaaaaa-0000-0000-0000-000000000001", "club_id": "aaaaaaaa-0000-0000-0000-000000000002",
         "kind": "member_pending", "category": "club",
         "data": {"member": "\(ola.uuidString.lowercased())", "name": "Ola Nordmann",
                  "club_name": "Golfgutu Invitational"},
         "actor_member_id": "\(ola.uuidString.lowercased())",
         "recipients": ["00000000-0000-0000-0000-000000000009"],
         "created_at": "2026-10-21T18:00:00Z"}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let row = try decoder.decode(ActivityRow.self, from: Data(json.utf8))
        #expect(row.category == .club)
        #expect(row.event == .memberPending(member: ola, name: "Ola Nordmann", clubName: "Golfgutu Invitational"))
        #expect(ActivityEvent.knownKinds.contains("member_pending"))
    }

    @Test func tilOgFraData() {
        let event = ActivityEvent.memberPending(member: ola, name: "Ola", clubName: "Golfgutu Invitational")
        #expect(event.kind == "member_pending")
        #expect(event.category == .club)
        #expect(ActivityEvent(kind: event.kind, data: event.data) == event)
        #expect(ActivityEvent(kind: "member_pending", data: ActivityData(name: "Ola")) == .unknown(kind: "member_pending"))
    }

    @Test func tekstenErSomPushen() {
        let event = ActivityEvent.memberPending(member: ola, name: "Ola Nordmann", clubName: "Golfgutu Invitational")
        let display = ActivityText.display(event, actor: ola, name: { _ in nil })
        #expect(display.text == "Ola Nordmann vil bli med i Golfgutu Invitational")
        #expect(display.emoji == "🙋")
        // Uten navn i data: navnet fra lista. Uten klubb: «klubben».
        let bare = ActivityText.display(.memberPending(member: ola, name: "  ", clubName: nil), actor: ola,
                                        name: { $0 == ola ? "Ola" : nil })
        #expect(bare.text == "Ola vil bli med i klubben")
    }
}

struct VentendeMedlemTrykkTests {
    private let club = UUID(uuidString: "9c4f5b5d-4444-4c3a-9d55-2b7a0d9f0a04")!

    /// Slik push-send pakker den (`apnsBody`): type, id, kind, club_id og kategorien.
    private var userInfo: [AnyHashable: Any] {
        ["aps": ["alert": ["title": "Golfgutu Invitational", "body": "🙋 Ola Nordmann vil bli med i Golfgutu Invitational"]],
         "dd18": ["type": "activity", "activity_id": "a1", "kind": "member_pending", "category": "club",
                  "club_id": club.uuidString.lowercased()]]
    }

    @Test func aapnerTroppenIKlubben() {
        let tap = PushTap(userInfo: userInfo, pendingMembers: true)
        #expect(tap?.destination == .roster)
        #expect(tap?.destination.tab == .arrangor)
        #expect(tap?.clubID == club)
    }

    @Test func utenFlaggetBareHjem() {
        #expect(PushTap(userInfo: userInfo, pendingMembers: false)?.destination == .home)
    }

    @Test func deAndreFanene() {
        #expect(PushDestination.tavla.tab == .tavla)
        #expect(PushDestination.notifications.tab == .hjem)
        #expect(PushDestination.home.tab == .hjem)
    }
}

struct VentendeMedlemBjelleTests {
    private let ola = H.id(67)

    private func row(recipients: [UUID]?, club: UUID = H.clubA) -> ActivityRow {
        H.row(1, club: club, .memberPending(member: ola, name: "Ola Nordmann", clubName: "Golfgutu Invitational"),
              actor: ola, at: H.now, recipients: recipients)
    }

    @Test func tilDemMedRettigheten() {
        #expect(HomeBell.reason(row(recipients: [H.me, H.anders]), viewer: H.viewer, pendingMembers: true) == .memberPending)
        #expect(HomeBell.reason(row(recipients: [H.anders]), viewer: H.viewer, pendingMembers: true) == nil)
        #expect(HomeBell.reason(row(recipients: nil), viewer: H.viewer, pendingMembers: true) == nil)
        // Klubb B: du er et annet medlem der.
        #expect(HomeBell.reason(row(recipients: [H.meB], club: H.clubB), viewer: H.viewer, pendingMembers: true)
                == .memberPending)
    }

    @Test func avUtenFlagget() {
        #expect(HomeBell.reason(row(recipients: [H.me]), viewer: H.viewer, pendingMembers: false) == nil)
    }

    @Test func linjaHarTroppen() {
        let sections = HomeBellList.sections([row(recipients: [H.me])], reactions: [], names: H.names,
                                             viewer: H.viewer, lastSeen: nil, now: H.now)
        let item = sections.first?.items.first
        #expect(item?.opensRoster == H.clubA)
        #expect(item?.display.text == "Ola Nordmann vil bli med i Golfgutu Invitational")
        #expect(item?.isUnread == true)
        // Andre linjer har ingen Tropp.
        let other = HomeBellList.sections([H.row(2, .announcement(text: "Hei"), actor: H.anders, at: H.now)],
                                          reactions: [], names: H.names, viewer: H.viewer, lastSeen: nil, now: H.now)
        #expect(other.first?.items.first?.opensRoster == nil)
    }
}

struct VentendeMedlemGruppeTests {
    @Test func arrangoerGruppen() {
        #expect(PushGroup.of(category: "club", kind: "member_pending") == .organizer)
        #expect(PushGroup.of(category: "club", kind: "member_joined") == .social)
        #expect(PushGroup.of(category: "club") == .social)
        #expect(PushGroupMap.kindTitle("member_pending") == "Nye som vil bli med i klubben")
    }

    @Test func serverensKartViserDenUnderArrangoer() {
        // Raden fra push_group_map() i 067.
        let map = PushGroupMap(rows: [
            PushGroupMapRow(groupKey: "social", category: "club", kind: "member_joined"),
            PushGroupMapRow(groupKey: "organizer", category: "club", kind: "member_pending"),
            PushGroupMapRow(groupKey: "organizer", category: "signup", kind: "signup_dropped"),
            PushGroupMapRow(groupKey: "evening", category: "signup", kind: "signup"),
            PushGroupMapRow(groupKey: "evening", category: "signup", kind: "waitlist_promoted"),
        ])
        #expect(map.extraKinds(in: .organizer).sorted() == ["member_pending", "signup_dropped"])
        #expect(map.mainGroup(of: "club") == .social)
    }
}

struct VentendeMedlemMerkeTests {
    @Test func merket() {
        #expect(PendingMembers.badge(count: 3, canManage: true, enabled: true) == 3)
        #expect(PendingMembers.badge(count: 3, canManage: false, enabled: true) == 0)
        #expect(PendingMembers.badge(count: 3, canManage: true, enabled: false) == 0)
        #expect(PendingMembers.badge(count: 0, canManage: true, enabled: true) == 0)
    }

    @Test func tekstene() {
        #expect(PendingMembers.rowTitle(count: 1, firstName: "Ola Nordmann") == "Ola Nordmann vil bli med")
        #expect(PendingMembers.rowTitle(count: 1, firstName: " ") == "1 vil bli med i klubben")
        #expect(PendingMembers.rowTitle(count: 3, firstName: "Ola") == "3 vil bli med i klubben")
        #expect(PendingMembers.menuTitle("Troppen", count: 2) == "Troppen (2 venter)")
        #expect(PendingMembers.menuTitle("Troppen", count: 0) == "Troppen")
    }
}
