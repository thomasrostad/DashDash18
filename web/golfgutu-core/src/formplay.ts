// Formene fra steg 7 (FormPlay.swift, GameSkins.swift og GameContext i Games.swift): skins som form,
// poengspillene Amerikaner og Københavner (NGF «Spilleformer» 2023, side 3 og 4), og poengene en runde
// gir i tabellen med `table.formPoints`. Bare det tabellen og konkurransene trenger av rundespillene;
// oppgjøret i poeng (`PointSplit`) er ikke portert.

import { courseHoles, numberOfHoles } from "./course.ts";
import { formAxes, roundForm, type PointsGameKind } from "./forms.ts";
import { effectiveHandicap } from "./handicap.ts";
import { jsRound, sortedStrings, stringLess } from "./jsmath.ts";
import { makePlayer, type PlayedHole, type Player, type Round } from "./models.ts";
import { pointsGameRules, type GameHandicap, type ParBogeyRules, type PointsGameRules, type Ruleset, type SkinsRules } from "./ruleset.ts";
import { handicapStrokes, roundPoints } from "./scoring.ts";
import { isTruncated } from "./truncation.ts";

// MARK: Runden sett fra et spill (GameContext)

/** Hullene som teller i spill på runden: rundens hull, kuttet ved avkortingen uansett regel. */
export function gameCountingHoles(round: Round): number {
  const n = numberOfHoles(round);
  const after = round.avkortetEtter;
  if (isTruncated(round) && after !== null && Number.isFinite(after) && after >= 1) return Math.min(n, jsRound(after));
  return n;
}

/** Runden er ferdig (låst eller avkortet). */
export function gameIsFinal(round: Round): boolean {
  return round.locked || isTruncated(round);
}

export class GameContext {
  readonly players: readonly string[];
  readonly round: Round;
  readonly roster: readonly Player[];
  readonly rules: Ruleset;
  readonly holes: PlayedHole[];
  readonly count: number;
  readonly isFinal: boolean;

  constructor(players: readonly string[], round: Round, roster: readonly Player[], rules: Ruleset) {
    this.players = players;
    this.round = round;
    this.roster = roster;
    this.rules = rules;
    this.holes = courseHoles(round);
    this.count = Math.min(gameCountingHoles(round), this.holes.length);
    this.isFinal = gameIsFinal(round);
  }

  /** Spillehandicapet i spillet per spiller (hele slag). */
  handicaps(h: GameHandicap): Map<string, number> {
    const out = new Map<string, number>();
    if (!h.net) {
      for (const p of this.players) out.set(p, 0);
      return out;
    }
    for (const p of this.players) {
      const player = this.roster.find((x) => x.id === p) ?? makePlayer(p);
      out.set(p, jsRound(effectiveHandicap(player, this.round, this.roster, this.rules) * h.allowance));
    }
    if (h.fromLowest && out.size > 0) {
      const low = Math.min(...out.values());
      for (const p of this.players) out.set(p, out.get(p)! - low);
    }
    return out;
  }

  gross(p: string, hole: number): number | null {
    return this.round.holeScores.get(p)?.get(hole) ?? null;
  }

  /** Slagene spilleren får på hullet. */
  strokes(p: string, hole: number, hcp: ReadonlyMap<string, number>): number {
    return handicapStrokes(hcp.get(p) ?? 0, this.holes[hole].strokeIndex, numberOfHoles(this.round));
  }

  /** Netto på hullet, eller `null` uten score. */
  net(p: string, hole: number, hcp: ReadonlyMap<string, number>): number | null {
    const g = this.gross(p, hole);
    if (g === null) return null;
    return g - this.strokes(p, hole, hcp);
  }

  /** Hullet kan regnes: alle har ført det, eller runden er ferdig. */
  isReady(hole: number): boolean {
    return this.isFinal || this.players.every((p) => this.gross(p, hole) !== null);
  }
}

// MARK: Par/bogey (FormPlay.swift)

/**
 * Par/bogey (Golfreglene 2019, regel 21.3): netto mot par på hullet. `null` (ingen score) er tapt (21.3b);
 * kalleren bestemmer om hullet venter mens runden går.
 */
export function parBogeyHoleValue(net: number | null, par: number, rules: ParBogeyRules): number {
  if (net === null) return rules.loss;
  if (net < par) return rules.win;
  if (net === par) return rules.halve;
  return rules.loss;
}

// MARK: Skins (GameSkins.swift)

export type SkinsHoleState = "pending" | "won" | "halved";

export interface SkinsHole {
  hole: number;
  state: SkinsHoleState;
  winners: string[];
  value: number;
}

export interface SkinsResult {
  holes: SkinsHole[];
  /** Skins vunnet per spiller (alle i spillet). */
  scores: Map<string, number>;
  isFinished: boolean;
  carry: number;
}

/** Skins med carry-over som rundespillet: lavest score alene vinner skinnet (og det som står). */
export function evaluateSkins(players: readonly string[], round: Round, roster: readonly Player[], rules: Ruleset, r: SkinsRules): SkinsResult {
  const ctx = new GameContext(players, round, roster, rules);
  const hcp = ctx.handicaps(r.handicap);
  const holes: SkinsHole[] = [];
  const scores = new Map<string, number>(players.map((p) => [p, 0]));
  let carry = 0;
  let lastLow: string[] = [];
  let stopped = false;
  for (let h = 0; h < ctx.count; h++) {
    if (stopped || !ctx.isReady(h)) {
      stopped = true;
      holes.push({ hole: h, state: "pending", winners: [], value: 0 });
      continue;
    }
    const nets: { id: string; net: number }[] = [];
    for (const p of players) {
      const n = ctx.net(p, h, hcp);
      if (n !== null) nets.push({ id: p, net: n });
    }
    const low = nets.length > 0 ? Math.min(...nets.map((x) => x.net)) : null;
    const atLow = nets.filter((x) => x.net === low).map((x) => x.id);
    if (atLow.length === 1) {
      const count = carry + 1;
      scores.set(atLow[0], (scores.get(atLow[0]) ?? 0) + count);
      holes.push({ hole: h, state: "won", winners: atLow, value: count });
      carry = 0;
    } else {
      carry = r.carryOver ? carry + 1 : 0;
      holes.push({ hole: h, state: "halved", winners: atLow, value: 0 });
    }
    lastLow = atLow;
  }
  const finished = !stopped;
  if (finished && carry > 0 && r.leftover === "split" && lastLow.length > 0) {
    for (const p of lastLow) scores.set(p, (scores.get(p) ?? 0) + carry / lastLow.length);
    carry = 0;
  } else if (finished) {
    carry = 0;
  }
  return { holes, scores, isFinished: finished, carry };
}

// MARK: Poengspillene (PointsGame)

export type PointsGameHoleState = "pending" | "scored" | "void";

export interface PointsGameHole {
  hole: number;
  state: PointsGameHoleState;
  pattern: string | null;
  points: Map<string, number>;
}

export interface PointsGameResult {
  kind: PointsGameKind;
  players: string[];
  holes: PointsGameHole[];
  totals: Map<string, number>;
  isFinished: boolean;
}

/** Spillerne gruppert etter score, beste (lavest) først; innen gruppen sortert på id. */
function scoreGroups(scores: ReadonlyMap<string, number>): string[][] {
  const sorted = [...scores].sort((a, b) => (a[1] !== b[1] ? a[1] - b[1] : stringLess(a[0], b[0]) ? -1 : stringLess(b[0], a[0]) ? 1 : 0));
  const out: string[][] = [];
  let last: number | null = null;
  for (const [id, s] of sorted) {
    if (s === last) out[out.length - 1].push(id);
    else out.push([id]);
    last = s;
  }
  return out;
}

/** Likhetsmønsteret: gruppestørrelsene fra beste score, skilt med «-» (f.eks. «1-2-1»). */
export function pointsGamePattern(scores: ReadonlyMap<string, number>): string {
  return scoreGroups(scores).map((g) => String(g.length)).join("-");
}

/** Poengene på ett hull, eller `null` når antallet eller mønsteret ikke finnes i tabellen. */
export function pointsGameHolePoints(scores: ReadonlyMap<string, number>, rules: PointsGameRules): Map<string, number> | null {
  if (scores.size !== rules.players) return null;
  const table = rules.points[pointsGamePattern(scores)];
  if (!table || table.length !== rules.players) return null;
  const out = new Map<string, number>();
  let place = 0;
  for (const group of scoreGroups(scores)) {
    const share = table.slice(place, place + group.length).reduce((a, b) => a + b, 0) / group.length;
    for (const id of group) out.set(id, share);
    place += group.length;
  }
  return out;
}

/** Poengspillet for en gruppe (se `PointsGame.evaluate`). `range`: 0-baserte hull, inkludert. */
export function evaluatePointsGame(
  kind: PointsGameKind, players: readonly string[], round: Round, roster: readonly Player[], rules: Ruleset,
  range: { first: number; last: number } | null = null,
): PointsGameResult {
  const game = pointsGameRules(rules, kind);
  const ctx = new GameContext(players, round, roster, rules);
  const hcp = ctx.handicaps(game.handicap);
  const totals = new Map<string, number>(players.map((p) => [p, 0]));
  const holes: PointsGameHole[] = [];
  for (let h = 0; h < ctx.count; h++) {
    if (range !== null && (h < range.first || h > Math.max(range.first, range.last))) continue;
    const nets = new Map<string, number>();
    for (const p of players) {
      const n = ctx.net(p, h, hcp);
      if (n !== null) nets.set(p, n);
    }
    if (nets.size !== players.length) {
      holes.push({ hole: h, state: ctx.isFinal ? "void" : "pending", pattern: null, points: new Map() });
      continue;
    }
    const points = pointsGameHolePoints(nets, game);
    if (points === null) {
      holes.push({ hole: h, state: "void", pattern: pointsGamePattern(nets), points: new Map() });
      continue;
    }
    for (const [p, v] of points) totals.set(p, (totals.get(p) ?? 0) + v);
    holes.push({ hole: h, state: "scored", pattern: pointsGamePattern(nets), points });
  }
  return { kind, players: [...players], holes, totals, isFinished: !holes.some((x) => x.state === "pending") };
}

// MARK: Tabellpoeng fra formen

/** Spillerne med score i runden, sortert på id. */
export function scoredPlayers(round: Round): string[] {
  return sortedStrings([...round.holeScores].filter(([, s]) => s.size > 0).map(([id]) => id));
}

/** Gruppene i et poengspill: rundens lag (lagnummeret er gruppen), ellers alle med score i én gruppe. */
export function pointsGameGroups(round: Round): string[][] {
  if (round.teams.size === 0) return [scoredPlayers(round)];
  const numbers = [...new Set(round.teams.values())].sort((a, b) => a - b);
  return numbers.map((n) => sortedStrings([...round.teams].filter(([, t]) => t === n).map(([id]) => id)));
}

/** Poengene runden gir i tabellen med `table.formPoints` (se `FormPlay.tablePoints`). Uvektet. */
export function formTablePoints(round: Round, roster: readonly Player[], rules: Ruleset): Map<string, number> {
  const scoring = formAxes(roundForm(round)).scoring;
  if (scoring.type === "parBogey") {
    // Par/bogey-summen (regel 21.3) med fullt spillehandicap, hver spiller for seg (formen er individuell).
    const players = scoredPlayers(round);
    const ctx = new GameContext(players, round, roster, rules);
    const hcp = ctx.handicaps({ net: true, allowance: 1, fromLowest: false });
    const out = new Map<string, number>();
    for (const p of players) {
      let total = 0;
      for (let h = 0; h < ctx.count; h++) {
        const n = ctx.net(p, h, hcp);
        if (n === null && !ctx.isFinal) continue;
        total += parBogeyHoleValue(n, ctx.holes[h].par, rules.formPlay.parBogey);
      }
      out.set(p, total);
    }
    return out;
  }
  if (scoring.type === "skins") {
    const players = scoredPlayers(round);
    if (players.length === 0) return new Map();
    const r = evaluateSkins(players, round, roster, rules, rules.formPlay.skins);
    return new Map(players.map((p) => [p, (r.scores.get(p) ?? 0) * rules.formPlay.skinPoints]));
  }
  if (scoring.type === "pointsGame") {
    const out = new Map<string, number>();
    for (const group of pointsGameGroups(round)) {
      if (group.length === 0) continue;
      for (const [p, v] of evaluatePointsGame(scoring.game, group, round, roster, rules).totals) out.set(p, v);
    }
    return out;
  }
  return new Map([...roundPoints(round, roster, rules)].map(([k, v]) => [k, v]));
}
