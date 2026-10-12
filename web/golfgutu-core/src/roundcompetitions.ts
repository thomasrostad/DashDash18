// Flere konkurranser på samme runde, og øyeblikksbildet ved start (RoundCompetitions.swift).

import { courseHoles } from "./course.ts";
import { decodeScoringMethod, decodeTeamForm, playsOneBall, type ScoringMethod, type TeamForm } from "./forms.ts";
import { evaluatePointsGame, evaluateSkins, GameContext, scoredPlayers } from "./formplay.ts";
import { effectiveHandicap } from "./handicap.ts";
import { deepCopy, stringLess } from "./jsmath.ts";
import { makeRound, type HoleScores, type PlayedHole, type Player, type Round } from "./models.ts";
import type { Ruleset } from "./ruleset.ts";

export interface HoleRange {
  first: number;
  last: number;
}

/** Én konkurranse på runden. Samme JSON som Swift (`RoundCompetition`). */
export interface RoundCompetition {
  id: string;
  teamForm: TeamForm;
  scoring: ScoringMethod;
  /** Sider eller grupper. `null`: hver for seg (individuelt), eller alle i én gruppe (skins, poengspill). */
  entrants: string[][] | null;
  holes: HoleRange | null;
  /** Andelen av spillehandicapet. `null`: 1. */
  allowance: number | null;
}

export function decodeRoundCompetition(x: unknown, path = "$"): RoundCompetition {
  const o = x as Record<string, unknown>;
  const holes = o.holes as Record<string, unknown> | undefined;
  return {
    id: String(o.id),
    teamForm: decodeTeamForm(o.teamForm, `${path}.teamForm`),
    scoring: decodeScoringMethod(o.scoring, `${path}.scoring`),
    entrants: Array.isArray(o.entrants) ? (o.entrants as unknown[]).map((e) => (e as unknown[]).map(String)) : null,
    holes: holes ? { first: Number(holes.first), last: Number(holes.last) } : null,
    allowance: typeof o.allowance === "number" ? o.allowance : null,
  };
}

export interface RoundCompetitionRow {
  players: string[];
  score: number;
  holes: number;
  rank: number;
}

export interface RoundCompetitionResult {
  id: string;
  supported: boolean;
  rows: RoundCompetitionRow[];
}

function inRange(h: number, r: HoleRange | null): boolean {
  return r === null || (h >= r.first && h <= Math.max(r.first, r.last));
}

/** Alle konkurransene fra samme runde (se `RoundCompetitions.evaluate`). */
export function evaluateRoundCompetitions(round: Round, roster: readonly Player[], competitions: readonly RoundCompetition[], rules: Ruleset): RoundCompetitionResult[] {
  return competitions.map((c) => evaluateCompetition(c, round, roster, rules));
}

function evaluateCompetition(comp: RoundCompetition, round: Round, roster: readonly Player[], rules: Ruleset): RoundCompetitionResult {
  const unsupported: RoundCompetitionResult = { id: comp.id, supported: false, rows: [] };
  if (playsOneBall(comp.teamForm)) return unsupported;
  const scored = scoredPlayers(round);
  const s = comp.scoring;
  switch (s.type) {
    case "stableford":
    case "strokePlay": {
      const stableford = s.type === "stableford";
      const entrants = comp.entrants ?? scored.map((p) => [p]);
      const ctx = new GameContext(entrants.flat(), round, roster, rules);
      const hcp = ctx.handicaps({ net: s.net, allowance: comp.allowance ?? 1, fromLowest: false });
      const rows: RoundCompetitionRow[] = [];
      for (const team of entrants) {
        let total = 0;
        let holes = 0;
        for (let h = 0; h < ctx.count; h++) {
          if (!inRange(h, comp.holes)) continue;
          const values: number[] = [];
          for (const p of team) {
            const n = ctx.net(p, h, hcp);
            if (n === null) continue;
            values.push(stableford ? Math.max(rules.scoring.minimumPoints, ctx.holes[h].par - n + rules.scoring.netParPoints) : n);
          }
          if (values.length === 0) continue;
          holes += 1;
          if (comp.teamForm.type === "pairs" && comp.teamForm.pairs === "aggregate") total += values.reduce((a, b) => a + b, 0);
          else total += stableford ? Math.max(...values) : Math.min(...values);
        }
        rows.push({ players: [...team], score: total, holes, rank: 0 });
      }
      return ranked(comp.id, rows, stableford, !stableford);
    }
    case "skins": {
      if (comp.teamForm.type !== "individual" || comp.holes !== null) return unsupported;
      const players = comp.entrants?.flat() ?? scored;
      if (players.length === 0) return { id: comp.id, supported: true, rows: [] };
      const game = evaluateSkins(players, round, roster, rules, rules.formPlay.skins);
      const done = game.holes.filter((h) => h.state !== "pending").length;
      return ranked(comp.id, players.map((p) => ({ players: [p], score: game.scores.get(p) ?? 0, holes: done, rank: 0 })), true, false);
    }
    case "pointsGame": {
      if (comp.teamForm.type !== "individual") return unsupported;
      const groups = comp.entrants ?? [scored];
      const rows: RoundCompetitionRow[] = [];
      for (const group of groups) {
        if (group.length === 0) continue;
        const r = evaluatePointsGame(s.game, group, round, roster, rules, comp.holes);
        const done = r.holes.filter((h) => h.state === "scored").length;
        for (const p of group) rows.push({ players: [p], score: r.totals.get(p) ?? 0, holes: done, rank: 0 });
      }
      return ranked(comp.id, rows, true, false);
    }
    default:
      return unsupported;
  }
}

function ranked(id: string, rows: RoundCompetitionRow[], higherIsBetter: boolean, byHoles: boolean): RoundCompetitionResult {
  const better = (a: RoundCompetitionRow, b: RoundCompetitionRow): boolean | null => {
    if (byHoles && a.holes !== b.holes) return a.holes > b.holes;
    if (a.score !== b.score) return higherIsBetter ? a.score > b.score : a.score < b.score;
    return null;
  };
  const key = (r: RoundCompetitionRow) => r.players.join(",");
  const sorted = [...rows].sort((a, b) => {
    const x = better(a, b);
    if (x !== null) return x ? -1 : 1;
    return stringLess(key(a), key(b)) ? -1 : stringLess(key(b), key(a)) ? 1 : 0;
  });
  sorted.forEach((r, i) => {
    r.rank = i > 0 && better(sorted[i - 1], r) === null ? sorted[i - 1].rank : i + 1;
  });
  return { id, supported: true, rows: sorted };
}

// MARK: Øyeblikksbildet ved start

/** Regelsett, hull og spillehandicap frosset da runden startet (`FrozenRound`). */
export interface FrozenRound {
  ruleset: Ruleset;
  holes: PlayedHole[];
  playingHandicaps: Map<string, number>;
  gameType: string | null;
  teams: Map<string, number>;
}

/** Øyeblikksbildet når runden starter. Ren funksjon; lagringen gjør appen. */
export function freezeRound(round: Round, roster: readonly Player[], ruleset: Ruleset): FrozenRound {
  const playingHandicaps = new Map<string, number>();
  for (const p of roster) playingHandicaps.set(p.id, effectiveHandicap(p, round, roster, ruleset));
  return {
    ruleset: deepCopy(ruleset),
    holes: courseHoles(round).map((h) => ({ ...h })),
    playingHandicaps,
    gameType: round.gameType,
    teams: new Map(round.teams),
  };
}

/** Runden bygd fra øyeblikksbildet og scorene. */
export function frozenRoundWithScores(f: FrozenRound, scores: ReadonlyMap<string, HoleScores>, locked = true): Round {
  return makeRound({
    gameType: f.gameType,
    holeCount: f.holes.length,
    holeStart: null,
    course: {
      id: null, name: null, par: null, courseRating: null, slopeRating: null,
      holes: f.holes.map((h) => ({ par: h.par, si: h.cardIndex, meters: h.meters })),
    },
    hcpAllowance: 1,
    teams: new Map(f.teams),
    holeScores: new Map([...scores].map(([k, v]) => [k, new Map(v)])),
    locked,
    playingHandicaps: new Map(f.playingHandicaps),
  });
}

/** Konkurransene fra øyeblikksbildet. */
export function evaluateFrozenCompetitions(f: FrozenRound, scores: ReadonlyMap<string, HoleScores>, competitions: readonly RoundCompetition[], locked = true): RoundCompetitionResult[] {
  return evaluateRoundCompetitions(frozenRoundWithScores(f, scores, locked), [], competitions, f.ruleset);
}
