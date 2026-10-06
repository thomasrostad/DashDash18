import Foundation
import Supabase

/// Leser og lagrer spillerens push-valg (`push_preferences`) og leser klubbens
/// (`clubs.push_disabled_categories`). Brukes bare når `PushFeature.isEnabled` er på,
/// fordi tabellen og kolonnen først finnes etter `sql/010_push.sql`.
nonisolated struct PushSettingsStore: Sendable {
    let client: SupabaseClient
    let memberID: UUID
    let clubID: UUID

    static let columns = "member_id, club_id, disabled_categories, thread_mode"

    /// Mine valg (standard hvis jeg aldri har endret noe) og det arrangøren har slått av.
    func load() async throws(DataError) -> (PushPreferences, ClubPushSettings) {
        do {
            let rows: [PushPreferences] = try await client.from("push_preferences")
                .select(Self.columns)
                .eq("member_id", value: memberID)
                .limit(1)
                .execute().value
            let clubs: [ClubPushSettings] = try await client.from("clubs")
                .select("push_disabled_categories")
                .eq("id", value: clubID)
                .limit(1)
                .execute().value
            return (rows.first ?? .defaults(memberID: memberID, clubID: clubID), clubs.first ?? ClubPushSettings())
        } catch {
            throw DataError.from(error)
        }
    }

    /// Lagrer valgene (én rad per medlemskap) og sjekker raden tilbake.
    @discardableResult
    func save(_ preferences: PushPreferences) async throws(DataError) -> PushPreferences {
        do {
            let rows: [PushPreferences] = try await client.from("push_preferences")
                .upsert(preferences, onConflict: "member_id")
                .select(Self.columns)
                .execute().value
            guard let row = rows.first, row == preferences else { throw DataError.notAllowed }
            return row
        } catch {
            throw DataError.from(error)
        }
    }
}
