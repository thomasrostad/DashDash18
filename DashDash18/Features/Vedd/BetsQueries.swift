import Foundation
import GolfgutuCore
import Supabase

/// Spørringene for veddemålene (`sql/012_veddemaal.sql`). Lesing direkte, skriving bare via
/// RPC-ene. Kalles ikke før `BetsFeature.isEnabled` er på.
enum BetsQueries {
    private nonisolated struct CreateResult: Decodable, Sendable {
        let bet_id: UUID
    }

    /// Sesongen (aktiv, ellers sist ferdige) med runder og tropp, og veddemålene i den.
    static func load(client: SupabaseClient, clubID: UUID) async throws -> BetsInput? {
        let seasons: [SeasonRow] = try await client.from("seasons")
            .select(SeasonRow.columns)
            .eq("club_id", value: clubID)
            .in("status", values: [SeasonStatus.active.rawValue, SeasonStatus.finished.rawValue])
            .order("created_at", ascending: false)
            .execute().value
        guard let season = seasons.first(where: { $0.status == .active }) ?? seasons.first else { return nil }
        async let tavla = TavlaQueries.load(client: client, season: season)
        async let betRows: [BetRow] = client.from("bets")
            .select(BetRow.columns)
            .eq("season_id", value: season.id)
            .order("created_at", ascending: false)
            .execute().value
        let bets = try await betRows
        let stakes: [BetStakeRow] = bets.isEmpty ? [] : try await client.from("bet_stakes")
            .select(BetStakeRow.columns)
            .in("bet_id", values: bets.map(\.id.uuidString))
            .execute().value
        return BetsInput(tavla: try await tavla, bets: bets, stakes: stakes)
    }

    /// Veddemålet og første innsats i én transaksjon. Returnerer id-en.
    static func create(client: SupabaseClient, _ params: CreateBetParams) async throws -> UUID {
        let result: CreateResult = try await client.rpc("create_bet", params: params).execute().value
        return result.bet_id
    }

    static func stake(client: SupabaseClient, betID: UUID, side: BetSide, points: Int) async throws {
        try await client.rpc("place_bet_stake", params: PlaceStakeParams(p_bet_id: betID, p_side: side, p_points: points))
            .execute()
    }

    /// Arrangøren for hånd. Avvises når hun har innsats i veddemålet.
    static func resolve(client: SupabaseClient, betID: UUID, verdict: BetVerdict) async throws {
        try await client.rpc("resolve_bet", params: ResolveBetParams(p_bet_id: betID, p_resolution: verdict.rawValue))
            .execute()
    }

    /// Feiingen på arrangørens telefon: bare veddemål med vilkår, og bare når scorene kan ha gitt svar.
    static func settle(client: SupabaseClient, betID: UUID, verdict: BetVerdict) async throws {
        try await client.rpc("settle_bet", params: ResolveBetParams(p_bet_id: betID, p_resolution: verdict.rawValue))
            .execute()
    }
}
