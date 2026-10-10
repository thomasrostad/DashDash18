// World Handicap System: score differential og handicapindeks regnet fra rundene i appen (WHS.swift).
// Kilde: Rules of Handicapping (R&A og USGA), utgaven fra 1. januar 2024. Tallene her er WHS-definisjonen,
// ikke regelverdier for en turnering. Avgrensningen er den samme som i Swift: bare 18-hullsrunder med
// alle hull ført og course rating og slope gir en differential; PCC settes til 0.

import { obj, optNumber, reqInt, reqNumber, reqString, type JSONObject } from "./decode.ts";

export const STANDARD_SLOPE = 113;
export const NET_DOUBLE_BOGEY_OVER_PAR = 2;
export const MAXIMUM_OVER_PAR_WITHOUT_INDEX = 5;
export const SCORES_IN_RECORD = 20;
export const MAXIMUM_INDEX = 54.0;
export const SOFT_CAP_THRESHOLD = 3.0;
export const SOFT_CAP_FACTOR = 0.5;
export const HARD_CAP = 5.0;
export const LOW_INDEX_WINDOW_DAYS = 365;
export const LOW_INDEX_MINIMUM_SCORES = 20;
/** Eksepsjonell score (regel 5.9): terskel → slag som trekkes fra. Høyeste terskel først. */
export const EXCEPTIONAL_SCORE_REDUCTIONS: readonly { threshold: number; reduction: number }[] = [
  { threshold: 10.0, reduction: 2.0 },
  { threshold: 7.0, reduction: 1.0 },
];

/** Tabellen i regel 5.2a: hvor mange av de laveste som brukes, og justeringen. Under 3 scorer: `null`. */
export function selection(count: number): { lowest: number; adjustment: number } | null {
  if (count < 3) return null;
  if (count === 3) return { lowest: 1, adjustment: -2.0 };
  if (count === 4) return { lowest: 1, adjustment: -1.0 };
  if (count === 5) return { lowest: 1, adjustment: 0 };
  if (count === 6) return { lowest: 2, adjustment: -1.0 };
  if (count <= 8) return { lowest: 2, adjustment: 0 };
  if (count <= 11) return { lowest: 3, adjustment: 0 };
  if (count <= 14) return { lowest: 4, adjustment: 0 };
  if (count <= 16) return { lowest: 5, adjustment: 0 };
  if (count <= 18) return { lowest: 6, adjustment: 0 };
  if (count === 19) return { lowest: 7, adjustment: 0 };
  return { lowest: 8, adjustment: 0 };
}

function awayFromZero(x: number): number {
  const t = Math.trunc(x);
  return Math.abs(x - t) >= 0.5 ? t + Math.sign(x) : t;
}

/** Nærmeste tidel, ,5 bort fra null. Tåler binær støy (12,25 kan bli 12,2499999…). */
export function roundTenth(x: number): number {
  const scaled = x * 10;
  const nudged = scaled + (scaled >= 0 ? 1e-9 : -1e-9);
  return awayFromZero(nudged) / 10;
}

/** Nærmeste hele tall, ,5 bort fra null. */
export function roundWhole(x: number): number {
  return awayFromZero(x + (x >= 0 ? 1e-9 : -1e-9));
}

/** Banehandicap (regel 6.1a). */
export function whsCourseHandicap(index: number, slope: number, courseRating: number, par: number): number {
  return roundWhole(index * (slope / STANDARD_SLOPE) + (courseRating - par));
}

/** Slag fått på hullet (regel 6.2). Et plusshandicap gir slag tilbake på de letteste hullene. */
export function strokesReceived(courseHandicap: number, strokeIndex: number, holes = 18): number {
  if (courseHandicap >= 0) {
    return Math.trunc(courseHandicap / holes) + (strokeIndex <= courseHandicap % holes ? 1 : 0);
  }
  const plus = -courseHandicap;
  return 0 - (Math.trunc(plus / holes) + (strokeIndex > holes - (plus % holes) ? 1 : 0));
}

/** Høyeste score som teller på hullet (regel 3.1). */
export function maximumHoleScore(par: number, strokeIndex: number, courseHandicap: number | null): number {
  if (courseHandicap === null) return par + MAXIMUM_OVER_PAR_WITHOUT_INDEX;
  return par + NET_DOUBLE_BOGEY_OVER_PAR + strokesReceived(courseHandicap, strokeIndex);
}

export interface WHSHole {
  par: number;
  strokeIndex: number;
  gross: number;
}

/** Justert bruttoscore (regel 3.1). */
export function adjustedGrossScore(holes: readonly WHSHole[], courseHandicap: number | null): number {
  return holes.reduce((sum, h) => sum + Math.min(h.gross, maximumHoleScore(h.par, h.strokeIndex, courseHandicap)), 0);
}

/** Score differential (regel 5.1a). */
export function scoreDifferential(adjustedGross: number, courseRating: number, slope: number, pcc = 0): number {
  return roundTenth((STANDARD_SLOPE / slope) * (adjustedGross - courseRating - pcc));
}

export interface WHSScore {
  id: string;
  /** `YYYY-MM-DD`. */
  date: string;
  holes: WHSHole[];
  courseRating: number;
  slope: number;
  /** Indeksen spilleren hadde da runden ble spilt. `null`: den utregnede før runden. */
  handicapIndex: number | null;
}

export function scorePar(s: WHSScore): number {
  return s.holes.reduce((sum, h) => sum + h.par, 0);
}

export interface WHSRevision {
  scoreID: string;
  date: string;
  courseHandicap: number | null;
  adjustedGross: number;
  differential: number;
  exceptionalReduction: number;
  index: number | null;
  scoresInRecord: number;
  lowIndex: number | null;
  capped: boolean;
}

/** Indeksen runde for runde (regel 5.2, 5.7, 5.8 og 5.9). Sortert på dato; samme dato beholder rekkefølgen. */
export function whsHistory(scores: readonly WHSScore[]): WHSRevision[] {
  const ordered = scores
    .map((element, offset) => ({ element, offset }))
    .sort((a, b) => (a.element.date === b.element.date ? a.offset - b.offset : a.element.date < b.element.date ? -1 : 1))
    .map((x) => x.element);

  const record: { differential: number; reduction: number }[] = [];
  const revisions: WHSRevision[] = [];
  const established: { date: string; index: number }[] = [];
  let current: number | null = null;

  for (const score of ordered) {
    if (!(score.holes.length === 18 && score.slope > 0)) continue;
    const indexForRound = score.handicapIndex ?? current;
    const ch = indexForRound !== null ? whsCourseHandicap(indexForRound, score.slope, score.courseRating, scorePar(score)) : null;
    const ags = adjustedGrossScore(score.holes, ch);
    const diff = scoreDifferential(ags, score.courseRating, score.slope);
    record.push({ differential: diff, reduction: 0 });

    if (current !== null) {
      const before = current;
      const esr = EXCEPTIONAL_SCORE_REDUCTIONS.find((e) => before - diff >= e.threshold);
      if (esr) {
        for (let i = Math.max(0, record.length - SCORES_IN_RECORD); i < record.length; i++) record[i].reduction += esr.reduction;
      }
    }

    const recent = record.slice(-SCORES_IN_RECORD);
    let lowIndex: number | null = null;
    let capped = false;
    let index: number | null = null;
    const sel = selection(recent.length);
    if (sel !== null) {
      const lowest = recent.map((e) => e.differential - e.reduction).sort((a, b) => a - b).slice(0, sel.lowest);
      let calc = roundTenth(lowest.reduce((s, x) => s + x, 0) / sel.lowest + sel.adjustment);
      if (record.length >= LOW_INDEX_MINIMUM_SCORES) {
        lowIndex = lowHandicapIndex(established, score.date);
        if (lowIndex !== null && calc - lowIndex > SOFT_CAP_THRESHOLD) {
          const soft = lowIndex + SOFT_CAP_THRESHOLD + (calc - lowIndex - SOFT_CAP_THRESHOLD) * SOFT_CAP_FACTOR;
          calc = roundTenth(Math.min(soft, lowIndex + HARD_CAP));
          capped = true;
        }
      }
      index = Math.min(calc, MAXIMUM_INDEX);
    }
    if (index !== null && record.length >= LOW_INDEX_MINIMUM_SCORES) established.push({ date: score.date, index });
    current = index ?? current;
    revisions.push({
      scoreID: score.id,
      date: score.date,
      courseHandicap: ch,
      adjustedGross: ags,
      differential: diff,
      exceptionalReduction: record[record.length - 1]?.reduction ?? 0,
      index,
      scoresInRecord: recent.length,
      lowIndex,
      capped,
    });
  }
  return revisions;
}

/** `YYYY-MM-DD` → millisekunder i UTC, eller `null`. */
function day(s: string): number | null {
  // Som Swifts `split(separator: "-").compactMap { Int($0) }`: tomme biter og ikke-tall faller bort.
  const parts = s.split("-").filter((p) => /^[+-]?[0-9]+$/.test(p)).map(Number);
  if (parts.length !== 3) return null;
  return Date.UTC(parts[0], parts[1] - 1, parts[2]);
}

/** Laveste indeks (regel 5.7): den laveste som gjaldt de 365 dagene før den siste scoren. */
export function lowHandicapIndex(established: readonly { date: string; index: number }[], mostRecentScore: string): number | null {
  const end = day(mostRecentScore);
  if (end === null) return null;
  const start = end - LOW_INDEX_WINDOW_DAYS * 86_400_000;
  const held: number[] = [];
  let beforeWindow: number | null = null;
  for (const e of established) {
    const d = day(e.date);
    if (d === null) continue;
    if (d < start) beforeWindow = e.index;
    else if (d < end) held.push(e.index);
  }
  if (beforeWindow !== null) held.push(beforeWindow);
  return held.length > 0 ? Math.min(...held) : null;
}

export function decodeWHSHole(x: unknown, path = "$"): WHSHole {
  const o: JSONObject = obj(x, path);
  return { par: reqInt(o, "par", path), strokeIndex: reqInt(o, "strokeIndex", path), gross: reqInt(o, "gross", path) };
}

export function decodeWHSScore(x: unknown, path = "$"): WHSScore {
  const o: JSONObject = obj(x, path);
  const holes = o.holes;
  if (!Array.isArray(holes)) throw new Error(`${path}.holes mangler`);
  return {
    id: reqString(o, "id", path),
    date: reqString(o, "date", path),
    holes: holes.map((h, i) => decodeWHSHole(h, `${path}.holes[${i}]`)),
    courseRating: reqNumber(o, "courseRating", path),
    slope: reqNumber(o, "slope", path),
    handicapIndex: optNumber(o, "handicapIndex", path),
  };
}
