import Foundation
import GolfgutuCore
import Supabase

/// Spørringene for runden som går: lesing, par-bekreftelsen og innmeldingene til longest drive
/// og nærmest pinnen. Score skrives aldri herfra (se `ScoreSubmitting`).
enum RundeQueries {
    /// Brukes fortsatt i Konkurranser/. Ny kode bruker `RoundRow.columns`.
    static let roundColumns = RoundRow.columns

    /// Runden som går i klubben (høyst én, se `rounds_one_active_per_club`), med alt under.
    static func activeRound(client: SupabaseClient, clubID: UUID) async throws -> RoundSnapshot? {
        let rounds: [RoundRow] = try await client.from("rounds")
            .select(RoundRow.columns)
            .eq("club_id", value: clubID)
            .eq("status", value: RoundStatus.active.rawValue)
            .limit(1)
            .execute().value
        guard let round = rounds.first else { return nil }
        return try await snapshot(client: client, round: round)
    }

    /// Runden med alt under. En klubbrunde får navn fra troppen og regler fra sesongen; en løs runde
    /// (uten klubb, sql/017) får navn fra deltakerne og regelsettet for løse runder.
    static func snapshot(client: SupabaseClient, round: RoundRow) async throws -> RoundSnapshot {
        guard let clubID = round.clubID, let eventID = round.eventID else {
            return try await looseSnapshot(client: client, round: round)
        }
        async let base = baseSnapshot(client: client, round: round)
        async let members: [ClubMemberRow] = client.from("club_members")
            .select(ClubMemberRow.columns)
            .eq("club_id", value: clubID).execute().value
        async let events: [EventRow] = client.from("events")
            .select(EventRow.columns)
            .eq("id", value: eventID).execute().value

        var snapshot = try await base
        snapshot.names = Dictionary(try await members.map { ($0.id, $0.displayName) }, uniquingKeysWith: { a, _ in a })
        let event = try await events.first
        snapshot.eventDate = event?.eventDate
        snapshot.rules = try await rules(client: client, clubID: clubID, seasonID: event?.seasonID)
        return snapshot
    }

    /// En løs runde: deltakerne (profil eller gjest) med navn fra `round_roster`, eieren, og
    /// regelsettet for løse runder. Datoen er dagen runden startet.
    static func looseSnapshot(client: SupabaseClient, round: RoundRow) async throws -> RoundSnapshot {
        struct Owner: Decodable {
            let ownerID: UUID?
            enum CodingKeys: String, CodingKey { case ownerID = "owner_id" }
        }
        async let base = baseSnapshot(client: client, round: round)
        async let roster: [RoundRosterRow] = client.from("round_roster")
            .select(RoundRosterRow.columns)
            .eq("round_id", value: round.id).execute().value
        async let owners: [Owner] = client.from("rounds")
            .select("owner_id")
            .eq("id", value: round.id).execute().value

        var snapshot = try await base
        let info = LooseRoundInfo(ownerID: try await owners.first?.ownerID, roster: try await roster)
        snapshot.loose = info
        snapshot.names = info.names
        snapshot.eventDate = round.startedAt.map(LooseRoundInfo.day)
        snapshot.rules = LooseRoundRules.template
        return snapshot
    }

    /// Det som er likt for alle runder: hull, spillere, matcher, scorer, sidepremier og banen.
    private static func baseSnapshot(client: SupabaseClient, round: RoundRow) async throws -> RoundSnapshot {
        let id = round.id
        async let holes: [RoundHoleRow] = client.from("round_holes")
            .select(RoundHoleRow.columns)
            .eq("round_id", value: id).execute().value
        async let players: [RoundPlayerRow] = client.from("round_players")
            .select(RoundPlayerRow.columns)
            .eq("round_id", value: id).execute().value
        async let matches: [RoundMatchRow] = client.from("round_matches")
            .select(RoundMatchRow.columns)
            .eq("round_id", value: id).execute().value
        async let scores: [HoleScoreRow] = client.from("hole_scores")
            .select(HoleScoreRow.columns)
            .eq("round_id", value: id).execute().value
        async let claims: [SideClaimRow] = client.from("side_claims")
            .select(SideClaimRow.columns)
            .eq("round_id", value: id).execute().value

        var snapshot = RoundSnapshot(round: round)
        snapshot.roundHoles = try await holes
        snapshot.players = try await players
        snapshot.matches = try await matches
        snapshot.scores = try await scores
        snapshot.sideClaims = try await claims

        if let courseID = round.courseID {
            async let courses: [CourseRow] = client.from("courses")
                .select(CourseRow.columns)
                .eq("id", value: courseID).execute().value
            async let courseHoles: [CourseHoleRecord] = client.from("course_holes")
                .select(CourseHoleRecord.columns)
                .eq("course_id", value: courseID).execute().value
            snapshot.course = try await courses.first
            snapshot.courseHoles = try await courseHoles
        }
        return snapshot
    }

    /// Regelsettet til kveldens sesong, ellers den aktive sesongen, ellers Golfgutu-oppsettet.
    static func rules(client: SupabaseClient, clubID: UUID, seasonID: UUID?) async throws -> Ruleset {
        if let seasonID {
            let rows: [SeasonRow] = try await client.from("seasons").select(SeasonRow.columns)
                .eq("id", value: seasonID).execute().value
            if let season = rows.first { return season.rules }
        }
        let active: [SeasonRow] = try await client.from("seasons").select(SeasonRow.columns)
            .eq("club_id", value: clubID)
            .eq("status", value: SeasonStatus.active.rawValue)
            .limit(1)
            .execute().value
        return active.first?.rules ?? .golfgutu
    }

    /// Par stemmer med skjermen: `confirm_round_par` (sql/007_foring.sql, regelen i sql/014). Hvem som
    /// kan, står i `RoundGame.canConfirmPar`. Svarer med tidspunktet; var den bekreftet, står den første.
    /// 42501 = ikke lov, 55000 = runden er ikke i gang.
    @discardableResult
    static func confirmPar(client: SupabaseClient, roundID: UUID) async throws -> String {
        struct Params: Encodable { let p_round_id: UUID }
        let confirmedAt: String = try await client
            .rpc("confirm_round_par", params: Params(p_round_id: roundID))
            .execute().value
        return confirmedAt
    }

    // MARK: Longest drive og nærmest pinnen

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
                .select(SideClaimRow.columns).execute().value
            if !rows.isEmpty { return try updated(rows) }
            // Raden er borte (slettet et annet sted): sett inn på nytt under.
        }
        do {
            let rows: [SideClaimRow] = try await client.from("side_claims")
                .insert(Insert(round_id: draft.roundID, member_id: draft.memberID, kind: draft.kind.rawValue,
                               meters: draft.meters, hole_index: draft.holeIndex))
                .select(SideClaimRow.columns).execute().value
            return try updated(rows)
        } catch let error where DataError.from(error) == .duplicate {
            let rows: [SideClaimRow] = try await client.from("side_claims")
                .update(update)
                .eq("round_id", value: draft.roundID)
                .eq("member_id", value: draft.memberID)
                .eq("kind", value: draft.kind.rawValue)
                .select(SideClaimRow.columns).execute().value
            return try updated(rows)
        }
    }

    /// Sletter en innmelding. Sjekker at raden faktisk ble slettet.
    static func deleteSideClaim(client: SupabaseClient, id: UUID) async throws {
        let rows: [SideClaimRow] = try await client.from("side_claims")
            .delete().eq("id", value: id)
            .select(SideClaimRow.columns).execute().value
        guard !rows.isEmpty else { throw DataError.notAllowed }
    }
}
