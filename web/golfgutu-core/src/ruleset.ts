// Regelsettet som styrer turneringen (Ruleset.swift, og regeldelene av Competitions.swift, Tips.swift
// og Bets.swift). Alle regelverdier regelmotoren bruker, ligger her; faste tall finnes bare i
// Golfgutu-malen (`GOLFGUTU`), som gjengir PWA-en.
//
// JSON: versjon 2 er gruppert (`scoring`, `table`, `sidePrizes`, `handicap`, `formats`). Versjon 1
// (flat, uten `version` eller med `version: 1`) leses fortsatt. Felt som mangler, får Golfgutu-verdien.

import {
  DecodeError,
  enumValue,
  has,
  numberArray,
  obj,
  optArray,
  optBool,
  optEnum,
  optInt,
  optNumber,
  optObject,
  optString,
  reqBool,
  reqNumber,
  stringArray,
  type JSONObject,
} from "./decode.ts";
import { DAY_TERMS, type DayTerm } from "./dayterm.ts";
import { ALL_FORMS, type CompetitionForm } from "./forms.ts";
import { deepCopy, deepEqual, jsRound } from "./jsmath.ts";

// MARK: Typer

/** Stablefordpoeng per hull: `max(minimumPoints, par − netto + netParPoints)`. */
export interface ScoringRules {
  netParPoints: number;
  minimumPoints: number;
}

/** Poeng for utfallet av en duell. */
export interface MatchPoints {
  win: number;
  draw: number;
  loss: number;
}

/** Enheten «beste N» telles i: kvelden, hver match, eller hver runde. */
export type CountingUnit = "evening" | "match" | "round";
export const COUNTING_UNITS: readonly CountingUnit[] = ["evening", "match", "round"];

/** Hva som teller: de beste N av en enhet, eller alle (`best: null`). */
export interface Counting {
  unit: CountingUnit;
  best: number | null;
}

/** Et skille ved poenglikhet i tabellen. */
export type Tiebreak = "holeDifference" | "stableford";
export const TIEBREAKS: readonly Tiebreak[] = ["holeDifference", "stableford"];

/** Hva tabellpoengene kommer fra. */
export type TablePointsSource = "matches" | "stableford";
export const TABLE_POINTS_SOURCES: readonly TablePointsSource[] = ["matches", "stableford"];

/** Tabellen (jakketavla). */
export interface TableRules {
  pointsSource: TablePointsSource;
  matchPoints: MatchPoints;
  /** Poeng i en trekant etter plass (beste først). */
  trianglePoints: number[];
  counting: Counting;
  stablefordCounting: Counting;
  tiebreaks: Tiebreak[];
  /** Poengene rundes til nærmeste multiplum av dette. `null`: ingen avrunding. */
  roundingStep: number | null;
}

export interface SidePrize {
  enabled: boolean;
  points: number;
}

export interface SidePrizeRules {
  longestDrive: SidePrize;
  closestToPin: SidePrize;
  /** Lik lengde deler poenget (1/n hver). */
  splitTies: boolean;
}

/** `drive` → longest drive, `kp` → nærmest pinnen. */
export function sidePrizeFor(rules: SidePrizeRules, kind: "drive" | "kp"): SidePrize {
  return kind === "drive" ? rules.longestDrive : rules.closestToPin;
}

export type TeamHandicapMethod = "average" | "weighted" | "lowest";
export const TEAM_HANDICAP_METHODS: readonly TeamHandicapMethod[] = ["average", "weighted", "lowest"];

/** Hvordan et lag får ett handicap av grunnlagene (sortert, lavest først). */
export interface TeamHandicapRule {
  method: TeamHandicapMethod;
  /** Bare for `weighted`. Utelatt (ikke `null`) i JSON når den mangler. */
  weights?: number[];
}

/** En seedet gruppe med fast turneringshandicap (`SEEDING_GRUPPER`). */
export interface SeedingGroup {
  number: number;
  handicap: number;
  name: string;
}

export interface HandicapRules {
  /** Fast andel for alle former. `null`: andelen per form. */
  allowanceOverride: number | null;
  formAllowances: Record<string, number>;
  seedingGroups: SeedingGroup[];
  externalHandicap: boolean;
  teamHandicap: Record<string, TeamHandicapRule>;
}

export type MatchStrokes = "lowestFromScratch" | "fullHandicap";
export const MATCH_STROKES: readonly MatchStrokes[] = ["lowestFromScratch", "fullHandicap"];

export interface FormatRules {
  defaultFormID: string;
  allowedFormIDs: string[];
  maxPerBay: number;
  matchStrokes: MatchStrokes;
}

/** Tippekupongen (bare reglene; tips-logikken er ikke portert). */
export interface TipsRules {
  defaultStartTime: string;
  defaultStakePoints: number;
  stakeOptions: number[];
  defaultLine: number;
  lineStep: number;
}

/** Veddemål med poeng (bare reglene; veddemål-logikken er ikke portert). */
export interface BetRules {
  lockAheadHoles: number;
  maxStakePerBet: number;
  stakeOptions: number[];
  defaultStake: number;
  startingPoints: number | null;
  payoutDecimals: number;
  voidTies: boolean;
}

// Liga, cup og morroturnering (Competitions.swift).

export type LeagueScoring = "placement" | "stableford";
export const LEAGUE_SCORINGS: readonly LeagueScoring[] = ["placement", "stableford"];
export type LeagueTiebreak = "wins" | "bestRound" | "stableford";
export const LEAGUE_TIEBREAKS: readonly LeagueTiebreak[] = ["wins", "bestRound", "stableford"];

export interface LeagueRules {
  scoring: LeagueScoring;
  /** Poeng for 1., 2., 3. plass … Plasser utover lista gir 0. */
  placementPoints: number[];
  /** Poeng for å ha spilt en tellende runde (i tillegg). */
  participationPoints: number;
  /** De beste N rundene teller. `null`: alle. */
  bestRounds: number | null;
  tiebreaks: LeagueTiebreak[];
}

export type CupSeeding = "random" | "handicap" | "ranking";
export const CUP_SEEDINGS: readonly CupSeeding[] = ["random", "handicap", "ranking"];
export type CupTie = "suddenDeath" | "countback" | "higherSeed" | "lowerHandicap";
export const CUP_TIES: readonly CupTie[] = ["suddenDeath", "countback", "higherSeed", "lowerHandicap"];

export interface CupRules {
  seeding: CupSeeding;
  tie: CupTie;
}

export interface CompetitionRules {
  league: LeagueRules;
  fun: LeagueRules;
  cup: CupRules;
}

/** Regelsettet. */
export interface Ruleset {
  /** Antall kvelder i sesongen. */
  evenings: number;
  scoring: ScoringRules;
  table: TableRules;
  sidePrizes: SidePrizeRules;
  handicap: HandicapRules;
  formats: FormatRules;
  tips: TipsRules;
  bets: BetRules;
  /** Hullene der ledelsen underveis meldes, stigende. */
  leadCheckpoints: number[];
  /** Liga, cup og morroturnering. `null`: malene gjelder. */
  competition: CompetitionRules | null;
  /** Hva en dag heter. `null`: «kveld». Bare ord, ikke en regel. */
  dayTerm: DayTerm | null;
}

/** Versjonen som skrives. */
export const CURRENT_RULESET_VERSION = 2;

// MARK: Malene

function deepFreeze<T>(x: T): T {
  if (x !== null && typeof x === "object") {
    for (const v of Object.values(x as object)) deepFreeze(v);
    Object.freeze(x);
  }
  return x;
}

/** Ligamalen: plasseringspoeng 10, 8, 6, 5, 4, 3, 2, 1 og 1 poeng for å spille, alle runder teller. */
export const LEAGUE_TEMPLATE: Readonly<LeagueRules> = deepFreeze({
  scoring: "placement",
  placementPoints: [10, 8, 6, 5, 4, 3, 2, 1],
  participationPoints: 1,
  bestRounds: null,
  tiebreaks: ["wins", "bestRound", "stableford"],
} as LeagueRules);

/** Morromalen: stablefordpoengene teller rett fram, alle runder, skille på beste runde og seire. */
export const FUN_TEMPLATE: Readonly<LeagueRules> = deepFreeze({
  scoring: "stableford",
  placementPoints: [...LEAGUE_TEMPLATE.placementPoints],
  participationPoints: 0,
  bestRounds: null,
  tiebreaks: ["bestRound", "wins"],
} as LeagueRules);

/** Cupmalen: trekning, og sudden death ved likt. */
export const CUP_TEMPLATE: Readonly<CupRules> = deepFreeze({ seeding: "random", tie: "suddenDeath" } as CupRules);

/** Konkurransemalene samlet (`CompetitionRules.standard`). */
export function standardCompetitionRules(): CompetitionRules {
  return { league: deepCopy(LEAGUE_TEMPLATE) as LeagueRules, fun: deepCopy(FUN_TEMPLATE) as LeagueRules, cup: { ...CUP_TEMPLATE } };
}

/** Golfgutu: ledelsen meldes etter hull 3, 6, 9, 12, 15 og 18 (`LEDELSE_SJEKKPUNKT`). */
const GOLFGUTU_LEAD_CHECKPOINTS = [3, 6, 9, 12, 15, 18];

/** Golfgutu: frist 17:00, 50 poeng (0/20/50/100), linje +2,5, ett slag per trykk. */
const GOLFGUTU_TIPS: TipsRules = {
  defaultStartTime: "17:00",
  defaultStakePoints: 50,
  stakeOptions: [0, 20, 50, 100],
  defaultLine: 2.5,
  lineStep: 1,
};

/** Golfgutu: forsprang 1, tak 200, knappene 50/100/200, 100 valgt, 1000 i bank, hele poeng, annuller likt. */
const GOLFGUTU_BETS: BetRules = {
  lockAheadHoles: 1,
  maxStakePerBet: 200,
  stakeOptions: [50, 100, 200],
  defaultStake: 100,
  startingPoints: 1000,
  payoutDecimals: 0,
  voidTies: true,
};

function golfgutuFormAllowances(): Record<string, number> {
  // app-nytt.js: `(form.hcpAndel !== null && form.kort === 'per spiller') ? form.hcpAndel : 1`.
  const out: Record<string, number> = {};
  for (const f of ALL_FORMS) out[f.id] = (f.card === "per spiller" ? f.allowance : null) ?? 1;
  return out;
}

function golfgutuTeamHandicap(): Record<string, TeamHandicapRule> {
  // `lagHandicap`: toerformer snitt, scramble-4 vektet, ellers laveste · andel.
  const out: Record<string, TeamHandicapRule> = {};
  for (const f of ALL_FORMS) {
    if (f.teamSize === 2) out[f.id] = { method: "average" };
    else if (f.id === "scramble-4") out[f.id] = { method: "weighted", weights: [0.25, 0.2, 0.15, 0.1] };
  }
  return out;
}

/**
 * Golfgutu-oppsettet: verdiene fra db-nytt.js og app-nytt.js. 7 kvelder, alle matcher teller,
 * stablefordsummen teller beste 5 runder, duellpoeng 1/0,5/0, trekant 1/0,5/0, LD og KP 1 poeng delt
 * ved likt, halve poeng, netto par 2 og bunn 0, seeding 0/5/10, andel per form, lagshandicap snitt for
 * toere og 25/20/15/10 i scramble-4, laveste fra scratch i match, 4 per bås og stableford som standard.
 * Frosset; bruk `golfgutuRules()` for en kopi som kan endres.
 */
export const GOLFGUTU: Readonly<Ruleset> = deepFreeze({
  evenings: 7,
  scoring: { netParPoints: 2, minimumPoints: 0 },
  table: {
    pointsSource: "matches",
    matchPoints: { win: 1, draw: 0.5, loss: 0 },
    trianglePoints: [1, 0.5, 0],
    counting: { unit: "match", best: null },
    stablefordCounting: { unit: "round", best: 5 },
    tiebreaks: ["holeDifference", "stableford"],
    roundingStep: 0.5,
  },
  sidePrizes: {
    longestDrive: { enabled: true, points: 1 },
    closestToPin: { enabled: true, points: 1 },
    splitTies: true,
  },
  handicap: {
    allowanceOverride: null,
    formAllowances: golfgutuFormAllowances(),
    seedingGroups: [
      { number: 1, handicap: 0, name: "Gruppe 1" },
      { number: 2, handicap: 5, name: "Gruppe 2" },
      { number: 3, handicap: 10, name: "Gruppe 3" },
    ],
    externalHandicap: false,
    teamHandicap: golfgutuTeamHandicap(),
  },
  formats: {
    defaultFormID: "stableford",
    allowedFormIDs: ALL_FORMS.map((f) => f.id),
    maxPerBay: 4,
    matchStrokes: "lowestFromScratch",
  },
  tips: GOLFGUTU_TIPS,
  bets: GOLFGUTU_BETS,
  leadCheckpoints: GOLFGUTU_LEAD_CHECKPOINTS,
  competition: null,
  dayTerm: null,
} as Ruleset);

/** En kopi av Golfgutu-oppsettet som kan endres. */
export function golfgutuRules(): Ruleset {
  return deepCopy(GOLFGUTU) as Ruleset;
}

/** PWA-ens oppgjør og feiing (paritetstestene mot db-nytt.js for veddemål). */
export const PWA_BET_RULES: Readonly<BetRules> = deepFreeze({
  ...GOLFGUTU_BETS,
  stakeOptions: [...GOLFGUTU_BETS.stakeOptions],
  startingPoints: null,
  payoutDecimals: 2,
  voidTies: false,
});

// MARK: Bruk

/** Er regelsettene like (Swifts `==`)? */
export function rulesetEquals(a: Ruleset, b: Ruleset): boolean {
  return deepEqual(a, b);
}

/** Ordet som gjelder: `dayTerm`, ellers «kveld». */
export function rulesetDay(r: Ruleset): DayTerm {
  return r.dayTerm ?? "evening";
}

/** Lagshandicap-regelen for formen. Mangler formen: `lowest`. */
export function teamHandicapRule(r: Ruleset, formID: string): TeamHandicapRule {
  return r.handicap.teamHandicap[formID] ?? { method: "lowest" };
}

/** Tildelingen en ny runde i denne formen får (`hcp_allowance`). */
export function allowanceFor(r: Ruleset, form: CompetitionForm): number {
  return r.handicap.allowanceOverride ?? r.handicap.formAllowances[form.id] ?? 1;
}

/** De tillatte formene, i katalogens rekkefølge. */
export function allowedForms(r: Ruleset): CompetitionForm[] {
  return ALL_FORMS.filter((f) => r.formats.allowedFormIDs.includes(f.id));
}

/** Avrunding til nærmeste multiplum av `step` (JS `Math.round`). Uten trinn: uendret. */
export function roundToStep(x: number, step: number | null): number {
  if (step === null || !(step > 0)) return x;
  return jsRound(x / step) * step;
}

/** Avrunding av tabellpoeng etter regelsettet. */
export function roundTablePoints(r: Ruleset, x: number): number {
  return roundToStep(x, r.table.roundingStep);
}

/** Reglene for liga, cup og morroturnering, med malene for det som mangler. */
export function competitionRulesOf(r: Ruleset): CompetitionRules {
  return r.competition ?? standardCompetitionRules();
}

// MARK: JSON inn

function decodeCounting(x: unknown, path: string): Counting {
  const o = obj(x, path);
  const unit = optEnum(o, "unit", COUNTING_UNITS, path);
  if (unit === null) throw new DecodeError(`${path}.unit`, "mangler");
  return { unit, best: optInt(o, "best", path) };
}

function decodeMatchPoints(x: unknown, path: string): MatchPoints {
  const o = obj(x, path);
  return { win: reqNumber(o, "win", path), draw: reqNumber(o, "draw", path), loss: reqNumber(o, "loss", path) };
}

function decodeScoring(x: unknown, path: string): ScoringRules {
  const o = obj(x, path);
  const netParPoints = optInt(o, "netParPoints", path);
  const minimumPoints = optInt(o, "minimumPoints", path);
  if (netParPoints === null || minimumPoints === null) throw new DecodeError(path, "mangler felt");
  return { netParPoints, minimumPoints };
}

function decodeSidePrize(x: unknown, path: string): SidePrize {
  const o = obj(x, path);
  return { enabled: reqBool(o, "enabled", path), points: reqNumber(o, "points", path) };
}

function decodeSeedingGroup(x: unknown, path: string): SeedingGroup {
  const o = obj(x, path);
  const number = optInt(o, "number", path);
  const name = optString(o, "name", path);
  if (number === null || name === null) throw new DecodeError(path, "mangler felt");
  return { number, handicap: reqNumber(o, "handicap", path), name };
}

function decodeTeamHandicapRule(x: unknown, path: string): TeamHandicapRule {
  const o = obj(x, path);
  const method = optEnum(o, "method", TEAM_HANDICAP_METHODS, path);
  if (method === null) throw new DecodeError(`${path}.method`, "mangler");
  const weights = optArray(o, "weights", path);
  return weights ? { method, weights: numberArray(weights, `${path}.weights`) } : { method };
}

function numberRecord(o: JSONObject, path: string): Record<string, number> {
  const out: Record<string, number> = {};
  for (const [k, v] of Object.entries(o)) {
    if (typeof v !== "number") throw new DecodeError(`${path}.${k}`, "ventet et tall");
    out[k] = v;
  }
  return out;
}

function decodeTable(x: unknown, path: string): TableRules {
  const o = obj(x, path);
  const g = GOLFGUTU.table;
  const mp = optObject(o, "matchPoints", path);
  const tp = optArray(o, "trianglePoints", path);
  const c = optObject(o, "counting", path);
  const sc = optObject(o, "stablefordCounting", path);
  const tb = optArray(o, "tiebreaks", path);
  return {
    pointsSource: optEnum(o, "pointsSource", TABLE_POINTS_SOURCES, path) ?? g.pointsSource,
    matchPoints: mp ? decodeMatchPoints(mp, `${path}.matchPoints`) : { ...g.matchPoints },
    trianglePoints: tp ? numberArray(tp, `${path}.trianglePoints`) : [...g.trianglePoints],
    counting: c ? decodeCounting(c, `${path}.counting`) : { ...g.counting },
    stablefordCounting: sc ? decodeCounting(sc, `${path}.stablefordCounting`) : { ...g.stablefordCounting },
    tiebreaks: tb ? tb.map((t, i) => enumValue(t, TIEBREAKS, `${path}.tiebreaks[${i}]`)) : [...g.tiebreaks],
    // `null` er et valg (ingen avrunding); mangler feltet, gjelder Golfgutu.
    roundingStep: has(o, "roundingStep") ? optNumber(o, "roundingStep", path) : g.roundingStep,
  };
}

function decodeSidePrizes(x: unknown, path: string): SidePrizeRules {
  const o = obj(x, path);
  const g = GOLFGUTU.sidePrizes;
  const ld = optObject(o, "longestDrive", path);
  const kp = optObject(o, "closestToPin", path);
  return {
    longestDrive: ld ? decodeSidePrize(ld, `${path}.longestDrive`) : { ...g.longestDrive },
    closestToPin: kp ? decodeSidePrize(kp, `${path}.closestToPin`) : { ...g.closestToPin },
    splitTies: optBool(o, "splitTies", path) ?? g.splitTies,
  };
}

function decodeHandicap(x: unknown, path: string): HandicapRules {
  const o = obj(x, path);
  const g = GOLFGUTU.handicap;
  const fa = optObject(o, "formAllowances", path);
  const sg = optArray(o, "seedingGroups", path);
  const th = optObject(o, "teamHandicap", path);
  let teamHandicap: Record<string, TeamHandicapRule>;
  if (th) {
    teamHandicap = {};
    for (const [k, v] of Object.entries(th)) teamHandicap[k] = decodeTeamHandicapRule(v, `${path}.teamHandicap.${k}`);
  } else {
    teamHandicap = deepCopy(g.teamHandicap) as Record<string, TeamHandicapRule>;
  }
  return {
    allowanceOverride: optNumber(o, "allowanceOverride", path),
    formAllowances: fa ? numberRecord(fa, `${path}.formAllowances`) : { ...g.formAllowances },
    seedingGroups: sg ? sg.map((s, i) => decodeSeedingGroup(s, `${path}.seedingGroups[${i}]`)) : deepCopy(g.seedingGroups) as SeedingGroup[],
    externalHandicap: optBool(o, "externalHandicap", path) ?? g.externalHandicap,
    teamHandicap,
  };
}

function decodeFormats(x: unknown, path: string): FormatRules {
  const o = obj(x, path);
  const g = GOLFGUTU.formats;
  const allowed = optArray(o, "allowedFormIDs", path);
  return {
    defaultFormID: optString(o, "defaultFormID", path) ?? g.defaultFormID,
    allowedFormIDs: allowed ? stringArray(allowed, `${path}.allowedFormIDs`) : [...g.allowedFormIDs],
    maxPerBay: optInt(o, "maxPerBay", path) ?? g.maxPerBay,
    matchStrokes: optEnum(o, "matchStrokes", MATCH_STROKES, path) ?? g.matchStrokes,
  };
}

function decodeTips(x: unknown, path: string): TipsRules {
  const o = obj(x, path);
  const g = GOLFGUTU_TIPS;
  const so = optArray(o, "stakeOptions", path);
  return {
    defaultStartTime: optString(o, "defaultStartTime", path) ?? g.defaultStartTime,
    defaultStakePoints: optInt(o, "defaultStakePoints", path) ?? g.defaultStakePoints,
    stakeOptions: so ? numberArray(so, `${path}.stakeOptions`, true) : [...g.stakeOptions],
    defaultLine: optNumber(o, "defaultLine", path) ?? g.defaultLine,
    lineStep: optNumber(o, "lineStep", path) ?? g.lineStep,
  };
}

function decodeBets(x: unknown, path: string): BetRules {
  const o = obj(x, path);
  const g = GOLFGUTU_BETS;
  const so = optArray(o, "stakeOptions", path);
  return {
    lockAheadHoles: optInt(o, "lockAheadHoles", path) ?? g.lockAheadHoles,
    maxStakePerBet: optInt(o, "maxStakePerBet", path) ?? g.maxStakePerBet,
    stakeOptions: so ? numberArray(so, `${path}.stakeOptions`, true) : [...g.stakeOptions],
    defaultStake: optInt(o, "defaultStake", path) ?? g.defaultStake,
    // `null` er et valg (ingen bank); mangler feltet, gjelder Golfgutu.
    startingPoints: has(o, "startingPoints") ? optInt(o, "startingPoints", path) : g.startingPoints,
    payoutDecimals: optInt(o, "payoutDecimals", path) ?? g.payoutDecimals,
    voidTies: optBool(o, "voidTies", path) ?? g.voidTies,
  };
}

/** Ligaregler fra JSON: feltene som mangler, får malens verdi. `bestRounds: null` er et valg (alle teller). */
export function decodeLeagueRules(x: unknown, fallback: Readonly<LeagueRules> = LEAGUE_TEMPLATE, path = "$"): LeagueRules {
  const o = obj(x, path);
  const pp = optArray(o, "placementPoints", path);
  const tb = optArray(o, "tiebreaks", path);
  return {
    scoring: optEnum(o, "scoring", LEAGUE_SCORINGS, path) ?? fallback.scoring,
    placementPoints: pp ? numberArray(pp, `${path}.placementPoints`) : [...fallback.placementPoints],
    participationPoints: optNumber(o, "participationPoints", path) ?? fallback.participationPoints,
    bestRounds: has(o, "bestRounds") ? optInt(o, "bestRounds", path) : fallback.bestRounds,
    tiebreaks: tb ? tb.map((t, i) => enumValue(t, LEAGUE_TIEBREAKS, `${path}.tiebreaks[${i}]`)) : [...fallback.tiebreaks],
  };
}

export function decodeCupRules(x: unknown, path = "$"): CupRules {
  const o = obj(x, path);
  return {
    seeding: optEnum(o, "seeding", CUP_SEEDINGS, path) ?? CUP_TEMPLATE.seeding,
    tie: optEnum(o, "tie", CUP_TIES, path) ?? CUP_TEMPLATE.tie,
  };
}

export function decodeCompetitionRules(x: unknown, path = "$"): CompetitionRules {
  const o = obj(x, path);
  const league = optObject(o, "league", path);
  const fun = optObject(o, "fun", path);
  const cup = optObject(o, "cup", path);
  return {
    league: league ? decodeLeagueRules(league, LEAGUE_TEMPLATE, `${path}.league`) : deepCopy(LEAGUE_TEMPLATE) as LeagueRules,
    fun: fun ? decodeLeagueRules(fun, FUN_TEMPLATE, `${path}.fun`) : deepCopy(FUN_TEMPLATE) as LeagueRules,
    cup: cup ? decodeCupRules(cup, `${path}.cup`) : { ...CUP_TEMPLATE },
  };
}

/** Regelsettet fra JSON (versjon 1 eller 2). Det som mangler, får Golfgutu-verdien. */
export function decodeRuleset(x: unknown, path = "$"): Ruleset {
  const o = obj(x, path);
  const version = optInt(o, "version", path) ?? 1;
  const r = golfgutuRules();
  if (version >= 2) {
    const s = optObject(o, "scoring", path);
    const t = optObject(o, "table", path);
    const sp = optObject(o, "sidePrizes", path);
    const h = optObject(o, "handicap", path);
    const f = optObject(o, "formats", path);
    const ti = optObject(o, "tips", path);
    const b = optObject(o, "bets", path);
    const lc = optArray(o, "leadCheckpoints", path);
    const c = optObject(o, "competition", path);
    const dt = optEnum(o, "dayTerm", DAY_TERMS, path);
    return {
      evenings: optInt(o, "evenings", path) ?? r.evenings,
      scoring: s ? decodeScoring(s, `${path}.scoring`) : r.scoring,
      table: t ? decodeTable(t, `${path}.table`) : r.table,
      sidePrizes: sp ? decodeSidePrizes(sp, `${path}.sidePrizes`) : r.sidePrizes,
      handicap: h ? decodeHandicap(h, `${path}.handicap`) : r.handicap,
      formats: f ? decodeFormats(f, `${path}.formats`) : r.formats,
      tips: ti ? decodeTips(ti, `${path}.tips`) : r.tips,
      bets: b ? decodeBets(b, `${path}.bets`) : r.bets,
      leadCheckpoints: lc ? numberArray(lc, `${path}.leadCheckpoints`, true) : r.leadCheckpoints,
      competition: c ? decodeCompetitionRules(c, `${path}.competition`) : null,
      dayTerm: dt,
    };
  }
  // Versjon 1. `countingEvenings` gjaldt matcher (`TELLENDE_MATCHER`), `stablefordCountingEvenings` runder.
  r.evenings = optInt(o, "evenings", path) ?? r.evenings;
  r.handicap.allowanceOverride = optNumber(o, "allowanceOverride", path);
  const sg = optArray(o, "seedingGroups", path);
  if (sg) r.handicap.seedingGroups = sg.map((s, i) => decodeSeedingGroup(s, `${path}.seedingGroups[${i}]`));
  r.handicap.externalHandicap = optBool(o, "externalHandicap", path) ?? r.handicap.externalHandicap;
  r.formats.defaultFormID = optString(o, "defaultFormID", path) ?? r.formats.defaultFormID;
  r.formats.maxPerBay = optInt(o, "maxPerBay", path) ?? r.formats.maxPerBay;
  r.table.counting = { unit: "match", best: optInt(o, "countingEvenings", path) };
  if (has(o, "stablefordCountingEvenings")) {
    r.table.stablefordCounting = { unit: "round", best: optInt(o, "stablefordCountingEvenings", path) };
  }
  const mp = optObject(o, "matchPoints", path);
  if (mp) r.table.matchPoints = decodeMatchPoints(mp, `${path}.matchPoints`);
  const tp = optArray(o, "trianglePoints", path);
  if (tp) r.table.trianglePoints = numberArray(tp, `${path}.trianglePoints`);
  const tb = optArray(o, "tiebreaks", path);
  if (tb) r.table.tiebreaks = tb.map((t, i) => enumValue(t, TIEBREAKS, `${path}.tiebreaks[${i}]`));
  const sp = optObject(o, "sidePrizes", path);
  if (sp) {
    const prize = decodeSidePrize(sp, `${path}.sidePrizes`);
    r.sidePrizes.longestDrive = { ...prize };
    r.sidePrizes.closestToPin = { ...prize };
  }
  return r;
}

/** Regelsettet fra en JSON-tekst. */
export function parseRuleset(text: string): Ruleset {
  return decodeRuleset(JSON.parse(text));
}

// MARK: JSON ut

export function encodeLeagueRules(l: LeagueRules): JSONObject {
  return {
    scoring: l.scoring,
    placementPoints: [...l.placementPoints],
    participationPoints: l.participationPoints,
    bestRounds: l.bestRounds,
    tiebreaks: [...l.tiebreaks],
  };
}

/** Regelsettet som JSON (versjon 2), med samme felt som Swift-motoren skriver. */
export function encodeRuleset(r: Ruleset): JSONObject {
  const table: JSONObject = {
    matchPoints: { ...r.table.matchPoints },
    trianglePoints: [...r.table.trianglePoints],
    counting: { unit: r.table.counting.unit, best: r.table.counting.best },
    stablefordCounting: { unit: r.table.stablefordCounting.unit, best: r.table.stablefordCounting.best },
    tiebreaks: [...r.table.tiebreaks],
    roundingStep: r.table.roundingStep,
  };
  // Bare når tabellen ikke teller matcher, så Golfgutu-JSON-en og eldre regelsett er som før.
  if (r.table.pointsSource !== "matches") table.pointsSource = r.table.pointsSource;
  const teamHandicap: JSONObject = {};
  for (const [k, v] of Object.entries(r.handicap.teamHandicap)) {
    teamHandicap[k] = v.weights !== undefined ? { method: v.method, weights: [...v.weights] } : { method: v.method };
  }
  const out: JSONObject = {
    version: CURRENT_RULESET_VERSION,
    evenings: r.evenings,
    scoring: { ...r.scoring },
    table,
    sidePrizes: {
      longestDrive: { ...r.sidePrizes.longestDrive },
      closestToPin: { ...r.sidePrizes.closestToPin },
      splitTies: r.sidePrizes.splitTies,
    },
    handicap: {
      allowanceOverride: r.handicap.allowanceOverride,
      formAllowances: { ...r.handicap.formAllowances },
      seedingGroups: r.handicap.seedingGroups.map((g) => ({ number: g.number, handicap: g.handicap, name: g.name })),
      externalHandicap: r.handicap.externalHandicap,
      teamHandicap,
    },
    formats: { ...r.formats, allowedFormIDs: [...r.formats.allowedFormIDs] },
    tips: { ...r.tips, stakeOptions: [...r.tips.stakeOptions] },
    bets: {
      lockAheadHoles: r.bets.lockAheadHoles,
      maxStakePerBet: r.bets.maxStakePerBet,
      stakeOptions: [...r.bets.stakeOptions],
      defaultStake: r.bets.defaultStake,
      startingPoints: r.bets.startingPoints,
      payoutDecimals: r.bets.payoutDecimals,
      voidTies: r.bets.voidTies,
    },
    leadCheckpoints: [...r.leadCheckpoints],
  };
  // Bare når konkurransen har egne regler, og bare når ordet er valgt.
  if (r.competition !== null) {
    out.competition = {
      league: encodeLeagueRules(r.competition.league),
      fun: encodeLeagueRules(r.competition.fun),
      cup: { ...r.competition.cup },
    };
  }
  if (r.dayTerm !== null) out.dayTerm = r.dayTerm;
  return out;
}
