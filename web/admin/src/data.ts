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

// ===== Del 2: én turnering =====

export type Participant = { id: string; member_id: string | null; profile_id: string | null; status: string; name: string };
export type SignupSettings = {
  signup_open: boolean; signup_audience: "members" | "anyone"; listed: boolean; max_entrants: number | null;
  waitlist_enabled: boolean; signup_opens_at: string | null; signup_closes_at: string | null;
};
export type WaitlistEntry = { id: string; waitlist_position: number; display_name: string; offered_at: string | null; offer_expires_at: string | null };
export type StaffRow = { profile_id: string; role: "organizer" | "scorer"; name: string };

async function profileNames(ids: string[]): Promise<Record<string, string>> {
  if (ids.length === 0) return {};
  const { data, error } = await supabase.from("profiles").select("id, display_name").in("id", ids);
  if (error) throw error;
  return Object.fromEntries((data as { id: string; display_name: string | null }[]).map((p) => [p.id, p.display_name ?? "Ukjent"]));
}

/** Påmeldte (aktive først), med navn fra troppen eller profilen. */
export async function participants(competitionID: string, roster: Member[]): Promise<Participant[]> {
  const { data, error } = await supabase
    .from("competition_participants").select("id, member_id, profile_id, status").eq("competition_id", competitionID);
  if (error) throw error;
  const rows = data as Omit<Participant, "name">[];
  const names = await profileNames(rows.filter((r) => !r.member_id && r.profile_id).map((r) => r.profile_id!));
  return rows
    .map((r) => ({ ...r, name: r.member_id ? roster.find((m) => m.id === r.member_id)?.display_name ?? "Ukjent" : names[r.profile_id!] ?? "Ukjent" }))
    .sort((a, b) => (a.status === b.status ? a.name.localeCompare(b.name, "nb") : a.status === "active" ? -1 : 1));
}

export async function signupSettings(competitionID: string): Promise<SignupSettings> {
  const { data, error } = await supabase
    .from("competitions")
    .select("signup_open, signup_audience, listed, max_entrants, waitlist_enabled, signup_opens_at, signup_closes_at")
    .eq("id", competitionID).single();
  if (error) throw error;
  return data as SignupSettings;
}

export async function saveSignupSettings(competitionID: string, s: SignupSettings): Promise<void> {
  const { error } = await supabase.rpc("set_competition_signup", {
    p_competition_id: competitionID, p_signup_open: s.signup_open, p_audience: s.signup_audience, p_listed: s.listed,
    p_max_entrants: s.max_entrants, p_waitlist_enabled: s.waitlist_enabled,
    p_opens_at: s.signup_opens_at, p_closes_at: s.signup_closes_at,
  });
  if (error) throw error;
}

export async function waitlist(competitionID: string): Promise<WaitlistEntry[]> {
  const { data, error } = await supabase.rpc("competition_waitlist_entries", { p_competition_id: competitionID });
  if (error) throw error;
  return data as WaitlistEntry[];
}

export async function staff(competitionID: string): Promise<StaffRow[]> {
  const { data, error } = await supabase.from("competition_staff").select("profile_id, role").eq("competition_id", competitionID);
  if (error) throw error;
  const rows = data as Omit<StaffRow, "name">[];
  const names = await profileNames(rows.map((r) => r.profile_id));
  return rows.map((r) => ({ ...r, name: names[r.profile_id] ?? "Ukjent" })).sort((a, b) => a.name.localeCompare(b.name, "nb"));
}

export async function addStaff(competitionID: string, profileID: string, role: StaffRow["role"]): Promise<void> {
  const { error } = await supabase.from("competition_staff").insert({ competition_id: competitionID, profile_id: profileID, role });
  if (error) throw error;
}

export async function removeStaff(competitionID: string, profileID: string): Promise<void> {
  const { error } = await supabase.from("competition_staff").delete().eq("competition_id", competitionID).eq("profile_id", profileID);
  if (error) throw error;
}

/** «Spill når det passer» (sql/042). */
export async function setPlaysWhenItSuits(competitionID: string, on: boolean): Promise<void> {
  const { error } = await supabase.from("competitions").update({ auto_count: on }).eq("id", competitionID);
  if (error) throw error;
}

/** Hele turneringen (sql/038). Navnet må skrives inn. */
export async function deleteTournament(competitionID: string, confirmName: string): Promise<{ name: string; rounds: number; events: number }> {
  const { data, error } = await supabase.rpc("delete_tournament", { p_competition_id: competitionID, p_confirm_name: confirmName });
  if (error) throw error;
  return data as { name: string; rounds: number; events: number };
}
