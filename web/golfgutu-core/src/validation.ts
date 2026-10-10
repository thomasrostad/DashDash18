// Gyldighetssjekk av regelsettet før det lagres (RulesetValidation.swift, og
// `CompetitionRules.validate` i Competitions.swift). Grensene for tips og veddemål er databasens.

import { ALL_FORMS } from "./forms.ts";
import type { CompetitionRules, Counting, LeagueRules, Ruleset } from "./ruleset.ts";

/** Et problem i et regelsett, med feltet det gjelder og en norsk melding til arrangøren. */
export interface RulesetIssue {
  /** Stien til feltet i JSON-en, f.eks. `table.counting.best`. */
  field: string;
  message: string;
}

/** Grensene databasen setter (ikke regelverdier). */
const TIPS_STAKE_LIMITS = [0, 1000] as const;
const TIPS_LINE_LIMITS = [-9.5, 18.5] as const;
const BET_STAKE_LIMITS = [1, 10_000] as const;
const BET_BANK_LIMIT = 1_000_000;
const BET_PAYOUT_DECIMALS = [0, 2] as const;

function inRange(x: number, r: readonly [number, number]): boolean {
  return x >= r[0] && x <= r[1];
}

/** `tipsStarttid`: første `H:MM` eller `H.MM` i teksten som `HH:MM`, ellers `fallback`. */
export function tipsStartTime(text: string | null, fallback: string): string {
  const m = /([0-9]{1,2})[:.]([0-9]{2})/.exec(text ?? "");
  if (m) {
    const t = Number(m[1]);
    const mi = Number(m[2]);
    if (t >= 0 && t <= 23 && mi >= 0 && mi <= 59) return (t < 10 ? "0" : "") + String(t) + ":" + m[2];
  }
  return fallback;
}

/** Linja på over/under: et halvt slag innenfor grensene. */
export function isValidTipsLine(x: number): boolean {
  return inRange(x, TIPS_LINE_LIMITS) && x - Math.floor(x) === 0.5;
}

function isFiniteNumber(x: number): boolean {
  return Number.isFinite(x);
}

/** Gyldighetssjekk før regelsettet lagres. Tom liste: alt er i orden. */
export function validateRuleset(r: Ruleset): RulesetIssue[] {
  const issues: RulesetIssue[] = [];
  const add = (field: string, message: string) => issues.push({ field, message });
  const notNegative = (x: number, field: string, what: string) => {
    if (x < 0 || !isFiniteNumber(x)) add(field, `${what} kan ikke være negativt.`);
  };

  // Sesong og telling.
  if (r.evenings < 1) add("evenings", "Turneringen må ha minst én kveld.");
  const checkCounting = (c: Counting, field: string, what: string) => {
    if (c.best === null) return;
    if (c.best < 1) {
      add(`${field}.best`, `${what}: «beste N» må være minst 1. La feltet stå tomt for at alt skal telle.`);
    } else if (c.unit === "evening" && r.evenings >= 1 && c.best > r.evenings) {
      add(`${field}.best`, `${what}: beste ${c.best} kvelder er flere enn de ${r.evenings} kveldene i turneringen.`);
    }
  };
  checkCounting(r.table.counting, "table.counting", "Tabellen");
  checkCounting(r.table.stablefordCounting, "table.stablefordCounting", "Stablefordsummen");
  if (r.table.pointsSource === "stableford" && r.table.counting.unit === "match") {
    add("table.counting.unit", "Tabellen teller stableford, så den kan ikke telle matcher. Velg runder eller kvelder.");
  }
  if (r.table.stablefordCounting.unit === "match") {
    add("table.stablefordCounting.unit", "Stablefordsummen kan ikke telle matcher. Velg runder eller kvelder.");
  }

  // Poeng.
  const mp = r.table.matchPoints;
  notNegative(mp.win, "table.matchPoints.win", "Poeng for seier");
  notNegative(mp.draw, "table.matchPoints.draw", "Poeng for uavgjort");
  notNegative(mp.loss, "table.matchPoints.loss", "Poeng for tap");
  if (mp.win < mp.draw || mp.draw < mp.loss) {
    add("table.matchPoints", "Seier må gi minst like mye som uavgjort, og uavgjort minst like mye som tap.");
  }
  const tp = r.table.trianglePoints;
  if (tp.length !== 3) add("table.trianglePoints", `Trekanten trenger poeng for tre plasser, ikke ${tp.length}.`);
  if (tp.some((x) => x < 0 || !isFiniteNumber(x))) add("table.trianglePoints", "Trekantpoeng kan ikke være negative.");
  if (tp.some((x, i) => i + 1 < tp.length && x < tp[i + 1])) {
    add("table.trianglePoints", "En bedre plass i trekanten må gi minst like mye som en dårligere.");
  }
  const step = r.table.roundingStep;
  if (step !== null && (!(step > 0) || !isFiniteNumber(step))) {
    add("table.roundingStep", "Avrundingen må være større enn 0, eller tom for ingen avrunding.");
  }
  if (new Set(r.table.tiebreaks).size !== r.table.tiebreaks.length) {
    add("table.tiebreaks", "Det samme skilletegnet står flere ganger.");
  }
  if (r.scoring.netParPoints < 0) add("scoring.netParPoints", "Poeng for netto par kan ikke være negativt.");
  if (r.scoring.minimumPoints > r.scoring.netParPoints) {
    add("scoring.minimumPoints", "Laveste poeng på et hull kan ikke være høyere enn poeng for netto par.");
  }

  // Sidepremier.
  notNegative(r.sidePrizes.longestDrive.points, "sidePrizes.longestDrive.points", "Poeng for longest drive");
  notNegative(r.sidePrizes.closestToPin.points, "sidePrizes.closestToPin.points", "Poeng for nærmest pinnen");

  // Handicap.
  const checkAllowance = (a: number, field: string) => {
    if (!(a >= 0 && a <= 1)) add(field, "Handicapandelen må være mellom 0 og 100 %.");
  };
  if (r.handicap.allowanceOverride !== null) checkAllowance(r.handicap.allowanceOverride, "handicap.allowanceOverride");
  for (const id of Object.keys(r.handicap.formAllowances).sort()) {
    checkAllowance(r.handicap.formAllowances[id], `handicap.formAllowances.${id}`);
  }
  const numbers = r.handicap.seedingGroups.map((g) => g.number);
  if (new Set(numbers).size !== numbers.length) add("handicap.seedingGroups", "To seedinggrupper har samme nummer.");
  for (const id of Object.keys(r.handicap.teamHandicap).sort()) {
    const rule = r.handicap.teamHandicap[id];
    if (rule.method !== "weighted") continue;
    const weights = rule.weights ?? [];
    if (weights.length === 0) {
      add(`handicap.teamHandicap.${id}`, "Vektet lagshandicap trenger vekter.");
    } else if (weights.some((w) => w < 0 || !isFiniteNumber(w))) {
      add(`handicap.teamHandicap.${id}`, "Vektene i lagshandicapet kan ikke være negative.");
    }
  }

  // Former.
  if (r.formats.maxPerBay < 1) add("formats.maxPerBay", "Det må være plass til minst én spiller per bås.");
  if (r.formats.allowedFormIDs.length === 0) add("formats.allowedFormIDs", "Minst én konkurranseform må være tillatt.");
  const known = new Set(ALL_FORMS.map((f) => f.id));
  for (const id of r.formats.allowedFormIDs) {
    if (!known.has(id)) add("formats.allowedFormIDs", `Ukjent konkurranseform: «${id}».`);
  }
  if (r.formats.allowedFormIDs.length > 0 && !r.formats.allowedFormIDs.includes(r.formats.defaultFormID)) {
    add("formats.defaultFormID", "Standardformen må være blant de tillatte formene.");
  }

  // Tippekupongen.
  const t = r.tips;
  if (tipsStartTime(t.defaultStartTime, "17:00") !== t.defaultStartTime || [...t.defaultStartTime].length !== 5) {
    add("tips.defaultStartTime", "Fristen må være et klokkeslett som 17:00.");
  }
  if (!inRange(t.defaultStakePoints, TIPS_STAKE_LIMITS)) {
    add("tips.defaultStakePoints", `Innsatsen må være mellom 0 og ${TIPS_STAKE_LIMITS[1]} poeng.`);
  }
  if (t.stakeOptions.length === 0 || t.stakeOptions.some((x) => !inRange(x, TIPS_STAKE_LIMITS))) {
    add("tips.stakeOptions", `Innsatsvalgene må være mellom 0 og ${TIPS_STAKE_LIMITS[1]} poeng.`);
  }
  if (!isValidTipsLine(t.defaultLine)) {
    add("tips.defaultLine", "Linja må være et halvt slag (som 2,5) mellom −9,5 og +18,5.");
  }
  if (!(t.lineStep > 0) || t.lineStep !== Math.round(t.lineStep)) {
    add("tips.lineStep", "Linja må flyttes i hele slag, så den blir stående på et halvt.");
  }

  // Veddemål.
  const b = r.bets;
  if (!(b.lockAheadHoles >= 1 && b.lockAheadHoles <= 17)) add("bets.lockAheadHoles", "Forspranget må være fra 1 til 17 hull.");
  if (!inRange(b.maxStakePerBet, BET_STAKE_LIMITS)) {
    add("bets.maxStakePerBet", `Taket per veddemål må være mellom 1 og ${BET_STAKE_LIMITS[1]} poeng.`);
  }
  if (b.stakeOptions.length === 0 || b.stakeOptions.some((x) => x < 1 || x > b.maxStakePerBet)) {
    add("bets.stakeOptions", "Beløpsknappene må være fra 1 poeng og opp til taket.");
  }
  if (b.defaultStake < 1 || b.defaultStake > b.maxStakePerBet) {
    add("bets.defaultStake", "Beløpet som er valgt må være fra 1 poeng og opp til taket.");
  }
  if (b.startingPoints !== null && !(b.startingPoints >= 0 && b.startingPoints <= BET_BANK_LIMIT)) {
    add("bets.startingPoints", `Startbeholdningen må være mellom 0 og ${BET_BANK_LIMIT} poeng, eller tom for ingen bank.`);
  }
  if (!inRange(b.payoutDecimals, BET_PAYOUT_DECIMALS)) {
    add("bets.payoutDecimals", `Oppgjøret kan ha fra 0 (hele poeng) til ${BET_PAYOUT_DECIMALS[1]} desimaler.`);
  }

  // Ledelsen underveis.
  const lc = r.leadCheckpoints;
  if (lc.some((x) => !(x >= 1 && x <= 18))) add("leadCheckpoints", "Sjekkpunktene for ledelsen må være hull fra 1 til 18.");
  if (lc.some((x, i) => i + 1 < lc.length && x >= lc[i + 1])) {
    add("leadCheckpoints", "Sjekkpunktene for ledelsen må stå i stigende rekkefølge, uten like.");
  }
  return issues;
}

/** Gyldighetssjekk av konkurransereglene. Tom liste: alt er i orden. */
export function validateCompetitionRules(c: CompetitionRules): RulesetIssue[] {
  const issues: RulesetIssue[] = [];
  const check = (r: LeagueRules, field: string) => {
    const pp = r.placementPoints;
    if (pp.some((x) => x < 0 || !isFiniteNumber(x))) {
      issues.push({ field: `${field}.placementPoints`, message: "Plasseringspoeng kan ikke være negative." });
    }
    if (pp.some((x, i) => i + 1 < pp.length && x < pp[i + 1])) {
      issues.push({ field: `${field}.placementPoints`, message: "En bedre plass må gi minst like mange poeng som en dårligere." });
    }
    if (r.scoring === "placement" && pp.length === 0) {
      issues.push({ field: `${field}.placementPoints`, message: "Plasseringspoeng trenger minst én plass." });
    }
    if (r.participationPoints < 0 || !isFiniteNumber(r.participationPoints)) {
      issues.push({ field: `${field}.participationPoints`, message: "Deltakerpoeng kan ikke være negative." });
    }
    if (r.bestRounds !== null && r.bestRounds < 1) {
      issues.push({ field: `${field}.bestRounds`, message: "«Beste N runder» må være minst 1. La feltet stå tomt for at alle skal telle." });
    }
    if (new Set(r.tiebreaks).size !== r.tiebreaks.length) {
      issues.push({ field: `${field}.tiebreaks`, message: "Et skille står to ganger." });
    }
  };
  check(c.league, "competition.league");
  check(c.fun, "competition.fun");
  return issues;
}
