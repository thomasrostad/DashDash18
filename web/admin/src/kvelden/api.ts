// Henter det Kvelden trenger. Bare lesing, med samme kall og tilganger som rundesiden (RLS).

import { GOLFGUTU } from "../../../golfgutu-core/src/index.ts";
import type { Competition, EventRow } from "../data.ts";
import { supabase } from "../supabase.ts";
import { activeRounds, loadDay, loadGame, rulesFor, type ListRound } from "../rounds/api.ts";
import { roundTable, type RoundGame, type RoundTable } from "../rounds/game.ts";
import { dataErrorText, groupTerm, venueFromStored, type GroupTerm } from "../rounds/logic.ts";
import type { KvPlayer, KvScore } from "./model.ts";

export interface LiveRound {
  round: ListRound;
  event: EventRow | null;
  competition: Competition | null;
  game: RoundGame;
  table: RoundTable;
  players: KvPlayer[];
  scores: KvScore[];
  term: GroupTerm;
}

export interface NextDay {
  event: EventRow;
  competition: Competition | null;
  signups: number;
  waitlisted: number;
  /** Runden for dagen som ikke er startet, hvis den finnes. */
  draft: { courseChosen: boolean; players: number; grouped: number } | null;
}

/** Den aktive runden som startet sist, med hull, tabell og når hvert hull ble lagret. Null: ingen aktiv runde. */
export async function loadLive(clubID: string, days: readonly EventRow[], comps: readonly Competition[]): Promise<LiveRound | null> {
  const active = await activeRounds(clubID);
  if (active.length === 0) return null;
  const round = [...active].sort((a, b) => Date.parse(b.startedAt ?? "") - Date.parse(a.startedAt ?? "") || b.roundNo - a.roundNo)[0];
  const event = days.find((d) => d.id === round.eventID) ?? null;
  const competition = event?.competition_id ? comps.find((c) => c.id === event.competition_id) ?? null : null;
  const rules = event ? await rulesFor(clubID, event, comps) : GOLFGUTU;
  const [game, timed] = await Promise.all([
    loadGame(round.id, rules),
    supabase.from("hole_scores").select("member_id, hole_index, recorded_at").eq("round_id", round.id),
  ]);
  if (timed.error) throw new Error(dataErrorText(timed.error));
  const table = roundTable(game);
  const names = new Map(table.rows.flatMap((r) => r.cells.map((c) => [`${r.memberID}:${c.index}`, c.scoreName] as const)));
  const scores = ((timed.data ?? []) as { member_id: string; hole_index: number; recorded_at: string }[]).map((s) => ({
    memberID: s.member_id, holeIndex: s.hole_index, recordedAt: s.recorded_at, scoreName: names.get(`${s.member_id}:${s.hole_index}`) ?? null,
  }));
  const players = game.snapshot.players.map((p) => ({ memberID: p.memberID, name: game.name(p.memberID), group: p.bayNo ?? 0, isMarker: p.isMarker }));
  return { round, event, competition, game, table, players, scores, term: groupTerm(venueFromStored(round.venue)) };
}

/** Neste spilledag (i dag eller senere) med påmelding og hvor langt oppsettet har kommet. */
export async function loadNextDay(clubID: string, days: readonly EventRow[], comps: readonly Competition[], today: string): Promise<NextDay | null> {
  const event = [...days].filter((d) => d.event_date >= today).sort((a, b) => a.event_date.localeCompare(b.event_date))[0];
  if (!event) return null;
  const competition = event.competition_id ? comps.find((c) => c.id === event.competition_id) ?? null : null;
  const day = await loadDay(clubID, event, comps);
  const coming = day.signups.filter((s) => s.status === "yes");
  const draftRound = day.allRounds.find((r) => r.eventID === event.id && r.status === "draft") ?? null;
  const seated = draftRound ? day.players.get(draftRound.id) ?? [] : [];
  return {
    event, competition,
    signups: coming.filter((s) => !s.waitlisted_at).length,
    waitlisted: coming.filter((s) => !!s.waitlisted_at).length,
    draft: draftRound ? { courseChosen: draftRound.courseID !== null, players: seated.length, grouped: seated.filter((p) => p.bayNo !== null).length } : null,
  };
}
