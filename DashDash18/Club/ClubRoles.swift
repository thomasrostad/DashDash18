import Foundation

// Egne roller per klubb (steg 2, sql/044, docs/roller.md). Ren logikk: rettighetene, rollene,
// hva den innloggede har, hvilke roller den kan gi, og hvilke deler av arrangørsiden som vises.
// Serveren er den egentlige vakta (RLS og RPC-ene). Her skjules bare det du ikke har lov til.

/// De fire rettighetene. Eier har alle, og i tillegg å styre rollene og eierskapet.
nonisolated enum ClubRight: String, Codable, CaseIterable, Hashable, Sendable {
    case tournaments
    case rounds
    case members
    case money

    var title: String {
        switch self {
        case .tournaments: "Turneringer og regler"
        case .rounds: "Runder og føring"
        case .members: "Medlemmer og invitasjon"
        case .money: "Penger og moderering"
        }
    }

    var detail: String {
        switch self {
        case .tournaments: "Turneringer, regler, terminliste, påmelding og sosialkomité."
        case .rounds: "Sette opp, starte og låse runder, rette score, baner og par."
        case .members: "Godkjenne, invitere, handicap, seeding, arkivere og gi roller."
        case .money: "Del regningen, veddemål, tippekupong, rapporter og fjerning av innhold."
        }
    }
}

/// En rad i `club_roles`.
nonisolated struct ClubRoleRow: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let clubID: UUID
    var name: String
    /// Rettighetene slik databasen har dem. Ukjente verdier hoppes over i `rightSet`.
    var rights: [String]
    var isOwner: Bool
    var templateKey: String?
    var sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case id
        case clubID = "club_id"
        case name
        case rights
        case isOwner = "is_owner"
        case templateKey = "template_key"
        case sortOrder = "sort_order"
    }

    static let columns = "id, club_id, name, rights, is_owner, template_key, sort_order"

    /// Eier har alle fire.
    var rightSet: Set<ClubRight> {
        isOwner ? Set(ClubRight.allCases) : Set(rights.compactMap(ClubRight.init(rawValue:)))
    }

    var isTemplate: Bool { templateKey != nil }
}

/// En rad i `club_member_roles`.
nonisolated struct ClubMemberRoleRow: Codable, Equatable, Hashable, Sendable {
    let clubID: UUID
    let memberID: UUID
    let roleID: UUID

    enum CodingKeys: String, CodingKey {
        case clubID = "club_id"
        case memberID = "member_id"
        case roleID = "role_id"
    }

    static let columns = "club_id, member_id, role_id"
}

/// Det den innloggede har i én klubb: rettighetene lagt sammen, og om den er eier.
nonisolated struct ClubRights: Equatable, Sendable {
    let rights: Set<ClubRight>
    let isOwner: Bool

    init(rights: Set<ClubRight>, isOwner: Bool = false) {
        self.isOwner = isOwner
        self.rights = isOwner ? Set(ClubRight.allCases) : rights
    }

    /// Rettighetene fra rollene medlemmet har.
    init(roles: [ClubRoleRow]) {
        self.init(rights: roles.reduce(into: Set<ClubRight>()) { $0.formUnion($1.rightSet) },
                  isOwner: roles.contains(where: \.isOwner))
    }

    static let none = ClubRights(rights: [])

    /// Uten roller (044 ikke kjørt, eller ikke hentet ennå): flaggene i `club_members`. Arrangør har
    /// alt, kasserer har penger. Ingen er eier, så rollestyringen vises ikke.
    static func legacy(isOrganizer: Bool, isTreasurer: Bool) -> ClubRights {
        if isOrganizer { return ClubRights(rights: Set(ClubRight.allCases)) }
        return ClubRights(rights: isTreasurer ? [.money] : [])
    }

    func has(_ right: ClubRight) -> Bool { rights.contains(right) }

    /// Minst én rettighet: da er du «arrangør» (Arrangør-fanen vises), som `is_club_organizer`.
    var hasAny: Bool { isOwner || !rights.isEmpty }

    /// Bare eieren lager, endrer og sletter roller og gir bort eierskapet.
    var canManageRoles: Bool { isOwner }

    /// Kan gi eller ta rollen (`private.assert_can_change_role`): Eier bare av en eier; ellers kreves
    /// medlemmer og invitasjon, og rollens rettigheter må være blant dine.
    func canGrant(_ role: ClubRoleRow) -> Bool {
        if role.isOwner { return isOwner }
        return has(.members) && role.rightSet.isSubset(of: rights)
    }
}

/// Rollene i én klubb og hvilke den innloggede har. nil i `ClubContext` når 044 ikke er kjørt.
nonisolated struct ClubRoleAccess: Equatable, Sendable {
    let roles: [ClubRoleRow]
    let myRoleIDs: Set<UUID>

    var rights: ClubRights { ClubRights(roles: roles.filter { myRoleIDs.contains($0.id) }) }

    /// Rollene per klubb, for medlemskapene den innloggede har. Klubber uten roller tas ikke med
    /// (da gjelder flaggene, som før).
    static func byClub(roles: [ClubRoleRow], mine: [ClubMemberRoleRow], memberIDs: Set<UUID>) -> [UUID: ClubRoleAccess] {
        let grouped = Dictionary(grouping: roles, by: \.clubID)
        return grouped.mapValues { clubRoles in
            let ids = Set(clubRoles.map(\.id))
            let my = Set(mine.filter { memberIDs.contains($0.memberID) && ids.contains($0.roleID) }.map(\.roleID))
            return ClubRoleAccess(roles: ClubRoleOrder.sorted(clubRoles), myRoleIDs: my)
        }
    }
}

nonisolated enum ClubRoleOrder {
    /// Eier først, så malene, så klubbens egne roller. Innenfor hver: `sort_order`, så navn.
    static func sorted(_ roles: [ClubRoleRow]) -> [ClubRoleRow] {
        roles.sorted { a, b in
            let ra = rank(a), rb = rank(b)
            if ra != rb { return ra < rb }
            if a.sortOrder != b.sortOrder { return a.sortOrder < b.sortOrder }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    private static func rank(_ role: ClubRoleRow) -> Int {
        role.isOwner ? 0 : role.isTemplate ? 1 : 2
    }
}

nonisolated enum ClubRoleInput {
    /// Navnet på en rolle: 1–40 tegn etter trimming, og ikke likt en annen rolle i klubben
    /// (`lower(btrim(name))`, som unik-indeksen).
    static func validate(name raw: String, roles: [ClubRoleRow], editing id: UUID?) -> Result<String, ClubRoleError> {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...40).contains(name.count) else { return .failure(.invalid("Rollen må ha et navn (1–40 tegn).")) }
        let key = name.lowercased()
        if roles.contains(where: { $0.id != id && $0.name.trimmingCharacters(in: .whitespaces).lowercased() == key }) {
            return .failure(.invalid("Klubben har alt en rolle som heter «\(name)»."))
        }
        return .success(name)
    }

    /// Rettighetene sendes i fast rekkefølge.
    static func rightsParameter(_ rights: Set<ClubRight>) -> [String] {
        ClubRight.allCases.filter(rights.contains).map(\.rawValue)
    }

    /// Ny rolleliste for et medlem når én rolle slås av eller på.
    static func toggled(_ current: Set<UUID>, role: UUID, on: Bool) -> Set<UUID> {
        var next = current
        if on { next.insert(role) } else { next.remove(role) }
        return next
    }

    /// Kan eierskapet gis til medlemmet? Aktiv, med innlogging, ikke deg selv, ikke eier fra før.
    static func canTransferOwnership(viewer: ClubRights, to row: ClubMemberRow, me: UUID, memberIsOwner: Bool) -> Bool {
        viewer.isOwner && row.id != me && row.status == .active && row.userID != nil && !memberIsOwner
    }
}

nonisolated enum ClubRoleError: Error, Equatable {
    case invalid(String)
    case other(DataError)

    var message: String {
        switch self {
        case .invalid(let text): text
        case .other(let error): error.message
        }
    }
}

/// Delene av arrangørsiden, og hvilken rettighet som viser dem.
nonisolated enum AdminArea: CaseIterable, Hashable, Sendable {
    /// Turneringen, ny turnering, ny kveld, sosialkomité, terminliste.
    case tournaments
    /// Kveldene (tidslinja) med stegrekka.
    case timeline
    /// Banene og rundearkivet.
    case rounds
    /// Troppen og invitasjonen.
    case roster
    /// Rapporter (moderering).
    case reports
    /// Varsler til troppen. Står på «minst én rettighet» (steg 5 bestemmer).
    case notices
    /// Klubbens navn og organisasjonsnummer (`clubs_update` krever minst én rettighet).
    case club
    /// Rollene. Bare eieren.
    case roles

    func isVisible(for rights: ClubRights) -> Bool {
        switch self {
        case .tournaments: rights.has(.tournaments)
        case .timeline: rights.has(.tournaments) || rights.has(.rounds)
        case .rounds: rights.has(.rounds)
        case .roster: rights.has(.members)
        case .reports: rights.has(.money)
        case .notices, .club: rights.hasAny
        case .roles: rights.canManageRoles
        }
    }

    static func visible(for rights: ClubRights) -> Set<AdminArea> {
        Set(allCases.filter { $0.isVisible(for: rights) })
    }
}
