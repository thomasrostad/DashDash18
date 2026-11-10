// «Challenge etter runden»: en konkurranse når alle er inne (f.eks. CP knockout), der vinneren får
// tilleggspoeng (sql/072). Ingen egne tabeller: hver vinner er én rad i point_adjustments med kvelden og
// en grunn som «CP knockout, bås 1» eller «CP knockout runde 2, bås 1» (samme form som 22.10).
// Ren logikk, testes i test/challenge.test.ts. Appen har samme regler (RoundChallenge.swift).

import { REASON_LIMIT } from "../adjustments.ts";
import type { GroupTerm } from "../rounds/logic.ts";

export type ChallengeScope = "group" | "all";

export interface ChallengeSetup {
  name: string;
  points: number;
  scope: ChallengeScope;
  /** Runde 1, 2, … av challengen samme kveld. */
  round: number;
}

export const CHALLENGE_DEFAULT: ChallengeSetup = { name: "CP knockout", points: 0.25, scope: "group", round: 1 };
/** Høyst så mange runder av challengen en kveld. */
export const CHALLENGE_MAX_ROUNDS = 9;

export interface ChallengeGroup {
  /** Bås- eller flightnummer; 0 er «hele runden». */
  no: number;
  title: string;
  members: string[];
  reason: string;
}

/** «CP knockout» i runde 1, «CP knockout runde 2» etter. */
export function challengeBase(name: string, round: number): string {
  const n = name.trim();
  return round > 1 ? `${n} runde ${round}` : n;
}

/** Grunnen som lagres: «CP knockout runde 2, bås 1», eller bare navnet for hele runden. Høyst 80 tegn. */
export function challengeReason(name: string, round: number, scope: ChallengeScope, term: GroupTerm, groupNo: number): string {
  const tail = scope === "group" && groupNo > 0 ? `, ${term.singular} ${groupNo}` : "";
  const room = REASON_LIMIT - [...challengeBase("", round)].length - [...tail].length;
  const name80 = [...name.trim()].slice(0, Math.max(1, room)).join("");
  return challengeBase(name80, round) + tail;
}

/**
 * Gruppene som får en vinner hver. Per bås/flight når spillerne er delt i grupper, ellers hele runden
 * som én. Spillere uten gruppe (0) havner i «Uten bås» når de andre har gruppe.
 */
export function challengeGroups(setup: ChallengeSetup, players: readonly { memberID: string; group: number }[], term: GroupTerm): ChallengeGroup[] {
  const grouped = setup.scope === "group" && players.some((p) => p.group > 0);
  if (!grouped) {
    return [{ no: 0, title: "Hele runden", members: players.map((p) => p.memberID), reason: challengeReason(setup.name, setup.round, "all", term, 0) }];
  }
  const by = new Map<number, string[]>();
  for (const p of players) by.set(p.group, [...(by.get(p.group) ?? []), p.memberID]);
  return [...by.entries()].sort((a, b) => (a[0] === 0 ? 1 : b[0] === 0 ? -1 : a[0] - b[0])).map(([no, members]) => ({
    no, members,
    title: no === 0 ? `Uten ${term.singular}` : `${term.singular[0].toUpperCase()}${term.singular.slice(1)} ${no}`,
    reason: challengeReason(setup.name, setup.round, "group", term, no),
  }));
}

/** Navn, poeng og runde må være i orden før noen vinner kan registreres. */
export function challengeProblem(setup: ChallengeSetup): string | null {
  if (setup.name.trim().length === 0) return "Gi challengen et navn.";
  if (!Number.isFinite(setup.points) || setup.points <= 0) return "Vinneren må få mer enn 0 poeng.";
  if (setup.points > 100) return "Høyst 100 poeng av gangen.";
  if (Math.abs(Math.round(setup.points * 100) - setup.points * 100) > 1e-9) return "Poengene kan ha høyst to desimaler.";
  return null;
}

/** Den høyeste runden av challengen som har en vinner for kvelden, eller 0. Så en ny visning fortsetter der dere var. */
export function lastChallengeRound(setup: ChallengeSetup, players: readonly { memberID: string; group: number }[], term: GroupTerm, reasons: readonly string[]): number {
  const have = new Set(reasons);
  let last = 0;
  for (let r = 1; r <= CHALLENGE_MAX_ROUNDS; r++) {
    if (challengeGroups({ ...setup, round: r }, players, term).some((g) => have.has(g.reason))) last = r;
  }
  return last;
}
