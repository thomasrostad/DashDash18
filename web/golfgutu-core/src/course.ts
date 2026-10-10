// Bane og hull (CourseRules.swift): standardpar, par-sjekk, hull fra `course_holes` og hullene slik de
// spilles i en runde (`courseForRound`).

import type { Course, CourseHole, CourseHoleRow, PlayedHole, Round } from "./models.ts";

/** `DEFAULT_PAR`: standardbanen, par 72 over 18 hull. */
export const DEFAULT_PAR: readonly number[] = Object.freeze([4, 5, 3, 4, 4, 3, 5, 4, 4, 4, 3, 5, 4, 4, 3, 4, 5, 4]);

/** `PAR_LENGDE`: rimelig lengde i meter per par (grensene er med). */
export const PAR_LENGTH_RANGE: Readonly<Record<number, readonly [number, number]>> = Object.freeze({
  3: [90, 210],
  4: [230, 440],
  5: [420, 580],
});

/** `parErEtTall`: par mellom 3 og 6. */
export function isValidPar(par: number | null | undefined): boolean {
  if (par === null || par === undefined) return false;
  return par >= 3 && par <= 6;
}

/** `lengdePasserParet`: passer lengden til paret? Uten lengde eller ukjent par: `true`. */
export function lengthMatchesPar(par: number | null, meters: number | null): boolean {
  if (meters === null || par === null) return true;
  const range = PAR_LENGTH_RANGE[par];
  if (!range) return true;
  return meters >= range[0] && meters <= range[1];
}

/** Et hull der lengden ikke passer paret. `number` er 1-basert. */
export interface OddLengthHole {
  number: number;
  par: number | null;
  meters: number | null;
}

/** `hullMedRarLengde` for banens hull eller rundens hull. */
export function holesWithOddLength(holes: readonly { par: number | null; meters: number | null }[]): OddLengthHole[] {
  const out: OddLengthHole[] = [];
  holes.forEach((h, i) => {
    if (!lengthMatchesPar(h.par, h.meters)) out.push({ number: i + 1, par: h.par, meters: h.meters });
  });
  return out;
}

/**
 * `banehullFraRader`: rader fra `course_holes` gruppert per bane, sortert på hullnummer. En bane får
 * `null` med mindre den har 9 eller 18 sammenhengende hull fra 1. Rader uten bane-id hoppes over.
 */
export function holesFromRows(rows: readonly CourseHoleRow[]): Map<string, CourseHole[] | null> {
  const perCourse = new Map<string, CourseHoleRow[]>();
  for (const row of rows) {
    const id = row.courseId;
    if (id === null || id === "") continue;
    const list = perCourse.get(id) ?? [];
    list.push(row);
    perCourse.set(id, list);
  }
  const out = new Map<string, CourseHole[] | null>();
  for (const [id, list] of perCourse) {
    const sorted = [...list].sort((a, b) => a.holeNumber - b.holeNumber);
    const whole = (sorted.length === 9 || sorted.length === 18) && sorted.every((r, i) => r.holeNumber === i + 1);
    out.set(id, whole ? sorted.map((r) => ({ par: r.par, si: r.hcpIndex, meters: r.distanceMeters })) : null);
  }
  return out;
}

/** `baneHarIndeks`: har hvert hull en stroke index over 0? */
export function courseHasStrokeIndex(course: Course): boolean {
  const holes = course.holes;
  if (!holes || holes.length === 0) return false;
  return holes.every((h) => (h.si ?? 0) > 0);
}

/** `baneErKlar`: 9 eller 18 hull, og gyldig par på hvert. */
export function courseIsReady(course: Course): boolean {
  const holes = course.holes;
  if (!holes || (holes.length !== 9 && holes.length !== 18)) return false;
  return holes.every((h) => isValidPar(h.par));
}

/** JS-sannhet for tall: 0, NaN og null faller gjennom (`a || b`). */
export function truthy(x: number | null | undefined): number | null {
  if (x === null || x === undefined || x === 0 || Number.isNaN(x)) return null;
  return x;
}

/** `antallHull`: 9 eller 18. Alt annet er 18. */
export function numberOfHoles(round: Round): number {
  return round.holeCount === 9 || round.holeCount === 18 ? round.holeCount : 18;
}

/**
 * `courseForRound`: hullene slik de spilles i denne runden.
 *
 * Par: rundens eget (hvis gyldig) → banens → `DEFAULT_PAR[i]` (merk: `i`, ikke `start + i`).
 * Kortindeks: rundens egen → banens → `i + 1`, med JS-sannhet. `strokeIndex` er rangen etter
 * kortindeks; likhet avgjøres av lavest hullindeks. Start på hull 10 gjelder bare når runden er 9 hull,
 * `holeStart == 9` og banen har 18 hull.
 */
export function courseHoles(round: Round): PlayedHole[] {
  const count = numberOfHoles(round);
  const fromCourse = round.course?.holes ?? null;
  const start = count === 9 && round.holeStart === 9 && fromCourse?.length === 18 ? 9 : 0;

  const played: PlayedHole[] = [];
  for (let i = 0; i < count; i++) {
    const custom = round.holes?.get(i) ?? null;
    const courseIndex = start + i;
    const fromBane = fromCourse !== null && courseIndex < fromCourse.length ? fromCourse[courseIndex] : null;

    let par: number;
    if (custom?.par !== null && custom?.par !== undefined && isValidPar(custom.par)) par = custom.par;
    else if (fromBane?.par !== null && fromBane?.par !== undefined && isValidPar(fromBane.par)) par = fromBane.par;
    else par = DEFAULT_PAR[i];
    const cardIndex = truthy(custom?.strokeIndex) ?? truthy(fromBane?.si) ?? i + 1;
    const meters = truthy(custom?.meters) ?? truthy(fromBane?.meters);
    played.push({ par, cardIndex, meters, strokeIndex: 0 });
  }

  const order = played.map((_, i) => i).sort((a, b) =>
    played[a].cardIndex !== played[b].cardIndex ? played[a].cardIndex - played[b].cardIndex : a - b);
  order.forEach((i, rank) => {
    played[i].strokeIndex = rank + 1;
  });
  return played;
}
