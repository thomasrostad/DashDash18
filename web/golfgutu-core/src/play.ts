// Maks slag per hull i utregningen (PlayRules.swift, `Round.cappingStrokes` og `strokeLimit`).
// Gruppen selv (typer, JSON og standard) ligger i ruleset.ts.

import { courseHoles, numberOfHoles } from "./course.ts";
import { effectiveHandicap } from "./handicap.ts";
import { copyRound, type PlayedHole, type Player, type Round } from "./models.ts";
import { maxStrokesLimit, type Ruleset } from "./ruleset.ts";
import { handicapStrokes } from "./scoring.ts";

function limitFor(round: Round, hole: PlayedHole, handicap: number, rules: Ruleset): number | null {
  const received = handicapStrokes(handicap, hole.strokeIndex, numberOfHoles(round));
  return maxStrokesLimit(rules.play.maxStrokes, hole.par, received);
}

/** Grensen for `playerID` på hull `hole` (0-basert), eller `null` uten grense. */
export function strokeLimit(round: Round, hole: number, playerID: string, roster: readonly Player[], rules: Ruleset): number | null {
  if (rules.play.maxStrokes.type === "off") return null;
  const course = courseHoles(round);
  if (hole < 0 || hole >= course.length) return null;
  const hcp = effectiveHandicap(roster.find((p) => p.id === playerID) ?? null, round, roster, rules);
  return limitFor(round, course[hole], hcp, rules);
}

/** Runden med hver score kappet til grensen (`play.maxStrokes`). Uendret (samme objekt) når grensen er av. */
export function cappingStrokes(round: Round, roster: readonly Player[], rules: Ruleset): Round {
  if (rules.play.maxStrokes.type === "off" || round.holeScores.size === 0) return round;
  const course = courseHoles(round);
  const r = copyRound(round);
  for (const [pid, scores] of round.holeScores) {
    const hcp = effectiveHandicap(roster.find((p) => p.id === pid) ?? null, round, roster, rules);
    const capped = new Map(scores);
    for (const [h, gross] of scores) {
      if (h < 0 || h >= course.length) continue;
      const max = limitFor(round, course[h], hcp, rules);
      if (max !== null && gross > max) capped.set(h, max);
    }
    r.holeScores.set(pid, capped);
  }
  return r;
}
