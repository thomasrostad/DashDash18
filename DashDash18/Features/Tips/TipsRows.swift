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

/// Et svar i `tips.answers` (sql/070): spiller-id eller ja/nei, over/under.
nonisolated enum TipsAnswerValue: Codable, Equatable, Sendable {
    case player(UUID)
    case flag(Bool)

    init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let b = try? c.decode(Bool.self) {
            self = .flag(b)
        } else {
            self = .player(try c.decode(UUID.self))
        }
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .player(let id): try c.encode(id)
        case .flag(let b): try c.encode(b)
        }
    }

    /// Svarene på spørsmålene som ikke har egen kolonne (alle utenom PWA-ens fem), nøkkel = spørsmålets id.
    /// Ubesvart er utelatt.
    static func answers(_ coupon: TipsCoupon) -> [String: TipsAnswerValue] {
        var out: [String: TipsAnswerValue] = [:]
        for q in TipsQuestion.allCases where !Ruleset.TipsRules.golfgutuQuestions.contains(q) {
            if q.kind == .player {
                if let id = coupon.player(q).flatMap(UUID.init(uuidString:)) { out[q.rawValue] = .player(id) }
            } else if let v = coupon.flag(q) {
                out[q.rawValue] = .flag(v)
            }
        }
        return out
    }

    /// Legger svarene inn i kupongen. Ukjente nøkler (fra en nyere app) og feil type hoppes over.
    static func apply(_ answers: [String: TipsAnswerValue], to coupon: inout TipsCoupon) {
        for (key, value) in answers {
            guard let q = TipsQuestion(rawValue: key), !Ruleset.TipsRules.golfgutuQuestions.contains(q) else { continue }
            switch (q.kind, value) {
            case (.player, .player(let id)): coupon.setPlayer(q, id.uuidString)
            case (.yesNo, .flag(let b)), (.overUnder, .flag(let b)): coupon.setFlag(q, b)
            default: break
            }
        }
    }
}

/// Én kupong (`tips`). Fasit og poeng lagres ikke; de regnes i GolfgutuCore. PWA-ens fem svar har
/// hver sin kolonne (appen 1.0.1 leser og skriver bare dem); de nye ligger i `answers` (sql/070).
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
    var answers: [String: TipsAnswerValue] = [:]

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
        case answers
    }

    init(eventID: UUID, memberID: UUID, clubID: UUID, winner: UUID?, frontNine: UUID?, mostPars: UUID?, birdie: Bool?,
         overLine: Bool?, updatedAt: Date?, answers: [String: TipsAnswerValue] = [:]) {
        self.eventID = eventID
        self.memberID = memberID
        self.clubID = clubID
        self.winner = winner
        self.frontNine = frontNine
        self.mostPars = mostPars
        self.birdie = birdie
        self.overLine = overLine
        self.updatedAt = updatedAt
        self.answers = answers
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        eventID = try c.decode(UUID.self, forKey: .eventID)
        memberID = try c.decode(UUID.self, forKey: .memberID)
        clubID = try c.decode(UUID.self, forKey: .clubID)
        winner = try c.decodeIfPresent(UUID.self, forKey: .winner)
        frontNine = try c.decodeIfPresent(UUID.self, forKey: .frontNine)
        mostPars = try c.decodeIfPresent(UUID.self, forKey: .mostPars)
        birdie = try c.decodeIfPresent(Bool.self, forKey: .birdie)
        overLine = try c.decodeIfPresent(Bool.self, forKey: .overLine)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
        // Et svar appen ikke kan lese (feil type), skal ikke stoppe hele kupongen.
        let raw = try c.decodeIfPresent([String: TipsLenientAnswer].self, forKey: .answers) ?? [:]
        answers = raw.compactMapValues(\.value)
    }

    static let columns = "event_id, member_id, club_id, winner, front_nine, most_pars, birdie, over_line, updated_at, answers"

    /// Regelmotorens kupong.
    var coupon: TipsCoupon {
        var c = TipsCoupon(playerID: memberID.uuidString, winner: winner?.uuidString, frontNine: frontNine?.uuidString,
                           mostPars: mostPars?.uuidString, birdie: birdie, over: overLine)
        TipsAnswerValue.apply(answers, to: &c)
        return c
    }
}

/// Et svar i `answers` som tåler en verdi appen ikke kjenner (blir `nil`).
private nonisolated struct TipsLenientAnswer: Decodable, Sendable {
    let value: TipsAnswerValue?

    init(from decoder: any Decoder) throws {
        value = try? TipsAnswerValue(from: decoder)
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
    /// Svarene på de nye spørsmålene. Skrives alltid (også tom), så et svar som er tatt bort, forsvinner.
    let answers: [String: TipsAnswerValue]

    init(eventID: UUID, memberID: UUID, clubID: UUID, coupon: TipsCoupon) {
        self.eventID = eventID
        self.memberID = memberID
        self.clubID = clubID
        winner = coupon.winner.flatMap(UUID.init(uuidString:))
        frontNine = coupon.frontNine.flatMap(UUID.init(uuidString:))
        mostPars = coupon.mostPars.flatMap(UUID.init(uuidString:))
        birdie = coupon.birdie
        overLine = coupon.over
        answers = TipsAnswerValue.answers(coupon)
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
        case answers
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
        try c.encode(answers, forKey: .answers)
    }

    /// Stemmer raden databasen svarte med med det som ble sendt?
    func matches(_ row: TipsRow) -> Bool {
        row.eventID == eventID && row.memberID == memberID && row.winner == winner && row.frontNine == frontNine
            && row.mostPars == mostPars && row.birdie == birdie && row.overLine == overLine && row.answers == answers
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
