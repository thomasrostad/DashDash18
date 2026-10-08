import Foundation
import GolfgutuCore
import Supabase

/// Spørringene for tippekupongen. Låsen og «andres tips først etter låsing» håndheves av
/// databasen (RLS og `tips_open`); appen sjekker radene den får tilbake.
enum TipsQueries {
    private nonisolated struct EventParam: Encodable, Sendable { let p_event_id: UUID }

    /// Kvelden med alt kupongen trenger.
    static func load(client: SupabaseClient, eventID: UUID) async throws -> TipsInput {
        let events: [TipsEventRow] = try await client.from("events")
            .select(TipsEventRow.columns)
            .eq("id", value: eventID)
            .execute().value
        guard let event = events.first else { throw DataError.invalid("Fant ikke kvelden.") }

        async let memberRows: [ClubMemberRow] = client.from("club_members")
            .select(ClubMemberRow.columns)
            .eq("club_id", value: event.clubID)
            .execute().value
        async let signupRows: [SignupRow] = client.from("signups")
            .select(SignupRow.columns)
            .eq("event_id", value: eventID)
            .execute().value
        async let couponRows: [TipsRow] = client.from("tips")
            .select(TipsRow.columns)
            .eq("event_id", value: eventID)
            .order("member_id")
            .execute().value
        async let submittedRows: [TipsSubmittedRow] = client
            .rpc("tips_submitted", params: EventParam(p_event_id: eventID))
            .execute().value
        async let deadlineText: String? = client
            .rpc("tips_deadline", params: EventParam(p_event_id: eventID))
            .execute().value
        async let open: Bool? = client
            .rpc("tips_open", params: EventParam(p_event_id: eventID))
            .execute().value
        async let rules = RundeQueries.rules(client: client, clubID: event.clubID, seasonID: event.seasonID)
        async let rounds = snapshots(client: client, event: event)

        let members = try await memberRows
        var input = TipsInput(event: event)
        input.rules = try await rules
        input.members = members
        input.signups = try await signupRows
        input.coupons = try await couponRows
        input.submitted = try await submittedRows
        input.serverDeadline = try await deadlineText.flatMap(parseTimestamp)
        input.serverOpen = try await open
        let names = Dictionary(members.map { ($0.id, $0.displayName) }, uniquingKeysWith: { a, _ in a })
        input.rounds = try await rounds.map { s in
            var s = s
            s.names = names
            s.rules = input.rules
            return s
        }
        return input
    }

    /// Kveldens runder (kladder bare for arrangøren, via RLS), i opprettelsesrekkefølge.
    private static func snapshots(client: SupabaseClient, event: TipsEventRow) async throws -> [RoundSnapshot] {
        let rounds: [RoundRow] = try await client.from("rounds")
            .select(RoundRow.columns)
            .eq("event_id", value: event.id)
            .order("round_no")
            .execute().value
        guard !rounds.isEmpty else { return [] }
        let ids = rounds.map(\.id.uuidString)
        let courseIDs = Array(Set(rounds.compactMap(\.courseID))).map(\.uuidString)

        async let holeRows: [RoundHoleRow] = client.from("round_holes")
            .select(RoundHoleRow.columns)
            .in("round_id", values: ids).execute().value
        async let playerRows: [RoundPlayerRow] = client.from("round_players")
            .select(RoundPlayerRow.columns)
            .in("round_id", values: ids).execute().value
        // Scorene per runde, så svaret aldri når PostgREST-grensen på 1000 rader.
        async let scoreRows = scores(client: client, roundIDs: rounds.map(\.id))
        async let courseRows: [CourseRow] = courseIDs.isEmpty ? [] : client.from("courses")
            .select(CourseRow.columns)
            .in("id", values: courseIDs).execute().value
        async let courseHoleRows: [CourseHoleRecord] = courseIDs.isEmpty ? [] : client.from("course_holes")
            .select(CourseHoleRecord.columns)
            .in("course_id", values: courseIDs).execute().value

        let holes = try await holeRows
        let players = try await playerRows
        let scores = try await scoreRows
        let courses = try await courseRows
        let courseHoles = try await courseHoleRows
        return rounds.map { round in
            var s = RoundSnapshot(round: round)
            s.roundHoles = holes.filter { $0.roundID == round.id }
            s.players = players.filter { $0.roundID == round.id }
            s.scores = scores[round.id] ?? []
            s.course = courses.first { $0.id == round.courseID }
            s.courseHoles = courseHoles.filter { $0.courseID == round.courseID }
            s.eventDate = event.eventDate
            return s
        }
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

    // MARK: Skriving

    /// Leverer eller endrer kupongen (én rad per kveld og medlem). Sjekker raden tilbake:
    /// er kupongen låst, avviser databasen (42501) eller svarer uten rad.
    static func save(client: SupabaseClient, _ row: TipsUpsert) async throws -> TipsRow {
        let saved: [TipsRow] = try await client.from("tips")
            .upsert(row, onConflict: "event_id,member_id")
            .select(TipsRow.columns)
            .execute().value
        guard let mine = saved.first, row.matches(mine) else { throw DataError.notAllowed }
        return mine
    }

    /// Trekker kupongen. Sjekker at raden faktisk ble slettet.
    static func withdraw(client: SupabaseClient, eventID: UUID, memberID: UUID) async throws {
        let rows: [TipsRow] = try await client.from("tips")
            .delete()
            .eq("event_id", value: eventID)
            .eq("member_id", value: memberID)
            .select(TipsRow.columns)
            .execute().value
        guard !rows.isEmpty else { throw DataError.notAllowed }
    }

    /// Arrangøren: innsats og linje for kvelden. Står fast når første kupong er levert (55000).
    static func saveSettings(client: SupabaseClient, eventID: UUID, _ update: TipsSettingsUpdate) async throws -> TipsEventRow {
        let rows: [TipsEventRow] = try await client.from("events")
            .update(update)
            .eq("id", value: eventID)
            .select(TipsEventRow.columns)
            .execute().value
        guard let row = rows.first, row.stakePoints == update.stakePoints, row.line == update.line else {
            throw DataError.notAllowed
        }
        return row
    }

    // MARK: Hjelpere

    /// `timestamptz` som Postgres skriver det (`2026-10-08T15:00:00+00:00`, ev. med brøkdeler).
    nonisolated static func parseTimestamp(_ text: String) -> Date? {
        let plain = ISO8601DateFormatter()
        if let d = plain.date(from: text) { return d }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = fractional.date(from: text) { return d }
        // «2026-10-08 15:00:00+00» (mellomrom og kort sone).
        var t = text.replacingOccurrences(of: " ", with: "T")
        if t.range(of: #"[+-]\d{2}$"#, options: .regularExpression) != nil { t += ":00" }
        return plain.date(from: t) ?? fractional.date(from: t)
    }
}
