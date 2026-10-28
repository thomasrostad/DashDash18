// Gjenbruk (sql/049, gjennomføringsplanen steg 8): spilledager i serie, egne maler og «Samme som sist».
// Ren logikk uten nettverk og React, så den kan testes med node --test. Nøklene i malene er de samme som
// i appen (SetupTemplates.swift); databasen sjekker bare formen.

import {
  canStartAtTen, keepOnly, venueFromStored, type BaySeat, type MatchDraft, type RosterMember, type RoundDraft, type UUID, type Venue,
} from "./rounds/logic.ts";
import { copiedCompetitions } from "./rounds/competitions.ts";
import { decodeStoredCompetition, type StoredCompetition } from "../../golfgutu-core/src/index.ts";

// MARK: - Serie av spilledager

const WEEKDAYS = ["mandag", "tirsdag", "onsdag", "torsdag", "fredag", "lørdag", "søndag"];

/** ISO-ukedag (1 = mandag … 7 = søndag) for «YYYY-MM-DD». */
export function isoWeekday(iso: string): number {
  const [y, m, d] = iso.split("-").map(Number);
  const day = new Date(Date.UTC(y, m - 1, d)).getUTCDay();
  return day === 0 ? 7 : day;
}

export function addDays(iso: string, days: number): string {
  const [y, m, d] = iso.split("-").map(Number);
  return new Date(Date.UTC(y, m - 1, d + days)).toISOString().slice(0, 10);
}

/** «mandag» … «søndag» for ISO 1–7. */
export function weekdayName(weekday: number): string {
  return WEEKDAYS[(weekday - 1 + 7) % 7] ?? "";
}

/**
 * Datoene `create_event_series` lager (før de som alt er tatt hoppes over): første dato fra og med
 * `start` med riktig ukedag, så hver `everyWeeks` uke, `count` datoer i alt.
 */
export function seriesDates(start: string, weekday: number, count: number, everyWeeks = 1): string[] {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(start) || weekday < 1 || weekday > 7 || count < 1) return [];
  const first = addDays(start, (weekday - isoWeekday(start) + 7) % 7);
  return Array.from({ length: Math.min(count, 52) }, (_, i) => addDays(first, i * 7 * Math.max(1, everyWeeks)));
}

/** «18», «18.30» av «18:00:00» / «18:30». */
function shortTime(t: string): string {
  const [h, m] = t.split(":");
  return m && m !== "00" ? `${Number(h)}.${m}` : `${Number(h)}`;
}

/** «Hver torsdag kl. 18», «Annenhver tirsdag», «Hver 3. uke på mandag kl. 18.30». */
export function seriesText(s: { weekday: number; every_weeks: number; start_time: string | null }): string {
  const day = weekdayName(s.weekday);
  const base = s.every_weeks <= 1 ? `Hver ${day}` : s.every_weeks === 2 ? `Annenhver ${day}` : `Hver ${s.every_weeks}. uke på ${day}`;
  return s.start_time ? `${base} kl. ${shortTime(s.start_time)}` : base;
}

/** Svaret fra `create_event_series`. */
export interface SeriesResult { series_id: string | null; event_ids: string[]; dates: string[]; skipped: string[] }

/** Svaret fra `update_event_series`. */
export interface SeriesUpdateResult { updated: string[]; skipped: string[]; shifted_days: number }

// MARK: - Maler

export type TemplateKind = "round" | "tournament";

export interface SetupTemplate {
  id: string;
  club_id: string | null;
  owner_id: string | null;
  kind: TemplateKind;
  name: string;
  payload: Record<string, unknown>;
  updated_at?: string;
}

export interface GameTemplate { kind: string; settings: Record<string, unknown> }

/** Rundemalen (kind = round), og rundedelen av `previous_round_setup`. */
export interface RoundTemplate {
  courseID: UUID | null;
  teeID: UUID | null;
  holeCount: number;
  firstHole: number;
  format: string | null;
  allowance: number | null;
  externalHandicap: boolean | null;
  venue: Venue | null;
  ldEnabled: boolean | null;
  ldHoleIndex: number | null;
  kpEnabled: boolean | null;
  kpHoleIndex: number | null;
  weight: number;
  counts: boolean;
  pointsTable: string | null;
  hideLastHoles: number;
  games: GameTemplate[];
}

export interface ScheduleTemplate {
  weekday: number;
  everyWeeks: number;
  count: number;
  /** «HH:MM» eller null. */
  startTime: string | null;
  venue: string | null;
}

export type SetupKind = "stablefordSeries" | "strokeSeries" | "matchSeries" | "cup" | "fun" | "amerikanerSeries" | "kobenhavnerSeries" | "skinsSeries" | "teamVsTeam";

/** Turneringsmalen (kind = tournament). */
export interface TournamentTemplate {
  template: SetupKind | null;
  kind: "season" | "league" | "cup" | "fun" | null;
  rules: Record<string, unknown> | null;
  schedule: ScheduleTemplate | null;
  venue: string | null;
  entry: "listed" | "club" | "open" | null;
  signupOpen: boolean | null;
  maxEntrants: number | null;
}

type Json = Record<string, unknown>;
const obj = (v: unknown): Json | null => (v !== null && typeof v === "object" && !Array.isArray(v) ? (v as Json) : null);
const str = (v: unknown): string | null => (typeof v === "string" && v.length > 0 ? v : null);
const num = (v: unknown): number | null => (typeof v === "number" && Number.isFinite(v) ? v : typeof v === "string" && v.trim() !== "" && Number.isFinite(Number(v)) ? Number(v) : null);
const int = (v: unknown): number | null => { const n = num(v); return n === null ? null : Math.round(n); };
const bool = (v: unknown): boolean | null => (typeof v === "boolean" ? v : null);
const oneOf = <T extends string>(v: unknown, allowed: readonly T[]): T | null => (allowed.includes(v as T) ? (v as T) : null);

/** Rundedelen fra en mal eller fra `previous_round_setup`. Tåler manglende og ukjente nøkler. */
export function decodeRoundTemplate(raw: unknown): RoundTemplate {
  const p = obj(raw) ?? {};
  const holeCount = int(p.hole_count) === 9 ? 9 : 18;
  return {
    courseID: str(p.course_id),
    teeID: str(p.tee_id),
    holeCount,
    firstHole: int(p.first_hole) === 10 ? 10 : 1,
    format: str(p.format),
    allowance: num(p.handicap_allowance),
    externalHandicap: bool(p.external_handicap),
    venue: p.venue === "course" || p.venue === "simulator" ? p.venue : null,
    ldEnabled: bool(p.ld_enabled),
    ldHoleIndex: int(p.ld_hole_index),
    kpEnabled: bool(p.kp_enabled),
    kpHoleIndex: int(p.kp_hole_index),
    weight: num(p.weight) ?? 1,
    counts: bool(p.counts) ?? true,
    pointsTable: str(p.points_table),
    hideLastHoles: Math.max(0, int(p.hide_last_holes) ?? 0),
    games: Array.isArray(p.games)
      ? p.games.flatMap((g) => { const o = obj(g); const kind = o && str(o.kind); return kind ? [{ kind, settings: obj(o.settings) ?? {} }] : []; })
      : [],
  };
}

/** Malen av oppsettet slik det står. Spillerne blir aldri med. */
export function encodeRoundTemplate(d: RoundDraft, games: GameTemplate[] = []): Json {
  return {
    version: 1,
    course_id: d.courseID,
    tee_id: d.teeID,
    hole_count: d.holeCount,
    first_hole: d.holeCount === 9 && d.firstHole === 10 ? 10 : 1,
    format: d.formID,
    handicap_allowance: Math.round(d.allowance * 1000) / 1000,
    external_handicap: d.externalHandicap,
    venue: d.venue,
    ld_enabled: d.ldEnabled,
    ld_hole_index: d.ldHoleIndex,
    kp_enabled: d.kpEnabled,
    kp_hole_index: d.kpHoleIndex,
    weight: d.weight,
    counts: d.counts,
    points_table: d.pointsTable,
    hide_last_holes: d.hideLastHoles,
    games,
  };
}

/**
 * Fyller oppsettet fra en mal eller forrige runde: sted, bane og tee (bare når banen er klar), start, form og
 * andel (bare når formen er tillatt), handicap, LD og KP, vekt og tabellreglene. Spillerne røres ikke.
 */
export function applyRoundTemplate(d: RoundDraft, t: RoundTemplate,
  courses: readonly { id: UUID; isReady: boolean; holeCount: number; teeIDs: UUID[] }[],
  allowedFormIDs: readonly string[], tableRules = true): RoundDraft {
  let out: RoundDraft = { ...d, weight: t.weight };
  if (t.venue) out.venue = t.venue;
  if (t.externalHandicap !== null) out.externalHandicap = out.venue === "course" ? false : t.externalHandicap;
  if (t.format && allowedFormIDs.includes(t.format)) {
    if (t.format !== out.formID) out = { ...out, formID: t.format, teams: {}, matches: [] };
    if (t.allowance !== null) out.allowance = t.allowance;
  }
  if (t.ldEnabled !== null) out.ldEnabled = t.ldEnabled;
  if (t.kpEnabled !== null) out.kpEnabled = t.kpEnabled;
  if (tableRules) out = { ...out, counts: t.counts, pointsTable: t.pointsTable, hideLastHoles: t.hideLastHoles };
  const course = courses.find((c) => c.id === t.courseID && c.isReady);
  if (!course) return out;
  return {
    ...out,
    courseID: course.id,
    teeID: t.teeID !== null && course.teeIDs.includes(t.teeID) ? t.teeID : null,
    holeCount: t.holeCount,
    firstHole: canStartAtTen(t.holeCount, course.holeCount) ? t.firstHole : 1,
    ldHoleIndex: t.ldHoleIndex !== null && t.ldHoleIndex < t.holeCount ? t.ldHoleIndex : null,
    kpHoleIndex: t.kpHoleIndex !== null && t.kpHoleIndex < t.holeCount ? t.kpHoleIndex : null,
  };
}

export function decodeTournamentTemplate(raw: unknown): TournamentTemplate {
  const p = obj(raw) ?? {};
  const s = obj(p.schedule);
  const weekday = s ? int(s.weekday) : null;
  const schedule: ScheduleTemplate | null = s && weekday !== null && weekday >= 1 && weekday <= 7 ? {
    weekday,
    everyWeeks: Math.min(8, Math.max(1, int(s.every_weeks) ?? 1)),
    count: Math.min(52, Math.max(1, int(s.count) ?? 1)),
    startTime: str(s.start_time)?.slice(0, 5) ?? null,
    venue: str(s.venue),
  } : null;
  return {
    template: oneOf(p.template, ["stablefordSeries", "strokeSeries", "matchSeries", "cup", "fun", "amerikanerSeries", "kobenhavnerSeries", "skinsSeries", "teamVsTeam"] as const),
    kind: oneOf(p.kind, ["season", "league", "cup", "fun"] as const),
    rules: obj(p.rules),
    schedule,
    venue: str(p.venue),
    entry: oneOf(p.entry, ["listed", "club", "open"] as const),
    signupOpen: bool(p.signup_open),
    maxEntrants: int(p.max_entrants),
  };
}

export function encodeTournamentTemplate(t: TournamentTemplate): Json {
  return {
    version: 1,
    template: t.template,
    kind: t.kind,
    rules: t.rules,
    schedule: t.schedule ? {
      weekday: t.schedule.weekday, every_weeks: t.schedule.everyWeeks, count: t.schedule.count,
      start_time: t.schedule.startTime, venue: t.schedule.venue,
    } : null,
    venue: t.venue,
    entry: t.entry,
    signup_open: t.signupOpen,
    max_entrants: t.maxEntrants,
  };
}

/** Malnavn: 1–60 tegn, unikt per type (uten hensyn til store og små bokstaver). */
export function templateNameError(name: string, existing: readonly SetupTemplate[], kind: TemplateKind, editingID: string | null = null): string | null {
  const n = name.trim();
  if (n.length === 0) return "Gi malen et navn.";
  if (n.length > 60) return "Navnet kan ha høyst 60 tegn.";
  if (existing.some((t) => t.kind === kind && t.id !== editingID && t.name.trim().toLowerCase() === n.toLowerCase())) {
    return `Det finnes alt en mal med navnet «${n}».`;
  }
  return null;
}

// MARK: - «Samme som sist»

export interface PreviousSetup {
  roundID: string;
  eventDate: string | null;
  roundNo: number;
  round: RoundTemplate;
  players: { memberID: UUID; bayNo: number | null; isMarker: boolean; teamNo: number | null; seedGroup: number | null; side?: 1 | 2 | null }[];
  /** sql/048: konkurransene i forrige runde (uten id). Tom før 048. */
  competitions: StoredCompetition[];
  matches: { matchNo: number; playerA: UUID | null; playerB: UUID | null; playerC: UUID | null; teamA: number | null; teamB: number | null }[];
}

/** Svaret fra `previous_round_setup`, eller null (ingen runde). */
export function decodePreviousSetup(raw: unknown): PreviousSetup | null {
  const p = obj(raw);
  const roundID = p && str(p.round_id);
  if (!p || !roundID) return null;
  const list = (v: unknown) => (Array.isArray(v) ? v.map(obj).filter((x): x is Json => x !== null) : []);
  return {
    roundID,
    eventDate: str(p.event_date),
    roundNo: int(p.round_no) ?? 1,
    round: decodeRoundTemplate(p),
    players: list(p.players).flatMap((x) => {
      const id = str(x.member_id);
      const side = int(x.side);
      return id ? [{ memberID: id, bayNo: int(x.bay_no), isMarker: bool(x.is_marker) ?? false, teamNo: int(x.team_no), seedGroup: int(x.seed_group),
        side: side === 1 || side === 2 ? side : null }] : [];
    }),
    competitions: (Array.isArray(p.competitions) ? p.competitions : []).map(decodeStoredCompetition).filter((c): c is StoredCompetition => c !== null),
    matches: list(p.matches).map((x, i) => ({
      matchNo: int(x.match_no) ?? i + 1, playerA: str(x.player_a), playerB: str(x.player_b), playerC: str(x.player_c),
      teamA: int(x.team_a), teamB: int(x.team_b),
    })).sort((a, b) => a.matchNo - b.matchNo),
  };
}

/**
 * «Bruk spillerne fra sist»: de samme spillerne (bare dem som fortsatt er i troppen), båsene, markørene, lagene
 * og matchene. Matcher med noen som ikke er med lenger, faller bort.
 */
export function applyPreviousPlayers(d: RoundDraft, prev: PreviousSetup, roster: readonly RosterMember[]): RoundDraft {
  const inRoster = new Set(roster.map((m) => m.id));
  const wanted = new Set(prev.players.map((p) => p.memberID).filter((id) => inRoster.has(id)));
  const participants = roster.map((m) => m.id).filter((id) => wanted.has(id));
  const bays: BaySeat[] = keepOnly(prev.players.filter((p) => p.bayNo !== null && wanted.has(p.memberID))
    .map((p) => ({ memberID: p.memberID, bay: p.bayNo!, isMarker: p.isMarker })), wanted);
  // Var markøren i båsen borte, blir den første i båsen markør.
  for (const bay of new Set(bays.map((s) => s.bay))) {
    if (!bays.some((s) => s.bay === bay && s.isMarker)) bays.find((s) => s.bay === bay)!.isMarker = true;
  }
  const teams: Record<UUID, number> = {};
  for (const p of prev.players) if (p.teamNo !== null && wanted.has(p.memberID)) teams[p.memberID] = p.teamNo;
  const ok = (id: UUID | null) => id === null || wanted.has(id);
  const matches: MatchDraft[] = prev.matches
    .filter((m) => ok(m.playerA) && ok(m.playerB) && ok(m.playerC))
    .map((m) => ({ playerA: m.playerA, playerB: m.playerB, playerC: m.playerC, teamA: m.teamA, teamB: m.teamB, result: null }));
  const sides: Record<UUID, 1 | 2> = {};
  for (const p of prev.players) if ((p.side === 1 || p.side === 2) && wanted.has(p.memberID)) sides[p.memberID] = p.side;
  // Sidene bare når 048 er kjørt (utkastet har da `sides`), eller forrige runde hadde sider.
  const withSides = d.sides !== undefined || Object.keys(sides).length > 0 ? { sides } : {};
  return { ...d, participants, participantSource: "saved", bays, teams, matches, ...withSides };
}

/** «Samme som sist» med konkurransene fra forrige runde som nye rader (sql/048). */
export function applyPreviousCompetitions(d: RoundDraft, prev: PreviousSetup): RoundDraft {
  return { ...d, competitions: copiedCompetitions(prev.competitions) };
}

export { venueFromStored };
