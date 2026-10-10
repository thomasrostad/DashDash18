// Fra databasens rader til regelmotorens runde (DashDash18/Features/Runde/RoundSnapshot.swift:
// `RoundSnapshot` og `RoundGame.makeRound` med hjelperne). Samme mapping som Kveld og Tavla i appen.

import { holesFromRows } from "../course.ts";
import { effectiveHandicap } from "../handicap.ts";
import { makePlayer, matchResultFromStored, type Course, type CourseHoleRow, type HoleScores, type Player, type Round, type RoundHole } from "../models.ts";
import { GOLFGUTU, type Ruleset } from "../ruleset.ts";
import type { TruncationRule } from "../truncation.ts";
import type {
  CourseHoleRecord,
  CourseRow,
  HoleScoreRow,
  RoundHoleRow,
  RoundMatchRow,
  RoundPlayerRow,
  RoundRow,
  SideClaimRow,
  UUID,
} from "./rows.ts";

/** Alt som er hentet for én runde, slik databasen leverer det. Rene rader, ingen poeng. */
export interface RoundSnapshot {
  round: RoundRow;
  roundHoles: RoundHoleRow[];
  players: RoundPlayerRow[];
  matches: RoundMatchRow[];
  scores: HoleScoreRow[];
  sideClaims: SideClaimRow[];
  course: CourseRow | null;
  courseHoles: CourseHoleRecord[];
  /** Kveldens dato (`YYYY-MM-DD`), fra `events`. */
  eventDate: string | null;
  /** Regelsettet til sesongen. Mangler det, gjelder Golfgutu-oppsettet. */
  rules: Ruleset;
  /** Navn fra troppen (klubbrunde) eller deltakerne (løs runde). */
  names: Map<UUID, string>;
}

export function makeSnapshot(round: RoundRow, s: Partial<Omit<RoundSnapshot, "round">> = {}): RoundSnapshot {
  return {
    round,
    roundHoles: s.roundHoles ?? [],
    players: s.players ?? [],
    matches: s.matches ?? [],
    scores: s.scores ?? [],
    sideClaims: s.sideClaims ?? [],
    course: s.course ?? null,
    courseHoles: s.courseHoles ?? [],
    eventDate: s.eventDate ?? null,
    rules: s.rules ?? GOLFGUTU,
    names: s.names ?? new Map(),
  };
}

/** `rounds.cut_rule` (skjemaets navn) → regelmotorens avkortingsregel. */
export function cutRule(raw: string | null): TruncationRule | null {
  switch (raw) {
    case "common":
      return "felles";
    case "net_par":
      return "nettopar";
    case "zero":
      return "null";
    default:
      return null;
  }
}

/** Banens par for banehandicapet: teens par fra start (`tee_par`), ellers summen av banens hull. */
export function coursePar(holesPar: number | null, teePar: number | null): number | null {
  return teePar ?? holesPar;
}

/**
 * Banen med hull fra `course_holes`. Hullene tas bare med når de er 9 eller 18 sammenhengende fra 1.
 * Par er summen av hullene. Er runden spilt fra en tee, gjelder CR, slope og par slik de var ved start.
 */
export function makeCourse(row: CourseRow | null, holes: readonly CourseHoleRecord[], round: RoundRow | null = null): Course | null {
  if (row === null) return null;
  const mine: CourseHoleRow[] = holes.filter((h) => h.courseID === row.id).map((h) => ({
    courseId: row.id, holeNumber: h.holeNumber, par: h.par, hcpIndex: h.strokeIndex, distanceMeters: h.lengthM,
  }));
  const played = holesFromRows(mine).get(row.id) ?? null;
  const par = played !== null ? played.reduce((s, h) => s + (h.par ?? 0), 0) : null;
  return {
    id: row.id,
    name: row.name,
    par: coursePar(par, round?.teePar ?? null),
    courseRating: round?.courseRating ?? row.courseRating,
    slopeRating: round?.slopeRating ?? row.slopeRating,
    holes: played,
  };
}

/** Spillehandicapet som ble frosset ved start (`round_players.playing_handicap`), per spiller. */
export function frozenHandicaps(s: RoundSnapshot): Map<string, number> {
  const out = new Map<string, number>();
  for (const p of s.players) {
    if (p.playingHandicap !== null && !out.has(p.memberID)) out.set(p.memberID, p.playingHandicap);
  }
  return out;
}

/** `RoundGame.makeRound`: regelmotorens runde av radene. */
export function makeRoundFromSnapshot(s: RoundSnapshot): Round {
  const r = s.round;
  const holeScores = new Map<string, HoleScores>();
  for (const row of s.scores) {
    const scores = holeScores.get(row.memberID) ?? new Map<number, number>();
    scores.set(row.holeIndex, row.strokes);
    holeScores.set(row.memberID, scores);
  }
  const teams = new Map<string, number>();
  for (const p of s.players) if (p.teamNo !== null) teams.set(p.memberID, p.teamNo);
  const overrides = new Map<number, RoundHole>();
  for (const h of s.roundHoles) {
    if (!overrides.has(h.holeIndex)) overrides.set(h.holeIndex, { par: h.par, strokeIndex: h.strokeIndex, meters: h.lengthM });
  }
  return {
    id: r.id,
    gameType: r.format,
    holeCount: r.holeCount,
    // Skjemaet lagrer banens første hull (1 eller 10), regelmotoren PWA-ens 0/9.
    holeStart: r.firstHole === 10 ? 9 : 0,
    course: makeCourse(s.course, s.courseHoles, r),
    holes: overrides.size === 0 ? null : overrides,
    hcpAllowance: r.handicapAllowance,
    hcpExtern: r.externalHandicap,
    teams,
    holeScores,
    avkortRegel: cutRule(r.cutRule),
    avkortetEtter: r.cutAfter,
    matches: [...s.matches].sort((a, b) => a.matchNo - b.matchNo).map((m) => ({
      matchNo: m.matchNo, playerA: m.playerA, playerB: m.playerB, playerC: m.playerC, teamA: m.teamA, teamB: m.teamB,
      result: matchResultFromStored(m.result),
    })),
    ldEnabled: r.ldEnabled,
    kpEnabled: r.kpEnabled,
    ldHoleIndex: r.ldHoleIndex,
    kpHoleIndex: r.kpHoleIndex,
    weight: r.weight,
    date: s.eventDate,
    locked: r.status === "locked",
    playingHandicaps: frozenHandicaps(s),
  };
}

/** Spillerne i runden med frosset indeks og seedet gruppe (`RoundGame.roster`). */
export function snapshotRoster(s: RoundSnapshot): Player[] {
  return s.players.map((row) => makePlayer(row.memberID, s.names.get(row.memberID) ?? "", row.handicapIndex, row.seedGroup));
}

/**
 * `RoundGame.handicap`: spillerens handicap i runden, i hele slag. Simulatoren → 0. `playing_handicap`
 * er fasiten når den er lagret; ellers `effectiveHandicap` med regelsettet og rundens frosne indeks.
 */
export function snapshotHandicap(s: RoundSnapshot, member: UUID, round: Round = makeRoundFromSnapshot(s), roster: Player[] = snapshotRoster(s)): number {
  if (round.hcpExtern) return 0;
  const stored = s.players.find((p) => p.memberID === member)?.playingHandicap ?? null;
  if (stored !== null) return stored;
  return effectiveHandicap(roster.find((p) => p.id === member) ?? null, round, roster, s.rules);
}
