// Tilleggspoeng (sql/072): poeng arrangøren gir en spiller for hånd, med en grunn. Som appens
// TilleggspoengModel.swift (`Tilleggspoeng`): samme grenser, men kvarte poeng og tillegget vist uten avrunding.
import { norwegianString } from "../../golfgutu-core/src/index.ts";

export type Adjustment = {
  id: string; club_id: string; season_id: string; member_id: string; event_id: string | null;
  points: number; reason: string; created_at: string;
};

export const ADJUSTMENT_COLUMNS = "id, club_id, season_id, member_id, event_id, points, reason, created_at";

/** Høyst så mange tegn i grunnen (sql/072). */
export const REASON_LIMIT = 80;
/** Poengene kan være negative (straff eller rettelse), men ikke 0. Databasen lagrer to desimaler. */
export const POINTS_MIN = -100;
export const POINTS_MAX = 100;
/** Steget i feltet: kvarte poeng, så 0,25 for en closest to pin-konkurranse går. */
export const POINTS_STEP = 0.25;

/** Hva som mangler før tillegget kan lagres, eller null. */
export function adjustmentProblem(memberID: string | null, points: number, reason: string): string | null {
  const r = reason.trim();
  if (!memberID) return "Velg en spiller.";
  if (!Number.isFinite(points) || points === 0) return "Poengene kan ikke være 0.";
  if (points < POINTS_MIN || points > POINTS_MAX) return "Høyst 100 poeng av gangen.";
  if (Math.abs(Math.round(points * 100) - points * 100) > 1e-9) return "Poengene kan ha høyst to desimaler.";
  if (r.length === 0) return "Skriv en grunn.";
  if ([...r].length > REASON_LIMIT) return `Grunnen kan ha høyst ${REASON_LIMIT} tegn.`;
  return null;
}

/** «+1», «+0,25», «−2»: tillegget slik det er lagret. Bare totalen i tabellen rundes av etter regelsettet. */
export function adjustmentPointsText(points: number): string {
  const text = norwegianString(Math.abs(points));
  return points < 0 ? "−" + text : "+" + text;
}

/** Raden som sendes. `created_by` settes av databasen. */
export function adjustmentInsert(clubID: string, seasonID: string, memberID: string, eventID: string | null, points: number, reason: string) {
  return { club_id: clubID, season_id: seasonID, member_id: memberID, event_id: eventID, points, reason: reason.trim() };
}
