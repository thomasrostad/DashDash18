import Foundation
import GolfgutuCore
import Testing
@testable import DashDash18

private let club = UUID()

private func member(
    _ name: String,
    user: Bool = true,
    status: MemberStatus = .active,
    organizer: Bool = false,
    treasurer: Bool = false,
    seed: Int? = nil,
    handicap: Double? = nil
) -> ClubMemberRow {
    ClubMemberRow(
        id: UUID(), clubID: club, userID: user ? UUID() : nil, displayName: name,
        handicapIndex: handicap, seedGroup: seed, isOrganizer: organizer, isTreasurer: treasurer,
        status: status, avatarPath: nil
    )
}

struct TroppSectionsTests {
    @Test func grupperOgSortererNorsk() {
        let rows = [
            member("Østby"), member("Aasen"), member("Zeta"), member("Ærlig"),
            member("Ny", status: .pending), member("Borte", status: .archived),
            member("Ledig", user: false), member("Bjørn", status: .pending),
        ]
        let sections = TroppSections(rows)
        #expect(sections.pending.map(\.displayName) == ["Bjørn", "Ny"])
        // æ, ø og å etter z, som localeCompare(…, 'no').
        #expect(sections.active.map(\.displayName) == ["Ledig", "Zeta", "Ærlig", "Østby", "Aasen"])
        #expect(sections.archived.map(\.displayName) == ["Borte"])
    }

    @Test func ingenTakPaaAntall() {
        let rows = (1...40).map { member("Spiller \($0)") }
        #expect(TroppSections(rows).active.count == 40)
    }
}

struct TroppRulesTests {
    @Test func sisteArrangoerKanIkkeMisteRollen() {
        let me = member("Meg", organizer: true)
        let other = member("Annen")
        let rows = [me, other]
        #expect(TroppRules.isLastOrganizer(me, in: rows))
        #expect(TroppRules.availability(.revokeOrganizer, for: me, in: rows, me: other.id) == .blocked(TroppRules.lastOrganizerText))
        #expect(TroppRules.availability(.archive, for: me, in: rows, me: other.id) == .blocked(TroppRules.lastOrganizerText))
        #expect(TroppRules.availability(.releaseLogin, for: me, in: rows, me: other.id) == .blocked(TroppRules.lastOrganizerText))
    }

    @Test func arrangoerUtenInnloggingTellerIkke() {
        // Som i guard_club_members: bare aktive arrangører med innlogging teller.
        let a = member("A", organizer: true)
        let ledig = member("Ledig", user: false, organizer: true)
        let arkivert = member("Arkivert", status: .archived)
        #expect(TroppRules.isLastOrganizer(a, in: [a, ledig, arkivert]))
        #expect(!TroppRules.isLastOrganizer(ledig, in: [a, ledig]))
    }

    @Test func toArrangoererKanFjerneHverandre() {
        let a = member("A", organizer: true)
        let b = member("B", organizer: true)
        let rows = [a, b]
        #expect(TroppRules.availability(.revokeOrganizer, for: b, in: rows, me: a.id) == .allowed)
        #expect(TroppRules.availability(.archive, for: b, in: rows, me: a.id) == .allowed)
        #expect(TroppRules.availability(.releaseLogin, for: b, in: rows, me: a.id) == .allowed)
    }

    @Test func ikkeMedSegSelv() {
        let a = member("A", organizer: true)
        let b = member("B", organizer: true)
        let rows = [a, b]
        #expect(TroppRules.availability(.releaseLogin, for: a, in: rows, me: a.id) == .blocked(TroppRules.ownRowText))
        #expect(TroppRules.availability(.archive, for: a, in: rows, me: a.id) == .blocked(TroppRules.ownRowText))
        #expect(TroppRules.availability(.revokeOrganizer, for: a, in: rows, me: a.id) == .blocked(TroppRules.ownRowText))
        #expect(TroppRules.availability(.edit, for: a, in: rows, me: a.id) == .allowed)
    }

    @Test func ventende() {
        let me = member("Meg", organizer: true)
        let pending = member("Ny", status: .pending)
        let rows = [me, pending]
        for action in [TroppAction.approve, .reject, .edit, .setSeedGroup] {
            #expect(TroppRules.availability(action, for: pending, in: rows, me: me.id) == .allowed)
        }
        // Ventende må ha innlogging og kan ikke ha roller (constraints).
        for action in [TroppAction.releaseLogin, .grantOrganizer, .grantTreasurer, .archive, .delete, .restore] {
            #expect(TroppRules.availability(action, for: pending, in: rows, me: me.id) == .hidden)
        }
    }

    @Test func ledigNavn() {
        let me = member("Meg", organizer: true)
        let open = member("Ledig", user: false)
        let rows = [me, open]
        #expect(TroppRules.availability(.delete, for: open, in: rows, me: me.id) == .allowed)
        #expect(TroppRules.availability(.releaseLogin, for: open, in: rows, me: me.id) == .hidden)
        #expect(TroppRules.availability(.grantOrganizer, for: open, in: rows, me: me.id) == .blocked(TroppRules.needsLoginText))
        #expect(TroppRules.availability(.archive, for: open, in: rows, me: me.id) == .allowed)
    }

    @Test func innloggetKanIkkeSlettes() {
        let me = member("Meg", organizer: true)
        let player = member("Spiller")
        #expect(TroppRules.availability(.delete, for: player, in: [me, player], me: me.id) == .hidden)
        #expect(TroppRules.availability(.grantOrganizer, for: player, in: [me, player], me: me.id) == .allowed)
        #expect(TroppRules.availability(.revokeTreasurer, for: player, in: [me, player], me: me.id) == .hidden)
    }

    @Test func gjenopprettSperresNaarNavnetErTatt() {
        let me = member("Meg", organizer: true)
        let old = member("Ola", status: .archived)
        let new = member(" ola ")
        #expect(TroppRules.availability(.restore, for: old, in: [me, old], me: me.id) == .allowed)
        #expect(!TroppRules.availability(.restore, for: old, in: [me, old, new], me: me.id).isAllowed)
        #expect(TroppRules.availability(.archive, for: old, in: [me, old], me: me.id) == .hidden)
        #expect(TroppRules.availability(.setSeedGroup, for: old, in: [me, old], me: me.id) == .hidden)
    }
}

struct TroppInputTests {
    private let rows = [member("Ola"), member("Kari", status: .archived)]

    @Test func gyldig() throws {
        let value = try TroppInput.validate(name: "  Per ", handicap: "+2,3", rows: rows).get()
        #expect(value == TroppInputValue(name: "Per", handicapIndex: -2.3))
        #expect(try TroppInput.validate(name: "Per", handicap: "", rows: rows).get().handicapIndex == nil)
    }

    @Test func navnetErTatt() {
        #expect(TroppInput.validate(name: "OLA", handicap: "", rows: rows) == .failure(.invalid("Det navnet finnes allerede i troppen.")))
        // Arkiverte holder ikke på navnet (unik-indeksen gjelder status <> archived).
        #expect((try? TroppInput.validate(name: "Kari", handicap: "", rows: rows).get()) != nil)
        // Eget navn ved redigering er ikke en kollisjon.
        #expect((try? TroppInput.validate(name: "Ola", handicap: "12", rows: rows, editing: rows[0].id).get()) != nil)
    }

    @Test func ugyldig() {
        #expect((try? TroppInput.validate(name: "  ", handicap: "", rows: rows).get()) == nil)
        #expect((try? TroppInput.validate(name: String(repeating: "x", count: 41), handicap: "", rows: rows).get()) == nil)
        #expect((try? TroppInput.validate(name: "Per", handicap: "55", rows: rows).get()) == nil)
        #expect((try? TroppInput.validate(name: "Per", handicap: "-3", rows: rows).get()) == nil)
    }

    @Test(arguments: [
        (nil as Double?, ""),
        (18.4, "18,4"),
        (18, "18,0"),
        (-2.3, "+2,3"),
        (0, "0,0"),
    ])
    func handicapTekst(_ index: Double?, _ forventet: String) throws {
        #expect(TroppInput.handicapText(index) == forventet)
        // Teksten tolkes tilbake til samme tall.
        #expect(try ClubInput.handicapIndex(forventet).get() == index)
    }
}

struct TroppSeedingTests {
    @Test func golfgutuUtenAktivSesong() {
        #expect(TroppSeeding.groups(activeSeason: nil) == SeedingGroup.golfgutu)
    }

    @Test func gruppeneFraAktivSesong() {
        var rules = Ruleset.golfgutu
        rules.handicap.seedingGroups = [
            SeedingGroup(number: 2, handicap: 8, name: "B"),
            SeedingGroup(number: 1, handicap: 2, name: "A"),
            SeedingGroup(number: 12, handicap: 20, name: "Utenfor"),
        ]
        let season = SeasonRow(id: UUID(), clubID: club, name: "2027", status: .active, rules: rules)
        let groups = TroppSeeding.groups(activeSeason: season)
        // Sortert, og bare 1–9 (check i databasen).
        #expect(groups.map(\.name) == ["A", "B"])
        #expect(TroppSeeding.label(2, groups: groups) == "B (hcp 8)")
        #expect(TroppSeeding.label(nil, groups: groups) == "Ingen gruppe")
        #expect(TroppSeeding.label(3, groups: groups) == "Gruppe 3 (finnes ikke i regelsettet)")
    }

    @Test func tomListeGirIngenGrupper() {
        var rules = Ruleset.golfgutu
        rules.handicap.seedingGroups = []
        let season = SeasonRow(id: UUID(), clubID: club, name: "Uten seeding", status: .active, rules: rules)
        #expect(TroppSeeding.groups(activeSeason: season).isEmpty)
    }
}

struct MemberPatchTests {
    private func json(_ patch: MemberPatch) throws -> [String: Any] {
        let data = try JSONEncoder().encode(patch)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func arkiverTarAvRollene() throws {
        let body = try json(.archive)
        #expect(body["status"] as? String == "archived")
        #expect(body["is_organizer"] as? Bool == false)
        #expect(body["is_treasurer"] as? Bool == false)
        #expect(body.count == 3)
    }

    @Test func frigjoerSenderNull() throws {
        let body = try json(.releaseLogin)
        #expect(body.keys.sorted() == ["user_id"])
        #expect(body["user_id"] is NSNull)
    }

    @Test func avvisArkivererOgFrigjoer() throws {
        let body = try json(.reject)
        #expect(body["status"] as? String == "archived")
        #expect(body["user_id"] is NSNull)
    }

    @Test func ingenGruppeSenderNull() throws {
        #expect(try json(.seed(nil))["seed_group"] is NSNull)
        #expect(try json(.seed(2))["seed_group"] as? Int == 2)
    }

    @Test func detaljerUtenHandicapSenderNull() throws {
        let body = try json(.details(TroppInputValue(name: "Per", handicapIndex: nil)))
        #expect(body["display_name"] as? String == "Per")
        #expect(body["handicap_index"] is NSNull)
        #expect(body.count == 2)
    }

    @Test func nyttNavnErLedigOgAktivt() throws {
        let data = try JSONEncoder().encode(NewMember(clubID: club, displayName: "Per", handicapIndex: 12.5))
        let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(body["status"] as? String == "active")
        #expect(body["user_id"] == nil)
        #expect(body["handicap_index"] as? Double == 12.5)
    }
}

struct TroppErrorTests {
    @Test func oversetter() {
        #expect(TroppError.from(sqlState: "42501", message: "Klubben må ha minst én arrangør") == .lastOrganizer)
        #expect(TroppError.from(sqlState: "42501", message: "Bare en arrangør kan endre roller") == .other(.notAllowed))
        #expect(TroppError.from(sqlState: "23505", message: "duplicate key") == .duplicateName)
        #expect(TroppError.from(sqlState: "23503", message: "violates foreign key") == .inUse)
        #expect(TroppError.from(sqlState: "PGRST116", message: "0 rows") == .notSaved)
    }
}

struct TroppDisplayTests {
    @Test func linjaUnderNavnet() {
        let row = member("Ola", user: false, organizer: true, seed: 2, handicap: -1.5)
        #expect(TroppDisplay.details(for: row, groups: SeedingGroup.golfgutu) == "Hcp +1,5 · Gruppe 2 · Arrangør · Har ikke logget inn")
        #expect(TroppDisplay.details(for: member("Kari"), groups: []) == "")
    }
}
