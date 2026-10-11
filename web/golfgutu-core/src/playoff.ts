// Playoff om førsteplassen (Playoff.swift, steg 6, `table.tieRule = playoff`) og «skjul de siste
// hullene» (`hiddenHoleIndices`, `hidingLastHoles`).
//
// Sudden death over hullene arrangøren velger: laveste score vinner hullet, de som ikke har beste score er
// ute, første hull med én beste avgjør. Scoren er netto med spillerens handicap i playoff-runden
// (rundens andel, frosne handicap, seeding); en bruttokonkurranse (andel 0) og simulatoren som deler ut
// slagene gir brutto.

import { courseHoles, numberOfHoles } from "./course.ts";
import { effectiveHandicap } from "./handicap.ts";
import { copyRound, makePlayer, type Player, type Round } from "./models.ts";
import { GOLFGUTU, type Ruleset } from "./ruleset.ts";
import { netStrokes } from "./scoring.ts";

/** Stillingen i playoffen. `position` og `next` er 0-baserte posisjoner i rekkefølgen hullene spilles. */
export type PlayoffDecision =
  | { kind: "won"; winner: string; position: number }
  | { kind: "pending"; remaining: string[]; next: number | null };

/** Forslaget til hull: siste, første, siste igjen. */
export function suggestedPlayoffHoles(round: Round): number[] {
  const last = numberOfHoles(round) - 1;
  return [last, 0, last];
}

/** Avgjør playoffen (`Playoff.decide`). `scores`: bruttoslag per spiller i samme rekkefølge som `holes`. */
export function decidePlayoff(
  players: readonly string[],
  holes: readonly number[],
  scores: ReadonlyMap<string, readonly number[]>,
  round: Round,
  roster: readonly Player[],
  rules: Ruleset = GOLFGUTU,
): PlayoffDecision {
  let remaining = [...players];
  if (remaining.length <= 1) {
    return remaining.length === 1 ? { kind: "won", winner: remaining[0], position: 0 } : { kind: "pending", remaining: [], next: null };
  }
  const course = courseHoles(round);
  const count = numberOfHoles(round);
  const handicap = new Map<string, number>();
  for (const id of players) handicap.set(id, effectiveHandicap(roster.find((p) => p.id === id) ?? makePlayer(id), round, roster, rules));
  for (let position = 0; position < holes.length; position++) {
    const hole = holes[position];
    if (!(hole >= 0 && hole < course.length)) return { kind: "pending", remaining, next: position };
    const net = new Map<string, number>();
    for (const id of remaining) {
      const strokes = scores.get(id);
      if (strokes === undefined || position >= strokes.length) return { kind: "pending", remaining, next: position };
      net.set(id, netStrokes(strokes[position], handicap.get(id) ?? 0, course[hole].strokeIndex, count));
    }
    const best = Math.min(...net.values());
    remaining = remaining.filter((id) => net.get(id) === best);
    if (remaining.length === 1) return { kind: "won", winner: remaining[0], position };
  }
  return { kind: "pending", remaining, next: null };
}

/** Hullene som skjules nå (0-baserte indekser): de siste `hideLastHoles` så lenge runden ikke er låst. */
export function hiddenHoleIndices(round: Round): number[] {
  const n = numberOfHoles(round);
  const hidden = Math.min(Math.max(0, round.hideLastHoles ?? 0), n);
  if (round.locked || hidden <= 0) return [];
  return Array.from({ length: hidden }, (_, i) => n - hidden + i);
}

/**
 * Runden slik den vises for andre mens den pågår: scorene på de skjulte hullene er fjernet, unntatt for
 * spillerne i `revealedTo` (markøren ser båsen hun fører; appen bestemmer). Låst runde: alt synlig.
 */
export function hidingLastHoles(round: Round, revealedTo: ReadonlySet<string> = new Set()): Round {
  const hidden = new Set(hiddenHoleIndices(round));
  if (hidden.size === 0) return round;
  const r = copyRound(round);
  for (const [id, scores] of round.holeScores) {
    if (revealedTo.has(id)) continue;
    r.holeScores.set(id, new Map([...scores].filter(([h]) => !hidden.has(h))));
  }
  return r;
}
