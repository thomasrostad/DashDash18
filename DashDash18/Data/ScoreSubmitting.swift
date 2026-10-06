import Foundation
import Supabase
import SwiftUI

/// Ett hull for en bås, slik markøren lagrer det. `strokes == nil` tømmer hullet.
nonisolated struct HoleSubmission: Codable, Equatable, Sendable {
    struct Entry: Codable, Equatable, Sendable {
        let memberID: UUID
        let strokes: Int?
    }

    let roundID: UUID
    /// Rundens 0-baserte hull.
    let holeIndex: Int
    let entries: [Entry]
    /// Når hullet ble tastet på telefonen. Serveren lar ikke en eldre innsending
    /// overskrive en nyere (save_hole), så utboksen kan sende i etterkant.
    let recordedAt: Date
}

nonisolated enum SubmitOutcome: Equatable, Sendable {
    /// Lagret på serveren. Radene er det serveren har for hullet etterpå.
    case saved([HoleScoreRow])
    /// Lagt i kø (ingen kontakt). Sendes automatisk senere.
    case queued
}

/// Kontrakten mellom hullkortet (fase 5) og lagringen. Hullkortet kjenner bare denne.
/// `DirectScoreSubmitter` sender rett til serveren. Utboksen (fase 5, SwiftData) legger
/// seg utenpå og gjør at ingenting går tapt uten dekning.
protocol ScoreSubmitting: AnyObject {
    func submit(_ submission: HoleSubmission) async throws -> SubmitOutcome
    /// Hull i runden som ligger i kø og ikke er bekreftet av serveren ennå.
    func pendingHoles(roundID: UUID) -> Set<Int>
}

/// Sender et hull rett til `save_hole` (én transaksjon for hele båsen).
final class DirectScoreSubmitter: ScoreSubmitting {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func submit(_ submission: HoleSubmission) async throws -> SubmitOutcome {
        struct Score: Encodable {
            let member_id: UUID
            let strokes: Int?

            func encode(to encoder: any Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encode(member_id, forKey: .member_id)
                // Eksplisitt null tømmer hullet (save_hole ser etter et tall).
                try c.encode(strokes, forKey: .strokes)
            }

            enum CodingKeys: String, CodingKey { case member_id, strokes }
        }
        struct Params: Encodable {
            let p_round_id: UUID
            let p_hole_index: Int
            let p_scores: [Score]
            let p_recorded_at: Date
        }
        do {
            let rows: [HoleScoreRow] = try await client
                .rpc("save_hole", params: Params(
                    p_round_id: submission.roundID,
                    p_hole_index: submission.holeIndex,
                    p_scores: submission.entries.map { Score(member_id: $0.memberID, strokes: $0.strokes) },
                    p_recorded_at: submission.recordedAt
                ))
                .execute()
                .value
            return .saved(rows)
        } catch {
            throw DataError.from(error)
        }
    }

    func pendingHoles(roundID: UUID) -> Set<Int> { [] }
}

extension EnvironmentValues {
    @Entry var scoreSubmitter: (any ScoreSubmitting)?
}
