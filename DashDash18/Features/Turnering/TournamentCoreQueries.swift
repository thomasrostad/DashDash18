import Foundation
import Supabase

/// Henting og skriving for fase 23 (sql/031 og 032). Kalles bare når `TournamentCoreFeature` er på,
/// bortsett fra `minimumBuild`, som bare leser `app_config` (031).
nonisolated enum TournamentCoreQueries {
    // MARK: Velgeren

    /// Klubbens turneringer (alle statuser; velgeren filtrerer).
    static func clubCompetitions(client: SupabaseClient, clubID: UUID) async throws -> [CompetitionRow] {
        try await client.from("competitions")
            .select(CompetitionRow.columns)
            .eq("club_id", value: clubID)
            .execute().value
    }

    // MARK: Påmelding

    private struct IDs: Encodable { let p_competition_ids: [UUID] }
    private struct One: Encodable { let p_competition_id: UUID }
    private struct Respond: Encodable { let p_competition_id: UUID; let p_accept: Bool }

    /// Min status i flere turneringer i ett kall (`competition_signup_status`).
    static func signupStatus(client: SupabaseClient, competitionIDs: [UUID]) async throws -> [CompetitionSignupStatus] {
        guard !competitionIDs.isEmpty else { return [] }
        return try await client.rpc("competition_signup_status", params: IDs(p_competition_ids: competitionIDs))
            .execute().value
    }

    static func signup(client: SupabaseClient, competitionID: UUID) async throws -> CompetitionSignupStatus {
        try await client.rpc("competition_signup", params: One(p_competition_id: competitionID)).execute().value
    }

    static func withdraw(client: SupabaseClient, competitionID: UUID) async throws -> CompetitionSignupStatus {
        try await client.rpc("competition_withdraw", params: One(p_competition_id: competitionID)).execute().value
    }

    static func respond(client: SupabaseClient, competitionID: UUID, accept: Bool) async throws -> CompetitionSignupStatus {
        try await client.rpc("competition_offer_respond", params: Respond(p_competition_id: competitionID, p_accept: accept))
            .execute().value
    }

    static func signupSettings(client: SupabaseClient, competitionID: UUID) async throws -> CompetitionSignupSettings {
        try await client.from("competitions")
            .select(CompetitionSignupSettings.columns)
            .eq("id", value: competitionID)
            .single()
            .execute().value
    }

    static func saveSignupSettings(client: SupabaseClient, _ params: SetSignupParams) async throws {
        try await client.rpc("set_competition_signup", params: params).execute()
    }

    static func waitlist(client: SupabaseClient, competitionID: UUID) async throws -> [WaitlistEntryRow] {
        try await client.rpc("competition_waitlist_entries", params: One(p_competition_id: competitionID))
            .execute().value
    }

    // MARK: Stab

    static func staff(client: SupabaseClient, competitionID: UUID) async throws -> [CompetitionStaffRow] {
        try await client.from("competition_staff")
            .select(CompetitionStaffRow.columns)
            .eq("competition_id", value: competitionID)
            .execute().value
    }

    private struct StaffInsert: Encodable {
        let competition_id: UUID
        let profile_id: UUID
        let role: StaffRole
    }

    static func addStaff(client: SupabaseClient, competitionID: UUID, profileID: UUID, role: StaffRole) async throws {
        try await client.from("competition_staff")
            .insert(StaffInsert(competition_id: competitionID, profile_id: profileID, role: role))
            .execute()
    }

    static func setStaffRole(client: SupabaseClient, competitionID: UUID, profileID: UUID, role: StaffRole) async throws {
        try await client.from("competition_staff")
            .update(["role": role.rawValue])
            .eq("competition_id", value: competitionID)
            .eq("profile_id", value: profileID)
            .execute()
    }

    static func removeStaff(client: SupabaseClient, competitionID: UUID, profileID: UUID) async throws {
        try await client.from("competition_staff")
            .delete()
            .eq("competition_id", value: competitionID)
            .eq("profile_id", value: profileID)
            .execute()
    }

    private struct ProfileName: Decodable {
        let id: UUID
        let displayName: String?

        enum CodingKeys: String, CodingKey {
            case id
            case displayName = "display_name"
        }
    }

    /// Navn på profiler du kan se (`can_see_profile`). De du ikke ser, mangler.
    static func profileNames(client: SupabaseClient, ids: [UUID]) async throws -> [UUID: String] {
        guard !ids.isEmpty else { return [:] }
        let rows: [ProfileName] = try await client.from("profiles")
            .select("id, display_name")
            .in("id", values: ids.map(\.uuidString))
            .execute().value
        return Dictionary(rows.compactMap { r in r.displayName.map { (r.id, $0) } }, uniquingKeysWith: { first, _ in first })
    }

    // MARK: Startliste

    private struct EventCompetition: Decodable {
        let competitionID: UUID?
        enum CodingKeys: String, CodingKey { case competitionID = "competition_id" }
    }

    /// Turneringen spilledagen hører til (`events.competition_id`, sql/031).
    static func eventCompetition(client: SupabaseClient, eventID: UUID) async throws -> UUID? {
        let rows: [EventCompetition] = try await client.from("events")
            .select("competition_id")
            .eq("id", value: eventID)
            .execute().value
        return rows.first?.competitionID
    }

    private struct RoundWave: Decodable {
        let id: UUID
        let waveNo: Int
        enum CodingKeys: String, CodingKey {
            case id
            case waveNo = "wave_no"
        }
    }

    /// Puljen per runde (`rounds.wave_no`, sql/031).
    static func waves(client: SupabaseClient, roundIDs: [UUID]) async throws -> [UUID: Int] {
        guard !roundIDs.isEmpty else { return [:] }
        let rows: [RoundWave] = try await client.from("rounds")
            .select("id, wave_no")
            .in("id", values: roundIDs.map(\.uuidString))
            .execute().value
        return Dictionary(rows.map { ($0.id, $0.waveNo) }, uniquingKeysWith: { first, _ in first })
    }

    static func players(client: SupabaseClient, roundIDs: [UUID]) async throws -> [RoundPlayerRow] {
        guard !roundIDs.isEmpty else { return [] }
        return try await client.from("round_players")
            .select(RoundPlayerRow.columns)
            .in("round_id", values: roundIDs.map(\.uuidString))
            .execute().value
    }

    static func startGroups(client: SupabaseClient, roundIDs: [UUID]) async throws -> [RoundStartGroupRow] {
        guard !roundIDs.isEmpty else { return [] }
        return try await client.from("round_start_groups")
            .select(RoundStartGroupRow.columns)
            .in("round_id", values: roundIDs.map(\.uuidString))
            .execute().value
    }

    static func saveStartList(client: SupabaseClient, _ params: SaveStartListParams) async throws {
        try await client.rpc("save_start_list", params: params).execute()
    }

    // MARK: Minste appbygg

    /// `app_config.min_ios_build` (sql/031). nil når raden mangler eller ikke kan leses.
    static func minimumBuild(client: SupabaseClient) async throws -> Int? {
        let rows: [AppConfigMinBuildRow] = try await client.from("app_config")
            .select("value")
            .eq("key", value: "min_ios_build")
            .limit(1)
            .execute().value
        return rows.first?.value?.build
    }
}
