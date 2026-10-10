// Handicap og tildeling (Handicap.swift, db-nytt.js linje 58–344). Seeding og lagshandicap leses fra
// regelsettet, med Golfgutu-oppsettet som standard.

import { numberOfHoles } from "./course.ts";
import { roundForm } from "./forms.ts";
import { jsRound, sortedStrings } from "./jsmath.ts";
import type { Player, Round } from "./models.ts";
import { GOLFGUTU, teamHandicapRule, type Ruleset, type SeedingGroup } from "./ruleset.ts";

/** `Number(x) || 0`: null og NaN blir 0. */
export function jsNumber(x: number | null | undefined): number {
  if (x === null || x === undefined || Number.isNaN(x)) return 0;
  return x;
}

/** `seedingGruppe`: gruppa med dette nummeret, eller `null`. */
export function seedingGroup(n: number | null | undefined, rules: Ruleset = GOLFGUTU): SeedingGroup | null {
  if (n === null || n === undefined) return null;
  return rules.handicap.seedingGroups.find((g) => g.number === n) ?? null;
}

/** `gruppeHandicap`: gruppas faste tall, eller `null` når spilleren ikke er seedet (0 er noe annet). */
export function groupHandicap(player: Player | null | undefined, rules: Ruleset = GOLFGUTU): number | null {
  return seedingGroup(player?.seedGroup, rules)?.handicap ?? null;
}

/** `erSeedet`. */
export function isSeeded(player: Player | null | undefined, rules: Ruleset = GOLFGUTU): boolean {
  return groupHandicap(player, rules) !== null;
}

/**
 * `courseHandicap`: `round(indeks · slope/113 + (rating − par))`, avrundet som JS. Mangler rating,
 * brukes par. Mangler slope, brukes 113. Mangler par (eller 0), brukes 72.
 */
export function courseHandicapFor(index: number | null, courseRating: number | null, slopeRating: number | null, par: number | null): number {
  const idx = jsNumber(index);
  const p = jsNumber(par) === 0 ? 72 : jsNumber(par);
  const rating = courseRating ?? p;
  const slope = slopeRating ?? 113;
  return jsRound(idx * (slope / 113) + (rating - p));
}

/** `rundeAndel`: tildelingen lagret på runden. Et tall ≥ 0 brukes (0 er brutto), ellers 1. */
export function allowance(round: Round): number {
  const a = round.hcpAllowance;
  if (a !== null && a >= 0) return a;
  return 1;
}

/** `banehandicap`: seedet → gruppetallet; ellers WHS-banehandicap med bane, rå indeks uten. Uten tildeling. */
export function courseHandicap(player: Player | null | undefined, round: Round, rules: Ruleset = GOLFGUTU): number {
  const gh = groupHandicap(player, rules);
  if (gh !== null) return gh;
  const idx = jsNumber(player?.handicap);
  const course = round.course;
  if (course !== null) return courseHandicapFor(idx, course.courseRating, course.slopeRating, course.par);
  return idx;
}

/** `lagGrunnlag`: seedet → gruppetallet; ellers banehandicap · antall hull / 18, ikke avrundet. */
export function teamBasis(player: Player | null | undefined, round: Round, rules: Ruleset = GOLFGUTU): number {
  const gh = groupHandicap(player, rules);
  if (gh !== null) return gh;
  return courseHandicap(player, round, rules) * (numberOfHoles(round) / 18);
}

/**
 * `lagHandicap`: lagets ene handicap, etter regelen for formen i regelsettet. Ett avrundingstrinn til
 * slutt. Brutto (tildeling 0) gir 0. `null` i `members` er en id som ikke finnes i troppen.
 */
export function teamHandicap(round: Round, members: readonly (Player | null)[], rules: Ruleset = GOLFGUTU): number {
  const basis = members.map((m) => teamBasis(m, round, rules)).sort((a, b) => a - b);
  if (basis.length === 0) return 0;
  if (allowance(round) === 0) return 0;
  const rule = teamHandicapRule(rules, roundForm(round).id);
  let sum: number;
  switch (rule.method) {
    case "average":
      sum = basis.reduce((s, x) => s + x, 0) / basis.length;
      break;
    case "weighted": {
      const w = rule.weights ?? [];
      sum = 0;
      for (let i = 0; i < Math.min(w.length, basis.length); i++) sum += w[i] * basis[i];
      break;
    }
    case "lowest":
      sum = basis[0] * allowance(round);
      break;
  }
  return jsRound(sum);
}

/** `lagHandicap` med spiller-id-er slått opp i troppen. */
export function teamHandicapByIDs(round: Round, memberIDs: readonly string[], roster: readonly Player[], rules: Ruleset = GOLFGUTU): number {
  return teamHandicap(round, memberIDs.map((id) => roster.find((p) => p.id === id) ?? null), rules);
}

/** `lagFor`: lagkameratene (med spilleren selv), sortert på id, eller `null` uten lag. Lag 0 er «ikke på lag». */
export function teammates(playerID: string, round: Round): string[] | null {
  const n = round.teams.get(playerID);
  if (n === undefined || n === 0) return null;
  const ids: string[] = [];
  for (const [id, team] of round.teams) if (team === n) ids.push(id);
  return sortedStrings(ids);
}

/**
 * `effectiveHandicap`: spillerens handicap i runden, i hele slag.
 * 1. Simulatoren deler ut slagene → 0.
 * 1b. Rundens frosne spillehandicap for spilleren → det.
 * 2. Form med ett kort per lag, eller toerform, og spilleren har lag → lagets handicap.
 * 3. Seedet → gruppetallet (0 når tildelingen er 0).
 * 4. Ellers `round(banehandicap · tildeling · antall hull / 18)`.
 */
export function effectiveHandicap(player: Player | null | undefined, round: Round, roster: readonly Player[], rules: Ruleset = GOLFGUTU): number {
  if (round.hcpExtern) return 0;
  if (player) {
    const frozen = round.playingHandicaps.get(player.id);
    if (frozen !== undefined) return frozen;
  }
  const form = roundForm(round);
  if ((form.card === "per lag" || form.teamSize === 2) && player) {
    const mates = teammates(player.id, round);
    if (mates !== null && mates.length > 0) return teamHandicapByIDs(round, mates, roster, rules);
  }
  const gh = groupHandicap(player, rules);
  if (gh !== null) return allowance(round) > 0 ? gh : 0;
  return jsRound(courseHandicap(player, round, rules) * allowance(round) * (numberOfHoles(round) / 18));
}
