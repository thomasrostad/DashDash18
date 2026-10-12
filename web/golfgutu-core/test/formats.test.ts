// FormatTests.swift (steg 7). Tall: Fixtures/formater.json, regnet for hånd; poengspillene etter NGF
// «Spilleformer» 2023, side 3 og 4.

import assert from "node:assert/strict";
import { test } from "node:test";
import {
  ALL_FORMS, decodeScoringMethod, decodeTeamForm, FORM_CATALOG, formAxes, formByAxes, formById, roundForm, teamFormSize,
  type FormAxes,
} from "../src/forms.ts";
import { evaluatePointsGame, evaluateSkins, formTablePoints, pointsGameHolePoints, pointsGamePattern } from "../src/formplay.ts";
import { effectiveHandicap } from "../src/handicap.ts";
import { copyRound, decodeMatch, makePlayer, makeRound, type HoleScores, type Player, type Round } from "../src/models.ts";
import {
  decodeRoundCompetition, evaluateFrozenCompetitions, evaluateRoundCompetitions, freezeRound, frozenRoundWithScores,
} from "../src/roundcompetitions.ts";
import { courseHoles } from "../src/course.ts";
import { decodeRuleset, encodeRuleset, golfgutuRules, GOLFGUTU, STANDARD_FORM_PLAY, type Ruleset } from "../src/ruleset.ts";
import { evaluateRyderCup, ryderCupPairings, ryderCupSingles } from "../src/rydercup.ts";
import { Season } from "../src/season.ts";
import { validateRuleset } from "../src/validation.ts";
import { fixture, map, obj, TEST_COURSE } from "./helpers.ts";

const fil = fixture("formater");

function scores(): Map<string, HoleScores> {
  return new Map(Object.entries(fil.runde.scorer as Record<string, number[]>).map(([p, list]) => [p, new Map(list.map((g, h) => [h, g]))]));
}

function round(o: { id?: string; gameType?: string; locked?: boolean; teams?: Record<string, number>; matches?: any[]; date?: string | null } = {}): Round {
  return makeRound({
    id: o.id ?? "r", gameType: o.gameType ?? "stableford", holeCount: 18, holeStart: 0, course: TEST_COURSE, hcpAllowance: 1,
    teams: map(o.teams ?? {}), holeScores: scores(), matches: (o.matches ?? []).map((m) => decodeMatch(m)), date: o.date ?? null,
    locked: o.locked ?? true, playingHandicaps: map(fil.runde.handicap),
  });
}

const roster: Player[] = ["a", "b", "c", "d"].map((id) => makePlayer(id, fil.tabell.navn[id]));
const competitions = (fil.runde.konkurranser as any[]).map((c, i) => decodeRoundCompetition(c, `$[${i}]`));

// MARK: 1. To akser

test("aksene dekker hver form én til én", () => {
  assert.deepEqual(fil.akser.map((a: any) => a.id), FORM_CATALOG.map((f) => f.id));
  for (const a of fil.akser) {
    const form = formById(a.id);
    const want: FormAxes = { teamForm: decodeTeamForm(a.teamForm), scoring: decodeScoringMethod(a.scoring) };
    assert.deepEqual(formAxes(form), want, a.id);
    assert.equal(formByAxes(formAxes(form))?.id, a.id);
    assert.equal(teamFormSize(formAxes(form).teamForm), form.teamSize, a.id);
  }
  assert.equal(new Set(FORM_CATALOG.map((f) => JSON.stringify(formAxes(f)))).size, FORM_CATALOG.length);
});

test("Golfgutu er uendret", () => {
  assert.equal(ALL_FORMS.length, 16);
  assert.ok(!GOLFGUTU.formats.allowedFormIDs.includes("amerikaner"));
  const json = encodeRuleset(GOLFGUTU) as any;
  assert.equal(json.formPlay, undefined);
  assert.equal(json.table.formPoints, undefined);
  assert.equal(formById("tull").id, "stableford");
  assert.equal(roundForm({ gameType: "Kobenhavner" }).id, "kobenhavner");
});

// MARK: 2. Amerikaner og Københavner

test("poengfordeling etter NGF", () => {
  for (const c of fil.poengspill) {
    const s = map<number>(c.scorer);
    assert.equal(pointsGamePattern(s), c.monster);
    assert.deepEqual(obj(pointsGameHolePoints(s, STANDARD_FORM_PLAY.pointsGames[c.spill])), c.poeng, `${c.spill} ${c.monster}`);
  }
  for (const p of Object.values(STANDARD_FORM_PLAY.pointsGames.amerikaner.points)) assert.equal(p.reduce((a, b) => a + b, 0), 12);
  for (const p of Object.values(STANDARD_FORM_PLAY.pointsGames.kobenhavner.points)) assert.equal(p.reduce((a, b) => a + b, 0), 6);
  assert.equal(pointsGameHolePoints(map({ a: 3, b: 4, c: 5 }), STANDARD_FORM_PLAY.pointsGames.amerikaner), null);
});

test("amerikaner hull for hull", () => {
  const r = evaluatePointsGame("amerikaner", ["a", "b", "c", "d"], round({ gameType: "amerikaner" }), [], GOLFGUTU);
  assert.deepEqual(r.holes.map((h) => obj(h.points)), fil.runde.amerikanerHull);
  assert.deepEqual(obj(r.totals), { a: 53, b: 55, c: 47, d: 61 });
  assert.ok(r.isFinished);
});

test("amerikaner: uferdig hull", () => {
  const r = round({ gameType: "amerikaner", locked: false });
  r.holeScores.get("c")!.delete(5);
  const res = evaluatePointsGame("amerikaner", ["a", "b", "c", "d"], r, [], GOLFGUTU);
  assert.equal(res.holes[5].state, "pending");
  assert.equal(res.totals.get("a"), 49);
  r.locked = true;
  assert.equal(evaluatePointsGame("amerikaner", ["a", "b", "c", "d"], r, [], GOLFGUTU).holes[5].state, "void");
});

// MARK: 3 og 5. Flere konkurranser på samme runde

test("flere konkurranser på samme runde", () => {
  const results = evaluateRoundCompetitions(round(), [], competitions, GOLFGUTU);
  assert.deepEqual(results.map((r) => r.id), fil.runde.forventet.map((f: any) => f.id));
  results.forEach((got, i) => {
    const want = fil.runde.forventet[i];
    assert.equal(got.supported, want.stottet, want.id);
    assert.deepEqual(got.rows.map((r) => ({ spillere: r.players, score: r.score, hull: r.holes, plass: r.rank })), want.rader, want.id);
  });
});

test("skins som rundespillet", () => {
  const g = evaluateSkins(["a", "b", "c", "d"], round(), [], GOLFGUTU, GOLFGUTU.formPlay.skins);
  assert.deepEqual(g.holes.map((h) => ({ state: h.state, winners: h.winners, value: h.value })), fil.runde.skinsHull);
  assert.deepEqual(obj(g.scores), { a: 5, b: 3, c: 4, d: 3 });
  const noCarry = golfgutuRules();
  noCarry.formPlay.skins.carryOver = false;
  assert.deepEqual(obj(formTablePoints(round({ gameType: "skins" }), [], noCarry)), { a: 2, b: 2, c: 1, d: 2 });
});

function tableRules(formPoints: boolean): Ruleset {
  const r = golfgutuRules();
  r.table.pointsSource = "stableford";
  r.table.counting = { unit: "round", best: null };
  r.table.tiebreaks = ["stableford"];
  r.table.formPoints = formPoints;
  return r;
}

test("skins og amerikaner i tabellen", () => {
  const rounds = (fil.tabell.runder as any[]).map((r) => round({ id: r.id, gameType: r.gameType, date: r.date }));
  const rules = tableRules(true);
  assert.deepEqual(validateRuleset(rules), []);
  const board = new Season(roster, rounds, [], rules).jacketBoard();
  assert.deepEqual(board.map((r) => ({ id: r.player.id, total: r.total, stableford: r.stableford })), fil.tabell.medFormpoeng);
  const plain = new Season(roster, rounds, [], tableRules(false)).jacketBoard();
  assert.deepEqual(plain.map((r) => ({ id: r.player.id, total: r.total, stableford: r.stableford })), fil.tabell.utenFormpoeng);
  const half = tableRules(true);
  half.formPlay.skinPoints = 0.5;
  assert.deepEqual(obj(formTablePoints(round({ gameType: "skins" }), [], half)), { a: 2.5, b: 1.5, c: 2, d: 1.5 });
  const bad = golfgutuRules();
  bad.table.formPoints = true;
  assert.ok(validateRuleset(bad).some((i) => i.field === "table.formPoints"));
});

test("formreglene som JSON", () => {
  const r = tableRules(true);
  r.formPlay.skinPoints = 2;
  r.formPlay.pointsGames.kobenhavner.points["1-1-1"] = [5, 1, 0];
  const back = decodeRuleset(JSON.parse(JSON.stringify(encodeRuleset(r))));
  assert.deepEqual(back, r);
  const partial = decodeRuleset({ version: 2, formPlay: { skinPoints: 3 } });
  assert.equal(partial.formPlay.skinPoints, 3);
  assert.deepEqual(partial.formPlay.pointsGames, STANDARD_FORM_PLAY.pointsGames);
});

// MARK: 4. Lag mot lag

test("lag mot lag", () => {
  const l = fil.lagMotLag;
  const rounds = (l.runder as any[]).map((r) => round({ id: r.id, gameType: r.gameType, teams: r.teams, matches: r.matches }));
  const res = evaluateRyderCup(rounds, map(l.sider), [], GOLFGUTU);
  assert.deepEqual(res.matches.map((m) => ({
    runde: m.roundIndex, matchNo: m.matchNo, sideA: m.sideA, sideB: m.sideB, state: m.state, utfallA: m.outcomeA, poengA: m.pointsA, poengB: m.pointsB,
  })), l.forventet.matcher);
  assert.deepEqual(res.table.map((r) => ({ side: r.side, poeng: r.points, vunnet: r.won, delt: r.halved, tapt: r.lost })), l.forventet.tabell);
  const rules = golfgutuRules();
  rules.formPlay.teamMatch = { win: 2, draw: 1, loss: 0 };
  assert.deepEqual(evaluateRyderCup(rounds, map(l.sider), [], rules).table.map((r) => r.points), [5, 1]);
  const pairs = ryderCupPairings(map(l.parring.lag), map(l.parring.sider));
  assert.deepEqual(pairs.map((m) => ({ teamA: m.teamA, teamB: m.teamB })), l.parring.forventet);
  assert.deepEqual(ryderCupSingles(["a", "b"], ["c", "d"]).map((m) => [m.matchNo, m.playerA, m.playerB]), [[1, "a", "c"], [2, "b", "d"]]);
});

// MARK: 6. Øyeblikksbildet

test("øyeblikksbildet holder resultatet", () => {
  const people = [makePlayer("a", "Anne", 2.4), makePlayer("b", "Bjørn", 17.8), makePlayer("c", "Cecilie", 9.1), makePlayer("d", "Dag", 25)];
  const live = round();
  live.playingHandicaps = new Map();
  live.hcpAllowance = 0.95;
  const frozen = freezeRound(live, people, GOLFGUTU);
  for (const p of people) assert.equal(frozen.playingHandicaps.get(p.id), effectiveHandicap(p, live, people, GOLFGUTU));
  assert.deepEqual(frozen.holes, courseHoles(live));

  const before = evaluateFrozenCompetitions(frozen, live.holeScores, competitions);
  assert.deepEqual(evaluateRoundCompetitions(live, people, competitions, GOLFGUTU), before);

  const changed = golfgutuRules();
  changed.scoring.netParPoints = 3;
  changed.formPlay.pointsGames.amerikaner.points["1-3"] = [12, 0, 0, 0];
  changed.formPlay.skins.carryOver = false;
  const newPeople = people.map((p) => ({ ...p, handicap: 0 }));
  const newRound = copyRound(live);
  newRound.course = { ...TEST_COURSE, holes: TEST_COURSE.holes!.map((h, i) => (i === 0 ? { ...h, par: 5 } : h)) };
  assert.notDeepEqual(evaluateRoundCompetitions(newRound, newPeople, competitions, changed), before);
  assert.deepEqual(evaluateFrozenCompetitions(frozen, live.holeScores, competitions), before);

  const nine = round();
  nine.holeCount = 9;
  nine.holeStart = 9;
  const f9 = freezeRound(nine, [], GOLFGUTU);
  assert.deepEqual(courseHoles(frozenRoundWithScores(f9, new Map())), courseHoles(nine));
});
