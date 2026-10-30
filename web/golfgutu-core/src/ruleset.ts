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
  reqInt,
  reqNumber,
  stringArray,
  type JSONObject,
} from "./decode.ts";
import { DAY_TERMS, type DayTerm } from "./dayterm.ts";
import { ALL_FORMS, FORM_CATALOG, POINTS_GAME_KINDS, type CompetitionForm, type PointsGameKind } from "./forms.ts";
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

/** Hvordan de tellende poengene blir til totalen: summen, eller snittet per spilte kveld som teller. */
export type Aggregation = "sum" | "average";
export const AGGREGATIONS: readonly Aggregation[] = ["sum", "average"];

/** Likhet i tabellen: skillene (Golfgutu), eller playoff om førsteplassen (andre likheter er delt plass). */
export type TieRule = "tiebreaks" | "playoff";
export const TIE_RULES: readonly TieRule[] = ["tiebreaks", "playoff"];

/** En navngitt poengtabell (f.eks. «finale» = 2). Kvelden peker på den med `Round.pointsTable`. */
export interface PointsTable {
  multiplier: number;
}

/** Trekningen av matcher: etter tabellen (Golfgutu), uten gjentakelser, eller manuelt. */
export type DrawMethod = "standings" | "avoidRepeats" | "manual";
export const DRAW_METHODS: readonly DrawMethod[] = ["standings", "avoidRepeats", "manual"];

/** Hva tabellpoengene kommer fra. */
export type TablePointsSource = "matches" | "stableford" | "placement";
export const TABLE_POINTS_SOURCES: readonly TablePointsSource[] = ["matches", "stableford", "placement"];

/** Tabellen teller runder (stableford eller plassering), ikke matcher. */
export function countsRounds(source: TablePointsSource): boolean {
  return source !== "matches";
}

/** Plasseringspoeng når regelsettet ikke har sin egen skala: 25, 20, 16, 13, 11, så 10 ned til 1. */
export const STANDARD_PLACEMENT_POINTS: readonly number[] = Object.freeze([25, 20, 16, 13, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1]);

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
  /** Minste antall spilte kvelder som teller for å få plass. `null` eller 0: alle rangeres. */
  minEvenings: number | null;
  aggregation: Aggregation;
  /** Navngitte poengtabeller. Tom: ingen. */
  pointsTables: Record<string, PointsTable>;
  tieRule: TieRule;
  /** Med `pointsSource` `stableford`: rundens poeng er formens egne (skins, Amerikaner, Københavner). */
  formPoints: boolean;
  /** Med `pointsSource` `placement`: poengene for 1., 2., 3. plass osv. Plasser etter lista gir 0. Tom: standarden. */
  placementPoints: number[];
}

/** Plasseringsskalaen som gjelder: regelsettets egen, ellers `STANDARD_PLACEMENT_POINTS`. */
export function effectivePlacementPoints(t: TableRules): readonly number[] {
  return (t.placementPoints ?? []).length === 0 ? STANDARD_PLACEMENT_POINTS : t.placementPoints;
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

/**
 * WHS-anbefalingen for formene der laget spiller én ball (`TeamHandicapRule.whsRecommended`): WHS «Rules of
 * Handicapping», Appendix C. Vektene lavest først: foursome 50 % av summen, greensome og chapman 60/40,
 * scramble 2 35/15, scramble 4 25/20/15/10.
 */
export const WHS_TEAM_HANDICAP: Readonly<Record<string, TeamHandicapRule>> = deepFreeze({
  "foursome": { method: "weighted", weights: [0.5, 0.5] },
  "greensome": { method: "weighted", weights: [0.6, 0.4] },
  "chapman": { method: "weighted", weights: [0.6, 0.4] },
  "scramble-2": { method: "weighted", weights: [0.35, 0.15] },
  "scramble-4": { method: "weighted", weights: [0.25, 0.2, 0.15, 0.1] },
} as Record<string, TeamHandicapRule>);

/** `HandicapRules.useWHSTeamHandicap()`: formene med én ball får WHS-anbefalingen, resten er som før. */
export function useWHSTeamHandicap(h: HandicapRules): void {
  for (const [k, v] of Object.entries(WHS_TEAM_HANDICAP)) h.teamHandicap[k] = deepCopy(v) as TeamHandicapRule;
}

/** `HandicapRules.usesWHSTeamHandicap`. */
export function usesWHSTeamHandicap(h: HandicapRules): boolean {
  return Object.entries(WHS_TEAM_HANDICAP).every(([k, v]) => deepEqual(h.teamHandicap[k], v));
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
  drawMethod: DrawMethod;
}

/** Spørsmålene en kupong kan ha (`TipsQuestion`). De fem første er PWA-ens. */
export type TipsQuestion =
  | "winner" | "frontNine" | "mostPars" | "birdie" | "over"
  | "birdieCount" | "mostBirdies" | "backNine" | "winnerPoints"
  | "lastPlace" | "lowestGross" | "comeback" | "mostBlanks" | "bestParThrees" | "bestParFives" | "parStreak"
  | "eagle" | "grossBirdie" | "leaderWins" | "sharedWin" | "highHandicapWins"
  | "lastPlacePoints" | "winningMargin" | "blankHoles" | "parOrBetterPlayers"
  | "longestDrive" | "closestToPin" | "longestDriveMeters";

/** Alle spørsmålene i kupongens rekkefølge (`TipsQuestion.catalog`). */
export const TIPS_QUESTIONS: readonly TipsQuestion[] = [
  "winner", "frontNine", "backNine", "mostPars",
  "lastPlace", "lowestGross", "comeback", "mostBlanks", "bestParThrees", "bestParFives", "parStreak",
  "longestDrive", "closestToPin",
  "birdie", "eagle", "grossBirdie", "leaderWins", "sharedWin", "highHandicapWins",
  "birdieCount", "mostBirdies", "over", "winnerPoints",
  "lastPlacePoints", "winningMargin", "blankHoles", "parOrBetterPlayers", "longestDriveMeters",
];

/** Flest spørsmål på én kupong (`TipsQuestion.maxPerCoupon`). */
export const TIPS_MAX_PER_COUPON = 12;

/** Standardlinjene for de morsomme over/under-spørsmålene (`TipsRules.golfgutuLines`). */
export const GOLFGUTU_TIPS_LINES: Readonly<Partial<Record<TipsQuestion, number>>> = {
  lastPlacePoints: 25.5, winningMargin: 2.5, blankHoles: 20.5, parOrBetterPlayers: 2.5, longestDriveMeters: 250.5,
};

/** Linja et over/under-spørsmål har i regelsettet (`TipsRules.line`). `null` for snittet og spørsmål uten linje. */
export function tipsLine(t: TipsRules, q: TipsQuestion): number | null {
  if (q === "birdieCount") return t.birdieCountLine;
  if (q === "winnerPoints") return t.winnerPointsLine;
  return t.lines[q] ?? GOLFGUTU_TIPS_LINES[q] ?? null;
}

/** Endrer linja (`TipsRules.setLine`). Standarden lagres ikke. */
export function setTipsLine(t: TipsRules, q: TipsQuestion, value: number): void {
  if (q === "birdieCount") { t.birdieCountLine = value; return; }
  if (q === "winnerPoints") { t.winnerPointsLine = value; return; }
  const standard = GOLFGUTU_TIPS_LINES[q];
  if (standard === undefined) return;
  if (value === standard) delete t.lines[q]; else t.lines[q] = value;
}

/** Malene (`TipsTemplate`): ferdige utvalg av spørsmål. */
export type TipsTemplate = "classic" | "birdieHunt" | "full" | "fun";

export const TIPS_TEMPLATES: readonly { id: TipsTemplate; title: string; questions: readonly TipsQuestion[] }[] = [
  { id: "classic", title: "Klassisk", questions: ["winner", "frontNine", "mostPars", "birdie", "over"] },
  { id: "birdieHunt", title: "Birdiejakt", questions: ["winner", "birdie", "birdieCount", "mostBirdies", "over"] },
  { id: "full", title: "Full kupong", questions: ["winner", "frontNine", "backNine", "mostPars", "birdie", "birdieCount", "mostBirdies", "over", "winnerPoints"] },
  { id: "fun", title: "Moro-kupong", questions: ["winner", "lastPlace", "comeback", "mostBlanks", "eagle", "grossBirdie", "leaderWins", "winningMargin"] },
];

/** Malen med akkurat disse spørsmålene i denne rekkefølgen, ellers `null` (tilpasset). */
export function matchingTipsTemplate(questions: readonly TipsQuestion[]): TipsTemplate | null {
  const t = TIPS_TEMPLATES.find((t) => t.questions.length === questions.length && t.questions.every((q, i) => q === questions[i]));
  return t ? t.id : null;
}

/** Tippekupongen (bare reglene; tips-logikken er ikke portert). */
export interface TipsRules {
  defaultStartTime: string;
  defaultStakePoints: number;
  stakeOptions: number[];
  defaultLine: number;
  lineStep: number;
  /** Spørsmålene på kupongen, i kupongens rekkefølge. */
  questions: TipsQuestion[];
  /** Linja på antall birdier i feltet. */
  birdieCountLine: number;
  /** Linja på vinnerens stablefordpoeng. */
  winnerPointsLine: number;
  /** De andre linjene der arrangøren har endret dem; ellers `GOLFGUTU_TIPS_LINES`. Bruk `tipsLine`/`setTipsLine`. */
  lines: Partial<Record<TipsQuestion, number>>;
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

// MARK: Formene fra steg 7 (FormPlay.swift)

/** Handicap i et spill (`GameHandicap`). */
export interface GameHandicap {
  net: boolean;
  allowance: number;
  fromLowest: boolean;
}

export type SkinsLeftover = "lapse" | "split";
export const SKINS_LEFTOVERS: readonly SkinsLeftover[] = ["lapse", "split"];

/** Skins (`SkinsRules`). */
export interface SkinsRules {
  handicap: GameHandicap;
  valuePerSkin: number;
  carryOver: boolean;
  leftover: SkinsLeftover;
}

/** Ett poengspill (`PointsGameRules`): poengene per hull etter likhetsmønster («1-2-1»). */
export interface PointsGameRules {
  players: number;
  handicap: GameHandicap;
  points: Record<string, number[]>;
}

/** Regelverdiene for formene fra steg 7 (`FormPlayRules`). */
export interface FormPlayRules {
  pointsGames: Record<string, PointsGameRules>;
  skins: SkinsRules;
  skinPoints: number;
  teamMatch: MatchPoints;
  /** Par/bogey (regel 21.3): verdien av et vunnet, delt og tapt hull. Standard +1 / 0 / −1. */
  parBogey: ParBogeyRules;
  /** Maksimumscore (regel 21.2): taket når konkurransen ikke har sitt eget. Standard netto dobbel bogey. */
  maximumScore: MaxStrokes;
}

/** Taket i maksimumscore når regelsettet ikke sier noe (`FormPlayRules.standardMaximumScore`). */
export const STANDARD_MAXIMUM_SCORE: Readonly<MaxStrokes> = Object.freeze({ type: "netDoubleBogey" });

/** `ParBogeyRules`. */
export interface ParBogeyRules {
  win: number;
  halve: number;
  loss: number;
}

/** Regel 21.3b: vunnet +1, delt 0, tapt −1. */
export const STANDARD_PAR_BOGEY: Readonly<ParBogeyRules> = Object.freeze({ win: 1, halve: 0, loss: -1 });

const FULL_HANDICAP: GameHandicap = { net: true, allowance: 1, fromLowest: false };

/** Skins-malen (`SkinsRules.standard`): netto, fullt handicap, 10 per skin, carry-over, resten faller bort. */
export const STANDARD_SKINS: Readonly<SkinsRules> = deepFreeze({
  handicap: { ...FULL_HANDICAP }, valuePerSkin: 10, carryOver: true, leftover: "lapse",
} as SkinsRules);

/**
 * Poengspillene etter NGF «Spilleformer» (4. oktober 2023): Amerikaner side 3 (12 poeng per hull),
 * Københavner side 4 (6 poeng per hull). Netto med fullt handicap (dokumentet sier ikke noe om handicap).
 */
export const STANDARD_POINTS_GAMES: Readonly<Record<PointsGameKind, PointsGameRules>> = deepFreeze({
  amerikaner: {
    players: 4, handicap: { ...FULL_HANDICAP }, points: {
      "1-1-1-1": [8, 4, 0, 0], "1-1-2": [8, 4, 0, 0], "1-2-1": [8, 2, 2, 0], "1-3": [9, 1, 1, 1],
      "2-1-1": [6, 6, 0, 0], "2-2": [6, 6, 0, 0], "3-1": [4, 4, 4, 0], "4": [3, 3, 3, 3],
    },
  },
  kobenhavner: {
    players: 3, handicap: { ...FULL_HANDICAP }, points: { "1-1-1": [4, 2, 0], "1-2": [4, 1, 1], "2-1": [3, 3, 0], "3": [2, 2, 2] },
  },
});

/** `FormPlayRules.standard`: NGF-poengene, skins som rundespillet med 1 tabellpoeng per skin, lag mot lag 1/½/0. */
export const STANDARD_FORM_PLAY: Readonly<FormPlayRules> = deepFreeze({
  pointsGames: deepCopy(STANDARD_POINTS_GAMES) as Record<string, PointsGameRules>,
  skins: deepCopy(STANDARD_SKINS) as SkinsRules,
  skinPoints: 1,
  teamMatch: { win: 1, draw: 0.5, loss: 0 },
  parBogey: { ...STANDARD_PAR_BOGEY },
  maximumScore: { ...STANDARD_MAXIMUM_SCORE },
} as FormPlayRules);

/** Reglene for poengspillet, med standarden når det mangler. */
export function pointsGameRules(r: Ruleset, kind: PointsGameKind): PointsGameRules {
  return r.formPlay.pointsGames[kind] ?? STANDARD_POINTS_GAMES[kind];
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
  /** Formene fra steg 7. Standard: `STANDARD_FORM_PLAY`, og da skrives gruppen ikke. */
  formPlay: FormPlayRules;
  /** Føring og visning (PlayRules.swift). Standard: `STANDARD_PLAY`, og da skrives gruppen ikke. */
  play: PlayRules;
}

// MARK: Føring og visning (PlayRules.swift)

/** Maks slag per hull: av (Golfgutu), netto dobbel bogey, eller et fast tall. */
export type MaxStrokes = { type: "off" } | { type: "netDoubleBogey" } | { type: "fixed"; strokes: number };

export interface PlayRules {
  maxStrokes: MaxStrokes;
  /** Markøren leverer kortet, og bare arrangøren kan åpne det igjen. */
  lockSubmittedCards: boolean;
  /** Hvor mange av de siste hullene «Skjul de siste hullene» skjuler i en ny runde (1–9). */
  hiddenHoles: number;
  /** Shank (brutto firedobbel bogey eller verre) står i feeden, uten push (sql/073). */
  shankPosts: boolean;
  /** Lagkamerater fører for hverandre i lagformer der hver spiller sin egen ball (sql/074). */
  teammatesScore: boolean;
}

export const MAX_STROKES_FIXED: readonly [number, number] = [3, 20];
export const HIDDEN_HOLES_RANGE: readonly [number, number] = [1, 9];

export const STANDARD_PLAY: Readonly<PlayRules> = deepFreeze({
  maxStrokes: { type: "off" },
  lockSubmittedCards: false,
  hiddenHoles: 3,
  shankPosts: false,
  teammatesScore: true,
} as PlayRules);

/** Det høyeste en spiller kan føre på et hull med `par` og `strokesReceived` slag. `null`: ingen grense. */
export function maxStrokesLimit(m: MaxStrokes, par: number, strokesReceived: number): number | null {
  switch (m.type) {
    case "off": return null;
    case "netDoubleBogey": return par + 2 + Math.max(0, strokesReceived);
    case "fixed": return m.strokes;
  }
}

const MAX_STROKES_TYPES = ["off", "netDoubleBogey", "fixed"] as const;

export function decodeMaxStrokes(x: unknown, path = "$"): MaxStrokes {
  const o = obj(x, path);
  const type = enumValue(o.type, MAX_STROKES_TYPES, `${path}.type`);
  if (type === "fixed") {
    return { type, strokes: reqInt(o, "strokes", path) };
  }
  return { type };
}

export function decodePlay(x: unknown, path = "$"): PlayRules {
  const o = obj(x, path);
  const m = optObject(o, "maxStrokes", path);
  return {
    maxStrokes: m ? decodeMaxStrokes(m, `${path}.maxStrokes`) : { ...STANDARD_PLAY.maxStrokes },
    lockSubmittedCards: optBool(o, "lockSubmittedCards", path) ?? STANDARD_PLAY.lockSubmittedCards,
    hiddenHoles: optInt(o, "hiddenHoles", path) ?? STANDARD_PLAY.hiddenHoles,
    shankPosts: optBool(o, "shankPosts", path) ?? STANDARD_PLAY.shankPosts,
    teammatesScore: optBool(o, "teammatesScore", path) ?? STANDARD_PLAY.teammatesScore,
  };
}

/** Gruppen som JSON, med samme felt som Swift skriver. */
export function encodePlay(p: PlayRules): JSONObject {
  const m = p.maxStrokes;
  return {
    maxStrokes: m.type === "fixed" ? { type: m.type, strokes: m.strokes } : { type: m.type },
    lockSubmittedCards: p.lockSubmittedCards,
    hiddenHoles: p.hiddenHoles,
    shankPosts: p.shankPosts,
    teammatesScore: p.teammatesScore,
  };
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

/** Golfgutu: frist 17:00, 50 poeng (0/20/50/100), linje +2,5, ett slag per trykk, de fem spørsmålene.
 *  Linjene for antall birdier (14,5) og vinnerens poeng (37,5) brukes bare når de spørsmålene er med. */
const GOLFGUTU_TIPS: TipsRules = {
  defaultStartTime: "17:00",
  defaultStakePoints: 50,
  stakeOptions: [0, 20, 50, 100],
  defaultLine: 2.5,
  lineStep: 1,
  questions: ["winner", "frontNine", "mostPars", "birdie", "over"],
  birdieCountLine: 14.5,
  winnerPointsLine: 37.5,
  lines: {},
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
    minEvenings: null,
    aggregation: "sum",
    pointsTables: {},
    tieRule: "tiebreaks",
    formPoints: false,
    placementPoints: [],
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
    drawMethod: "standings",
  },
  tips: GOLFGUTU_TIPS,
  bets: GOLFGUTU_BETS,
  leadCheckpoints: GOLFGUTU_LEAD_CHECKPOINTS,
  competition: null,
  dayTerm: null,
  formPlay: deepCopy(STANDARD_FORM_PLAY),
  play: deepCopy(STANDARD_PLAY),
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
  return FORM_CATALOG.filter((f) => r.formats.allowedFormIDs.includes(f.id));
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
  const pp = optArray(o, "placementPoints", path);
  return {
    pointsSource: optEnum(o, "pointsSource", TABLE_POINTS_SOURCES, path) ?? g.pointsSource,
    matchPoints: mp ? decodeMatchPoints(mp, `${path}.matchPoints`) : { ...g.matchPoints },
    trianglePoints: tp ? numberArray(tp, `${path}.trianglePoints`) : [...g.trianglePoints],
    counting: c ? decodeCounting(c, `${path}.counting`) : { ...g.counting },
    stablefordCounting: sc ? decodeCounting(sc, `${path}.stablefordCounting`) : { ...g.stablefordCounting },
    tiebreaks: tb ? tb.map((t, i) => enumValue(t, TIEBREAKS, `${path}.tiebreaks[${i}]`)) : [...g.tiebreaks],
    // `null` er et valg (ingen avrunding); mangler feltet, gjelder Golfgutu.
    roundingStep: has(o, "roundingStep") ? optNumber(o, "roundingStep", path) : g.roundingStep,
    minEvenings: optInt(o, "minEvenings", path) ?? g.minEvenings,
    aggregation: optEnum(o, "aggregation", AGGREGATIONS, path) ?? g.aggregation,
    pointsTables: decodePointsTables(optObject(o, "pointsTables", path), `${path}.pointsTables`),
    tieRule: optEnum(o, "tieRule", TIE_RULES, path) ?? g.tieRule,
    formPoints: optBool(o, "formPoints", path) ?? g.formPoints,
    placementPoints: pp ? numberArray(pp, `${path}.placementPoints`) : [...g.placementPoints],
  };
}

function decodePointsTables(o: JSONObject | null, path: string): Record<string, PointsTable> {
  const out: Record<string, PointsTable> = {};
  if (o === null) return out;
  for (const [k, v] of Object.entries(o)) out[k] = { multiplier: reqNumber(obj(v, `${path}.${k}`), "multiplier", `${path}.${k}`) };
  return out;
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
    drawMethod: optEnum(o, "drawMethod", DRAW_METHODS, path) ?? g.drawMethod,
  };
}

function decodeGameHandicap(o: JSONObject | null, fallback: GameHandicap, path: string): GameHandicap {
  if (o === null) return { ...fallback };
  return {
    net: optBool(o, "net", path) ?? fallback.net,
    allowance: optNumber(o, "allowance", path) ?? fallback.allowance,
    fromLowest: optBool(o, "fromLowest", path) ?? fallback.fromLowest,
  };
}

/** Skins fra JSON: det som mangler, får malens verdi. */
export function decodeSkinsRules(x: unknown, path = "$"): SkinsRules {
  const o = obj(x, path);
  const s = STANDARD_SKINS;
  return {
    handicap: decodeGameHandicap(optObject(o, "handicap", path), s.handicap, `${path}.handicap`),
    valuePerSkin: optInt(o, "valuePerSkin", path) ?? s.valuePerSkin,
    carryOver: optBool(o, "carryOver", path) ?? s.carryOver,
    leftover: optEnum(o, "leftover", SKINS_LEFTOVERS, path) ?? s.leftover,
  };
}

function decodeFormPlay(x: unknown, path: string): FormPlayRules {
  const o = obj(x, path);
  const s = STANDARD_FORM_PLAY;
  const pointsGames = deepCopy(s.pointsGames) as Record<string, PointsGameRules>;
  const pg = optObject(o, "pointsGames", path);
  if (pg) {
    for (const [k, v] of Object.entries(pg)) {
      const p = `${path}.pointsGames.${k}`;
      const g = obj(v, p);
      const base: PointsGameRules = POINTS_GAME_KINDS.includes(k as PointsGameKind)
        ? STANDARD_POINTS_GAMES[k as PointsGameKind] : { players: 0, handicap: FULL_HANDICAP, points: {} };
      const pts = optObject(g, "points", p);
      let points: Record<string, number[]>;
      if (pts) {
        points = {};
        for (const [pattern, list] of Object.entries(pts)) {
          if (!Array.isArray(list)) throw new DecodeError(`${p}.points.${pattern}`, "ventet en liste");
          points[pattern] = numberArray(list, `${p}.points.${pattern}`);
        }
      } else {
        points = deepCopy(base.points) as Record<string, number[]>;
      }
      pointsGames[k] = {
        players: optInt(g, "players", p) ?? base.players,
        handicap: decodeGameHandicap(optObject(g, "handicap", p), base.handicap, `${p}.handicap`),
        points,
      };
    }
  }
  const sk = optObject(o, "skins", path);
  const tm = optObject(o, "teamMatch", path);
  return {
    pointsGames,
    skins: sk ? decodeSkinsRules(sk, `${path}.skins`) : deepCopy(s.skins) as SkinsRules,
    skinPoints: optNumber(o, "skinPoints", path) ?? s.skinPoints,
    teamMatch: tm ? decodeMatchPoints(tm, `${path}.teamMatch`) : { ...s.teamMatch },
    parBogey: decodeParBogey(optObject(o, "parBogey", path), `${path}.parBogey`),
    maximumScore: o.maximumScore !== undefined && o.maximumScore !== null
      ? decodeMaxStrokes(o.maximumScore, `${path}.maximumScore`) : { ...STANDARD_MAXIMUM_SCORE },
  };
}

function decodeParBogey(o: JSONObject | null, path: string): ParBogeyRules {
  const s = STANDARD_PAR_BOGEY;
  if (!o) return { ...s };
  return {
    win: optNumber(o, "win", path) ?? s.win,
    halve: optNumber(o, "halve", path) ?? s.halve,
    loss: optNumber(o, "loss", path) ?? s.loss,
  };
}

function decodeTips(x: unknown, path: string): TipsRules {
  const o = obj(x, path);
  const g = GOLFGUTU_TIPS;
  const so = optArray(o, "stakeOptions", path);
  const qs = optArray(o, "questions", path);
  return {
    defaultStartTime: optString(o, "defaultStartTime", path) ?? g.defaultStartTime,
    defaultStakePoints: optInt(o, "defaultStakePoints", path) ?? g.defaultStakePoints,
    stakeOptions: so ? numberArray(so, `${path}.stakeOptions`, true) : [...g.stakeOptions],
    defaultLine: optNumber(o, "defaultLine", path) ?? g.defaultLine,
    lineStep: optNumber(o, "lineStep", path) ?? g.lineStep,
    // Et spørsmål vi ikke kjenner (fra en nyere app), hoppes over, som i Swift.
    questions: qs
      ? stringArray(qs, `${path}.questions`).filter((q): q is TipsQuestion => (TIPS_QUESTIONS as readonly string[]).includes(q))
      : [...g.questions],
    birdieCountLine: optNumber(o, "birdieCountLine", path) ?? g.birdieCountLine,
    winnerPointsLine: optNumber(o, "winnerPointsLine", path) ?? g.winnerPointsLine,
    lines: decodeTipsLines(optObject(o, "lines", path), `${path}.lines`),
  };
}

/** Som i Swift: en linje på et spørsmål vi ikke kjenner, eller uten linje, hoppes over. */
function decodeTipsLines(o: JSONObject | null, path: string): Partial<Record<TipsQuestion, number>> {
  const out: Partial<Record<TipsQuestion, number>> = {};
  if (!o) return out;
  for (const k of Object.keys(o)) {
    if (GOLFGUTU_TIPS_LINES[k as TipsQuestion] === undefined) continue;
    const v = optNumber(o, k, path);
    if (v !== null) out[k as TipsQuestion] = v;
  }
  return out;
}

/** `tips` slik Swift skriver det: spørsmålene og de nye linjene bare når de ikke er standard. */
function encodeTips(t: TipsRules): JSONObject {
  const g = GOLFGUTU_TIPS;
  const out: JSONObject = {
    defaultStartTime: t.defaultStartTime,
    defaultStakePoints: t.defaultStakePoints,
    stakeOptions: [...t.stakeOptions],
    defaultLine: t.defaultLine,
    lineStep: t.lineStep,
  };
  if (t.questions.length !== g.questions.length || t.questions.some((q, i) => q !== g.questions[i])) {
    out.questions = [...t.questions];
  }
  if (t.birdieCountLine !== g.birdieCountLine) out.birdieCountLine = t.birdieCountLine;
  if (t.winnerPointsLine !== g.winnerPointsLine) out.winnerPointsLine = t.winnerPointsLine;
  const lines = Object.entries(t.lines).filter(([, v]) => v !== undefined) as [string, number][];
  if (lines.length > 0) out.lines = Object.fromEntries(lines);
  return out;
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
    const fp = optObject(o, "formPlay", path);
    const pl = optObject(o, "play", path);
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
      formPlay: fp ? decodeFormPlay(fp, `${path}.formPlay`) : r.formPlay,
      play: pl ? decodePlay(pl, `${path}.play`) : r.play,
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
  // Tabellreglene fra steg 6 skrives bare når de ikke er standard, av samme grunn.
  if (r.table.minEvenings !== null && r.table.minEvenings !== undefined) table.minEvenings = r.table.minEvenings;
  if (r.table.aggregation !== "sum") table.aggregation = r.table.aggregation;
  const pt = r.table.pointsTables ?? {};
  if (Object.keys(pt).length > 0) {
    const tables: JSONObject = {};
    for (const [k, v] of Object.entries(pt)) tables[k] = { multiplier: v.multiplier };
    table.pointsTables = tables;
  }
  if (r.table.tieRule !== "tiebreaks") table.tieRule = r.table.tieRule;
  if (r.table.formPoints) table.formPoints = true;
  if ((r.table.placementPoints ?? []).length > 0) table.placementPoints = [...r.table.placementPoints];
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
    formats: {
      defaultFormID: r.formats.defaultFormID,
      allowedFormIDs: [...r.formats.allowedFormIDs],
      maxPerBay: r.formats.maxPerBay,
      matchStrokes: r.formats.matchStrokes,
      // Bare når trekningen ikke er etter tabellen.
      ...(r.formats.drawMethod !== "standings" ? { drawMethod: r.formats.drawMethod } : {}),
    },
    tips: encodeTips(r.tips),
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
  // Bare når formreglene ikke er standard.
  if (r.formPlay !== undefined && !deepEqual(r.formPlay, STANDARD_FORM_PLAY)) out.formPlay = encodeFormPlay(r.formPlay);
  // Bare når føringsreglene ikke er standard.
  if (r.play !== undefined && !deepEqual(r.play, STANDARD_PLAY)) out.play = encodePlay(r.play);
  return out;
}

function encodeGameHandicap(h: GameHandicap): JSONObject {
  return { net: h.net, allowance: h.allowance, fromLowest: h.fromLowest };
}

/** Formreglene som JSON, med samme felt som Swift skriver. */
export function encodeFormPlay(f: FormPlayRules): JSONObject {
  const pointsGames: JSONObject = {};
  for (const [k, g] of Object.entries(f.pointsGames)) {
    const points: JSONObject = {};
    for (const [pattern, list] of Object.entries(g.points)) points[pattern] = [...list];
    pointsGames[k] = { players: g.players, handicap: encodeGameHandicap(g.handicap), points };
  }
  return {
    pointsGames,
    skins: {
      handicap: encodeGameHandicap(f.skins.handicap),
      valuePerSkin: f.skins.valuePerSkin,
      carryOver: f.skins.carryOver,
      leftover: f.skins.leftover,
    },
    skinPoints: f.skinPoints,
    teamMatch: { ...f.teamMatch },
    // Skrives bare når den ikke er standard (som Swift).
    ...(deepEqual(f.parBogey, STANDARD_PAR_BOGEY) ? {} : { parBogey: { ...f.parBogey } }),
    ...(deepEqual(f.maximumScore, STANDARD_MAXIMUM_SCORE) ? {} : { maximumScore: { ...f.maximumScore } }),
  };
}
