import Foundation
import GolfgutuCore

// Ren logikk for troppen: gruppering, hvilke handlinger som er lov for en rad,
// validering og endringene som sendes til `club_members`. Ingen SwiftUI eller nettverk,
// så alt kan testes isolert. Reglene speiler `guard_club_members` og constraintene i
// `sql/001_skjema_v1.sql`, slik at knappene er sperret før databasen sier nei.

// MARK: - Gruppering

/// Troppen delt i de tre listene arrangøren ser, hver sortert norsk på navn.
nonisolated struct TroppSections: Equatable, Sendable {
    var pending: [ClubMemberRow] = []
    var active: [ClubMemberRow] = []
    var archived: [ClubMemberRow] = []

    init(_ rows: [ClubMemberRow]) {
        let sorted = rows.sorted { a, b in
            let byName = NorwegianSort.compare(a.displayName, b.displayName)
            return byName == .orderedSame ? a.id.uuidString < b.id.uuidString : byName == .orderedAscending
        }
        for row in sorted {
            switch row.status {
            case .pending: pending.append(row)
            case .active: active.append(row)
            case .archived: archived.append(row)
            }
        }
    }
}

// MARK: - Handlinger og hva som er lov

nonisolated enum TroppAction: Hashable, Sendable {
    case approve
    case reject
    case edit
    case setSeedGroup
    case grantOrganizer
    case revokeOrganizer
    case grantTreasurer
    case revokeTreasurer
    case releaseLogin
    case archive
    case restore
    case delete
}

/// Om en handling vises, og om den kan brukes.
nonisolated enum TroppAvailability: Equatable, Sendable {
    /// Gir ikke mening for raden (f.eks. «godkjenn» på en aktiv spiller).
    case hidden
    case allowed
    /// Vises, men er sperret. Teksten forklarer hvorfor.
    case blocked(String)

    var isAllowed: Bool { self == .allowed }
    var isVisible: Bool { self != .hidden }
    var reason: String? {
        if case .blocked(let text) = self { return text }
        return nil
    }
}

nonisolated enum TroppRules {
    static let lastOrganizerText = "Klubben må ha minst én arrangør. Gi rollen til en annen først."
    static let ownRowText = "Du kan ikke gjøre dette med deg selv. Be en annen arrangør."
    static let needsLoginText = "Roller gis til spillere som har logget inn."

    /// Teller som arrangør for databasen: aktiv, med innlogging og flagget satt
    /// (samme vilkår som sperra for siste arrangør i `guard_club_members`).
    static func isEffectiveOrganizer(_ row: ClubMemberRow) -> Bool {
        row.isOrganizer && row.status == .active && row.userID != nil
    }

    /// Raden er klubbens eneste arrangør. Da kan den ikke miste rollen, arkiveres
    /// eller frigjøres.
    static func isLastOrganizer(_ row: ClubMemberRow, in rows: [ClubMemberRow]) -> Bool {
        isEffectiveOrganizer(row) && !rows.contains { $0.id != row.id && isEffectiveOrganizer($0) }
    }

    /// Normalisert navn for unikhet, som `lower(btrim(display_name))` i databasen.
    static func nameKey(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Finnes navnet allerede blant radene som ikke er arkivert (unik-indeksen)?
    static func nameTaken(_ name: String, in rows: [ClubMemberRow], excluding id: UUID? = nil) -> Bool {
        let key = nameKey(name)
        return rows.contains { $0.id != id && $0.status != .archived && nameKey($0.displayName) == key }
    }

    static func availability(
        _ action: TroppAction,
        for row: ClubMemberRow,
        in rows: [ClubMemberRow],
        me: UUID
    ) -> TroppAvailability {
        let isMe = row.id == me
        let lastOrganizer = isLastOrganizer(row, in: rows)

        switch action {
        case .approve, .reject:
            return row.status == .pending ? .allowed : .hidden

        case .edit:
            return .allowed

        case .setSeedGroup:
            return row.status == .archived ? .hidden : .allowed

        case .grantOrganizer, .grantTreasurer:
            guard row.status == .active else { return .hidden }
            let has = action == .grantOrganizer ? row.isOrganizer : row.isTreasurer
            if has { return .hidden }
            return row.userID == nil ? .blocked(needsLoginText) : .allowed

        case .revokeOrganizer:
            guard row.status == .active, row.isOrganizer else { return .hidden }
            if lastOrganizer { return .blocked(lastOrganizerText) }
            if isMe { return .blocked(ownRowText) }
            return .allowed

        case .revokeTreasurer:
            return row.status == .active && row.isTreasurer ? .allowed : .hidden

        case .releaseLogin:
            // En ventende rad må ha innlogging (constraint). Avvis i stedet.
            guard row.userID != nil, row.status != .pending else { return .hidden }
            if isMe { return .blocked(ownRowText) }
            if lastOrganizer { return .blocked(lastOrganizerText) }
            return .allowed

        case .archive:
            guard row.status == .active else { return .hidden }
            if isMe { return .blocked(ownRowText) }
            if lastOrganizer { return .blocked(lastOrganizerText) }
            return .allowed

        case .restore:
            guard row.status == .archived else { return .hidden }
            if nameTaken(row.displayName, in: rows, excluding: row.id) {
                return .blocked("Navnet «\(row.displayName)» er i bruk i troppen. Gi nytt navn først.")
            }
            return .allowed

        case .delete:
            // Databasen lar bare ledige rader slettes. Rader med runder stoppes av
            // fremmednøklene; da kommer feilen fra databasen.
            guard row.userID == nil, row.status != .pending else { return .hidden }
            return .allowed
        }
    }
}

// MARK: - Validering

nonisolated struct TroppInputValue: Equatable, Sendable {
    let name: String
    let handicapIndex: Double?
}

nonisolated enum TroppInput {
    /// Navn og handicap fra skjemaet, sjekket som i klubbskjemaene (`ClubInput`)
    /// og mot navnene i troppen.
    static func validate(
        name rawName: String,
        handicap rawHandicap: String,
        rows: [ClubMemberRow],
        editing id: UUID? = nil
    ) -> Result<TroppInputValue, TroppError> {
        guard let name = ClubInput.normalizedName(rawName) else {
            return .failure(.invalid("Skriv inn et navn (høyst 40 tegn)."))
        }
        if TroppRules.nameTaken(name, in: rows, excluding: id) {
            return .failure(.invalid("Det navnet finnes allerede i troppen."))
        }
        switch ClubInput.handicapIndex(rawHandicap) {
        case .success(let index):
            return .success(TroppInputValue(name: name, handicapIndex: index))
        case .failure(let error):
            return .failure(.invalid(error.message))
        }
    }

    /// Handicap slik det står i skjemaet: «18,4», «+2,3» for plusshandicap, tomt for ikke oppgitt.
    static func handicapText(_ index: Double?) -> String {
        guard let index else { return "" }
        let text = String(format: "%.1f", abs(index)).replacingOccurrences(of: ".", with: ",")
        return index < 0 ? "+" + text : text
    }
}

// MARK: - Seeding

nonisolated enum TroppSeeding {
    /// Gruppene fra den aktive sesongens regelsett, ellers Golfgutu-gruppene.
    /// Bare nummer databasen tåler (1–9), sortert på nummer.
    static func groups(activeSeason: SeasonRow?) -> [SeedingGroup] {
        let groups = activeSeason?.rules.handicap.seedingGroups ?? SeedingGroup.golfgutu
        return groups.filter { (1...9).contains($0.number) }.sorted { $0.number < $1.number }
    }

    /// Navnet på gruppa, også når nummeret ikke finnes i regelsettet.
    static func label(_ number: Int?, groups: [SeedingGroup]) -> String {
        guard let number else { return "Ingen gruppe" }
        if let group = groups.first(where: { $0.number == number }) {
            return "\(group.name) (hcp \(JS.norwegianString(group.handicap)))"
        }
        return "Gruppe \(number) (finnes ikke i regelsettet)"
    }
}

// MARK: - Endringer mot databasen

/// En delvis oppdatering av `club_members`. Bare feltene som er satt sendes, og
/// `.some(nil)` sendes som `null` (å tømme et felt).
nonisolated struct MemberPatch: Encodable, Equatable, Sendable {
    var displayName: String?
    var handicapIndex: Double??
    var seedGroup: Int??
    var isOrganizer: Bool?
    var isTreasurer: Bool?
    var status: MemberStatus?
    var userID: UUID??

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case handicapIndex = "handicap_index"
        case seedGroup = "seed_group"
        case isOrganizer = "is_organizer"
        case isTreasurer = "is_treasurer"
        case status
        case userID = "user_id"
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(displayName, forKey: .displayName)
        if let handicapIndex { try c.encodeNullable(handicapIndex, forKey: .handicapIndex) }
        if let seedGroup { try c.encodeNullable(seedGroup, forKey: .seedGroup) }
        try c.encodeIfPresent(isOrganizer, forKey: .isOrganizer)
        try c.encodeIfPresent(isTreasurer, forKey: .isTreasurer)
        try c.encodeIfPresent(status, forKey: .status)
        if let userID { try c.encodeNullable(userID, forKey: .userID) }
    }

    static let approve = MemberPatch(status: .active)
    /// Avvis: raden arkiveres og innloggingen frigjøres. En ventende rad kan ikke
    /// slettes (den har innlogging), og med innloggingen igjen på en arkivert rad
    /// ville `join_club` bare gitt personen den arkiverte raden tilbake.
    static let reject = MemberPatch(status: .archived, userID: .some(nil))
    /// Arkiver. Rollene må av samtidig (`club_members_roles_need_active`).
    static let archive = MemberPatch(isOrganizer: false, isTreasurer: false, status: .archived)
    static let restore = MemberPatch(status: .active)
    static let releaseLogin = MemberPatch(userID: .some(nil))

    static func details(_ value: TroppInputValue) -> MemberPatch {
        MemberPatch(displayName: value.name, handicapIndex: .some(value.handicapIndex))
    }

    static func seed(_ group: Int?) -> MemberPatch {
        MemberPatch(seedGroup: .some(group))
    }
}

nonisolated private extension KeyedEncodingContainer {
    mutating func encodeNullable<T: Encodable>(_ value: T?, forKey key: Key) throws {
        if let value { try encode(value, forKey: key) } else { try encodeNil(forKey: key) }
    }
}

/// Ny, ledig tropprad uten innlogging.
nonisolated struct NewMember: Encodable, Equatable, Sendable {
    let clubID: UUID
    let displayName: String
    let handicapIndex: Double?

    enum CodingKeys: String, CodingKey {
        case clubID = "club_id"
        case displayName = "display_name"
        case handicapIndex = "handicap_index"
        case status
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(clubID, forKey: .clubID)
        try c.encode(displayName, forKey: .displayName)
        try c.encodeIfPresent(handicapIndex, forKey: .handicapIndex)
        try c.encode(MemberStatus.active, forKey: .status)
    }
}

// MARK: - Feil

nonisolated enum TroppError: Error, Equatable {
    case invalid(String)
    case lastOrganizer
    case duplicateName
    case inUse
    case notSaved
    case other(DataError)

    var message: String {
        switch self {
        case .invalid(let text): text
        case .lastOrganizer: TroppRules.lastOrganizerText
        case .duplicateName: "Det navnet finnes allerede i troppen."
        case .inUse: "Spilleren har spilt runder og kan ikke slettes. Arkiver i stedet."
        case .notSaved: "Endringen ble ikke lagret. Du har kanskje ikke tilgang lenger. Last inn på nytt."
        case .other(let error): error.message
        }
    }

    /// Oversetter SQLSTATE og melding fra databasen (se `sql/README.md`, feilkoder).
    static func from(sqlState: String?, message: String) -> TroppError {
        switch sqlState {
        case "42501" where message.contains("minst én arrangør"): .lastOrganizer
        case "23505": .duplicateName
        case "23503": .inUse
        // `.single()` uten rad tilbake: RLS slapp ikke endringen gjennom.
        case "PGRST116": .notSaved
        case "23514": .invalid("Verdien er ikke gyldig.")
        default: .other(DataError.from(sqlState: sqlState, message: message))
        }
    }
}

// MARK: - Visning

nonisolated enum TroppDisplay {
    /// Linja under navnet i lista: handicap, gruppe, roller og innlogging.
    static func details(for row: ClubMemberRow, groups: [SeedingGroup]) -> String {
        var parts: [String] = []
        if let index = row.handicapIndex {
            parts.append("Hcp \(TroppInput.handicapText(index))")
        }
        if let group = row.seedGroup {
            parts.append(groups.first { $0.number == group }?.name ?? "Gruppe \(group)")
        }
        if row.isOrganizer { parts.append("Arrangør") }
        if row.isTreasurer { parts.append("Kasserer") }
        if row.userID == nil { parts.append("Har ikke logget inn") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Invitasjon

/// Invitasjonskoden til klubben (`clubs.join_code`), slik arrangøren deler den fra Troppen,
/// arrangørsiden og Hjem.
nonisolated enum TroppInvite {
    /// Teksten som deles, med lenken (`dashdash://klubb/KODE`) og koden. Nil når klubben ikke har noen kode.
    static func shareText(clubName: String, code: String?) -> String? {
        invite(code).map { $0.shareText(clubName: clubName) }
    }

    /// Invitasjonen til klubben, eller nil når den ikke har noen (gyldig) kode.
    static func invite(_ code: String?) -> ClubInvite? {
        code.flatMap { ClubInvite(code: $0) }
    }
}
