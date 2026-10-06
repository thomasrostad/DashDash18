import Foundation
import GolfgutuCore

// Radene tippekupongen leser og skriver (sql/008_sosialt.sql). Egne typer her, så
// `EventRow` i Data/ ikke må endres for kolonnene bare kupongen bruker.

/// Kvelden med kupongens kolonner. `nil` = regelsettets standard.
nonisolated struct TipsEventRow: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let clubID: UUID
    var seasonID: UUID?
    /// `YYYY-MM-DD`.
    var eventDate: String
    /// `HH:MM:SS` i Oslo-tid, eller nil (da gjelder regelsettets frist).
    var startTime: String?
    /// Innsats i poeng (B10). 0 = for æra.
    var stakePoints: Int?
    /// Linja på over/under, alltid x,5.
    var line: Double?

    enum CodingKeys: String, CodingKey {
        case id
        case clubID = "club_id"
        case seasonID = "season_id"
        case eventDate = "event_date"
        case startTime = "start_time"
        case stakePoints = "tips_stake_points"
        case line = "tips_line"
    }

    static let columns = "id, club_id, season_id, event_date, start_time, tips_stake_points, tips_line"
}

/// Én kupong (`tips`). Fasit og poeng lagres ikke; de regnes i GolfgutuCore.
nonisolated struct TipsRow: Codable, Equatable, Sendable {
    let eventID: UUID
    let memberID: UUID
    let clubID: UUID
    var winner: UUID?
    var frontNine: UUID?
    var mostPars: UUID?
    var birdie: Bool?
    var overLine: Bool?
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case eventID = "event_id"
        case memberID = "member_id"
        case clubID = "club_id"
        case winner
        case frontNine = "front_nine"
        case mostPars = "most_pars"
        case birdie
        case overLine = "over_line"
        case updatedAt = "updated_at"
    }

    static let columns = "event_id, member_id, club_id, winner, front_nine, most_pars, birdie, over_line, updated_at"

    /// Regelmotorens kupong.
    var coupon: TipsCoupon {
        TipsCoupon(playerID: memberID.uuidString, winner: winner?.uuidString, frontNine: frontNine?.uuidString,
                   mostPars: mostPars?.uuidString, birdie: birdie, over: overLine)
    }
}

/// Raden som sendes ved levering. Alle svar skrives, også null, så en endring aldri blir halv.
nonisolated struct TipsUpsert: Encodable, Equatable, Sendable {
    let eventID: UUID
    let memberID: UUID
    let clubID: UUID
    let winner: UUID?
    let frontNine: UUID?
    let mostPars: UUID?
    let birdie: Bool?
    let overLine: Bool?

    init(eventID: UUID, memberID: UUID, clubID: UUID, coupon: TipsCoupon) {
        self.eventID = eventID
        self.memberID = memberID
        self.clubID = clubID
        winner = coupon.winner.flatMap(UUID.init(uuidString:))
        frontNine = coupon.frontNine.flatMap(UUID.init(uuidString:))
        mostPars = coupon.mostPars.flatMap(UUID.init(uuidString:))
        birdie = coupon.birdie
        overLine = coupon.over
    }

    enum CodingKeys: String, CodingKey {
        case eventID = "event_id"
        case memberID = "member_id"
        case clubID = "club_id"
        case winner
        case frontNine = "front_nine"
        case mostPars = "most_pars"
        case birdie
        case overLine = "over_line"
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(eventID, forKey: .eventID)
        try c.encode(memberID, forKey: .memberID)
        try c.encode(clubID, forKey: .clubID)
        try c.encode(winner, forKey: .winner)
        try c.encode(frontNine, forKey: .frontNine)
        try c.encode(mostPars, forKey: .mostPars)
        try c.encode(birdie, forKey: .birdie)
        try c.encode(overLine, forKey: .overLine)
    }

    /// Stemmer raden databasen svarte med med det som ble sendt?
    func matches(_ row: TipsRow) -> Bool {
        row.eventID == eventID && row.memberID == memberID && row.winner == winner && row.frontNine == frontNine
            && row.mostPars == mostPars && row.birdie == birdie && row.overLine == overLine
    }
}

/// Arrangørens oppsett for kvelden. `nil` skrives som null (tilbake til regelsettets standard).
nonisolated struct TipsSettingsUpdate: Encodable, Equatable, Sendable {
    let stakePoints: Int?
    let line: Double?

    enum CodingKeys: String, CodingKey {
        case stakePoints = "tips_stake_points"
        case line = "tips_line"
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(stakePoints, forKey: .stakePoints)
        try c.encode(line, forKey: .line)
    }
}

/// `tips_submitted(kveld)`: hvem som har levert og når, uten svarene.
nonisolated struct TipsSubmittedRow: Codable, Equatable, Sendable {
    let memberID: UUID
    var submittedAt: Date?

    enum CodingKeys: String, CodingKey {
        case memberID = "member_id"
        case submittedAt = "submitted_at"
    }
}
