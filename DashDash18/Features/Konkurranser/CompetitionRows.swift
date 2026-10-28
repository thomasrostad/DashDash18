import Foundation
import GolfgutuCore

// Radtypene fra sql/022_konkurranser.sql.

/// En cupkamp (`competition_matches`). Spillerne er påmeldte (`competition_participants.id`).
nonisolated struct CompetitionMatchRow: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let competitionID: UUID
    /// 1 = første runde.
    var roundNo: Int
    /// Plassen i runden, ovenfra (0 …).
    var slot: Int
    var playerA: UUID?
    /// Tom i første runde: bye.
    var playerB: UUID?
    var winner: UUID?
    var walkover: Bool
    /// «3&2», «2 opp» …
    var result: String?
    /// Runden kampen ble spilt i.
    var roundID: UUID?

    enum CodingKeys: String, CodingKey {
        case id
        case competitionID = "competition_id"
        case roundNo = "round_no"
        case slot
        case playerA = "player_a"
        case playerB = "player_b"
        case winner
        case walkover
        case result
        case roundID = "round_id"
    }

    static let columns = "id, competition_id, round_no, slot, player_a, player_b, winner, walkover, result, round_id"
}

/// Parametrene til `create_competition_with_entrants` (sql/022).
nonisolated struct CreateCompetitionParams: Encodable, Equatable, Sendable {
    let p_kind: String
    let p_name: String
    let p_club_id: UUID?
    let p_entry: String
    let p_rules: Ruleset
    let p_starts_on: String?
    let p_ends_on: String?
    let p_signup_open: Bool
    let p_member_ids: [UUID]
    let p_profile_ids: [UUID]
}

/// Første runde i trekningen, som `draw_cup` vil ha den.
nonisolated struct CupPairingParam: Encodable, Equatable, Sendable {
    let slot: Int
    let a: UUID
    let b: UUID?
}

/// Det `competition_invite_preview` gir (sql/022): bare navn, type, eier og antall påmeldte, og om
/// du er med selv. Med sql/060 også klubbturneringer: klubbnavnet og de ledige deltakernavnene
/// («Er du en av disse?»), tomme når du er med fra før.
nonisolated struct CompetitionInvitePreview: Decodable, Equatable, Sendable {
    /// Et ledig deltakernavn (en deltakerrad uten innlogging som er påmeldt turneringen).
    struct OpenName: Decodable, Equatable, Hashable, Identifiable, Sendable {
        let memberID: UUID
        let displayName: String

        var id: UUID { memberID }

        enum CodingKeys: String, CodingKey {
            case memberID = "member_id"
            case displayName = "display_name"
        }
    }

    let competitionID: UUID
    let name: String
    let kind: CompetitionKind
    var ownerName: String?
    let entrants: Int
    let entered: Bool
    /// Klubben turneringen hører til, eller nil for en privat.
    var clubName: String?
    var openNames: [OpenName] = []

    enum CodingKeys: String, CodingKey {
        case competitionID = "competition_id"
        case name, kind
        case ownerName = "owner_name"
        case entrants, entered
        case clubName = "club_name"
        case openNames = "open_names"
    }

    init(competitionID: UUID, name: String, kind: CompetitionKind, ownerName: String?, entrants: Int, entered: Bool,
         clubName: String? = nil, openNames: [OpenName] = []) {
        self.competitionID = competitionID
        self.name = name
        self.kind = kind
        self.ownerName = ownerName
        self.entrants = entrants
        self.entered = entered
        self.clubName = clubName
        self.openNames = openNames
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        competitionID = try c.decode(UUID.self, forKey: .competitionID)
        name = try c.decode(String.self, forKey: .name)
        kind = try c.decode(CompetitionKind.self, forKey: .kind)
        ownerName = try c.decodeIfPresent(String.self, forKey: .ownerName)
        entrants = try c.decode(Int.self, forKey: .entrants)
        entered = try c.decode(Bool.self, forKey: .entered)
        clubName = try c.decodeIfPresent(String.self, forKey: .clubName)
        openNames = try c.decodeIfPresent([OpenName].self, forKey: .openNames) ?? []
    }

    /// En klubbturnering: du blir deltaker i turneringen, ikke medlem i klubben.
    var isClub: Bool { clubName != nil }

    /// «Cup · 4 påmeldte».
    var summary: String {
        let count = entrants == 1 ? "1 påmeldt" : "\(entrants) påmeldte"
        return "\(CompetitionText.kind(kind)) · \(count)"
    }
}

/// Svaret fra `claim_competition_invite`.
nonisolated struct CompetitionClaimResult: Decodable, Equatable, Sendable {
    enum Joined: String, Decodable, Sendable {
        /// Du var påmeldt fra før.
        case already
        /// Du er påmeldt.
        case new
        /// Du hadde meldt deg av, og er påmeldt igjen.
        case rejoined
        /// Du tok et ledig deltakernavn (sql/060).
        case claimed
    }

    let competitionID: UUID
    let participantID: UUID
    let joined: Joined

    enum CodingKeys: String, CodingKey {
        case competitionID = "competition_id"
        case participantID = "participant_id"
        case joined
    }
}
