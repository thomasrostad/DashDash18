import Foundation
import Supabase

/// Leser og lagrer spillerens push-valg (`push_preferences`) og leser klubbens
/// (`clubs.push_disabled_categories`). Tabellen og kolonnen
/// kom med `sql/010_push.sql`.
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

    // MARK: Gruppene og e-post (sql/046)

    /// Gruppene og e-postvalget. nil når 046 ikke er kjørt (kolonnene mangler): da vises
    /// innstillingene som før, uten grupper.
    func loadGroups() async throws(DataError) -> PushGroupSettings? {
        do {
            let rows: [PushGroupSettings] = try await client.from("push_preferences")
                .select(PushGroupSettings.columns)
                .eq("member_id", value: memberID)
                .limit(1)
                .execute().value
            return rows.first ?? .defaults
        } catch let error as PostgrestError where PushSchema.isMissing(code: error.code) {
            return nil
        } catch {
            throw DataError.from(error)
        }
    }

    /// Hva som hører til hvilken gruppe. Den lokale kopien når kallet feiler.
    func loadGroupMap() async -> PushGroupMap {
        let rows: [PushGroupMapRow]? = try? await client.rpc("push_group_map").execute().value
        guard let rows, !rows.isEmpty else { return .local }
        return PushGroupMap(rows: rows)
    }

    /// Lagrer gruppene og e-postvalget på alle medlemskapene (`push_set_groups`), og leser
    /// valget tilbake.
    @discardableResult
    func saveGroups(_ settings: PushGroupSettings) async throws(DataError) -> PushGroupSettings {
        do {
            _ = try await client.rpc("push_set_groups", params: settings.rpcParams).execute()
        } catch {
            throw DataError.from(error)
        }
        guard let back = try await loadGroups(), back.matches(settings) else { throw DataError.notAllowed }
        return back
    }
}

/// «Demp denne kvelden» (sql/046): egne rader i `push_event_mutes`, skriving med
/// `push_mute_event`. Uten 046 svarer `isMuted` nil, og bryteren skjules.
nonisolated struct PushEventMuteStore: Sendable {
    let client: SupabaseClient

    nonisolated private struct Row: Decodable {
        let eventID: UUID
        enum CodingKeys: String, CodingKey { case eventID = "event_id" }
    }

    func isMuted(eventID: UUID) async throws(DataError) -> Bool? {
        do {
            // RLS gir bare egne rader.
            let rows: [Row] = try await client.from("push_event_mutes")
                .select("event_id")
                .eq("event_id", value: eventID)
                .limit(1)
                .execute().value
            return !rows.isEmpty
        } catch let error as PostgrestError where PushSchema.isMissing(code: error.code) {
            return nil
        } catch {
            throw DataError.from(error)
        }
    }

    /// Demper (på) eller slår på igjen (av). Svarer om kvelden er dempet etterpå.
    func setMuted(eventID: UUID, on: Bool) async throws(DataError) -> Bool {
        struct Params: Encodable {
            let p_event_id: UUID
            let p_on: Bool
        }
        do {
            let result: Bool = try await client.rpc("push_mute_event", params: Params(p_event_id: eventID, p_on: on))
                .execute().value
            return result
        } catch {
            throw DataError.from(error)
        }
    }
}
