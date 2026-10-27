import Foundation
import GolfgutuCore
import Supabase
import Testing
@testable import DashDash18

// Deltakerinvitasjonen (sql/060): arrangøren limer inn lista over deltakere i en klubbturnering og deler
// lenken, og den som åpner lenken, tar plassen sin (eller meldes på som ny). Ingen nettverk.

private enum P {
    static func id(_ n: Int) -> UUID { H.id(n) }
    static let club = id(6000)
    static let me = id(6001)
    static let organizer = CompetitionAccess(profileID: me, memberships: [
        .init(clubID: club, memberID: id(6002), isOrganizer: true, isActive: true),
    ])
    static let member = CompetitionAccess(profileID: me, memberships: [
        .init(clubID: club, memberID: id(6002), isOrganizer: false, isActive: true),
    ])
    static let participantRow = id(6003)
    static let participant = CompetitionAccess(profileID: me, memberships: [],
                                               participants: [.init(clubID: club, memberID: participantRow)])

    static func competition(_ kind: CompetitionKind = .league, club: UUID? = P.club, owner: UUID? = nil,
                            entry: CompetitionEntry = .listed, status: SeasonStatus = .active) -> CompetitionRow {
        CompetitionRow(id: id(6100), kind: kind, name: "Klubbmesterskapet", clubID: club, ownerID: owner, seasonID: nil,
                       status: status, entry: entry, rules: .golfgutu, startsOn: nil, endsOn: nil, isMain: false,
                       requiresPurchase: false, entitlementID: nil, signupOpen: true)
    }
}

/// Lista arrangøren limer inn: navn, handicap og NGF-nummer.
struct DeltakerImportTests {
    @Test(arguments: [
        ("Kari Nordmann", "Kari Nordmann", "", ""),
        ("Kari Nordmann 18,4", "Kari Nordmann", "18,4", ""),
        ("Kari Nordmann;18,4;12-3456", "Kari Nordmann", "18,4", "12-3456"),
        ("Kari Nordmann\t18,4\t1234567", "Kari Nordmann", "18,4", "1234567"),
        ("Kari Nordmann;;12-3456", "Kari Nordmann", "", "12-3456"),
        ("Kari Nordmann;12-3456", "Kari Nordmann", "", "12-3456"),
        ("Kari Nordmann\t\t12", "Kari Nordmann", "12", ""),
        ("Kari Nordmann;-2", "Kari Nordmann", "-2", ""),
    ])
    func delerNavnHandicapOgNGF(_ line: String, _ name: String, _ handicap: String, _ ngf: String) {
        let columns = TroppImport.columns(line)
        #expect(columns.name == name)
        #expect(columns.handicap == handicap)
        #expect(columns.ngf == ngf)
    }

    /// Troppens innliming er som før: NGF-kolonnen tas ikke med der.
    @Test func troppenErSomFor() {
        #expect(TroppImport.split("Kari Nordmann\t\t12") == ("Kari Nordmann", "12"))
        #expect(TroppImport.split("Kari Nordmann;18,4;12-3456") == ("Kari Nordmann", "18,4"))
    }

    @Test func lesesMedDobbeltOgPåmeldte() {
        let text = """
        Kari Nordmann;18,4;12-3456

        Ola Hansen 22
        kari nordmann
        Kari Nordmann;;99-9999
        Per Påmeldt
        Ola 70
        """
        let lines = ParticipantImport.parse(text, entered: ["Per påmeldt"])
        #expect(lines.map(\.name) == ["Kari Nordmann", "Ola Hansen", "kari nordmann", "Kari Nordmann", "Per Påmeldt", "Ola"])
        #expect(lines.map(\.problem) == [nil, nil, .repeated, nil, .exists,
                                         .invalid("Handicap må være mellom +10 og 54.")])
        #expect(lines[0].handicapIndex == 18.4)
        #expect(lines[0].ngfNumber == "12-3456")
        #expect(lines[1].ngfNumber == nil)
        #expect(ParticipantImport.valid(lines).count == 3)
        #expect(ParticipantImport.message(lines[2]) == "Står allerede i lista")
        #expect(ParticipantImport.message(lines[4]) == "Er påmeldt fra før")
    }

    /// Samme navn som et medlem er greit: deltakere kan hete det samme.
    @Test func sammeNavnSomMedlemErGreit() {
        let lines = ParticipantImport.parse("Anne", entered: [])
        #expect(lines.first?.problem == nil)
    }

    @Test func høystTrehundre() {
        let text = (1...350).map { "Spiller \($0)" }.joined(separator: "\n")
        #expect(ParticipantImport.parse(text, entered: []).count == ParticipantImport.maxLines)
        #expect(ParticipantImport.maxLines == 300)
    }

    @Test func sendesSomJSON() throws {
        let lines = ParticipantImport.parse("Kari Nordmann;+2,3;12-3456\nOla", entered: [])
        let data = try JSONEncoder().encode(ParticipantImport.entries(lines))
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        #expect(json.count == 2)
        #expect(json[0]["display_name"] as? String == "Kari Nordmann")
        #expect(json[0]["handicap_index"] as? Double == -2.3)
        #expect(json[0]["ngf_number"] as? String == "12-3456")
        #expect(json[1]["display_name"] as? String == "Ola")
        #expect(json[1]["handicap_index"] == nil)
        #expect(json[1]["ngf_number"] == nil)
    }

    @Test func barePåmeldingIKlubbturneringer() {
        #expect(ParticipantImport.canAdd(P.competition(), access: P.organizer))
        #expect(ParticipantImport.canAdd(P.competition(.cup), access: P.organizer))
        #expect(!ParticipantImport.canAdd(P.competition(), access: P.member))
        #expect(!ParticipantImport.canAdd(P.competition(), access: P.participant))
        #expect(!ParticipantImport.canAdd(P.competition(entry: .club), access: P.organizer))
        #expect(!ParticipantImport.canAdd(P.competition(status: .finished), access: P.organizer))
        #expect(!ParticipantImport.canAdd(P.competition(.season), access: P.organizer))
        #expect(!ParticipantImport.canAdd(P.competition(club: nil, owner: P.me), access: P.organizer))
    }

    @Test func antallLagtTil() {
        #expect(ParticipantImport.addedText(0) == "Ingen nye. Alle var påmeldt fra før.")
        #expect(ParticipantImport.addedText(1) == "1 lagt til")
        #expect(ParticipantImport.addedText(12) == "12 lagt til")
    }
}

/// «Inviter» i en klubbturnering: bare arrangøren deler lenken.
struct DeltakerLenkeTests {
    @Test func arrangørenDelerLenken() {
        let c = P.competition()
        #expect(P.organizer.canInvite(c, [], isDrawn: false))
        #expect(P.organizer.canInvite(P.competition(.cup), [], isDrawn: false))
        #expect(!P.organizer.canInvite(P.competition(.cup), [], isDrawn: true))
        #expect(!P.organizer.canInvite(P.competition(status: .finished), [], isDrawn: false))
        #expect(!P.organizer.canInvite(P.competition(entry: .club), [], isDrawn: false))
        #expect(!P.organizer.canInvite(P.competition(.season), [], isDrawn: false))
    }

    @Test func deltakereOgMedlemmerInvitererIkke() {
        let c = P.competition()
        let entered = [CompetitionParticipantRow(id: P.id(6200), competitionID: c.id, memberID: P.participantRow,
                                                 profileID: nil, status: .active)]
        #expect(!P.participant.canInvite(c, entered, isDrawn: false))
        let memberEntered = [CompetitionParticipantRow(id: P.id(6201), competitionID: c.id, memberID: P.id(6002),
                                                       profileID: nil, status: .active)]
        #expect(!P.member.canInvite(c, memberEntered, isDrawn: false))
    }

    @Test func klubbturneringensTekster() {
        let target = InviteTarget.competition(name: "Klubbmesterskapet", clubName: "Hauger GK")
        let code = InviteCode("ABCDEFGH23")!
        let text = target.shareText(code, universal: true)
        #expect(text.contains("Klubbmesterskapet"))
        #expect(text.contains("https://dashdash18.com/konkurranse/ABCDEFGH23"))
        #expect(target.help.contains("60 dager"))
        #expect(target.help.contains("ikke medlem"))
        // Private turneringer som før.
        #expect(InviteTarget.competition(name: "Vennecupen").help.contains("7 dager"))
    }
}

/// Den som åpner lenken: klubbnavnet, de ledige navnene og svaret.
struct DeltakerForhandsvisningTests {
    private func decode(_ json: String) throws -> CompetitionInvitePreview {
        try JSONDecoder().decode(CompetitionInvitePreview.self, from: Data(json.utf8))
    }

    @Test func klubbturneringMedLedigeNavn() throws {
        let preview = try decode("""
        {"competition_id": "\(P.id(6100).uuidString)", "name": "Klubbmesterskapet", "kind": "league",
         "owner_name": null, "entrants": 14, "entered": false, "club_name": "Hauger GK",
         "open_names": [{"member_id": "\(P.id(6300).uuidString)", "display_name": "Kari Nordmann"},
                        {"member_id": "\(P.id(6301).uuidString)", "display_name": "Åse Ås"}]}
        """)
        #expect(preview.clubName == "Hauger GK")
        #expect(preview.isClub)
        #expect(preview.openNames.map(\.displayName) == ["Kari Nordmann", "Åse Ås"])
        #expect(preview.openNames.first?.memberID == P.id(6300))
    }

    /// Svaret fra før 060 (og private turneringer): uten klubb og uten navn.
    @Test func privatUtenNavn() throws {
        let preview = try decode("""
        {"competition_id": "\(P.id(6100).uuidString)", "name": "Vennecupen", "kind": "cup",
         "owner_name": "Thomas", "entrants": 4, "entered": false}
        """)
        #expect(preview.clubName == nil)
        #expect(!preview.isClub)
        #expect(preview.openNames.isEmpty)
        let empty = try decode("""
        {"competition_id": "\(P.id(6100).uuidString)", "name": "Vennecupen", "kind": "cup",
         "owner_name": "Thomas", "entrants": 4, "entered": false, "club_name": null, "open_names": []}
        """)
        #expect(empty.openNames.isEmpty && !empty.isClub)
    }

    @Test func søkINavnene() {
        let names = [
            CompetitionInvitePreview.OpenName(memberID: P.id(1), displayName: "Kari Nordmann"),
            CompetitionInvitePreview.OpenName(memberID: P.id(2), displayName: "Åse Ås"),
            CompetitionInvitePreview.OpenName(memberID: P.id(3), displayName: "Ola Hansen"),
        ]
        #expect(OpenNameSearch.filter(names, query: "").count == 3)
        #expect(OpenNameSearch.filter(names, query: "  kari ").map(\.memberID) == [P.id(1)])
        #expect(OpenNameSearch.filter(names, query: "ås").map(\.memberID) == [P.id(2)])
        #expect(OpenNameSearch.filter(names, query: "ola han").map(\.memberID) == [P.id(3)])
        #expect(OpenNameSearch.filter(names, query: "zz").isEmpty)
        #expect(!OpenNameSearch.showsSearch(names))
        #expect(OpenNameSearch.showsSearch(Array(repeating: names[0], count: OpenNameSearch.searchFrom)))
    }

    @Test func navnetErTatt() throws {
        let json = """
        {"competition_id": "\(P.id(6100).uuidString)", "participant_id": "\(P.id(6400).uuidString)", "joined": "claimed"}
        """
        let result = try JSONDecoder().decode(CompetitionClaimResult.self, from: Data(json.utf8))
        #expect(result.joined == .claimed)
    }

    @Test func nyeFeilPåNorsk() {
        let taken = PostgrestError(code: "55000", message: "Navnet er tatt eller finnes ikke lenger")
        #expect(CompetitionInviteErrors.message(for: taken) == CompetitionInviteErrors.nameTakenMessage)
        #expect(CompetitionInviteErrors.isNameTaken(taken))
        let row = PostgrestError(code: "55000", message: "Du har allerede en rad i klubben. Spør arrangøren.")
        #expect(CompetitionInviteErrors.message(for: row) == CompetitionInviteErrors.existingRowMessage)
        #expect(!CompetitionInviteErrors.isNameTaken(row))
        // Andre 55000 som før.
        #expect(CompetitionInviteErrors.message(for: PostgrestError(code: "55000", message: "Turneringen er ferdig"))
                == "Turneringen er ferdig")
    }
}

/// Etter at du er med: en ny bruker uten klubb skal se turneringen, ikke valgskjermen.
@MainActor
struct DeltakerHjemTests {
    @Test func deltakerUtenValgFårVennemodus() {
        #expect(OpenAppGate.automaticChoice(club: .noClub, choice: nil, hasParticipations: true, openApp: true) == .friends)
    }

    @Test func ingentingNårDuHarValgtEllerHarKlubb() {
        #expect(OpenAppGate.automaticChoice(club: .noClub, choice: nil, hasParticipations: false, openApp: true) == nil)
        #expect(OpenAppGate.automaticChoice(club: .noClub, choice: .club, hasParticipations: true, openApp: true) == nil)
        #expect(OpenAppGate.automaticChoice(club: .noClub, choice: .friends, hasParticipations: true, openApp: true) == nil)
        #expect(OpenAppGate.automaticChoice(club: .active(.preview), choice: nil, hasParticipations: true, openApp: true) == nil)
        #expect(OpenAppGate.automaticChoice(club: .loading, choice: nil, hasParticipations: true, openApp: true) == nil)
        #expect(OpenAppGate.automaticChoice(club: .noClub, choice: nil, hasParticipations: true, openApp: false) == nil)
    }

    @Test func påmeldtMedLenkenTellerSomDeltaker() {
        #expect(OpenAppGate.automaticChoice(club: .noClub, choice: nil, hasParticipations: false, joinedByLink: true,
                                            openApp: true) == .friends)
    }
}
