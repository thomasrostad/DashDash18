// Tabellreglene fra steg 6 i «Reglene» (som RulesetDraft i appen): minste antall kvelder, sum eller snitt,
// navngitte poengtabeller, likt på første plass og trekning av matcher. Rene funksjoner på et regelsett som
// endres på stedet (RulesEditor kloner først), så de kan testes uten React.

import { dayCount, dayMany, dayOne, rulesetDay, type Ruleset } from "../../golfgutu-core/src/index.ts";

export type DrawMethod = Ruleset["formats"]["drawMethod"];
export type TieRule = Ruleset["table"]["tieRule"];
export type Aggregation = Ruleset["table"]["aggregation"];

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
