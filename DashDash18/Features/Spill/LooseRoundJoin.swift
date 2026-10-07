import Foundation
import GolfgutuCore

/// Det `round_invite_preview` gir (sql/018): runden bak en kode, med deltakerne og gjesteplassene.
nonisolated struct InvitePreview: Decodable, Equatable, Sendable {
    struct Player: Decodable, Equatable, Identifiable, Sendable {
        let participantID: UUID
        let displayName: String
        let isGuest: Bool

        var id: UUID { participantID }

        enum CodingKeys: String, CodingKey {
            case participantID = "participant_id"
            case displayName = "display_name"
            case isGuest = "is_guest"
        }
    }

    let roundID: UUID
    let status: RoundStatus
    let holeCount: Int
    let firstHole: Int
    let format: String
    var venue: String?
    var courseName: String?
    var ownerName: String?
    /// Plassen din, når du er med fra før.
    var myParticipantID: UUID?
    let players: [Player]

    enum CodingKeys: String, CodingKey {
        case roundID = "round_id"
        case status
        case holeCount = "hole_count"
        case firstHole = "first_hole"
        case format, venue
        case courseName = "course_name"
        case ownerName = "owner_name"
        case myParticipantID = "my_participant_id"
        case players
    }

    /// «18 hull · Stableford (netto)» (banen står som overskrift).
    var summary: String {
        var parts: [String] = []
        parts.append(firstHole == 10 ? "hull 10–18" : "\(holeCount) hull")
        parts.append(CompetitionForm.form(id: format).name)
        return parts.joined(separator: " · ")
    }
}

/// Svaret fra `claim_round_invite`.
nonisolated struct ClaimResult: Decodable, Equatable, Sendable {
    enum Joined: String, Decodable, Sendable {
        /// Du var med fra før.
        case already
        /// Du tok en gjesteplass.
        case guest
        /// Du ble lagt til som ny deltaker.
        case new
    }

    let roundID: UUID
    let participantID: UUID
    let joined: Joined

    enum CodingKeys: String, CodingKey {
        case roundID = "round_id"
        case participantID = "participant_id"
        case joined
    }

    var message: String {
        switch joined {
        case .already: "Du er med i runden."
        case .guest: "Plassen er din. Scorene som er ført, følger med."
        case .new: "Du er med i runden."
        }
    }
}

/// «Er du X?»: valgene når du åpner en invitasjon. Gjesteplassene (uten profil) kan tas, eller du
/// blir med som ny. Er du med fra før, er det bare å åpne runden.
nonisolated enum JoinChoice: Equatable, Hashable, Sendable {
    case alreadyIn(UUID)
    /// Ta gjesteplassen.
    case guest(UUID)
    case newPlayer

    static func options(_ preview: InvitePreview) -> [JoinChoice] {
        if let mine = preview.myParticipantID { return [.alreadyIn(mine)] }
        return preview.players.filter(\.isGuest).map { .guest($0.participantID) } + [.newPlayer]
    }

    /// Forslaget: plassen din, ellers gjesten som heter det samme som deg, ellers ny.
    static func suggested(_ preview: InvitePreview, myName: String?) -> JoinChoice {
        if let mine = preview.myParticipantID { return .alreadyIn(mine) }
        let key = Self.key(myName)
        if !key.isEmpty, let match = preview.players.first(where: { $0.isGuest && Self.key($0.displayName) == key }) {
            return .guest(match.participantID)
        }
        return .newPlayer
    }

    /// Plassen som sendes til `claim_round_invite` (nil = ny deltaker eller med fra før).
    var participantID: UUID? {
        if case .guest(let id) = self { return id }
        return nil
    }

    /// Teksten på valget: «Ja, jeg er Per», «Nei, bli med som ny».
    func title(in preview: InvitePreview) -> String {
        switch self {
        case .alreadyIn: return "Du er med i runden"
        case .guest(let id):
            let name = preview.players.first { $0.participantID == id }?.displayName ?? "gjesten"
            return "Jeg er \(name)"
        case .newPlayer: return "Bli med som ny spiller"
        }
    }

    private static func key(_ name: String?) -> String {
        (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
