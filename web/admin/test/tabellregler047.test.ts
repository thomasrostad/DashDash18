// sql/047 i web-admin: tabellreglene på runden (skrives bare når kolonnene finnes), playoffen holdes
// utenfor det som teller, og «Tabeller» viser og avgjør playoffen om førsteplassen.

import { test } from "node:test";
import assert from "node:assert/strict";
import { decodeRuleset, golfgutuRules } from "../../golfgutu-core/src/index.ts";
import {
  blockingRound, HIDE_LAST_HOLES, newDraft, ordinaryRounds, pointsTableChoices, roundWrite, savedDraft, tableRulesPatch,
} from "../src/rounds/logic.ts";
import { competitionData, parsePlayoffHoles, playoffHoleNumbers, seasonView, type CompetitionRaw } from "../src/standings/model.ts";

const id = (n: number) => `00000000-0000-0000-0000-${String(n).padStart(12, "0")}`;
const rules = decodeRuleset({ version: 2, table: { pointsSource: "stableford", counting: { unit: "evening", best: null }, roundingStep: null,
  pointsTables: { finale: { multiplier: 2 }, dobbel: { multiplier: 1.5 } }, tieRule: "playoff" } });

test("runden: tabellreglene skrives bare med 047", () => {
  const d = newDraft({ roundID: id(1), eventID: id(2), roundNo: 1, teeTime: null, participants: [], source: "signups", rules: golfgutuRules() });
  assert.deepEqual([d.counts, d.pointsTable, d.hideLastHoles], [true, null, 0]);
  const old = roundWrite(d, id(3), null);
  assert.equal("counts" in old, false);
  assert.equal("points_table" in old, false);
  assert.equal("hide_last_holes" in old, false);
  const w = roundWrite({ ...d, counts: false, pointsTable: "finale", hideLastHoles: HIDE_LAST_HOLES }, id(3), null, true);
  assert.deepEqual([w.counts, w.points_table, w.hide_last_holes], [false, "finale", 3]);
  assert.deepEqual(tableRulesPatch({ counts: true, pointsTable: "  ", hideLastHoles: 12 }), { counts: true, points_table: null, hide_last_holes: 9 });
});

test("runden: lagret kladd uten 047 får standardverdiene", () => {
  const base = { id: id(1), eventID: id(2), roundNo: 1, courseID: null, teeID: null, holeCount: 18, firstHole: 1, teeTime: null,
    format: "stableford", handicapAllowance: 1, externalHandicap: false, weight: 1, ldEnabled: false, ldHoleIndex: null,
    kpEnabled: false, kpHoleIndex: null, venue: null };
  const d = savedDraft(base, [], [], [], "signups");
  assert.deepEqual([d.counts, d.pointsTable, d.hideLastHoles], [true, null, 0]);
  const e = savedDraft({ ...base, counts: false, pointsTable: "finale", hideLastHoles: 3 }, [], [], [], "signups");
  assert.deepEqual([e.counts, e.pointsTable, e.hideLastHoles], [false, "finale", 3]);
});

test("poengtabell: «Vanlig» først, så regelsettets tabeller", () => {
  assert.deepEqual(pointsTableChoices(rules), [
    { value: null, title: "Vanlig" }, { value: "dobbel", title: "Dobbel (× 1,5)" }, { value: "finale", title: "Finale (× 2)" },
  ]);
  assert.deepEqual(pointsTableChoices(golfgutuRules()), [{ value: null, title: "Vanlig" }]);
  assert.deepEqual(pointsTableChoices(golfgutuRules(), "borte").map((c) => c.title), ["Vanlig", "Borte"]);
});

test("playoff: stopper ingen runde og står ikke blant de vanlige", () => {
  const rounds = [{ id: "p", eventID: "e", waveNo: 1, kind: "playoff" }, { id: "r", eventID: "e", waveNo: 1, kind: "normal" }];
  assert.equal(blockingRound([rounds[0]], "ny", "e", 1), null);
  assert.equal(blockingRound(rounds, "ny", "e", 1)?.id, "r");
  assert.deepEqual(ordinaryRounds(rounds).map((r) => r.id), ["r"]);
});

test("playoff: hullene som tekst", () => {
  assert.equal(playoffHoleNumbers([17, 0, 17]), "18, 1, 18");
  assert.equal(playoffHoleNumbers([8, 0], 10), "18, 10");
  assert.deepEqual(parsePlayoffHoles("18, 1 18", 18), [17, 0, 17]);
  assert.deepEqual(parsePlayoffHoles("18,10", 9, 10), [8, 0]);
  assert.equal(parsePlayoffHoles("19", 18), null);
  assert.equal(parsePlayoffHoles("", 18), null);
  assert.equal(parsePlayoffHoles("a", 18), null);
});

// MARK: Tabeller

const CLUB = id(100), SEASON = id(101), COURSE = id(102), A = id(11), B = id(12), C = id(13);
const roundJSON = (rid: string, extra: Record<string, unknown> = {}) => ({
  id: rid, club_id: CLUB, event_id: id(200), course_id: COURSE, round_no: 1, name: null, status: "locked", hole_count: 18,
  first_hole: 1, tee_time: null, format: "stableford", handicap_allowance: 1, external_handicap: false, weight: 1,
  ld_enabled: false, ld_hole_index: null, kp_enabled: false, kp_hole_index: null, cut_rule: null, cut_after: null, ...extra,
});
const score = (r: string, m: string, h: number, s: number) => ({ round_id: r, member_id: m, hole_index: h, strokes: s });
const R1 = id(301), P1 = id(302);

function tavlaData(playoff: Record<string, unknown> | null, playoffScores: ReturnType<typeof score>[] = []) {
  const rounds = [roundJSON(R1)];
  const players = [A, B, C].map((m) => ({ round_id: R1, member_id: m, club_id: CLUB, handicap_index: 0, playing_handicap: 0 }));
  if (playoff) {
    rounds.push(roundJSON(P1, { round_no: 2, name: "Playoff", counts: false, kind: "playoff", playoff_for: SEASON, ...playoff }));
    players.push(...[A, B].map((m) => ({ round_id: P1, member_id: m, club_id: CLUB, handicap_index: 0, playing_handicap: 0 })));
  }
  return {
    events: [{ id: id(200), club_id: CLUB, season_id: SEASON, event_date: "2026-05-01" }],
    members: [A, B, C].map((m, i) => ({ id: m, club_id: CLUB, display_name: ["Anne", "Bjørn", "Cato"][i], status: "active" })),
    rounds, players, courses: [{ id: COURSE, club_id: CLUB, name: "Banen" }],
    course_holes: Array.from({ length: 18 }, (_, i) => ({ course_id: COURSE, hole_number: i + 1, par: 4, stroke_index: i + 1, length_m: null })),
    scores: [...Array.from({ length: 18 }, (_, i) => [score(R1, A, i, 4), score(R1, B, i, 4), score(R1, C, i, 5)]).flat(), ...playoffScores],
  };
}
const season = { id: SEASON, club_id: CLUB, name: "Sesongen", status: "active", rules: { version: 2, table: { pointsSource: "stableford",
  counting: { unit: "evening", best: null }, roundingStep: null, tieRule: "playoff" } } };

test("Tabeller: delt førsteplass foreslår playoff med de som står likt", () => {
  const v = seasonView(tavlaData(null), season, null);
  assert.deepEqual(v.playoff?.tied.map((t) => t.name), ["Anne", "Bjørn"]);
  assert.deepEqual(v.playoff?.suggested, [17, 0, 17]);
  assert.equal(v.playoff?.round, null);
  assert.equal(v.playoff?.text, "Delt førsteplass: Anne og Bjørn. Avgjøres med playoff.");
});

test("Tabeller: playoff-runden avgjør, og står ikke i «Alle runder»", () => {
  const v = seasonView(tavlaData({ playoff_holes: [17, 0] }, [score(P1, A, 0, 4), score(P1, B, 0, 4), score(P1, A, 1, 3), score(P1, B, 1, 4)]), season, null);
  assert.deepEqual(v.rows.map((r) => [r.name, r.placeText]), [["Anne", "1."], ["Bjørn", "2."], ["Cato", "3."]]);
  assert.equal(v.grid.columns.length, 1);
  assert.equal(v.playoff?.text, "Anne vant playoffen på playoff-hull 2.");
});

test("Tabeller: fortsatt likt gir «Legg til hull»", () => {
  const v = seasonView(tavlaData({ status: "active", playoff_holes: [17] }, [score(P1, A, 0, 4), score(P1, B, 0, 4)]), season, null);
  assert.equal(v.playoff?.round?.canAddHoles, true);
  assert.deepEqual(v.playoff?.round?.holes, [17]);
  assert.equal(v.playoff?.text, "Fortsatt likt etter 1 hull: Anne og Bjørn.");
  assert.ok(v.rows.slice(0, 2).every((r) => r.detail.startsWith("Playoff")));
});

test("Tabeller: uten playoff-regel ingen playoff", () => {
  const plain = { ...season, rules: { version: 2, table: { pointsSource: "stableford", counting: { unit: "evening", best: null }, roundingStep: null } } };
  assert.equal(seasonView(tavlaData(null), plain, null).playoff, null);
});

test("liga: en playoff (playoff_for) teller aldri, selv om den er koblet", () => {
  const td = tavlaData({ playoff_holes: [17] }, [score(P1, A, 0, 3), score(P1, B, 0, 4)]);
  const raw: CompetitionRaw = {
    competition: { id: SEASON, kind: "league", name: "Ligaen", club_id: CLUB, owner_id: null, season_id: null, status: "active", entry: "club", rules: season.rules },
    participants: [], links: [{ competition_id: SEASON, round_id: R1 }, { competition_id: SEASON, round_id: P1 }],
    rounds: td.rounds, roundHoles: [], players: td.players, matches: [], scores: td.scores, claims: [], courses: td.courses,
    courseHoles: td.course_holes, events: td.events, clubMembers: td.members, roundMembers: td.members, seasons: [], roster: [],
    roundParticipants: [], profiles: [], cupMatches: [],
  };
  const d = competitionData(raw);
  assert.deepEqual(d.input.rounds.map((r) => r.round.id), [R1]);
  assert.equal(d.snapshots.length, 2);
});
