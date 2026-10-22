import { errorText, supabase } from "./supabase.ts";
import {
  isMissing, signupErrorText, type EveningGuest, type EveningSettings, type EveningSignup, type SettingsForm,
  type SignupLogRow, type SignupStatus, settingsPatch,
} from "./signups.ts";

// Påmeldingen per kveld (sql/045). Uten 045 hentes svarene uten ventelista, innstillinger,
// gjester og logg skjules, og arrangøren endrer svar rett i signups som før.

export type EveningSignupData = {
  signups: EveningSignup[];
  /** null: sql/045 er ikke kjørt. */
  settings: EveningSettings | null;
  guests: EveningGuest[];
  /** Medlemmene som har sett kvelden. null: ikke kjent. */
  seen: Set<string> | null;
};

/** Svarene på en kveld, med ventelista når kolonnen finnes. */
export async function eveningSignups(eventID: string): Promise<EveningSignup[]> {
  const full = await supabase.from("signups").select("member_id, status, comment, waitlisted_at, late").eq("event_id", eventID);
  if (!full.error) return (full.data ?? []) as EveningSignup[];
  if (!isMissing(full.error.code)) throw full.error;
  const old = await supabase.from("signups").select("member_id, status, comment").eq("event_id", eventID);
  if (old.error) throw old.error;
  return (old.data ?? []) as EveningSignup[];
}

/** Innstillingene for kveldene, eller null når sql/045 ikke er kjørt. */
export async function eveningSettings(eventIDs: string[]): Promise<Record<string, EveningSettings> | null> {
  if (eventIDs.length === 0) return {};
  const { data, error } = await supabase.from("events")
    .select("id, max_players, signup_deadline, withdraw_deadline, allow_guests").in("id", eventIDs);
  if (error) return null;
  return Object.fromEntries((data as EveningSettings[]).map((s) => [s.id, s]));
}

export async function eveningData(eventID: string): Promise<EveningSignupData> {
  const [signups, settings] = await Promise.all([eveningSignups(eventID), eveningSettings([eventID])]);
  if (!settings) return { signups, settings: null, guests: [], seen: null };
  const [g, v] = await Promise.all([
    supabase.from("event_guests").select("id, event_id, name, invited_by, waitlisted_at").eq("event_id", eventID).order("created_at"),
    supabase.from("event_views").select("member_id").eq("event_id", eventID),
  ]);
  return {
    signups, settings: settings[eventID] ?? null,
    guests: (g.data ?? []) as EveningGuest[],
    seen: v.error ? null : new Set(((v.data ?? []) as { member_id: string }[]).map((r) => r.member_id)),
  };
}

function signupError(error: { code?: string; message?: string }): Error {
  return new Error(signupErrorText(error));
}

/** Arrangøren endrer svaret for et medlem. `status` null fjerner svaret. Reserve uten sql/045: rett i signups. */
export async function setAnswer(event: { id: string; club_id: string }, memberID: string, status: SignupStatus | null): Promise<void> {
  const { error } = await supabase.rpc("evening_signup", {
    p_event_id: event.id, p_status: status, p_comment: null, p_member_id: memberID,
  });
  if (!error) return;
  if (!isMissing(error.code)) throw signupError(error);
  const q = status === null
    ? supabase.from("signups").delete().eq("event_id", event.id).eq("member_id", memberID)
    : supabase.from("signups").upsert({ event_id: event.id, member_id: memberID, club_id: event.club_id, status },
      { onConflict: "event_id,member_id" });
  const res = await q;
  if (res.error) throw res.error;
}

export async function addGuest(eventID: string, name: string, invitedBy: string): Promise<void> {
  const { error } = await supabase.rpc("evening_guest_add", { p_event_id: eventID, p_name: name.trim(), p_invited_by: invitedBy });
  if (error) throw error.code === "23505" ? new Error("En gjest med det navnet er alt påmeldt.") : signupError(error);
}

export async function removeGuest(guestID: string): Promise<void> {
  const { error } = await supabase.rpc("evening_guest_remove", { p_guest_id: guestID });
  if (error) throw signupError(error);
}

export async function signupLog(eventID: string): Promise<SignupLogRow[]> {
  const { data, error } = await supabase.from("signup_log")
    .select("id, member_id, guest_name, old_status, new_status, changed_at, note")
    .eq("event_id", eventID).order("changed_at", { ascending: false }).limit(200);
  if (error) throw error;
  return data as SignupLogRow[];
}

/** Tak, frister og gjester (vanlig update på events). */
export async function saveSettings(eventID: string, form: SettingsForm): Promise<void> {
  const { error } = await supabase.from("events").update(settingsPatch(form)).eq("id", eventID);
  if (error) throw new Error(`Datoen er lagret, men ikke påmeldingen. ${errorText(error)}`);
}
