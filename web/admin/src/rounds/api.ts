// Lesing og skriving for rundene på en spilledag. Samme tabeller, RPC-er og rekkefølge som appen
// (RundeAdminModel.swift, RoundReviewModel/EveningCloser i AvslutningModel.swift, RundeQueries.snapshot,
// DirectScoreSubmitter, StartListModel). RLS og RPC-ene er tilgangskontrollen.

import { supabase } from "../supabase.ts";
import type { Competition, EventRow } from "../data.ts";
import {
  decodeCourseHoleRecord, decodeCourseRow, decodeHoleScoreRow, decodeRoundHoleRow, decodeRoundMatchRow, decodeRoundPlayerRow,
  decodeRoundRow, decodeRuleset, decodeSideClaimRow, GOLFGUTU, makeSnapshot, rulesetDay,
  type CourseHoleRecord, type DayTerm, type RoundPlayerRow, type RoundRow, type Ruleset,
} from "../../../golfgutu-core/src/index.ts";
import {
  coreCourseWithTee, courseItemReady, findTee, makeCourseItem, type CourseItem, type CourseKind, type CourseTee, type SlopeCourse,
} from "./courses.ts";
import { RoundGame, cutPatch, cutPatchMatches, type CutChoice } from "./game.ts";
import {
  dataErrorText, deletedMessage, roundTitle, saveErrorText, setupIssues, setupParams, startErrorText, issueMessage,
  groupTerm, roundWrite, sortedByName, type DeleteSummary, type RosterMember, type RoundDraft, type SignupRow,
} from "./logic.ts";
import { startListParams, type StartGroupDraft, type StartGroupRow } from "./startlist.ts";

const ROUND_COLUMNS = "id, club_id, event_id, course_id, round_no, name, status, hole_count, first_hole, tee_time, format, "
  + "handicap_allowance, external_handicap, weight, ld_enabled, ld_hole_index, kp_enabled, kp_hole_index, cut_rule, cut_after, "
  + "started_at, locked_at, venue, tee_id, tee_name, course_rating, slope_rating, tee_par, wave_no";
const PLAYER_COLUMNS = "round_id, member_id, club_id, handicap_index, seed_group, playing_handicap, bay_no, is_marker, team_no";
const COURSE_COLUMNS = "id, club_id, name, external_name, course_rating, slope_rating, in_use, kind";
const TEE_COLUMNS = "id, course_id, name, gender, course_rating, slope_rating, par, sort_order";

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
  const active = seasons.find((x) => x.status === "active");
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
    const [rules, membersRes, coursesRes, roundsRes, signupsRes, meRes] = await Promise.all([
      rulesFor(clubID, event, comps),
      supabase.from("club_members").select("id, display_name, handicap_index, seed_group, user_id").eq("club_id", clubID).eq("status", "active"),
      supabase.from("courses").select(COURSE_COLUMNS).eq("club_id", clubID),
      supabase.from("rounds").select(ROUND_COLUMNS).eq("club_id", clubID).order("round_no"),
      supabase.from("signups").select("member_id, status").eq("event_id", event.id),
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
    return {
      rules, dayTerm: rulesetDay(rules), roster, signups: (signupsRes.data ?? []) as SignupRow[], allRounds, players, courses,
      myMemberID: ((meRes.data ?? []) as { id: string }[])[0]?.id ?? null,
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
}

function courseCheck(ctx: SetupContext) {
  return ctx.course ? { name: ctx.course.course.name, isReady: courseItemReady(ctx.course) } : null;
}

function courseFor(ctx: SetupContext, d: RoundDraft) {
  return ctx.course ? coreCourseWithTee(ctx.course, d.teeID) : null;
}

/** Raden i `rounds`, upsert på id (et nytt forsøk etter en feil treffer samme rad). Status røres ikke. */
async function writeRound(ctx: SetupContext, d: RoundDraft): Promise<void> {
  const write = roundWrite({ ...d, teeID: ctx.course && findTee(ctx.course, d.teeID) ? d.teeID : null }, ctx.clubID, courseFor(ctx, d));
  const { data, error } = await supabase.from("rounds").upsert(write, { onConflict: "id" }).select("id");
  if (error) fail(error, saveErrorText);
  // RLS sa nei uten feilkode.
  if (!data || data.length === 0) throw new RoundError("Du har ikke tilgang til dette.");
}

/** «Lagre som kladd»: raden, så `set_round_setup` uten spillehandicap. */
export async function saveDraft(ctx: SetupContext, d: RoundDraft): Promise<void> {
  const issue = setupIssues(d, courseCheck(ctx), ctx.rules, ctx.roster, false)[0];
  if (issue) throw new RoundError(issueMessage(issue, groupTerm(d.venue)));
  await writeRound(ctx, d);
  const params = setupParams(d.roundID, d, ctx.roster, courseFor(ctx, d), ctx.rules, false);
  const { data, error } = await supabase.rpc("set_round_setup", params);
  if (error) throw new RoundError(`Runden er lagret, men ikke oppsettet. ${dataErrorText(error)}`);
  const counts = data as { players: number; matches: number };
  if (counts.players !== params.p_players.length || counts.matches !== params.p_matches.length) {
    throw new RoundError("Runden er lagret, men ikke oppsettet. Oppsettet ble ikke lagret slik det sto. Last inn på nytt og sjekk.");
  }
}

/** Runden som går i klubben nå, hvis noen. */
export async function activeRound(clubID: string): Promise<ListRound | null> {
  const { data, error } = await supabase.from("rounds").select(ROUND_COLUMNS).eq("club_id", clubID).eq("status", "active").limit(1);
  if (error) fail(error);
  const rows = (data ?? []) as unknown as Record<string, unknown>[];
  return rows.length > 0 ? decodeListRound(rows[0]) : null;
}

/**
 * «Start runden»: sjekkene, runden som er i veien, raden, og `start_round` (oppsett med spillehandicap og
 * status i én transaksjon). Feiler start_round, står runden som kladd.
 */
export async function startRound(ctx: SetupContext, d: RoundDraft, titleOf: (r: ListRound) => string): Promise<void> {
  const issue = setupIssues(d, courseCheck(ctx), ctx.rules, ctx.roster, true)[0];
  if (issue) throw new RoundError(issueMessage(issue, groupTerm(d.venue)));
  const blocking = await activeRound(ctx.clubID);
  if (blocking && blocking.id !== d.roundID) {
    throw new RoundError(`${titleOf(blocking)} går allerede. Lås den før du starter en ny, eller lagre denne som kladd.`);
  }
  await writeRound(ctx, d);
  const params = setupParams(d.roundID, d, ctx.roster, courseFor(ctx, d), ctx.rules, true);
  const { data, error } = await supabase.rpc("start_round", params);
  if (error) throw new RoundError("Runden startet ikke. " + startErrorText(error));
  const started = data as { players: number; matches: number; status: string };
  if (started.status !== "active" || started.players !== params.p_players.length || started.matches !== params.p_matches.length) {
    throw new RoundError("Runden startet ikke. Runden ble ikke startet slik oppsettet sto. Last inn på nytt og sjekk.");
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
    const { data: rows, error } = await supabase.from("rounds").select(ROUND_COLUMNS).eq("id", roundID).limit(1);
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
