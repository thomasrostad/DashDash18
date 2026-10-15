// Konkurransene på en runde slik de er lagret (sql/048, round_competitions) og øyeblikksbildet ved start
// (rounds.rules_snapshot, holes_snapshot). Felles for web-admin og TV-en: radene → regelmotorens
// RoundCompetition og FrozenRound, og resultatene. Rent, uten nett.

import { DEFAULT_PAR } from "../course.ts";
import { decodeScoringMethod, decodeTeamForm, formAxes, formById, type FormAxes } from "../forms.ts";
import type { HoleScores, PlayedHole, Player, Round } from "../models.ts";
import {
  evaluateFrozenCompetitions, evaluateRoundCompetitions, type FrozenRound, type RoundCompetition, type RoundCompetitionResult,
} from "../roundcompetitions.ts";
import { decodeRuleset, type Ruleset } from "../ruleset.ts";
import { evaluateRyderCup, type RyderCupResult } from "../rydercup.ts";
import type { RoundPlayerRow, UUID } from "./rows.ts";

/** Nøklene `format_version` 1 godtar i `config` (sql/048, `round_competition_problem`). */
export const COMPETITION_CONFIG_KEYS = ["form", "teamForm", "scoring", "entrants", "holes", "allowance"] as const;

/** Én rad i `round_competitions`. `config` er motorens RoundCompetition uten id. */
export interface StoredCompetition {
  id: UUID | null;
  roundID: UUID | null;
  name: string;
  isMain: boolean;
  formatVersion: number;
  config: Record<string, unknown>;
  sortOrder: number;
}

const isObj = (x: unknown): x is Record<string, unknown> => typeof x === "object" && x !== null && !Array.isArray(x);

/** Raden fra databasen (eller fra `previous_round_setup`, uten id). null: ikke et objekt eller uten navn. */
export function decodeStoredCompetition(x: unknown): StoredCompetition | null {
  if (!isObj(x) || typeof x.name !== "string") return null;
  return {
    id: typeof x.id === "string" ? x.id.toLowerCase() : null,
    roundID: typeof x.round_id === "string" ? x.round_id.toLowerCase() : null,
    name: x.name,
    isMain: x.is_main === true,
    formatVersion: typeof x.format_version === "number" ? x.format_version : 1,
    config: isObj(x.config) ? x.config : {},
    sortOrder: typeof x.sort_order === "number" ? x.sort_order : 0,
  };
}

/** Sortert som serveren: `sort_order`, så hovedkonkurransen først. */
export function sortedCompetitions(rows: readonly StoredCompetition[]): StoredCompetition[] {
  return [...rows].sort((a, b) => a.sortOrder - b.sortOrder || Number(b.isMain) - Number(a.isMain));
}

/** Aksene for en konkurranse: `form` (katalogen), ellers `teamForm` og `scoring`. Hovedkonkurransen: rundens form. */
export function competitionAxes(c: StoredCompetition, roundFormat: string): FormAxes | null {
  // Hovedkonkurransen speiler rounds.format (048), så formen der vinner.
  if (c.isMain) return formAxes(formById(roundFormat));
  if (typeof c.config.form === "string") return formAxes(formById(c.config.form));
  try {
    return { teamForm: decodeTeamForm(c.config.teamForm), scoring: decodeScoringMethod(c.config.scoring) };
  } catch {
    return null;
  }
}

/** Regelmotorens konkurranse. null: ukjent versjon eller form. */
export function engineCompetition(c: StoredCompetition, roundFormat: string, key: string): RoundCompetition | null {
  if (c.formatVersion !== 1) return null;
  const axes = competitionAxes(c, roundFormat);
  if (!axes) return null;
  const cfg = c.config;
  const entrants = Array.isArray(cfg.entrants)
    ? (cfg.entrants as unknown[]).filter(Array.isArray).map((e) => (e as unknown[]).map((p) => String(p).toLowerCase()))
    : null;
  const holes = isObj(cfg.holes) && typeof cfg.holes.first === "number" && typeof cfg.holes.last === "number"
    ? { first: cfg.holes.first, last: cfg.holes.last } : null;
  const allowance = !c.isMain && typeof cfg.allowance === "number" ? cfg.allowance : null;
  return { id: key, teamForm: axes.teamForm, scoring: axes.scoring, entrants, holes, allowance };
}

// MARK: Øyeblikksbildet

/** Det som trengs fra `rounds` for øyeblikksbildet (råfeltene fra sql/048). */
export interface SnapshotFields {
  format: string;
  externalHandicap: boolean;
  rulesSnapshot: unknown;
  holesSnapshot: unknown;
  snapshotSource: string | null;
}

export function snapshotFields(raw: Record<string, unknown>): SnapshotFields {
  return {
    format: typeof raw.format === "string" ? raw.format : "stableford",
    externalHandicap: raw.external_handicap === true,
    rulesSnapshot: raw.rules_snapshot ?? null,
    holesSnapshot: raw.holes_snapshot ?? null,
    snapshotSource: typeof raw.snapshot_source === "string" ? raw.snapshot_source : null,
  };
}

/** `holes_snapshot.holes` → motorens hull. Par mangler: `DEFAULT_PAR` som i dag. null: ikke en liste. */
export function snapshotHoles(holesSnapshot: unknown): PlayedHole[] | null {
  if (!isObj(holesSnapshot) || !Array.isArray(holesSnapshot.holes) || holesSnapshot.holes.length === 0) return null;
  return holesSnapshot.holes.map((h, i) => {
    const o = isObj(h) ? h : {};
    const num = (v: unknown) => (typeof v === "number" && Number.isFinite(v) ? v : null);
    return {
      par: num(o.par) ?? DEFAULT_PAR[i % DEFAULT_PAR.length],
      cardIndex: num(o.cardIndex) ?? i + 1,
      meters: num(o.meters),
      strokeIndex: num(o.strokeIndex) ?? i + 1,
    };
  });
}

/**
 * FrozenRound fra lagringen: regelsettet (`rules_snapshot`; mangler det, gjelder `liveRules`), hullene
 * (`holes_snapshot.holes`), det frosne spillehandicapet (`playing_handicap`), formen og lagene. null når runden
 * ikke har noe øyeblikksbilde (kladd, eller 048 er ikke kjørt): da regnes det fra dagens data.
 */
export function frozenFromRows(round: SnapshotFields, players: readonly RoundPlayerRow[], liveRules: Ruleset,
  fallbackHandicap: (member: UUID) => number = () => 0): FrozenRound | null {
  if (round.snapshotSource === null) return null;
  const holes = snapshotHoles(round.holesSnapshot);
  if (!holes) return null;
  let ruleset = liveRules;
  if (isObj(round.rulesSnapshot)) {
    try { ruleset = decodeRuleset(round.rulesSnapshot); } catch { ruleset = liveRules; }
  }
  const playingHandicaps = new Map<string, number>();
  const teams = new Map<string, number>();
  for (const p of players) {
    playingHandicaps.set(p.memberID, round.externalHandicap ? 0 : p.playingHandicap ?? fallbackHandicap(p.memberID));
    if (p.teamNo !== null) teams.set(p.memberID, p.teamNo);
  }
  return { ruleset, holes, playingHandicaps, gameType: round.format, teams };
}

// MARK: Resultatene

export interface CompetitionBoard {
  key: string;
  name: string;
  isMain: boolean;
  /** `false`: motoren regner ikke denne kombinasjonen ennå («Ikke støttet ennå»). */
  supported: boolean;
  /** Poeng (høyest best) eller slag (lavest best). */
  higherIsBetter: boolean;
  /** Par/bogey: summen vises med fortegn («+3», «−2»). */
  signed: boolean;
  rows: RoundCompetitionResult["rows"];
}

/**
 * Hver konkurranse på runden med resultatlista. Uten rader er rundens form den eneste (hovedkonkurransen,
 * slik alle runder var før 048). Med øyeblikksbildet regnes det fra det, ellers fra `live` (dagens data).
 */
export function competitionBoards(p: {
  competitions: readonly StoredCompetition[];
  roundFormat: string;
  frozen: FrozenRound | null;
  live: { round: Round; roster: readonly Player[]; rules: Ruleset };
}): CompetitionBoard[] {
  const stored = p.competitions.length > 0
    ? sortedCompetitions(p.competitions)
    : [{ id: null, roundID: null, name: formById(p.roundFormat).name, isMain: true, formatVersion: 1, config: { form: p.roundFormat }, sortOrder: 0 }];
  const keyed = stored.map((c, i) => ({ c, key: c.id ?? `k${i}`, engine: engineCompetition(c, p.roundFormat, c.id ?? `k${i}`) }));
  const engines = keyed.flatMap((k) => (k.engine ? [k.engine] : []));
  const scores: Map<string, HoleScores> = p.live.round.holeScores;
  const results = p.frozen
    ? evaluateFrozenCompetitions(p.frozen, scores, engines, p.live.round.locked)
    : evaluateRoundCompetitions(p.live.round, p.live.roster, engines, p.live.rules);
  const byKey = new Map(results.map((r) => [r.id, r]));
  return keyed.map(({ c, key, engine }) => {
    const r = byKey.get(key);
    return {
      key, name: c.name, isMain: c.isMain,
      supported: engine !== null && (r?.supported ?? false),
      higherIsBetter: engine ? !(engine.scoring.type === "strokePlay" || engine.scoring.type === "maximumScore") : true,
      signed: engine?.scoring.type === "parBogey",
      rows: r?.rows ?? [],
    };
  });
}

/** Sidene for lag mot lag (`round_players.side`, sql/048): spiller → 1 eller 2. */
export function sidesFromRaw(players: readonly unknown[]): Map<UUID, number> {
  const out = new Map<UUID, number>();
  for (const x of players) {
    if (!isObj(x) || typeof x.member_id !== "string") continue;
    if (x.side === 1 || x.side === 2) out.set(x.member_id.toLowerCase(), x.side);
  }
  return out;
}

/** Lag mot lag i én runde: matchene med poeng til sidene. null uten sider. */
export function teamMatchResult(round: Round, sides: ReadonlyMap<UUID, number>, roster: readonly Player[], rules: Ruleset): RyderCupResult | null {
  if (sides.size === 0) return null;
  return evaluateRyderCup([round], sides, roster, rules);
}

/** Poeng eller slag som tekst: «12» eller «12,5». Med `signed` (par/bogey): «+3», «0», «−2». */
export function competitionScoreText(score: number, signed = false): string {
  const text = Number.isInteger(Math.abs(score)) ? String(Math.abs(score)) : Math.abs(score).toFixed(1).replace(".", ",");
  if (score < 0) return (signed ? "−" : "-") + text;
  return (signed && score > 0 ? "+" : "") + text;
}
