// Hva en dag i turneringen heter (DayTerm.swift). Bare ord: regelmotoren bruker det ikke.

export type DayTerm = "evening" | "playingDay";

export const DAY_TERMS: readonly DayTerm[] = ["evening", "playingDay"];

/** «kveld», «spilledag». */
export function dayOne(t: DayTerm): string {
  return t === "evening" ? "kveld" : "spilledag";
}

/** «kvelden», «spilledagen». */
export function dayThe(t: DayTerm): string {
  return dayOne(t) + "en";
}

/** «kvelder», «spilledager». */
export function dayMany(t: DayTerm): string {
  return dayOne(t) + "er";
}

/** «kveldene», «spilledagene». */
export function dayTheMany(t: DayTerm): string {
  return dayOne(t) + "ene";
}

/** «kveldens», «spilledagens». */
export function dayPossessive(t: DayTerm): string {
  return dayThe(t) + "s";
}

/** «1 kveld», «3 kvelder». */
export function dayCount(t: DayTerm, n: number): string {
  return n === 1 ? `1 ${dayOne(t)}` : `${n} ${dayMany(t)}`;
}

/** «I kveld», «I dag». */
export function dayToday(t: DayTerm): string {
  return t === "evening" ? "I kveld" : "I dag";
}

/** «Kveld», «Spilledag». */
export function dayTitle(t: DayTerm): string {
  return capitalized(dayOne(t));
}

/** Stor forbokstav: «kvelden» → «Kvelden». */
export function capitalized(word: string): string {
  if (word.length === 0) return word;
  const first = String.fromCodePoint(word.codePointAt(0)!);
  return first.toUpperCase() + word.slice(first.length);
}
