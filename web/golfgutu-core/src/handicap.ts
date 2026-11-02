// Handicap og tildeling (Handicap.swift, db-nytt.js linje 58–344). Seeding og lagshandicap leses fra
// regelsettet, med Golfgutu-oppsettet som standard.

import { courseHoles, numberOfHoles } from "./course.ts";
import { roundForm } from "./forms.ts";
import { jsRound, sortedStrings } from "./jsmath.ts";
import type { Player, Round } from "./models.ts";
import { GOLFGUTU, handicapRoundWhole, teamHandicapRule, type Ruleset, type SeedingGroup } from "./ruleset.ts";
import { roundWhole, STANDARD_SLOPE, whsCourseHandicapForHoles } from "./whs.ts";

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

/**
 * `banehandicap`: seedet → gruppetallet. Uten tildeling. Som PWA-en (`pwa`): WHS-banehandicap for 18 hull med
 * bane, rå indeks uten. Golfreglene (`whs`): banehandicapet for hullene som spilles (`whsCourseHandicapInRound`).
 */
export function courseHandicap(player: Player | null | undefined, round: Round, rules: Ruleset = GOLFGUTU): number {
  const gh = groupHandicap(player, rules);
  if (gh !== null) return gh;
  const idx = jsNumber(player?.handicap);
  if (rules.handicap.calculation === "whs") return whsCourseHandicapInRound(idx, round);
  const course = round.course;
  if (course !== null) return courseHandicapFor(idx, course.courseRating, course.slopeRating, course.par);
  return idx;
}

/**
 * Banehandicap etter golfreglene for hullene runden spiller (`Handicap.whsCourseHandicap`, regel 6.1a og 6.1b).
 * Ratingen gjelder 9 hull når banen har 9 hull, ellers 18. Par: banens når runden spiller like mange hull som
 * ratingen gjelder, ellers summen av par på hullene som spilles. Uten rating: lik par; uten slope: 113.
 * Uten bane: indeksen for hullene.
 */
export function whsCourseHandicapInRound(index: number, round: Round): number {
  const holes = numberOfHoles(round);
  const playedPar = courseHoles(round).reduce((s, h) => s + h.par, 0);
  const course = round.course;
  // `+ 0`: −0 blir 0, som heltallet i Swift.
  if (course === null) return roundWhole(index * holes / 18) + 0;
  const rated = course.holes?.length === 9 ? 9 : 18;
  const par = (holes === rated && course.par !== null && course.par > 0 ? course.par : null) ?? playedPar;
  // Uten rating: lik par for hullene ratingen gjelder, så CR − par blir 0.
  const rating = course.courseRating ?? par * rated / holes;
  return whsCourseHandicapForHoles(index, course.slopeRating ?? STANDARD_SLOPE, rating, rated, par, holes) + 0;
}

/**
 * `lagGrunnlag`: seedet → gruppetallet. Som PWA-en: banehandicap · antall hull / 18, ikke avrundet. Golfreglene:
 * banehandicapet for hullene som spilles (WHS appendiks C).
 */
export function teamBasis(player: Player | null | undefined, round: Round, rules: Ruleset = GOLFGUTU): number {
  const gh = groupHandicap(player, rules);
  if (gh !== null) return gh;
  const ch = courseHandicap(player, round, rules);
  return rules.handicap.calculation === "whs" ? ch : ch * (numberOfHoles(round) / 18);
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
  return handicapRoundWhole(rules.handicap.calculation, sum);
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
 * 4. Ellers som PWA-en `round(banehandicap · tildeling · antall hull / 18)`, eller etter golfreglene
 *    `round(banehandicap for hullene · tildeling)` (regel 6.2), ,5 bort fra null.
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
  const ch = courseHandicap(player, round, rules);
  if (rules.handicap.calculation === "whs") return handicapRoundWhole("whs", ch * allowance(round));
  return jsRound(ch * allowance(round) * (numberOfHoles(round) / 18));
}
