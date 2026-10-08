// Ren logikk for push-send: hvem skal ha hvilket varsel, og hva står i det.
// Ingen nettverk, ingen Deno-API-er, så den kan testes uten APNs og uten
// database (logic_test.ts). Dataene kommer fra push_job_payload() i
// sql/010_push.sql.
//
// Reglene (samme som PWA-ens _worker.js, pluss valg per spiller):
//   * Arrangøren slår kategorier av for klubben. «Melding til alle» og purring
//     har ingen klubbryter: arrangøren trykket selv (PWA: ALLTID).
//   * Spilleren slår kategorier av for seg selv. «Melding til alle» har ingen
//     spillerbryter.
//   * recipients på linja: null = alle, liste = bare dem, tom liste = ingen.
//   * Den som gjorde det, får ikke push om sin egen hendelse.
//   * Tråden: all / mentions (standard) / off. Arrangørens meldinger går også
//     til dem som har mentions (PWA: mottakereForMelding).
//   * Blokkering (sql/019, user_blocks): har mottakeren blokkert den som står
//     bak (pushOriginators), får mottakeren ikke push. Bare én retning, som
//     tråden i 019: den blokkerte får fortsatt push om den som blokkerte.
//   * Linja står i Varsler i appen uansett. Det er bare pushen som stoppes.
//
// Tekstene følger ActivityText.display i appen (DashDash18/Data/Activity.swift),
// med emojien foran, siden et varsel ikke har ikon.

// ---------------------------------------------------------------------------
// Kategorier
// ---------------------------------------------------------------------------

/** Samme liste som check på activity.category (008). */
export const ACTIVITY_CATEGORIES = [
  "score", "lead", "side_prize", "round", "setup", "bet", "signup",
  "social", "club", "tips", "announcement", "nudge", "reminder",
] as const;
export type ActivityCategory = typeof ACTIVITY_CATEGORIES[number];

/** Kategoriene en push kan ha. 'thread' er kveldens tråd. */
export type PushCategory = ActivityCategory | "thread";

/** Kan ikke slås av for klubben (push_club_categories() i 010). */
export const CLUB_ALWAYS_ON: readonly PushCategory[] = ["announcement", "nudge"];
/** Kan ikke slås av av spilleren (push_player_categories() i 010). */
export const PLAYER_ALWAYS_ON: readonly PushCategory[] = ["announcement"];

export type ThreadMode = "all" | "mentions" | "off";

/** Hvor gammel en linje eller melding kan være og likevel gå som push. */
export const MAX_AGE_MS = {
  activity: 30 * 60 * 1000,
  // PWA-en: fem minutter for tråden. En gammel chatmelding er bare støy.
  thread: 5 * 60 * 1000,
} as const;

/** Tråden: lengste tekst i varselet (PWA: meldingTekst). */
export const THREAD_PREVIEW_MAX = 160;

export function isActivityCategory(value: unknown): value is ActivityCategory {
  return typeof value === "string" && (ACTIVITY_CATEGORIES as readonly string[]).includes(value);
}

// ---------------------------------------------------------------------------
// Dataene fra push_job_payload()
// ---------------------------------------------------------------------------

export interface DevicePayload {
  token: string;
  environment: "sandbox" | "production";
  bundle_id: string | null;
}

export interface MemberPayload {
  id: string;
  display_name: string;
  is_organizer: boolean;
  /** Aktivt medlem med innlogging. */
  active: boolean;
  disabled_categories: string[] | null;
  thread_mode: string | null;
  devices: DevicePayload[];
  /**
   * Klubbmedlemmene (club_members.id) dette medlemmets innlogging har blokkert.
   * Kommer ikke fra push_job_payload(): index.ts fyller det med attachBlocks()
   * før planPush. Mangler feltet, er ingen blokkert.
   */
  blocked_member_ids?: string[];
}

export interface ActivityPayload {
  id: string;
  kind: string;
  category: string;
  data: Record<string, unknown> | null;
  actor_member_id: string | null;
  event_id: string | null;
  round_id: string | null;
  recipients: string[] | null;
  created_at: string;
  round_status: string | null;
}

export interface MessagePayload {
  id: string;
  event_id: string;
  member_id: string;
  body: string;
  mentions: string[] | null;
  has_image: boolean;
  created_at: string;
  pushed_at: string | null;
  event_date: string | null;
}

export interface JobPayload {
  job_id: number;
  kind: "activity" | "thread";
  club: { id: string; name: string; disabled_categories: string[] | null };
  activity: ActivityPayload | null;
  message: MessagePayload | null;
  members: MemberPayload[];
}

/** Ett varsel til én telefon. */
export interface PushNotification {
  memberId: string;
  token: string;
  environment: "sandbox" | "production";
  title: string;
  body: string;
  category: PushCategory;
  /** aps.thread-id: grupperer varslene på låseskjermen. */
  threadId: string;
  /** apns-collapse-id: et nyere varsel erstatter det forrige (ledelsen). */
  collapseId?: string;
  /** Det appen trenger for å åpne riktig sted. */
  data: Record<string, string>;
}

export interface PushPlan {
  /** Satt når ingenting skal sendes, med grunnen (lagres i push_queue.result). */
  skipped?: string;
  notifications: PushNotification[];
}

// ---------------------------------------------------------------------------
// Av og på
// ---------------------------------------------------------------------------

/** Har arrangøren latt kategorien gå som push i klubben? */
export function clubAllows(club: JobPayload["club"], category: PushCategory): boolean {
  if (CLUB_ALWAYS_ON.includes(category)) return true;
  return !(club.disabled_categories ?? []).includes(category);
}

/** Vil spilleren ha kategorien? (Tråden styres av threadMode.) */
export function playerAllows(member: MemberPayload, category: PushCategory): boolean {
  if (PLAYER_ALWAYS_ON.includes(category)) return true;
  return !(member.disabled_categories ?? []).includes(category);
}

export function threadMode(member: MemberPayload): ThreadMode {
  const mode = member.thread_mode;
  return mode === "all" || mode === "off" ? mode : "mentions";
}

/** Kan medlemmet få push i det hele tatt? Aktivt, innlogget og med en telefon. */
export function reachable(member: MemberPayload): boolean {
  return member.active && member.devices.length > 0;
}

// ---------------------------------------------------------------------------
// Blokkering
// ---------------------------------------------------------------------------

/** club_members.id og innloggingen bak (user_id = profiles.id = auth.uid()). */
export interface MemberLink {
  id: string;
  user_id: string | null;
}

/** En rad i user_blocks. */
export interface BlockRow {
  blocker_id: string;
  blocked_id: string;
}

/**
 * Hvem står bak hendelsen? Har mottakeren blokkert en av dem, får hen ikke push.
 *   tråden:        forfatteren
 *   alle linjer:   actor_member_id (den som utløste den: føreren, arrangøren
 *                  som purret eller skrev til alle, den som rettet)
 *   big_score, side_prize, signup, member_joined: data.member (spilleren det
 *                  handler om, som ikke alltid er den som førte)
 *   lead_changed:  lederne; tips_king: tippekongene
 * Ikke med: de som bare nevnes uten å ha gjort noe (den som ble passert på
 * sidepremien, den som fikk scoren rettet, sosialkomiteen som ble trukket,
 * mottakerlista på purringen).
 */
export function pushOriginators(payload: JobPayload): string[] {
  const out = new Set<string>();
  if (payload.kind === "thread") {
    if (payload.message?.member_id) out.add(payload.message.member_id);
    return [...out];
  }
  const a = payload.activity;
  if (!a) return [];
  if (a.actor_member_id) out.add(a.actor_member_id);
  const d = a.data ?? {};
  switch (a.kind) {
    case "big_score":
    case "side_prize":
    case "signup":
    case "member_joined": {
      const member = str(d.member);
      if (member) out.add(member);
      break;
    }
    case "lead_changed":
      for (const id of ids(d.leaders) ?? []) out.add(id);
      break;
    case "tips_king":
      for (const id of ids(d.members) ?? []) out.add(id);
      break;
  }
  return [...out];
}

/**
 * Fyller blocked_member_ids på hvert medlem: medlemmene i klubben hvis
 * innlogging medlemmets innlogging har blokkert (user_blocks er mellom
 * profiler, payloaden er i klubbmedlemmer). Ren funksjon, endrer ikke payload.
 */
export function attachBlocks(payload: JobPayload, links: MemberLink[], blocks: BlockRow[]): JobPayload {
  const membersOfUser = new Map<string, string[]>();
  const userOfMember = new Map<string, string>();
  for (const l of links) {
    if (!l.user_id) continue;
    userOfMember.set(l.id, l.user_id);
    membersOfUser.set(l.user_id, [...(membersOfUser.get(l.user_id) ?? []), l.id]);
  }
  const blockedUsers = new Map<string, Set<string>>();
  for (const b of blocks) {
    if (!blockedUsers.has(b.blocker_id)) blockedUsers.set(b.blocker_id, new Set());
    blockedUsers.get(b.blocker_id)!.add(b.blocked_id);
  }
  return {
    ...payload,
    members: payload.members.map((m) => {
      const user = userOfMember.get(m.id);
      const blocked = user ? blockedUsers.get(user) : undefined;
      const memberIds = blocked ? [...blocked].flatMap((u) => membersOfUser.get(u) ?? []) : [];
      return { ...m, blocked_member_ids: [...new Set([...(m.blocked_member_ids ?? []), ...memberIds])] };
    }),
  };
}

/** Har medlemmet blokkert en av dem som står bak hendelsen? */
export function hasBlockedAny(member: MemberPayload, originators: readonly string[]): boolean {
  const blocked = member.blocked_member_ids ?? [];
  return blocked.length > 0 && originators.some((id) => blocked.includes(id));
}

/** Mottakerne av en linje i aktivitetsloggen. */
export function activityRecipients(payload: JobPayload, activity: ActivityPayload): MemberPayload[] {
  const category = activity.category as ActivityCategory;
  const listed = activity.recipients;
  const originators = pushOriginators(payload);
  return payload.members.filter((m) =>
    reachable(m) &&
    m.id !== activity.actor_member_id &&
    (listed === null || listed.includes(m.id)) &&
    playerAllows(m, category) &&
    !hasBlockedAny(m, originators)
  );
}

/** Mottakerne av en melding i tråden. */
export function threadRecipients(payload: JobPayload, message: MessagePayload): MemberPayload[] {
  const author = payload.members.find((m) => m.id === message.member_id);
  const fromOrganizer = author?.is_organizer ?? false;
  const mentions = message.mentions ?? [];
  return payload.members.filter((m) => {
    if (!reachable(m) || m.id === message.member_id) return false;
    if (hasBlockedAny(m, [message.member_id])) return false;
    switch (threadMode(m)) {
      case "off": return false;
      case "all": return true;
      case "mentions": return fromOrganizer || mentions.includes(m.id);
    }
  });
}

// ---------------------------------------------------------------------------
// Planen for én jobb
// ---------------------------------------------------------------------------

export function planPush(payload: JobPayload, now: Date): PushPlan {
  if (payload.kind === "thread") return planThread(payload, now);
  return planActivity(payload, now);
}

function tooOld(createdAt: string, maxAgeMs: number, now: Date): boolean {
  const t = Date.parse(createdAt);
  return !Number.isFinite(t) || now.getTime() - t > maxAgeMs;
}

function planActivity(payload: JobPayload, now: Date): PushPlan {
  const activity = payload.activity;
  if (!activity) return { skipped: "linja finnes ikke", notifications: [] };
  if (activity.round_status === "draft") return { skipped: "kladdrunde", notifications: [] };
  if (!isActivityCategory(activity.category)) {
    return { skipped: `ukjent kategori ${activity.category}`, notifications: [] };
  }
  if (tooOld(activity.created_at, MAX_AGE_MS.activity, now)) return { skipped: "for gammel", notifications: [] };
  if (!clubAllows(payload.club, activity.category)) {
    return { skipped: `${activity.category} er av for klubben`, notifications: [] };
  }
  const to = activityRecipients(payload, activity);
  if (to.length === 0) return { skipped: "ingen mottakere", notifications: [] };

  const names = nameLookup(payload.members);
  const display = activityDisplay(activity, names);
  const title = payload.club.name;
  const body = `${display.emoji} ${display.text}`;
  const data: Record<string, string> = { type: "activity", activity_id: activity.id, kind: activity.kind };
  if (activity.event_id) data.event_id = activity.event_id;
  if (activity.round_id) data.round_id = activity.round_id;
  const collapseId = activity.kind === "lead_changed" && activity.round_id
    ? `lead-${activity.round_id}`.slice(0, 64)
    : undefined;

  return {
    notifications: to.flatMap((m) =>
      m.devices.map((d) => ({
        memberId: m.id,
        token: d.token,
        environment: d.environment,
        title,
        body,
        category: activity.category as PushCategory,
        threadId: `club-${payload.club.id}`,
        collapseId,
        data,
      }))
    ),
  };
}

function planThread(payload: JobPayload, now: Date): PushPlan {
  const message = payload.message;
  if (!message) return { skipped: "meldingen finnes ikke", notifications: [] };
  if (message.pushed_at) return { skipped: "pushet fra før", notifications: [] };
  if (tooOld(message.created_at, MAX_AGE_MS.thread, now)) return { skipped: "for gammel", notifications: [] };
  if (!clubAllows(payload.club, "thread")) return { skipped: "tråden er av for klubben", notifications: [] };
  const to = threadRecipients(payload, message);
  if (to.length === 0) return { skipped: "ingen mottakere", notifications: [] };

  const author = payload.members.find((m) => m.id === message.member_id)?.display_name ?? "Noen";
  const title = message.event_date
    ? `Tråden · ${eveningLongText(message.event_date)}`
    : `${payload.club.name} · tråden`;
  const body = threadText(author, message.body, message.has_image);
  const data = { type: "thread", message_id: message.id, event_id: message.event_id };
  return {
    notifications: to.flatMap((m) =>
      m.devices.map((d) => ({
        memberId: m.id,
        token: d.token,
        environment: d.environment,
        title,
        body,
        category: "thread" as const,
        threadId: `thread-${message.event_id}`,
        data,
      }))
    ),
  };
}

// ---------------------------------------------------------------------------
// Tekstene
// ---------------------------------------------------------------------------

export type NameLookup = (id: string | null | undefined) => string;

export function nameLookup(members: MemberPayload[]): NameLookup {
  const map = new Map(members.map((m) => [m.id, m.display_name]));
  return (id) => (id ? map.get(id) : undefined) ?? "Noen";
}

/** «Navn: tekst», kuttet til 160 tegn. Bilde uten tekst er «📷 Bilde» (PWA: meldingTekst). */
export function threadText(author: string, body: string, hasImage: boolean): string {
  const clean = String(body ?? "").replace(/\s+/g, " ").trim();
  const chars = Array.from(clean);
  const short = chars.length > THREAD_PREVIEW_MAX
    ? chars.slice(0, THREAD_PREVIEW_MAX - 1).join("") + "…"
    : clean;
  if (hasImage) return `${author}: 📷 ${short || "Bilde"}`;
  return `${author}: ${short}`;
}

/** «Anders, Bjørn og Cato» (NorwegianList.join). */
export function norwegianList(items: string[]): string {
  if (items.length === 0) return "";
  if (items.length === 1) return items[0];
  return items.slice(0, -1).join(", ") + " og " + items[items.length - 1];
}

const WEEKDAYS = ["søndag", "mandag", "tirsdag", "onsdag", "torsdag", "fredag", "lørdag"];
const MONTHS = ["januar", "februar", "mars", "april", "mai", "juni",
  "juli", "august", "september", "oktober", "november", "desember"];

/** «torsdag 8. oktober» fra «2026-10-08» (EveningDates.longText). Ugyldig dato gis tilbake som den er. */
export function eveningLongText(date: string): string {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(date);
  if (!m) return date;
  const [y, mo, d] = [Number(m[1]), Number(m[2]), Number(m[3])];
  const t = new Date(Date.UTC(y, mo - 1, d));
  if (t.getUTCFullYear() !== y || t.getUTCMonth() !== mo - 1 || t.getUTCDate() !== d) return date;
  return `${WEEKDAYS[t.getUTCDay()]} ${d}. ${MONTHS[mo - 1]}`;
}

/** «272,5 m» (SidePrizes.formatMeters: én desimal, desimalkomma). */
export function formatMeters(meters: number): string {
  const rounded = Math.floor(meters * 10 + 0.5) / 10;
  return String(rounded).replace(".", ",") + " m";
}

/** «Runde 2 – Pebble Beach» (RoundListing.title), ellers banen eller «runden». */
function roundTitle(roundNo: number | undefined, course: string | undefined): string {
  if (!roundNo || roundNo <= 0) return course ?? "runden";
  return `Runde ${roundNo}` + (course ? ` – ${course}` : "");
}

export interface ActivityDisplay {
  emoji: string;
  text: string;
}

// Lesing av jsonb-feltene. Feil type blir undefined, som ActivityData i appen.
const str = (v: unknown) => (typeof v === "string" ? v : undefined);
const num = (v: unknown) => (typeof v === "number" && Number.isFinite(v) ? v : undefined);
const ids = (v: unknown) => (Array.isArray(v) ? v.filter((x): x is string => typeof x === "string") : undefined);

const UNKNOWN: ActivityDisplay = { emoji: "🔔", text: "Ny hendelse i klubben" };

/** Teksten for en linje. Mangler et felt hendelsen ikke klarer seg uten, blir den den nøytrale teksten. */
export function activityDisplay(activity: ActivityPayload, name: NameLookup): ActivityDisplay {
  const d = activity.data ?? {};
  const who = (id: unknown) => name(str(id));
  const list = (v: string[]) => norwegianList(v.map((id) => name(id)));
  const evening = (v: unknown) => (str(v) ? eveningLongText(str(v)!) : undefined);
  const actor = name(activity.actor_member_id);

  switch (activity.kind) {
    case "round_started": {
      let text = "Ny runde: " + roundTitle(num(d.round_no), str(d.course_name));
      const holeCount = num(d.hole_count);
      if (holeCount !== undefined) text += ` · ${holeCount} hull`;
      const extras: string[] = [];
      const ld = num(d.ld_hole), kp = num(d.kp_hole), bays = num(d.bays);
      if (ld !== undefined) extras.push(`longest drive på hull ${ld}`);
      if (kp !== undefined) extras.push(`nærmest pinnen på hull ${kp}`);
      if (bays !== undefined && bays > 0) extras.push(bays === 1 ? "1 bås" : `${bays} båser`);
      if (extras.length) text += " — " + extras.join(", ");
      return { emoji: "🏌️", text };
    }
    case "round_locked":
      return { emoji: "🔒", text: `${actor} låste ${roundTitle(num(d.round_no), str(d.course_name))}` };
    case "round_deleted":
      return { emoji: "🗑️", text: `${actor} slettet ${roundTitle(num(d.round_no), str(d.course_name))}` };
    case "big_score": {
      const member = str(d.member), hole = num(d.hole), strokes = num(d.strokes), par = num(d.par);
      const kind = str(d.name);
      if (!member || hole === undefined || strokes === undefined || par === undefined) return UNKNOWN;
      if (kind === "hole_in_one") return { emoji: "🎯", text: `${who(member)} HOLE IN ONE på hull ${hole}!` };
      if (kind === "albatross") {
        return { emoji: "🦅", text: `${who(member)} albatross på hull ${hole} — ${strokes} slag på par ${par}` };
      }
      if (kind === "eagle") {
        return { emoji: "🦅", text: `${who(member)} eagle på hull ${hole} — ${strokes} slag på par ${par}` };
      }
      return UNKNOWN;
    }
    case "lead_changed": {
      const after = num(d.after_hole), leaders = ids(d.leaders), points = num(d.points);
      const verb = {
        leads: "leder",
        took_lead: "har tatt ledelsen",
        shares: "deler ledelsen",
        won: "vant runden",
        snatched: "snappet runden på siste hull",
        tied_finish: "endte likt",
      }[str(d.outcome) ?? ""];
      if (after === undefined || !leaders?.length || points === undefined || !verb) return UNKNOWN;
      return { emoji: "📈", text: `${list(leaders)} ${verb} etter ${after} hull · ${points} poeng` };
    }
    case "side_prize": {
      const prize = str(d.kind), member = str(d.member), hole = num(d.hole), meters = num(d.meters);
      if ((prize !== "drive" && prize !== "kp") || !member || hole === undefined || meters === undefined) {
        return UNKNOWN;
      }
      let text = prize === "drive"
        ? `${who(member)} leder longest drive på hull ${hole} med ${formatMeters(meters)}`
        : `${who(member)} nærmest pinnen på hull ${hole} med ${formatMeters(meters)}`;
      const passed = str(d.passed);
      if (passed) {
        text += ` — forbi ${who(passed)}`;
        const passedMeters = num(d.passed_meters);
        if (passedMeters !== undefined) text += ` (${formatMeters(passedMeters)})`;
      }
      return { emoji: prize === "drive" ? "🚀" : "🎯", text };
    }
    case "score_corrected": {
      const member = str(d.member), hole = num(d.hole);
      if (!member || hole === undefined) return UNKNOWN;
      let text = `${actor} rettet hull ${hole} for ${who(member)}`;
      const roundNo = num(d.round_no), course = str(d.course_name);
      if (roundNo !== undefined || course !== undefined) text += " i " + roundTitle(roundNo, course);
      const from = num(d.from), to = num(d.to);
      text += `: ${from !== undefined ? from : "–"} → ${to !== undefined ? to : "–"}`;
      return { emoji: "✏️", text };
    }
    case "signup": {
      const member = str(d.member), status = str(d.status), date = evening(d.event_date);
      if (!member) return UNKNOWN;
      if (status === "yes") return { emoji: "✅", text: `${who(member)} meldte seg på` + (date ? ` ${date}` : "") };
      if (status === "no") return { emoji: "↩️", text: `${who(member)} meldte forfall` + (date ? ` til ${date}` : "") };
      if (status === "maybe") {
        return { emoji: "↩️", text: `${who(member)} er likevel usikker` + (date ? ` på ${date}` : "") };
      }
      return UNKNOWN;
    }
    case "nudge": {
      const date = evening(d.event_date);
      let text = "Hvem kommer" + (date ? ` ${date}` : "") + "?";
      const recipients = activity.recipients;
      text += recipients?.length ? ` Mangler svar fra ${list(recipients)} — svar i appen.` : " Svar i appen.";
      return { emoji: "⏰", text };
    }
    case "reminder": {
      const date = evening(d.event_date);
      let text = "Påminnelse: " + (date ? `${date} om en uke` : "neste kveld nærmer seg");
      const counts: string[] = [];
      const coming = num(d.coming), unsure = num(d.unsure);
      if (coming !== undefined) counts.push(`${coming} kommer`);
      if (unsure !== undefined && unsure > 0) counts.push(unsure === 1 ? "1 usikker" : `${unsure} usikre`);
      if (counts.length) text += " · " + counts.join(", ");
      return { emoji: "📅", text };
    }
    case "announcement": {
      const text = str(d.text);
      if (text === undefined) return UNKNOWN;
      return { emoji: "📣", text: `${actor}: ${text}` };
    }
    case "committee_drawn": {
      const members = ids(d.members) ?? [];
      const date = evening(d.event_date);
      let text = "Sosialkomiteen" + (date ? ` ${date}` : "");
      text += members.length === 0 ? " er trukket" : ": " + list(members);
      return { emoji: "🍺", text };
    }
    case "member_joined": {
      const member = str(d.member);
      if (!member) return UNKNOWN;
      return { emoji: "⛳", text: `${who(member)} ble med i klubben` };
    }
    case "tips_king": {
      const members = ids(d.members), correct = num(d.correct), possible = num(d.possible);
      if (!members || correct === undefined || possible === undefined) return UNKNOWN;
      const date = evening(d.event_date);
      const title = members.length > 1 ? "Tippekongene" : "Tippekongen";
      return {
        emoji: "👑",
        text: `${title}${date ? ` ${date}` : ""}: ${list(members)} med ${correct} av ${possible} riktige`,
      };
    }
    default:
      return UNKNOWN;
  }
}

// ---------------------------------------------------------------------------
// APNs: innholdet og svaret
// ---------------------------------------------------------------------------

/** JSON-innholdet APNs får. Under 4 kB med god margin (teksten er kort). */
export function apnsBody(n: PushNotification): Record<string, unknown> {
  return {
    aps: {
      alert: { title: n.title, body: n.body },
      sound: "default",
      "thread-id": n.threadId,
    },
    dd18: { ...n.data, category: n.category },
  };
}

/**
 * Hva svaret fra APNs betyr for tokenet og jobben.
 *   sent    – levert til APNs
 *   dead    – tokenet er dødt (410, eller 400 BadDeviceToken): slett det
 *   retry   – midlertidig (429, 5xx, nettverk): jobben kan prøves igjen
 *   config  – feil hos oss (403 nøkkel/JWT, feil topic): rett secrets
 *   failed  – annet, ikke prøv igjen
 */
export type ApnsOutcome = "sent" | "dead" | "retry" | "config" | "failed";

export function classifyApnsResponse(status: number, reason?: string | null): ApnsOutcome {
  if (status === 200) return "sent";
  if (status === 410) return "dead";
  if (status === 400 && reason === "BadDeviceToken") return "dead";
  if (status === 429 || status >= 500 || status === 0) return "retry";
  if (status === 403) return "config";
  if (status === 400 && (reason === "DeviceTokenNotForTopic" || reason === "TopicDisallowed" ||
    reason === "MissingTopic" || reason === "BadTopic")) return "config";
  return "failed";
}

export interface SendResult {
  token: string;
  status: number;
  reason?: string | null;
}

export interface JobSummary {
  /** true = jobben er ferdig. false = prøv igjen senere (finish_push_job p_ok). */
  ok: boolean;
  sent: number;
  failed: number;
  deadTokens: string[];
  error?: string;
}

/**
 * Oppsummerer sendingen av én jobb. Jobben prøves igjen bare når INGENTING kom
 * fram og minst én feil var midlertidig eller hos oss (APNs nede, feil nøkkel):
 * ellers ville de som alt har fått varselet, fått det to ganger.
 */
export function summarize(results: SendResult[]): JobSummary {
  let sent = 0, failed = 0, retryable = 0;
  const deadTokens: string[] = [];
  const reasons = new Set<string>();
  for (const r of results) {
    const outcome = classifyApnsResponse(r.status, r.reason);
    if (outcome === "sent") { sent++; continue; }
    failed++;
    if (outcome === "dead") deadTokens.push(r.token);
    if (outcome === "retry" || outcome === "config") retryable++;
    reasons.add(`${r.status}${r.reason ? " " + r.reason : ""}`);
  }
  const ok = !(sent === 0 && retryable > 0);
  const error = reasons.size ? [...reasons].join(", ").slice(0, 500) : undefined;
  return { ok, sent, failed, deadTokens, error };
}
