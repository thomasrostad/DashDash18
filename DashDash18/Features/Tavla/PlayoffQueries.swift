import Foundation
import Supabase

/// Nettverket for playoffen (sql/047). Uten 047 finnes ikke RPC-ene (PGRST202); da sier
/// `DataError` det, og knappene vises ikke (`RoundRulesFeature`).
enum PlayoffQueries {
    /// Turneringen bak sesongen (`competitions.season_id`). Playoffen lages på turneringen.
    static func competitionID(client: SupabaseClient, seasonID: UUID) async throws -> UUID? {
        struct Row: Decodable { let id: UUID }
        let rows: [Row] = try await client.from("competitions")
            .select("id")
            .eq("season_id", value: seasonID)
            .limit(1)
            .execute().value
        return rows.first?.id
    }

    /// `create_playoff_round`: en aktiv playoff-runde på turneringens siste kveld (klubb) eller en løs
    /// runde (uten klubb). Gir runde-id-en.
    static func create(client: SupabaseClient, competitionID: UUID, memberIDs: [UUID], holes: [Int]) async throws -> UUID {
        struct Params: Encodable {
            let p_competition_id: UUID
            let p_event_id: UUID?
            let p_member_ids: [UUID]
            let p_holes: [Int]
            let p_course_id: UUID?
        }
        struct Result: Decodable {
            let roundID: UUID
            enum CodingKeys: String, CodingKey { case roundID = "round_id" }
        }
        do {
            let result: Result = try await client.rpc("create_playoff_round", params: Params(
                p_competition_id: competitionID, p_event_id: nil, p_member_ids: memberIDs, p_holes: holes,
                p_course_id: nil)).execute().value
            return result.roundID
        } catch {
            throw mapped(error)
        }
    }

    /// `playoff_set_holes`: bytter eller forlenger hullene (hull med score står).
    static func setHoles(client: SupabaseClient, roundID: UUID, holes: [Int]) async throws {
        struct Params: Encodable {
            let p_round_id: UUID
            let p_holes: [Int]
        }
        do {
            try await client.rpc("playoff_set_holes", params: Params(p_round_id: roundID, p_holes: holes)).execute()
        } catch {
            throw mapped(error)
        }
    }

    /// Låser playoffen når den er avgjort (samme vei som en vanlig runde: status på `rounds`).
    static func lock(client: SupabaseClient, roundID: UUID) async throws {
        do {
            try await client.from("rounds").update(RoundStatusPatch(status: .locked)).eq("id", value: roundID).execute()
        } catch {
            throw DataError.from(error)
        }
    }

    /// Runden med alt under (navn, regler, bane og scorer).
    static func snapshot(client: SupabaseClient, roundID: UUID) async throws -> RoundSnapshot? {
        let rows: [RoundRow] = try await client.from("rounds")
            .select(RoundRow.columns)
            .eq("id", value: roundID)
            .execute().value
        guard let round = rows.first else { return nil }
        return try await RundeQueries.snapshot(client: client, round: round)
    }

    private static func mapped(_ error: any Error) -> DataError {
        if let postgrest = error as? PostgrestError, EveningSignupService.isMissing(postgrest) {
            return .invalid("Playoff er ikke slått på ennå.")
        }
        return DataError.from(error)
    }
}
