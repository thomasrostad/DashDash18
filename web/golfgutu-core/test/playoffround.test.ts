// sql/047 i app-mappingen: de nye kolonnene på runden (med standardverdier når de mangler), playoff-runden
// (hole_index = posisjon, playoff_holes[i] = rundehullet) og vinneren inn i tabellen.

import assert from "node:assert/strict";
import { test } from "node:test";
import { CompetitionScope, type CompetitionRow } from "../src/app/competition.ts";
import {
  decidePlayoffRound,
  hiddenHoles,
  hidesLastHoles,
  latestPlayoff,
  playoffHoles,
  playoffScores,
} from "../src/app/playoffround.ts";
import { makeRoundFromSnapshot } from "../src/app/roundgame.ts";
import { decodeRoundRow, decodeSeasonRow, decodeTavlaData, isPlayoff } from "../src/app/rows.ts";
import { tavlaInput, TavlaStandings } from "../src/app/tavla.ts";

const CLUB = "c0000000-0000-0000-0000-000000000001";
const SEASON = "50000000-0000-0000-0000-000000000001";
const COURSE = "b0000000-0000-0000-0000-000000000001";
const A = "a0000000-0000-0000-0000-00000000000a";
const B = "a0000000-0000-0000-0000-00000000000b";
const C = "a0000000-0000-0000-0000-00000000000c";

function roundJSON(id: string, extra: Record<string, unknown> = {}) {
  return {
    id, club_id: CLUB, event_id: "e1", course_id: COURSE, round_no: 1, name: null, status: "locked", hole_count: 18,
    first_hole: 1, tee_time: null, format: "stableford", handicap_allowance: 1, external_handicap: false, weight: 1,
    ld_enabled: false, ld_hole_index: null, kp_enabled: false, kp_hole_index: null, cut_rule: null, cut_after: null,
    ...extra,
  };
}

test("rundens nye kolonner: standardverdier uten 047", () => {
  const r = decodeRoundRow(roundJSON("r1"));
  assert.equal(r.counts, true);
  assert.equal(r.pointsTable, null);
  assert.equal(r.hideLastHoles, 0);
  assert.equal(r.kind, "normal");
  assert.equal(r.playoffFor, null);
  assert.equal(r.playoffHoles, null);
  assert.equal(isPlayoff(r), false);
});

test("rundens nye kolonner: lest og sendt til motoren", () => {
  const r = decodeRoundRow(roundJSON("R1", { counts: false, points_table: "finale", hide_last_holes: 3, kind: "playoff",
    playoff_for: SEASON.toUpperCase(), playoff_holes: [17, 0, 17] }));
  assert.equal(r.counts, false);
  assert.equal(r.pointsTable, "finale");
  assert.equal(r.hideLastHoles, 3);
  assert.equal(r.kind, "playoff");
  assert.equal(r.playoffFor, SEASON);
  assert.deepEqual(r.playoffHoles, [17, 0, 17]);
  const round = makeRoundFromSnapshot({ round: r, roundHoles: [], players: [], matches: [], scores: [], sideClaims: [], course: null, courseHoles: [], eventDate: null, rules: decodeSeasonRow(seasonJSON()).rules, names: new Map() });
  assert.equal(round.counts, false);
  assert.equal(round.pointsTable, "finale");
  assert.equal(round.hideLastHoles, 3);
  assert.throws(() => decodeRoundRow(roundJSON("r", { playoff_holes: [1.5] })));
});

function seasonJSON() {
  return { id: SEASON, club_id: CLUB, name: "Sesong", status: "active",
    rules: { version: 2, table: { pointsSource: "stableford", counting: { unit: "evening", best: null }, roundingStep: null, tieRule: "playoff" } } };
}

const courseHoles = Array.from({ length: 18 }, (_, i) => ({ course_id: COURSE, hole_number: i + 1, par: i === 0 ? 5 : 4, stroke_index: i + 1, length_m: null }));

function score(round: string, member: string, hole: number, strokes: number) {
  return { round_id: round, member_id: member, hole_index: hole, strokes };
}

function data(playoff: Record<string, unknown> | null, playoffScores: ReturnType<typeof score>[]) {
  const normal = Array.from({ length: 18 }, (_, i) => [score("r1", A, i, 4), score("r1", B, i, 4), score("r1", C, i, 5)]).flat();
  const rounds = [roundJSON("r1")];
  const players = [A, B, C].map((m) => ({ round_id: "r1", member_id: m, club_id: CLUB, handicap_index: 0, playing_handicap: 0 }));
  if (playoff !== null) {
    rounds.push(roundJSON("p1", { round_no: 2, name: "Playoff", counts: false, kind: "playoff", playoff_for: SEASON, ...playoff }));
    players.push(...[A, B].map((m) => ({ round_id: "p1", member_id: m, club_id: CLUB, handicap_index: 0, playing_handicap: 0 })));
  }
  return decodeTavlaData({
    events: [{ id: "e1", club_id: CLUB, season_id: SEASON, event_date: "2026-05-01" }],
    members: [A, B, C].map((id, i) => ({ id, club_id: CLUB, display_name: ["Anne", "Bjørn", "Cato"][i], status: "active" })),
    rounds, players, courses: [{ id: COURSE, club_id: CLUB, name: "Banen" }], course_holes: courseHoles,
    scores: [...normal, ...playoffScores],
  });
}

test("playoff: venter uten playoff-runde, og runden står ikke i tabellen", () => {
  const t = new TavlaStandings(tavlaInput(data(null, []), decodeSeasonRow(seasonJSON())));
  assert.deepEqual(t.rows.slice(0, 2).map((r) => [r.place, r.playoffPending]), [[1, true], [1, true]]);
  assert.equal(t.playoffWinner, null);
});

test("playoff: posisjon, hull og vinner inn i tabellen", () => {
  const d = data({ playoff_holes: [17, 0, 17] }, [score("p1", A, 0, 4), score("p1", B, 0, 4), score("p1", B, 1, 6), score("p1", A, 1, 5)]);
  const input = tavlaInput(d, decodeSeasonRow(seasonJSON()));
  assert.equal(input.rounds.length, 1);
  assert.equal(input.playoffs?.length, 1);
  const p = input.playoffs![0];
  assert.deepEqual(playoffHoles(p).map((h) => [h.position, h.holeIndex, h.par, h.strokeIndex]), [[0, 17, 4, 18], [1, 0, 5, 1], [2, 17, 4, 18]]);
  assert.deepEqual(playoffScores(p).get(A), [4, 5]);
  assert.deepEqual(decidePlayoffRound(p, [A, B]), { kind: "won", winner: A, position: 1 });

  const t = new TavlaStandings(input);
  assert.equal(t.playoffWinner, A);
  assert.equal(t.snapshots.length, 1, "playoffen står ikke i «Alle runder»");
  assert.deepEqual(t.rows.map((r) => [r.memberID, r.place, r.playoffPending]), [[A, 1, false], [B, 2, false], [C, 3, false]]);
});

test("playoff: uavgjort så langt står som ventende", () => {
  const d = data({ playoff_holes: [17] }, [score("p1", A, 0, 4), score("p1", B, 0, 4)]);
  const input = tavlaInput(d, decodeSeasonRow(seasonJSON()));
  assert.deepEqual(decidePlayoffRound(input.playoffs![0], [A, B]), { kind: "pending", remaining: [A, B], next: null });
  const t = new TavlaStandings(input);
  assert.equal(t.playoffWinner, null);
  assert.ok(t.rows.slice(0, 2).every((r) => r.playoffPending));
});

test("konkurranse: playoff kobles med playoff_for, aldri som tellende runde", () => {
  const d = data({ playoff_holes: [17, 0] }, [score("p1", A, 0, 3), score("p1", B, 0, 4)]);
  const all = tavlaInput(d, decodeSeasonRow(seasonJSON()));
  const competition = { id: SEASON, clubID: CLUB, seasonID: null, name: "Sesong", kind: "season", status: "active", entry: "club",
    rules: all.season.rules } as unknown as CompetitionRow;
  const scope = new CompetitionScope(competition, [{ competitionID: SEASON, roundID: "r1" }, { competitionID: SEASON, roundID: "p1" }] as any);
  const candidates = [...all.rounds, ...all.playoffs!];
  assert.deepEqual(scope.countedRounds(candidates).map((s) => s.round.id), ["r1"]);
  const input = scope.tavlaInput(d.members, candidates)!;
  assert.equal(input.playoffs!.length, 1);
  assert.equal(new TavlaStandings(input).playoffWinner, A);
  assert.equal(latestPlayoff(candidates, "00000000-0000-0000-0000-000000000000"), null);
});

test("skjulte hull: bare mens runden ikke er låst", () => {
  const active = decodeRoundRow(roundJSON("r", { status: "active", hide_last_holes: 3 }));
  assert.equal(hidesLastHoles(active), true);
  assert.equal(hidesLastHoles({ ...active, status: "locked" }), false);
  assert.equal(hidesLastHoles({ ...active, hideLastHoles: 0 }), false);
  const s = { round: active, roundHoles: [], players: [], matches: [], scores: [], sideClaims: [], course: null, courseHoles: [], eventDate: null, rules: decodeSeasonRow(seasonJSON()).rules, names: new Map() };
  assert.deepEqual(hiddenHoles(s), [15, 16, 17]);
});
