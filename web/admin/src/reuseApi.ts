import { supabase } from "./supabase.ts";
import type { SeriesResult, SeriesUpdateResult, SetupTemplate, TemplateKind } from "./reuse.ts";

// Kallene for gjenbruk (sql/049). Mangler 049, skjules alt (`reuseAvailable` gir false).

/** Tabell, kolonne eller funksjon finnes ikke (049 er ikke kjørt). */
export function isMissing049(code: string | null | undefined): boolean {
  return ["PGRST202", "PGRST205", "PGRST200", "42883", "42703", "PGRST204", "42P01"].includes(code ?? "");
}

let probe: Promise<boolean> | null = null;

/** Finnes 049? Spør én gang per økt; en annen feil (nettet) prøves på nytt neste gang. */
export function reuseAvailable(): Promise<boolean> {
  probe ??= (async () => {
    const { error } = await supabase.from("event_series").select("id").limit(1);
    if (!error) return true;
    if (!isMissing049(error.code)) probe = null;
    return false;
  })();
  return probe;
}

export type SeriesRow = { id: string; competition_id: string; weekday: number; every_weeks: number; start_time: string | null; venue: string | null };

/** Kveld → serie, og seriene. Tomt uten 049. */
export async function seriesFor(clubID: string): Promise<{ eventSeries: Record<string, string>; series: Record<string, SeriesRow> }> {
  const [e, s] = await Promise.all([
    supabase.from("events").select("id, series_id").eq("club_id", clubID).not("series_id", "is", null),
    supabase.from("event_series").select("id, competition_id, weekday, every_weeks, start_time, venue").eq("club_id", clubID),
  ]);
  if (e.error || s.error) return { eventSeries: {}, series: {} };
  return {
    eventSeries: Object.fromEntries((e.data as { id: string; series_id: string }[]).map((r) => [r.id, r.series_id])),
    series: Object.fromEntries((s.data as SeriesRow[]).map((r) => [r.id, r])),
  };
}

export async function createEventSeries(p: {
  competitionID: string; firstDate: string; weekday: number; count: number; everyWeeks: number; startTime: string | null; venue: string | null;
}): Promise<SeriesResult> {
  const { data, error } = await supabase.rpc("create_event_series", {
    p_competition_id: p.competitionID, p_first_date: p.firstDate, p_weekday: p.weekday, p_count: p.count,
    p_every_weeks: p.everyWeeks, p_start_time: p.startTime ? `${p.startTime.slice(0, 5)}:00` : null, p_venue: p.venue?.trim() || null,
  });
  if (error) throw error;
  const r = data as SeriesResult;
  return { series_id: r.series_id, event_ids: r.event_ids ?? [], dates: r.dates ?? [], skipped: r.skipped ?? [] };
}

export async function updateEventSeries(p: {
  eventID: string; scope: "one" | "future"; startTime: string | null; venue: string | null; newDate: string | null;
}): Promise<SeriesUpdateResult> {
  const { data, error } = await supabase.rpc("update_event_series", {
    p_event_id: p.eventID, p_scope: p.scope, p_start_time: p.startTime ? `${p.startTime.slice(0, 5)}:00` : null,
    p_venue: p.venue?.trim() || null, p_new_date: p.newDate,
  });
  if (error) {
    if (error.code === "23505") throw new Error(error.message || "Turneringen har alt en dag på den datoen.");
    throw error;
  }
  const r = data as SeriesUpdateResult;
  return { updated: r.updated ?? [], skipped: r.skipped ?? [], shifted_days: r.shifted_days ?? 0 };
}

/** Klubbens maler av typen, sortert på navn. Tom uten 049 eller uten rettighet. */
export async function templates(clubID: string, kind: TemplateKind): Promise<SetupTemplate[]> {
  const { data, error } = await supabase.from("setup_templates")
    .select("id, club_id, owner_id, kind, name, payload, updated_at").eq("club_id", clubID).eq("kind", kind);
  if (error) {
    if (isMissing049(error.code)) return [];
    throw error;
  }
  return (data as SetupTemplate[]).sort((a, b) => a.name.localeCompare(b.name, "nb"));
}

export async function saveTemplate(p: { id: string | null; clubID: string; kind: TemplateKind; name: string; payload: Record<string, unknown> }): Promise<SetupTemplate> {
  const { data, error } = await supabase.rpc("setup_template_save", {
    p_id: p.id, p_club_id: p.clubID, p_kind: p.kind, p_name: p.name.trim(), p_payload: p.payload,
  });
  if (error) throw error;
  return data as SetupTemplate;
}

export async function deleteTemplate(id: string): Promise<void> {
  const { error } = await supabase.rpc("setup_template_delete", { p_id: id });
  if (error) throw error;
}

/** `previous_round_setup(kveld)`. undefined: funksjonen finnes ikke (bruk det lokale forslaget). null: ingen runde. */
export async function previousRoundSetup(eventID: string): Promise<unknown | null | undefined> {
  const { data, error } = await supabase.rpc("previous_round_setup", { p_event_id: eventID });
  if (error) {
    if (isMissing049(error.code) || error.code === "42501") return undefined;
    throw error;
  }
  return data ?? null;
}
