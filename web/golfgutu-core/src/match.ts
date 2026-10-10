// Matchspill hull for hull (Match.swift, db-nytt.js linje 398–634).

import { courseHoles, numberOfHoles } from "./course.ts";
import { effectiveHandicap } from "./handicap.ts";
import { sortedStrings } from "./jsmath.ts";
import { isTriangle, type Match, type Player, type Round } from "./models.ts";
import { GOLFGUTU, type MatchPoints, type Ruleset } from "./ruleset.ts";
import { netStrokes } from "./scoring.ts";
import { countingHoles } from "./truncation.ts";

/** Sidene i en match. `c` finnes bare for singelmatcher. */
export interface MatchSides {
  a: string[];
  b: string[];
  c: string[] | null;
}

export function allInMatch(s: MatchSides): string[] {
  return [...s.a, ...s.b, ...(s.c ?? [])];
}

/** Hulldifferansen sett fra A (`matchHullDiff`). */
export interface MatchHoleDiff {
  /** Hull opp (negativt = ned). */
  up: number;
  /** Hull der begge sider har ført. */
  played: number;
}

/** Stillingen sett fra én spiller (`matchStilling`). */
export interface MatchStanding {
  up: number;
  played: number;
  /** Tellende hull som gjenstår. */
  remaining: number;
  /** Flere hull opp enn det er igjen. */
  decided: boolean;
  /** Motstanderne. Den første er `motstander`. */
  opponents: string[];
}

/** `matcherForRunde`. */
export function matchesIn(round: Round): Match[] {
  return round.matches;
}

/** `lagForRunde` for ett lagnummer, sortert på id. */
export function teamMembers(n: number, round: Round): string[] {
  const ids: string[] = [];
  for (const [id, team] of round.teams) if (team === n) ids.push(id);
  return sortedStrings(ids);
}

function nonEmpty(id: string | null): string[] {
  return id === null || id === "" ? [] : [id];
}

/** `matchSider`: lagmatch slår opp lagene, ellers spillerne A, B og C. */
export function matchSides(m: Match, round: Round): MatchSides {
  if (m.teamA !== null) {
    const b = m.teamB !== null ? teamMembers(m.teamB, round) : [];
    return { a: teamMembers(m.teamA, round), b, c: null };
  }
  return { a: nonEmpty(m.playerA), b: nonEmpty(m.playerB), c: m.playerC === null || m.playerC === "" ? [] : [m.playerC] };
}

/** `matchGjelder`: er spilleren med i matchen? */
export function matchInvolves(m: Match, playerID: string, round: Round): boolean {
  return allInMatch(matchSides(m, round)).includes(playerID);
}

function effective(pid: string, round: Round, roster: readonly Player[], rules: Ruleset): number {
  return effectiveHandicap(roster.find((p) => p.id === pid) ?? null, round, roster, rules);
}

/** `sideHandicap`: laveste `effectiveHandicap` på siden. Tom side → 0. */
export function sideHandicap(playerIDs: readonly string[], round: Round, roster: readonly Player[], rules: Ruleset = GOLFGUTU): number {
  if (playerIDs.length === 0) return 0;
  return Math.min(...playerIDs.map((id) => effective(id, round, roster, rules)));
}

/** `matchSlag`: tallet som trekkes fra alles handicap i matchen (laveste fra scratch), eller 0 med fullt handicap. */
export function strokeOffset(m: Match, round: Round, roster: readonly Player[], rules: Ruleset = GOLFGUTU): number {
  if (rules.formats.matchStrokes === "fullHandicap") return 0;
  const s = matchSides(m, round);
  return Math.min(sideHandicap(s.a, round, roster, rules), sideHandicap(s.b, round, roster, rules));
}

/** `sideNettoPaaHull`: beste netto på siden på hullet. `null` når ingen på siden har ført, eller hullet ikke finnes. */
export function sideNet(playerIDs: readonly string[], hole: number, extraStrokes: number, round: Round, roster: readonly Player[], rules: Ruleset = GOLFGUTU): number | null {
  const course = courseHoles(round);
  if (!(hole >= 0 && hole < course.length)) return null;
  const played = course[hole];
  let best: number | null = null;
  for (const pid of playerIDs) {
    const gross = round.holeScores.get(pid)?.get(hole);
    if (gross === undefined) continue;
    const own = effective(pid, round, roster, rules);
    const net = netStrokes(gross, Math.max(0, own - extraStrokes), played.strokeIndex, numberOfHoles(round));
    if (best === null || net < best) best = net;
  }
  return best;
}

/** `matchHullVinner`: 1 når A vant hullet, −1 når B vant, 0 delt. `null` når en side ikke har ført. */
export function holeWinner(m: Match, hole: number, round: Round, roster: readonly Player[], rules: Ruleset = GOLFGUTU, lowest: number | null = null): number | null {
  const s = matchSides(m, round);
  if (s.a.length === 0 || s.b.length === 0) return null;
  const lav = lowest ?? strokeOffset(m, round, roster, rules);
  const a = sideNet(s.a, hole, lav, round, roster, rules);
  const b = sideNet(s.b, hole, lav, round, roster, rules);
  if (a === null || b === null) return null;
  return a < b ? 1 : b < a ? -1 : 0;
}

/** `matchHullDiff`: summen over de tellende hullene, sett fra A. `null` når en side er tom. */
export function holeDiff(m: Match, round: Round, roster: readonly Player[], rules: Ruleset = GOLFGUTU): MatchHoleDiff | null {
  const s = matchSides(m, round);
  if (s.a.length === 0 || s.b.length === 0) return null;
  const lav = strokeOffset(m, round, roster, rules);
  const diff: MatchHoleDiff = { up: 0, played: 0 };
  const n = countingHoles(round);
  for (let h = 0; h < n; h++) {
    const v = holeWinner(m, h, round, roster, rules, lav);
    if (v === null) continue;
    diff.played += 1;
    diff.up += v;
  }
  return diff;
}

/** `matchUtfallForA`: 1 seier, 0,5 delt, 0 tap. Manuelt resultat vinner. `null` for trekant og uten spilte hull. */
export function outcomeForA(m: Match, round: Round, roster: readonly Player[], rules: Ruleset = GOLFGUTU): number | null {
  if (isTriangle(m)) return null;
  if (m.result !== null) return m.result === "a" ? 1 : m.result === "b" ? 0 : 0.5;
  const d = holeDiff(m, round, roster, rules);
  if (d === null || d.played <= 0) return null;
  return d.up > 0 ? 1 : d.up < 0 ? 0 : 0.5;
}

/** `poengForUtfall`: hva utfallet er verdt i tabellen, etter regelsettet. */
export function pointsForOutcome(outcome: number | null, points: MatchPoints = GOLFGUTU.table.matchPoints): number {
  return outcome === 1 ? points.win : outcome === 0.5 ? points.draw : points.loss;
}

/** `matchStilling`: stillingen sett fra spilleren. `null` for trekant og tom side. */
export function matchStanding(m: Match, playerID: string, round: Round, roster: readonly Player[], rules: Ruleset = GOLFGUTU): MatchStanding | null {
  if (isTriangle(m)) return null;
  const d = holeDiff(m, round, roster, rules);
  if (d === null) return null;
  const s = matchSides(m, round);
  const onB = s.b.includes(playerID);
  const mine = onB ? 0 - d.up : d.up;
  const remaining = countingHoles(round) - d.played;
  return { up: mine, played: d.played, remaining, decided: Math.abs(mine) > remaining && d.played > 0, opponents: onB ? s.a : s.b };
}

/** `matchTekst`: «Vunnet 3&2», «Tapt 4 ned», «Delt etter 5», «2 opp etter 6», «Ikke startet». */
export function matchText(st: MatchStanding | null): string {
  if (st === null) return "";
  if (st.played === 0) return "Ikke startet";
  const n = Math.abs(st.up);
  const dir = st.up > 0 ? " opp" : " ned";
  if (st.decided || st.remaining === 0) {
    if (st.up === 0) return "Delt";
    const outcome = st.up > 0 ? "Vunnet " : "Tapt ";
    return st.remaining > 0 ? `${outcome}${n}&${st.remaining}` : `${outcome}${n}${dir}`;
  }
  if (st.up === 0) return `Delt etter ${st.played}`;
  return `${n}${dir} etter ${st.played}`;
}

/** `matchStillingKort`: «2 opp», «1 ned», «Delt» eller «—». */
export function matchShortText(st: MatchStanding | null): string {
  if (st === null || !(st.played > 0)) return "—";
  if (st.up === 0) return "Delt";
  return `${Math.abs(st.up)}` + (st.up > 0 ? " opp" : " ned");
}

/** `hullMatchFor`: spillerens første match som ikke er en trekant. */
export function holeMatchFor(playerID: string, round: Round): Match | null {
  return round.matches.find((m) => !isTriangle(m) && matchInvolves(m, playerID, round)) ?? null;
}

/** `avgjoresHullForHull`: har runden minst én match som ikke er en trekant? */
export function isDecidedHoleByHole(round: Round): boolean {
  return round.matches.some((m) => !isTriangle(m));
}
