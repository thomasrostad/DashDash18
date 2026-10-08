import Foundation
import GolfgutuCore
import Supabase

/// Nettverket for løse runder (sql/017 og 018). Brukes bare når `LooseRoundsFeature` er på.
/// Flere rader skrives alltid i én RPC; det som kommer tilbake, sjekkes.
enum LooseRoundQueries {
    /// Brukes fortsatt i Konkurranser/. Ny kode bruker `RoundRosterRow.columns` og `ProfileRow.columns`.
    static let rosterColumns = RoundRosterRow.columns
    static let profileColumns = ProfileRow.columns

    // MARK: Profil og venner

    /// Profilen din, laget eller fylt fra klubben ved første kall (`ensure_profile`, 017).
    static func ensureProfile(client: SupabaseClient) async throws -> ProfileRow {
        try await client.rpc("ensure_profile").execute().value
    }

    /// Folk du kan legge til: profilene RLS lar deg se (felles klubb, runde eller konkurranse),
    /// uten deg selv, i norsk navnerekkefølge. Det finnes ikke noe søk etter fremmede.
    static func friends(client: SupabaseClient, userID: UUID) async throws -> [ProfileRow] {
        let rows: [ProfileRow] = try await client.from("profiles")
            .select(ProfileRow.columns)
            .neq("id", value: userID)
            .execute().value
        return rows
            .filter { !($0.displayName ?? "").trimmingCharacters(in: .whitespaces).isEmpty }
            .sorted { NorwegianSort.areInIncreasingOrder($0.displayName ?? "", $1.displayName ?? "") }
    }

    // MARK: Runden

    /// Ny runde med alt oppsettet, startet (`start_loose_round`). Gir rundens id.
    static func start(client: SupabaseClient, _ setup: LooseRoundStart) async throws -> UUID {
        struct Params: Encodable { let p_setup: LooseRoundStart }
        struct Answer: Decodable {
            let roundID: UUID
            enum CodingKeys: String, CodingKey { case roundID = "round_id" }
        }
        let answer: Answer = try await client.rpc("start_loose_round", params: Params(p_setup: setup)).execute().value
        return answer.roundID
    }

    /// Teen du brukte sist på banen i en løs runde (sql/029), eller nil.
    static func previousTeeID(client: SupabaseClient, courseID: UUID, userID: UUID) async throws -> UUID? {
        guard SlopeNoFeature.isEnabled else { return nil }
        struct Row: Decodable {
            let teeID: UUID?
            enum CodingKeys: String, CodingKey { case teeID = "tee_id" }
        }
        let rows: [Row] = try await client.from("rounds")
            .select("tee_id")
            .eq("course_id", value: courseID)
            .eq("owner_id", value: userID)
            .is("club_id", value: nil)
            .not("tee_id", operator: .is, value: "null")
            .order("created_at", ascending: false)
            .limit(1)
            .execute().value
        return rows.first?.teeID
    }

    /// Runden med alt under, eller nil når du ikke kan se den (lenger).
    static func snapshot(client: SupabaseClient, roundID: UUID) async throws -> RoundSnapshot? {
        let rows: [RoundRow] = try await client.from("rounds")
            .select(RoundRow.columns)
            .eq("id", value: roundID)
            .is("club_id", value: nil)
            .limit(1)
            .execute().value
        guard let round = rows.first else { return nil }
        return try await RundeQueries.looseSnapshot(client: client, round: round)
    }

    /// «Avslutt runden» (`finish_loose_round`): bare eieren. Koden slettes.
    static func finish(client: SupabaseClient, roundID: UUID) async throws {
        struct Params: Encodable { let p_round_id: UUID }
        _ = try await client.rpc("finish_loose_round", params: Params(p_round_id: roundID)).execute()
    }

    // MARK: Invitasjon

    struct Invite: Decodable, Equatable, Sendable {
        let code: String
        let expiresAt: Date

        enum CodingKeys: String, CodingKey {
            case code
            case expiresAt = "expires_at"
        }
    }

    /// Koden til runden (`loose_round_invite`): den som finnes, eller en ny.
    static func invite(client: SupabaseClient, roundID: UUID) async throws -> InviteCode {
        struct Params: Encodable { let p_round_id: UUID }
        let invite: Invite = try await client.rpc("loose_round_invite", params: Params(p_round_id: roundID))
            .execute().value
        guard let code = InviteCode(invite.code) else { throw DataError.invalid("Serveren ga en ugyldig kode.") }
        return code
    }

    static func preview(client: SupabaseClient, code: InviteCode) async throws -> InvitePreview {
        struct Params: Encodable { let p_code: String }
        return try await client.rpc("round_invite_preview", params: Params(p_code: code.value)).execute().value
    }

    /// Bli med (`claim_round_invite`): ta en gjesteplass, eller bli med som ny. Én transaksjon.
    static func claim(client: SupabaseClient, code: InviteCode, participantID: UUID?) async throws -> ClaimResult {
        struct Params: Encodable {
            let p_code: String
            let p_participant_id: UUID?

            func encode(to encoder: any Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encode(p_code, forKey: .p_code)
                try c.encode(p_participant_id, forKey: .p_participant_id)
            }

            enum CodingKeys: String, CodingKey { case p_code, p_participant_id }
        }
        return try await client.rpc("claim_round_invite", params: Params(p_code: code.value, p_participant_id: participantID))
            .execute().value
    }

    // MARK: Mine runder

    /// Dine løse runder (eier eller med), nyeste først, med det som trengs for resultatet. Henter
    /// alt i noen få spørringer for hele lista, ikke én runde om gangen.
    static func myRounds(client: SupabaseClient, limit: Int = 40) async throws -> [RoundSnapshot] {
        let rows: [LooseRoundRecord] = try await client.from("rounds")
            .select(RoundRow.columns + ", owner_id")
            .is("club_id", value: nil)
            .neq("status", value: RoundStatus.draft.rawValue)
            .order("started_at", ascending: false)
            .limit(limit)
            .execute().value
        guard !rows.isEmpty else { return [] }
        let ids = rows.map(\.round.id.uuidString)
        let courseIDs = Array(Set(rows.compactMap(\.round.courseID))).map(\.uuidString)

        async let players: [RoundPlayerRow] = client.from("round_players")
            .select(RoundPlayerRow.columns).in("round_id", values: ids).execute().value
        async let scores: [HoleScoreRow] = client.from("hole_scores")
            .select(HoleScoreRow.columns).in("round_id", values: ids).execute().value
        async let matches: [RoundMatchRow] = client.from("round_matches")
            .select(RoundMatchRow.columns)
            .in("round_id", values: ids).execute().value
        async let holes: [RoundHoleRow] = client.from("round_holes")
            .select(RoundHoleRow.columns).in("round_id", values: ids).execute().value
        async let roster: [RoundRosterRow] = client.from("round_roster")
            .select(RoundRosterRow.columns).in("round_id", values: ids).execute().value
        async let courses: [CourseRow] = client.from("courses")
            .select(CourseRow.columns).in("id", values: courseIDs).execute().value
        async let courseHoles: [CourseHoleRecord] = client.from("course_holes")
            .select(CourseHoleRecord.columns).in("course_id", values: courseIDs)
            .execute().value

        return assemble(rows, players: try await players, scores: try await scores, matches: try await matches,
                        holes: try await holes, roster: try await roster, courses: try await courses,
                        courseHoles: try await courseHoles)
    }

    /// Setter sammen rundene av radene. Ren, så den kan prøves uten nett.
    nonisolated static func assemble(_ rows: [LooseRoundRecord], players: [RoundPlayerRow], scores: [HoleScoreRow],
                                     matches: [RoundMatchRow], holes: [RoundHoleRow], roster: [RoundRosterRow],
                                     courses: [CourseRow], courseHoles: [CourseHoleRecord]) -> [RoundSnapshot] {
        let byCourse = Dictionary(courses.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return rows.map { row in
            let id = row.round.id
            var s = RoundSnapshot(round: row.round)
            s.players = players.filter { $0.roundID == id }
            s.scores = scores.filter { $0.roundID == id }
            s.matches = matches.filter { $0.roundID == id }
            s.roundHoles = holes.filter { $0.roundID == id }
            let info = LooseRoundInfo(ownerID: row.ownerID, roster: roster.filter { $0.roundID == id })
            s.loose = info
            s.names = info.names
            s.eventDate = row.round.startedAt.map(LooseRoundInfo.day)
            s.rules = LooseRoundRules.template
            if let courseID = row.round.courseID {
                s.course = byCourse[courseID]
                s.courseHoles = courseHoles.filter { $0.courseID == courseID }
            }
            return s
        }
    }
}

/// En løs runde med eieren (`rounds.owner_id`, sql/017).
nonisolated struct LooseRoundRecord: Decodable, Equatable, Sendable {
    let round: RoundRow
    let ownerID: UUID?

    init(round: RoundRow, ownerID: UUID?) {
        self.round = round
        self.ownerID = ownerID
    }

    init(from decoder: any Decoder) throws {
        round = try RoundRow(from: decoder)
        ownerID = try decoder.container(keyedBy: CodingKeys.self).decodeIfPresent(UUID.self, forKey: .ownerID)
    }

    enum CodingKeys: String, CodingKey { case ownerID = "owner_id" }
}
