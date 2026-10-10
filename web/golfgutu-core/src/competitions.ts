// Konkurranser over flere runder (Competitions.swift): liga, morroturnering og cup. Sesongen
// (jakkeracet) regnes av `Season`. Reglene (malene og JSON-en) ligger i ruleset.ts.

import { lexicographicallyPrecedes, norwegianCompare, roundAwayFromZero, sortedBy } from "./jsmath.ts";
import { holeWinner, matchStanding, sideHandicap, strokeOffset } from "./match.ts";
import { makeMatch, type Player, type Round } from "./models.ts";
import { competitionRulesOf, type CupRules, type CupTie, type LeagueRules, type Ruleset } from "./ruleset.ts";
import { countingHoles } from "./truncation.ts";

// MARK: Liga og morroturnering

/** En tellende runde: stablefordpoengene til dem som spilte, spiller-id → poeng. */
export interface LeagueRound {
  id: string;
  stableford: ReadonlyMap<string, number>;
}

/** Plassen og poengene i én runde. */
export interface LeaguePlacing {
  /** 1, 2, 2, 4 …: delt plass har samme nummer. */
  place: number;
  points: number;
}

/** Spillerens resultat i én runde. */
export interface LeagueRoundResult {
  roundID: string;
  place: number;
  stableford: number;
  points: number;
  /** Blant de beste N. */
  counted: boolean;
}

/** En rad i tabellen. */
export interface LeagueRow {
  playerID: string;
  /** 1, 1, 3 …: like på total og alle skillene gir delt plass. */
  place: number;
  total: number;
  played: number;
  wins: number;
  /** Beste enkeltrunde (poeng). `null` før første runde. */
  bestRound: number | null;
  stableford: number;
  /** Rundene spilleren spilte, i tidsrekkefølge. */
  results: LeagueRoundResult[];
}

/** Plass og poeng i runden for de påmeldte som spilte. Andre spillere strykes først. */
export function leaguePlacings(round: LeagueRound, entrants: ReadonlySet<string>, rules: LeagueRules): Map<string, LeaguePlacing> {
  const scores = [...round.stableford]
    .filter(([k]) => entrants.has(k))
    .sort(([ka, va], [kb, vb]) => (va !== vb ? vb - va : ka < kb ? -1 : ka > kb ? 1 : 0));
  const out = new Map<string, LeaguePlacing>();
  let i = 0;
  while (i < scores.length) {
    const value = scores[i][1];
    let j = i;
    while (j < scores.length && scores[j][1] === value) j++;
    // Plassene i..<j deler summen av plassenes poeng.
    let shared = 0;
    for (let k = i; k < j; k++) shared += k < rules.placementPoints.length ? rules.placementPoints[k] : 0;
    shared /= j - i;
    for (let k = i; k < j; k++) {
      const base = rules.scoring === "placement" ? shared : value;
      out.set(scores[k][0], { place: i + 1, points: base + rules.participationPoints });
    }
    i = j;
  }
  return out;
}

/** Tabellen. `entrants` i rekkefølgen som skiller til slutt (navn), `rounds` i tidsrekkefølge. */
export function leagueTable(entrants: readonly string[], rounds: readonly LeagueRound[], rules: LeagueRules): LeagueRow[] {
  const set = new Set(entrants);
  const perRound = rounds.map((r) => leaguePlacings(r, set, rules));
  const rows: LeagueRow[] = entrants.map((id) => {
    const results: LeagueRoundResult[] = [];
    rounds.forEach((round, r) => {
      const p = perRound[r].get(id);
      const s = round.stableford.get(id);
      if (p === undefined || s === undefined) return;
      results.push({ roundID: round.id, place: p.place, stableford: s, points: p.points, counted: true });
    });
    // De beste N: flest poeng, og den tidligste ved likt.
    if (rules.bestRounds !== null) {
      const order = results.map((_, i) => i).sort((a, b) =>
        results[a].points !== results[b].points ? (results[a].points > results[b].points ? -1 : 1) : a - b);
      const keep = new Set(order.slice(0, Math.max(0, rules.bestRounds)));
      results.forEach((r, i) => {
        r.counted = keep.has(i);
      });
    }
    const counted = results.filter((r) => r.counted);
    return {
      playerID: id,
      place: 0,
      total: counted.reduce((s, r) => s + r.points, 0),
      played: results.length,
      wins: results.filter((r) => r.place === 1).length,
      bestRound: results.length > 0 ? Math.max(...results.map((r) => r.points)) : null,
      stableford: counted.reduce((s, r) => s + r.stableford, 0),
      results,
    };
  });

  const key = (row: LeagueRow): number[] => [
    row.total,
    ...rules.tiebreaks.map((t) => (t === "wins" ? row.wins : t === "bestRound" ? row.bestRound ?? 0 : row.stableford)),
  ];
  // Summer av brøker sammenlignes på tusendeler, så 1/3 + 2/3 er lik 1.
  const rounded = (k: number[]) => k.map((x) => roundAwayFromZero(x * 1000));
  const sameKey = (a: number[], b: number[]) => a.length === b.length && a.every((x, i) => x === b[i]);
  const order = new Map(entrants.map((id, i) => [id, i]));
  const sorted = sortedBy(rows, (a, b) => {
    const ka = rounded(key(a));
    const kb = rounded(key(b));
    if (!sameKey(ka, kb)) return lexicographicallyPrecedes(ka, kb, (x, y) => x > y);
    return (order.get(a.playerID) ?? 0) < (order.get(b.playerID) ?? 0);
  });
  sorted.forEach((row, i) => {
    row.place = i > 0 && sameKey(rounded(key(row)), rounded(key(sorted[i - 1]))) ? sorted[i - 1].place : i + 1;
  });
  return sorted;
}

// MARK: Cup

/** En deltaker i cupen med det seedingen trenger. */
export interface CupEntrant {
  id: string;
  name: string;
  handicap: number | null;
  /** Plassen i rangeringen (1 = best). `null`: ikke rangert. */
  rank: number | null;
}

/** En kamp i første runde. `b` tom: walkover (bye) for `a`. */
export interface CupPairing {
  slot: number;
  a: string;
  b: string | null;
}

/** Et ført resultat: vinneren av kamp `slot` i runde `round` (1 = første). */
export interface CupResult {
  round: number;
  slot: number;
  winner: string;
  walkover: boolean;
}

export type CupMatchState = "waiting" | "ready" | "decided";

/** En kamp i treet. */
export interface CupMatch {
  round: number;
  slot: number;
  a: string | null;
  b: string | null;
  winner: string | null;
  isBye: boolean;
  walkover: boolean;
}

export function cupMatchState(m: CupMatch): CupMatchState {
  if (m.winner !== null) return "decided";
  return m.a !== null && m.b !== null ? "ready" : "waiting";
}

function involves(m: CupMatch, id: string): boolean {
  return m.a === id || m.b === id;
}

function opponentIn(m: CupMatch, id: string): string | null {
  return m.a === id ? m.b : m.b === id ? m.a : null;
}

/** Hele treet med det som er avgjort. */
export interface CupBracket {
  /** Rundene, første først. Siste runde er finalen. */
  rounds: CupMatch[][];
  champion: string | null;
}

export function bracketSizeOf(b: CupBracket): number {
  return (b.rounds[0]?.length ?? 0) * 2;
}

/** Kampen spilleren skal spille nå, eller `null` når hen er ute eller har vunnet. */
export function nextCupMatch(b: CupBracket, id: string): CupMatch | null {
  for (const round of b.rounds) {
    const m = round.find((x) => involves(x, id));
    if (m !== undefined && m.winner === null) return m;
  }
  return null;
}

/** Motstanderen i neste kamp, når den er kjent. */
export function cupOpponent(b: CupBracket, id: string): string | null {
  const m = nextCupMatch(b, id);
  return m === null ? null : opponentIn(m, id);
}

/** Hen tapte en kamp. */
export function isEliminated(b: CupBracket, id: string): boolean {
  return b.rounds.flat().some((m) => involves(m, id) && m.winner !== null && m.winner !== id);
}

/** Kampene som kan spilles nå. */
export function readyMatches(b: CupBracket): CupMatch[] {
  return b.rounds.flat().filter((m) => cupMatchState(m) === "ready");
}

export function cupMatchAt(b: CupBracket, round: number, slot: number): CupMatch | null {
  if (round < 1 || round > b.rounds.length || slot < 0 || slot >= b.rounds[round - 1].length) return null;
  return b.rounds[round - 1][slot];
}

/** Antall plasser i treet: minste toerpotens som rommer alle (minst 2). */
export function bracketSize(n: number): number {
  let size = 2;
  while (size < n) size *= 2;
  return size;
}

/** Seedenes plass i treet, ovenfra: 1, 8, 4, 5, 2, 7, 3, 6 for 8. */
export function seedPositions(size: number): number[] {
  let order = [1, 2];
  while (order.length < size) {
    const n = order.length * 2;
    order = order.flatMap((x) => [x, n + 1 - x]);
  }
  return order;
}

/** SplitMix64 (Steele, Lea og Flood 2014): en liten, gjentakbar tallgenerator for trekningen. */
export class SplitMix64 {
  private state: bigint;
  private static readonly MASK = (1n << 64n) - 1n;

  constructor(seed: bigint | number) {
    this.state = BigInt(seed) & SplitMix64.MASK;
  }

  next(): bigint {
    const M = SplitMix64.MASK;
    this.state = (this.state + 0x9e3779b97f4a7c15n) & M;
    let z = this.state;
    z = ((z ^ (z >> 30n)) * 0xbf58476d1ce4e5b9n) & M;
    z = ((z ^ (z >> 27n)) * 0x94d049bb133111ebn) & M;
    return z ^ (z >> 31n);
  }
}

/** Deltakerne i seed-rekkefølge (seed 1 først). */
export function cupSeeded(entrants: readonly CupEntrant[], rules: CupRules, randomSeed: bigint | number): string[] {
  const byHandicap = (a: CupEntrant, b: CupEntrant): boolean => {
    if (a.handicap !== null && b.handicap !== null && a.handicap !== b.handicap) return a.handicap < b.handicap;
    if (a.handicap !== null && b.handicap === null) return true;
    if (a.handicap === null && b.handicap !== null) return false;
    const c = norwegianCompare(a.name, b.name);
    return c !== 0 ? c < 0 : a.id < b.id;
  };
  switch (rules.seeding) {
    case "handicap":
      return sortedBy(entrants, byHandicap).map((e) => e.id);
    case "ranking":
      return sortedBy(entrants, (a, b) => {
        if (a.rank !== null && b.rank !== null && a.rank !== b.rank) return a.rank < b.rank;
        if (a.rank !== null && b.rank === null) return true;
        if (a.rank === null && b.rank !== null) return false;
        return byHandicap(a, b);
      }).map((e) => e.id);
    case "random": {
      const ids = entrants.map((e) => e.id).sort((a, b) => (a < b ? -1 : a > b ? 1 : 0));
      const rng = new SplitMix64(randomSeed);
      for (let i = ids.length - 1; i >= 1; i--) {
        const j = Number(rng.next() % BigInt(i + 1));
        [ids[i], ids[j]] = [ids[j], ids[i]];
      }
      return ids;
    }
  }
}

/** Første runde fra seed-rekkefølgen. De beste seedene får bye når deltakerne ikke fyller treet. */
export function cupDraw(seeded: readonly string[]): CupPairing[] {
  if (seeded.length < 2) return [];
  const positions = seedPositions(bracketSize(seeded.length));
  const out: CupPairing[] = [];
  for (let i = 0; i < positions.length; i += 2) {
    const x = Math.min(positions[i], positions[i + 1]);
    const y = Math.max(positions[i], positions[i + 1]);
    out.push({ slot: i / 2, a: seeded[x - 1], b: y <= seeded.length ? seeded[y - 1] : null });
  }
  return out;
}

/** Treet fra første runde og resultatene. Et resultat som ikke passer, hoppes over. */
export function cupBracket(draw: readonly CupPairing[], results: readonly CupResult[]): CupBracket {
  if (draw.length === 0) return { rounds: [], champion: null };
  // Én kamp per plass (den siste vinner), og plassene fylt opp til en toerpotens.
  const bySlot = new Map<number, CupPairing>();
  for (const p of draw) bySlot.set(p.slot, p);
  const maxSlot = Math.max(...bySlot.keys());
  const slots = bracketSize((maxSlot + 1) * 2) / 2;
  let roundCount = 1;
  while (2 ** roundCount < slots * 2) roundCount++;
  const byKey = new Map<string, CupResult>();
  for (const r of results) byKey.set(`${r.round}:${r.slot}`, r);

  const apply = (m: CupMatch) => {
    if (m.winner !== null || m.a === null || m.b === null) return;
    const r = byKey.get(`${m.round}:${m.slot}`);
    if (r === undefined || (r.winner !== m.a && r.winner !== m.b)) return;
    m.winner = r.winner;
    m.walkover = r.walkover;
  };

  const rounds: CupMatch[][] = [];
  const first: CupMatch[] = [];
  for (let i = 0; i < slots; i++) {
    const p = bySlot.get(i);
    first.push(p === undefined
      ? { round: 1, slot: i, a: null, b: null, winner: null, isBye: false, walkover: false }
      : { round: 1, slot: i, a: p.a, b: p.b, winner: p.b === null ? p.a : null, isBye: p.b === null, walkover: false });
  }
  first.forEach(apply);
  rounds.push(first);
  for (let r = 2; r <= roundCount; r++) {
    const previous = rounds[r - 2];
    const current: CupMatch[] = [];
    for (let i = 0; i < previous.length; i += 2) {
      current.push({ round: r, slot: i / 2, a: previous[i].winner, b: previous[i + 1].winner, winner: null, isBye: false, walkover: false });
    }
    current.forEach(apply);
    rounds.push(current);
  }
  return { rounds, champion: rounds[rounds.length - 1]?.[0]?.winner ?? null };
}

/** Utfallet av en cupkamp spilt i en runde. */
export type CupDecision =
  | { kind: "notStarted" }
  | { kind: "inProgress"; up: number; played: number; remaining: number }
  | { kind: "won"; winner: string; up: number; remaining: number; tie: CupTie | null }
  | { kind: "tied" };

/** Kampen mellom `a` og `b` i runden, som matchspill med regelsettets slag. `seeds`: id → seed. */
export function cupDecide(a: string, b: string, round: Round, roster: readonly Player[], rules: Ruleset, seeds: ReadonlyMap<string, number> = new Map()): CupDecision {
  const match = makeMatch({ playerA: a, playerB: b });
  const st = matchStanding(match, a, round, roster, rules);
  if (st === null || !(st.played > 0)) return { kind: "notStarted" };
  if (st.up !== 0 && (st.decided || st.remaining === 0)) {
    return { kind: "won", winner: st.up > 0 ? a : b, up: Math.abs(st.up), remaining: st.remaining, tie: null };
  }
  if (st.remaining !== 0) return { kind: "inProgress", up: st.up, played: st.played, remaining: st.remaining };

  const tie = competitionRulesOf(rules).cup.tie;
  switch (tie) {
    case "suddenDeath":
      return { kind: "tied" };
    case "countback": {
      const lowest = strokeOffset(match, round, roster, rules);
      for (let hole = countingHoles(round) - 1; hole >= 0; hole--) {
        const w = holeWinner(match, hole, round, roster, rules, lowest);
        if (w !== null && w !== 0) return { kind: "won", winner: w > 0 ? a : b, up: 0, remaining: 0, tie: "countback" };
      }
      return { kind: "tied" };
    }
    case "higherSeed": {
      const sa = seeds.get(a);
      const sb = seeds.get(b);
      if (sa === undefined || sb === undefined || sa === sb) return { kind: "tied" };
      return { kind: "won", winner: sa < sb ? a : b, up: 0, remaining: 0, tie: "higherSeed" };
    }
    case "lowerHandicap": {
      const ha = sideHandicap([a], round, roster, rules);
      const hb = sideHandicap([b], round, roster, rules);
      if (ha === hb) return { kind: "tied" };
      return { kind: "won", winner: ha < hb ? a : b, up: 0, remaining: 0, tie: "lowerHandicap" };
    }
  }
}
