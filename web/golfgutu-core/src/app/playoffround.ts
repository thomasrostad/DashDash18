// Playoff-runden og de skjulte hullene slik databasen lagrer dem (sql/047):
//
// * `rounds.playoff_holes[i]` er rundehullet (0-basert) som spilles som playoff-hull nummer i, og samme hull
//   kan stå flere ganger (forslaget er siste, første, siste).
// * Scoren for playoff-hull nummer i lagres med `hole_index = i`, altså posisjonen, ikke banehullet.
//
// Her er oversettelsen til regelmotoren (`decidePlayoff`, `hidingLastHoles`) og vinneren til tabellen.

import { courseHoles } from "../course.ts";
import { decidePlayoff, hiddenHoleIndices, type PlayoffDecision } from "../playoff.ts";
import type { Ruleset } from "../ruleset.ts";
import type { Standing } from "../season.ts";
import { makeRoundFromSnapshot, snapshotRoster, type RoundSnapshot } from "./roundgame.ts";
import { isPlayoff, type RoundRow, type UUID } from "./rows.ts";

/** Ett playoff-hull: posisjonen (0-basert, = `hole_index` i `hole_scores`) og rundehullet med par og indeks. */
export interface PlayoffHole {
  position: number;
  /** Rundens 0-baserte hull. */
  holeIndex: number;
  par: number;
  strokeIndex: number;
}

/** Playoff-hullene med par og indeks fra banen (`playoff_holes[i]`). Tom for en vanlig runde. */
export function playoffHoles(s: RoundSnapshot): PlayoffHole[] {
  const holes = s.round.playoffHoles ?? [];
  if (!isPlayoff(s.round) || holes.length === 0) return [];
  const course = courseHoles(makeRoundFromSnapshot(s));
  return holes.map((h, position) => ({
    position,
    holeIndex: h,
    par: course[h]?.par ?? 0,
    strokeIndex: course[h]?.strokeIndex ?? 0,
  }));
}

/** Bruttoslag per spiller i rekkefølgen hullene spilles (posisjon 0, 1, …), til første posisjon uten score. */
export function playoffScores(s: RoundSnapshot): Map<string, number[]> {
  const byMember = new Map<string, Map<number, number>>();
  for (const row of s.scores) {
    const m = byMember.get(row.memberID) ?? new Map<number, number>();
    m.set(row.holeIndex, row.strokes);
    byMember.set(row.memberID, m);
  }
  const out = new Map<string, number[]>();
  for (const [id, m] of byMember) {
    const list: number[] = [];
    while (m.has(list.length)) list.push(m.get(list.length)!);
    out.set(id, list);
  }
  return out;
}

/** `Playoff.decide` for playoff-runden. `players`: de som står likt øverst; mangler de, rundens spillere. */
export function decidePlayoffRound(s: RoundSnapshot, players: readonly string[] | null = null, rules: Ruleset = s.rules): PlayoffDecision {
  const inRound = s.players.map((p) => p.memberID);
  const chosen = players === null ? inRound : players.filter((id) => inRound.includes(id));
  return decidePlayoff(chosen.length > 0 ? chosen : inRound, s.round.playoffHoles ?? [], playoffScores(s),
    makeRoundFromSnapshot(s), snapshotRoster(s), rules);
}

/** Den nyeste playoff-runden for turneringen (`playoff_for`), aktiv eller låst. */
export function latestPlayoff(snapshots: readonly RoundSnapshot[], competitionID: UUID | null = null): RoundSnapshot | null {
  const id = competitionID?.toLowerCase() ?? null;
  const mine = snapshots.filter((s) => isPlayoff(s.round) && s.round.status !== "draft" &&
    (id === null || s.round.playoffFor === null || s.round.playoffFor === id));
  // Høyest rundenummer på siste dato vinner; uten dato (løs playoff) den siste i lista.
  let best: RoundSnapshot | null = null;
  for (const s of mine) {
    if (best === null) { best = s; continue; }
    const a = best.eventDate ?? "";
    const b = s.eventDate ?? "";
    if (b > a || (b === a && s.round.roundNo >= best.round.roundNo)) best = s;
  }
  return best;
}

/**
 * Vinneren av playoffen om førsteplassen, til `Season.standings(playoffWinner:)`. `standings` er tabellen
 * uten vinner; gruppa er de med `playoffPending`. `null` når ingen playoff venter eller den ikke er avgjort.
 */
export function playoffWinner(standings: readonly Standing[], playoffs: readonly RoundSnapshot[], competitionID: UUID | null = null): string | null {
  const group = standings.filter((s) => s.playoffPending).map((s) => s.row.player.id);
  if (group.length < 2) return null;
  const playoff = latestPlayoff(playoffs, competitionID);
  if (playoff === null) return null;
  const decision = decidePlayoffRound(playoff, group);
  return decision.kind === "won" && group.includes(decision.winner) ? decision.winner : null;
}

/** Skjules de siste hullene i runden nå? Bare mens runden ikke er låst. */
export function hidesLastHoles(round: Pick<RoundRow, "hideLastHoles" | "status">): boolean {
  return round.status !== "locked" && round.hideLastHoles > 0;
}

/** Notisen under tavla når hull er skjult. */
export const HIDDEN_HOLES_NOTE = "De siste hullene vises når runden er låst";

/** De skjulte rundehullene nå (0-basert), som `hiddenHoleIndices`. */
export function hiddenHoles(s: RoundSnapshot): number[] {
  return hiddenHoleIndices(makeRoundFromSnapshot(s));
}
