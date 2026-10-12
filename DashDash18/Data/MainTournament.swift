import Foundation
import Supabase

/// Sesongene leses fra turneringsradene: `competitions` med `season_id` (gjennomføringsplanen steg 3).
/// Etter sql/035 er `seasons` et view over de samme radene; før 035 holder 033-triggerne dem like.
/// Radene og kolonnene er de samme som fra `seasons`, med `season_id` som sesongens id
/// (`SeasonRow.columns`). Filtrer på sesongen med `season_id`, ikke `id` (turneringsradens egen id).
nonisolated enum SeasonQuery {
    static func select(_ client: SupabaseClient) -> PostgrestFilterBuilder {
        client.from("competitions")
            .select(SeasonRow.columns)
            .not("season_id", operator: .is, value: "null")
    }
}

/// Klubbens hovedturnering (`competitions.is_main`). Etter sql/034 kan en klubb ha flere aktive
/// serier samtidig, men bare én aktiv hovedturnering. Der appen trenger «klubbens sesong» (Tavla,
/// Vedd, Tropp, arrangørsiden, regelsettet uten kveld), er det hovedturneringen, aldri en vilkårlig
/// aktiv serie.
nonisolated enum MainTournament {
    /// Den aktive hovedturneringens sesong. Uten kjente hovedturneringer (oppslaget feilet, eller data
    /// fra før turneringsraden fantes) brukes den aktive bare når den er den eneste. Nil ellers: en
    /// serie som går ved siden av, blir aldri «klubbens sesong».
    static func activeSeason(_ seasons: [SeasonRow], mainSeasonIDs: Set<UUID>) -> SeasonRow? {
        let active = seasons.filter { $0.status == .active }
        if let main = active.first(where: { mainSeasonIDs.contains($0.id) }) { return main }
        return mainSeasonIDs.isEmpty && active.count == 1 ? active.first : nil
    }

    /// Sesongen tabellen viser (Tavla, Vedd, dagens ord): den aktive hovedturneringen, ellers den
    /// sist opprettede hovedturneringen, ellers den eneste aktive, ellers den sist opprettede.
    /// - Parameter seasons: nyeste først (`created_at` synkende), aktive og ferdige.
    static func tableSeason(_ seasons: [SeasonRow], mainSeasonIDs: Set<UUID>) -> SeasonRow? {
        if let active = activeSeason(seasons, mainSeasonIDs: mainSeasonIDs) { return active }
        if let main = seasons.first(where: { mainSeasonIDs.contains($0.id) && $0.status != .planned }) { return main }
        return seasons.first { $0.status == .finished } ?? seasons.first
    }

    /// Den aktive hovedturneringen som `season` ville erstattet om den ble aktivert som
    /// hovedturnering. Nil når klubben ikke har en annen aktiv hovedturnering.
    static func activeMain(otherThan season: SeasonRow, in seasons: [SeasonRow], mainSeasonIDs: Set<UUID>) -> SeasonRow? {
        let others = seasons.filter { $0.id != season.id && $0.clubID == season.clubID }
        return activeSeason(others, mainSeasonIDs: mainSeasonIDs)
    }

    /// Sesongene bak klubbens hovedturneringer (aktive og ferdige). Feiler oppslaget, er settet tomt,
    /// og valget faller tilbake på «den eneste aktive».
    static func seasonIDs(client: SupabaseClient, clubID: UUID) async -> Set<UUID> {
        struct Row: Decodable {
            let seasonID: UUID?
            enum CodingKeys: String, CodingKey { case seasonID = "season_id" }
        }
        let rows: [Row]? = try? await client.from("competitions")
            .select("season_id")
            .eq("club_id", value: clubID)
            .eq("is_main", value: true)
            .execute().value
        return Set(rows?.compactMap(\.seasonID) ?? [])
    }
}
