import Foundation
import Testing
@testable import DashDash18

struct ClubInputTests {
    @Test(arguments: [
        ("a1b2c3d4e5", "A1B2C3D4E5"),
        (" A1B2 C3D4-E5 ", "A1B2C3D4E5"),
        ("ABC123", "ABC123"),
    ])
    func gyldigKode(_ input: String, _ forventet: String) {
        #expect(ClubInput.normalizedJoinCode(input) == forventet)
    }

    @Test(arguments: ["", "ABC12", "ÆØÅ123", "ABC!23", String(repeating: "A", count: 17)])
    func ugyldigKode(_ input: String) {
        #expect(ClubInput.normalizedJoinCode(input) == nil)
    }

    @Test func navn() {
        #expect(ClubInput.normalizedName("  Thomas  ") == "Thomas")
        #expect(ClubInput.normalizedName("   ") == nil)
        #expect(ClubInput.normalizedName(String(repeating: "x", count: 41)) == nil)
        #expect(ClubInput.normalizedName(String(repeating: "x", count: 60), maxLength: 60) != nil)
    }

    @Test(arguments: [
        ("", nil as Double?),
        ("18,4", 18.4),
        ("18.4", 18.4),
        (" 54 ", 54.0),
        ("0", 0.0),
        ("+2", -2.0),
        ("+2,3", -2.3),
        ("12,34", 12.3),
        ("12, 4", 12.4),
        ("+ 2,3", -2.3),
        ("\u{00A0}7,0\u{00A0}", 7.0),
        ("12,", 12.0),
        (",5", 0.5),
        ("+0", 0.0),
    ])
    func gyldigHandicap(_ input: String, _ forventet: Double?) throws {
        #expect(try ClubInput.handicapIndex(input).get() == forventet)
    }

    @Test(arguments: ["abc", "54,1", "+10,1", "-3", "\u{2212}3", "1e1", "0x1A", "12,4,1", "+", ",", "inf", "nan", "++2"])
    func ugyldigHandicap(_ input: String) {
        // «-3» er ugyldig fordi plusshandicap skrives med «+», ikke minus.
        if case .success = ClubInput.handicapIndex(input) {
            Issue.record("\(input) skulle vært avvist")
        }
    }
}

struct ClubErrorTests {
    @Test func sqlStateTilNorsk() {
        #expect(ClubError.from(sqlState: "P0002", message: "") == .notFound)
        #expect(ClubError.from(sqlState: "55000", message: "") == .nameTaken)
        #expect(ClubError.from(sqlState: "23505", message: "") == .duplicateName)
        #expect(ClubError.from(sqlState: "22023", message: "Skriv inn et navn") == .invalidInput("Skriv inn et navn"))
        #expect(ClubError.from(sqlState: "42501", message: "") == .notAllowed)
        #expect(ClubError.from(sqlState: nil, message: "x") == .unknown("x"))
    }
}

struct MembershipTests {
    private func medlem(_ klubb: UUID, _ status: MemberStatus) -> Membership {
        Membership(id: UUID(), clubID: klubb, displayName: "T", status: status,
                   isOrganizer: false, isTreasurer: false, club: .init(name: "K", joinCode: nil))
    }

    @Test func velgerHusketAktivKlubb() {
        let a = UUID(), b = UUID()
        let valgt = Membership.choose(from: [medlem(a, .active), medlem(b, .active)], remembered: b)
        #expect(valgt?.clubID == b)
    }

    @Test func fallerTilbakeTilForsteAktive() {
        let a = UUID(), b = UUID()
        let valgt = Membership.choose(from: [medlem(a, .pending), medlem(b, .active)], remembered: a)
        #expect(valgt?.clubID == b)
    }

    @Test func venterHvisIngenAktive() {
        let a = UUID()
        #expect(Membership.choose(from: [medlem(a, .archived), medlem(a, .pending)], remembered: nil)?.status == .pending)
        #expect(Membership.choose(from: [medlem(a, .archived)], remembered: nil) == nil)
        #expect(Membership.choose(from: [], remembered: nil) == nil)
    }

    @Test func dekoderRadFraSupabase() throws {
        let json = """
        {"id":"7d6c8a51-2f0e-4a5b-9a1c-0d2b3c4e5f60","club_id":"1b2c3d4e-5f60-4718-8a9b-0c1d2e3f4a5b",
         "display_name":"Thomas","status":"active","is_organizer":true,"is_treasurer":false,
         "clubs":{"name":"Golfgutu Invitational","join_code":"A1B2C3D4E5"}}
        """
        let m = try JSONDecoder().decode(Membership.self, from: Data(json.utf8))
        #expect(m.displayName == "Thomas")
        #expect(m.club.joinCode == "A1B2C3D4E5")
        #expect(m.roleText == "Arrangør")
    }

    @Test func dekoderForhandsvisning() throws {
        let json = """
        {"club_id":"1b2c3d4e-5f60-4718-8a9b-0c1d2e3f4a5b","name":"Golfgutu","my_status":null,
         "open_members":[{"id":"7d6c8a51-2f0e-4a5b-9a1c-0d2b3c4e5f60","display_name":"Per"}]}
        """
        let p = try JSONDecoder().decode(ClubPreview.self, from: Data(json.utf8))
        #expect(p.openMembers.map(\.displayName) == ["Per"])
        #expect(p.myStatus == nil)
    }
}
