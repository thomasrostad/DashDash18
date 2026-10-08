import Foundation
import GolfgutuCore

// Radtyper for tabellene i skjema v1 (`sql/001_skjema_v1.sql`). Én type per tabell,
// med kolonnenavnene fra databasen i CodingKeys. Dato og klokkeslett holdes som tekst
// slik Postgres leverer dem (`2026-10-08`, `17:00:00`), og tolkes der de vises.
// Felles for alle funksjoner, så agenter og skjermer ikke lager hver sin variant.
// `columns` er kolonnelista spørringene henter: CodingKeys, uten valgfrie felt som bare hentes noen steder.
// (`CourseHoleRecord` heter ikke `…Row` fordi GolfgutuCore har en `CourseHoleRow` med PWA-ens kolonner.)

nonisolated struct ClubMemberRow: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let clubID: UUID
    var userID: UUID?
    var displayName: String
    var handicapIndex: Double?
    var seedGroup: Int?
    var isOrganizer: Bool
    var isTreasurer: Bool
    var status: MemberStatus
    var avatarPath: String?

    enum CodingKeys: String, CodingKey {
        case id
        case clubID = "club_id"
        case userID = "user_id"
        case displayName = "display_name"
        case handicapIndex = "handicap_index"
        case seedGroup = "seed_group"
        case isOrganizer = "is_organizer"
        case isTreasurer = "is_treasurer"
        case status
        case avatarPath = "avatar_path"
    }

    static let columns =
        "id, club_id, user_id, display_name, handicap_index, seed_group, is_organizer, is_treasurer, status, avatar_path"

    /// Ledig navn i troppen som ingen har tatt ennå.
    var isOpen: Bool { userID == nil }
}

nonisolated enum SeasonStatus: String, Codable, Sendable {
    case planned
    case active
    case finished
}

nonisolated struct SeasonRow: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let clubID: UUID
    var name: String
    var status: SeasonStatus
    /// Regelsettet (B12). Leses av GolfgutuCore, som tåler versjon 1 og 2 og fyller inn
    /// Golfgutu-verdier for felt som mangler.
    var rules: Ruleset

    enum CodingKeys: String, CodingKey {
        case id
        case clubID = "club_id"
        case name
        case status
        case rules
    }

    static let columns = "id, club_id, name, status, rules"
}

nonisolated struct EventRow: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let clubID: UUID
    var seasonID: UUID?
    /// `YYYY-MM-DD`.
    var eventDate: String
    /// `HH:MM:SS` i lokal tid (Europe/Oslo), eller nil.
    var startTime: String?
    var venue: String?
    var note: String?

    enum CodingKeys: String, CodingKey {
        case id
        case clubID = "club_id"
        case seasonID = "season_id"
        case eventDate = "event_date"
        case startTime = "start_time"
        case venue
        case note
    }

    static let columns = "id, club_id, season_id, event_date, start_time, venue, note"
}

nonisolated struct EventCommitteeRow: Codable, Equatable, Sendable {
    let eventID: UUID
    let memberID: UUID
    let clubID: UUID

    enum CodingKeys: String, CodingKey {
        case eventID = "event_id"
        case memberID = "member_id"
        case clubID = "club_id"
    }

    static let columns = "event_id, member_id, club_id"
}

nonisolated enum SignupStatus: String, Codable, CaseIterable, Sendable {
    case yes
    case maybe
    case no

    var title: String {
        switch self {
        case .yes: "Kommer"
        case .maybe: "Usikker"
        case .no: "Kommer ikke"
        }
    }
}

nonisolated struct SignupRow: Codable, Equatable, Sendable {
    let eventID: UUID
    let memberID: UUID
    let clubID: UUID
    var status: SignupStatus
    var comment: String?

    enum CodingKeys: String, CodingKey {
        case eventID = "event_id"
        case memberID = "member_id"
        case clubID = "club_id"
        case status
        case comment
    }

    static let columns = "event_id, member_id, club_id, status, comment"
}

nonisolated struct CourseRow: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    /// Klubbens bane, eller tom: banen ligger i det felles biblioteket (sql/017).
    let clubID: UUID?
    var name: String
    var externalName: String?
    var courseRating: Double?
    var slopeRating: Int?
    var inUse: Bool
    var confirmedBy: UUID?
    var confirmedAt: Date?
    /// Den som la inn en bane i det felles biblioteket (sql/017). Hentes bare der; ellers nil.
    var createdByProfile: UUID? = nil

    enum CodingKeys: String, CodingKey {
        case id
        case clubID = "club_id"
        case name
        case externalName = "external_name"
        case courseRating = "course_rating"
        case slopeRating = "slope_rating"
        case inUse = "in_use"
        case confirmedBy = "confirmed_by"
        case confirmedAt = "confirmed_at"
        case createdByProfile = "created_by_profile"
    }

    /// Uten `created_by_profile`, som bare hentes fra det felles biblioteket.
    static let columns = "id, club_id, name, external_name, course_rating, slope_rating, in_use, confirmed_by, confirmed_at"
}

nonisolated struct CourseHoleRecord: Codable, Equatable, Sendable {
    let courseID: UUID
    var holeNumber: Int
    var par: Int
    var strokeIndex: Int?
    var lengthM: Int?

    enum CodingKeys: String, CodingKey {
        case courseID = "course_id"
        case holeNumber = "hole_number"
        case par
        case strokeIndex = "stroke_index"
        case lengthM = "length_m"
    }

    static let columns = "course_id, hole_number, par, stroke_index, length_m"
}

// MARK: - Runder (fase 4–5)

nonisolated enum RoundStatus: String, Codable, Sendable {
    /// Kladd: bare arrangøren ser den.
    case draft
    case active
    case locked
}

nonisolated struct RoundRow: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    /// Klubb og kveld, eller begge tomme: en løs runde uten klubb (sql/017, `rounds_home_check`).
    let clubID: UUID?
    var eventID: UUID?
    var courseID: UUID?
    var roundNo: Int
    var name: String?
    var status: RoundStatus
    var holeCount: Int
    /// 1, eller 10 for «siste ni» på en 18-hullsbane.
    var firstHole: Int
    var teeTime: String?
    /// Id fra konkurranseform-katalogen i GolfgutuCore.
    var format: String
    var handicapAllowance: Double
    var externalHandicap: Bool
    var weight: Double
    var ldEnabled: Bool
    var ldHoleIndex: Int?
    var kpEnabled: Bool
    var kpHoleIndex: Int?
    /// `common`, `net_par` eller `zero`.
    var cutRule: String?
    var cutAfter: Int?
    var parConfirmedBy: UUID?
    var parConfirmedAt: Date?
    var startedAt: Date?
    var lockedAt: Date?
    /// `simulator` eller `course` (sql/015). Hentes bare når `VenueFeature` er på; `nil` = simulator.
    var venue: String? = nil
    /// Teen runden spilles fra, med navnet og CR/slope slik de var ved start (sql/029,
    /// `rounds_tee_snapshot`). Hentes bare når `SlopeNoFeature` er på; tomme = banens tall gjelder.
    var teeID: UUID? = nil
    var teeName: String? = nil
    var courseRating: Double? = nil
    var slopeRating: Int? = nil

    enum CodingKeys: String, CodingKey {
        case id
        case clubID = "club_id"
        case eventID = "event_id"
        case courseID = "course_id"
        case roundNo = "round_no"
        case name
        case status
        case holeCount = "hole_count"
        case firstHole = "first_hole"
        case teeTime = "tee_time"
        case format
        case handicapAllowance = "handicap_allowance"
        case externalHandicap = "external_handicap"
        case weight
        case ldEnabled = "ld_enabled"
        case ldHoleIndex = "ld_hole_index"
        case kpEnabled = "kp_enabled"
        case kpHoleIndex = "kp_hole_index"
        case cutRule = "cut_rule"
        case cutAfter = "cut_after"
        case parConfirmedBy = "par_confirmed_by"
        case parConfirmedAt = "par_confirmed_at"
        case startedAt = "started_at"
        case lockedAt = "locked_at"
        case venue
        case teeID = "tee_id"
        case teeName = "tee_name"
        case courseRating = "course_rating"
        case slopeRating = "slope_rating"
    }

    /// `venue` er med bare når sql/015 er kjørt (`VenueFeature`); før det finnes ikke kolonnen.
    /// Teen og tallene (sql/029) bare når `SlopeNoFeature` er på.
    static let columns = """
        id, club_id, event_id, course_id, round_no, name, status, hole_count, first_hole, tee_time, format, \
        handicap_allowance, external_handicap, weight, ld_enabled, ld_hole_index, kp_enabled, kp_hole_index, \
        cut_rule, cut_after, par_confirmed_by, par_confirmed_at, started_at, locked_at
        """ + (VenueFeature.isEnabled ? ", venue" : "")
        + (SlopeNoFeature.isEnabled ? ", " + teeColumns : "")

    static let teeColumns = "tee_id, tee_name, course_rating, slope_rating"
}

/// Overstyring av ett hull for én runde. `holeIndex` er rundens 0-baserte hull.
nonisolated struct RoundHoleRow: Codable, Equatable, Sendable {
    let roundID: UUID
    var holeIndex: Int
    var par: Int?
    var strokeIndex: Int?
    var lengthM: Int?

    enum CodingKeys: String, CodingKey {
        case roundID = "round_id"
        case holeIndex = "hole_index"
        case par
        case strokeIndex = "stroke_index"
        case lengthM = "length_m"
    }

    static let columns = "round_id, hole_index, par, stroke_index, length_m"
}

/// Deltaker i runden med frosset handicap, bås, markør og lag.
nonisolated struct RoundPlayerRow: Codable, Equatable, Sendable {
    let roundID: UUID
    let memberID: UUID
    /// Tom for en deltaker i en løs runde (profil eller gjest, sql/017).
    let clubID: UUID?
    var handicapIndex: Double?
    var seedGroup: Int?
    var playingHandicap: Int?
    var bayNo: Int?
    var isMarker: Bool
    var teamNo: Int?

    enum CodingKeys: String, CodingKey {
        case roundID = "round_id"
        case memberID = "member_id"
        case clubID = "club_id"
        case handicapIndex = "handicap_index"
        case seedGroup = "seed_group"
        case playingHandicap = "playing_handicap"
        case bayNo = "bay_no"
        case isMarker = "is_marker"
        case teamNo = "team_no"
    }

    static let columns =
        "round_id, member_id, club_id, handicap_index, seed_group, playing_handicap, bay_no, is_marker, team_no"
}

nonisolated struct RoundMatchRow: Codable, Equatable, Sendable {
    let roundID: UUID
    var matchNo: Int
    var playerA: UUID?
    var playerB: UUID?
    var playerC: UUID?
    var teamA: Int?
    var teamB: Int?
    /// `a`, `b`, `halved` eller nil (regnes fra hullene).
    var result: String?

    enum CodingKeys: String, CodingKey {
        case roundID = "round_id"
        case matchNo = "match_no"
        case playerA = "player_a"
        case playerB = "player_b"
        case playerC = "player_c"
        case teamA = "team_a"
        case teamB = "team_b"
        case result
    }

    static let columns = "round_id, match_no, player_a, player_b, player_c, team_a, team_b, result"
}

/// Brutto slag. Ingen rad = hullet er ikke ført. Poeng regnes i appen.
nonisolated struct HoleScoreRow: Codable, Equatable, Sendable {
    let roundID: UUID
    let memberID: UUID
    var holeIndex: Int
    var strokes: Int
    var recordedAt: Date?
    var updatedBy: UUID?
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case roundID = "round_id"
        case memberID = "member_id"
        case holeIndex = "hole_index"
        case strokes
        case recordedAt = "recorded_at"
        case updatedBy = "updated_by"
        case updatedAt = "updated_at"
    }

    static let columns = "round_id, member_id, hole_index, strokes, recorded_at, updated_by, updated_at"
}

nonisolated enum SideClaimKind: String, Codable, Sendable {
    case drive
    case kp
}

nonisolated struct SideClaimRow: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let roundID: UUID
    let memberID: UUID
    var kind: SideClaimKind
    var meters: Double
    var holeIndex: Int?
    /// Når innmeldingen ble opprettet. Avgjør rekkefølgen ved lik lengde (tidligst først, som PWA-ens `ts`).
    /// Valgfri: spørringer som ikke ber om `created_at`, gir nil.
    var createdAt: Date? = nil

    enum CodingKeys: String, CodingKey {
        case id
        case roundID = "round_id"
        case memberID = "member_id"
        case kind
        case meters
        case holeIndex = "hole_index"
        case createdAt = "created_at"
    }

    static let columns = "id, round_id, member_id, kind, meters, hole_index, created_at"

    /// `created_at` som regelmotorens `ts`: ISO 8601 i UTC med millisekunder, så strengene sorteres i tidsrekkefølge.
    var timestamp: String? {
        createdAt?.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true))
    }
}
