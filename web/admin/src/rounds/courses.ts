// Banene i runde-oppsettet, som appen (CourseListItem.swift, SlopeNo.swift `TeeChoice`, SlopeNoHoles.swift
// `TeeHoles`, CourseSearch). Ren logikk.

import { courseIsReady, makeCourse, norwegianCompare, type Course, type CourseHoleRecord, type CourseRow } from "../../../golfgutu-core/src/index.ts";

export type CourseKind = "simulator" | "course";
export type TeeGender = "men" | "women" | "mixed";

export interface CourseTee {
  id: string;
  courseID: string;
  name: string;
  gender: TeeGender;
  courseRating: number;
  slopeRating: number;
  par: number | null;
  sortOrder: number;
  /** Teens egne hull (sql/030). Tom = banens hull gjelder. */
  holes: CourseHoleRecord[];
}

export interface CourseItem {
  course: CourseRow;
  /** Sortert på hullnummer. */
  holes: CourseHoleRecord[];
  kind: CourseKind;
  tees: CourseTee[];
  /** Hentet fra slope.no og spilt direkte. */
  isFromSource: boolean;
}

export function teeGenderTitle(g: TeeGender): string {
  return g === "men" ? "Herre" : g === "women" ? "Dame" : "Alle";
}

/** Teene som vises, i kildens rekkefølge (så navn). */
export function visibleTees(tees: readonly CourseTee[]): CourseTee[] {
  return [...tees].sort((a, b) => a.sortOrder - b.sortOrder || norwegianCompare(a.name, b.name));
}

export function makeCourseItem(course: CourseRow, holes: readonly CourseHoleRecord[], kind: CourseKind | null, tees: readonly CourseTee[] = [], isFromSource = false): CourseItem {
  return {
    course,
    holes: [...holes].sort((a, b) => a.holeNumber - b.holeNumber),
    kind: kind ?? "simulator",
    tees: visibleTees(tees),
    isFromSource,
  };
}

/** Er hullene et helt sett: 9 eller 18 sammenhengende fra 1, med gyldig par på hvert? */
export function isCompleteHoles(holes: readonly CourseHoleRecord[]): boolean {
  if (holes.length === 0) return false;
  const id = holes[0].courseID;
  const core = makeCourse({ id, clubID: null, name: "", externalName: null, courseRating: null, slopeRating: null, inUse: true }, holes);
  return core !== null && courseIsReady(core);
}

export function findTee(item: CourseItem, id: string | null): CourseTee | null {
  return id === null ? null : item.tees.find((t) => t.id === id) ?? null;
}

/** Har teen et helt sett egne hull? */
export function teeHasOwnHoles(tee: CourseTee | null): boolean {
  return tee !== null && isCompleteHoles(tee.holes);
}

/** GolfgutuCore-banen uten tee. */
export function coreCourseOf(item: CourseItem): Course {
  return makeCourse(item.course, item.holes)!;
}

/**
 * Banen slik runden regner med den: teens hull når teen har et helt sett, og teens CR og slope.
 * Uten tee er banen uendret (Golfgutu-pariteten for simulatorbaner og baner uten tee).
 */
export function coreCourseWithTee(item: CourseItem, teeID: string | null): Course {
  const tee = findTee(item, teeID);
  const base = teeHasOwnHoles(tee)
    ? makeCourse(item.course, tee!.holes.map((h) => ({ ...h, courseID: item.course.id })))!
    : coreCourseOf(item);
  if (tee === null) return base;
  return { ...base, courseRating: tee.courseRating, slopeRating: tee.slopeRating };
}

/** `baneErKlar`. */
export function courseItemReady(item: CourseItem): boolean {
  return courseIsReady(coreCourseOf(item));
}

/** «18 hull · par 72 · CR 72 · slope 113 · 2 tees · med indeks», eller hva som mangler. */
export function courseSummary(item: CourseItem): string {
  if (!courseItemReady(item)) return "Ikke satt opp. Skriv inn parene fra skjermen.";
  const core = coreCourseOf(item);
  const parts = [`${item.holes.length} hull`, `par ${core.par}`];
  if (item.course.courseRating !== null) parts.push(`CR ${String(item.course.courseRating).replace(".", ",")}`);
  if (item.course.slopeRating !== null) parts.push(`slope ${item.course.slopeRating}`);
  if (item.tees.length > 0) parts.push(item.tees.length === 1 ? "1 tee" : `${item.tees.length} tees`);
  parts.push((core.holes ?? []).every((h) => (h.si ?? 0) > 0) ? "med indeks" : "uten indeks");
  return parts.join(" · ") + (item.isFromSource ? " · fra slope.no" : "");
}

/** Forslaget: teen som ble brukt sist på banen, ellers første herre-tee, ellers første tee. */
export function suggestedTee(tees: readonly CourseTee[], previous: string | null): CourseTee | null {
  const shown = visibleTees(tees);
  if (previous !== null) {
    const t = shown.find((x) => x.id === previous);
    if (t) return t;
  }
  return shown.find((t) => t.gender === "men") ?? shown[0] ?? null;
}

/** Teen som ble brukt i den siste runden på banen: den som startet sist, ellers høyest rundenummer. */
export function previousTeeID(rounds: readonly { courseID: string | null; teeID: string | null; startedAt: string | null; roundNo: number }[], courseID: string | null): string | null {
  if (courseID === null) return null;
  let best: (typeof rounds)[number] | null = null;
  for (const r of rounds) {
    if (r.courseID !== courseID || r.teeID === null) continue;
    if (best === null) { best = r; continue; }
    const a = best, b = r;
    let less: boolean;
    if (a.startedAt !== null && b.startedAt !== null) less = Date.parse(a.startedAt) < Date.parse(b.startedAt);
    else if (a.startedAt === null && b.startedAt !== null) less = true;
    else if (a.startedAt !== null && b.startedAt === null) less = false;
    else less = a.roundNo < b.roundNo;
    if (less) best = r;
  }
  return best?.teeID ?? null;
}

/** «herre · CR 71,2 · slope 129 · par 72». */
export function teeDetail(tee: CourseTee): string {
  const parts = [teeGenderTitle(tee.gender).toLowerCase(), `CR ${String(tee.courseRating).replace(".", ",")}`, `slope ${tee.slopeRating}`];
  const par = teeHasOwnHoles(tee) ? tee.holes.reduce((s, h) => s + h.par, 0) : tee.par;
  if (par !== null) parts.push(`par ${par}`);
  return parts.join(" · ");
}

// MARK: - Søk i slope.no-banene

export interface SlopeCourse {
  id: string;
  name: string;
  city: string | null;
  country: string | null;
  hasHoles: boolean;
}

export function countryName(code: string | null): string | null {
  if (code === null) return null;
  return ({ NO: "Norge", SE: "Sverige", DK: "Danmark", FI: "Finland", IS: "Island", PL: "Polen", DE: "Tyskland" } as Record<string, string>)[code.toUpperCase()] ?? code;
}

export function slopePlace(c: SlopeCourse): string {
  return [c.city, countryName(c.country)].filter((x): x is string => !!x).join(", ");
}

/** Uten hensyn til store bokstaver og aksenter. */
export function normalize(s: string): string {
  return s.toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "");
}

/** Alle ordene må finnes i navnet, stedet eller landet. Norske baner først, så resten; norsk alfabetisk. */
export function filterSlope(courses: readonly SlopeCourse[], query: string, excluding: ReadonlySet<string> = new Set()): SlopeCourse[] {
  const words = query.split(/\s+/).filter(Boolean).map(normalize);
  const matching = courses.filter((c) => c.hasHoles && !excluding.has(c.id)).filter((c) => {
    if (words.length === 0) return true;
    const hay = normalize([c.name, c.city ?? "", countryName(c.country) ?? "", c.country ?? ""].join(" "));
    return words.every((w) => hay.includes(w));
  });
  return matching.sort((a, b) => {
    const na = (a.country ?? "").toUpperCase() === "NO" ? 0 : 1;
    const nb = (b.country ?? "").toUpperCase() === "NO" ? 0 : 1;
    return na - nb || norwegianCompare(a.name, b.name);
  });
}

/** Hvor mange baner fra slope.no velgeren viser om gangen. */
export const SLOPE_PICKER_LIMIT = 25;
