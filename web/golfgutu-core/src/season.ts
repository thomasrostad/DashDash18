// Sesongen: tabellen (jakketavla), stablefordsummen og kveldene (Season.swift, db-nytt.js linje
// 380–775, 1052–1095 og 2307–2342), styrt av regelsettet. Med Golfgutu-oppsettet gir alt samme svar
// som PWA-en. Rundens poeng regnes fra scorene.

import { formTablePoints } from "./formplay.ts";
import { cappingStrokes } from "./play.ts";
import { jsRound, norwegianLess, norwegianString, sortedStrings } from "./jsmath.ts";
import { avoidingRepeats, meetings } from "./draw.ts";
import { matchInvolves, matchSides, matchStanding, outcomeForA, pointsForOutcome } from "./match.ts";
import { copyRound, isTriangle, type Player, type Round, type SideClaim, type SideClaimKind } from "./models.ts";
import { GOLFGUTU, roundTablePoints, sidePrizeFor, type CountingUnit, type Ruleset } from "./ruleset.ts";
import { roundPoints as scoreRoundPoints } from "./scoring.ts";
import { claimsFor, sidePrizeWinners } from "./sideprize.ts";
import { drawMatches as drawSwiss, trianglePoints } from "./triangle.ts";

/** Én match for én spiller, vektet med runden. */
export interface SeasonMatchResult {
  /** Indeksen i `rounds`. */
  roundIndex: number;
  roundID: string | null;
  matchNo: number | null;
  points: number;
  /** Hulldifferansen. 0 for trekant og manuelt resultat. */
  holes: number;
  isTriangle: boolean;
}

export interface MatchSelection {
  counting: SeasonMatchResult[];
  dropped: SeasonMatchResult[];
}

/** Én sidepremie vunnet (helt eller delt), vektet med runden. */
export interface SidePrizeResult {
  roundIndex: number;
  roundID: string | null;
  kind: SideClaimKind;
  shared: boolean;
  points: number;
}

export interface SidePrizeSelection {
  counting: SidePrizeResult[];
  dropped: SidePrizeResult[];
}

/** Én runde i stablefordsummen, vektet. */
export interface RoundScore {
  roundIndex: number;
  roundID: string | null;
  points: number;
}

export interface RoundSelection {
  counting: RoundScore[];
  dropped: RoundScore[];
}

/** Det som teller i tabellen. `rounds` er tom når tabellen teller matcher. */
export interface TableSelection {
  matches: MatchSelection;
  sidePrizes: SidePrizeSelection;
  rounds: RoundSelection;
}

/** `matchSum`. */
export interface MatchSum {
  points: number;
  holes: number;
  matches: number;
}

/** En rad i jakketavla. */
export interface JacketRow {
  player: Player;
  /** Duell (eller stablefordpoeng) + sidepremier, avrundet etter regelsettet. */
  total: number;
  /** Tellende matchpoeng. 0 når tabellen teller stableford. */
  duel: number;
  /** Tellende sidepremier. */
  side: number;
  /** Tellende matcher. */
  matches: number;
  holes: number;
  /** Spilte matcher, også strøkne. Når tabellen teller stableford: spilte runder. */
  played: number;
  /** Stablefordsummen (skilletegn). */
  stableford: number;
  /** Tellende stablefordpoeng i tabellen (vektet, før avrunding) når tabellen teller stableford. */
  roundPoints: number;
  /** Kveldene spilleren har spilt som teller (score eller match i en runde med vekt over 0). */
  evenings: number;
  /** Har spilt nok kvelder til å rangeres (`table.minEvenings`). */
  qualified: boolean;
}

/** En rad i tabellen med plass (`Season.standings`). */
export interface Standing {
  row: JacketRow;
  /** 1, 1, 3 …: delt plass har samme nummer. `null`: ikke kvalifisert, står under de rangerte. */
  place: number | null;
  /** Delt førsteplass med `tieRule` `playoff`, og playoffen er ikke avgjort. */
  playoffPending: boolean;
  /** Vant playoffen om førsteplassen. */
  wonPlayoff: boolean;
}

/** En rad i stablefordtavla (`seasonBoardNytt`). */
export interface StablefordRow {
  player: Player;
  total: number;
  played: number;
  counting: number;
  dropped: number;
}

interface GroupItem {
  key: string;
  round: number;
  points: number;
  holes: number;
}

/** Rundevekten. NaN regnes som 0. */
export function roundWeight(round: Round): number {
  return Number.isNaN(round.weight) ? 0 : round.weight;
}

/** Kvelden runden hører til: datoen, eller «uten dato <id>». */
export function eveningKey(round: Round): string {
  return round.date !== null && round.date !== "" ? round.date : "uten dato " + (round.id ?? "undefined");
}

/** `kveldsDatoer`: kveldene, sortert. To runder samme dato er én kveld; en runde uten dato er sin egen. */
export function eveningDates(rounds: readonly Round[]): string[] {
  return sortedStrings(new Set(rounds.map(eveningKey)));
}

/** `antallKvelder`. */
export function eveningCount(rounds: readonly Round[]): number {
  return eveningDates(rounds).length;
}

/** `matchSum`: poengene avrundet etter regelsettet, hulldifferansen og antall matcher. */
export function matchSum(results: readonly SeasonMatchResult[], rules: Ruleset = GOLFGUTU): MatchSum {
  return {
    points: roundTablePoints(rules, results.reduce((s, r) => s + r.points, 0)),
    holes: results.reduce((s, r) => s + r.holes, 0),
    matches: results.length,
  };
}

/** `fmtPoeng`: avrundet etter regelsettet, desimalkomma. «4», ikke «4,0». */
export function formatPoints(x: number, rules: Ruleset = GOLFGUTU): string {
  return norwegianString(roundTablePoints(rules, Number.isNaN(x) ? 0 : x));
}

/** Nøklene til de N beste gruppene: summen av poengene, så hulldifferansen, så den tidligste runden. */
export function bestGroups(items: readonly GroupItem[], n: number): Set<string> {
  const groups = new Map<string, { round: number; points: number; holes: number }>();
  for (const item of items) {
    const g = groups.get(item.key) ?? { round: item.round, points: 0, holes: 0 };
    g.round = Math.min(g.round, item.round);
    g.points += item.points;
    g.holes += item.holes;
    groups.set(item.key, g);
  }
  const ranked = [...groups].sort(([, x], [, y]) => {
    if (x.points !== y.points) return x.points > y.points ? -1 : 1;
    if (x.holes !== y.holes) return x.holes > y.holes ? -1 : 1;
    return x.round - y.round;
  });
  return new Set(ranked.slice(0, Math.max(0, n)).map(([k]) => k));
}

/** Sortering med fallende poeng, så tidligst (indeksen i lista). Stabil. */
function byPointsThenOrder<T extends { points: number }>(items: readonly T[]): T[] {
  return items
    .map((element, offset) => ({ element, offset }))
    .sort((x, y) => (x.element.points !== y.element.points ? (x.element.points > y.element.points ? -1 : 1) : x.offset - y.offset))
    .map((x) => x.element);
}

/** Sesongen. Lag én per beregning; rundens poeng regnes én gang. */
export class Season {
  /** Troppen. Alle står i tabellen, også de som ikke har spilt. */
  readonly players: readonly Player[];
  /** Sesongens runder, i lagret rekkefølge. */
  readonly rounds: readonly Round[];
  readonly claims: readonly SideClaim[];
  readonly ruleset: Ruleset;
  private readonly pointsByRound: Map<string, number>[];
  /** Rundepoengene i tabellen med `table.formPoints` (og `pointsSource` `stableford`). Tom ellers. */
  private readonly formPointsByRound: Map<string, number>[];

  /**
   * `playingHandicaps`: rundens frosne spillehandicap, runde-id → spiller-id → slag. Legges på rundene
   * (og vinner over det som står der fra før).
   */
  constructor(
    players: readonly Player[],
    rounds: readonly Round[],
    claims: readonly SideClaim[] = [],
    ruleset: Ruleset = GOLFGUTU,
    playingHandicaps: ReadonlyMap<string, ReadonlyMap<string, number>> = new Map(),
  ) {
    this.players = players;
    this.rounds = rounds.map((round) => {
      const frozen = round.id !== null ? playingHandicaps.get(round.id) : undefined;
      let r = round;
      if (frozen !== undefined && frozen.size > 0) {
        r = copyRound(round);
        for (const [k, v] of frozen) r.playingHandicaps.set(k, v);
      }
      // Maks slag per hull (`play.maxStrokes`): scorer over grensen teller som grensen. Av: uendret.
      return cappingStrokes(r, players, ruleset);
    });
    this.claims = claims;
    this.ruleset = ruleset;
    this.pointsByRound = this.rounds.map((r) => scoreRoundPoints(r, players, ruleset));
    this.formPointsByRound = ruleset.table.formPoints && ruleset.table.pointsSource === "stableford"
      ? this.rounds.map((r) => formTablePoints(r, players, ruleset)) : [];
  }

  // MARK: Matcher

  /** `matchResultaterFor`: spillerens matcher, med det som teller og det som er strøket. */
  matchResults(playerID: string): MatchSelection {
    return this.tableSelection(playerID).matches;
  }

  /** Det som teller i tabellen for spilleren, etter `table.counting`. */
  tableSelection(playerID: string): TableSelection {
    if (this.ruleset.table.pointsSource === "stableford") return this.stablefordTableSelection(playerID);
    const chronological = this.matchResultsInOrder(playerID);
    const all = chronological
      .map((element, offset) => ({ element, offset }))
      .sort((x, y) => {
        if (x.element.points !== y.element.points) return x.element.points > y.element.points ? -1 : 1;
        if (x.element.holes !== y.element.holes) return x.element.holes > y.element.holes ? -1 : 1;
        return x.offset - y.offset;
      })
      .map((x) => x.element);
    const side = this.sidePrizeResults(playerID);
    const counting = this.ruleset.table.counting;
    const emptyRounds: RoundSelection = { counting: [], dropped: [] };
    const n = counting.best;
    if (n === null || !(n > 0)) {
      return { matches: { counting: all, dropped: [] }, sidePrizes: { counting: side, dropped: [] }, rounds: emptyRounds };
    }
    if (counting.unit === "match") {
      return {
        matches: { counting: all.slice(0, n), dropped: all.slice(n) },
        sidePrizes: { counting: side, dropped: [] },
        rounds: emptyRounds,
      };
    }
    const unit = counting.unit;
    const items: GroupItem[] = [
      ...chronological.map((m) => ({ key: this.groupKey(m.roundIndex, unit), round: m.roundIndex, points: m.points, holes: m.holes })),
      ...side.map((s) => ({ key: this.groupKey(s.roundIndex, unit), round: s.roundIndex, points: s.points, holes: 0 })),
    ];
    const keep = bestGroups(items, n);
    const inKeep = (i: number) => keep.has(this.groupKey(i, unit));
    return {
      matches: { counting: all.filter((m) => inKeep(m.roundIndex)), dropped: all.filter((m) => !inKeep(m.roundIndex)) },
      sidePrizes: { counting: side.filter((s) => inKeep(s.roundIndex)), dropped: side.filter((s) => !inKeep(s.roundIndex)) },
      rounds: emptyRounds,
    };
  }

  /** Tabellen når den teller stableford: stablefordpoeng per runde (vektet) pluss sidepremiene. */
  private stablefordTableSelection(playerID: string): TableSelection {
    const side = this.sidePrizeResults(playerID);
    const chronological: RoundScore[] = [];
    this.rounds.forEach((round, i) => {
      if (this.effectiveWeight(round) === 0) return;
      const p = this.weightedTableRoundPoints(i, playerID);
      if (p === null) return;
      chronological.push({ roundIndex: i, roundID: round.id, points: p });
    });
    const all = byPointsThenOrder(chronological);
    const none: MatchSelection = { counting: [], dropped: [] };
    const counting = this.ruleset.table.counting;
    const n = counting.best;
    if (n === null || !(n > 0)) {
      return { matches: none, sidePrizes: { counting: side, dropped: [] }, rounds: { counting: all, dropped: [] } };
    }
    const unit: CountingUnit = counting.unit === "evening" ? "evening" : "round";
    const items: GroupItem[] = [
      ...chronological.map((r) => ({ key: this.groupKey(r.roundIndex, unit), round: r.roundIndex, points: r.points, holes: 0 })),
      ...side.map((s) => ({ key: this.groupKey(s.roundIndex, unit), round: s.roundIndex, points: s.points, holes: 0 })),
    ];
    const keep = bestGroups(items, n);
    const inKeep = (i: number) => keep.has(this.groupKey(i, unit));
    return {
      matches: none,
      sidePrizes: { counting: side.filter((s) => inKeep(s.roundIndex)), dropped: side.filter((s) => !inKeep(s.roundIndex)) },
      rounds: { counting: all.filter((r) => inKeep(r.roundIndex)), dropped: all.filter((r) => !inKeep(r.roundIndex)) },
    };
  }

  /** Matchene i rundenes rekkefølge, før sortering og utvalg. */
  private matchResultsInOrder(playerID: string): SeasonMatchResult[] {
    const all: SeasonMatchResult[] = [];
    const rules = this.ruleset;
    this.rounds.forEach((round, i) => {
      const weight = this.effectiveWeight(round);
      if (weight === 0) return;
      for (const m of round.matches) {
        if (!matchInvolves(m, playerID, round)) continue;
        if (isTriangle(m)) {
          const tp = trianglePoints(m, round, this.players, rules)?.get(playerID);
          if (tp === undefined) continue;
          all.push({ roundIndex: i, roundID: round.id, matchNo: m.matchNo, points: tp * weight, holes: 0, isTriangle: true });
          continue;
        }
        const toA = outcomeForA(m, round, this.players, rules);
        if (toA === null) continue;
        const onA = matchSides(m, round).a.includes(playerID);
        const mine = onA ? toA : 1 - toA;
        const st = m.result === null ? matchStanding(m, playerID, round, this.players, rules) : null;
        const holes = st !== null && st.played > 0 ? st.up : 0;
        all.push({
          roundIndex: i,
          roundID: round.id,
          matchNo: m.matchNo,
          points: pointsForOutcome(mine, rules.table.matchPoints) * weight,
          holes,
          isTriangle: false,
        });
      }
    });
    return all;
  }

  /** Nøkkelen en runde telles under: kvelden eller runden selv. */
  groupKey(roundIndex: number, unit: CountingUnit): string {
    return unit === "evening" ? eveningKey(this.rounds[roundIndex]) : `runde ${roundIndex}`;
  }

  /**
   * Vekten runden teller med: 0 når kvelden ikke teller (`counts`), ellers rundevekten ganget med
   * poengtabellen den peker på (`table.pointsTables`; ukjent eller ingen: 1).
   */
  effectiveWeight(round: Round): number {
    if (round.counts === false) return 0;
    const name = round.pointsTable ?? null;
    const tables = this.ruleset.table.pointsTables ?? {};
    return roundWeight(round) * (name !== null && Object.hasOwn(tables, name) ? tables[name].multiplier : 1);
  }

  /** `matchPoengFor` / `matchHullFor`: summen av de tellende matchene. */
  matchTotals(playerID: string): MatchSum {
    return matchSum(this.matchResults(playerID).counting, this.ruleset);
  }

  // MARK: Sidepremier

  /** `sidepremieResultaterFor`: premiene spilleren har vunnet, vektet med runden. */
  sidePrizeResults(playerID: string): SidePrizeResult[] {
    const out: SidePrizeResult[] = [];
    const prizes = this.ruleset.sidePrizes;
    this.rounds.forEach((round, i) => {
      const weight = this.effectiveWeight(round);
      if (weight === 0) return;
      for (const kind of ["drive", "kp"] as const) {
        const prize = sidePrizeFor(prizes, kind);
        if (!prize.enabled) continue;
        const winners = sidePrizeWinners(claimsFor(kind, round, this.claims));
        if (!winners.includes(playerID)) continue;
        const share = prizes.splitTies ? winners.length : 1;
        out.push({ roundIndex: i, roundID: round.id, kind, shared: winners.length > 1, points: (prize.points / share) * weight });
      }
    });
    return out;
  }

  /** `sidepremiePoengFor`. */
  sidePrizePoints(playerID: string): number {
    return this.sidePrizeResults(playerID).reduce((s, r) => s + r.points, 0);
  }

  // MARK: Stablefordsummen

  /** Rundens poeng (`round_points`), regnet fra scorene. */
  roundPoints(roundIndex: number): Map<string, number> {
    return this.pointsByRound[roundIndex];
  }

  /** Rundens poeng i tabellen ganget med vekten: formens poeng med `table.formPoints`, ellers stablefordpoengene. */
  weightedTableRoundPoints(roundIndex: number, playerID: string): number | null {
    if (this.formPointsByRound.length === 0) return this.weightedRoundPoints(roundIndex, playerID);
    const p = this.formPointsByRound[roundIndex].get(playerID);
    if (p === undefined) return null;
    return p * this.effectiveWeight(this.rounds[roundIndex]);
  }

  /** `rundePoengVektet`: rundens poeng ganget med vekten. `null` når spilleren ikke har poeng i runden. */
  weightedRoundPoints(roundIndex: number, playerID: string): number | null {
    const p = this.pointsByRound[roundIndex].get(playerID);
    if (p === undefined) return null;
    return p * this.effectiveWeight(this.rounds[roundIndex]);
  }

  /** `tellendeRunderFor`: rundene som teller i stablefordsummen, best først, etter `table.stablefordCounting`. */
  countingRounds(playerID: string): RoundSelection {
    const chronological: RoundScore[] = [];
    this.rounds.forEach((round, i) => {
      const p = this.weightedRoundPoints(i, playerID);
      if (p !== null) chronological.push({ roundIndex: i, roundID: round.id, points: p });
    });
    const all = byPointsThenOrder(chronological);
    const counting = this.ruleset.table.stablefordCounting;
    const n = counting.best;
    if (n === null) return { counting: all, dropped: [] };
    if (counting.unit !== "evening") return { counting: all.slice(0, Math.max(0, n)), dropped: all.slice(Math.max(0, n)) };
    const keep = bestGroups(
      chronological.map((r) => ({ key: this.groupKey(r.roundIndex, "evening"), round: r.roundIndex, points: r.points, holes: 0 })),
      n,
    );
    const inKeep = (r: RoundScore) => keep.has(this.groupKey(r.roundIndex, "evening"));
    return { counting: all.filter(inKeep), dropped: all.filter((r) => !inKeep(r)) };
  }

  /** `seasonTotalNytt`: summen av de tellende rundene, avrundet som JS. */
  stablefordTotal(playerID: string): number {
    return jsRound(this.countingRounds(playerID).counting.reduce((s, r) => s + r.points, 0));
  }

  // MARK: Tabellene

  /**
   * `jakketavle`: duellpoeng (eller stablefordpoeng) pluss sidepremier, alle i troppen. Sortert på
   * total, så regelsettets skilletegn, så navn (norsk).
   */
  jacketBoard(): JacketRow[] {
    const rules = this.ruleset;
    const table = rules.table;
    const minEvenings = table.minEvenings ?? 0;
    const rows = this.players.map((p): JacketRow => {
      const selection = this.tableSelection(p.id);
      const d = selection.matches;
      const s = matchSum(d.counting, rules);
      const side = selection.sidePrizes.counting.reduce((sum, r) => sum + r.points, 0);
      const played = this.playedEvenings(p.id);
      let row: JacketRow;
      if (table.pointsSource === "stableford") {
        const r = selection.rounds;
        const points = r.counting.reduce((sum, x) => sum + x.points, 0);
        row = {
          player: p,
          total: roundTablePoints(rules, points + side),
          duel: 0,
          side,
          matches: 0,
          holes: 0,
          played: r.counting.length + r.dropped.length,
          stableford: this.stablefordTotal(p.id),
          roundPoints: points,
          evenings: 0,
          qualified: true,
        };
      } else {
        row = {
          player: p,
          total: roundTablePoints(rules, s.points + side),
          duel: s.points,
          side,
          matches: s.matches,
          holes: s.holes,
          played: d.counting.length + d.dropped.length,
          stableford: this.stablefordTotal(p.id),
          roundPoints: 0,
          evenings: 0,
          qualified: true,
        };
      }
      row.evenings = played.size;
      row.qualified = minEvenings <= 0 || played.size >= minEvenings;
      if ((table.aggregation ?? "sum") === "average") {
        // Snitt per spilte kveld som teller: kvelder der alt ble strøket av «beste N», regnes ikke.
        const counted = [...selection.matches.counting, ...selection.rounds.counting, ...selection.sidePrizes.counting];
        const dropped = [...selection.matches.dropped, ...selection.rounds.dropped, ...selection.sidePrizes.dropped];
        const countedKeys = new Set(counted.map((x) => eveningKey(this.rounds[x.roundIndex])));
        const droppedKeys = new Set(dropped.map((x) => eveningKey(this.rounds[x.roundIndex])).filter((k) => !countedKeys.has(k)));
        const divisor = [...played].filter((k) => !droppedKeys.has(k)).length;
        const raw = d.counting.reduce((sum, x) => sum + x.points, 0) + selection.rounds.counting.reduce((sum, x) => sum + x.points, 0) + side;
        row.total = divisor > 0 ? roundTablePoints(rules, raw / divisor) : 0;
      }
      return row;
    });
    const less = (a: JacketRow, b: JacketRow): boolean => {
      if (a.qualified !== b.qualified) return a.qualified;
      if (a.total !== b.total) return a.total > b.total;
      if ((table.tieRule ?? "tiebreaks") === "tiebreaks") {
        for (const t of table.tiebreaks) {
          if (t === "holeDifference" && a.holes !== b.holes) return a.holes > b.holes;
          if (t === "stableford" && a.stableford !== b.stableford) return a.stableford > b.stableford;
        }
      }
      return norwegianLess(a.player.name, b.player.name);
    };
    return rows.sort((a, b) => (less(a, b) ? -1 : less(b, a) ? 1 : 0));
  }

  /** Kveldene (nøklene) spilleren har spilt som teller: runder med vekt over 0 med poeng eller en match. */
  playedEvenings(playerID: string): Set<string> {
    const out = new Set<string>();
    this.rounds.forEach((round, i) => {
      if (this.effectiveWeight(round) === 0) return;
      if (this.pointsByRound[i].has(playerID) || round.matches.some((m) => matchInvolves(m, playerID, round))) out.add(eveningKey(round));
    });
    return out;
  }

  /**
   * Tabellen med plass: delt plass ved likhet (på total, og på alle skillene med `tieRule` `tiebreaks`),
   * ingen plass for dem som ikke er kvalifisert, og playoff om delt førsteplass med `tieRule` `playoff`.
   */
  standings(playoffWinner: string | null = null): Standing[] {
    const table = this.ruleset.table;
    const playoff = (table.tieRule ?? "tiebreaks") === "playoff";
    const rows = this.jacketBoard();
    const same = (a: JacketRow, b: JacketRow): boolean => {
      if (a.total !== b.total) return false;
      if (playoff) return true;
      return table.tiebreaks.every((t) => (t === "holeDifference" ? a.holes === b.holes : a.stableford === b.stableford));
    };
    let pending = false;
    let winner: string | null = null;
    const ranked: JacketRow[] = [];
    for (const r of rows) {
      if (!r.qualified) break;
      ranked.push(r);
    }
    if (playoff && ranked.length >= 2 && same(ranked[0], ranked[1]) && ranked[0].evenings > 0) {
      let n = 0;
      while (n < ranked.length && same(ranked[n], ranked[0])) n++;
      const i = playoffWinner === null ? -1 : ranked.slice(0, n).findIndex((r) => r.player.id === playoffWinner);
      if (i >= 0) {
        const [w] = rows.splice(i, 1);
        rows.unshift(w);
        winner = playoffWinner;
      } else {
        pending = true;
      }
    }
    const out: Standing[] = [];
    rows.forEach((row, i) => {
      if (!row.qualified) {
        out.push({ row, place: null, playoffPending: false, wonPlayoff: false });
        return;
      }
      const prev = i > 0 ? rows[i - 1] : null;
      const shares = prev !== null && same(row, prev) && prev.player.id !== winner;
      const place = shares ? out[i - 1].place : i + 1;
      out.push({ row, place, playoffPending: pending && place === 1, wonPlayoff: row.player.id === winner });
    });
    return out;
  }

  /** `seasonBoardNytt`: stablefordsummen, alle i troppen. Sortert på sum, så navn (norsk). */
  stablefordBoard(): StablefordRow[] {
    const rows = this.players.map((p): StablefordRow => {
      const d = this.countingRounds(p.id);
      return {
        player: p,
        total: this.stablefordTotal(p.id),
        played: d.counting.length + d.dropped.length,
        counting: d.counting.length,
        dropped: d.dropped.length,
      };
    });
    const less = (a: StablefordRow, b: StablefordRow) => (a.total !== b.total ? a.total > b.total : norwegianLess(a.player.name, b.player.name));
    return rows.sort((a, b) => (less(a, b) ? -1 : less(b, a) ? 1 : 0));
  }

  /**
   * Trekningen etter regelsettets `formats.drawMethod`: etter tabellen, uten gjentakelser (møtene fra
   * rundene i sesongen, gjentakbar med `seed`), eller `null` for manuell.
   */
  draw(participants: readonly Player[], round: number, seed: bigint | number): string[][] | null {
    switch (this.ruleset.formats.drawMethod ?? "standings") {
      case "standings":
        return this.drawMatches(participants, round);
      case "avoidRepeats":
        return avoidingRepeats(participants, meetings(this.rounds), seed);
      case "manual":
        return null;
    }
  }

  /** `trekkMatcher` med stillingen fra tabellen (`matchPoengFor`). */
  drawMatches(participants: readonly Player[], round: number): string[][] {
    const standing = new Map<string, number>();
    for (const p of participants) standing.set(p.id, this.matchTotals(p.id).points);
    return drawSwiss(participants, round, standing);
  }

  // MARK: Kvelder

  /** `rundeNummerFor`: kveldens nummer for en dato. En ny dato får plassen sin; uten dato: neste ledige. */
  roundNumber(date: string | null): number {
    const dates = eveningDates(this.rounds);
    if (date === null || date === "") return dates.length + 1;
    if (!dates.includes(date)) {
      dates.push(date);
      dates.sort((a, b) => (a < b ? -1 : a > b ? 1 : 0));
    }
    const i = dates.indexOf(date);
    return (i >= 0 ? i : dates.length) + 1;
  }

  /** `kveldErFerdig`: kvelden har runder, og alle er låst. */
  isEveningFinished(date: string): boolean {
    const evening = this.rounds.filter((r) => r.date === date);
    return evening.length > 0 && evening.every((r) => r.locked);
  }
}
