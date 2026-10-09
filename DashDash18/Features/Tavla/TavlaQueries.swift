import Foundation
import GolfgutuCore
import Supabase

/// Spørringene for Tavla. Bare lesing. Radene samles i `TavlaData` og gjøres om til `RoundSnapshot`,
/// så rundene bygges med samme mapping som Kveld (`RoundGame.makeRound`).
enum TavlaQueries {
    /// Den aktive sesongen, ellers den sist opprettede ferdige. Nil når ingen finnes.
    static func load(client: SupabaseClient, clubID: UUID) async throws -> TavlaInput? {
        let seasons: [SeasonRow] = try await client.from("seasons")
            .select(SeasonRow.columns)
            .eq("club_id", value: clubID)
            .in("status", values: [SeasonStatus.active.rawValue, SeasonStatus.finished.rawValue])
            .order("created_at", ascending: false)
            .execute().value
        guard let season = seasons.first(where: { $0.status == .active }) ?? seasons.first else { return nil }
        return try await load(client: client, season: season)
    }

    static func load(client: SupabaseClient, season: SeasonRow) async throws -> TavlaInput {
        if TavlaRPCFeature.isEnabled, let data = try await rpc(client: client, seasonID: season.id) {
            return data.input(season: season)
        }
        return try await tables(client: client, season: season).input(season: season)
    }

    /// Alt i ett kall (`sql/036`). Nil når funksjonen ikke gir svar for deg (ikke medlem i klubben,
    /// P0002) eller ikke finnes ennå (PGRST202): da hentes det som før, og RLS avgjør.
    static func rpc(client: SupabaseClient, seasonID: UUID) async throws -> TavlaData? {
        struct Params: Encodable { let p_season_id: UUID }
        do {
            return try await client.rpc("tavla_data", params: Params(p_season_id: seasonID)).execute().value
        } catch let error as PostgrestError where ["P0002", "PGRST202"].contains(error.code ?? "") {
            return nil
        }
    }

    /// Én spørring per tabell og én per runde for scorene. RLS sjekker hver rad.
    static func tables(client: SupabaseClient, season: SeasonRow) async throws -> TavlaData {
        async let eventRows: [EventRow] = client.from("events")
            .select(EventRow.columns)
            .eq("season_id", value: season.id)
            .execute().value
        async let memberRows: [ClubMemberRow] = client.from("club_members")
            .select(ClubMemberRow.columns)
            .eq("club_id", value: season.clubID)
            .execute().value
        var data = TavlaData(events: try await eventRows, members: try await memberRows)
        guard !data.events.isEmpty else { return data }

        // Kladder ser bare arrangøren, og de teller ikke.
        data.rounds = try await client.from("rounds")
            .select(RoundRow.columns)
            .in("event_id", values: data.events.map(\.id.uuidString))
            .in("status", values: [RoundStatus.active.rawValue, RoundStatus.locked.rawValue])
            .execute().value
        guard !data.rounds.isEmpty else { return data }

        let ids = data.rounds.map(\.id.uuidString)
        let courseIDs = Array(Set(data.rounds.compactMap(\.courseID))).map(\.uuidString)

        async let holeRows: [RoundHoleRow] = client.from("round_holes")
            .select(RoundHoleRow.columns)
            .in("round_id", values: ids).execute().value
        async let playerRows: [RoundPlayerRow] = client.from("round_players")
            .select(RoundPlayerRow.columns)
            .in("round_id", values: ids).execute().value
        async let matchRows: [RoundMatchRow] = client.from("round_matches")
            .select(RoundMatchRow.columns)
            .in("round_id", values: ids).execute().value
        async let claimRows: [SideClaimRow] = client.from("side_claims")
            .select(SideClaimRow.columns)
            .in("round_id", values: ids).execute().value
        async let courseRows: [CourseRow] = courseIDs.isEmpty ? [] : client.from("courses")
            .select(CourseRow.columns)
            .in("id", values: courseIDs).execute().value
        async let courseHoleRows: [CourseHoleRecord] = courseIDs.isEmpty ? [] : client.from("course_holes")
            .select(CourseHoleRecord.columns)
            .in("course_id", values: courseIDs).execute().value
        // Scorene per runde: en hel sesong kan gå over PostgREST-grensen på 1000 rader i ett svar.
        let scoreRows = try await scores(client: client, roundIDs: data.rounds.map(\.id))

        data.roundHoles = try await holeRows
        data.players = try await playerRows
        data.matches = try await matchRows
        data.claims = try await claimRows
        data.courses = try await courseRows
        data.courseHoles = try await courseHoleRows
        data.scores = data.rounds.flatMap { scoreRows[$0.id] ?? [] }
        return data
    }

    private static func scores(client: SupabaseClient, roundIDs: [UUID]) async throws -> [UUID: [HoleScoreRow]] {
        try await withThrowingTaskGroup(of: (UUID, [HoleScoreRow]).self) { group in
            for id in roundIDs {
                group.addTask {
                    let rows: [HoleScoreRow] = try await client.from("hole_scores")
                        .select(HoleScoreRow.columns)
                        .eq("round_id", value: id)
                        .execute().value
                    return (id, rows)
                }
            }
            var out: [UUID: [HoleScoreRow]] = [:]
            for try await (id, rows) in group { out[id] = rows }
            return out
        }
    }
}
