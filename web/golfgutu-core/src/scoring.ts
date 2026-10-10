// Slag og stablefordpoeng (Scoring.swift, db-nytt.js linje 823–836, 906–909, 992–1050).

import { courseHoles, numberOfHoles } from "./course.ts";
import { roundForm } from "./forms.ts";
import { effectiveHandicap, teammates } from "./handicap.ts";
import { jsRound, sortedStrings } from "./jsmath.ts";
import type { HoleScores, Player, Round } from "./models.ts";
import { GOLFGUTU, type Ruleset } from "./ruleset.ts";
import { countingHoles, pointsForEmptyHole } from "./truncation.ts";

/** Hvordan et hull gikk, netto mot par (`scoreNameForHole`). */
export type ScoreName = "eagle" | "birdie" | "par" | "bogey" | "dobbel" | "blowup";

/** `SCORE_LABEL`. */
export function scoreNameLabel(n: ScoreName): string {
  switch (n) {
    case "eagle":
      return "Eagle";
    case "birdie":
      return "Birdie";
    case "par":
      return "Par";
    case "bogey":
      return "Bogey";
    case "dobbel":
      return "Dobbel";
    case "blowup":
      return "Blowup";
  }
}

/** `handicapStrokesForHole`: slag fått på hullet. Handicap rundes som JS og kan ikke bli negativt. */
export function handicapStrokes(handicap: number, strokeIndex: number, holes: number): number {
  const n = holes === 9 || holes === 18 ? holes : 18;
  const h = Math.max(0, jsRound(Number.isNaN(handicap) ? 0 : handicap));
  return Math.trunc(h / n) + (strokeIndex <= h % n ? 1 : 0);
}

/** `netStrokesForHole`. */
export function netStrokes(gross: number, handicap: number, strokeIndex: number, holes: number): number {
  return gross - handicapStrokes(handicap, strokeIndex, holes);
}

/** `pointsForHole`: `max(bunn, par − netto + poeng for netto par)` fra regelsettet. */
export function holePoints(par: number, gross: number, handicap: number, strokeIndex: number, holes: number, rules: Ruleset = GOLFGUTU): number {
  const net = netStrokes(gross, handicap, strokeIndex, holes);
  return Math.max(rules.scoring.minimumPoints, par - net + rules.scoring.netParPoints);
}

/** `scoreNameForHole`: netto − par. ≤ −2 eagle, −1 birdie, 0 par, 1 bogey, 2 dobbel, ellers blowup. */
export function scoreName(par: number, gross: number, handicap: number, strokeIndex: number, holes: number): ScoreName {
  const diff = netStrokes(gross, handicap, strokeIndex, holes) - par;
  if (diff <= -2) return "eagle";
  if (diff === -1) return "birdie";
  if (diff === 0) return "par";
  if (diff === 1) return "bogey";
  if (diff === 2) return "dobbel";
  return "blowup";
}

/**
 * `poengFraHull`: stablefordsummen over de tellende hullene. Hull uten score gir `poengForTomtHull`.
 * Ingen score i det hele tatt gir 0, også med `nettopar`.
 */
export function pointsFromScores(scores: HoleScores, round: Round, handicap: number, rules: Ruleset = GOLFGUTU): number {
  if (scores.size === 0) return 0;
  const course = courseHoles(round);
  const count = numberOfHoles(round);
  const counting = countingHoles(round);
  const empty = pointsForEmptyHole(round, rules);
  let total = 0;
  for (let i = 0; i < counting && i < course.length; i++) {
    const hole = course[i];
    const gross = scores.get(i);
    total += gross !== undefined ? holePoints(hole.par, gross, handicap, hole.strokeIndex, count, rules) : empty;
  }
  return total;
}

/** `roundNetTotal`: summen for én spiller med et gitt handicap. */
export function roundNetTotalWithHandicap(round: Round, playerID: string | null, handicap: number, rules: Ruleset = GOLFGUTU): number {
  const scores = playerID !== null ? round.holeScores.get(playerID) ?? new Map<number, number>() : new Map<number, number>();
  return pointsFromScores(scores, round, handicap, rules);
}

/** `roundNetTotalForPlayer`: summen med spillerens `effectiveHandicap` i runden. */
export function roundNetTotal(round: Round, player: Player | null, roster: readonly Player[], rules: Ruleset = GOLFGUTU): number {
  return roundNetTotalWithHandicap(round, player?.id ?? null, effectiveHandicap(player, round, roster, rules), rules);
}

/**
 * Rundens poeng per spiller (`round_points`, `regnOmRundePoeng`). Spillere som har ført noe får sin
 * stablefordsum. Er spilleren på et lag med flere, får hele laget lagets sum.
 */
export function roundPoints(round: Round, roster: readonly Player[], rules: Ruleset = GOLFGUTU): Map<string, number> {
  const out = new Map<string, number>();
  for (const pid of sortedStrings(round.holeScores.keys())) {
    if ((round.holeScores.get(pid)?.size ?? 0) === 0) continue;
    if (out.has(pid)) continue;
    const mates = teammates(pid, round);
    if (mates !== null && mates.length > 1) {
      const total = teamPoints(round, mates, roster, rules);
      for (const m of mates) out.set(m, total);
      continue;
    }
    const hcp = effectiveHandicap(roster.find((p) => p.id === pid) ?? null, round, roster, rules);
    out.set(pid, roundNetTotalWithHandicap(round, pid, hcp, rules));
  }
  return out;
}

/** `skrivLagpoeng`: lagets sum etter formens regning. */
export function teamPoints(round: Round, members: readonly string[], roster: readonly Player[], rules: Ruleset): number {
  const course = courseHoles(round);
  const count = numberOfHoles(round);
  const form = roundForm(round);
  const perHole = new Map<number, number[]>();
  for (const pid of members) {
    const scores = round.holeScores.get(pid);
    if (scores === undefined) continue;
    const hcp = effectiveHandicap(roster.find((p) => p.id === pid) ?? null, round, roster, rules);
    const holes = [...scores.keys()].sort((a, b) => a - b);
    for (const h of holes) {
      if (!(h >= 0 && h < course.length)) continue;
      const hole = course[h];
      const list = perHole.get(h) ?? [];
      list.push(holePoints(hole.par, scores.get(h)!, hcp, hole.strokeIndex, count, rules));
      perHole.set(h, list);
    }
  }
  const empty = pointsForEmptyHole(round, rules);
  let total = 0;
  const counting = countingHoles(round);
  for (let h = 0; h < counting; h++) {
    const p = perHole.get(h);
    if (p === undefined || p.length === 0) {
      total += empty;
      continue;
    }
    switch (form.scoring) {
      case "sum-netto":
        total += p.reduce((s, x) => s + x, 0);
        break;
      case "beste-netto":
        total += Math.max(...p);
        break;
      default:
        total += p[0];
    }
  }
  return total;
}
