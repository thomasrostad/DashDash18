import Foundation
import Testing
@testable import DashDash18

private let memberID = UUID(uuidString: "11111111-0000-0000-0000-000000000002")!
private let clubID = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001")!

private func row(
    id: UUID = memberID,
    name: String = "Anders",
    handicap: Double? = 18.4
) -> ClubMemberRow {
    ClubMemberRow(
        id: id, clubID: clubID, userID: UUID(), displayName: name, handicapIndex: handicap,
        seedGroup: 2, isOrganizer: false, isTreasurer: false, status: .active, avatarPath: nil
    )
}

struct DegProfileDraftTests {
    @Test(arguments: [
        (18.4 as Double?, "18,4"),
        (-2.3, "+2,3"),
        (54.0, "54,0"),
        (nil, ""),
    ])
    func skjemaetFyllesFraRaden(_ handicap: Double?, _ text: String) {
        let draft = DegProfileDraft(row: row(handicap: handicap))
        #expect(draft.name == "Anders")
        #expect(draft.handicap == text)
    }

    @Test func gyldigSkjemaTrimmesOgTolkes() throws {
        let change = try DegProfileDraft(name: "  Anders B  ", handicap: "17.9").validate().get()
        #expect(change == DegProfileChange(name: "Anders B", handicapIndex: 17.9))
    }

    @Test func tomtHandicapErIkkeOppgitt() throws {
        let change = try DegProfileDraft(name: "Anders", handicap: " ").validate().get()
        #expect(change.handicapIndex == nil)
    }

    @Test func plusshandicapLagresNegativt() throws {
        let change = try DegProfileDraft(name: "Anders", handicap: "+1,5").validate().get()
        #expect(change.handicapIndex == -1.5)
    }

    @Test(arguments: [
        ("", "18,4"),
        ("   ", "18,4"),
        (String(repeating: "x", count: 41), "18,4"),
        ("Anders", "abc"),
        ("Anders", "54,1"),
        ("Anders", "-3"),
    ])
    func ugyldigSkjemaAvvises(_ name: String, _ handicap: String) {
        guard case .failure(.invalid(let message)) = DegProfileDraft(name: name, handicap: handicap).validate() else {
            Issue.record("«\(name)» / «\(handicap)» skulle vært avvist")
            return
        }
        #expect(!message.isEmpty)
    }

    @Test func uendretSkjemaHarIngenEndring() {
        let original = row()
        #expect(!DegProfileDraft(row: original).hasChanges(from: original))
        // Punktum og komma er samme verdi.
        #expect(!DegProfileDraft(name: "Anders", handicap: "18.4").hasChanges(from: original))
        #expect(!DegProfileDraft(name: " Anders ", handicap: "18,4").hasChanges(from: original))
    }

    @Test func endringerOppdages() {
        let original = row()
        #expect(DegProfileDraft(name: "Anders B", handicap: "18,4").hasChanges(from: original))
        #expect(DegProfileDraft(name: "Anders", handicap: "18,3").hasChanges(from: original))
        #expect(DegProfileDraft(name: "Anders", handicap: "").hasChanges(from: original))
        #expect(DegProfileDraft(name: "Anders", handicap: "abc").hasChanges(from: original))
        #expect(DegProfileDraft(name: "Anders", handicap: "12").hasChanges(from: row(handicap: nil)))
    }
}

struct DegProfilePatchTests {
    private func json(_ change: DegProfileChange) throws -> [String: Any] {
        let data = try JSONEncoder().encode(change.patch)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func senderBareNavnOgHandicap() throws {
        let object = try json(DegProfileChange(name: "Anders", handicapIndex: 18.4))
        #expect(Set(object.keys) == ["display_name", "handicap_index"])
        #expect(object["display_name"] as? String == "Anders")
        #expect(object["handicap_index"] as? Double == 18.4)
    }

    /// Kolonnevakten (`guard_club_members`) stopper rolle, seeding, status og
    /// innloggingskobling på egen rad. Det vi sender, må være lov for en spiller.
    @Test func senderIngenKolonnerKolonnevaktenStopper() throws {
        let object = try json(DegProfileChange(name: "Anders", handicapIndex: nil))
        #expect(Set(object.keys).isSubset(of: DegProfile.ownWritableColumns))
        for guarded in ["is_organizer", "is_treasurer", "seed_group", "status", "user_id", "club_id"] {
            #expect(object[guarded] == nil)
        }
    }

    @Test func tomtHandicapSendesSomNull() throws {
        let object = try json(DegProfileChange(name: "Anders", handicapIndex: nil))
        #expect(object["handicap_index"] is NSNull)
    }
}

struct DegProfileVerifyTests {
    private let change = DegProfileChange(name: "Anders B", handicapIndex: 17.9)

    @Test func lagretRadGodtas() throws {
        let saved = row(name: "Anders B", handicap: 17.9)
        let result = try DegProfile.verify(returned: [saved], memberID: memberID, change: change).get()
        #expect(result == saved)
    }

    @Test func ingenRadTilbakeBetyrIkkeLagret() {
        // RLS stoppet oppdateringen: PostgREST gir null rader, ikke en feil.
        #expect(DegProfile.verify(returned: [], memberID: memberID, change: change) == .failure(.notSaved))
    }

    @Test func feilRadEllerFlereRaderBetyrIkkeLagret() {
        let other = row(id: UUID(), name: "Anders B", handicap: 17.9)
        #expect(DegProfile.verify(returned: [other], memberID: memberID, change: change) == .failure(.notSaved))
        let saved = row(name: "Anders B", handicap: 17.9)
        #expect(DegProfile.verify(returned: [saved, saved], memberID: memberID, change: change) == .failure(.notSaved))
    }

    @Test func annenVerdiTilbakeOppdages() {
        let stale = row(name: "Anders", handicap: 17.9)
        #expect(DegProfile.verify(returned: [stale], memberID: memberID, change: change) == .failure(.mismatch))
        let cleared = row(name: "Anders B", handicap: nil)
        #expect(DegProfile.verify(returned: [cleared], memberID: memberID, change: change) == .failure(.mismatch))
    }

    @Test func handicapMedSammeDesimalGodtas() {
        let saved = row(name: "Anders B", handicap: 17.900000001)
        #expect((try? DegProfile.verify(returned: [saved], memberID: memberID, change: change).get()) != nil)
    }
}

struct DegProfileErrorTests {
    @Test func sqlStateTilNorsk() {
        #expect(DegProfileError.from(sqlState: "23505", message: "") == .duplicateName)
        #expect(DegProfileError.from(sqlState: "23514", message: "x") == .invalid("Verdien er ikke gyldig."))
        #expect(DegProfileError.from(sqlState: "42501", message: "Bare en arrangør kan endre roller") == .other(.notAllowed))
        #expect(DegProfileError.from(sqlState: nil, message: "x") == .other(.unknown("x")))
    }

    @Test func meldingeneErNorske() {
        #expect(DegProfileError.duplicateName.message == "Det navnet finnes allerede i troppen.")
        #expect(DegProfileError.notSaved.message.contains("ikke lagret"))
    }
}
