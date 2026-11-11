import CryptoKit
import Foundation
import GolfgutuCore

// «Finn fra kontakter» (sql/077, docs/folge.md). Ren logikk uten nettverk og SwiftUI: e-post og
// nummer gjøres om til sha256 på telefonen (likt med serveren), koblingen mellom kodene og navnene
// i kontaktene, og hvem som havner under «I Atten» og «Inviter til Atten».

/// Én kontakt fra telefonen, slik appen trenger den. Lagres ikke.
nonisolated struct PhoneContact: Equatable, Identifiable, Sendable {
    /// `CNContact.identifier`.
    let id: String
    let name: String
    var emails: [String] = []
    var phones: [String] = []

    /// Nummeret Meldinger får: det første som kan leses som E.164, ellers det første som står.
    var messagePhone: String? {
        phones.lazy.compactMap(ContactHashing.e164).first ?? phones.first { !$0.isEmpty }
    }
}

/// Normalisering og sha256 slik `find_contacts` og `set_my_phone` (sql/077) gjør det.
nonisolated enum ContactHashing {
    /// Høyst så mange koder per oppslag (`find_contacts`, 22023).
    static let limit = 3000

    /// E-posten uten mellomrom og med små bokstaver, eller nil når den er tom.
    static func normalizedEmail(_ raw: String) -> String? {
        let email = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return email.isEmpty ? nil : email
    }

    /// Nummeret som E.164 (`+4791234567`): bare sifre og «+», «00» blir «+», 8 sifre blir norsk (+47).
    /// nil når det ikke blir et gyldig nummer.
    static func e164(_ raw: String) -> String? {
        var number = raw.filter { "0123456789+".contains($0) }
        if number.hasPrefix("00") {
            number = "+" + number.dropFirst(2)
        } else if number.count == 8, number.allSatisfy(isASCIIDigit) {
            number = "+47" + number
        }
        // ^\+[1-9][0-9]{6,14}$
        let digits = number.dropFirst()
        guard number.first == "+", (7...15).contains(digits.count), digits.allSatisfy(isASCIIDigit),
              digits.first != "0" else { return nil }
        return number
    }

    private static func isASCIIDigit(_ c: Character) -> Bool { c.isASCII && c.isNumber }

    static func emailHash(_ raw: String) -> String? {
        normalizedEmail(raw).map(sha256)
    }

    static func phoneHash(_ raw: String) -> String? {
        e164(raw).map(sha256)
    }

    /// sha256 av teksten (UTF-8) som hex med små bokstaver.
    static func sha256(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// Kodene som sendes til `find_contacts`, og hvilke kontakter hver kode kom fra.
nonisolated struct ContactLookup: Equatable, Sendable {
    private(set) var emailHashes: [String] = []
    private(set) var phoneHashes: [String] = []
    /// Kode → kontaktene (id) med den e-posten eller det nummeret.
    private(set) var contactsByHash: [String: [String]] = [:]

    /// Kontaktene i rekkefølge. Like koder sendes én gang. Blir det flere enn `limit`, kuttes
    /// resten (hele kontakter, så en kontakt ikke halvveis er med).
    init(_ contacts: [PhoneContact], limit: Int = ContactHashing.limit) {
        for contact in contacts {
            let emails = Set(contact.emails.compactMap(ContactHashing.emailHash)).sorted()
            let phones = Set(contact.phones.compactMap(ContactHashing.phoneHash)).sorted()
            let newEmails = emails.filter { contactsByHash[$0] == nil }
            let newPhones = phones.filter { contactsByHash[$0] == nil }
            guard count + newEmails.count + newPhones.count <= limit else { break }
            emailHashes += newEmails
            phoneHashes += newPhones
            for hash in emails + phones { contactsByHash[hash, default: []].append(contact.id) }
        }
    }

    var count: Int { emailHashes.count + phoneHashes.count }
    var isEmpty: Bool { count == 0 }
}

/// Én rad fra `find_contacts`.
nonisolated struct ContactMatchRow: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let displayName: String
    var avatarPath: String?
    var clubName: String?
    var myStatus: FollowStatus
    var followsMe: Bool
    /// Kodene som traff.
    var matched: [String]

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case avatarPath = "avatar_path"
        case clubName = "club_name"
        case myStatus = "my_status"
        case followsMe = "follows_me"
        case matched
    }

    init(id: UUID, displayName: String, avatarPath: String? = nil, clubName: String? = nil,
         myStatus: FollowStatus = .none, followsMe: Bool = false, matched: [String] = []) {
        self.id = id
        self.displayName = displayName
        self.avatarPath = avatarPath
        self.clubName = clubName
        self.myStatus = myStatus
        self.followsMe = followsMe
        self.matched = matched
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName) ?? "Spiller"
        avatarPath = try c.decodeIfPresent(String.self, forKey: .avatarPath)
        clubName = try c.decodeIfPresent(String.self, forKey: .clubName)
        myStatus = FollowStatus(server: try c.decodeIfPresent(String.self, forKey: .myStatus))
        followsMe = try c.decodeIfPresent(Bool.self, forKey: .followsMe) ?? false
        matched = try c.decodeIfPresent([String].self, forKey: .matched) ?? []
    }
}

/// En kontakt som er på Atten: Atten-profilen og navnet i kontaktene.
nonisolated struct ContactMatch: Equatable, Identifiable, Sendable {
    var row: ContactMatchRow
    /// Navnet i kontaktene, så et feil nummer synes (nil når det er det samme som i Atten).
    var contactName: String?

    var id: UUID { row.id }

    /// «Ola i kontaktene · Klubben · Følger deg».
    var subtitle: String? {
        let parts = [contactName.map { "\($0) i kontaktene" }, followTrimmed(row.clubName),
                     row.followsMe ? "Følger deg" : nil]
            .compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// Svaret fra `find_contacts` delt i «I Atten» og «Inviter til Atten».
nonisolated struct ContactResults: Equatable, Sendable {
    var inAtten: [ContactMatch]
    /// Kontaktene som ikke traff, med navn, sortert.
    var invite: [PhoneContact]

    static let empty = ContactResults(inAtten: [], invite: [])

    init(inAtten: [ContactMatch], invite: [PhoneContact]) {
        self.inAtten = inAtten
        self.invite = invite
    }

    init(rows: [ContactMatchRow], contacts: [PhoneContact], lookup: ContactLookup) {
        let byID = Dictionary(contacts.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var matchedContacts = Set<String>()
        inAtten = rows.map { row in
            let ids = row.matched.flatMap { lookup.contactsByHash[$0] ?? [] }
            matchedContacts.formUnion(ids)
            let name = ids.lazy.compactMap { byID[$0]?.name }.first { !$0.isEmpty }
            let same = name.map { $0.compare(row.displayName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
            return ContactMatch(row: row, contactName: same == true ? nil : name)
        }
        .sorted { NorwegianSort.areInIncreasingOrder($0.row.displayName, $1.row.displayName) }
        invite = contacts
            .filter { !matchedContacts.contains($0.id) && !$0.name.isEmpty }
            .sorted { NorwegianSort.areInIncreasingOrder($0.name, $1.name) }
    }

    /// Lista er lang nok til å trenge et søkefelt.
    static let searchThreshold = 15

    /// Inviter-lista filtrert på navn (store og små bokstaver og aksenter likt).
    func invite(matching query: String) -> [PhoneContact] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return invite }
        return invite.filter { $0.name.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }
}

/// Teksten i invitasjonen.
nonisolated enum ContactInvite {
    static func message(link: URL?) -> String {
        guard let link else { return "Bli med meg på Atten!" }
        return "Bli med meg på Atten! Følg meg her: \(link.absoluteString)"
    }
}

/// Feiltekstene for kontakter og telefonnummer (sql/077).
nonisolated enum ContactsError {
    static func findMessage(_ error: DataError, code: String?) -> String {
        switch code {
        case "54000": "Prøv igjen om litt."
        case "22023": "For mange kontakter."
        default: error.message
        }
    }

    static func phoneMessage(_ error: DataError, code: String?) -> String {
        code == "22023" ? "Ugyldig telefonnummer." : error.message
    }
}
