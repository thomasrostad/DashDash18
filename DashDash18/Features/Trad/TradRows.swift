import Foundation

// Radtypene for kveldens tråd (`thread_messages` i `sql/008_sosialt.sql`). Ligger her og
// ikke i `Data/Rows.swift` til tråden er koblet inn; flyttes dit når andre trenger dem.

/// Én melding i kveldens tråd, slik den leses fra databasen.
nonisolated struct ThreadMessageRow: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let clubID: UUID
    let eventID: UUID
    let memberID: UUID
    var body: String
    var mentions: [UUID]
    /// `<member_id>/<id>.jpg` i bøtta `thread`, med små bokstaver. nil = ingen bilde.
    var imagePath: String?
    /// Settes av serveren.
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case clubID = "club_id"
        case eventID = "event_id"
        case memberID = "member_id"
        case body
        case mentions
        case imagePath = "image_path"
        case createdAt = "created_at"
    }

    static let columns = "id, club_id, event_id, member_id, body, mentions, image_path, created_at"
}

/// Det klienten sender ved ny melding. Ingen `created_at` eller `pushed_at`: dem setter
/// serveren. `image_path` er utelatt når meldingen ikke har bilde.
nonisolated struct ThreadMessageInsert: Encodable, Equatable, Sendable {
    let id: UUID
    let clubID: UUID
    let eventID: UUID
    let memberID: UUID
    let body: String
    let mentions: [UUID]
    let imagePath: String?

    enum CodingKeys: String, CodingKey {
        case id
        case clubID = "club_id"
        case eventID = "event_id"
        case memberID = "member_id"
        case body
        case mentions
        case imagePath = "image_path"
    }
}
