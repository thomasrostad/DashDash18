// Felles for testene: fixturene leses rett fra Swift-pakken (ingen kopi), og goldenfilene fra
// Fixtures/golden (skrevet av Swift-testen GoldenTests med GOLDEN_WRITE=1).

import { readFileSync } from "node:fs";
import { decodeMatch, makeRound, type Course, type HoleScores, type Round } from "../src/models.ts";

const FIXTURES = new URL("../../../Packages/GolfgutuCore/Tests/GolfgutuCoreTests/Fixtures/", import.meta.url);

/** Rå JSON fra en fixture (`navn` uten `.json`). */
export function fixture(name: string): any {
  return JSON.parse(readFileSync(new URL(`${name}.json`, FIXTURES), "utf8"));
}

/** Teksten i en fixture, byte for byte. */
export function fixtureText(name: string): string {
  return readFileSync(new URL(`${name}.json`, FIXTURES), "utf8");
}

/** En goldenfil fra Swift-motoren. */
export function golden(name: string): any {
  return JSON.parse(readFileSync(new URL(`golden/${name}.json`, FIXTURES), "utf8"));
}

/** `Map` → objekt, for å sammenligne med JSON. */
export function obj<V>(m: ReadonlyMap<string | number, V> | null | undefined): Record<string, V> | null {
  if (m === null || m === undefined) return null;
  const out: Record<string, V> = {};
  for (const [k, v] of m) out[String(k)] = v;
  return out;
}

/** Objekt → `Map<string, V>`. */
export function map<V>(o: Record<string, V>): Map<string, V> {
  return new Map(Object.entries(o));
}

// MARK: Stableford-tabellen (StablefordTableTests.swift)

/** 18 hull par 4, stroke index 1–18, slope 113 og CR = par: handicap 0 gir 0 slag. */
export const TEST_COURSE: Course = {
  id: "bane", name: "Testbanen", par: 72, courseRating: 72, slopeRating: 113,
  holes: Array.from({ length: 18 }, (_, i) => ({ par: 4, si: i + 1, meters: null })),
};

/** Scorer som gir `points` stablefordpoeng med handicap 0. */
export function scoresFor(points: number): HoleScores {
  const perHole = Array(18).fill(2);
  let rest = points - 36;
  let i = 0;
  while (rest !== 0) {
    if (rest > 0 && perHole[i] < 4) { perHole[i]++; rest--; } else if (rest < 0 && perHole[i] > 0) { perHole[i]--; rest++; } else i++;
  }
  return new Map(perHole.map((p, h) => [h, 6 - p]));
}

export function stablefordRounds(fil: any): Round[] {
  return (fil.runder as any[]).map((r) => makeRound({
    id: r.id, gameType: "stableford", holeCount: 18, holeStart: 0, course: TEST_COURSE, hcpAllowance: 1,
    holeScores: new Map(Object.entries(r.poeng as Record<string, number>).map(([k, v]) => [k, scoresFor(v)])),
    matches: ((r.matcher ?? []) as any[]).map((m) => decodeMatch(m)),
    weight: r.vekt, date: r.dato, locked: true,
  }));
}

