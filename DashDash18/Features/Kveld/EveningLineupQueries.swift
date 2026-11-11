import Foundation
import Supabase

/// Oppstillingen arrangøren har vist for spillerne før start (`event_lineups`, sql/076).
enum EveningLineupQueries {
    /// Radene for kvelden. Tomt når ingenting er vist, og når hentingen feiler: uten 076 finnes ikke
    /// funksjonen (PGRST202), og Hjem skal se ut som før.
    static func rows(client: SupabaseClient, eventID: UUID) async -> [EventLineupRow] {
        struct Params: Encodable { let p_event_id: UUID }
        do {
            return try await client.rpc("event_lineups", params: Params(p_event_id: eventID)).execute().value
        } catch {
            return []
        }
    }
}
