// Oppsettene arrangøren velger mellom i «Ny turnering» (RulesetTemplate.swift). Hvert oppsett er et
// ferdig regelsett; Golfgutu er ett av dem (`matchSeries`).

import { deepCopy, deepEqual, sortedStrings } from "./jsmath.ts";
import {
  encodeRuleset,
  FUN_TEMPLATE,
  golfgutuRules,
  standardCompetitionRules,
  type LeagueRules,
  type Ruleset,
} from "./ruleset.ts";

export type RulesetTemplate =
  | "stablefordSeries"
  | "strokeSeries"
  | "matchSeries"
  | "cup"
  | "fun"
  | "amerikanerSeries"
  | "kobenhavnerSeries"
  | "skinsSeries"
  | "teamVsTeam";
export const RULESET_TEMPLATES: readonly RulesetTemplate[] = [
  "stablefordSeries",
  "strokeSeries",
  "matchSeries",
  "cup",
  "fun",
  "amerikanerSeries",
  "kobenhavnerSeries",
  "skinsSeries",
  "teamVsTeam",
];

/** Navnet i «Ny turnering». */
export function templateTitle(t: RulesetTemplate): string {
  switch (t) {
    case "stablefordSeries":
      return "Stableford-serie";
    case "strokeSeries":
      return "Slagspill-serie";
    case "matchSeries":
      return "Matchspill-serie";
    case "cup":
      return "Cup";
    case "fun":
      return "Morroturnering";
    case "amerikanerSeries":
      return "Amerikaner";
    case "kobenhavnerSeries":
      return "Københavner";
    case "skinsSeries":
      return "Skins";
    case "teamVsTeam":
      return "Lag mot lag";
  }
}

/** Én kort setning om oppsettet. */
export function templateSummary(t: RulesetTemplate): string {
  switch (t) {
    case "stablefordSeries":
      return "Stableford-poeng hver kveld. De beste kveldene teller.";
    case "strokeSeries":
      return "Slagspill hver kveld. Plassen gir poeng i tabellen, og de beste kveldene teller.";
    case "matchSeries":
      return "Matcher hver kveld gir poeng i tabellen, med sidepremier og seeding.";
    case "cup":
      return "Utslag i matchspill. Den som vinner, går videre.";
    case "fun":
      return "Stableford-poengene teller rett fram, runde for runde.";
    case "amerikanerSeries":
      return "Fire i gruppa deler 12 poeng per hull. Poengene går i tabellen.";
    case "kobenhavnerSeries":
      return "Tre i gruppa deler 6 poeng per hull. Poengene går i tabellen.";
    case "skinsSeries":
      return "Hvert hull er et skin. Skinsene går i tabellen.";
    case "teamVsTeam":
      return "To sider spiller fourball lag mot lag og samler poeng.";
  }
}

/**
 * Stableford-serie: Golfgutu-oppsettet der tabellpoengene er stablefordpoengene, de beste 5 av 7
 * kveldene teller (både i tabellen og stablefordsummen), skille ved likt er stablefordsummen, og det
 * er ingen sidepremier og ingen seeding.
 */
function stablefordSeriesRules(): Ruleset {
  const r = golfgutuRules();
  r.table.pointsSource = "stableford";
  r.table.counting = { unit: "evening", best: 5 };
  r.table.stablefordCounting = { unit: "evening", best: 5 };
  r.table.tiebreaks = ["stableford"];
  r.sidePrizes.longestDrive.enabled = false;
  r.sidePrizes.closestToPin.enabled = false;
  r.handicap.seedingGroups = [];
  r.formats.defaultFormID = "stableford";
  return r;
}

/**
 * Slagspill-serie: stableford-serien der tabellen gir plasseringspoeng (standardskalaen) og standardformen
 * er slagspill netto. Arrangøren kan bytte form (brutto, maksimumscore) og skala.
 */
function strokeSeriesRules(): Ruleset {
  const r = stablefordSeriesRules();
  r.table.pointsSource = "placement";
  r.formats.defaultFormID = "slag-netto";
  for (const form of ["slag-netto", "slag-brutto", "maks-score"]) {
    if (!r.formats.allowedFormIDs.includes(form)) r.formats.allowedFormIDs.push(form);
  }
  return r;
}

/** Amerikaner, Københavner og skins: stableford-serien med formens poeng i tabellen (`table.formPoints`). */
function formPointsRules(form: string): Ruleset {
  const r = stablefordSeriesRules();
  r.table.formPoints = true;
  r.formats.defaultFormID = form;
  if (!r.formats.allowedFormIDs.includes(form)) r.formats.allowedFormIDs.push(form);
  return r;
}

/** Lag mot lag: Golfgutu-oppsettet med fourball som standardform (sidene settes per runde). */
function teamVsTeamRules(): Ruleset {
  const r = golfgutuRules();
  r.formats.defaultFormID = "fourball";
  return r;
}

/** Cup og morroturnering: Golfgutu-oppsettet med konkurransemalene under `competition`. */
function competitionTemplateRules(): Ruleset {
  const r = golfgutuRules();
  r.competition = standardCompetitionRules();
  return r;
}

/** Regelsettet oppsettet gir (en ny kopi hver gang). */
export function templateRules(t: RulesetTemplate): Ruleset {
  switch (t) {
    case "stablefordSeries":
      return stablefordSeriesRules();
    case "strokeSeries":
      return strokeSeriesRules();
    case "matchSeries":
      return golfgutuRules();
    case "cup":
    case "fun":
      return competitionTemplateRules();
    case "amerikanerSeries":
      return formPointsRules("amerikaner");
    case "kobenhavnerSeries":
      return formPointsRules("kobenhavner");
    case "skinsSeries":
      return formPointsRules("skins");
    case "teamVsTeam":
      return teamVsTeamRules();
  }
}

/** Stableford-serien som liga: stableford-poeng uten deltakerpoeng, like mange tellende runder som kvelder. */
export function stablefordSeriesLeagueRules(): LeagueRules {
  const league = deepCopy(FUN_TEMPLATE) as LeagueRules;
  league.bestRounds = stablefordSeriesRules().table.counting.best;
  return league;
}

/** Regelsettet når oppsettet lages som liga. Bare stableford-serien har egne ligaregler. */
export function templateLeagueRules(t: RulesetTemplate): Ruleset {
  const r = templateRules(t);
  if (t !== "stablefordSeries") return r;
  const competition = standardCompetitionRules();
  competition.league = stablefordSeriesLeagueRules();
  r.competition = competition;
  return r;
}

/** Oppsettet regelsettet er helt likt, eller `null` når det er tilpasset. Ordet for dagen teller ikke. */
export function matchingTemplate(rules: Ruleset, among: readonly RulesetTemplate[] = RULESET_TEMPLATES, asLeague = false): RulesetTemplate | null {
  const r = { ...rules, dayTerm: null };
  return among.find((t) => deepEqual(asLeague ? templateLeagueRules(t) : templateRules(t), r)) ?? null;
}

/** Oppsettet som ligger nærmest: færrest felt endret. Likt: det første. `null` bare når `among` er tom. */
export function closestTemplate(rules: Ruleset, among: readonly RulesetTemplate[] = RULESET_TEMPLATES, asLeague = false): RulesetTemplate | null {
  let best: { t: RulesetTemplate; n: number } | null = null;
  for (const t of among) {
    const n = templateDifferences(t, rules, asLeague).length;
    if (best === null || n < best.n) best = { t, n };
  }
  return best?.t ?? null;
}

/** Feltene i `rules` som er endret fra oppsettet. */
export function templateDifferences(t: RulesetTemplate, rules: Ruleset, asLeague = false): string[] {
  return changedFields(rules, asLeague ? templateLeagueRules(t) : templateRules(t));
}

/**
 * Feltene som er forskjellige fra `base`, som stier i JSON-en, sortert. Objekter sammenlignes felt for
 * felt; lister og tall som én verdi. Et felt som bare står i det ene, er endret. Ordet for dagen teller ikke.
 */
export function changedFields(rules: Ruleset, base: Ruleset): string[] {
  const out: string[] = [];
  diff(encodeRuleset(rules), encodeRuleset(base), "", out);
  return sortedStrings(out.filter((p) => p !== "dayTerm"));
}

function isPlainObject(x: unknown): x is Record<string, unknown> {
  return x !== null && typeof x === "object" && !Array.isArray(x);
}

function diff(a: unknown, b: unknown, path: string, out: string[]): void {
  if (isPlainObject(a) && isPlainObject(b)) {
    const keys = new Set([...Object.keys(a), ...Object.keys(b)]);
    for (const k of keys) diff(a[k], b[k], path === "" ? k : `${path}.${k}`, out);
    return;
  }
  // Mangler (undefined) i begge: likt. `null` er en verdi (NSNull), som i Swift.
  if (a === undefined && b === undefined) return;
  if (a !== undefined && b !== undefined && deepEqual(a, b)) return;
  out.push(path);
}

/** Golfgutu-oppsettet er `matchSeries`. */
export const GOLFGUTU_TEMPLATE: RulesetTemplate = "matchSeries";
