// Tabellreglene fra steg 6 i «Reglene» (som RulesetDraft i appen): minste antall kvelder, sum eller snitt,
// navngitte poengtabeller, likt på første plass og trekning av matcher. Og tippekupongen: mal, spørsmål og linjer. Rene funksjoner på et regelsett som
// endres på stedet (RulesEditor kloner først), så de kan testes uten React.

import {
  countsRounds, dayCount, dayMany, dayOne, effectivePlacementPoints, matchingTipsTemplate, rulesetDay, TIPS_QUESTIONS, TIPS_TEMPLATES,
  type Ruleset, type TipsQuestion, type TipsTemplate,
} from "../../golfgutu-core/src/index.ts";

export type DrawMethod = Ruleset["formats"]["drawMethod"];
export type TieRule = Ruleset["table"]["tieRule"];
export type Aggregation = Ruleset["table"]["aggregation"];
export type PointsSource = Ruleset["table"]["pointsSource"];

/** Valgene i rekkefølge, med teksten i skjemaet (som `RuleNames` i appen). */
export const DRAW_METHOD_OPTIONS: readonly { value: DrawMethod; title: string }[] = [
  { value: "standings", title: "Etter tabellen" },
  { value: "avoidRepeats", title: "Tilfeldig uten gjentakelser" },
  { value: "manual", title: "Manuelt" },
];

export const TIE_RULE_OPTIONS: readonly { value: TieRule; title: string }[] = [
  { value: "tiebreaks", title: "Skilletegn (som i dag)" },
  { value: "playoff", title: "Playoff" },
];

/** «Sum», «Snitt per kveld» (eller spilledag). */
export function aggregationOptions(r: Ruleset): { value: Aggregation; title: string }[] {
  return [{ value: "sum", title: "Sum" }, { value: "average", title: `Snitt per ${dayOne(rulesetDay(r))}` }];
}

/** «Minste antall kvelder» (eller spilledager). */
export function minEveningsLabel(r: Ruleset): string {
  return `Minste antall ${dayMany(rulesetDay(r))}`;
}

/** Er grensen på? Utelatt eller 0: alle rangeres. */
export function hasMinEvenings(r: Ruleset): boolean {
  return (r.table.minEvenings ?? 0) > 0;
}

/** Slår grensen på (halvparten av kveldene, minst 1) eller av. */
export function toggleMinEvenings(r: Ruleset, on: boolean): void {
  r.table.minEvenings = on ? Math.max(1, Math.floor(r.evenings / 2)) : null;
}

/** Linja under: hva grensen betyr («De med færre enn 3 kvelder står under tabellen uten plass.»). */
export function minEveningsHelp(r: Ruleset): string | null {
  const min = r.table.minEvenings ?? 0;
  if (min <= 0) return null;
  return `De med færre enn ${dayCount(rulesetDay(r), min)} står under tabellen uten plass.`;
}

export interface NamedPointsTable {
  name: string;
  multiplier: number;
}

/** Poengtabellene sortert på navn (norsk). */
export function pointsTableList(r: Ruleset): NamedPointsTable[] {
  return Object.entries(r.table.pointsTables ?? {})
    .map(([name, t]) => ({ name, multiplier: t.multiplier }))
    .sort((a, b) => a.name.localeCompare(b.name, "nb"));
}

/** Ny poengtabell: «Finale» × 2 først, så «Tabell 2», «Tabell 3» … Svarer med navnet. */
export function addPointsTable(r: Ruleset): string {
  const tables = (r.table.pointsTables ??= {});
  let name = "Finale";
  for (let n = 2; tables[name] !== undefined; n++) name = `Tabell ${n}`;
  tables[name] = { multiplier: 2 };
  return name;
}

/** Gir en poengtabell nytt navn. Usann når navnet er tomt eller i bruk (da står det gamle). */
export function renamePointsTable(r: Ruleset, from: string, to: string): boolean {
  const tables = r.table.pointsTables ?? {};
  const name = to.trim();
  const table = tables[from];
  if (table === undefined) return false;
  if (name === from) return true;
  if (name === "" || tables[name] !== undefined) return false;
  delete tables[from];
  tables[name] = table;
  return true;
}

export function setPointsTableMultiplier(r: Ruleset, name: string, multiplier: number): void {
  const tables = r.table.pointsTables ?? {};
  if (tables[name] !== undefined) tables[name] = { multiplier };
}

export function removePointsTable(r: Ruleset, name: string): void {
  if (r.table.pointsTables) delete r.table.pointsTables[name];
}

// MARK: Hva tabellen teller

/** «Tabellen teller: matcher / stableford / plassering». Uten matcher gir «matcher» som enhet ingen mening, så den byttes til kvelder. */
export function setPointsSource(r: Ruleset, source: PointsSource): void {
  r.table.pointsSource = source;
  if (countsRounds(source) && r.table.counting.unit === "match") r.table.counting.unit = "evening";
}

/** Plasseringspoengene som redigeres: regelsettets egne, ellers standardskalaen (som da skrives inn ved første endring). */
export function placementPointsOf(r: Ruleset): number[] {
  return [...effectivePlacementPoints(r.table)];
}

/** Poengene for plassen (0-basert). */
export function setPlacementPoint(r: Ruleset, index: number, points: number): void {
  const list = placementPointsOf(r);
  if (index < 0 || index >= list.length) return;
  list[index] = points;
  r.table.placementPoints = list;
}

/** Én plass til nederst (poengene til den siste minus 1, ikke under 0; 1 når lista er tom). */
export function addPlacement(r: Ruleset): void {
  const list = placementPointsOf(r);
  list.push(Math.max(list.length > 0 ? list[list.length - 1] - 1 : 1, 0));
  r.table.placementPoints = list;
}

/** Én plass færre (minst én plass). */
export function removePlacement(r: Ruleset): void {
  const list = placementPointsOf(r);
  if (list.length > 1) { list.pop(); r.table.placementPoints = list; }
}

// MARK: Tippekupongen

/** Spørsmålene slik arrangøren ser dem (`TipsQuestion.title` i appen). */
export const TIPS_QUESTION_TITLES: Readonly<Record<TipsQuestion, string>> = {
  winner: "Hvem vinner kvelden?",
  frontNine: "Lavest netto på første ni?",
  backNine: "Lavest netto på siste ni?",
  mostPars: "Flest par eller bedre?",
  birdie: "Blir det slått en birdie?",
  birdieCount: "Antall birdier: over eller under?",
  mostBirdies: "Hvem får flest birdier?",
  over: "Over eller under linja?",
  winnerPoints: "Vinnerens poeng: over eller under?",
  lastPlace: "Hvem blir sist?",
  lowestGross: "Lavest brutto?",
  comeback: "Kveldens comeback?",
  mostBlanks: "Hvem får flest blanke hull?",
  bestParThrees: "Best på par 3-hullene?",
  bestParFives: "Best på par 5-hullene?",
  parStreak: "Lengst rekke med par eller bedre?",
  eagle: "Blir det en eagle?",
  grossBirdie: "Blir det en ekte birdie?",
  leaderWins: "Vinner lederen etter ni hull?",
  sharedWin: "Blir det delt seier?",
  highHandicapWins: "Vinner en med høyt handicap?",
  lastPlacePoints: "Sistemannens poeng: over eller under?",
  winningMargin: "Seiersmarginen: over eller under?",
  blankHoles: "Antall blanke hull: over eller under?",
  parOrBetterPlayers: "Antall på par eller bedre: over eller under?",
};

/** Overskriften på linja for et over/under-spørsmål i regelsettet (`RulesetTipsSection.lineTitle` i appen). */
export const TIPS_LINE_TITLES: Readonly<Partial<Record<TipsQuestion, string>>> = {
  birdieCount: "Linje for antall birdier",
  winnerPoints: "Linje for vinnerens poeng",
  lastPlacePoints: "Linje for sistemannens poeng",
  winningMargin: "Linje for seiersmarginen",
  blankHoles: "Linje for blanke hull",
  parOrBetterPlayers: "Linje for antall på par",
};

/** Malen kupongen er på, eller `null` (tilpasset). */
export function tipsTemplateOf(r: Ruleset): TipsTemplate | null {
  return matchingTipsTemplate(r.tips.questions);
}

/** Velger en mal: spørsmålene byttes, linjene står. */
export function applyTipsTemplate(r: Ruleset, id: TipsTemplate): void {
  const t = TIPS_TEMPLATES.find((t) => t.id === id);
  if (t) r.tips.questions = [...t.questions];
}

/** Slår et spørsmål av eller på. Lista holdes i kupongens rekkefølge, så malene kjennes igjen. */
export function setTipsQuestion(r: Ruleset, q: TipsQuestion, on: boolean): void {
  const chosen = new Set(r.tips.questions);
  if (on) chosen.add(q); else chosen.delete(q);
  r.tips.questions = TIPS_QUESTIONS.filter((x) => chosen.has(x));
}
