import Foundation
import GolfgutuCore
import Supabase

/// Spørringene for Tavla. Bare lesing. Radene gjøres om til `RoundSnapshot`, så rundene bygges
/// med samme mapping som Kveld (`RoundGame.makeRound`).
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
        async let eventRows: [EventRow] = client.from("events")
            .select(EventRow.columns)
            .eq("season_id", value: season.id)
            .execute().value
        async let memberRows: [ClubMemberRow] = client.from("club_members")
            .select(ClubMemberRow.columns)
            .eq("club_id", value: season.clubID)
            .execute().value
        let events = try await eventRows
        let members = try await memberRows
        guard !events.isEmpty else { return TavlaInput(season: season, members: members, rounds: []) }

        // Kladder ser bare arrangøren, og de teller ikke.
        let rounds: [RoundRow] = try await client.from("rounds")
            .select(RoundRow.columns)
            .in("event_id", values: events.map(\.id.uuidString))
            .in("status", values: [RoundStatus.active.rawValue, RoundStatus.locked.rawValue])
            .execute().value
        guard !rounds.isEmpty else { return TavlaInput(season: season, members: members, rounds: []) }

        let ids = rounds.map(\.id.uuidString)
        let courseIDs = Array(Set(rounds.compactMap(\.courseID))).map(\.uuidString)

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
        let scoreRows = try await scores(client: client, roundIDs: rounds.map(\.id))

        let holes = try await holeRows
        let players = try await playerRows
        let matches = try await matchRows
        let claims = try await claimRows
        let courses = try await courseRows
        let courseHoles = try await courseHoleRows

        let names = Dictionary(members.map { ($0.id, $0.displayName) }, uniquingKeysWith: { a, _ in a })
        let dates = Dictionary(events.map { ($0.id, $0.eventDate) }, uniquingKeysWith: { a, _ in a })
        let snapshots = rounds.map { round in
            var s = RoundSnapshot(round: round)
            s.roundHoles = holes.filter { $0.roundID == round.id }
            s.players = players.filter { $0.roundID == round.id }
            s.matches = matches.filter { $0.roundID == round.id }
            s.scores = scoreRows[round.id] ?? []
            s.sideClaims = claims.filter { $0.roundID == round.id }
            s.course = courses.first { $0.id == round.courseID }
            s.courseHoles = courseHoles.filter { $0.courseID == round.courseID }
            s.eventDate = round.eventID.flatMap { dates[$0] }
            s.rules = season.rules
            s.names = names
            return s
        }
        return TavlaInput(season: season, members: members, rounds: snapshots)
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
