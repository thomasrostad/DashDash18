// Avkortet runde (Truncation.swift, db-nytt.js linje 911–990).

import { numberOfHoles } from "./course.ts";
import { effectiveHandicap } from "./handicap.ts";
import { jsRound } from "./jsmath.ts";
import { copyRound, type Player, type Round } from "./models.ts";
import { GOLFGUTU, type Ruleset } from "./ruleset.ts";
import { pointsFromScores } from "./scoring.ts";

/** Regelen for uspilte hull (`AVKORT_REGLER`). Verdiene er de som lagres på runden. */
export type TruncationRule = "felles" | "nettopar" | "null";
export const TRUNCATION_RULES: readonly TruncationRule[] = ["felles", "nettopar", "null"];

/** Navnet i `AVKORT_REGLER`. */
export function truncationRuleName(r: TruncationRule): string {
  switch (r) {
    case "felles":
      return "Tell til laveste felles hull";
    case "nettopar":
      return "Uspilte hull gir netto par";
    case "null":
      return "Uspilte hull gir 0 poeng";
  }
}

/** Hjelpeteksten i `AVKORT_REGLER`. */
export function truncationRuleHelp(r: TruncationRule): string {
  switch (r) {
    case "felles":
      return "Bare hullene alle rakk teller, for alle. Rettferdig, men de som rakk lengst mister poengene sine fra de siste hullene.";
    case "nettopar":
      return "Hele runden teller. Hvert hull uten score gir 2 poeng, som om det ble spilt til netto par.";
    case "null":
      return "Hele runden teller. Hull uten score gir ingenting — den som rakk flest hull vinner mest på det.";
  }
}

/** `avkortRegel`: regelen på runden, eller `null` når runden ikke er avkortet. */
export function truncationRule(round: Round): TruncationRule | null {
  const r = round.avkortRegel;
  return r !== null && (TRUNCATION_RULES as readonly string[]).includes(r) ? (r as TruncationRule) : null;
}

/** `erAvkortet`. */
export function isTruncated(round: Round): boolean {
  return truncationRule(round) !== null;
}

/** `tellendeHull`: bare `felles` kutter, til `min(antall, round(avkortetEtter))`. Ugyldig eller under 1 → hele. */
export function countingHoles(round: Round): number {
  const count = numberOfHoles(round);
  if (truncationRule(round) !== "felles") return count;
  const after = round.avkortetEtter;
  if (after === null || !Number.isFinite(after) || after < 1) return count;
  return Math.min(count, jsRound(after));
}

/** `poengForTomtHull`: poeng for netto par med `nettopar`, ellers 0. */
export function pointsForEmptyHole(round: Round, rules: Ruleset = GOLFGUTU): number {
  return truncationRule(round) === "nettopar" ? rules.scoring.netParPoints : 0;
}

/** `lavesteFellesHull`: sammenhengende førte hull fra hull 1, laveste blant dem som har begynt. */
export function lowestCommonHole(round: Round): number {
  const started = [...round.holeScores.values()].filter((s) => s.size > 0);
  if (started.length === 0) return 0;
  const count = numberOfHoles(round);
  let lowest = count;
  for (const scores of started) {
    let n = 0;
    while (n < count && scores.has(n)) n++;
    lowest = Math.min(lowest, n);
  }
  return lowest;
}

/** Én spiller som får en annen sum med avkortingen. */
export interface TruncationChange {
  playerID: string;
  before: number;
  after: number;
  diff: number;
}

/** Hva avkortingen koster. */
export interface TruncationCost {
  countingHoles: number;
  holes: number;
  /** Spillerne som får en annen sum, størst tap først. */
  changes: TruncationChange[];
}

/** `avkortingenKoster`: summen per spiller før og etter en tenkt avkorting. */
export function truncationCost(round: Round, after: number, rule: TruncationRule | null, roster: readonly Player[], rules: Ruleset = GOLFGUTU): TruncationCost {
  const draft = copyRound(round);
  draft.avkortetEtter = Number.isFinite(after) ? jsRound(after) : null;
  draft.avkortRegel = rule;

  const changes: { index: number; change: TruncationChange }[] = [];
  roster.forEach((player, index) => {
    const scores = round.holeScores.get(player.id);
    if (scores === undefined || scores.size === 0) return;
    const hcp = effectiveHandicap(player, round, roster, rules);
    const before = pointsFromScores(scores, round, hcp, rules);
    const afterPoints = pointsFromScores(scores, draft, hcp, rules);
    if (before !== afterPoints) {
      changes.push({ index, change: { playerID: player.id, before, after: afterPoints, diff: afterPoints - before } });
    }
  });
  changes.sort((a, b) => (a.change.diff !== b.change.diff ? a.change.diff - b.change.diff : a.index - b.index));
  return { countingHoles: countingHoles(draft), holes: numberOfHoles(round), changes: changes.map((c) => c.change) };
}
