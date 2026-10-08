import Foundation
import GolfgutuCore

// Radtyper for fundamentet i fase 12 (`sql/017_fundament.sql`, `docs/datamodell-v2.md`): profiler,
// runder uten klubb, deltakere (profil eller gjest), konkurranser og hvilke runder som teller.
// Kolonnenavnene fra databasen står i CodingKeys, som i `Rows.swift`.

/// Fundamentet (sql/017, kjørt på test). Når det er på, hentes profiler, løse runder og
/// konkurranser (fase 13 og 15). Av: appen oppfører seg som før 017.
nonisolated enum FoundationFeature {
    static let isEnabled = true
}

/// Én person per innlogging (`profiles`). `id` er innloggingens id (`auth.users.id`), den samme som
/// `club_members.user_id`.
nonisolated struct ProfileRow: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    /// Tomt til personen har sagt hva hen heter, eller navnet er fylt fra klubben (`ensure_profile`).
    var displayName: String?
    var handicapIndex: Double?
    var avatarPath: String?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case handicapIndex = "handicap_index"
        case avatarPath = "avatar_path"
    }

    static let columns = "id, display_name, handicap_index, avatar_path"
}

/// Hvor en runde hører hjemme: klubb og kveld, eller ingen av delene (en løs runde med en eier,
/// `rounds_home_check`).
/// Bare kolonnene som avgjør tilhørighet og om runden teller; resten av runden er `RoundRow`.
nonisolated struct RoundOriginRow: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var clubID: UUID?
    var eventID: UUID?
    /// Eieren av en løs runde. Tom på klubbrunder.
    var ownerID: UUID?
    var status: RoundStatus

    enum CodingKeys: String, CodingKey {
        case id
        case clubID = "club_id"
        case eventID = "event_id"
        case ownerID = "owner_id"
        case status
    }

    static let columns = "id, club_id, event_id, owner_id, status"

    init(id: UUID, clubID: UUID?, eventID: UUID?, ownerID: UUID?, status: RoundStatus) {
        self.id = id
        self.clubID = clubID
        self.eventID = eventID
        self.ownerID = ownerID
        self.status = status
    }

    /// En klubbrunde slik den er hentet i dag.
    init(_ round: RoundRow) {
        self.init(id: round.id, clubID: round.clubID, eventID: round.eventID, ownerID: nil, status: round.status)
    }
}

/// Deltaker i en løs runde (`round_participants`): en profil, eller en gjest med bare navn.
/// `id` er også spillerens id i runden (`round_players.member_id`, `hole_scores.member_id`).
nonisolated struct RoundParticipantRow: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let roundID: UUID
    /// Tom = gjest. Kan kobles til en profil senere.
    var profileID: UUID?
    /// Navnet slik det ble skrevet inn, eller profilens navn da personen ble lagt til.
    var displayName: String
    var handicapIndex: Double?

    enum CodingKeys: String, CodingKey {
        case id
        case roundID = "round_id"
        case profileID = "profile_id"
        case displayName = "display_name"
        case handicapIndex = "handicap_index"
    }

    static let columns = "id, round_id, profile_id, display_name, handicap_index"

    var isGuest: Bool { profileID == nil }
}

/// Én rad fra viewet `round_roster`: deltakeren i en runde med navn og profil, uansett om hen er
/// klubbmedlem, profil eller gjest.
nonisolated struct RoundRosterRow: Codable, Equatable, Sendable {
    let roundID: UUID
    /// `round_players.member_id`.
    let playerID: UUID
    var clubID: UUID?
    var displayName: String?
    var profileID: UUID?
    var isGuest: Bool

    enum CodingKeys: String, CodingKey {
        case roundID = "round_id"
        case playerID = "player_id"
        case clubID = "club_id"
        case displayName = "display_name"
        case profileID = "profile_id"
        case isGuest = "is_guest"
    }

    static let columns = "round_id, player_id, club_id, display_name, profile_id, is_guest"
}

// MARK: - Konkurranser

/// `competitions.kind`.
nonisolated enum CompetitionKind: String, Codable, CaseIterable, Sendable {
    /// Turnering/sesong, som jakkeracet.
    case season
    case league
    /// Utslag.
    case cup
    /// Morroturnering.
    case fun
    /// Spill på runden (skins, Nassau …).
    case game
}

/// `competitions.entry`: hvem som er med i tabellen.
nonisolated enum CompetitionEntry: String, Codable, Sendable {
    /// Klubbens tropp: aktive medlemmer, pluss alle som har spilt en tellende runde (som Tavla).
    case club
    /// Bare de påmeldte (`competition_participants`).
    case listed
    /// Alle som spiller en tellende runde.
    case open
}

/// En konkurranse (`competitions`). Sesongens konkurranse speiler navn, status og regler fra sesongen.
nonisolated struct CompetitionRow: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var kind: CompetitionKind
    var name: String
    /// Eier: en klubb, eller en profil (`ownerID`) når klubben er tom.
    var clubID: UUID?
    var ownerID: UUID?
    /// Sesongen den speiler (jakkeracet), ellers tom.
    var seasonID: UUID?
    /// Samme verdier som sesongens status.
    var status: SeasonStatus
    var entry: CompetitionEntry
    /// Regelsettet, som `seasons.rules`. Felt som mangler, får Golfgutu-verdien.
    var rules: Ruleset
    /// `YYYY-MM-DD`, eller tom.
    var startsOn: String?
    var endsOn: String?
    /// Klubbens hovedturnering.
    var isMain: Bool
    /// StoreKit: krever kjøp. Settes bare av serveren.
    var requiresPurchase: Bool
    var entitlementID: UUID?
    /// Åpen påmelding (`signup_open`, sql/022). Tom når kolonnen ikke er hentet (før 022).
    var signupOpen: Bool? = nil

    enum CodingKeys: String, CodingKey {
        case id
        case kind
        case name
        case clubID = "club_id"
        case ownerID = "owner_id"
        case seasonID = "season_id"
        case status
        case entry
        case rules
        case startsOn = "starts_on"
        case endsOn = "ends_on"
        case isMain = "is_main"
        case requiresPurchase = "requires_purchase"
        case entitlementID = "entitlement_id"
        case signupOpen = "signup_open"
    }

    static let columns = "id, kind, name, club_id, owner_id, season_id, status, entry, rules, starts_on, ends_on, "
        + "is_main, requires_purchase, entitlement_id"
    /// Med åpen påmelding. Krever 022 (`CompetitionsFeature`).
    static let columnsWithSignup = columns + ", signup_open"

    /// Påmeldingen er åpen.
    var isSignupOpen: Bool { signupOpen ?? false }
}

/// Påmeldt i en konkurranse (`competition_participants`): et klubbmedlem eller en profil.
nonisolated struct CompetitionParticipantRow: Codable, Equatable, Identifiable, Sendable {
    enum Status: String, Codable, Sendable {
        case active
        case withdrawn
    }

    let id: UUID
    let competitionID: UUID
    var memberID: UUID?
    var profileID: UUID?
    var status: Status

    enum CodingKeys: String, CodingKey {
        case id
        case competitionID = "competition_id"
        case memberID = "member_id"
        case profileID = "profile_id"
        case status
    }

    static let columns = "id, competition_id, member_id, profile_id, status"
}

/// En runde som teller i en konkurranse (`competition_rounds`). En runde kan telle i flere.
nonisolated struct CompetitionRoundRow: Codable, Equatable, Sendable {
    enum Source: String, Codable, Sendable {
        /// Koblet av databasen: runden er i en kveld i sesongen.
        case season
        /// Lagt til av arrangøren eller eieren.
        case manual
    }

    let competitionID: UUID
    let roundID: UUID
    var source: Source

    enum CodingKeys: String, CodingKey {
        case competitionID = "competition_id"
        case roundID = "round_id"
        case source
    }

    static let columns = "competition_id, round_id, source"
}
