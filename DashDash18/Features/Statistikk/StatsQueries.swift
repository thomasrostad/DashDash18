import Foundation
import GolfgutuCore
import Supabase

/// Hvem statistikken gjelder.
nonisolated enum StatsScope: Equatable, Hashable, Sendable {
    /// Deg: alle klubbene dine og, med fundamentet (sql/017), løse runder med profilen din.
    case me(userID: UUID, memberIDs: [UUID], clubNames: [UUID: String])
    /// En spiller i klubben (fra spillerprofilen på Tavla): bare klubbens runder.
    case member(memberID: UUID, clubID: UUID, clubName: String)

    var includesLoose: Bool {
        if case .me = self { return FoundationFeature.isEnabled }
        return false
    }
}

/// Spørringene for statistikken. Bare lesing. RLS avgjør hva som kommer tilbake.
enum StatsQueries {
    /// Runder per spørring for scorer og føring: 18 hull × 40 runder holder seg under
    /// PostgREST-grensen på 1000 rader.
    nonisolated static let roundsPerChunk = 40

    static func load(client: SupabaseClient, scope: StatsScope) async throws -> StatsInput {
        var input = StatsInput()
        var players: [StatsPlayerRow] = []
        switch scope {
        case .me(let userID, let memberIDs, let names):
            input.clubNames = names
            if !memberIDs.isEmpty {
                players += try await playerRows(client: client, memberIDs: memberIDs)
            }
            if scope.includesLoose {
                let mine: [RoundParticipantRow] = try await client.from("round_participants")
                    .select("id, round_id, profile_id, display_name, handicap_index")
                    .eq("profile_id", value: userID)
                    .execute().value
                if !mine.isEmpty {
                    players += try await playerRows(client: client, memberIDs: mine.map(\.id))
                }
            }
        case .member(let memberID, let clubID, let name):
            input.clubNames = [clubID: name]
            players = try await playerRows(client: client, memberIDs: [memberID])
        }
        guard !players.isEmpty else { return input }

        var rounds: [StatsRoundRow] = []
        for chunk in chunked(Array(Set(players.map(\.roundID)))) {
            rounds += try await client.from("rounds")
                .select(StatsRoundRow.columns)
                .in("id", values: chunk.map(\.uuidString))
                .in("status", values: [RoundStatus.active.rawValue, RoundStatus.locked.rawValue])
                .execute().value
        }
        if case .member(_, let clubID, _) = scope {
            rounds = rounds.filter { $0.clubID == clubID }
        }
        guard !rounds.isEmpty else { return input }
        input.rounds = rounds
        let roundIDs = Set(rounds.map(\.id))
        input.players = players.filter { roundIDs.contains($0.roundID) }
        let memberIDs = Array(Set(input.players.map(\.memberID))).map(\.uuidString)

        let eventIDs = Array(Set(rounds.compactMap(\.eventID))).map(\.uuidString)
        let courseIDs = Array(Set(rounds.compactMap(\.courseID))).map(\.uuidString)
        async let eventRows: [StatsEventRow] = eventIDs.isEmpty ? [] : client.from("events")
            .select("id, event_date, season_id")
            .in("id", values: eventIDs).execute().value
        async let courseRows: [StatsCourseRow] = courseIDs.isEmpty ? [] : client.from("courses")
            .select(StatsCourseRow.columns)
            .in("id", values: courseIDs).execute().value
        async let courseHoleRows: [CourseHoleRecord] = courseIDs.isEmpty ? [] : client.from("course_holes")
            .select("course_id, hole_number, par, stroke_index, length_m")
            .in("course_id", values: courseIDs).execute().value

        for chunk in chunked(Array(roundIDs)) {
            let ids = chunk.map(\.uuidString)
            async let holes: [RoundHoleRow] = client.from("round_holes")
                .select("round_id, hole_index, par, stroke_index, length_m")
                .in("round_id", values: ids).execute().value
            async let scores: [HoleScoreRow] = client.from("hole_scores")
                .select(RundeQueries.scoreColumns)
                .in("round_id", values: ids).in("member_id", values: memberIDs).execute().value
            async let details: [HoleStatRow] = client.from("hole_stats")
                .select(HoleStatRow.columns)
                .in("round_id", values: ids).in("member_id", values: memberIDs).execute().value
            input.roundHoles += try await holes
            input.scores += try await scores
            input.details += try await details
        }

        let events = try await eventRows
        input.courses = try await courseRows
        input.courseHoles = try await courseHoleRows
        input.eventDates = Dictionary(events.map { ($0.id, $0.eventDate) }, uniquingKeysWith: { a, _ in a })

        let seasonIDs = Array(Set(events.compactMap(\.seasonID))).map(\.uuidString)
        if !seasonIDs.isEmpty {
            let seasons: [SeasonRow] = try await client.from("seasons")
                .select(TavlaQueries.seasonColumns)
                .in("id", values: seasonIDs).execute().value
            let rules = Dictionary(seasons.map { ($0.id, $0.rules) }, uniquingKeysWith: { a, _ in a })
            for e in events {
                if let s = e.seasonID, let r = rules[s] { input.eventRules[e.id] = r }
            }
        }
        return input
    }

    private static func playerRows(client: SupabaseClient, memberIDs: [UUID]) async throws -> [StatsPlayerRow] {
        try await client.from("round_players")
            .select(StatsPlayerRow.columns)
            .in("member_id", values: memberIDs.map(\.uuidString))
            .execute().value
    }

    nonisolated static func chunked(_ ids: [UUID], size: Int = roundsPerChunk) -> [[UUID]] {
        stride(from: 0, to: ids.count, by: size).map { Array(ids[$0..<min($0 + size, ids.count)]) }
    }

    // MARK: Føring per hull

    /// Spillerens føring i runden (alle hull).
    static func details(client: SupabaseClient, roundID: UUID, memberID: UUID) async throws -> [HoleStatRow] {
        try await client.from("hole_stats")
            .select(HoleStatRow.columns)
            .eq("round_id", value: roundID)
            .eq("member_id", value: memberID)
            .execute().value
    }

    /// Lagrer føringen for ett hull. Tom føring sletter raden (databasen tar ikke tomme rader).
    static func save(client: SupabaseClient, row: HoleStatRow) async throws {
        if row.detail.isEmpty {
            try await client.from("hole_stats")
                .delete()
                .eq("round_id", value: row.roundID)
                .eq("member_id", value: row.memberID)
                .eq("hole_index", value: row.holeIndex)
                .execute()
        } else {
            try await client.from("hole_stats")
                .upsert(row, onConflict: "round_id,member_id,hole_index")
                .execute()
        }
    }
}

/// Kveldens dato og sesong.
nonisolated struct StatsEventRow: Codable, Equatable, Sendable {
    let id: UUID
    var eventDate: String
    var seasonID: UUID?

    enum CodingKeys: String, CodingKey {
        case id
        case eventDate = "event_date"
        case seasonID = "season_id"
    }
}
