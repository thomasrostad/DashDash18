// Kvelden: hva som skjer på banen akkurat nå, regnet fra de lagrede hullene. Ren logikk (testes i
// test/kvelden.test.ts). Ingen nye tabeller: flighten er `round_players.bay_no`, tiden er `hole_scores.recorded_at`.

import type { ScoreName } from "../../../golfgutu-core/src/index.ts";

export interface KvPlayer { memberID: string; name: string; group: number; isMarker: boolean }
export interface KvScore { memberID: string; holeIndex: number; recordedAt: string; scoreName: ScoreName | null }

export interface KvGroup {
  no: number;
  members: string[];
  /** Hull der minst én i gruppa har score. */
  played: number;
  /** Hullet gruppa står på nå (indeks), eller null når gruppa er inne. */
  nextIndex: number | null;
  /** Alle i gruppa har alle hullene. */
  done: boolean;
  /** Sist lagrede hull, ISO-tid. */
  lastAt: string | null;
}

export interface KvGap { memberID: string; group: number; holeIndex: number }

export type KvFeedItem =
  | { kind: "hole"; at: string; group: number; holeIndex: number }
  | { kind: "score"; at: string; memberID: string; holeIndex: number; name: "birdie" | "eagle" }
  | { kind: "in"; at: string; group: number };

export type KvPhase = "for" | "under" | "etter";

const later = (a: string | null, b: string) => (a === null || Date.parse(b) > Date.parse(a) ? b : a);

/** Gruppene (flight eller bås) med hvor de er. Spillere uten bås havner i gruppe 0. */
export function groupsOf(players: readonly KvPlayer[], scores: readonly KvScore[], holeCount: number): KvGroup[] {
  const byGroup = new Map<number, string[]>();
  for (const p of players) byGroup.set(p.group, [...(byGroup.get(p.group) ?? []), p.memberID]);
  const groupOf = new Map(players.map((p) => [p.memberID, p.group]));
  const holesOf = new Map<string, Set<number>>();
  const lastByGroup = new Map<number, { at: string; index: number }>();
  const playedByGroup = new Map<number, Set<number>>();
  for (const s of scores) {
    const g = groupOf.get(s.memberID);
    if (g === undefined || s.holeIndex < 0 || s.holeIndex >= holeCount) continue;
    holesOf.set(s.memberID, (holesOf.get(s.memberID) ?? new Set()).add(s.holeIndex));
    playedByGroup.set(g, (playedByGroup.get(g) ?? new Set()).add(s.holeIndex));
    const last = lastByGroup.get(g);
    if (!last || Date.parse(s.recordedAt) > Date.parse(last.at)) lastByGroup.set(g, { at: s.recordedAt, index: s.holeIndex });
  }
  return [...byGroup.entries()].sort((a, b) => a[0] - b[0]).map(([no, members]) => {
    const played = playedByGroup.get(no) ?? new Set<number>();
    const done = members.every((m) => (holesOf.get(m)?.size ?? 0) >= holeCount);
    const last = lastByGroup.get(no) ?? null;
    let nextIndex: number | null = null;
    if (!done) {
      // Hullet etter det sist lagrede som ikke er spilt; før første hull: der gruppa ikke har noe ennå (0).
      const from = last ? last.index + 1 : 0;
      for (let k = 0; k < holeCount; k++) {
        const i = (from + k) % holeCount;
        if (!played.has(i)) { nextIndex = i; break; }
      }
      if (nextIndex === null) nextIndex = last ? last.index : 0; // alle hull har noe, men noen mangler: bli stående
    }
    return { no, members, played: played.size, nextIndex, done, lastAt: last?.at ?? null };
  });
}

/** Hull som mangler for én spiller mens resten av gruppa har gått videre. Hullet gruppa står på nå teller ikke. */
export function gapsOf(players: readonly KvPlayer[], scores: readonly KvScore[], groups: readonly KvGroup[], holeCount: number): KvGap[] {
  const has = new Set(scores.map((s) => `${s.memberID}:${s.holeIndex}`));
  const groupHoles = new Map<number, Set<number>>();
  const groupOf = new Map(players.map((p) => [p.memberID, p.group]));
  for (const s of scores) {
    const g = groupOf.get(s.memberID);
    if (g !== undefined && s.holeIndex >= 0 && s.holeIndex < holeCount) groupHoles.set(g, (groupHoles.get(g) ?? new Set()).add(s.holeIndex));
  }
  const lastIndex = new Map<number, number>();
  for (const g of groups) {
    const latest = scores.filter((s) => groupOf.get(s.memberID) === g.no).reduce<KvScore | null>((a, s) => (!a || Date.parse(s.recordedAt) > Date.parse(a.recordedAt) ? s : a), null);
    if (latest && !g.done) lastIndex.set(g.no, latest.holeIndex);
  }
  const out: KvGap[] = [];
  for (const p of players) {
    for (const h of [...(groupHoles.get(p.group) ?? [])].sort((a, b) => a - b)) {
      if (h === lastIndex.get(p.group)) continue;
      if (!has.has(`${p.memberID}:${h}`)) out.push({ memberID: p.memberID, group: p.group, holeIndex: h });
    }
  }
  return out;
}

/** Siste hendelser, nyeste først: et lagret hull per gruppe, birdie og eagle, og når en gruppe er inne. */
export function feedOf(players: readonly KvPlayer[], scores: readonly KvScore[], groups: readonly KvGroup[], limit = 8): KvFeedItem[] {
  const groupOf = new Map(players.map((p) => [p.memberID, p.group]));
  const holes = new Map<string, { group: number; holeIndex: number; at: string; best: KvScore | null }>();
  const rank = (n: ScoreName | null) => (n === "eagle" ? 2 : n === "birdie" ? 1 : 0);
  for (const s of scores) {
    const g = groupOf.get(s.memberID);
    if (g === undefined) continue;
    const key = `${g}:${s.holeIndex}`;
    const cur = holes.get(key) ?? { group: g, holeIndex: s.holeIndex, at: s.recordedAt, best: null };
    cur.at = later(cur.at, s.recordedAt);
    if (rank(s.scoreName) > rank(cur.best?.scoreName ?? null)) cur.best = s;
    holes.set(key, cur);
  }
  const items: KvFeedItem[] = [...holes.values()].map((h) => (h.best && (h.best.scoreName === "birdie" || h.best.scoreName === "eagle")
    ? { kind: "score", at: h.at, memberID: h.best.memberID, holeIndex: h.holeIndex, name: h.best.scoreName }
    : { kind: "hole", at: h.at, group: h.group, holeIndex: h.holeIndex }));
  for (const g of groups) if (g.done && g.lastAt) items.push({ kind: "in", at: g.lastAt, group: g.no });
  // «Inne» kommer foran hullet som avsluttet gruppa når tiden er den samme.
  return items.sort((a, b) => Date.parse(b.at) - Date.parse(a.at) || (a.kind === "in" ? -1 : b.kind === "in" ? 1 : 0)).slice(0, limit);
}

/** Før (ingen score ennå), under (noen spiller), etter (alle er inne, runden er ikke låst). */
export function phaseOf(scores: readonly KvScore[], groups: readonly KvGroup[]): KvPhase {
  if (scores.length === 0) return "for";
  return groups.length > 0 && groups.every((g) => g.done) ? "etter" : "under";
}

/** «18.42» i norsk tid. */
export function clockText(iso: string): string {
  const d = new Date(iso);
  return `${String(d.getHours()).padStart(2, "0")}.${String(d.getMinutes()).padStart(2, "0")}`;
}
