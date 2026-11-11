import Foundation
import Testing
@testable import DashDash18

// «Finn fra kontakter» (sql/077): normalisering og sha256 likt med serveren, kodene som sendes,
// og delingen i «I Atten» og «Inviter til Atten».

private func id(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))! }

// Fasit fra terminalen: printf '%s' 'ola@example.com' | shasum -a 256
private let olaEmail = "4dc2395295507982ee5c81cd5b8b1daf50a570af0fa177bdf387d69d930609b4"
// printf '%s' '+4791234567' | shasum -a 256
private let olaPhone = "ffcbee1d17948bbad790c0b467ce90267dc1d9f9f4494f28451642fee49ff9a9"

struct KontakterHashTests {
    @Test func epostSomServeren() {
        #expect(ContactHashing.emailHash("ola@example.com") == olaEmail)
        // Mellomrom og store bokstaver: samme kode (lower(btrim(email))).
        #expect(ContactHashing.emailHash("  Ola@Example.COM\n") == olaEmail)
        #expect(ContactHashing.emailHash("   ") == nil)
    }

    @Test func nummerSomServeren() {
        for raw in ["+4791234567", "+47 912 34 567", "91234567", "912 34 567", "0047 91234567", "(+47) 912-34-567"] {
            #expect(ContactHashing.phoneHash(raw) == olaPhone, "\(raw)")
        }
    }

    @Test func e164() {
        #expect(ContactHashing.e164("+46 70 123 45 67") == "+46701234567")
        #expect(ContactHashing.e164("001 555 123 4567") == "+15551234567")
        // Sju sifre etter + er nok, femten er mest.
        #expect(ContactHashing.e164("+1234567") == "+1234567")
        #expect(ContactHashing.e164("+123456789012345") == "+123456789012345")
        #expect(ContactHashing.e164("+1234567890123456") == nil)
        #expect(ContactHashing.e164("+123456") == nil)
        // Uten landskode og ikke 8 sifre, eller landskode som starter på 0: droppes.
        #expect(ContactHashing.e164("1234567") == nil)
        #expect(ContactHashing.e164("123456789") == nil)
        #expect(ContactHashing.e164("+0123456789") == nil)
        #expect(ContactHashing.e164("12+34567890") == nil)
        #expect(ContactHashing.e164("") == nil)
    }
}

struct KontakterOppslagTests {
    private let ola = PhoneContact(id: "a", name: "Ola Nordmann", emails: ["ola@example.com", "OLA@example.com "],
                                   phones: ["912 34 567", "+4791234567", "123"])
    private let kari = PhoneContact(id: "b", name: "Kari", phones: ["91234567"])

    @Test func likeKoderSendesEnGang() {
        let lookup = ContactLookup([ola, kari])
        #expect(lookup.emailHashes == [olaEmail])
        #expect(lookup.phoneHashes == [olaPhone])
        // Samme nummer hos to kontakter: begge navnene er koblet til koden.
        #expect(lookup.contactsByHash[olaPhone] == ["a", "b"])
        #expect(lookup.contactsByHash[olaEmail] == ["a"])
    }

    @Test func kuttesVedGrensen() {
        let contacts = (0..<10).map { n in PhoneContact(id: "\(n)", name: "K\(n)", emails: ["k\(n)@x.no", "k\(n)@y.no"]) }
        let lookup = ContactLookup(contacts, limit: 5)
        // Hele kontakter: to og to koder, så fire.
        #expect(lookup.count == 4)
        #expect(lookup.contactsByHash.values.flatMap { $0 }.allSatisfy { ["0", "1"].contains($0) })
        #expect(ContactLookup(contacts).count == 20)
    }

    @Test func nummerTilMeldinger() {
        #expect(ola.messagePhone == "+4791234567")
        #expect(PhoneContact(id: "c", name: "C", phones: ["123"]).messagePhone == "123")
        #expect(PhoneContact(id: "d", name: "D").messagePhone == nil)
    }
}

struct KontakterResultatTests {
    private let contacts = [
        PhoneContact(id: "a", name: "Ola Nordmann", emails: ["ola@example.com"]),
        PhoneContact(id: "b", name: "Åse", phones: ["40000000"]),
        PhoneContact(id: "c", name: "Ærlig Eriksen"),
        PhoneContact(id: "d", name: "Zorro"),
        PhoneContact(id: "e", name: "", phones: ["41111111"]),
        PhoneContact(id: "f", name: "Kari", phones: ["91234567"]),
    ]

    @Test func iAttenOgInviter() throws {
        let lookup = ContactLookup(contacts)
        let rows = [
            ContactMatchRow(id: id(1), displayName: "Olamann", clubName: "Golfgutu", followsMe: true,
                            matched: [olaEmail]),
            ContactMatchRow(id: id(2), displayName: "kari", myStatus: .pending, matched: [olaPhone]),
        ]
        let results = ContactResults(rows: rows, contacts: contacts, lookup: lookup)
        #expect(results.inAtten.map(\.id) == [id(2), id(1)])
        #expect(results.inAtten[1].contactName == "Ola Nordmann")
        #expect(results.inAtten[1].subtitle == "Ola Nordmann i kontaktene · Golfgutu · Følger deg")
        // Samme navn som i Atten: ingen «i kontaktene».
        #expect(results.inAtten[0].contactName == nil)
        #expect(results.inAtten[0].subtitle == nil)
        // De andre, med navn, i norsk rekkefølge (Z, Æ, Ø, Å).
        #expect(results.invite.map(\.id) == ["d", "c", "b"])
    }

    @Test func ingenTreff() {
        let results = ContactResults(rows: [], contacts: contacts, lookup: ContactLookup(contacts))
        #expect(results.inAtten.isEmpty)
        #expect(results.invite.count == 5)
    }

    @Test func sokIInviterLista() {
        let results = ContactResults(rows: [], contacts: contacts, lookup: ContactLookup(contacts))
        #expect(results.invite(matching: "erik").map(\.id) == ["c"])
        #expect(results.invite(matching: "  ").count == 5)
        #expect(results.invite(matching: "xyz").isEmpty)
    }

    @Test func radFraServeren() throws {
        let json = """
        [{"id": "00000000-0000-0000-0000-000000000001", "display_name": "Ola", "avatar_path": null,
          "club_name": "Golfgutu", "my_status": "accepted", "follows_me": false, "matched": ["\(olaEmail)"]},
         {"id": "00000000-0000-0000-0000-000000000002", "display_name": null, "my_status": "rart"}]
        """
        let rows = try JSONDecoder().decode([ContactMatchRow].self, from: Data(json.utf8))
        #expect(rows[0] == ContactMatchRow(id: id(1), displayName: "Ola", clubName: "Golfgutu",
                                           myStatus: .accepted, matched: [olaEmail]))
        #expect(rows[1].displayName == "Spiller")
        #expect(rows[1].myStatus == .none)
        #expect(rows[1].matched.isEmpty)
    }
}

struct KontakterTekstTests {
    @Test func invitasjonen() throws {
        let link = try #require(FollowLink(code: "ABCD2345"))
        #expect(ContactInvite.message(link: link.url) == "Bli med meg på Atten! Følg meg her: \(link.url.absoluteString)")
        #expect(link.url.absoluteString == "https://dashdash18.com/folg/ABCD2345")
        #expect(ContactInvite.message(link: nil) == "Bli med meg på Atten!")
    }

    @Test func feilkodene() {
        #expect(ContactsError.findMessage(.invalid("x"), code: "54000") == "Prøv igjen om litt.")
        #expect(ContactsError.findMessage(.invalid("x"), code: "22023") == "For mange kontakter.")
        #expect(ContactsError.findMessage(.offline, code: nil) == DataError.offline.message)
        #expect(ContactsError.phoneMessage(.invalid("x"), code: "22023") == "Ugyldig telefonnummer.")
        #expect(ContactsError.phoneMessage(.offline, code: nil) == DataError.offline.message)
    }
}
