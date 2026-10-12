// Sesongene leses fra turneringsradene (gjennomføringsplanen steg 3): `competitions` med `season_id`,
// med `season_id` som sesongens id. Etter sql/035 er `seasons` et view over de samme radene; før 035
// holder 033-triggerne dem like. Samme rader og kolonner som appens `SeasonQuery` (MainTournament.swift).
// Filtrer på sesongen med `season_id`, ikke `id` (turneringsradens egen id).

import { supabase } from "./supabase.ts";

/** Sesongraden som før (`id, club_id, name, status, rules`), med id fra `season_id`. */
export const SEASON_COLUMNS = "id:season_id, club_id, name, status, rules";

/** Sesongene du kan se. Legg på `.eq("club_id", …)`, `.eq("season_id", …)` osv. */
export function seasonRows(columns: string = SEASON_COLUMNS) {
  return supabase.from("competitions").select(columns).not("season_id", "is", null);
}
