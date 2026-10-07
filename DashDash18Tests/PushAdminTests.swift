import Foundation
import Testing
@testable import DashDash18

// Arrangørens push-skjermer (fase 8): «Hva blir push» (clubs.push_disabled_categories) og
// «Hvem har push» (push_status i sql/010_push.sql).

struct ClubPushPlanTests {
    @Test func bryterneErKlubbkategorierPlussTraaden() {
        let keys = ClubPushPlan.toggles.map(\.key)
        #expect(keys == ["score", "lead", "round", "reminder", "side_prize", "tips", "signup", "social", "setup", "club", "thread"])
        // Alle må godtas av push_club_categories() i 010.
        let allowed = Set(PushCategories.clubToggleable.map(\.rawValue) + [PushCategories.threadKey])
        #expect(Set(keys).isSubset(of: allowed))
        #expect(!keys.contains("announcement"))
        #expect(!keys.contains("nudge"))
    }

    @Test func norskeNavnFraKategoriene() {
        let titles = Dictionary(uniqueKeysWithValues: ClubPushPlan.toggles.map { ($0.key, $0.title) })
        #expect(titles["score"] == "Store scorer")
        #expect(titles["reminder"] == "Påminnelser")
        #expect(titles["thread"] == "Kveldens tråd")
    }

    @Test func meldingTilAlleOgPurringErLaast() {
        #expect(ClubPushPlan.locked == [.announcement, .nudge])
        #expect(ClubPushPlan.locked.map(\.title) == ["Melding til alle", "Purring"])
    }

    @Test func slaaAvOgPaa() {
        var disabled: [String] = []
        disabled = ClubPushPlan.setting("score", on: false, in: disabled)
        #expect(disabled == ["score"])
        #expect(!ClubPushPlan.isOn("score", disabled: disabled))
        // To ganger av gir ikke dobbel id.
        disabled = ClubPushPlan.setting("score", on: false, in: disabled)
        #expect(disabled == ["score"])
        disabled = ClubPushPlan.setting("thread", on: false, in: disabled)
        disabled = ClubPushPlan.setting("score", on: true, in: disabled)
        #expect(disabled == ["thread"])
        #expect(ClubPushPlan.isOn("score", disabled: disabled))
    }

    @Test func ukjenteIderBeholdes() {
        let next = ClubPushPlan.setting("lead", on: false, in: ["fremtidig"])
        #expect(next == ["fremtidig", "lead"])
    }

    @Test func radenTilbakeSammenliknesUtenRekkefoelge() {
        #expect(ClubPushPlan.matches(["lead", "score"], ["score", "lead"]))
        #expect(!ClubPushPlan.matches(["score"], ["score", "lead"]))
    }

    @Test func kolonnenSomJSON() throws {
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(ClubPushRow(disabledCategories: ["tips"]))) as? [String: [String]]
        #expect(json == ["push_disabled_categories": ["tips"]])
        let row = try JSONDecoder().decode(ClubPushRow.self, from: Data(#"{"push_disabled_categories":[]}"#.utf8))
        #expect(row.disabledCategories.isEmpty)
    }
}

struct PushStatusTests {
    private func id(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))!
    }

    @Test func dekoderPushStatus() throws {
        let json = #"""
        [{"member_id":"00000000-0000-0000-0000-000000000001","has_login":true,"devices":2,"last_seen_at":"2026-10-07T18:30:00Z"},
         {"member_id":"00000000-0000-0000-0000-000000000002","has_login":false,"devices":0,"last_seen_at":null}]
        """#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let rows = try decoder.decode([PushStatusRow].self, from: Data(json.utf8))
        #expect(rows.count == 2)
        #expect(rows[0] == PushStatusRow(memberID: id(1), hasLogin: true, devices: 2, lastSeenAt: Date(timeIntervalSince1970: 1_791_397_800)))
        #expect(rows[1].lastSeenAt == nil)
        #expect(!rows[1].hasLogin)
    }

    @Test func treListerSortertNorsk() {
        let seen = Date(timeIntervalSince1970: 1_000)
        let status = [
            PushStatusRow(memberID: id(1), hasLogin: true, devices: 1, lastSeenAt: seen),
            PushStatusRow(memberID: id(2), hasLogin: true, devices: 0, lastSeenAt: nil),
            PushStatusRow(memberID: id(3), hasLogin: false, devices: 0, lastSeenAt: nil),
            PushStatusRow(memberID: id(4), hasLogin: true, devices: 2, lastSeenAt: seen),
            PushStatusRow(memberID: id(5), hasLogin: true, devices: 3, lastSeenAt: seen),
        ]
        let names = [
            PushMemberName(id: id(1), displayName: "Øystein"),
            PushMemberName(id: id(2), displayName: "Bjørn"),
            PushMemberName(id: id(3), displayName: "Ledig"),
            PushMemberName(id: id(4), displayName: "Åse"),
            PushMemberName(id: id(5), displayName: "Anders"),
        ]
        let sections = PushStatusSections(status: status, names: names)
        // Norsk: Æ, Ø, Å kommer til slutt, i den rekkefølgen.
        #expect(sections.on.map(\.name) == ["Anders", "Øystein", "Åse"])
        #expect(sections.off.map(\.name) == ["Bjørn"])
        #expect(sections.noLogin.map(\.name) == ["Ledig"])
        #expect(sections.summary == "3 av 5 har push")
        #expect(sections.on.first?.state == .on(devices: 3, lastSeenAt: seen))
    }

    @Test func antallTelefoner() {
        let one = PushStatusEntry(id: id(1), name: "A", state: .on(devices: 1, lastSeenAt: nil))
        let two = PushStatusEntry(id: id(2), name: "B", state: .on(devices: 2, lastSeenAt: nil))
        let off = PushStatusEntry(id: id(3), name: "C", state: .off)
        #expect(one.devicesText == "1 telefon")
        #expect(two.devicesText == "2 telefoner")
        #expect(off.devicesText == nil)
    }

    @Test func navnSomManglerVisesSomUkjent() {
        let sections = PushStatusSections(
            status: [PushStatusRow(memberID: id(9), hasLogin: true, devices: 0, lastSeenAt: nil)],
            names: []
        )
        #expect(sections.off.map(\.name) == ["Ukjent spiller"])
    }

    @Test func likeNavnSorteresStabiltPaaId() {
        let status = [
            PushStatusRow(memberID: id(2), hasLogin: true, devices: 0, lastSeenAt: nil),
            PushStatusRow(memberID: id(1), hasLogin: true, devices: 0, lastSeenAt: nil),
        ]
        let names = [PushMemberName(id: id(1), displayName: "Per"), PushMemberName(id: id(2), displayName: "Per")]
        #expect(PushStatusSections(status: status, names: names).off.map(\.id) == [id(1), id(2)])
    }
}
