// Trekanten og trekningen av matcher (Triangle.swift, db-nytt.js linje 537–566 og 779–803).

import { norwegianCompare } from "./jsmath.ts";
import { isTriangle, type Match, type Player, type Round } from "./models.ts";
import { GOLFGUTU, type Ruleset } from "./ruleset.ts";
import { roundNetTotal } from "./scoring.ts";

/**
 * `trekantPoeng`: tre spillere rangert på rundens stablefordsum, med plasspoengene fra regelsettet.
 * Delt plass deler summen av plassene. `null` når matchen ikke er en trekant, eller når en av de tre
 * ikke har ført noe.
 */
export function trianglePoints(m: Match, round: Round, roster: readonly Player[], rules: Ruleset = GOLFGUTU): Map<string, number> | null {
  const placePoints = rules.table.trianglePoints;
  if (!isTriangle(m) || m.playerA === null || m.playerB === null || m.playerC === null) return null;
  const ids = [m.playerA, m.playerB, m.playerC];
  const totals: number[] = [];
  for (const pid of ids) {
    const scores = round.holeScores.get(pid);
    if (scores === undefined || scores.size === 0) return null;
    totals.push(roundNetTotal(round, roster.find((p) => p.id === pid) ?? null, roster, rules));
  }
  // Høyest først. Ved likt beholdes rekkefølgen A, B, C.
  const ranked = [0, 1, 2].sort((x, y) => (totals[x] !== totals[y] ? totals[y] - totals[x] : x - y));
  const out = new Map<string, number>();
  let i = 0;
  while (i < ranked.length) {
    let j = i;
    while (j + 1 < ranked.length && totals[ranked[j + 1]] === totals[ranked[i]]) j++;
    let shared = 0;
    for (let k = i; k <= j; k++) shared += k < placePoints.length ? placePoints[k] : 0;
    const each = shared / (j - i + 1);
    for (let n = i; n <= j; n++) out.set(ids[ranked[n]], each);
    i = j + 1;
  }
  return out;
}

/**
 * `trekkMatcher`: sveitsisk trekning. Sorter på stilling (høyest først), så navn (norsk). Oddetall
 * omgang snur rekka. Oddetall spillere: de tre siste blir en trekant. Under to spillere: ingen matcher.
 * `standing`: tabellpoeng per spiller-id (mangler = 0). `round`: omgangen, 0-basert.
 */
export function drawMatches(participants: readonly Player[], round: number, standing: ReadonlyMap<string, number>): string[][] {
  const order = participants
    .map((p, offset) => ({ p, offset }))
    .sort((x, y) => {
      const sx = standing.get(x.p.id) ?? 0;
      const sy = standing.get(y.p.id) ?? 0;
      if (sx !== sy) return sx > sy ? -1 : 1;
      const byName = norwegianCompare(x.p.name, y.p.name);
      if (byName !== 0) return byName;
      return x.offset - y.offset;
    })
    .map((x) => x.p);
  if (round % 2 === 1) order.reverse();

  const pairs: string[][] = [];
  if (order.length < 2) return pairs;
  const triangle = order.length % 2 === 1;
  const end = triangle ? order.length - 3 : order.length;
  for (let i = 0; i + 1 < end; i += 2) pairs.push([order[i].id, order[i + 1].id]);
  if (triangle) pairs.push(order.slice(-3).map((p) => p.id));
  return pairs;
}
