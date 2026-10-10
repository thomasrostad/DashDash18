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

// ===== Del 3: terminliste og tropp =====

export type EventInput = {
  event_date: string; start_time: string | null; venue: string | null; note: string | null;
  /** Sesongens kvelder får season_id; liga, cup og morro får competition_id (sql/033). */
  season_id: string | null; competition_id: string | null;
};

export async function committees(clubID: string): Promise<Record<string, string[]>> {
  const { data, error } = await supabase.from("event_committee").select("event_id, member_id").eq("club_id", clubID);
  if (error) throw error;
  const out: Record<string, string[]> = {};
  for (const r of data as { event_id: string; member_id: string }[]) (out[r.event_id] ??= []).push(r.member_id);
  return out;
}

export async function saveEvent(clubID: string, id: string | null, e: EventInput, committee: string[]): Promise<void> {
  const row: Record<string, unknown> = {
    club_id: clubID, season_id: e.season_id, event_date: e.event_date, start_time: e.start_time,
    venue: e.venue?.trim() || null, note: e.note?.trim() || null,
  };
  if (!e.season_id && e.competition_id) row.competition_id = e.competition_id;
  const q = id ? supabase.from("events").update(row).eq("id", id) : supabase.from("events").insert(row);
  const { data, error } = await q.select("id").single();
  if (error) {
    if (error.code === "23505") throw new Error("Datoen står allerede i terminlista.");
    throw error;
  }
  const { error: cErr } = await supabase.rpc("set_event_committee", { p_event_id: (data as { id: string }).id, p_member_ids: committee });
  if (cErr) throw new Error(`Datoen er lagret, men ikke sosialkomiteen. ${cErr.message}`);
}

export async function deleteEvent(id: string): Promise<void> {
  const { error } = await supabase.from("events").delete().eq("id", id);
  if (error) {
    if (error.code === "23503") throw new Error("Datoen har runder og kan ikke slettes. Slett rundene først.");
    throw error;
  }
}

export type MemberPatch = Partial<Pick<Member, "display_name" | "handicap_index" | "seed_group" | "is_organizer" | "is_treasurer" | "status">> & { user_id?: null };

export async function updateMember(clubID: string, id: string, patch: MemberPatch): Promise<void> {
  const { error } = await supabase.from("club_members").update(patch).eq("id", id).eq("club_id", clubID);
  if (error) throw error;
}

export async function addMember(clubID: string, name: string, handicap: number | null): Promise<void> {
  const { error } = await supabase.from("club_members").insert({ club_id: clubID, display_name: name.trim(), handicap_index: handicap });
  if (error) throw error;
}

// ===== Del 2b: ny turnering og regler =====

/** Ny serie i klubben (sesong): lagres planlagt, og startes med activate_season når arrangøren vil. */
export async function createSeason(clubID: string, name: string, rules: Record<string, unknown>, start: boolean): Promise<void> {
  const { data, error } = await supabase.from("seasons")
    .insert({ club_id: clubID, name: name.trim(), status: "planned", rules }).select("id").single();
  if (error) throw error;
  if (start) {
    const { error: aErr } = await supabase.rpc("activate_season", { p_season_id: (data as { id: string }).id });
    if (aErr) throw new Error(`Turneringen er laget, men ikke startet. ${aErr.message}`);
  }
}

/** Cup eller morroturnering i klubben (create_competition_with_entrants, sql/022). Gir id-en. */
export async function createCompetition(p: {
  clubID: string; kind: "cup" | "fun" | "league"; name: string; entry: string; rules: Record<string, unknown>;
  startsOn: string | null; endsOn: string | null; signupOpen: boolean;
}): Promise<string> {
  const { data, error } = await supabase.rpc("create_competition_with_entrants", {
    p_kind: p.kind, p_name: p.name.trim(), p_club_id: p.clubID, p_entry: p.entry, p_rules: p.rules,
    p_starts_on: p.startsOn, p_ends_on: p.endsOn, p_signup_open: p.signupOpen, p_member_ids: [], p_profile_ids: [],
  });
  if (error) throw error;
  return data as string;
}

/** Lagrer regelsettet: sesongens i seasons (speiles til turneringen), de andres i competitions. */
export async function saveRules(c: Competition, rules: Record<string, unknown>): Promise<void> {
  const q = c.kind === "season" && c.season_id
    ? supabase.from("seasons").update({ rules }).eq("id", c.season_id)
    : supabase.from("competitions").update({ rules }).eq("id", c.id);
  const { error } = await q;
  if (error) throw error;
}
