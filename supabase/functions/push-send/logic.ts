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
//   * Forfall gir ett varsel per person (gjennomføringsplanen steg 4 og 6):
//     appen skriver «meldte forfall» (signup, status no) til alle, og
//     serveren (sql/045) skriver signup_dropped til arrangørene (recipients).
//     Når push-send sender appens linje, slår index.ts opp signup_dropped for
//     samme kveld og medlem innen DROP_WINDOW_MS, og attachAlreadyNotified
//     legger mottakerne der i already_notified_ids. De hoppes over her: de
//     har fått serverens varsel (med «etter fristen»). Alle andre får appens.
//     Feiler oppslaget, pushes linja som før (heller to varsler enn ingen).
//   * Varsler, steg 5 (sql/046): grupper og demping avgjøres i push_job_payload (devices er
//     tom, og muted/group_off sier hvorfor). collapse fra svaret blir apns-collapse-id.
//     evening_started har egen tekst. Turneringer uten klubb (audience = 'competition') har
//     profil-id-er som medlemmer, og threadId competition-<id>. pushLogResults gir loggen per
//     mottaker til push_log_result (sent, failed eller skipped med grunn).
//   * Sosialt (sql/050): comment_added, mentioned og photo_prompt har egne tekster. Mottakerne
//     står i recipients: medlems-id-er i klubben, profil-id-er i en turnering uten klubb
//     (isRecipient). Den som skrev kommentaren (actor_member_id, eller data.author_profile uten
//     klubb) er aktøren og står bak (blokkering).
//   * Del regningen (sql/051): bill_share_sent og bill_share_disputed har egen tekst
//     (data.title, data.name) og går bare til mottakeren på linja (recipients).
//   * Følge (sql/054): personlige linjer uten klubb og turnering har audience 'person'.
//     Medlemmene er mottakerlista (profil-id-er), aktøren er activity.actor_profile_id (også
//     for blokkering), tittelen er «Atten» og threadId 'follow' (kommentarer: card-<kort>).
//     follow_requested, follow_accepted og followed har egen tekst (data.actor_name).
//     round_finished går aldri som push (køen tar den ikke heller).
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
  // sql/046. Mangler i eldre svar (da gjelder det som før).
  /** Innloggingen (auth.uid()). null for ledige navn. */
  user_id?: string | null;
  disabled_groups?: string[] | null;
  email_fallback?: boolean;
  /** Har dempet kvelden (devices er da tom). */
  muted?: boolean;
  /** Har slått av gruppen linja hører til (devices er da tom). */
  group_off?: boolean;
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
  /** sql/054: aktøren som profil på personlige linjer (uten klubb og turnering). */
  actor_profile_id?: string | null;
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
  /** id er null for turneringer uten klubb (sql/046): da er name turneringens navn. */
  club: { id: string | null; name: string; disabled_categories: string[] | null };
  activity: ActivityPayload | null;
  message: MessagePayload | null;
  members: MemberPayload[];
  /**
   * Medlemmer som allerede har fått varsel om det samme (forfall: serverens
   * signup_dropped). Kommer ikke fra push_job_payload(): index.ts fyller det
   * med attachAlreadyNotified() før planPush. Mangler feltet, gjelder ingen.
   */
  already_notified_ids?: string[];
  // sql/046. Mangler i eldre svar.
  /** Gruppen linja hører til: game, social, evening eller organizer. */
  group?: string | null;
  /** apns-collapse-id for linjer med kveld: event-<kveld>-<gruppe>. */
  collapse?: string | null;
  event_id?: string | null;
  competition?: { id: string; name: string } | null;
  /**
   * 'club': id-ene er klubbmedlemmer. 'competition' (turnering uten klubb) og 'person'
   * (personlige linjer, sql/054): id-ene er profiler.
   */
  audience?: "club" | "competition" | "person";
  /** Hva en dag heter («kveld» eller «spilledag»), når svaret har det. Ellers nøytral tekst. */
  day_term?: string | null;
  /**
   * Innloggingen bak actor_member_id. Kommer ikke fra push_job_payload(): index.ts fyller
   * det for turneringer uten klubb, der mottakerne er profiler og ikke klubbmedlemmer.
   */
  actor_user_id?: string | null;
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
  /** De med innlogging som ikke får den, med grunn (sql/046: push_log_result). */
  skippedMembers?: MemberSkip[];
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
 *   big_score, side_prize, signup, member_joined, signup_dropped: data.member
 *                  (spilleren det handler om, som ikke alltid er den som førte)
 *   lead_changed:  lederne; tips_king: tippekongene
 *   table_changed: den linja handler om (ny leder eller den som klatret mest)
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
  // sql/054: personlige linjer har aktøren som profil.
  if (a.actor_profile_id) out.add(a.actor_profile_id);
  const d = a.data ?? {};
  switch (a.kind) {
    case "big_score":
    case "side_prize":
    case "signup":
    case "signup_dropped":
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
    case "table_changed": {
      const subject = tableSubject(tableSpots(d.table) ?? []);
      if (subject) out.add(subject.spot.member);
      break;
    }
    // sql/050: den som skrev kommentaren (profilen uten klubb; i klubben er det actor_member_id).
    case "comment_added":
    case "mentioned": {
      const author = str(d.author_profile);
      if (author) out.add(author);
      break;
    }
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

// ---------------------------------------------------------------------------
// Forfall: ett varsel per person
// ---------------------------------------------------------------------------

/** Hvor nær i tid serverens signup_dropped må være appens forfallslinje. */
export const DROP_WINDOW_MS = 10 * 60 * 1000;

/** En signup_dropped-linje slik index.ts henter den. */
export interface DroppedRow {
  recipients: string[] | null;
  created_at: string;
}

/**
 * Er jobben appens «meldte forfall» (signup med status no)? Da gir den kvelden
 * og medlemmet index.ts skal slå opp signup_dropped for. Ellers null.
 */
export function dropoutLookup(payload: JobPayload): { eventId: string; member: string; createdAt: string } | null {
  const a = payload.activity;
  if (payload.kind !== "activity" || !a || a.kind !== "signup" || !a.event_id) return null;
  const member = str(a.data?.member);
  if (!member || a.data?.status !== "no") return null;
  return { eventId: a.event_id, member, createdAt: a.created_at };
}

/**
 * Legger mottakerne av serverens signup_dropped (samme kveld og medlem, innen
 * DROP_WINDOW_MS) i already_notified_ids. recipients null betyr alle.
 * Ren funksjon, endrer ikke payload.
 */
export function attachAlreadyNotified(payload: JobPayload, dropped: DroppedRow[]): JobPayload {
  const lookup = dropoutLookup(payload);
  if (!lookup) return payload;
  const at = Date.parse(lookup.createdAt);
  const near = dropped.filter((d) => {
    const t = Date.parse(d.created_at);
    return Number.isFinite(at) && Number.isFinite(t) && Math.abs(t - at) <= DROP_WINDOW_MS;
  });
  if (near.length === 0) return payload;
  const ids = new Set(payload.already_notified_ids ?? []);
  for (const d of near) {
    for (const id of d.recipients ?? payload.members.map((m) => m.id)) ids.add(id);
  }
  return { ...payload, already_notified_ids: [...ids] };
}

/** Har medlemmet blokkert en av dem som står bak hendelsen? */
export function hasBlockedAny(member: MemberPayload, originators: readonly string[]): boolean {
  const blocked = member.blocked_member_ids ?? [];
  return blocked.length > 0 && originators.some((id) => blocked.includes(id));
}

// ---------------------------------------------------------------------------
// Hvem får, og hvorfor ikke (sql/046: logg per mottaker)
// ---------------------------------------------------------------------------

/**
 * Hvorfor et medlem ikke fikk push (notifications.reason). Bare for dem med innlogging.
 *   actor          den som gjorde det (eller skrev meldingen)
 *   not_recipient  ikke på mottakerlista, har fått varsel om det samme, eller ikke nevnt i tråden
 *   too_old        linja eller meldingen var for gammel da senderen kom til den
 *   club_off       arrangøren har slått av kategorien (eller tråden) for klubben
 *   muted          har dempet kvelden
 *   group_off      har slått av gruppen
 *   category_off   har slått av kategorien (eller tråden)
 *   blocked        har blokkert den som står bak
 */
export type SkipReason =
  | "actor"
  | "not_recipient"
  | "too_old"
  | "club_off"
  | "muted"
  | "group_off"
  | "category_off"
  | "blocked";

export interface MemberSkip {
  memberId: string;
  reason: SkipReason;
}

/** Er id-ene i jobben profiler (turnering uten klubb, eller personlige linjer fra sql/054)? */
export function profileAudience(payload: JobPayload): boolean {
  return payload.audience === "competition" || payload.audience === "person";
}

/** Innloggingen bak et medlem: user_id fra 046, ellers id-en selv når id-ene er profiler. */
export function memberUserId(payload: JobPayload, member: MemberPayload): string | null {
  if (member.user_id) return member.user_id;
  return profileAudience(payload) ? member.id : null;
}

/** Er medlemmet den som gjorde det? Klubbmedlem-id, eller innloggingen (turnering uten klubb). */
export function isActor(payload: JobPayload, member: MemberPayload, actorId: string | null | undefined): boolean {
  if (actorId && member.id === actorId) return true;
  const actorUser = payload.actor_user_id;
  if (actorUser && memberUserId(payload, member) === actorUser) return true;
  // sql/054: personlige linjer har aktøren som profil.
  const actorProfile = payload.activity?.actor_profile_id;
  if (actorProfile && memberUserId(payload, member) === actorProfile) return true;
  // sql/050: kommentaren uten klubb er skrevet av en profil (data.author_profile).
  const authorProfile = str(payload.activity?.data?.author_profile);
  return !!authorProfile && memberUserId(payload, member) === authorProfile;
}

/**
 * Står medlemmet på mottakerlista? null = alle. I en klubb er id-ene medlemmer; i en turnering
 * uten klubb (audience 'competition') er de profiler (sql/034, 050), og medlemmet leses som
 * innloggingen.
 */
export function isRecipient(payload: JobPayload, activity: ActivityPayload, member: MemberPayload): boolean {
  if (activity.recipients === null) return true;
  if (activity.recipients.includes(member.id)) return true;
  if (!profileAudience(payload)) return false;
  const user = memberUserId(payload, member);
  return !!user && activity.recipients.includes(user);
}

/** Bare aktive med innlogging logges. Ledige navn og de som har gått ut, logges ikke. */
function loggable(payload: JobPayload, member: MemberPayload): boolean {
  return member.active && memberUserId(payload, member) !== null;
}

/**
 * Grunnen til at medlemmet ikke får linja, i fast rekkefølge, eller null når det skal ha den.
 * "none" betyr ingen telefon (eller ikke aktivt): ingen push, og ingenting å logge.
 */
function activitySkip(
  payload: JobPayload,
  activity: ActivityPayload,
  m: MemberPayload,
  originators: readonly string[],
  jobReason: SkipReason | null,
): SkipReason | "none" | null {
  if (!m.active) return "none";
  if (isActor(payload, m, activity.actor_member_id)) return "actor";
  if (!isRecipient(payload, activity, m)) return "not_recipient";
  if ((payload.already_notified_ids ?? []).includes(m.id)) return "not_recipient";
  if (jobReason) return jobReason;
  if (m.muted) return "muted";
  if (m.group_off) return "group_off";
  if (!playerAllows(m, activity.category as ActivityCategory)) return "category_off";
  if (hasBlockedAny(m, originators)) return "blocked";
  if (!reachable(m)) return "none";
  return null;
}

function threadSkip(
  payload: JobPayload,
  message: MessagePayload,
  m: MemberPayload,
  fromOrganizer: boolean,
  jobReason: SkipReason | null,
): SkipReason | "none" | null {
  if (!m.active) return "none";
  if (m.id === message.member_id || isActor(payload, m, message.member_id)) return "actor";
  const mode = threadMode(m);
  if (mode === "off") return "category_off";
  if (mode === "mentions" && !fromOrganizer && !(message.mentions ?? []).includes(m.id)) return "not_recipient";
  if (jobReason) return jobReason;
  if (m.muted) return "muted";
  if (m.group_off) return "group_off";
  if (hasBlockedAny(m, [message.member_id])) return "blocked";
  if (!reachable(m)) return "none";
  return null;
}

/** Mottakerne av en linje i aktivitetsloggen. */
export function activityRecipients(payload: JobPayload, activity: ActivityPayload): MemberPayload[] {
  const originators = pushOriginators(payload);
  return payload.members.filter((m) => activitySkip(payload, activity, m, originators, null) === null);
}

/** Mottakerne av en melding i tråden. */
export function threadRecipients(payload: JobPayload, message: MessagePayload): MemberPayload[] {
  const fromOrganizer = payload.members.find((m) => m.id === message.member_id)?.is_organizer ?? false;
  return payload.members.filter((m) => threadSkip(payload, message, m, fromOrganizer, null) === null);
}

/** De som ikke får linja, med grunn. Bare dem med innlogging. */
function activitySkips(payload: JobPayload, activity: ActivityPayload, jobReason: SkipReason | null): MemberSkip[] {
  const originators = pushOriginators(payload);
  return payload.members.flatMap((m) => {
    if (!loggable(payload, m)) return [];
    const reason = activitySkip(payload, activity, m, originators, jobReason);
    return reason && reason !== "none" ? [{ memberId: m.id, reason }] : [];
  });
}

function threadSkips(payload: JobPayload, message: MessagePayload, jobReason: SkipReason | null): MemberSkip[] {
  const fromOrganizer = payload.members.find((m) => m.id === message.member_id)?.is_organizer ?? false;
  return payload.members.flatMap((m) => {
    if (!loggable(payload, m)) return [];
    const reason = threadSkip(payload, message, m, fromOrganizer, jobReason);
    return reason && reason !== "none" ? [{ memberId: m.id, reason }] : [];
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

/** Følgevarslene (sql/054): personlige linjer om følging. */
export const FOLLOW_KINDS: readonly string[] = ["follow_requested", "follow_accepted", "followed"];

/**
 * aps.thread-id for linjene: klubben, eller turneringen når den ikke har klubb (sql/046).
 * Personlige linjer (sql/054): 'follow' for følging, card-<kort> for kommentarer på et kort.
 */
export function activityThreadId(payload: JobPayload): string {
  if (payload.audience === "person") {
    const target = str(payload.activity?.data?.target_id);
    if (!FOLLOW_KINDS.includes(payload.activity?.kind ?? "") && target) return `card-${target}`;
    return "follow";
  }
  if (payload.audience === "competition" && payload.competition?.id) return `competition-${payload.competition.id}`;
  return `club-${payload.club.id ?? payload.competition?.id ?? "ukjent"}`;
}

/**
 * apns-collapse-id: payload.collapse fra 046 (event-<kveld>-<gruppe>) når den finnes, ellers
 * ledelsen i runden og tabellen i konkurransen som før. APNs tillater høyst 64 byte.
 */
export function activityCollapseId(payload: JobPayload, activity: ActivityPayload): string | undefined {
  if (payload.collapse) return payload.collapse.slice(0, 64);
  const competition = str(activity.data?.competition);
  if (activity.kind === "lead_changed" && activity.round_id) return `lead-${activity.round_id}`.slice(0, 64);
  if (activity.kind === "table_changed" && competition) return `table-${competition}`.slice(0, 64);
  return undefined;
}

function planActivity(payload: JobPayload, now: Date): PushPlan {
  const activity = payload.activity;
  if (!activity) return { skipped: "linja finnes ikke", notifications: [], skippedMembers: [] };
  if (activity.round_status === "draft") return { skipped: "kladdrunde", notifications: [], skippedMembers: [] };
  // sql/054: kortet i «Følger» er ikke et varsel.
  if (activity.kind === "round_finished") {
    return { skipped: "round_finished går ikke som push", notifications: [], skippedMembers: [] };
  }
  if (!isActivityCategory(activity.category)) {
    return { skipped: `ukjent kategori ${activity.category}`, notifications: [], skippedMembers: [] };
  }
  if (tooOld(activity.created_at, MAX_AGE_MS.activity, now)) {
    return { skipped: "for gammel", notifications: [], skippedMembers: activitySkips(payload, activity, "too_old") };
  }
  if (!clubAllows(payload.club, activity.category)) {
    return {
      skipped: `${activity.category} er av for klubben`,
      notifications: [],
      skippedMembers: activitySkips(payload, activity, "club_off"),
    };
  }
  const to = activityRecipients(payload, activity);
  const skippedMembers = activitySkips(payload, activity, null);
  if (to.length === 0) return { skipped: "ingen mottakere", notifications: [], skippedMembers };

  const names = nameLookup(payload.members);
  const display = activityDisplay(activity, names, payload.day_term);
  const title = payload.club.name;
  const body = `${display.emoji} ${display.text}`;
  const data: Record<string, string> = { type: "activity", activity_id: activity.id, kind: activity.kind };
  if (activity.event_id) data.event_id = activity.event_id;
  if (activity.round_id) data.round_id = activity.round_id;
  const targetKind = str(activity.data?.target_kind), targetId = str(activity.data?.target_id);
  if (targetKind && targetId) {
    data.target_kind = targetKind;
    data.target_id = targetId;
  }
  const collapseId = activityCollapseId(payload, activity);
  const threadId = activityThreadId(payload);

  return {
    notifications: to.flatMap((m) =>
      m.devices.map((d) => ({
        memberId: m.id,
        token: d.token,
        environment: d.environment,
        title,
        body,
        category: activity.category as PushCategory,
        threadId,
        collapseId,
        data,
      }))
    ),
    skippedMembers,
  };
}

function planThread(payload: JobPayload, now: Date): PushPlan {
  const message = payload.message;
  if (!message) return { skipped: "meldingen finnes ikke", notifications: [], skippedMembers: [] };
  if (message.pushed_at) return { skipped: "pushet fra før", notifications: [], skippedMembers: [] };
  if (tooOld(message.created_at, MAX_AGE_MS.thread, now)) {
    return { skipped: "for gammel", notifications: [], skippedMembers: threadSkips(payload, message, "too_old") };
  }
  if (!clubAllows(payload.club, "thread")) {
    return {
      skipped: "tråden er av for klubben",
      notifications: [],
      skippedMembers: threadSkips(payload, message, "club_off"),
    };
  }
  const to = threadRecipients(payload, message);
  const skippedMembers = threadSkips(payload, message, null);
  if (to.length === 0) return { skipped: "ingen mottakere", notifications: [], skippedMembers };

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
    skippedMembers,
  };
}

// ---------------------------------------------------------------------------
// Loggen (push_log_result i sql/046)
// ---------------------------------------------------------------------------

/** Ett resultat til push_log_result. user_id når vi har den, ellers member_id (klubbens jobber). */
export interface LogResult {
  user_id?: string;
  member_id?: string;
  channel: "push" | "email";
  status: "sent" | "failed" | "skipped";
  reason?: string;
}

/**
 * Loggen for én jobb: skipped med grunn fra planen, og sent eller failed per medlem etter APNs
 * (sent når minst én telefon fikk den). `results` står i samme rekkefølge som
 * plan.notifications (sendAll beholder rekkefølgen). Medlemmer uten innlogging logges ikke.
 */
export function pushLogResults(payload: JobPayload, plan: PushPlan, results: SendResult[] = []): LogResult[] {
  const byId = new Map(payload.members.map((m) => [m.id, m]));
  const who = (memberId: string): Pick<LogResult, "user_id" | "member_id"> | null => {
    const m = byId.get(memberId);
    const user = m ? memberUserId(payload, m) : null;
    if (user) return { user_id: user };
    return null;
  };
  const out: LogResult[] = [];
  for (const s of plan.skippedMembers ?? []) {
    const id = who(s.memberId);
    if (id) out.push({ ...id, channel: "push", status: "skipped", reason: s.reason });
  }
  const perMember = new Map<string, { sent: boolean; reasons: Set<string> }>();
  plan.notifications.forEach((n, i) => {
    const entry = perMember.get(n.memberId) ?? { sent: false, reasons: new Set<string>() };
    const r = results[i];
    if (r && classifyApnsResponse(r.status, r.reason) === "sent") entry.sent = true;
    else entry.reasons.add(r ? `${r.status}${r.reason ? " " + r.reason : ""}` : "ikke sendt");
    perMember.set(n.memberId, entry);
  });
  for (const [memberId, entry] of perMember) {
    const id = who(memberId);
    if (!id) continue;
    out.push(entry.sent
      ? { ...id, channel: "push", status: "sent" }
      : { ...id, channel: "push", status: "failed", reason: [...entry.reasons].join(", ").slice(0, 200) });
  }
  return out;
}

// ---------------------------------------------------------------------------
// Turneringer uten klubb (sql/046): blokkering per innlogging
// ---------------------------------------------------------------------------

/**
 * For audience = 'competition' er medlemmene profiler (id = innloggingen). De som står bak
 * (pushOriginators) kan være klubbmedlemmer eller profiler: `links` gir innloggingen bak
 * klubbmedlemmene, og en id som ikke står der, leses som en profil. Fyller blocked_member_ids
 * med de originators medlemmet har blokkert, og actor_user_id. Ren funksjon.
 */
export function attachCompetitionBlocks(payload: JobPayload, links: MemberLink[], blocks: BlockRow[]): JobPayload {
  const originators = pushOriginators(payload);
  const userOf = new Map(links.filter((l) => l.user_id).map((l) => [l.id, l.user_id!]));
  const resolve = (id: string) => userOf.get(id) ?? id;
  const blockedBy = new Map<string, Set<string>>();
  for (const b of blocks) {
    if (!blockedBy.has(b.blocker_id)) blockedBy.set(b.blocker_id, new Set());
    blockedBy.get(b.blocker_id)!.add(b.blocked_id);
  }
  const actor = payload.activity?.actor_member_id;
  return {
    ...payload,
    actor_user_id: payload.actor_user_id ?? (actor ? userOf.get(actor) ?? null : null),
    members: payload.members.map((m) => {
      const blocked = blockedBy.get(memberUserId(payload, m) ?? "");
      const ids = blocked ? originators.filter((o) => blocked.has(resolve(o))) : [];
      return { ...m, blocked_member_ids: [...new Set([...(m.blocked_member_ids ?? []), ...ids])] };
    }),
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

/** «50 poeng på JA», eller undefined når innsatsen mangler. */
function betStake(side: unknown, points: unknown): string | undefined {
  const p = num(points);
  if (p === undefined || (side !== "yes" && side !== "no")) return undefined;
  return `${p} poeng på ${side === "yes" ? "JA" : "NEI"}`;
}
const num = (v: unknown) => (typeof v === "number" && Number.isFinite(v) ? v : undefined);
const ids = (v: unknown) => (Array.isArray(v) ? v.filter((x): x is string => typeof x === "string") : undefined);

const UNKNOWN: ActivityDisplay = { emoji: "🔔", text: "Ny hendelse i klubben" };

// ---------------------------------------------------------------------------
// Plassbytte i tabellen (table_changed, fase 19). Samme regler og ordlyd som
// TableChangeText i appen (DashDash18/Features/Hjem/TableChange.swift).
// ---------------------------------------------------------------------------

/** Én plass i tabellen etter runden. from mangler når det ikke fantes en plass før. */
export interface TableSpot {
  member: string;
  place: number;
  from?: number;
  points?: number;
}

/** data.table. Én rar plass gjør hele lista ugyldig, som i appen. */
export function tableSpots(v: unknown): TableSpot[] | undefined {
  if (!Array.isArray(v)) return undefined;
  const out: TableSpot[] = [];
  for (const x of v) {
    if (!x || typeof x !== "object") return undefined;
    const o = x as Record<string, unknown>;
    const member = str(o.member), place = num(o.place);
    if (!member || place === undefined) return undefined;
    out.push({ member, place, from: num(o.from), points: num(o.points) });
  }
  return out;
}

export type TableKind = "leads" | "took_lead" | "climbed";

/**
 * Den linja handler om: ny leder går foran (første runde: «leder»), ellers den
 * som klatret flest plasser (likt: best plass). Undefined når ingen klatret.
 */
export function tableSubject(table: TableSpot[]): { spot: TableSpot; kind: TableKind } | undefined {
  const leader = table.find((s) => s.place === 1);
  if (leader) {
    if (table.every((s) => s.from === undefined)) return { spot: leader, kind: "leads" };
    if (leader.from !== 1) return { spot: leader, kind: "took_lead" };
  }
  let best: TableSpot | undefined;
  for (const s of table) {
    const move = s.from === undefined ? 0 : s.from - s.place;
    if (move <= 0) continue;
    const bestMove = best ? best.from! - best.place : 0;
    if (!best || move > bestMove || (move === bestMove && s.place < best.place)) best = s;
  }
  return best ? { spot: best, kind: "climbed" } : undefined;
}

/** «Anders klatret til 3. plass i Jakkeracet etter runde 3» (TableChangeText.headline). */
export function tableHeadline(table: TableSpot[], competitionName: string, roundNo: number | undefined,
  name: NameLookup): string {
  const tail = roundNo !== undefined && roundNo > 0 ? ` etter runde ${roundNo}` : "";
  const subject = tableSubject(table);
  if (!subject) return `Tabellen i ${competitionName} er oppdatert${tail}`;
  const who = name(subject.spot.member);
  switch (subject.kind) {
    case "leads": return `${who} leder ${competitionName}${tail}`;
    case "took_lead": return `${who} har tatt ledelsen i ${competitionName}${tail}`;
    case "climbed": return `${who} klatret til ${subject.spot.place}. plass i ${competitionName}${tail}`;
  }
}

/**
 * «Kvelden» eller «Spilledagen» (DayTerm i appen), eller undefined når ordet ikke er kjent.
 * Godtar appens nøkler (evening, playingDay) og de norske ordene.
 */
export function dayTermThe(term: unknown): string | undefined {
  switch (typeof term === "string" ? term.trim().toLowerCase() : "") {
    case "evening":
    case "kveld":
      return "Kvelden";
    case "playingday":
    case "playing_day":
    case "spilledag":
      return "Spilledagen";
    default:
      return undefined;
  }
}

/**
 * «🏁 Kvelden er i gang: torsdag 8. oktober · Runde 1 – Pebble Beach» (sql/046). Uten kjent
 * ord for dagen: «Runden er i gang», som passer både kveld og spilledag.
 */
export function eveningStartedText(data: Record<string, unknown>, dayTerm?: unknown): string {
  const head = `${dayTermThe(data.day_term ?? dayTerm) ?? "Runden"} er i gang`;
  const date = str(data.event_date) ? eveningLongText(str(data.event_date)!) : undefined;
  const roundNo = num(data.round_no), course = str(data.course_name);
  const round = (roundNo !== undefined && roundNo > 0) || course ? roundTitle(roundNo, course) : undefined;
  const parts = [date, round].filter((x): x is string => !!x);
  return parts.length ? `${head}: ${parts.join(" · ")}` : head;
}

/** «Anders har sendt sin del for Simulatorleie» (sql/051, til mottakeren). */
export function billShareSentText(data: Record<string, unknown>): string {
  return `${str(data.name)?.trim() || "Noen"} har sendt sin del for ${str(data.title)?.trim() || "regningen"}`;
}

/** «Thomas sier at din del for Simulatorleie ikke kom» (sql/051, til den som skal betale). */
export function billShareDisputedText(data: Record<string, unknown>): string {
  return `${str(data.name)?.trim() || "Mottakeren"} sier at din del for ${str(data.title)?.trim() || "regningen"} ikke kom`;
}

/** Teksten for en linje. Mangler et felt hendelsen ikke klarer seg uten, blir den den nøytrale teksten. */
export function activityDisplay(activity: ActivityPayload, name: NameLookup, dayTerm?: unknown): ActivityDisplay {
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
    // sql/046: én per kveld, skrevet av serveren når den første runden starter.
    case "evening_started":
      return { emoji: "🏁", text: eveningStartedText(d, dayTerm) };
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
    // sql/045: skrevet av serveren. Opprykket går bare til den som fikk plass (recipients).
    case "waitlist_promoted": {
      const date = evening(d.event_date), guest = str(d.guest_name);
      const when = date ? ` ${date}` : "";
      return { emoji: "🎉", text: guest ? `${guest} har fått plass${when} (gjesten din)` : `Du har fått plass${when}` };
    }
    case "signup_dropped": {
      const member = str(d.member), date = evening(d.event_date);
      if (!member) return UNKNOWN;
      return { emoji: "↩️", text: `${who(member)} har meldt seg av` + (date ? ` ${date}` : "") + (d.late === true ? " etter fristen" : "") };
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
      let text = "Påminnelse: " + (date ? `${date} om en uke` : "neste runde nærmer seg");
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
    // Veddemål (012): samme ordlyd som appen (ActivityText), PWA-ens tekster med poeng for kroner.
    case "bet_challenge": {
      const question = str(d.question), against = str(d.against);
      if (!question || !against) return UNKNOWN;
      const stake = betStake(d.side, d.points);
      return { emoji: "⚔️", text: `${actor} utfordret ${who(against)}: «${question}»${stake ? ` — ${stake}` : ""}` };
    }
    case "bet_created": {
      const question = str(d.question);
      if (!question) return UNKNOWN;
      const stake = betStake(d.side, d.points);
      return { emoji: "📈", text: `${actor} åpnet «${question}»${stake ? ` og satset ${stake}` : ""}` };
    }
    case "bet_resolved": {
      const question = str(d.question), resolution = str(d.resolution);
      if (!question || !resolution) return UNKNOWN;
      if (resolution === "yes" || resolution === "no") {
        return { emoji: "🏆", text: `Veddemål avgjort: «${question}» → ${resolution === "yes" ? "JA" : "NEI"}` };
      }
      return { emoji: "↩️", text: `Veddemål annullert: «${question}»` };
    }
    // Del regningen (sql/051): data.title og data.name (den som betalte, eller mottakeren).
    case "bill_share_sent":
      return { emoji: "💸", text: billShareSentText(d) };
    case "bill_share_disputed":
      return { emoji: "❓", text: billShareDisputedText(d) };
    case "table_changed": {
      const competition = str(d.competition), competitionName = str(d.competition_name);
      const table = tableSpots(d.table);
      if (!competition || !competitionName || !table?.length) return UNKNOWN;
      return { emoji: "📊", text: tableHeadline(table, competitionName, num(d.round_no), name) };
    }
    // sql/050: skrevet av serveren til mottakerne (forfatteren av målet, de som følger, de som nevnes).
    case "comment_added":
    case "mentioned": {
      const author = str(d.author_name) ?? actor;
      const quote = quotedPreview(d.preview);
      // sql/054: på et kort i «Følger» (personlig linje uten klubb og turnering).
      const card = !!activity.actor_profile_id && d.target_kind === "activity";
      const verb = activity.kind === "mentioned" ? "nevnte deg" : card ? "kommenterte runden" : "kommenterte";
      return { emoji: "💬", text: `${author} ${verb}${quote ? `: ${quote}` : ""}` };
    }
    // sql/054: følging. Navnet står i data.actor_name.
    case "follow_requested":
      return { emoji: "👋", text: `${actorName(d)} vil følge deg` };
    case "follow_accepted":
      return { emoji: "✅", text: `${actorName(d)} godtok forespørselen din` };
    case "followed":
      return { emoji: "👋", text: `${actorName(d)} følger deg nå` };
    case "photo_prompt":
      return { emoji: "📸", text: PHOTO_PROMPT_TEXT };
    default:
      return UNKNOWN;
  }
}

/** Navnet på den som vil følge, godtok eller følger (sql/054, data.actor_name). */
function actorName(d: Record<string, unknown>): string {
  return str(d.actor_name)?.trim() || "Noen";
}

/** Bildeoppfordringen (sql/050), som PhotoPrompt.title i appen. */
export const PHOTO_PROMPT_TEXT = "Ta et bilde av gjengen";
/** Lengden på sitatet i comment_added og mentioned (SocialComment.previewLength i appen). */
export const COMMENT_PREVIEW_MAX = 80;

/** «Hei der» i sitattegn, på én linje og kuttet, eller undefined når den er tom. */
export function quotedPreview(preview: unknown): string | undefined {
  const clean = String(preview ?? "").replace(/\s+/g, " ").trim();
  if (!clean) return undefined;
  const chars = Array.from(clean);
  const short = chars.length > COMMENT_PREVIEW_MAX ? chars.slice(0, COMMENT_PREVIEW_MAX - 1).join("") + "…" : clean;
  return `«${short}»`;
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
