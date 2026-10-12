// Lag mot lag (Ryder Cup) som oppskrift (RyderCup.swift): to sider, flere matcher per kveld, poeng til
// siden per match vunnet eller delt (`formPlay.teamMatch`) og en lagtabell.

import { sortedStrings } from "./jsmath.ts";
import { allInMatch, matchSides, outcomeForA, pointsForOutcome } from "./match.ts";
import { isTriangle, makeMatch, makePlayer, type Match, type Player, type Round } from "./models.ts";
import type { Ruleset } from "./ruleset.ts";

export type TeamMatchState = "pending" | "decided" | "invalid";

export interface TeamMatchResult {
  roundIndex: number;
  roundID: string | null;
  matchNo: number | null;
  sideA: number | null;
  sideB: number | null;
  state: TeamMatchState;
  outcomeA: number | null;
  pointsA: number;
  pointsB: number;
}

export interface TeamMatchRow {
  side: number;
  points: number;
  won: number;
  halved: number;
  lost: number;
}

export interface RyderCupResult {
  matches: TeamMatchResult[];
  table: TeamMatchRow[];
}

/** Lagkonkurransen over rundene (se `RyderCup.evaluate`). */
export function evaluateRyderCup(rounds: readonly Round[], sides: ReadonlyMap<string, number>, roster: readonly Player[], rules: Ruleset): RyderCupResult {
  const points = rules.formPlay.teamMatch;
  // `outcomeForA` slår opp spilleren i troppen for det frosne handicapet; de som mangler, legges til.
  const known = new Set(roster.map((p) => p.id));
  const missing = new Set<string>();
  for (const r of rounds) for (const m of r.matches) for (const id of allInMatch(matchSides(m, r))) if (!known.has(id)) missing.add(id);
  const fullRoster = [...roster, ...sortedStrings(missing).map((id) => makePlayer(id))];

  const matches: TeamMatchResult[] = [];
  const rows = new Map<number, TeamMatchRow>();
  for (const side of [...new Set(sides.values())].sort((a, b) => a - b)) rows.set(side, { side, points: 0, won: 0, halved: 0, lost: 0 });

  rounds.forEach((round, i) => {
    if (!round.counts || round.weight === 0) return;
    for (const m of round.matches) {
      if (isTriangle(m)) continue;
      const s = matchSides(m, round);
      const aSides = new Set(s.a.map((p) => sides.get(p) ?? null));
      const bSides = new Set(s.b.map((p) => sides.get(p) ?? null));
      const sa = aSides.size === 1 ? [...aSides][0] : null;
      const sb = bSides.size === 1 ? [...bSides][0] : null;
      const base = { roundIndex: i, roundID: round.id, matchNo: m.matchNo };
      if (sa === null || sb === null || sa === sb) {
        matches.push({ ...base, sideA: null, sideB: null, state: "invalid", outcomeA: null, pointsA: 0, pointsB: 0 });
        continue;
      }
      const outcome = outcomeForA(m, round, fullRoster, rules);
      if (outcome === null) {
        matches.push({ ...base, sideA: sa, sideB: sb, state: "pending", outcomeA: null, pointsA: 0, pointsB: 0 });
        continue;
      }
      const pa = pointsForOutcome(outcome, points);
      const pb = pointsForOutcome(1 - outcome, points);
      matches.push({ ...base, sideA: sa, sideB: sb, state: "decided", outcomeA: outcome, pointsA: pa, pointsB: pb });
      for (const [side, mine, p] of [[sa, outcome, pa], [sb, 1 - outcome, pb]] as const) {
        const row = rows.get(side) ?? { side, points: 0, won: 0, halved: 0, lost: 0 };
        row.points += p;
        if (mine === 1) row.won += 1;
        else if (mine === 0) row.lost += 1;
        else row.halved += 1;
        rows.set(side, row);
      }
    }
  });
  const table = [...rows.values()].sort((a, b) => (a.points !== b.points ? b.points - a.points : a.side - b.side));
  return { matches, table };
}

/** Side 1 sine lag mot side 2 sine, i lagnummerets rekkefølge (første mot første). */
export function ryderCupPairings(teams: ReadonlyMap<string, number>, sides: ReadonlyMap<string, number>): Match[] {
  const numbers = [...new Set(teams.values())].sort((a, b) => a - b);
  const sideOf = (team: number): number | null => {
    const first = sortedStrings([...teams].filter(([, t]) => t === team).map(([id]) => id))[0];
    return first === undefined ? null : sides.get(first) ?? null;
  };
  const one = numbers.filter((n) => sideOf(n) === 1);
  const two = numbers.filter((n) => sideOf(n) === 2);
  const out: Match[] = [];
  for (let i = 0; i < Math.min(one.length, two.length); i++) out.push(makeMatch({ teamA: one[i], teamB: two[i] }));
  return out;
}

/** Singler: første mot første, nummerert fra 1. */
export function ryderCupSingles(a: readonly string[], b: readonly string[]): Match[] {
  const out: Match[] = [];
  for (let i = 0; i < Math.min(a.length, b.length); i++) out.push(makeMatch({ matchNo: i + 1, playerA: a[i], playerB: b[i] }));
  return out;
}
