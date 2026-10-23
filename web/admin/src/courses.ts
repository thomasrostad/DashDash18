// Klubbens baner: lage og endre, også simulatorbaner (pakke 2, punkt 4). Som CourseDraft.swift i appen:
// tallfeltene holdes som tekst og tolkes her, med databasens grenser (sql/001, 002) og PWA-ens regler.
// Ren logikk; kallene står i coursesApi.ts.

import { DEFAULT_PAR, holesWithOddLength, isValidPar } from "../../golfgutu-core/src/course.ts";
import { plainErrorText } from "./text.ts";

export type CourseKind = "simulator" | "course";

export interface HoleDraft { number: number; par: number | null; strokeIndexText: string; lengthText: string }

export interface CourseDraft {
  name: string;
  externalName: string;
  courseRatingText: string;
  slopeText: string;
  inUse: boolean;
  kind: CourseKind;
  holes: HoleDraft[];
}

export interface CourseRow {
  id: string; club_id: string | null; name: string; external_name: string | null; course_rating: number | null;
  slope_rating: number | null; in_use: boolean; kind?: CourseKind | null;
}
export interface CourseHoleRow { course_id: string; hole_number: number; par: number; stroke_index: number | null; length_m: number | null }

export const HOLE_COUNTS = [9, 18];
export const PAR_CHOICES = [3, 4, 5, 6];
/** `courses.name` og `external_name`. */
export const MAX_NAME_LENGTH = 80;
/** PWA-ens grense (`handleLagreBane`). Databasen tåler 20–90. */
export const COURSE_RATING_RANGE: [number, number] = [50, 90];
export const SLOPE_RANGE: [number, number] = [55, 155];
export const LENGTH_RANGE: [number, number] = [50, 700];

function emptyHoles(from: number, to: number): HoleDraft[] {
  return Array.from({ length: to - from + 1 }, (_, i) => ({ number: from + i, par: null, strokeIndexText: "", lengthText: "" }));
}

/** Ny, tom bane. Par står tomt til det leses av skjermen; appen gjetter ikke par. */
export function newDraft(holeCount = 18): CourseDraft {
  return { name: "", externalName: "", courseRatingText: "", slopeText: "", inUse: true, kind: "simulator", holes: emptyHoles(1, holeCount) };
}

/** `72` → «72», `71.4` → «71,4». */
export function decimalText(value: number): string {
  return String(value).replace(".", ",");
}

/** Fra lagrede rader. Hull som mangler i databasen blir tomme. */
export function draftFromRows(course: CourseRow, rows: readonly CourseHoleRow[]): CourseDraft {
  const count = rows.length > 9 ? 18 : rows.length === 0 ? 18 : 9;
  const byNumber = new Map<number, CourseHoleRow>();
  for (const r of rows) if (!byNumber.has(r.hole_number)) byNumber.set(r.hole_number, r);
  return {
    name: course.name,
    externalName: course.external_name ?? "",
    courseRatingText: course.course_rating !== null ? decimalText(course.course_rating) : "",
    slopeText: course.slope_rating !== null ? String(course.slope_rating) : "",
    inUse: course.in_use,
    kind: course.kind ?? "simulator",
    holes: Array.from({ length: count }, (_, i) => {
      const r = byNumber.get(i + 1);
      return r
        ? { number: i + 1, par: r.par, strokeIndexText: r.stroke_index !== null ? String(r.stroke_index) : "", lengthText: r.length_m !== null ? String(r.length_m) : "" }
        : { number: i + 1, par: null, strokeIndexText: "", lengthText: "" };
    }),
  };
}

/** Bytter mellom 9 og 18 hull. Det som er skrevet inn på hull 1–9 beholdes. */
export function setHoleCount(d: CourseDraft, count: number): CourseDraft {
  if (!HOLE_COUNTS.includes(count) || count === d.holes.length) return d;
  return { ...d, holes: count < d.holes.length ? d.holes.slice(0, count) : [...d.holes, ...emptyHoles(d.holes.length + 1, count)] };
}

/** Summen av parene, eller null når noen mangler. */
export function draftPar(d: CourseDraft): number | null {
  if (d.holes.length === 0 || d.holes.some((h) => h.par === null)) return null;
  return d.holes.reduce((s, h) => s + (h.par ?? 0), 0);
}

/** Standardbanen (par 72 over 18 hull, par 36 over 9). */
export function standardPars(d: CourseDraft): number[] {
  return DEFAULT_PAR.slice(0, d.holes.length);
}

/** Teksten på knappen: «Fyll standard par 72», eller for tomme hull når noe er skrevet inn. */
export function fillStandardText(d: CourseDraft): string {
  return d.holes.every((h) => h.par === null) ? `Fyll standard par ${standardPars(d).reduce((a, b) => a + b, 0)}` : "Fyll tomme hull med standard par";
}

/** Fyller hullene uten par med standardbanen. Par som alt er skrevet inn, røres ikke. */
export function fillStandardPar(d: CourseDraft): CourseDraft {
  const pars = standardPars(d);
  return { ...d, holes: d.holes.map((h, i) => (h.par === null && i < pars.length ? { ...h, par: pars[i] } : h)) };
}

/** Par-knappen: trykk på valgt par igjen tømmer hullet. */
export function tapPar(d: CourseDraft, par: number, hole: number): CourseDraft {
  return { ...d, holes: d.holes.map((h) => (h.number === hole ? { ...h, par: h.par === par ? null : par } : h)) };
}

export function setHole(d: CourseDraft, hole: number, patch: Partial<HoleDraft>): CourseDraft {
  return { ...d, holes: d.holes.map((h) => (h.number === hole ? { ...h, ...patch } : h)) };
}

/** Desimaltall med komma eller punktum, rundet til én desimal. Tomt: null. Ugyldig: undefined. */
export function parseDecimal(raw: string): number | null | undefined {
  const text = raw.trim().replace(",", ".");
  if (!text) return null;
  if (!/^[+-]?(\d+(\.\d*)?|\.\d+)$/.test(text)) return undefined;
  const v = Number(text);
  return Number.isFinite(v) ? Math.round(v * 10) / 10 : undefined;
}

/** Heltall. Tomt: null. Ugyldig: undefined. */
export function parseInteger(raw: string): number | null | undefined {
  const text = raw.trim();
  if (!text) return null;
  return /^[+-]?\d+$/.test(text) ? Number(text) : undefined;
}

/** «hull 3», «hull 3 og 7», «hull 3, 7 og 12». */
export function holeList(holes: readonly number[]): string {
  if (holes.length === 0) return "";
  if (holes.length === 1) return `hull ${holes[0]}`;
  return `hull ${holes.slice(0, -1).join(", ")} og ${holes[holes.length - 1]}`;
}

export interface Issue { blocking: boolean; message: string }

export interface CourseValues {
  name: string; externalName: string | null; courseRating: number | null; slopeRating: number | null; inUse: boolean;
  kind: CourseKind;
  holes: { hole_number: number; par: number; stroke_index: number | null; length_m: number | null }[];
}

export interface CourseValidation { issues: Issue[]; values: CourseValues | null }

const err = (message: string): Issue => ({ blocking: true, message });
const warn = (message: string): Issue => ({ blocking: false, message });

/** Sjekker skjemaet. Gir banen klar til lagring når ingen feil sperrer. Advarsler lagres likevel. */
export function validate(d: CourseDraft): CourseValidation {
  const issues: Issue[] = [];
  const name = d.name.trim();
  if (!name) issues.push(err("Gi banen et navn."));
  else if ([...name].length > MAX_NAME_LENGTH) issues.push(err(`Navnet kan ha høyst ${MAX_NAME_LENGTH} tegn.`));
  const external = d.kind === "simulator" ? d.externalName.trim() : "";
  if ([...external].length > MAX_NAME_LENGTH) issues.push(err(`Navnet i simulatoren kan ha høyst ${MAX_NAME_LENGTH} tegn.`));

  let courseRating: number | null = null;
  const cr = parseDecimal(d.courseRatingText);
  if (cr === undefined || (cr !== null && (cr < COURSE_RATING_RANGE[0] || cr > COURSE_RATING_RANGE[1]))) {
    issues.push(err(`Course Rating må være et tall mellom ${COURSE_RATING_RANGE[0]} og ${COURSE_RATING_RANGE[1]}, eller stå tom.`));
  } else courseRating = cr;

  let slope: number | null = null;
  const sl = parseInteger(d.slopeText);
  if (sl === undefined || (sl !== null && (sl < SLOPE_RANGE[0] || sl > SLOPE_RANGE[1]))) {
    issues.push(err(`Slope må være et heltall mellom ${SLOPE_RANGE[0]} og ${SLOPE_RANGE[1]}, eller stå tom.`));
  } else slope = sl;

  const count = d.holes.length;
  if (!HOLE_COUNTS.includes(count)) issues.push(err(`En bane har 9 eller 18 hull, ikke ${count}.`));
  const noParAtAll = d.holes.every((h) => h.par === null);
  if (noParAtAll) issues.push(warn("Ingen par er skrevet inn. Banen lagres, men står som ikke satt opp."));

  const validHoles: CourseValues["holes"] = [];
  const missingPar: number[] = [];
  const missingIndex: number[] = [];
  const byIndex = new Map<number, number[]>();
  for (const h of d.holes) {
    if (h.par === null) { if (!noParAtAll) missingPar.push(h.number); }
    else if (!isValidPar(h.par)) issues.push(err(`Hull ${h.number}: par må være mellom 3 og 6.`));

    let strokeIndex: number | null = null;
    const si = parseInteger(h.strokeIndexText);
    if (si === undefined || (si !== null && (si < 1 || si > count))) {
      issues.push(err(`Hull ${h.number}: indeks må være mellom 1 og ${count}, eller stå tom.`));
    } else if (si === null) missingIndex.push(h.number);
    else { strokeIndex = si; byIndex.set(si, [...(byIndex.get(si) ?? []), h.number]); }

    let length: number | null = null;
    const len = parseInteger(h.lengthText);
    if (len === undefined || (len !== null && (len < LENGTH_RANGE[0] || len > LENGTH_RANGE[1]))) {
      issues.push(err(`Hull ${h.number}: lengden må være mellom ${LENGTH_RANGE[0]} og ${LENGTH_RANGE[1]} meter, eller stå tom.`));
    } else length = len;

    if (h.par !== null) validHoles.push({ hole_number: h.number, par: h.par, stroke_index: strokeIndex, length_m: length });
  }
  if (missingPar.length > 0) issues.push(err(`Par mangler på ${holeList(missingPar)}. Les det av skjermen.`));
  for (const [index, numbers] of [...byIndex].sort((a, b) => a[0] - b[0])) {
    if (numbers.length > 1) {
      const list = holeList(numbers);
      issues.push(err(`${list.charAt(0).toUpperCase()}${list.slice(1)} har samme indeks (${index}).`));
    }
  }
  if (!noParAtAll && missingIndex.length > 0) {
    issues.push(warn(`Indeks mangler på ${holeList(missingIndex)}. Den trengs bare når appen selv deler ut slagene.`));
  }
  // Advarsel som i PWA-en (`hullMedRarLengde`): lagres likevel.
  for (const odd of holesWithOddLength(validHoles.map((h) => ({ par: h.par, meters: h.length_m })))) {
    issues.push(warn(`Hull ${validHoles[odd.number - 1].hole_number}: ${odd.meters} m er uvanlig for en par ${odd.par}. Stemmer det med skjermen?`));
  }

  const values = issues.some((i) => i.blocking) ? null : {
    name, externalName: external || null, courseRating, slopeRating: slope, inUse: d.inUse, kind: d.kind,
    holes: noParAtAll ? [] : validHoles,
  };
  return { issues, values };
}

/** Argumentene til `save_course` (sql/002): alle hullene i én transaksjon. */
export function saveParams(clubID: string, courseID: string | null, v: CourseValues) {
  return {
    p_club_id: clubID, p_course_id: courseID, p_name: v.name, p_external_name: v.externalName,
    p_course_rating: v.courseRating, p_slope_rating: v.slopeRating, p_in_use: v.inUse, p_holes: v.holes,
  };
}

/** «Par 72 · 18 hull», «Ikke satt opp» eller hva som mangler, til banelista. */
export function courseSummary(holes: readonly CourseHoleRow[]): string {
  if (holes.length === 0) return "Ikke satt opp";
  const whole = (holes.length === 9 || holes.length === 18) && holes.every((h) => isValidPar(h.par));
  if (!whole) return `${holes.length} hull, ikke klar`;
  return `Par ${holes.reduce((s, h) => s + h.par, 0)} · ${holes.length} hull`;
}

export function kindText(kind: CourseKind | null | undefined): string {
  return kind === "course" ? "Ekte bane" : "Simulator";
}

/** Feil fra lagringen på norsk (CourseLibraryModel.saveError). */
export function saveErrorText(error: { code?: string; message?: string }, name: string): string {
  if (error.code === "23505") return error.message?.includes("stroke_index") ? "To hull har samme indeks." : `Det finnes allerede en bane som heter «${name}».`;
  return plainErrorText(error);
}

/** Sletting stoppes når runder bruker banen (CourseLibraryModel.deleteError). */
export function deleteErrorText(error: { code?: string; message?: string }): string {
  if (error.code === "23503") {
    return "Banen er brukt i en runde og kan ikke slettes. Sett den til «ikke i bruk» i stedet, så forsvinner den fra velgeren.";
  }
  return plainErrorText(error);
}
