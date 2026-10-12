// Veddemål med poeng (Bets.swift, og `PointSplit.apportion` fra Games.swift). Låsingen, utfallet av
// vilkårene (birdie, par, hullduell, slår i runden, longest drive, nærmest pinnen, match), feiingen,
// malene, oppgjøret i poeng, poengbanken og sjekken av en innsats. Samme svar som Swift-pakken.
// Brukes av oppgjørsfunksjonen på serveren (supabase/functions/bet-settle) når runden låses.

import { courseHoles, numberOfHoles } from "./course.ts";
import { DecodeError, obj, optArray, optInt, optString, reqNumber, reqString } from "./decode.ts";
import { effectiveHandicap } from "./handicap.ts";
import { jsRound, norwegianLess, round2, roundAwayFromZero, sortedBy, stringLess } from "./jsmath.ts";
import { matchInvolves, matchStanding } from "./match.ts";
import type { Player, Round, SideClaim } from "./models.ts";
import { GOLFGUTU, type Ruleset } from "./ruleset.ts";
import { netStrokes, roundNetTotal } from "./scoring.ts";
import { claimsFor } from "./sideprize.ts";
import { countingHoles } from "./truncation.ts";

// MARK: Modellen

/** JA eller NEI. */
export type BetSide = "yes" | "no";
export const BET_SIDES: readonly BetSide[] = ["yes", "no"];

export function oppositeSide(s: BetSide): BetSide {
  return s === "yes" ? "no" : "yes";
}

export type BetConditionKind = "birdie" | "par" | "hole" | "beats" | "drive" | "kp" | "match";
export const BET_CONDITION_KINDS: readonly BetConditionKind[] = ["birdie", "par", "hole", "beats", "drive", "kp", "match"];

/** Gjelder ett hull. Ellers gjelder vilkåret hele runden. */
export function isHoleBet(kind: BetConditionKind): boolean {
  return kind === "birdie" || kind === "par" || kind === "hole";
}

/** Vilkåret appen (og serveren) kan avgjøre selv. */
export interface BetCondition {
  kind: BetConditionKind;
  /** Runden vilkåret gjelder. */
  round: string;
  /** Rundens 0-baserte hull, for hullvilkårene. */
  hole: number | null;
  /** Spilleren. `null` på `birdie` betyr «noen». */
  player: string | null;
  a: string | null;
  b: string | null;
}

export function makeBetCondition(c: Partial<BetCondition> & { kind: BetConditionKind; round: string }): BetCondition {
  return { kind: c.kind, round: c.round, hole: c.hole ?? null, player: c.player ?? null, a: c.a ?? null, b: c.b ?? null };
}

/** `vilkaarSpillere`: spillerne vilkåret handler om. Tom = «noen». */
export function conditionPlayers(c: BetCondition): string[] {
  return [c.player, c.a, c.b].filter((x): x is string => x !== null && x !== "");
}

export interface BetStake {
  id: string | null;
  playerID: string;
  side: BetSide;
  points: number;
}

export type BetStatus = "open" | "resolved" | "void";

export interface Bet {
  id: string | null;
  status: BetStatus;
  resolution: BetSide | null;
  closedAt: string | null;
  condition: BetCondition | null;
  against: string | null;
  creatorID: string | null;
  stakes: BetStake[];
}

export function makeBet(b: Partial<Bet> = {}): Bet {
  return {
    id: b.id ?? null,
    status: b.status ?? "open",
    resolution: b.resolution ?? null,
    closedAt: b.closedAt ?? null,
    condition: b.condition ?? null,
    against: b.against ?? null,
    creatorID: b.creatorID ?? null,
    stakes: b.stakes ?? [],
  };
}

export function betPool(bet: Bet, side: BetSide): number {
  return bet.stakes.filter((s) => s.side === side).reduce((sum, s) => sum + s.points, 0);
}

/** Spillerens innsatser summert, og siden til den første. `null` = ingen. */
export function betPosition(bet: Bet, playerID: string): { side: BetSide; points: number } | null {
  const mine = bet.stakes.filter((s) => s.playerID === playerID);
  if (mine.length === 0) return null;
  return { side: mine[0].side, points: mine.reduce((sum, s) => sum + s.points, 0) };
}

/** `handlerOmMeg`. */
export function betIsAbout(bet: Bet, playerID: string): boolean {
  return bet.against === playerID || (bet.condition !== null && conditionPlayers(bet.condition).includes(playerID));
}

export type BetPhase = "open" | "closed" | "resolvedYes" | "resolvedNo" | "void";
export type BetVerdict = "yes" | "no" | "void";

/** Siden som vant, eller `null` når veddemålet annulleres. */
export function verdictSide(v: BetVerdict): BetSide | null {
  return v === "void" ? null : v;
}

export interface BetUpdate {
  betID: string | null;
  close: boolean;
  verdict: BetVerdict | null;
}

export type BetTemplateKind =
  | "holeDuel" | "par" | "beats" | "podium" | "myBirdie" | "anyBirdie" | "myPar" | "winRound" | "seasonPodium";

export interface BetTemplate {
  kind: BetTemplateKind;
  condition: BetCondition | null;
  side: BetSide;
}

export interface BetTransfer {
  from: string;
  to: string;
  points: number;
}

export interface BetNettingLine {
  counterpart: string;
  points: number;
}

export interface BetNetting {
  gives: BetNettingLine[];
  receives: BetNettingLine[];
  even: string[];
  totalGives: number;
  totalReceives: number;
}

export interface BetTableRow {
  playerID: string;
  name: string;
  net: number;
  atStake: number;
  balance: number | null;
  available: number | null;
  bets: number;
  won: number;
}

export type StakeProblem =
  | { kind: "closed" }
  | { kind: "invalidAmount" }
  | { kind: "overCap"; max: number; already: number }
  | { kind: "otherSide"; side: BetSide }
  | { kind: "insufficient"; available: number };

// MARK: JSON (Swift-motorens form)

function side(v: string | null, path: string): BetSide | null {
  if (v === null) return null;
  if (v !== "yes" && v !== "no") throw new DecodeError(path, `ukjent side ${v}`);
  return v;
}

export function decodeBetCondition(x: unknown, path = "$"): BetCondition {
  const o = obj(x, path);
  const kind = reqString(o, "kind", path);
  if (!(BET_CONDITION_KINDS as readonly string[]).includes(kind)) throw new DecodeError(`${path}.kind`, `ukjent vilkår ${kind}`);
  return {
    kind: kind as BetConditionKind,
    round: reqString(o, "round", path),
    hole: optInt(o, "hole", path),
    player: optString(o, "player", path),
    a: optString(o, "a", path),
    b: optString(o, "b", path),
  };
}

export function decodeBetStake(x: unknown, path = "$"): BetStake {
  const o = obj(x, path);
  return {
    id: optString(o, "id", path),
    playerID: reqString(o, "playerID", path),
    side: side(reqString(o, "side", path), `${path}.side`)!,
    points: reqNumber(o, "points", path),
  };
}

export function decodeBet(x: unknown, path = "$"): Bet {
  const o = obj(x, path);
  const status = optString(o, "status", path) ?? "open";
  if (status !== "open" && status !== "resolved" && status !== "void") throw new DecodeError(`${path}.status`, status);
  const cond = o["condition"];
  return {
    id: optString(o, "id", path),
    status,
    resolution: side(optString(o, "resolution", path), `${path}.resolution`),
    closedAt: optString(o, "closedAt", path),
    condition: cond === null || cond === undefined ? null : decodeBetCondition(cond, `${path}.condition`),
    against: optString(o, "against", path),
    creatorID: optString(o, "creatorID", path),
    stakes: (optArray(o, "stakes", path) ?? []).map((s, i) => decodeBetStake(s, `${path}.stakes[${i}]`)),
  };
}

// MARK: Fordelingen (PointSplit.apportion i Games.swift)

/**
 * Deler `total` enheter etter vekt. Hver andel rundes med `floor(x + 0.5)`, og resten gis eller tas
 * én enhet om gangen etter største vekt, så laveste id. Summen er nøyaktig `total`.
 */
export function apportion(total: number, weights: readonly { id: string; weight: number }[]): Map<string, number> {
  const order = sortedBy(weights.filter((w) => w.weight > 0),
    (a, b) => (a.weight !== b.weight ? a.weight > b.weight : stringLess(a.id, b.id)));
  const sum = order.reduce((s, w) => s + w.weight, 0);
  if (!(sum > 0)) return new Map();
  const units = order.map((w) => jsRound(w.weight * total / sum));
  const rest = roundAwayFromZero(total - units.reduce((s, u) => s + u, 0));
  for (let k = 0; k < Math.abs(rest); k++) units[k % units.length] += rest > 0 ? 1 : -1;
  const out = new Map<string, number>();
  order.forEach((w, i) => out.set(w.id, units[i]));
  return out;
}

// MARK: Låsing

/** `frontForSpiller`: høyeste førte hull pluss én. 0 = ikke begynt. */
export function playerFront(playerID: string, round: Round): number {
  const scores = round.holeScores.get(playerID);
  if (!scores || scores.size === 0) return 0;
  return Math.max(...scores.keys()) + 1;
}

/** `rundenHarStartet`. */
export function roundHasStarted(round: Round): boolean {
  for (const s of round.holeScores.values()) if (s.size > 0) return true;
  return false;
}

/** `frontForVeddemaal`: den av spillerne som har kommet lengst. Tom liste: feltet. */
export function betFront(players: readonly string[], round: Round): number {
  const ids = players.length === 0 ? [...round.holeScores.keys()] : players;
  return ids.reduce((m, id) => Math.max(m, playerFront(id, round)), 0);
}

/** `forsteApneHull`: første hull det går an å vedde på, eller `null`. */
export function firstOpenHole(round: Round | null, players: readonly string[], rules: Ruleset = GOLFGUTU): number | null {
  if (round === null || round.locked) return null;
  const front = betFront(players, round);
  const i = front === 0 ? 0 : front + rules.bets.lockAheadHoles;
  return i < countingHoles(round) ? i : null;
}

/** `markedTarInnsatser`. `round` = `null`: runden finnes ikke, ingen score å lekke fra. */
export function acceptsStakes(bet: Bet, round: Round | null, rules: Ruleset = GOLFGUTU): boolean {
  if (bet.status !== "open" || bet.closedAt !== null) return false;
  const c = bet.condition;
  if (c === null) return true;
  if (round === null || round.id !== c.round) return true;
  if (round.locked) return false;
  if (isHoleBet(c.kind)) {
    const open = firstOpenHole(round, conditionPlayers(c), rules);
    if (open === null || c.hole === null) return false;
    return c.hole >= open;
  }
  return !roundHasStarted(round);
}

/** Statuspillen. */
export function betPhase(bet: Bet, accepts: boolean): BetPhase {
  switch (bet.status) {
    case "resolved":
      return bet.resolution === "yes" ? "resolvedYes" : bet.resolution === "no" ? "resolvedNo" : "void";
    case "void":
      return "void";
    case "open":
      return accepts ? "open" : "closed";
  }
}

// MARK: Utfallet

type Result = { side: BetSide } | "tie" | null;

function result(round: Round, c: BetCondition, roster: readonly Player[], claims: readonly SideClaim[], rules: Ruleset): Result {
  if (round.id !== c.round) return null;
  const course = courseHoles(round);
  const count = numberOfHoles(round);

  // Netto mot par på ett hull. Med ekstern handicap er netto tallet som ble ført.
  const netToPar = (pid: string | null, h: number | null): number | null => {
    if (pid === null || h === null || h < 0 || h >= course.length) return null;
    const gross = round.holeScores.get(pid)?.get(h);
    if (gross === undefined) return null;
    const hole = course[h];
    const hcp = effectiveHandicap(roster.find((p) => p.id === pid) ?? null, round, roster, rules);
    return netStrokes(gross, hcp, hole.strokeIndex, count) - hole.par;
  };

  switch (c.kind) {
    case "birdie":
    case "par": {
      const limit = c.kind === "birdie" ? -1 : 0;
      if (c.player !== null && c.player !== "") {
        const d = netToPar(c.player, c.hole);
        if (d === null) return null;
        return { side: d <= limit ? "yes" : "no" };
      }
      // «Noen»: JA så snart én klarer det, NEI først når alle i runden har ført hullet.
      let allDone = round.holeScores.size > 0;
      for (const pid of round.holeScores.keys()) {
        const d = netToPar(pid, c.hole);
        if (d !== null && d <= limit) return { side: "yes" };
        if (d === null) allDone = false;
      }
      return allDone || round.locked ? { side: "no" } : null;
    }
    case "hole": {
      const ha = netToPar(c.a, c.hole);
      const hb = netToPar(c.b, c.hole);
      if (ha === null || hb === null) return null;
      if (ha === hb) return "tie";
      return { side: ha < hb ? "yes" : "no" };
    }
    case "beats": {
      if (!round.locked) return null;
      const a = roundNetTotal(round, roster.find((p) => p.id === c.a) ?? null, roster, rules);
      const b = roundNetTotal(round, roster.find((p) => p.id === c.b) ?? null, roster, rules);
      if (a === b) return "tie";
      return { side: a > b ? "yes" : "no" };
    }
    case "drive":
    case "kp": {
      if (!round.locked) return null;
      const list = claimsFor(c.kind, round, claims);
      if (list.length === 0) return null;
      return { side: list[0].playerId === c.player ? "yes" : "no" };
    }
    case "match": {
      const p = c.player;
      if (p === null) return null;
      const m = round.matches.find((x) => matchInvolves(x, p, round));
      if (m === undefined) return null;
      const st = matchStanding(m, p, round, roster, rules);
      if (st === null) return null;
      if (!st.decided && !round.locked) return null;
      if (st.up > 0) return { side: "yes" };
      if (st.up < 0) return { side: "no" };
      return "tie";
    }
  }
}

/** `vilkaarUtfall`: utfallet, eller `null` når det ennå ikke er sikkert eller er delt. */
export function betOutcome(round: Round, c: BetCondition, roster: readonly Player[], claims: readonly SideClaim[] = [],
  rules: Ruleset = GOLFGUTU): BetSide | null {
  const r = result(round, c, roster, claims, rules);
  return r !== null && r !== "tie" ? r.side : null;
}

/** Som `betOutcome`, men `void` når utfallet er kjent og delt og regelsettet annullerer slike (`voidTies`). */
export function betVerdict(round: Round, c: BetCondition, roster: readonly Player[], claims: readonly SideClaim[] = [],
  rules: Ruleset = GOLFGUTU): BetVerdict | null {
  const r = result(round, c, roster, claims, rules);
  if (r === null) return null;
  if (r === "tie") return rules.bets.voidTies ? "void" : null;
  return r.side;
}

/** `skalLukkes`. */
export function shouldClose(bet: Bet, round: Round, hole: number): boolean {
  const c = bet.condition;
  if (bet.status !== "open" || bet.closedAt !== null || c === null || c.round !== round.id) return false;
  return isHoleBet(c.kind) ? c.hole === hole : true;
}

/** `oppdaterMarkeder` uten skrivingen. */
export function sweep(bets: readonly Bet[], round: Round, hole: number | null, roster: readonly Player[],
  claims: readonly SideClaim[] = [], rules: Ruleset = GOLFGUTU): BetUpdate[] {
  const out: BetUpdate[] = [];
  for (const bet of bets) {
    const c = bet.condition;
    if (bet.status !== "open" || c === null || c.round !== round.id) continue;
    const stamp = hole !== null ? shouldClose(bet, round, hole) : false;
    const v = betVerdict(round, c, roster, claims, rules);
    const close = stamp || (v !== null && bet.closedAt === null);
    if (!close && v === null) continue;
    out.push({ betID: bet.id, close, verdict: v });
  }
  return out;
}

// MARK: Malene

/** `utfordringMaler`. */
export function betTemplates(round: Round | null, me: string, against: string | null, rules: Ruleset = GOLFGUTU): BetTemplate[] {
  const rid = round?.id ?? null;
  if (against !== null) {
    const him = against;
    const out: BetTemplate[] = [];
    if (rid !== null) {
      const h = firstOpenHole(round, [him, me], rules);
      if (h !== null) out.push({ kind: "holeDuel", condition: makeBetCondition({ kind: "hole", round: rid, hole: h, a: him, b: me }), side: "no" });
    }
    if (rid !== null) {
      const h = firstOpenHole(round, [him], rules);
      if (h !== null) out.push({ kind: "par", condition: makeBetCondition({ kind: "par", round: rid, hole: h, player: him }), side: "no" });
    }
    if (rid === null || !(round !== null && roundHasStarted(round))) {
      out.push({ kind: "beats", condition: rid !== null ? makeBetCondition({ kind: "beats", round: rid, a: him, b: me }) : null, side: "no" });
    }
    out.push({ kind: "podium", condition: null, side: "no" });
    return out;
  }
  const h = rid !== null ? firstOpenHole(round, [me], rules) : null;
  if (rid === null || h === null) {
    return [{ kind: "winRound", condition: null, side: "yes" }, { kind: "seasonPodium", condition: null, side: "yes" }];
  }
  return [
    { kind: "myBirdie", condition: makeBetCondition({ kind: "birdie", round: rid, hole: h, player: me }), side: "yes" },
    { kind: "anyBirdie", condition: makeBetCondition({ kind: "birdie", round: rid, hole: h }), side: "yes" },
    { kind: "myPar", condition: makeBetCondition({ kind: "par", round: rid, hole: h, player: me }), side: "yes" },
  ];
}

// MARK: Oppgjøret

/** Hver spillers resultat i ett avgjort veddemål. Tomt når ingen poeng flytter seg. */
export function betPayouts(bet: Bet, rules: Ruleset = GOLFGUTU): Map<string, number> {
  const res = bet.resolution;
  if (bet.status !== "resolved" || res === null) return new Map();
  const order: string[] = [];
  const sums = new Map<string, { side: BetSide; points: number }>();
  for (const s of bet.stakes) {
    let e = sums.get(s.playerID);
    if (!e) { order.push(s.playerID); e = { side: s.side, points: 0 }; sums.set(s.playerID, e); }
    e.points += s.points;
  }
  const winners = sortedBy(order.filter((p) => sums.get(p)!.side === res), (a, b) => {
    const x = sums.get(a)!.points, y = sums.get(b)!.points;
    return x !== y ? x > y : stringLess(a, b);
  });
  const losers = order.filter((p) => sums.get(p)!.side !== res);
  const win = winners.reduce((s, p) => s + sums.get(p)!.points, 0);
  const lose = losers.reduce((s, p) => s + sums.get(p)!.points, 0);
  if (!(win > 0 && lose > 0)) return new Map();
  const scale = Math.pow(10, Math.max(0, rules.bets.payoutDecimals));
  const units = apportion(lose * scale, winners.map((p) => ({ id: p, weight: sums.get(p)!.points })));
  const out = new Map<string, number>();
  for (const p of winners) out.set(p, (units.get(p) ?? 0) / scale);
  for (const p of losers) out.set(p, -sums.get(p)!.points);
  return out;
}

/** `veddemaalPoster`: taperne gir vinnerne poeng i forhold til innsats. */
export function betTransfers(bet: Bet, rules: Ruleset = GOLFGUTU): BetTransfer[] {
  const res = bet.resolution;
  if (bet.status !== "resolved" || res === null) return [];
  const winners = bet.stakes.filter((s) => s.side === res);
  const losers = bet.stakes.filter((s) => s.side !== res);
  const pot = winners.reduce((s, w) => s + w.points, 0);
  if (pot === 0 || losers.length === 0) return [];
  const scale = Math.pow(10, Math.max(0, rules.bets.payoutDecimals));
  const order: string[] = [];
  const sums = new Map<string, BetTransfer>();
  for (const t of losers) {
    for (const w of winners) {
      if (t.playerID === w.playerID) continue;
      const key = `${t.playerID}>${w.playerID}`;
      let e = sums.get(key);
      if (!e) { order.push(key); e = { from: t.playerID, to: w.playerID, points: 0 }; sums.set(key, e); }
      e.points += t.points * w.points / pot;
    }
  }
  const out: BetTransfer[] = [];
  for (const key of order) {
    const s = sums.get(key)!;
    const points = jsRound(s.points * scale) / scale;
    if (points > 0) out.push({ from: s.from, to: s.to, points });
  }
  return out;
}

/** `marketNetFor`. */
export function betNet(playerID: string, bets: readonly Bet[], rules: Ruleset = GOLFGUTU): number {
  return bets.reduce((s, b) => s + (betPayouts(b, rules).get(playerID) ?? 0), 0);
}

/** Det spilleren har stående i veddemål som ikke er avgjort. */
export function betAtStake(playerID: string, bets: readonly Bet[]): number {
  let sum = 0;
  for (const b of bets) if (b.status === "open") for (const s of b.stakes) if (s.playerID === playerID) sum += s.points;
  return sum;
}

/** Saldoen: startbeholdning + netto. `null` uten bank. */
export function betBalance(playerID: string, bets: readonly Bet[], rules: Ruleset = GOLFGUTU): number | null {
  const start = rules.bets.startingPoints;
  return start === null ? null : start + betNet(playerID, bets, rules);
}

/** Saldo minus det som står i åpne veddemål. `null` uten bank. */
export function betAvailable(playerID: string, bets: readonly Bet[], rules: Ruleset = GOLFGUTU): number | null {
  const b = betBalance(playerID, bets, rules);
  return b === null ? null : b - betAtStake(playerID, bets);
}

/** `skyldOversikt` uten kassa. */
export function betNetting(transfers: readonly BetTransfer[], playerID: string): BetNetting {
  const order: string[] = [];
  const sums = new Map<string, number>();
  for (const t of transfers) {
    let other: string;
    let signed: number;
    if (t.from === playerID) { other = t.to; signed = t.points; }
    else if (t.to === playerID) { other = t.from; signed = -t.points; }
    else continue;
    if (!sums.has(other)) { order.push(other); sums.set(other, 0); }
    sums.set(other, sums.get(other)! + signed);
  }
  let gives: BetNettingLine[] = [];
  let receives: BetNettingLine[] = [];
  const even: string[] = [];
  for (const other of order) {
    const n = round2(sums.get(other)!);
    if (Math.abs(n) < 0.005) even.push(other);
    else if (n > 0) gives.push({ counterpart: other, points: n });
    else receives.push({ counterpart: other, points: -n });
  }
  const sorted = (lines: BetNettingLine[]) => lines
    .map((l, i) => ({ l, i }))
    .sort((x, y) => (x.l.points !== y.l.points ? (x.l.points > y.l.points ? -1 : 1) : x.i - y.i))
    .map((x) => x.l);
  gives = sorted(gives);
  receives = sorted(receives);
  return {
    gives, receives, even,
    totalGives: round2(gives.reduce((s, l) => s + l.points, 0)),
    totalReceives: round2(receives.reduce((s, l) => s + l.points, 0)),
  };
}

/** Poengtabellen for veddemål, sortert på saldo (netto uten bank), så norsk navn. */
export function betTable(players: readonly Player[], bets: readonly Bet[], rules: Ruleset = GOLFGUTU): BetTableRow[] {
  const rows = players.map((p): BetTableRow => {
    const mine = bets.filter((b) => b.stakes.some((s) => s.playerID === p.id));
    const won = mine.filter((b) => b.status === "resolved" && b.resolution !== null && betPosition(b, p.id)?.side === b.resolution);
    return {
      playerID: p.id, name: p.name, net: betNet(p.id, bets, rules), atStake: betAtStake(p.id, bets),
      balance: betBalance(p.id, bets, rules), available: betAvailable(p.id, bets, rules),
      bets: mine.length, won: won.length,
    };
  });
  return sortedBy(rows, (a, b) => {
    const x = a.balance ?? a.net, y = b.balance ?? b.net;
    if (x !== y) return x > y;
    return norwegianLess(a.name, b.name);
  });
}

// MARK: Avgjøringen og innsatsen

/** Kan `playerID` (en arrangør) avgjøre veddemålet for hånd? Bare åpent og uten egen innsats. */
export function canResolveBet(bet: Bet, playerID: string): boolean {
  return bet.status === "open" && betPosition(bet, playerID) === null;
}

/** Sjekken før en innsats sendes. `null` = i orden. */
export function stakeProblem(bet: Bet, playerID: string, s: BetSide, points: number, round: Round | null,
  bets: readonly Bet[], rules: Ruleset = GOLFGUTU): StakeProblem | null {
  if (!acceptsStakes(bet, round, rules)) return { kind: "closed" };
  if (points < 1) return { kind: "invalidAmount" };
  const pos = betPosition(bet, playerID);
  const max = rules.bets.maxStakePerBet;
  if (pos !== null) {
    if (pos.side !== s) return { kind: "otherSide", side: pos.side };
    if (pos.points + points > max) return { kind: "overCap", max, already: pos.points };
  } else if (points > max) {
    return { kind: "overCap", max, already: 0 };
  }
  const free = betAvailable(playerID, bets, rules);
  if (free !== null && points > free) return { kind: "insufficient", available: Math.max(0, free) };
  return null;
}
