import Foundation
import GolfgutuCore

// Radtyper for tabellene i skjema v1 (`sql/001_skjema_v1.sql`). Én type per tabell,
// med kolonnenavnene fra databasen i CodingKeys. Dato og klokkeslett holdes som tekst
// slik Postgres leverer dem (`2026-10-08`, `17:00:00`), og tolkes der de vises.
// Felles for alle funksjoner, så agenter og skjermer ikke lager hver sin variant.
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
}

nonisolated struct CourseRow: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let clubID: UUID
    var name: String
    var externalName: String?
    var courseRating: Double?
    var slopeRating: Int?
    var inUse: Bool
    var confirmedBy: UUID?
    var confirmedAt: Date?

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
    }
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
}
