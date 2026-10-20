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
    /// Innsendingene som ligger i kø for runden, eldst først. Runde-skjermen legger dem oppå
    /// serverens tall, så hullene står også etter at appen er startet på nytt.
    func pendingSubmissions(roundID: UUID) -> [HoleSubmission]
    /// Hull i runden som lå i kø og ble avvist av serveren (runden låst, ingen tilgang). Tallene
    /// står ikke på kortet, så føringen sier fra til de er sett.
    func rejectedHoles(roundID: UUID) -> [RejectedHole]
    /// Føringen har sagt fra: glem de avviste hullene i runden (alle, eller bare `holes`).
    func acknowledgeRejected(roundID: UUID, holes: Set<Int>?)
}

extension ScoreSubmitting {
    func pendingSubmissions(roundID: UUID) -> [HoleSubmission] { [] }
    func rejectedHoles(roundID: UUID) -> [RejectedHole] { [] }
    func acknowledgeRejected(roundID: UUID, holes: Set<Int>?) {}
    func acknowledgeRejected(roundID: UUID) { acknowledgeRejected(roundID: roundID, holes: nil) }
}

/// Et hull serveren avviste, med grunnen slik den ble vist (`DataError.message`).
nonisolated struct RejectedHole: Equatable, Sendable {
    let holeIndex: Int
    let message: String
}

nonisolated enum RejectedHoles {
    /// Stripa i føringen: «Hull 7, 8 og 9 ble ikke lagret: Runden er låst. Tallene står ikke på kortet.
    /// Før dem på nytt, eller si fra til arrangøren.» Grunnen er den første. nil uten avviste hull.
    static func text(_ holes: [RejectedHole], holeNumber: (Int) -> Int) -> String? {
        let sorted = holes.sorted { $0.holeIndex < $1.holeIndex }
        guard let first = sorted.first else { return nil }
        let numbers = Array(Set(sorted.map(\.holeIndex))).sorted().map { String(holeNumber($0)) }
        let list = numbers.count == 1 ? numbers[0]
            : numbers.dropLast().joined(separator: ", ") + " og " + numbers.last!
        var reason = first.message.trimmingCharacters(in: .whitespaces)
        if let last = reason.last, !".!?".contains(last) { reason += "." }
        return "Hull \(list) ble ikke lagret: \(reason) Tallene står ikke på kortet. Før dem på nytt, eller si fra til arrangøren."
    }
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
