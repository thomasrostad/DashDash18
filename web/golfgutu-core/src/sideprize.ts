// Longest drive og nærmest pinnen (SidePrize.swift, db-nytt.js linje 717–722 og 2836–2925).

import { courseHoles } from "./course.ts";
import { jsRound, norwegianCompare, norwegianString, sortedBy } from "./jsmath.ts";
import type { PlayedHole, Round, SideClaim, SideClaimKind } from "./models.ts";

/** `harLongestDrive`. */
export function hasLongestDrive(round: Round): boolean {
  return round.ldEnabled;
}

/** `harKp`. */
export function hasClosestToPin(round: Round): boolean {
  return round.kpEnabled;
}

/** `longestDriveHullFor`: det lagrede hullet, ellers forslaget. `null` når premien er av. */
export function longestDriveHole(round: Round): number | null {
  if (!hasLongestDrive(round)) return null;
  return round.ldHoleIndex ?? suggestedLongestDriveHole(round);
}

/** `kpHullFor`: det lagrede hullet, ellers forslaget. `null` når premien er av. */
export function closestToPinHole(round: Round): number | null {
  if (!hasClosestToPin(round)) return null;
  return round.kpHoleIndex ?? suggestedClosestToPinHole(round);
}

function hasMeters(h: PlayedHole): boolean {
  return (h.meters ?? 0) !== 0;
}

/**
 * `foreslaattLongestDriveHull`: med lengder det lengste hullet som ikke er par 3. Uten: første par 5 fra
 * og med hull 4, så første par 5, så første par 4, ellers hull 1.
 */
export function suggestedLongestDriveHole(round: Round): number {
  const course = courseHoles(round);
  if (course.some((h) => h.par >= 4 && hasMeters(h))) {
    let best = -1;
    let bestValue = -1;
    course.forEach((h, i) => {
      if (h.par >= 4 && hasMeters(h) && h.meters! > bestValue) {
        best = i;
        bestValue = h.meters!;
      }
    });
    return best;
  }
  let i = course.findIndex((h, n) => n >= 3 && h.par >= 5);
  if (i >= 0) return i;
  i = course.findIndex((h) => h.par >= 5);
  if (i >= 0) return i;
  i = course.findIndex((h) => h.par >= 4);
  if (i >= 0) return i;
  return 0;
}

/** `foreslaattKpHull`: første par 3 fra og med hull 4, så første par 3, ellers hull 3. */
export function suggestedClosestToPinHole(round: Round): number {
  const course = courseHoles(round);
  let i = course.findIndex((h, n) => n >= 3 && h.par === 3);
  if (i >= 0) return i;
  i = course.findIndex((h) => h.par === 3);
  if (i >= 0) return i;
  return 2;
}

/** `(a.ts||'').localeCompare(b.ts||'')`. Lik tid beholder rekkefølgen. */
function earlier(a: SideClaim, b: SideClaim): boolean {
  return norwegianCompare(a.ts ?? "", b.ts ?? "") < 0;
}

function longestFirst(a: SideClaim, b: SideClaim): boolean {
  return a.meters !== b.meters ? a.meters > b.meters : earlier(a, b);
}

function closestFirst(a: SideClaim, b: SideClaim): boolean {
  return a.meters !== b.meters ? a.meters < b.meters : earlier(a, b);
}

/** `longestDriveClaims`: rundens innmeldinger, lengst først; ved likt den som meldte først. */
export function longestDriveClaims(round: Round, claims: readonly SideClaim[]): SideClaim[] {
  if (!hasLongestDrive(round)) return [];
  return sortedBy(claims.filter((c) => c.kind === "drive" && c.roundId === round.id), longestFirst);
}

/** `kpClaims`: rundens innmeldinger, nærmest først; ved likt den som meldte først. */
export function closestToPinClaims(round: Round, claims: readonly SideClaim[]): SideClaim[] {
  if (!hasClosestToPin(round)) return [];
  return sortedBy(claims.filter((c) => c.kind === "kp" && c.roundId === round.id), closestFirst);
}

/** Innmeldingene som teller for premien i runden, sortert. */
export function claimsFor(kind: SideClaimKind, round: Round, claims: readonly SideClaim[]): SideClaim[] {
  return kind === "drive" ? longestDriveClaims(round, claims) : closestToPinClaims(round, claims);
}

/** `sidepremieVinnere`: alle med samme lengde som den første i den sorterte lista. */
export function sidePrizeWinners(sortedClaims: readonly SideClaim[]): string[] {
  if (sortedClaims.length === 0) return [];
  const best = sortedClaims[0].meters;
  return sortedClaims.filter((c) => c.meters === best).map((c) => c.playerId);
}

/** `besteClaimPerSpiller`: hver spillers beste innmelding, i rekkefølgen spillerne dukker opp. */
export function bestClaimPerPlayer(claims: readonly SideClaim[], isBetter: (n: number, old: number) => boolean): SideClaim[] {
  const order: string[] = [];
  const best = new Map<string, SideClaim>();
  for (const c of claims) {
    const now = best.get(c.playerId);
    if (now !== undefined) {
      if (isBetter(c.meters, now.meters)) best.set(c.playerId, c);
    } else {
      order.push(c.playerId);
      best.set(c.playerId, c);
    }
  }
  return order.map((id) => best.get(id)!);
}

/** `longestDriveSesong`: hver spillers lengste drive i sesongen, lengst først. */
export function seasonLongestDrive(claims: readonly SideClaim[]): SideClaim[] {
  return sortedBy(bestClaimPerPlayer(claims.filter((c) => c.kind === "drive"), (a, b) => a > b), longestFirst);
}

/** `kpSesong`: hver spillers nærmeste i sesongen, nærmest først. */
export function seasonClosestToPin(claims: readonly SideClaim[]): SideClaim[] {
  return sortedBy(bestClaimPerPlayer(claims.filter((c) => c.kind === "kp"), (a, b) => a < b), closestFirst);
}

/** `fmtMeter`: én desimal, desimalkomma: «272,5 m». */
export function formatMeters(meters: number): string {
  return norwegianString(jsRound(meters * 10) / 10) + " m";
}
