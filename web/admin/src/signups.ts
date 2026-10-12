// Påmelding per kveld (steg 4, sql/045). Ren logikk, som appens SignupSummary og
// EveningSignupRules.swift: «kommer» er yes uten venteliste pluss bekreftede gjester.

export type SignupStatus = "yes" | "maybe" | "no";

export interface EveningSignup {
  member_id: string;
  status: SignupStatus | string;
  comment?: string | null;
  waitlisted_at?: string | null;
  late?: boolean | null;
}

export interface EveningGuest {
  id: string;
  event_id: string;
  name: string;
  invited_by: string;
  waitlisted_at: string | null;
}

export interface EveningSettings {
  id: string;
  max_players: number | null;
  signup_deadline: string | null;
  withdraw_deadline: string | null;
  allow_guests: boolean;
}

export interface SignupLogRow {
  id: number;
  member_id: string | null;
  guest_name: string | null;
  old_status: string;
  new_status: string;
  changed_at: string;
  note: string | null;
}

export interface SummaryEntry {
  /** Medlemmet, eller den som meldte på gjesten. */
  memberID: string;
  name: string;
  comment: string | null;
  guestID?: string;
  invitedBy?: string;
  place?: number;
  seen?: boolean;
}

export interface SignupSummary {
  yes: SummaryEntry[];
  guests: SummaryEntry[];
  waitlist: SummaryEntry[];
  maybe: SummaryEntry[];
  no: SummaryEntry[];
  notAnswered: SummaryEntry[];
  coming: number;
}

export const DEADLINE_TEXT = "Fristen er ute. Kontakt arrangøren.";

export function isConfirmed(s: Pick<EveningSignup, "status" | "waitlisted_at">): boolean {
  return s.status === "yes" && !s.waitlisted_at;
}

/**
 * Troppen (aktive, i visningsrekkefølge) fordelt på svarene. `seen` er medlemmene som har sett
 * kvelden, eller null når det ikke er kjent.
 */
export function summarize(
  roster: readonly { id: string; display_name: string }[],
  signups: readonly EveningSignup[],
  guests: readonly EveningGuest[] = [],
  seen: ReadonlySet<string> | null = null,
): SignupSummary {
  const byMember = new Map(signups.map((s) => [s.member_id, s]));
  const names = new Map(roster.map((m) => [m.id, m.display_name]));
  const out: SignupSummary = { yes: [], guests: [], waitlist: [], maybe: [], no: [], notAnswered: [], coming: 0 };
  const waiting: { at: string; key: string; entry: SummaryEntry }[] = [];
  for (const m of roster) {
    const s = byMember.get(m.id);
    if (!s) {
      out.notAnswered.push({ memberID: m.id, name: m.display_name, comment: null, seen: seen ? seen.has(m.id) : undefined });
      continue;
    }
    const entry: SummaryEntry = { memberID: m.id, name: m.display_name, comment: s.comment?.trim() || null };
    if (s.status === "yes") {
      if (s.waitlisted_at) waiting.push({ at: s.waitlisted_at, key: m.id.toLowerCase(), entry });
      else out.yes.push(entry);
    } else if (s.status === "maybe") out.maybe.push(entry);
    else if (s.status === "no") out.no.push(entry);
  }
  for (const g of guests) {
    const entry: SummaryEntry = { memberID: g.invited_by, name: g.name, comment: null, guestID: g.id,
      invitedBy: names.get(g.invited_by) ?? "et medlem" };
    if (g.waitlisted_at) waiting.push({ at: g.waitlisted_at, key: g.id.toLowerCase(), entry });
    else out.guests.push(entry);
  }
  out.waitlist = waiting
    .sort((a, b) => (Date.parse(a.at) - Date.parse(b.at)) || (a.key < b.key ? -1 : a.key > b.key ? 1 : 0))
    .map((w, i) => ({ ...w.entry, place: i + 1 }));
  out.coming = out.yes.length + out.guests.length;
  return out;
}

/** Gruppene som vises. «Ikke svart» deles i «Ikke svart» og «Ikke sett» når det er kjent. */
export function summaryGroups(s: SignupSummary): { title: string; entries: SummaryEntry[] }[] {
  const groups = [{ title: "Kommer", entries: [...s.yes, ...s.guests] }];
  if (s.waitlist.length > 0) groups.push({ title: "Venteliste", entries: s.waitlist });
  groups.push({ title: "Usikker", entries: s.maybe }, { title: "Kommer ikke", entries: s.no });
  if (s.notAnswered.some((e) => e.seen !== undefined)) {
    groups.push({ title: "Ikke svart", entries: s.notAnswered.filter((e) => e.seen) });
    groups.push({ title: "Ikke sett", entries: s.notAnswered.filter((e) => e.seen === false) });
  } else {
    groups.push({ title: "Ikke svart", entries: s.notAnswered });
  }
  return groups;
}

/** «gjest av Anders · nr. 2 på ventelista». */
export function entryDetail(e: SummaryEntry): string | null {
  const parts: string[] = [];
  if (e.invitedBy) parts.push(`gjest av ${e.invitedBy}`);
  if (e.place) parts.push(`nr. ${e.place} på ventelista`);
  return parts.length ? parts.join(" · ") : null;
}

/** «9 av 12 kommer + 2 gjester · 1 på venteliste · 1 usikker», som appens Tonight.signupText. */
export function signupText(signups: readonly EveningSignup[], guests: readonly EveningGuest[], rosterCount: number): string {
  if (signups.length === 0 && guests.length === 0) return `Ingen har svart ennå · ${rosterCount} i troppen`;
  const yes = signups.filter(isConfirmed).length;
  const maybe = signups.filter((s) => s.status === "maybe").length;
  const confirmedGuests = guests.filter((g) => !g.waitlisted_at).length;
  const waiting = signups.filter((s) => s.status === "yes" && s.waitlisted_at).length + guests.length - confirmedGuests;
  let text = `${yes} av ${rosterCount} kommer`;
  if (confirmedGuests > 0) text += confirmedGuests === 1 ? " + 1 gjest" : ` + ${confirmedGuests} gjester`;
  if (waiting > 0) text += ` · ${waiting} på venteliste`;
  if (maybe > 0) text += ` · ${maybe} ${maybe === 1 ? "usikker" : "usikre"}`;
  return text;
}

/** «På venteliste (nr. 2)». */
export function waitlistText(place: number | null | undefined): string {
  return place ? `På venteliste (nr. ${place})` : "På venteliste";
}

/** Feilteksten: fristen (DDB02) står alene. */
export function signupErrorText(error: { code?: string; message?: string } | null | undefined): string {
  if (!error) return "";
  if (error.code === "DDB02") return DEADLINE_TEXT;
  return error.message ?? "Noe gikk galt.";
}

/** Funksjonen, kolonnen eller tabellen finnes ikke (sql/045 ikke kjørt). */
export function isMissing(code: string | null | undefined): boolean {
  return ["PGRST202", "42883", "42703", "PGRST204", "42P01"].includes(code ?? "");
}

// MARK: Innstillingene i skjemaet

export interface SettingsForm {
  hasMax: boolean;
  maxPlayers: number;
  signupDeadline: string; // datetime-local, tom = av
  withdrawDeadline: string;
  allowGuests: boolean;
}

/** ISO-tidspunkt til `datetime-local` (lokal tid i nettleseren). */
export function toLocalInput(iso: string | null): string {
  if (!iso) return "";
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return "";
  const p = (n: number) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}T${p(d.getHours())}:${p(d.getMinutes())}`;
}

/** `datetime-local` til ISO, eller null når feltet er tomt. */
export function fromLocalInput(value: string): string | null {
  if (!value) return null;
  const d = new Date(value);
  return Number.isNaN(d.getTime()) ? null : d.toISOString();
}

export function settingsForm(s: EveningSettings | null | undefined): SettingsForm {
  return {
    hasMax: s?.max_players != null, maxPlayers: s?.max_players ?? 12,
    signupDeadline: toLocalInput(s?.signup_deadline ?? null), withdrawDeadline: toLocalInput(s?.withdraw_deadline ?? null),
    allowGuests: s?.allow_guests ?? false,
  };
}

/** Det som skrives til `events`. Det som er av, blir null. Taket holdes innenfor 1–500. */
export function settingsPatch(f: SettingsForm): Omit<EveningSettings, "id"> {
  return {
    max_players: f.hasMax ? Math.min(500, Math.max(1, Math.round(f.maxPlayers) || 1)) : null,
    signup_deadline: fromLocalInput(f.signupDeadline),
    withdraw_deadline: fromLocalInput(f.withdrawDeadline),
    allow_guests: f.allowGuests,
  };
}

// MARK: Loggen

const STATE: Record<string, string> = { yes: "Kommer", maybe: "Usikker", no: "Kommer ikke", waitlist: "Venteliste", none: "Ikke svart" };
const NOTE: Record<string, string> = { organizer: "endret av arrangøren", late: "etter fristen", promoted: "fikk plass", system: "automatisk" };

/** «Anders: Kommer → Kommer ikke (etter fristen)». */
export function logLine(row: SignupLogRow, name: (id: string) => string | undefined): string {
  const who = row.guest_name
    ? `${row.guest_name} (gjest av ${(row.member_id && name(row.member_id)) || "et medlem"})`
    : (row.member_id && name(row.member_id)) || "Tidligere medlem";
  let text = `${who}: ${STATE[row.old_status] ?? row.old_status} → ${STATE[row.new_status] ?? row.new_status}`;
  const note = row.note ? NOTE[row.note] : undefined;
  if (note) text += ` (${note})`;
  return text;
}
