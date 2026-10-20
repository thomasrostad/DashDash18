import Foundation
import Testing
@testable import DashDash18

private let userID = UUID(uuidString: "22222222-0000-0000-0000-000000000001")!

private func profile(
    name: String? = "Anders",
    handicap: Double? = 18.4,
    ngf: String? = nil
) -> OwnProfileRow {
    OwnProfileRow(id: userID, displayName: name, handicapIndex: handicap, ngfNumber: ngf)
}

struct NGFNumberTests {
    @Test(arguments: [
        ("", nil as String?),
        ("   ", nil),
        ("12345", "12345"),
        (" 12345 ", "12345"),
        ("123 456", "123456"),
        ("1-2", "1-2"),
        ("123456789012", "123456789012"),
        ("123456789012-123456789012", "123456789012-123456789012"),
    ])
    func gyldigeNumre(_ raw: String, _ expected: String?) throws {
        #expect(try NGFNumber.normalized(raw).get() == expected)
    }

    @Test(arguments: [
        "abc",
        "12a",
        "-12",
        "12-",
        "1--2",
        "1-2-3",
        "1234567890123",
        "1-1234567890123",
        "١٢٣", // arabiske sifre, som databasen ikke godtar
        "+47",
    ])
    func ugyldigeNumreAvvises(_ raw: String) {
        guard case .failure(.invalid(let message)) = NGFNumber.normalized(raw) else {
            Issue.record("«\(raw)» skulle vært avvist")
            return
        }
        #expect(!message.isEmpty)
    }
}

struct OwnProfileDraftTests {
    @Test func skjemaetFyllesFraProfilen() {
        let draft = OwnProfileDraft(row: profile(handicap: -2.3, ngf: "12345"))
        #expect(draft.name == "Anders")
        #expect(draft.handicap == "+2,3")
        #expect(draft.ngf == "12345")
    }

    @Test func tomProfilGirTomtSkjema() {
        let draft = OwnProfileDraft(row: profile(name: nil, handicap: nil))
        #expect(draft == OwnProfileDraft(name: "", handicap: "", ngf: ""))
    }

    @Test func gyldigSkjemaTrimmesOgTolkes() throws {
        let change = try OwnProfileDraft(name: "  Anders B ", handicap: "17.9", ngf: " 98765 ").validate().get()
        #expect(change == OwnProfileChange(nameAndHandicap: .init(name: "Anders B", handicapIndex: 17.9), ngfNumber: "98765"))
    }

    @Test func tomtHandicapOgNGFErIkkeOppgitt() throws {
        let change = try OwnProfileDraft(name: "Anders", handicap: "", ngf: "").validate().get()
        #expect(change.nameAndHandicap?.handicapIndex == nil)
        #expect(change.ngfNumber == nil)
    }

    @Test(arguments: [
        ("", "18,4", ""),
        (String(repeating: "x", count: 41), "", ""),
        ("Anders", "abc", ""),
        ("Anders", "-3", ""),
        ("Anders", "18,4", "12a"),
    ])
    func ugyldigSkjemaAvvises(_ name: String, _ handicap: String, _ ngf: String) {
        guard case .failure(.invalid) = OwnProfileDraft(name: name, handicap: handicap, ngf: ngf).validate() else {
            Issue.record("«\(name)» / «\(handicap)» / «\(ngf)» skulle vært avvist")
            return
        }
    }

    @Test func bareNGFIgnorererNavnOgHandicap() throws {
        // Med klubb står navnet i medlemskapet: skjemaet sender bare NGF-nummeret.
        let draft = OwnProfileDraft(name: "", handicap: "abc", ngf: "555", scope: .ngfOnly)
        let change = try draft.validate().get()
        #expect(change == OwnProfileChange(nameAndHandicap: nil, ngfNumber: "555"))
    }

    @Test func uendretSkjemaHarIngenEndring() {
        let original = profile(ngf: "12345")
        #expect(!OwnProfileDraft(row: original).hasChanges(from: original))
        #expect(!OwnProfileDraft(name: " Anders ", handicap: "18.4", ngf: "123 45").hasChanges(from: original))
    }

    @Test func endringerOppdages() {
        let original = profile()
        #expect(OwnProfileDraft(name: "Anders B", handicap: "18,4", ngf: "").hasChanges(from: original))
        #expect(OwnProfileDraft(name: "Anders", handicap: "", ngf: "").hasChanges(from: original))
        #expect(OwnProfileDraft(name: "Anders", handicap: "18,4", ngf: "1").hasChanges(from: original))
        #expect(OwnProfileDraft(name: "Anders", handicap: "18,4", ngf: "x").hasChanges(from: original))
        #expect(OwnProfileDraft(name: "Anders", handicap: "", ngf: "").hasChanges(from: profile(name: nil, handicap: nil)))
    }

    @Test func bareNGFSerBortFraNavnetVedSammenligning() {
        let original = profile(name: nil, handicap: nil, ngf: "1")
        let same = OwnProfileDraft(row: original, scope: .ngfOnly)
        #expect(!same.hasChanges(from: original))
        var changed = same
        changed.ngf = ""
        #expect(changed.hasChanges(from: original))
    }
}

struct OwnProfilePatchTests {
    private func json(_ change: OwnProfileChange) throws -> [String: Any] {
        let data = try JSONEncoder().encode(change.patch)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func heleSkjemaetSenderTreKolonner() throws {
        let object = try json(OwnProfileChange(nameAndHandicap: .init(name: "Anders", handicapIndex: nil), ngfNumber: nil))
        #expect(Set(object.keys) == ["display_name", "handicap_index", "ngf_number"])
        #expect(object["display_name"] as? String == "Anders")
        #expect(object["handicap_index"] is NSNull)
        #expect(object["ngf_number"] is NSNull)
    }

    @Test func bareNGFSenderBareNGF() throws {
        let object = try json(OwnProfileChange(nameAndHandicap: nil, ngfNumber: "42"))
        #expect(Set(object.keys) == ["ngf_number"])
        #expect(object["ngf_number"] as? String == "42")
    }
}

struct OwnProfileVerifyTests {
    private let change = OwnProfileChange(nameAndHandicap: .init(name: "Anders", handicapIndex: 18.4), ngfNumber: "1")

    @Test func riktigRadGodtas() throws {
        let saved = try OwnProfile.verify(returned: [profile(ngf: "1")], userID: userID, change: change).get()
        #expect(saved.displayName == "Anders")
    }

    @Test func ingenRadErIkkeLagret() {
        #expect(OwnProfile.verify(returned: [], userID: userID, change: change) == .failure(.notSaved))
    }

    @Test func annenVerdiErAvvik() {
        #expect(OwnProfile.verify(returned: [profile(ngf: "2")], userID: userID, change: change) == .failure(.mismatch))
        #expect(OwnProfile.verify(returned: [profile(name: "Bjørn", ngf: "1")], userID: userID, change: change) == .failure(.mismatch))
    }

    @Test func bareNGFSjekkerBareNGF() {
        let ngfOnly = OwnProfileChange(nameAndHandicap: nil, ngfNumber: nil)
        #expect((try? OwnProfile.verify(returned: [profile(name: nil)], userID: userID, change: ngfOnly).get()) != nil)
    }

    @Test func unikNGFGirEgenMelding() {
        let error = OwnProfileError.from(sqlState: "23505", message: "duplicate key")
        #expect(error == .ngfTaken)
        #expect(error.message == "Det NGF-nummeret er registrert på en annen bruker.")
    }
}

struct AppleNameTests {
    private func components(_ given: String?, _ family: String?) -> PersonNameComponents {
        var name = PersonNameComponents()
        name.givenName = given
        name.familyName = family
        return name
    }

    @Test func fulltNavnSettesSammen() {
        #expect(AppleName.displayName(from: components("Kari", "Nordmann")) == "Kari Nordmann")
        #expect(AppleName.displayName(from: components(" Kari ", nil)) == "Kari")
        #expect(AppleName.displayName(from: components(nil, "Nordmann")) == "Nordmann")
    }

    @Test func ingentingFraAppleGirIngenNavn() {
        #expect(AppleName.displayName(from: nil) == nil)
        #expect(AppleName.displayName(from: components(nil, nil)) == nil)
        #expect(AppleName.displayName(from: components("  ", "")) == nil)
    }

    @Test func forLangtNavnFallerTilbakePaFornavnet() {
        let long = String(repeating: "x", count: 40)
        #expect(AppleName.displayName(from: components("Kari", long)) == "Kari")
        #expect(AppleName.displayName(from: components(long + "y", nil)) == nil)
    }

    @Test(arguments: [
        (nil as String?, "Kari Nordmann" as String?),
        ("", "Kari Nordmann"),
        ("   ", "Kari Nordmann"),
        ("Kari", nil),
        ("Spiller", nil),
    ])
    func appleNavnetLagresBareNarProfilenManglerNavn(_ existing: String?, _ expected: String?) {
        #expect(AppleName.nameToSave(apple: "Kari Nordmann", existing: existing) == expected)
    }

    @Test func utenAppleNavnLagresIngenting() {
        #expect(AppleName.nameToSave(apple: nil, existing: nil) == nil)
    }
}

struct OwnProfileNudgeTests {
    @Test func oppfordringNarNavnetMangler() {
        #expect(OwnProfile.needsName(nil))
        #expect(OwnProfile.needsName(""))
        #expect(OwnProfile.needsName("  "))
        #expect(!OwnProfile.needsName("Kari"))
    }
}
