// EnBallMatchTests.swift: match med én ball per lag (foursome, greensome, chapman, scramble) som konkurranse på runden.
// Tall: Fixtures/en-ball-match.json (regnet uavhengig av motoren, se «kilde»).

import assert from "node:assert/strict";
import { test } from "node:test";
import { competitionBoards, competitionRowText, engineCompetition } from "../src/app/roundcomp.ts";
import { effectiveHandicap } from "../src/handicap.ts";
import { holeWinner, matchText } from "../src/match.ts";
import { decodeMatch, makePlayer, makeRound, type HoleScores, type Player, type Round } from "../src/models.ts";
import {
  competitionSupported, decodeRoundCompetition, evaluateFrozenCompetitions, evaluateRoundCompetitions, freezeRound,
} from "../src/roundcompetitions.ts";
import { golfgutuRules, useWHSTeamHandicap, type Ruleset } from "../src/ruleset.ts";
import { fixture, map, TEST_COURSE } from "./helpers.ts";

const fil = fixture("en-ball-match");
const roster: Player[] = Object.entries(fil.indeks as Record<string, number>).map(([id, h]) => makePlayer(id, id, h));

function rules(name: string): Ruleset {
  const r = golfgutuRules();
  if (name === "whs" || name === "whsFulltHandicap") useWHSTeamHandicap(r.handicap);
  if (name === "whsFulltHandicap") r.formats.matchStrokes = "fullHandicap";
  return r;
}

function round(r: any): Round {
  const holeScores = new Map<string, HoleScores>();
  for (const [p, list] of Object.entries(r.scorer as Record<string, (number | null)[]>)) {
    holeScores.set(p, new Map(list.flatMap((g, h) => (g === null ? [] : [[h, g] as [number, number]]))));
  }
  return makeRound({
    id: r.id, gameType: r.gameType, holeCount: 18, holeStart: 0, course: TEST_COURSE, hcpAllowance: 1,
    teams: map(r.lag), holeScores, locked: r.laast,
  });
}

const runde = (id: string) => fil.runder.find((r: any) => r.id === id);
const comps = (r: any) => (r.konkurranser as any[]).map((c, i) => decodeRoundCompetition(c, `$[${i}]`));

test("lagshandicapet er regelsettets", () => {
  for (const r of fil.runder) {
    const rnd = round(r);
    for (const [p, h] of Object.entries(r.lagshandicap as Record<string, number>)) {
      assert.equal(effectiveHandicap(roster.find((x) => x.id === p)!, rnd, roster, rules(r.regelsett)), h, `${r.id} ${p}`);
    }
  }
});

test("én ball-match: sum, hull, plass, per hull, stilling og tekst", () => {
  for (const r of fil.runder) {
    const results = evaluateRoundCompetitions(round(r), roster, comps(r), rules(r.regelsett));
    assert.deepEqual(results.map((x) => x.id), r.forventet.map((x: any) => x.id), r.id);
    results.forEach((got, i) => {
      const want = r.forventet[i];
      const id = `${r.id}/${want.id}`;
      assert.equal(got.supported, want.stottet, id);
      assert.deepEqual(got.rows.map((x) => x.players), want.rader.map((x: any) => x.spillere), `${id}: rekkefølge`);
      assert.deepEqual(got.rows.map((x) => x.score), want.rader.map((x: any) => x.score), `${id}: sum`);
      assert.deepEqual(got.rows.map((x) => x.holes), want.rader.map((x: any) => x.hull), `${id}: hull`);
      assert.deepEqual(got.rows.map((x) => x.rank), want.rader.map((x: any) => x.plass), `${id}: plass`);
      got.rows.forEach((row, j) => {
        const w = want.rader[j];
        assert.deepEqual(Array.from({ length: 18 }, (_, h) => row.holeValues.get(h) ?? null), w.perHull, `${id} ${row.players}: per hull`);
        assert.deepEqual(row.match, { up: w.stilling.opp, played: w.stilling.spilt, remaining: w.stilling.igjen,
          decided: w.stilling.avgjort, opponents: w.stilling.motstandere }, `${id} ${row.players}: stilling`);
        assert.equal(matchText(row.match ?? null), w.tekst, `${id} ${row.players}: tekst`);
      });
    });
  }
});

test("fra øyeblikksbildet gir samme svar", () => {
  for (const r of fil.runder) {
    const rnd = round(r);
    const rs = rules(r.regelsett);
    const live = evaluateRoundCompetitions(rnd, roster, comps(r), rs);
    const snap = evaluateFrozenCompetitions(freezeRound(rnd, roster, rs), rnd.holeScores, comps(r), r.laast);
    assert.deepEqual(snap, live, r.id);
  }
});

test("én ball støttes for alle lagformene med én ball, ikke sammenlagt", () => {
  for (const teamForm of [
    { type: "pairs", pairs: "foursome" }, { type: "pairs", pairs: "greensome" }, { type: "pairs", pairs: "chapman" },
    { type: "scramble", size: 2 }, { type: "scramble", size: 4 },
  ] as const) {
    assert.ok(competitionSupported({ teamForm, scoring: { type: "matchPlay" } }), JSON.stringify(teamForm));
  }
  assert.ok(!competitionSupported({ teamForm: { type: "pairs", pairs: "aggregate" }, scoring: { type: "matchPlay" } }));
});

test("samme hull som rundens lagmatch, men stopper når den er avgjort", () => {
  const r = runde("foursome");
  const rnd = round(r);
  rnd.matches = [decodeMatch({ matchNo: 1, teamA: 1, teamB: 2 })];
  const rs = rules(r.regelsett);
  const comp = evaluateRoundCompetitions(rnd, roster, [comps(r)[0]], rs)[0];
  const ab = comp.rows.find((x) => x.players.join() === "a,b")!;
  for (let h = 0; h < 16; h++) assert.equal(holeWinner(rnd.matches[0], h, rnd, roster, rs), ab.holeValues.get(h), `hull ${h + 1}`);
  assert.equal(ab.holeValues.get(16), undefined);
  assert.equal(matchText(ab.match ?? null), "Tapt 3&2");
});

test("lagform som ikke er rundens, og uten lag: appens konkurranse og tavla", () => {
  const r = runde("greensome-whs");
  const rnd = round(r);
  const individual = { ...rnd, gameType: "stableford" };
  const comp = decodeRoundCompetition({ id: "m", teamForm: { type: "pairs", pairs: "greensome" }, scoring: { type: "matchPlay" } });
  assert.equal(evaluateRoundCompetitions(individual, roster, [comp], rules("whs"))[0].supported, false);
  // Lagret config uten entrants: én ball bruker rundens lag, ikke sidene i lag mot lag.
  const stored = { id: "x", roundID: "r", name: "Greensome-match", isMain: false, formatVersion: 1,
    config: { teamForm: { type: "pairs", pairs: "greensome" }, scoring: { type: "matchPlay" } }, sortOrder: 1 };
  const sides = new Map([["a", 1], ["b", 1], ["c", 2], ["d", 2]]);
  assert.equal(engineCompetition(stored, "greensome", "x", sides)?.entrants, null);
  const boards = competitionBoards({ competitions: [stored], roundFormat: "greensome", frozen: null,
    live: { round: rnd, roster, rules: rules("whs") }, sides });
  const board = boards.find((b) => b.key === "x")!;
  assert.ok(board.supported && board.isMatch);
  assert.deepEqual(board.rows.map((x) => competitionRowText(board, x)), ["Vunnet 1 opp", "Tapt 1 ned"]);
});
