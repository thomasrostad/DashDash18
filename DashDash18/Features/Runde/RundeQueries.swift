import Foundation
import GolfgutuCore
import Supabase

/// Spørringene for runden som går. Bare lesing, pluss par-bekreftelsen for arrangøren.
/// Score skrives aldri herfra (se `ScoreSubmitting`).
enum RundeQueries {
    static let roundColumns = """
        id, club_id, event_id, course_id, round_no, name, status, hole_count, first_hole, tee_time, format, \
        handicap_allowance, external_handicap, weight, ld_enabled, ld_hole_index, kp_enabled, kp_hole_index, \
        cut_rule, cut_after, par_confirmed_by, par_confirmed_at, started_at, locked_at
        """
    static let playerColumns =
        "round_id, member_id, club_id, handicap_index, seed_group, playing_handicap, bay_no, is_marker, team_no"
    static let scoreColumns = "round_id, member_id, hole_index, strokes, recorded_at, updated_by, updated_at"

    /// Runden som går i klubben (høyst én, se `rounds_one_active_per_club`), med alt under.
    static func activeRound(client: SupabaseClient, clubID: UUID) async throws -> RoundSnapshot? {
        let rounds: [RoundRow] = try await client.from("rounds")
            .select(roundColumns)
            .eq("club_id", value: clubID)
            .eq("status", value: RoundStatus.active.rawValue)
            .limit(1)
            .execute().value
        guard let round = rounds.first else { return nil }
        return try await snapshot(client: client, round: round)
    }

    static func snapshot(client: SupabaseClient, round: RoundRow) async throws -> RoundSnapshot {
        let id = round.id
        async let holes: [RoundHoleRow] = client.from("round_holes")
            .select("round_id, hole_index, par, stroke_index, length_m")
            .eq("round_id", value: id).execute().value
        async let players: [RoundPlayerRow] = client.from("round_players")
            .select(playerColumns)
            .eq("round_id", value: id).execute().value
        async let matches: [RoundMatchRow] = client.from("round_matches")
            .select("round_id, match_no, player_a, player_b, player_c, team_a, team_b, result")
            .eq("round_id", value: id).execute().value
        async let scores: [HoleScoreRow] = client.from("hole_scores")
            .select(scoreColumns)
            .eq("round_id", value: id).execute().value
        async let claims: [SideClaimRow] = client.from("side_claims")
            .select(claimColumns)
            .eq("round_id", value: id).execute().value
        async let members: [ClubMemberRow] = client.from("club_members")
            .select(KveldQueries.memberColumns)
            .eq("club_id", value: round.clubID).execute().value
        async let events: [EventRow] = client.from("events")
            .select("id, club_id, season_id, event_date, start_time, venue, note")
            .eq("id", value: round.eventID).execute().value

        var snapshot = RoundSnapshot(round: round)
        snapshot.roundHoles = try await holes
        snapshot.players = try await players
        snapshot.matches = try await matches
        snapshot.scores = try await scores
        snapshot.sideClaims = try await claims
        snapshot.names = Dictionary(try await members.map { ($0.id, $0.displayName) }, uniquingKeysWith: { a, _ in a })
        let event = try await events.first
        snapshot.eventDate = event?.eventDate

        if let courseID = round.courseID {
            async let courses: [CourseRow] = client.from("courses")
                .select("id, club_id, name, external_name, course_rating, slope_rating, in_use, confirmed_by, confirmed_at")
                .eq("id", value: courseID).execute().value
            async let courseHoles: [CourseHoleRecord] = client.from("course_holes")
                .select("course_id, hole_number, par, stroke_index, length_m")
                .eq("course_id", value: courseID).execute().value
            snapshot.course = try await courses.first
            snapshot.courseHoles = try await courseHoles
        }
        snapshot.rules = try await rules(client: client, clubID: round.clubID, seasonID: event?.seasonID)
        return snapshot
    }

    /// Regelsettet til kveldens sesong, ellers den aktive sesongen, ellers Golfgutu-oppsettet.
    static func rules(client: SupabaseClient, clubID: UUID, seasonID: UUID?) async throws -> Ruleset {
        let columns = "id, club_id, name, status, rules"
        if let seasonID {
            let rows: [SeasonRow] = try await client.from("seasons").select(columns)
                .eq("id", value: seasonID).execute().value
            if let season = rows.first { return season.rules }
        }
        let active: [SeasonRow] = try await client.from("seasons").select(columns)
            .eq("club_id", value: clubID)
            .eq("status", value: SeasonStatus.active.rawValue)
            .limit(1)
            .execute().value
        return active.first?.rules ?? .golfgutu
    }

    /// Par stemmer med skjermen: `confirm_round_par` (sql/007_foring.sql). Arrangøren, eller en
    /// markør i en runde som går. Svarer med tidspunktet; var den bekreftet, står den første.
    /// 42501 = ikke markør eller arrangør, 55000 = runden er ikke i gang.
    @discardableResult
    static func confirmPar(client: SupabaseClient, roundID: UUID) async throws -> String {
        struct Params: Encodable { let p_round_id: UUID }
        let confirmedAt: String = try await client
            .rpc("confirm_round_par", params: Params(p_round_id: roundID))
            .execute().value
        return confirmedAt
    }

    // MARK: Longest drive og nærmest pinnen

    static let claimColumns = "id, round_id, member_id, kind, meters, hole_index, created_at"

    /// «Meld inn» / «Oppdater»: én rad per runde, spiller og type (`side_claims_one_per_kind`).
    /// Finnes raden, oppdateres den; ellers settes den inn. Har noen andre satt inn i mellomtiden
    /// (arrangøren for deg), rettes den raden. Sjekker raden tilbake (RLS kan stille avvise).
    static func saveSideClaim(client: SupabaseClient, _ draft: SideClaimDraft) async throws -> SideClaimRow {
        struct Insert: Encodable {
            let round_id: UUID
            let member_id: UUID
            let kind: String
            let meters: Double
            let hole_index: Int
        }
        struct Update: Encodable {
            let meters: Double
            let hole_index: Int
        }
        let update = Update(meters: draft.meters, hole_index: draft.holeIndex)

        func updated(_ rows: [SideClaimRow]) throws -> SideClaimRow {
            guard let row = rows.first, abs(row.meters - draft.meters) < 0.05 else { throw DataError.notAllowed }
            return row
        }

        if let id = draft.existing {
            let rows: [SideClaimRow] = try await client.from("side_claims")
                .update(update).eq("id", value: id)
                .select(claimColumns).execute().value
            if !rows.isEmpty { return try updated(rows) }
            // Raden er borte (slettet et annet sted): sett inn på nytt under.
        }
        do {
            let rows: [SideClaimRow] = try await client.from("side_claims")
                .insert(Insert(round_id: draft.roundID, member_id: draft.memberID, kind: draft.kind.rawValue,
                               meters: draft.meters, hole_index: draft.holeIndex))
                .select(claimColumns).execute().value
            return try updated(rows)
        } catch let error where DataError.from(error) == .duplicate {
            let rows: [SideClaimRow] = try await client.from("side_claims")
                .update(update)
                .eq("round_id", value: draft.roundID)
                .eq("member_id", value: draft.memberID)
                .eq("kind", value: draft.kind.rawValue)
                .select(claimColumns).execute().value
            return try updated(rows)
        }
    }

    /// Sletter en innmelding. Sjekker at raden faktisk ble slettet.
    static func deleteSideClaim(client: SupabaseClient, id: UUID) async throws {
        let rows: [SideClaimRow] = try await client.from("side_claims")
            .delete().eq("id", value: id)
            .select(claimColumns).execute().value
        guard !rows.isEmpty else { throw DataError.notAllowed }
    }
}
