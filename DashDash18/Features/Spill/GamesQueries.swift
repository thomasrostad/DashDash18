import Foundation
import GolfgutuCore
import Supabase

/// Spørringene for spill på runden (`sql/020_spill.sql`). Lesing direkte (RLS via deltakelse),
/// skriving bare via RPC-ene. Kalles ikke før `GamesFeature.isEnabled` er på.
enum GamesQueries {
    /// Spillene i runden med deltakere, markeringer og oppgjør.
    static func load(client: SupabaseClient, roundID: UUID) async throws -> GamesInput {
        let games: [RoundGameRow] = try await client.from("round_games")
            .select(RoundGameRow.columns)
            .eq("round_id", value: roundID)
            .order("created_at", ascending: true)
            .execute().value
        guard !games.isEmpty else { return GamesInput() }
        async let players: [RoundGamePlayerRow] = client.from("round_game_players")
            .select(RoundGamePlayerRow.columns)
            .eq("round_id", value: roundID)
            .execute().value
        async let marks: [RoundGameMarkRow] = client.from("round_game_marks")
            .select(RoundGameMarkRow.columns)
            .eq("round_id", value: roundID)
            .execute().value
        async let results: [RoundGameResultRow] = client.from("round_game_results")
            .select(RoundGameResultRow.columns)
            .eq("round_id", value: roundID)
            .execute().value
        return GamesInput(games: games, players: try await players, marks: try await marks,
                          results: try await results)
    }

    /// Spillet og deltakerne i én transaksjon. Returnerer id-en.
    static func create(client: SupabaseClient, _ params: CreateRoundGameParams) async throws -> UUID {
        try await client.rpc("create_round_game", params: params).execute().value
    }

    static func delete(client: SupabaseClient, gameID: UUID) async throws {
        try await client.rpc("delete_round_game", params: GameIDParams(p_game_id: gameID)).execute()
    }

    /// Markering på et hull. Spiller og modus tomme: markeringen fjernes.
    static func setMark(client: SupabaseClient, _ params: GameMarkParams) async throws {
        try await client.rpc("set_round_game_mark", params: params).execute()
    }

    /// Oppgjøret i hele poeng (summen null) når runden er ferdig.
    static func settle(client: SupabaseClient, gameID: UUID, points: [UUID: Int]) async throws {
        try await client.rpc("settle_round_game", params: SettleGameParams(gameID: gameID, points: points)).execute()
    }
}
