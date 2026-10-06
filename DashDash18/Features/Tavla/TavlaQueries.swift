import Foundation
import GolfgutuCore
import Supabase

/// Spørringene for Tavla. Bare lesing. Radene gjøres om til `RoundSnapshot`, så rundene bygges
/// med samme mapping som Kveld (`RoundGame.makeRound`).
enum TavlaQueries {
    static let seasonColumns = "id, club_id, name, status, rules"

    /// Den aktive sesongen, ellers den sist opprettede ferdige. Nil når ingen finnes.
    static func load(client: SupabaseClient, clubID: UUID) async throws -> TavlaInput? {
        let seasons: [SeasonRow] = try await client.from("seasons")
            .select(seasonColumns)
            .eq("club_id", value: clubID)
            .in("status", values: [SeasonStatus.active.rawValue, SeasonStatus.finished.rawValue])
            .order("created_at", ascending: false)
            .execute().value
        guard let season = seasons.first(where: { $0.status == .active }) ?? seasons.first else { return nil }
        return try await load(client: client, season: season)
    }

    static func load(client: SupabaseClient, season: SeasonRow) async throws -> TavlaInput {
        async let eventRows: [EventRow] = client.from("events")
            .select("id, club_id, season_id, event_date, start_time, venue, note")
            .eq("season_id", value: season.id)
            .execute().value
        async let memberRows: [ClubMemberRow] = client.from("club_members")
            .select(KveldQueries.memberColumns)
            .eq("club_id", value: season.clubID)
            .execute().value
        let events = try await eventRows
        let members = try await memberRows
        guard !events.isEmpty else { return TavlaInput(season: season, members: members, rounds: []) }

        // Kladder ser bare arrangøren, og de teller ikke.
        let rounds: [RoundRow] = try await client.from("rounds")
            .select(RundeQueries.roundColumns)
            .in("event_id", values: events.map(\.id.uuidString))
            .in("status", values: [RoundStatus.active.rawValue, RoundStatus.locked.rawValue])
            .execute().value
        guard !rounds.isEmpty else { return TavlaInput(season: season, members: members, rounds: []) }

        let ids = rounds.map(\.id.uuidString)
        let courseIDs = Array(Set(rounds.compactMap(\.courseID))).map(\.uuidString)

        async let holeRows: [RoundHoleRow] = client.from("round_holes")
            .select("round_id, hole_index, par, stroke_index, length_m")
            .in("round_id", values: ids).execute().value
        async let playerRows: [RoundPlayerRow] = client.from("round_players")
            .select(RundeQueries.playerColumns)
            .in("round_id", values: ids).execute().value
        async let matchRows: [RoundMatchRow] = client.from("round_matches")
            .select("round_id, match_no, player_a, player_b, player_c, team_a, team_b, result")
            .in("round_id", values: ids).execute().value
        async let claimRows: [SideClaimRow] = client.from("side_claims")
            .select(RundeQueries.claimColumns)
            .in("round_id", values: ids).execute().value
        async let courseRows: [CourseRow] = courseIDs.isEmpty ? [] : client.from("courses")
            .select("id, club_id, name, external_name, course_rating, slope_rating, in_use, confirmed_by, confirmed_at")
            .in("id", values: courseIDs).execute().value
        async let courseHoleRows: [CourseHoleRecord] = courseIDs.isEmpty ? [] : client.from("course_holes")
            .select("course_id, hole_number, par, stroke_index, length_m")
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
            s.eventDate = dates[round.eventID]
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
                        .select(RundeQueries.scoreColumns)
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
