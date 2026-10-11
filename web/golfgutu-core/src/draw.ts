// Trekningsvalgene for matcher og lag (Draw.swift, steg 6, `formats.drawMethod`): etter tabellen
// (`drawMatches` i triangle.ts), uten gjentakelser (`avoidingRepeats`, gjentakbar med et frø) og manuelt
// (`validateDraw`). Tilfeldige lag og bytte av to spillere (`randomTeams`, `swapTeams`).

import { SplitMix64 } from "./competitions.ts";
import { allInMatch, matchSides } from "./match.ts";
import { isTriangle, type Player, type Round } from "./models.ts";

/** Nøkkelen for et møte mellom to spillere: id-ene sortert, med «|» mellom. */
export function pairKey(a: string, b: string): string {
  return a < b ? `${a}|${b}` : `${b}|${a}`;
}

/** Legger gruppenes møter til (alle i en gruppe møter hverandre). */
export function addMeetings(groups: readonly (readonly string[])[], meetings: Map<string, number>): void {
  for (const g of groups) {
    for (let i = 0; i < g.length; i++) {
      for (let j = i + 1; j < g.length; j++) {
        const k = pairKey(g[i], g[j]);
        meetings.set(k, (meetings.get(k) ?? 0) + 1);
      }
    }
  }
}

/** Hvor mange ganger hvert par har møtt hverandre i rundenes matcher (alle rundene). */
export function meetings(rounds: readonly Round[]): Map<string, number> {
  const out = new Map<string, number>();
  for (const round of rounds) {
    for (const m of round.matches) {
      const s = matchSides(m, round);
      if (isTriangle(m)) {
        addMeetings([allInMatch(s)], out);
        continue;
      }
      for (const a of s.a) {
        for (const b of s.b) {
          if (a === b) continue;
          const k = pairKey(a, b);
          out.set(k, (out.get(k) ?? 0) + 1);
        }
      }
    }
  }
  return out;
}

function cost(group: readonly string[], previous: ReadonlyMap<string, number>): number {
  let c = 0;
  for (let i = 0; i < group.length; i++) {
    for (let j = i + 1; j < group.length; j++) c += previous.get(pairKey(group[i], group[j])) ?? 0;
  }
  return c;
}

/** Antall møter i gruppene som har vært før. */
export function repeats(groups: readonly (readonly string[])[], previous: ReadonlyMap<string, number>): number {
  return groups.reduce((s, g) => s + cost(g, previous), 0);
}

/** Id-ene sortert, så stokket med Fisher–Yates bakfra og SplitMix64 (som cupens trekning). */
export function shuffledIDs(ids: readonly string[], seed: bigint | number): string[] {
  const out = [...ids].sort((a, b) => (a < b ? -1 : a > b ? 1 : 0));
  const rng = new SplitMix64(seed);
  for (let i = out.length - 1; i >= 1; i--) {
    const j = Number(rng.next() % BigInt(i + 1));
    [out[i], out[j]] = [out[j], out[i]];
  }
  return out;
}

/**
 * Tilfeldig trekning med færrest mulig møter som har vært før: stokk med frøet, grådig (den første uten
 * motstander får den ledige den har møtt færrest ganger; med oddetall blir de tre siste en trekant), så
 * bytt to spillere i ulike grupper så lenge det gir færre gjentakelser. Under to deltakere: ingen matcher.
 */
export function avoidingRepeats(participants: readonly Player[], previous: ReadonlyMap<string, number>, seed: bigint | number): string[][] {
  const order = shuffledIDs(participants.map((p) => p.id), seed);
  if (order.length < 2) return [];
  const free = [...order];
  const groups: string[][] = [];
  while (free.length > 0) {
    if (free.length === 3 && order.length % 2 === 1) {
      groups.push([...free]);
      break;
    }
    const x = free.shift()!;
    let best = 0;
    for (let k = 0; k < free.length; k++) {
      if ((previous.get(pairKey(x, free[k])) ?? 0) < (previous.get(pairKey(x, free[best])) ?? 0)) best = k;
    }
    groups.push([x, free.splice(best, 1)[0]]);
  }
  let improved = true;
  while (improved) {
    improved = false;
    for (let g1 = 0; g1 < groups.length; g1++) {
      for (let g2 = g1 + 1; g2 < groups.length; g2++) {
        for (let i = 0; i < groups[g1].length; i++) {
          for (let j = 0; j < groups[g2].length; j++) {
            const a = [...groups[g1]];
            const b = [...groups[g2]];
            [a[i], b[j]] = [b[j], a[i]];
            if (cost(a, previous) + cost(b, previous) < cost(groups[g1], previous) + cost(groups[g2], previous)) {
              groups[g1] = a;
              groups[g2] = b;
              improved = true;
            }
          }
        }
      }
    }
  }
  return groups;
}

/** Et problem i en manuell trekning (`DrawIssue`). */
export type DrawIssue =
  | { kind: "unknownPlayer"; id: string }
  | { kind: "duplicate"; id: string }
  | { kind: "missing"; id: string }
  | { kind: "groupSize"; index: number; size: number }
  | { kind: "triangles"; count: number };

/** Språknøytral kode: `ukjent:X`, `dobbel:X`, `mangler:X`, `gruppe:i:n`, `trekanter:n`. */
export function drawIssueCode(i: DrawIssue): string {
  switch (i.kind) {
    case "unknownPlayer": return `ukjent:${i.id}`;
    case "duplicate": return `dobbel:${i.id}`;
    case "missing": return `mangler:${i.id}`;
    case "groupSize": return `gruppe:${i.index}:${i.size}`;
    case "triangles": return `trekanter:${i.count}`;
  }
}

/** Norsk melding til arrangøren. */
export function drawIssueMessage(i: DrawIssue): string {
  switch (i.kind) {
    case "unknownPlayer": return `${i.id} er ikke med denne kvelden.`;
    case "duplicate": return `${i.id} står i mer enn én match.`;
    case "missing": return `${i.id} har ingen match.`;
    case "groupSize": return `Match ${i.index + 1} har ${i.size} spillere. En match har to, en trekant tre.`;
    case "triangles":
      return i.count === 0
        ? "Med oddetall spillere må én match være en trekant."
        : `Det kan bare være én trekant, og bare med oddetall spillere (nå ${i.count}).`;
  }
}

/** Sjekker en manuell trekning (`Draw.validate`). Tom liste: i orden. */
export function validateDraw(groups: readonly (readonly string[])[], participants: readonly string[]): DrawIssue[] {
  const issues: DrawIssue[] = [];
  const known = new Set(participants);
  const seen = new Set<string>();
  const reported = new Set<string>();
  groups.forEach((g, index) => {
    if (g.length !== 2 && g.length !== 3) issues.push({ kind: "groupSize", index, size: g.length });
    for (const id of g) {
      if (!known.has(id)) {
        if (!reported.has(id)) {
          reported.add(id);
          issues.push({ kind: "unknownPlayer", id });
        }
      } else if (seen.has(id)) {
        if (!reported.has(id)) {
          reported.add(id);
          issues.push({ kind: "duplicate", id });
        }
      } else {
        seen.add(id);
      }
    }
  });
  for (const id of participants) if (!seen.has(id)) issues.push({ kind: "missing", id });
  const triangles = groups.filter((g) => g.length === 3).length;
  if (triangles !== participants.length % 2) issues.push({ kind: "triangles", count: triangles });
  return issues;
}

/** Tilfeldige lag med `teamSize` spillere (`Teams.random`): spiller-id → lagnummer (1, 2, …). */
export function randomTeams(playerIDs: readonly string[], teamSize: number, seed: bigint | number): Map<string, number> {
  const size = Math.max(1, teamSize);
  const out = new Map<string, number>();
  shuffledIDs(playerIDs, seed).forEach((id, i) => out.set(id, Math.floor(i / size) + 1));
  return out;
}

/** Bytter lagene til to spillere (`Teams.swap`). Uendret når en mangler lag eller de er på samme lag. */
export function swapTeams(teams: ReadonlyMap<string, number>, a: string, b: string): Map<string, number> {
  const out = new Map(teams);
  const ta = teams.get(a);
  const tb = teams.get(b);
  if (ta === undefined || tb === undefined || ta === tb) return out;
  out.set(a, tb);
  out.set(b, ta);
  return out;
}
