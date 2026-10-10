import { supabase } from "./supabase.ts";

// Radene web-admin leser. Samme kolonner som appens radtyper (Rows.swift, FoundationRows.swift).

export type Club = { id: string; name: string; join_code: string | null };
export type Membership = { id: string; club_id: string; display_name: string; is_organizer: boolean; status: string; clubs: Club };
export type Competition = {
  id: string; kind: "season" | "league" | "cup" | "fun" | "game"; name: string; club_id: string | null;
  season_id: string | null; status: "planned" | "active" | "finished"; entry: string; starts_on: string | null;
  ends_on: string | null; is_main: boolean; signup_open: boolean | null; auto_count?: boolean | null;
  rules: Record<string, unknown>;
};
export type EventRow = {
  id: string; club_id: string; season_id: string | null; competition_id: string | null; event_date: string;
  start_time: string | null; venue: string | null; note: string | null;
};
export type Member = {
  id: string; club_id: string; user_id: string | null; display_name: string; handicap_index: number | null;
  seed_group: number | null; is_organizer: boolean; is_treasurer: boolean; status: string;
};

/** Klubbene der du er arrangør (aktiv). */
export async function organizerClubs(): Promise<Membership[]> {
  const { data: user } = await supabase.auth.getUser();
  if (!user.user) return [];
  const { data, error } = await supabase
    .from("club_members")
    .select("id, club_id, display_name, is_organizer, status, clubs(id, name, join_code)")
    .eq("user_id", user.user.id)
    .eq("status", "active");
  if (error) throw error;
  return (data as unknown as Membership[]).filter((m) => m.is_organizer).sort((a, b) => a.clubs.name.localeCompare(b.clubs.name, "nb"));
}

export async function competitions(clubID: string): Promise<Competition[]> {
  const { data, error } = await supabase
    .from("competitions")
    .select("id, kind, name, club_id, season_id, status, entry, starts_on, ends_on, is_main, signup_open, auto_count, rules")
    .eq("club_id", clubID)
    .neq("kind", "game")
    .order("created_at", { ascending: false });
  if (error) throw error;
  return data as Competition[];
}

export async function events(clubID: string): Promise<EventRow[]> {
  const { data, error } = await supabase
    .from("events")
    .select("id, club_id, season_id, competition_id, event_date, start_time, venue, note")
    .eq("club_id", clubID)
    .order("event_date");
  if (error) throw error;
  return data as EventRow[];
}

export async function members(clubID: string): Promise<Member[]> {
  const { data, error } = await supabase
    .from("club_members")
    .select("id, club_id, user_id, display_name, handicap_index, seed_group, is_organizer, is_treasurer, status")
    .eq("club_id", clubID);
  if (error) throw error;
  return (data as Member[]).sort((a, b) => a.display_name.localeCompare(b.display_name, "nb"));
}
