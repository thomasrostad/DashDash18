import Foundation
import GolfgutuCore

// Statistikk (fase 16, `sql/021_statistikk.sql`). Alt nytt er av til 021 er godkjent og kjørt.

/// Statistikk under Deg og fra spillerprofilen, og den valgfrie føringen per hull. Av til 021 er
/// godkjent og kjørt på test.
nonisolated enum StatsFeature {
    static let isEnabled = false
}

/// Om spilleren vil føre fairway, green og putter. Av som standard, én bryter per innlogging på
/// telefonen (ikke i databasen).
nonisolated struct HoleStatsSetting: @unchecked Sendable {
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    static func key(_ userID: UUID) -> String { "statistikk.foring.\(userID.uuidString)" }

    func isOn(for userID: UUID) -> Bool {
        defaults.bool(forKey: Self.key(userID))
    }

    func set(_ on: Bool, for userID: UUID) {
        defaults.set(on, forKey: Self.key(userID))
    }
}

/// Den valgfrie føringen for ett hull (`hole_stats`). En rad uten noe ført finnes ikke.
nonisolated struct HoleStatRow: Codable, Equatable, Sendable {
    let roundID: UUID
    let memberID: UUID
    var holeIndex: Int
    var fairway: FairwayResult?
    var greenInRegulation: Bool?
    var putts: Int?
    var bunker: Bool?
    var penalties: Int?

    enum CodingKeys: String, CodingKey {
        case roundID = "round_id"
        case memberID = "member_id"
        case holeIndex = "hole_index"
        case fairway
        case greenInRegulation = "green_in_regulation"
        case putts
        case bunker
        case penalties
    }

    static let columns = "round_id, member_id, hole_index, fairway, green_in_regulation, putts, bunker, penalties"

    init(roundID: UUID, memberID: UUID, holeIndex: Int, detail: HoleDetail) {
        self.roundID = roundID
        self.memberID = memberID
        self.holeIndex = holeIndex
        fairway = detail.fairway
        greenInRegulation = detail.greenInRegulation
        putts = detail.putts
        bunker = detail.bunker
        penalties = detail.penalties
    }

    var detail: HoleDetail {
        HoleDetail(fairway: fairway, greenInRegulation: greenInRegulation, putts: putts, bunker: bunker,
                   penalties: penalties)
    }

    /// Alle feltene skrives (også tomme), så en upsert nullstiller det som er tatt bort.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(roundID, forKey: .roundID)
        try c.encode(memberID, forKey: .memberID)
        try c.encode(holeIndex, forKey: .holeIndex)
        try c.encode(fairway, forKey: .fairway)
        try c.encode(greenInRegulation, forKey: .greenInRegulation)
        try c.encode(putts, forKey: .putts)
        try c.encode(bunker, forKey: .bunker)
        try c.encode(penalties, forKey: .penalties)
    }
}

/// En runde slik statistikken trenger den. Klubb og kveld kan være tomme (løs runde, sql/017).
nonisolated struct StatsRoundRow: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var clubID: UUID?
    var eventID: UUID?
    var courseID: UUID?
    var name: String?
    var status: RoundStatus
    var holeCount: Int
    var firstHole: Int
    var format: String
    var handicapAllowance: Double
    var externalHandicap: Bool
    var startedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case clubID = "club_id"
        case eventID = "event_id"
        case courseID = "course_id"
        case name
        case status
        case holeCount = "hole_count"
        case firstHole = "first_hole"
        case format
        case handicapAllowance = "handicap_allowance"
        case externalHandicap = "external_handicap"
        case startedAt = "started_at"
    }

    static let columns = """
        id, club_id, event_id, course_id, name, status, hole_count, first_hole, format, \
        handicap_allowance, external_handicap, started_at
        """
}

/// Spilleren i runden: frosset indeks og spillehandicap. Klubb kan være tom (løs runde).
nonisolated struct StatsPlayerRow: Codable, Equatable, Sendable {
    let roundID: UUID
    let memberID: UUID
    var handicapIndex: Double?
    var seedGroup: Int?
    var playingHandicap: Int?

    enum CodingKeys: String, CodingKey {
        case roundID = "round_id"
        case memberID = "member_id"
        case handicapIndex = "handicap_index"
        case seedGroup = "seed_group"
        case playingHandicap = "playing_handicap"
    }

    static let columns = "round_id, member_id, handicap_index, seed_group, playing_handicap"
}

/// En bane i klubben eller i det felles biblioteket (klubb tom, sql/017).
nonisolated struct StatsCourseRow: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var courseRating: Double?
    var slopeRating: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case courseRating = "course_rating"
        case slopeRating = "slope_rating"
    }

    static let columns = "id, name, course_rating, slope_rating"
}
