// Lesing og skriving for rundene på en spilledag. Samme tabeller, RPC-er og rekkefølge som appen
// (RundeAdminModel.swift, RoundReviewModel/EveningCloser i AvslutningModel.swift, RundeQueries.snapshot,
// DirectScoreSubmitter, StartListModel). RLS og RPC-ene er tilgangskontrollen.

import { supabase } from "../supabase.ts";
import type { Competition, EventRow } from "../data.ts";
import { eveningSignups } from "../signupsApi.ts";
import { isMissing } from "../signups.ts";
import {
  decodeCourseHoleRecord, decodeCourseRow, decodeHoleScoreRow, decodeRoundHoleRow, decodeRoundMatchRow, decodeRoundPlayerRow,
  decodeRoundRow, decodeRuleset, decodeSideClaimRow, GOLFGUTU, makeSnapshot, rulesetDay,
  type CourseHoleRecord, type DayTerm, type RoundMatchRow, type RoundPlayerRow, type RoundRow, type Ruleset,
} from "../../../golfgutu-core/src/index.ts";
import {
  coreCourseWithTee, courseItemReady, findTee, makeCourseItem, type CourseItem, type CourseKind, type CourseTee, type SlopeCourse,
} from "./courses.ts";
import { RoundGame, cutPatch, cutPatchMatches, type CutChoice } from "./game.ts";
import {
  blockingRound, dataErrorText, draftForm, drawPlan, type DrawPlan, deletedMessage, mainActiveSeason, mainSeasonIDs, roundTitle, saveErrorText, setupIssues, setupParams, startErrorText, issueMessage,
  groupTerm, roundWrite, sortedByName, tableRulesPatch, type DeleteSummary, type RosterMember, type RoundDraft, type SignupRow,
} from "./logic.ts";
import { startListParams, type StartGroupDraft, type StartGroupRow } from "./startlist.ts";
import {
  competitionIssues, competitionsPayload, draftsFromStored, sideProblem, sidesFromRows, withSides, type CompetitionContext,
} from "./competitions.ts";
import { decodeStoredCompetition, isTeamForm as coreIsTeamForm, snapshotFields, type SnapshotFields, type StoredCompetition } from "../../../golfgutu-core/src/index.ts";

const ROUND_COLUMNS = "id, club_id, event_id, course_id, round_no, name, status, hole_count, first_hole, tee_time, format, "
  + "handicap_allowance, external_handicap, weight, ld_enabled, ld_hole_index, kp_enabled, kp_hole_index, cut_rule, cut_after, "
  + "started_at, locked_at, venue, tee_id, tee_name, course_rating, slope_rating, tee_par, wave_no";
/** sql/047: tabellreglene og playoffen på runden. */
export const TABLE_RULES_COLUMNS = "counts, points_table, hide_last_holes, kind, playoff_for, playoff_holes";
const PLAYER_COLUMNS = "round_id, member_id, club_id, handicap_index, seed_group, playing_handicap, bay_no, is_marker, team_no";
const COURSE_COLUMNS = "id, club_id, name, external_name, course_rating, slope_rating, in_use, kind";
const TEE_COLUMNS = "id, course_id, name, gender, course_rating, slope_rating, par, sort_order";

let tableRulesProbe: Promise<boolean> | null = null;

/**
 * Finnes kolonnene fra sql/047? Spørres én gang per økt. Uten dem hentes rundene med de gamle kolonnene
 * (standardverdiene gjelder), og valgene for tabellreglene og playoffen vises ikke.
 */
export function hasTableRules(): Promise<boolean> {
  tableRulesProbe ??= Promise.resolve(supabase.from("rounds").select("kind").limit(1)).then(
    ({ error }) => {
      if (error && !isMissing(error.code)) tableRulesProbe = null; // prøv igjen neste gang
      return !error;
    },
    () => { tableRulesProbe = null; return false; },
  );
  return tableRulesProbe;
}

let formatsProbe: Promise<boolean> | null = null;

/**
 * Finnes sql/048 (round_competitions, round_players.side, øyeblikksbildet)? Spørres én gang per økt. Uten den
 * vises ikke konkurransene, sidene eller «Oppdater øyeblikksbildet», og alt annet er som før.
 */
export function hasFormats(): Promise<boolean> {
  formatsProbe ??= Promise.resolve(supabase.from("round_competitions").select("id").limit(1)).then(
    ({ error }) => {
      if (error && !isMissing048(error.code)) formatsProbe = null;
      return !error;
    },
    () => { formatsProbe = null; return false; },
  );
  return formatsProbe;
}

/** Tabell, kolonne eller funksjon fra 048 finnes ikke. */
export function isMissing048(code: string | null | undefined): boolean {
  return isMissing(code) || ["PGRST205", "PGRST200"].includes(code ?? "");
}

/** Kolonnene for `rounds`, med sql/047 når den er kjørt. */
export async function roundColumns(): Promise<string> {
  return (await hasTableRules()) ? `${ROUND_COLUMNS}, ${TABLE_RULES_COLUMNS}` : ROUND_COLUMNS;
}

/** En runde i lista, med det appens `RoundRow` har og tidspunktene. */
export type ListRound = RoundRow & { startedAt: string | null; lockedAt: string | null; waveNo: number };

/** Feil med teksten som vises (allerede på norsk). */
export class RoundError extends Error {}

function fail(e: unknown, text = dataErrorText): never {
  if (e instanceof RoundError) throw e;
  throw new RoundError(text(e));
}

function decodeListRound(x: Record<string, unknown>): ListRound {
  return {
    ...decodeRoundRow(x),
    startedAt: (x.started_at as string | null) ?? null,
    lockedAt: (x.locked_at as string | null) ?? null,
    waveNo: (x.wave_no as number | null) ?? 1,
  };
}

// MARK: - Spilledagen

export interface DayData {
  rules: Ruleset;
  dayTerm: DayTerm;
  /** Aktive medlemmer, sortert på navn. */
  roster: RosterMember[];
  signups: SignupRow[];
  /** Alle rundene i klubben. Kladder ser bare arrangørene (RLS). */
  allRounds: ListRound[];
  /** Deltakerne per runde. */
  players: Map<string, RoundPlayerRow[]>;
  /** Klubbens baner og hentede baner som rundene peker på. */
  courses: CourseItem[];
  /** Mitt medlemskap i klubben (`cut_by`). */
  myMemberID: string | null;
  /** Rundene i turneringen dagen hører til (til trekningen uten gjentakelser). */
  seasonRoundIDs: string[];
  /** Matchene i turneringens runder. Hentes bare når trekningen er «uten gjentakelser» (steg 6). */
  seasonMatches: RoundMatchRow[];
  /** sql/047 er kjørt: «Teller ikke», poengtabell og «Skjul de tre siste hullene» kan velges. */
  tableRules: boolean;
  /** sql/048 er kjørt: konkurranser i runden, lag mot lag og øyeblikksbildet. */
  formats?: boolean;
}

/** Trekningen for en runde på dagen: regelsettets `formats.drawMethod`, med møtene i turneringens andre runder. */
export function dayDrawPlan(data: DayData, roundID: string | null): DrawPlan {
  const ids = new Set(data.seasonRoundIDs);
  return drawPlan(data.rules, data.allRounds.filter((r) => ids.has(r.id)), data.seasonMatches, data.players, roundID);
}

/** Rundene på turneringens dager, og matchene deres når trekningen trenger dem (`loadSeasonMatches` i appen). */
async function loadSeasonHistory(event: EventRow, rules: Ruleset, allRounds: readonly ListRound[]): Promise<{ ids: string[]; matches: RoundMatchRow[] }> {
  if ((rules.formats.drawMethod ?? "standings") !== "avoidRepeats") return { ids: [], matches: [] };
  const column = event.season_id ? "season_id" : event.competition_id ? "competition_id" : null;
  const value = event.season_id ?? event.competition_id;
  if (column === null || value === null) return { ids: [], matches: [] };
  const { data: days, error } = await supabase.from("events").select("id").eq(column, value);
  if (error) throw error;
  const dayIDs = new Set(((days ?? []) as { id: string }[]).map((d) => d.id.toLowerCase()));
  const ids = allRounds.filter((r) => r.eventID !== null && dayIDs.has(r.eventID) && r.status !== "draft").map((r) => r.id);
  const matches: RoundMatchRow[] = [];
  for (let i = 0; i < ids.length; i += 100) {
    const { data, error: mErr } = await supabase.from("round_matches")
      .select("round_id, match_no, player_a, player_b, player_c, team_a, team_b, result").in("round_id", ids.slice(i, i + 100));
    if (mErr) throw mErr;
    matches.push(...((data ?? []) as unknown[]).map((x) => decodeRoundMatchRow(x)));
  }
  return { ids, matches };
}

/** Turneringen dagen hører til: sesongens (`season_id`) eller turneringens egen (`competition_id`). */
export function competitionFor(e: EventRow, comps: readonly Competition[]): Competition | null {
  return comps.find((c) => (e.season_id && c.season_id === e.season_id) || (!e.season_id && e.competition_id && c.id === e.competition_id)) ?? null;
}

/**
 * Regelsettet for dagen (`RoundListing.rules`, `RundeAdminModel.rules`): sesongens, eller turneringens egne
 * på en spilledag i liga, cup og morro, ellers den aktive sesongens, ellers Golfgutu-oppsettet.
 */
async function rulesFor(clubID: string, e: EventRow, comps: readonly Competition[]): Promise<Ruleset> {
  const { data, error } = await supabase.from("seasons").select("id, status, rules").eq("club_id", clubID);
  if (error) throw error;
  const seasons = (data ?? []) as { id: string; status: string; rules: unknown }[];
  if (e.season_id) {
    const s = seasons.find((x) => x.id === e.season_id);
    if (s) return decodeRuleset(s.rules);
  }
  if (!e.season_id && e.competition_id) {
    const c = comps.find((x) => x.id === e.competition_id);
    if (c) return decodeRuleset(c.rules);
  }
  // Flere serier kan være aktive (sql/034): uten kveldens sesong gjelder hovedturneringen.
  const active = mainActiveSeason(seasons, mainSeasonIDs(comps));
  return active ? decodeRuleset(active.rules) : GOLFGUTU;
}

async function loadTees(courseIDs: string[]): Promise<CourseTee[]> {
  if (courseIDs.length === 0) return [];
  const { data, error } = await supabase.from("course_tees").select(TEE_COLUMNS).in("course_id", courseIDs).is("missing_at", null);
  if (error) throw error;
  const tees = (data ?? []) as Record<string, unknown>[];
  if (tees.length === 0) return [];
  const holeRows: Record<string, unknown>[] = [];
  const ids = tees.map((t) => t.id as string);
  for (let i = 0; i < ids.length; i += 100) {
    const { data: h, error: hErr } = await supabase.from("course_tee_holes")
      .select("tee_id, hole_number, par, stroke_index, length_m").in("tee_id", ids.slice(i, i + 100));
    if (hErr) throw hErr;
    holeRows.push(...((h ?? []) as Record<string, unknown>[]));
  }
  return tees.map((t) => ({
    id: t.id as string,
    courseID: t.course_id as string,
    name: t.name as string,
    gender: (t.gender as CourseTee["gender"]) ?? "mixed",
    courseRating: Number(t.course_rating),
    slopeRating: Number(t.slope_rating),
    par: (t.par as number | null) ?? null,
    sortOrder: (t.sort_order as number | null) ?? 0,
    holes: holeRows.filter((h) => h.tee_id === t.id)
      .map((h) => ({ courseID: t.course_id as string, holeNumber: h.hole_number as number, par: h.par as number, strokeIndex: (h.stroke_index as number | null) ?? null, lengthM: (h.length_m as number | null) ?? null }))
      .sort((a, b) => a.holeNumber - b.holeNumber),
  }));
}

/** Baner med hull, type og tees. `fromSource`: hentet fra slope.no (alltid ekte bane). */
async function loadCourseItems(rows: Record<string, unknown>[], fromSource: boolean): Promise<CourseItem[]> {
  if (rows.length === 0) return [];
  const ids = rows.map((r) => r.id as string);
  const { data, error } = await supabase.from("course_holes").select("course_id, hole_number, par, stroke_index, length_m").in("course_id", ids);
  if (error) throw error;
  const holes = ((data ?? []) as unknown[]).map((h) => decodeCourseHoleRecord(h));
  const tees = await loadTees(ids);
  return rows.map((r) => {
    const row = decodeCourseRow(r);
    const kind: CourseKind | null = fromSource ? "course" : ((r.kind as CourseKind | null) ?? null);
    return makeCourseItem(row, holes.filter((h: CourseHoleRecord) => h.courseID === row.id), kind, tees.filter((t) => t.courseID === row.id), fromSource);
  });
}

/** Hentede baner (slope.no) med hull og tees, slik de spilles direkte. */
export async function loadSourceCourses(ids: string[]): Promise<CourseItem[]> {
  if (ids.length === 0) return [];
  const { data, error } = await supabase.from("courses").select(COURSE_COLUMNS).in("id", ids).not("source", "is", null);
  if (error) throw error;
  return loadCourseItems((data ?? []) as Record<string, unknown>[], true);
}

export async function loadDay(clubID: string, event: EventRow, comps: readonly Competition[]): Promise<DayData> {
  try {
    const user = (await supabase.auth.getUser()).data.user;
    const [tableRules, formats] = await Promise.all([hasTableRules(), hasFormats()]);
    const columns = tableRules ? `${ROUND_COLUMNS}, ${TABLE_RULES_COLUMNS}` : ROUND_COLUMNS;
    const [rules, membersRes, coursesRes, roundsRes, signupsRes, meRes] = await Promise.all([
      rulesFor(clubID, event, comps),
      supabase.from("club_members").select("id, display_name, handicap_index, seed_group, user_id").eq("club_id", clubID).eq("status", "active"),
      supabase.from("courses").select(COURSE_COLUMNS).eq("club_id", clubID),
      supabase.from("rounds").select(columns).eq("club_id", clubID).order("round_no"),
      eveningSignups(event.id).then((data) => ({ data, error: null }), (error) => ({ data: null, error })),
      user ? supabase.from("club_members").select("id").eq("club_id", clubID).eq("user_id", user.id).limit(1) : Promise.resolve({ data: [], error: null }),
    ]);
    for (const r of [membersRes, coursesRes, roundsRes, signupsRes]) if (r.error) throw r.error;
    const roster = sortedByName(((membersRes.data ?? []) as Record<string, unknown>[]).map((m) => ({
      id: m.id as string, name: m.display_name as string, handicap: (m.handicap_index as number | null) ?? null,
      seed: (m.seed_group as number | null) ?? null, userID: (m.user_id as string | null) ?? null,
    })));
    const allRounds = ((roundsRes.data ?? []) as unknown as Record<string, unknown>[]).map(decodeListRound);
    const players = new Map<string, RoundPlayerRow[]>();
    if (allRounds.length > 0) {
      const ids = allRounds.map((r) => r.id);
      for (let i = 0; i < ids.length; i += 100) {
        const { data, error } = await supabase.from("round_players").select(PLAYER_COLUMNS).in("round_id", ids.slice(i, i + 100));
        if (error) throw error;
        for (const p of (data ?? []) as unknown[]) {
          const row = decodeRoundPlayerRow(p);
          players.set(row.roundID, [...(players.get(row.roundID) ?? []), row]);
        }
      }
    }
    let courses = await loadCourseItems((coursesRes.data ?? []) as Record<string, unknown>[], false);
    const known = new Set(courses.map((c) => c.course.id));
    const missing = [...new Set(allRounds.map((r) => r.courseID).filter((x): x is string => x !== null && !known.has(x)))];
    // Feiler hentingen av hentede baner, vises rundene uten banenavn, som i appen.
    courses = courses.concat(await loadSourceCourses(missing).catch(() => []));
    // En playoff (sql/047) er ingen runde i trekningen.
    const history = await loadSeasonHistory(event, rules, allRounds.filter((r) => r.kind !== "playoff"));
    return {
      rules, dayTerm: rulesetDay(rules), roster, signups: (signupsRes.data ?? []) as SignupRow[], allRounds, players, courses,
      myMemberID: ((meRes.data ?? []) as { id: string }[])[0]?.id ?? null,
      seasonRoundIDs: history.ids, seasonMatches: history.matches, tableRules, formats,
    };
  } catch (e) {
    fail(e);
  }
}

/** Banene fra slope.no som kan spilles direkte (de med hull). PostgREST gir høyst 1000 om gangen. */
export async function loadSlopeCatalog(): Promise<SlopeCourse[]> {
  const page = 1000;
  const all: SlopeCourse[] = [];
  try {
    for (let start = 0; start < 20 * page; start += page) {
      const { data, error } = await supabase.from("courses").select("id, name, city, country, course_holes(hole_number)")
        .eq("source", "slope").is("club_id", null).is("missing_at", null).eq("course_holes.hole_number", 1)
        .order("id").range(start, start + page - 1);
      if (error) throw error;
      const rows = (data ?? []) as { id: string; name: string; city: string | null; country: string | null; course_holes: unknown[] | null }[];
      all.push(...rows.map((r) => ({ id: r.id, name: r.name, city: r.city, country: r.country, hasHoles: (r.course_holes ?? []).length > 0 })));
      if (rows.length < page) break;
    }
    return all;
  } catch (e) {
    fail(e);
  }
}

// MARK: - Kladden

/** Kladden (eller runden) slik den er lagret: deltakerne og matchene. */
export async function loadSetup(roundID: string) {
  const [p, m] = await Promise.all([
    supabase.from("round_players").select(PLAYER_COLUMNS).eq("round_id", roundID),
    supabase.from("round_matches").select("round_id, match_no, player_a, player_b, player_c, team_a, team_b, result").eq("round_id", roundID).order("match_no"),
  ]);
  if (p.error) fail(p.error);
  if (m.error) fail(m.error);
  return {
    players: ((p.data ?? []) as unknown[]).map((x) => decodeRoundPlayerRow(x)),
    matches: ((m.data ?? []) as unknown[]).map((x) => decodeRoundMatchRow(x)),
  };
}

export interface SetupContext {
  clubID: string;
  rules: Ruleset;
  roster: RosterMember[];
  course: CourseItem | null;
  /** sql/047 er kjørt: tabellreglene skrives med raden. */
  tableRules?: boolean;
  /** sql/048 er kjørt: sidene og konkurransene lagres. */
  formats?: boolean;
}

function courseCheck(ctx: SetupContext) {
  return ctx.course ? { name: ctx.course.course.name, isReady: courseItemReady(ctx.course) } : null;
}

function courseFor(ctx: SetupContext, d: RoundDraft) {
  return ctx.course ? coreCourseWithTee(ctx.course, d.teeID) : null;
}

/** Raden i `rounds`, upsert på id (et nytt forsøk etter en feil treffer samme rad). Status røres ikke. */
async function writeRound(ctx: SetupContext, d: RoundDraft): Promise<void> {
  const write = roundWrite({ ...d, teeID: ctx.course && findTee(ctx.course, d.teeID) ? d.teeID : null }, ctx.clubID, courseFor(ctx, d), ctx.tableRules ?? false);
  const { data, error } = await supabase.from("rounds").upsert(write, { onConflict: "id" }).select("id");
  if (error) fail(error, saveErrorText);
  // RLS sa nei uten feilkode.
  if (!data || data.length === 0) throw new RoundError("Du har ikke tilgang til dette.");
}

/** «Lagre som kladd»: raden, så `set_round_setup` uten spillehandicap. */
export async function saveDraft(ctx: SetupContext, d: RoundDraft): Promise<void> {
  const issue = setupIssues(d, courseCheck(ctx), ctx.rules, ctx.roster, false)[0];
  if (issue) throw new RoundError(issueMessage(issue, groupTerm(d.venue)));
  checkFormats(ctx, d);
  await writeRound(ctx, d);
  const params = formatsParams(ctx, d, setupParams(d.roundID, d, ctx.roster, courseFor(ctx, d), ctx.rules, false));
  const { data, error } = await supabase.rpc("set_round_setup", params);
  if (error) throw new RoundError(`Runden er lagret, men ikke oppsettet. ${dataErrorText(error)}`);
  const counts = data as { players: number; matches: number };
  if (counts.players !== params.p_players.length || counts.matches !== params.p_matches.length) {
    throw new RoundError("Runden er lagret, men ikke oppsettet. Oppsettet ble ikke lagret slik det sto. Last inn på nytt og sjekk.");
  }
  await saveCompetitions(ctx, d, "Runden er lagret, men ikke konkurransene.");
}

/** Det konkurransene trenger fra oppsettet. Lagene bare når formen har lag (som team_no i set_round_setup). */
export function competitionContext(d: RoundDraft): CompetitionContext {
  const teams = coreIsTeamForm(draftForm(d)) ? d.teams : {};
  return { participants: d.participants, teams, bays: d.bays, holeCount: d.holeCount, mainForm: d.formID };
}

/** Sidene og konkurransene sjekkes før noe skrives (048). */
function checkFormats(ctx: SetupContext, d: RoundDraft) {
  if (!ctx.formats) return;
  const c = competitionContext(d);
  const side = d.sides ? sideProblem(d.sides, c.teams, d.participants) : null;
  if (side) throw new RoundError(side);
  const issue = d.competitions ? competitionIssues(d.competitions, c)[0] : undefined;
  if (issue) throw new RoundError(issue);
}

/** «side» per spiller når 048 er kjørt og sidene er hentet. */
function formatsParams<T extends { p_players: { member_id: string }[] }>(ctx: SetupContext, d: RoundDraft, params: T): T {
  if (!ctx.formats || !d.sides) return params;
  return { ...params, p_players: withSides(params.p_players, d.sides) };
}

/** `round_competitions_set` når runden har (eller hadde) andre konkurranser. Ellers røres ingenting. */
async function saveCompetitions(ctx: SetupContext, d: RoundDraft, prefix: string): Promise<void> {
  if (!ctx.formats || !d.competitions || (d.competitions.length === 0 && !d.hadCompetitions)) return;
  const list = d.competitions.length === 0 ? [] : competitionsPayload(d.competitions, competitionContext(d), d.mainCompetitionID ?? null);
  const { error } = await supabase.rpc("round_competitions_set", { p_round_id: d.roundID, p_competitions: list });
  if (error) throw new RoundError(`${prefix} ${dataErrorText(error)}`);
}

/** Konkurransene og sidene for oppsettet (048). Tomt uten 048. */
export async function loadFormatsSetup(roundID: string): Promise<{ competitions: StoredCompetition[]; sides: Record<string, 1 | 2> }> {
  if (!(await hasFormats())) return { competitions: [], sides: {} };
  const [c, p] = await Promise.all([
    supabase.from("round_competitions").select("id, round_id, name, is_main, format_version, config, sort_order").eq("round_id", roundID).order("sort_order"),
    supabase.from("round_players").select("member_id, side").eq("round_id", roundID),
  ]);
  if (c.error && !isMissing048(c.error.code)) fail(c.error);
  if (p.error && !isMissing048(p.error.code)) fail(p.error);
  return {
    competitions: ((c.data ?? []) as unknown[]).map(decodeStoredCompetition).filter((x): x is StoredCompetition => x !== null),
    sides: sidesFromRows((p.data ?? []) as { member_id: string; side: number | null }[]),
  };
}

/** Utkastet med konkurransene og sidene som er lagret. */
export async function withFormats(d: RoundDraft): Promise<RoundDraft> {
  const { competitions, sides } = await loadFormatsSetup(d.roundID);
  const { mainID, extras } = draftsFromStored(competitions);
  return { ...d, sides, competitions: extras, mainCompetitionID: mainID, hadCompetitions: competitions.length > 0 };
}

/** For rundens side: konkurransene, øyeblikksbildet og sidene (048). null uten 048. */
export async function loadRoundFormats(roundID: string): Promise<{ competitions: StoredCompetition[]; snapshot: SnapshotFields; sidePlayers: unknown[] } | null> {
  if (!(await hasFormats())) return null;
  const [c, r, p] = await Promise.all([
    supabase.from("round_competitions").select("id, round_id, name, is_main, format_version, config, sort_order").eq("round_id", roundID).order("sort_order"),
    supabase.from("rounds").select("format, external_handicap, rules_snapshot, holes_snapshot, snapshot_source, snapshot_at").eq("id", roundID).limit(1),
    supabase.from("round_players").select("member_id, side").eq("round_id", roundID),
  ]);
  for (const x of [c, r, p]) if (x.error) { if (isMissing048(x.error.code)) return null; fail(x.error); }
  const raw = ((r.data ?? []) as Record<string, unknown>[])[0];
  if (!raw) return null;
  return {
    competitions: ((c.data ?? []) as unknown[]).map(decodeStoredCompetition).filter((x): x is StoredCompetition => x !== null),
    snapshot: snapshotFields(raw),
    sidePlayers: (p.data ?? []) as unknown[],
  };
}

/** «Oppdater øyeblikksbildet» (`round_snapshot_refresh`): regelsettet og hullene på nytt, bare i en aktiv runde. */
export async function refreshSnapshot(roundID: string): Promise<void> {
  const { error } = await supabase.rpc("round_snapshot_refresh", { p_round_id: roundID });
  if (error) fail(error);
}

/** Rundene som går i klubben nå. Etter sql/034 kan flere gå samtidig (én per spilledag og pulje). */
export async function activeRounds(clubID: string): Promise<ListRound[]> {
  const { data, error } = await supabase.from("rounds").select(await roundColumns()).eq("club_id", clubID).eq("status", "active")
    .order("started_at", { ascending: false });
  if (error) fail(error);
  return ((data ?? []) as unknown as Record<string, unknown>[]).map(decodeListRound);
}

/**
 * «Start runden»: sjekkene, runden som er i veien, raden, og `start_round` (oppsett med spillehandicap og
 * status i én transaksjon). Feiler start_round, står runden som kladd.
 */
export async function startRound(ctx: SetupContext, d: RoundDraft, titleOf: (r: ListRound) => string): Promise<void> {
  const issue = setupIssues(d, courseCheck(ctx), ctx.rules, ctx.roster, true)[0];
  if (issue) throw new RoundError(issueMessage(issue, groupTerm(d.venue)));
  const active = await activeRounds(ctx.clubID);
  // Puljen til runden som startes (`rounds.wave_no`, satt i startlista). Ny runde: pulje 1.
  const { data: own } = await supabase.from("rounds").select("wave_no").eq("id", d.roundID).limit(1);
  const wave = ((own ?? [])[0] as { wave_no?: number } | undefined)?.wave_no ?? 1;
  const blocking = blockingRound(active, d.roundID, d.eventID, wave);
  if (blocking) {
    throw new RoundError(`${titleOf(blocking)} går allerede. Lås den før du starter en ny, eller lagre denne som kladd.`);
  }
  checkFormats(ctx, d);
  await writeRound(ctx, d);
  const params = formatsParams(ctx, d, setupParams(d.roundID, d, ctx.roster, courseFor(ctx, d), ctx.rules, true));
  const { data, error } = await supabase.rpc("start_round", params);
  if (error) throw new RoundError("Runden startet ikke. " + startErrorText(error));
  const started = data as { players: number; matches: number; status: string };
  if (started.status !== "active" || started.players !== params.p_players.length || started.matches !== params.p_matches.length) {
    throw new RoundError("Runden startet ikke. Runden ble ikke startet slik oppsettet sto. Last inn på nytt og sjekk.");
  }
  await saveCompetitions(ctx, d, "Runden er startet, men konkurransene ble ikke lagret.");
}

/**
 * «Teller ikke», poengtabell og «Skjul de tre siste hullene» på en startet eller låst runde: vanlig update på
 * `rounds` (sql/047, rettigheten rounds). Sjekker raden tilbake.
 */
export async function saveTableRules(roundID: string, patch: { counts: boolean; pointsTable: string | null; hideLastHoles: number }): Promise<void> {
  const write = tableRulesPatch(patch);
  const { data, error } = await supabase.from("rounds").update(write).eq("id", roundID).select("counts, points_table, hide_last_holes");
  if (error) fail(error, saveErrorText);
  const row = ((data ?? []) as Record<string, unknown>[])[0];
  if (!row || row.counts !== write.counts || (row.points_table ?? null) !== write.points_table || row.hide_last_holes !== write.hide_last_holes) {
    throw new RoundError("Du har ikke tilgang til dette.");
  }
}

// MARK: - Lås og slett

/** «Lås runden»: runden er ferdig. Sjekker raden tilbake. */
export async function lockRound(roundID: string): Promise<boolean> {
  const { data, error } = await supabase.from("rounds").update({ status: "locked" }).eq("id", roundID).select("id, status");
  if (error) fail(error);
  const row = ((data ?? []) as { status: string }[])[0];
  if (!row || row.status !== "locked") throw new RoundError("Du har ikke tilgang til dette.");
  return true;
}

/** Hva som forsvinner med runden. Telles før slettingen. */
export async function deleteSummary(round: { id: string; status: string }): Promise<DeleteSummary> {
  const [s, c] = await Promise.all([
    supabase.from("hole_scores").select("member_id").eq("round_id", round.id),
    supabase.from("side_claims").select("member_id").eq("round_id", round.id),
  ]);
  if (s.error) fail(s.error);
  if (c.error) fail(c.error);
  const scores = (s.data ?? []) as { member_id: string }[];
  return {
    holeScores: scores.length, playersWithScores: new Set(scores.map((x) => x.member_id)).size,
    sideClaims: (c.data ?? []).length, isDraft: round.status === "draft",
  };
}

/** «Slett runden» med `delete_round`. Låste runder avvises av databasen. */
export async function deleteRound(roundID: string): Promise<string> {
  const { data, error } = await supabase.rpc("delete_round", { p_round_id: roundID });
  if (error) fail(error);
  return deletedMessage(data as { round_no: number; hole_scores: number; side_claims: number });
}

// MARK: - Én runde (tabell, avkorting, retting)

/** Alt for én runde, som `RundeQueries.snapshot`. */
export async function loadGame(roundID: string, rules: Ruleset): Promise<RoundGame> {
  try {
    const { data: rows, error } = await supabase.from("rounds").select(await roundColumns()).eq("id", roundID).limit(1);
    if (error) throw error;
    const raw = ((rows ?? []) as unknown as Record<string, unknown>[])[0];
    if (!raw) throw new RoundError("Fant ikke runden. Den kan ha blitt slettet.");
    const round = decodeRoundRow(raw);
    const [holes, players, matches, scores, claims, members, events] = await Promise.all([
      supabase.from("round_holes").select("round_id, hole_index, par, stroke_index, length_m").eq("round_id", roundID),
      supabase.from("round_players").select(PLAYER_COLUMNS).eq("round_id", roundID),
      supabase.from("round_matches").select("round_id, match_no, player_a, player_b, player_c, team_a, team_b, result").eq("round_id", roundID),
      supabase.from("hole_scores").select("round_id, member_id, hole_index, strokes").eq("round_id", roundID),
      supabase.from("side_claims").select("id, round_id, member_id, kind, meters, hole_index, created_at").eq("round_id", roundID),
      supabase.from("club_members").select("id, display_name").eq("club_id", round.clubID ?? ""),
      supabase.from("events").select("event_date").eq("id", round.eventID ?? ""),
    ]);
    for (const r of [holes, players, matches, scores, claims, members, events]) if (r.error) throw r.error;
    let course = null;
    let courseHoles: CourseHoleRecord[] = [];
    if (round.courseID) {
      const [c, ch] = await Promise.all([
        supabase.from("courses").select("id, club_id, name, external_name, course_rating, slope_rating, in_use").eq("id", round.courseID),
        supabase.from("course_holes").select("course_id, hole_number, par, stroke_index, length_m").eq("course_id", round.courseID),
      ]);
      if (c.error) throw c.error;
      if (ch.error) throw ch.error;
      const first = (c.data ?? [])[0];
      course = first ? decodeCourseRow(first) : null;
      courseHoles = ((ch.data ?? []) as unknown[]).map((x) => decodeCourseHoleRecord(x));
    }
    return new RoundGame(makeSnapshot(round, {
      roundHoles: ((holes.data ?? []) as unknown[]).map((x) => decodeRoundHoleRow(x)),
      players: ((players.data ?? []) as unknown[]).map((x) => decodeRoundPlayerRow(x)),
      matches: ((matches.data ?? []) as unknown[]).map((x) => decodeRoundMatchRow(x)),
      scores: ((scores.data ?? []) as unknown[]).map((x) => decodeHoleScoreRow(x)),
      sideClaims: ((claims.data ?? []) as unknown[]).map((x) => decodeSideClaimRow(x)),
      course, courseHoles,
      eventDate: ((events.data ?? []) as { event_date: string }[])[0]?.event_date ?? null,
      rules,
      names: new Map(((members.data ?? []) as { id: string; display_name: string }[]).map((m) => [m.id, m.display_name])),
    }));
  } catch (e) {
    fail(e);
  }
}

/** Lagrer avkortingen (eller fjerner den med null) og sjekker raden tilbake. Låst runde avkortes ikke. */
export async function saveCut(game: RoundGame, choice: CutChoice | null, myMemberID: string | null): Promise<void> {
  if (game.status === "locked") throw new RoundError("Runden er låst og kan ikke avkortes. Enkelthull rettes med «Rett en score».");
  const patch = cutPatch(choice, myMemberID, new Date());
  const { data, error } = await supabase.from("rounds").update(patch).eq("id", game.roundID).select("cut_rule, cut_after");
  if (error) fail(error);
  const row = ((data ?? []) as { cut_rule: string | null; cut_after: number | null }[])[0];
  if (!row || !cutPatchMatches(patch, row)) throw new RoundError("Du har ikke tilgang til dette.");
}

/** Rett ett hull via `save_hole` (også i en låst runde), som appens `DirectScoreSubmitter`. */
export async function saveHole(params: Record<string, unknown>): Promise<void> {
  const { error } = await supabase.rpc("save_hole", params);
  if (error) fail(error);
}

/** «Avslutt kvelden»: låser rundene én for én. Gir id-ene som ble låst. */
export async function lockAll(ids: readonly string[]): Promise<Set<string>> {
  const locked = new Set<string>();
  for (const id of ids) {
    const { data, error } = await supabase.from("rounds").update({ status: "locked" }).eq("id", id).select("id, status");
    if (!error && ((data ?? []) as { status: string }[])[0]?.status === "locked") locked.add(id);
  }
  return locked;
}

// MARK: - Startlista

export interface StaffOption { id: string; name: string; role: string }

/** Lagrede grupper og staben i turneringen dagen hører til (funksjonærvalget). */
export async function loadStartList(eventID: string, roundIDs: string[]): Promise<{ saved: StartGroupRow[]; staff: StaffOption[] }> {
  try {
    let saved: StartGroupRow[] = [];
    if (roundIDs.length > 0) {
      const { data, error } = await supabase.from("round_start_groups")
        .select("round_id, group_no, starts_at, start_hole, resource_label, scorer_id").in("round_id", roundIDs);
      if (error) throw error;
      saved = (data ?? []) as StartGroupRow[];
    }
    const { data: ev, error: evErr } = await supabase.from("events").select("competition_id").eq("id", eventID).limit(1);
    if (evErr) throw evErr;
    const competitionID = ((ev ?? []) as { competition_id: string | null }[])[0]?.competition_id ?? null;
    let staff: StaffOption[] = [];
    if (competitionID) {
      const { data: s } = await supabase.from("competition_staff").select("profile_id, role").eq("competition_id", competitionID);
      const rows = (s ?? []) as { profile_id: string; role: string }[];
      if (rows.length > 0) {
        const { data: names } = await supabase.from("profiles").select("id, display_name").in("id", rows.map((r) => r.profile_id));
        const byID = new Map(((names ?? []) as { id: string; display_name: string | null }[]).map((n) => [n.id, n.display_name ?? "Uten navn"]));
        staff = rows.map((r) => ({ id: r.profile_id, name: byID.get(r.profile_id) ?? "Uten navn", role: r.role }))
          .sort((a, b) => (a.role !== b.role ? (a.role === "organizer" ? -1 : 1) : a.name.localeCompare(b.name, "nb")));
      }
    }
    return { saved, staff };
  } catch (e) {
    fail(e);
  }
}

/** Lagrer hver runde i én transaksjon hver. 23505: en annen runde går i samme pulje. */
export async function saveStartList(roundID: string, wave: number, groups: readonly StartGroupDraft[]): Promise<void> {
  const { error } = await supabase.rpc("save_start_list", startListParams(roundID, wave, groups));
  if (error) {
    if (error.code === "23505") throw new RoundError("En runde går allerede i denne puljen.");
    fail(error);
  }
}

export { roundTitle };
