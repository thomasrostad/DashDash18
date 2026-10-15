// SpillformerTests.swift: scramble, foursome, greensome, chapman og par/bogey som konkurranser på runden.
// Tall: Fixtures/spillformer.json (WHS «Rules of Handicapping» Appendix C, Golfreglene 2019 regel 21.3).

import assert from "node:assert/strict";
import { test } from "node:test";
import { competitionScoreText } from "../src/app/roundcomp.ts";
import { formTablePoints, parBogeyHoleValue } from "../src/formplay.ts";
import { effectiveHandicap, teamHandicapByIDs } from "../src/handicap.ts";
import { makePlayer, makeRound, type HoleScores, type Player, type Round } from "../src/models.ts";
import { competitionSupported, decodeRoundCompetition, evaluateRoundCompetitions } from "../src/roundcompetitions.ts";
import {
  decodeRuleset, encodeRuleset, golfgutuRules, GOLFGUTU, STANDARD_PAR_BOGEY, usesWHSTeamHandicap, useWHSTeamHandicap,
  WHS_TEAM_HANDICAP, type Ruleset,
} from "../src/ruleset.ts";
import { roundPoints } from "../src/scoring.ts";
import { changedFields } from "../src/template.ts";
import { validateRuleset } from "../src/validation.ts";
import { fixture, map, TEST_COURSE } from "./helpers.ts";

const fil = fixture("spillformer");
const roster: Player[] = Object.entries(fil.indeks as Record<string, number>).map(([id, h]) => makePlayer(id, id, h));

function whs(): Ruleset {
  const r = golfgutuRules();
  useWHSTeamHandicap(r.handicap);
  return r;
}
const rules = (name: string): Ruleset => (name === "whs" ? whs() : GOLFGUTU);

function round(r: any): Round {
  const holeScores = new Map<string, HoleScores>();
  for (const [p, list] of Object.entries(r.scorer as Record<string, (number | null)[]>)) {
    holeScores.set(p, new Map(list.flatMap((g, h) => (g === null ? [] : [[h, g] as [number, number]]))));
  }
  return makeRound({
    id: r.id, gameType: r.gameType, holeCount: 18, holeStart: 0, course: TEST_COURSE, hcpAllowance: 1,
    teams: map(r.lag), holeScores, locked: r.laast, playingHandicaps: map(r.spillehandicap ?? {}),
  });
}

test("lagshandicap: Golfgutu og WHS", () => {
  for (const c of fil.lagshandicap) {
    const r = makeRound({ gameType: c.form, holeCount: c.hull, course: TEST_COURSE, hcpAllowance: 1 });
    assert.equal(teamHandicapByIDs(r, c.spillere, roster, GOLFGUTU), c.golfgutu, `${c.form} golfgutu`);
    assert.equal(teamHandicapByIDs(r, c.spillere, roster, whs()), c.whs, `${c.form} whs`);
  }
});

test("WHS-tallene ligger i regelsettet", () => {
  assert.deepEqual(WHS_TEAM_HANDICAP["scramble-2"].weights, [0.35, 0.15]);
  assert.deepEqual(WHS_TEAM_HANDICAP["greensome"].weights, [0.6, 0.4]);
  assert.ok(!usesWHSTeamHandicap(GOLFGUTU.handicap));
  assert.ok(usesWHSTeamHandicap(whs().handicap));
  assert.deepEqual(validateRuleset(whs()), []);
  assert.deepEqual(changedFields(whs(), GOLFGUTU), [
    "handicap.teamHandicap.chapman.method", "handicap.teamHandicap.chapman.weights",
    "handicap.teamHandicap.foursome.method", "handicap.teamHandicap.foursome.weights",
    "handicap.teamHandicap.greensome.method", "handicap.teamHandicap.greensome.weights",
    "handicap.teamHandicap.scramble-2.method", "handicap.teamHandicap.scramble-2.weights",
  ]);
});

test("lagshandicap i runden", () => {
  for (const r of fil.runder) {
    if (!r.lagshandicap) continue;
    const rnd = round(r);
    for (const [p, h] of Object.entries(r.lagshandicap as Record<string, number>)) {
      assert.equal(effectiveHandicap(roster.find((x) => x.id === p), rnd, roster, rules(r.regelsett)), h, `${r.id} ${p}`);
    }
  }
});

test("konkurransene: poeng per hull, sum, plass og uavgjort", () => {
  for (const r of fil.runder) {
    const comps = (r.konkurranser as any[]).map((c, i) => decodeRoundCompetition(c, `$[${i}]`));
    const results = evaluateRoundCompetitions(round(r), roster, comps, rules(r.regelsett));
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
        const per = Array.from({ length: 18 }, (_, h) => row.holeValues.get(h) ?? null);
        assert.deepEqual(per, want.rader[j].perHull, `${id} ${row.players}: per hull`);
      });
    });
  }
});

test("hovedkonkurransen gir tabellpoengene", () => {
  for (const r of fil.runder) {
    if (r.gameType === "par-bogey") continue;
    const rnd = round(r);
    const main = evaluateRoundCompetitions(rnd, roster, [decodeRoundCompetition(r.konkurranser[0])], rules(r.regelsett))[0];
    const points = roundPoints(rnd, roster, rules(r.regelsett));
    for (const row of main.rows) for (const p of row.players) if (points.has(p)) assert.equal(points.get(p), row.score, `${r.id} ${p}`);
  }
});

test("én ball krever at runden spilles i lagformen", () => {
  const r = fil.runder.find((x: any) => x.id === "scramble-2");
  const rnd = round(r);
  rnd.gameType = "stableford";
  const comp = decodeRoundCompetition({ id: "s", teamForm: { type: "scramble", size: 2 }, scoring: { type: "stableford", net: true } });
  assert.equal(evaluateRoundCompetitions(rnd, roster, [comp], whs())[0].supported, false);
  const mixed = decodeRoundCompetition({ id: "m", teamForm: { type: "scramble", size: 2 }, scoring: { type: "stableford", net: true }, entrants: [["a", "c"]] });
  assert.equal(evaluateRoundCompetitions(round(r), roster, [mixed], whs())[0].supported, false);
  assert.ok(competitionSupported({ teamForm: { type: "scramble", size: 2 }, scoring: { type: "parBogey" } }));
  assert.ok(!competitionSupported({ teamForm: { type: "individual" }, scoring: { type: "maximumScore" } }));
});

test("par/bogey: hull, tabell og verdier fra regelsettet", () => {
  assert.equal(parBogeyHoleValue(3, 4, STANDARD_PAR_BOGEY), 1);
  assert.equal(parBogeyHoleValue(4, 4, STANDARD_PAR_BOGEY), 0);
  assert.equal(parBogeyHoleValue(5, 4, STANDARD_PAR_BOGEY), -1);
  assert.equal(parBogeyHoleValue(null, 4, STANDARD_PAR_BOGEY), -1);

  const r = fil.runder.find((x: any) => x.id === "par-bogey");
  const want = r.forventet[0].rader;
  const points = formTablePoints(round(r), roster, GOLFGUTU);
  assert.deepEqual(Object.fromEntries(points), Object.fromEntries(want.map((x: any) => [x.spillere[0], x.score])));

  const custom = golfgutuRules();
  custom.formPlay.parBogey = { win: 2, halve: 1, loss: 0 };
  const got = evaluateRoundCompetitions(round(r), roster, [decodeRoundCompetition(r.konkurranser[0])], custom)[0];
  for (const row of got.rows) {
    const std = want.find((x: any) => x.spillere.join() === row.players.join());
    assert.equal(row.score, std.score + std.hull, row.players.join());
  }
  const json = encodeRuleset(custom) as any;
  assert.deepEqual(json.formPlay.parBogey, { win: 2, halve: 1, loss: 0 });
  assert.deepEqual(decodeRuleset(json).formPlay.parBogey, { win: 2, halve: 1, loss: 0 });
  const other = golfgutuRules();
  other.formPlay.skinPoints = 2;
  assert.equal((encodeRuleset(other) as any).formPlay.parBogey, undefined);
  assert.equal((encodeRuleset(GOLFGUTU) as any).formPlay, undefined);
  const bad = golfgutuRules();
  bad.formPlay.parBogey = { win: -1, halve: 0, loss: 1 };
  assert.ok(validateRuleset(bad).some((i) => i.field === "formPlay.parBogey"));

  assert.equal(competitionScoreText(3, true), "+3");
  assert.equal(competitionScoreText(-2, true), "−2");
  assert.equal(competitionScoreText(0, true), "0");
  assert.equal(competitionScoreText(-2), "-2");
  assert.equal(competitionScoreText(12.5), "12,5");
});
