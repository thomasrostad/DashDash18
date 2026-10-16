// MaksOgMatchTests.swift: maksimumscore (Golfreglene 2019, regel 21.2) og match som konkurranser på runden.
// Tall: Fixtures/maks-og-match.json (regnet uavhengig av motoren, se «kilde»).

import assert from "node:assert/strict";
import { test } from "node:test";
import { competitionBoards, competitionRowText, engineCompetition, sidesAsEntrants } from "../src/app/roundcomp.ts";
import { decodeScoringMethod, formAxes, formById } from "../src/forms.ts";
import { decodeMatch, makePlayer, makeRound, type HoleScores, type Round } from "../src/models.ts";
import { holeWinner, matchStanding, matchText } from "../src/match.ts";
import { competitionSupported, decodeRoundCompetition, evaluateRoundCompetitions } from "../src/roundcompetitions.ts";
import { decodeRuleset, encodeRuleset, golfgutuRules, GOLFGUTU, type Ruleset } from "../src/ruleset.ts";
import { validateRuleset } from "../src/validation.ts";
import { fixture, map, TEST_COURSE } from "./helpers.ts";

const fil = fixture("maks-og-match");

function rules(name: string): Ruleset {
  const r = golfgutuRules();
  if (name === "fastTak7") r.formPlay.maximumScore = { type: "fixed", strokes: 7 };
  if (name === "fulltHandicap") r.formats.matchStrokes = "fullHandicap";
  return r;
}

function round(r: any, matches: unknown[] = []): Round {
  const holeScores = new Map<string, HoleScores>();
  for (const [p, list] of Object.entries(r.scorer as Record<string, (number | null)[]>)) {
    holeScores.set(p, new Map(list.flatMap((g, h) => (g === null ? [] : [[h, g] as [number, number]]))));
  }
  return makeRound({
    id: r.id, gameType: r.gameType, holeCount: 18, holeStart: 0, course: TEST_COURSE, hcpAllowance: 1,
    holeScores, locked: r.laast, playingHandicaps: map(r.spillehandicap), matches: matches.map((m) => decodeMatch(m)),
  });
}

const runde = (id: string) => fil.runder.find((r: any) => r.id === id);

test("konkurransene: sum, hull, plass, per hull og stilling", () => {
  for (const r of fil.runder) {
    const comps = (r.konkurranser as any[]).map((c, i) => decodeRoundCompetition(c, `$[${i}]`));
    const results = evaluateRoundCompetitions(round(r), [], comps, rules(r.regelsett));
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
        if (w.stilling) {
          assert.deepEqual(row.match, { up: w.stilling.opp, played: w.stilling.spilt, remaining: w.stilling.igjen,
            decided: w.stilling.avgjort, opponents: w.stilling.motstandere }, `${id} ${row.players}: stilling`);
        } else {
          assert.equal(row.match, undefined, `${id} ${row.players}`);
        }
      });
    });
  }
});

test("maksimumscore: støttet, JSON og taket i regelsettet", () => {
  assert.ok(competitionSupported({ teamForm: { type: "individual" }, scoring: { type: "maximumScore", net: true } }));
  assert.deepEqual(decodeScoringMethod({ type: "maximumScore" }), formAxes(formById("maks-score")).scoring);
  assert.deepEqual(decodeScoringMethod({ type: "maximumScore", net: false, maxStrokes: { type: "fixed", strokes: 8 } }),
    { type: "maximumScore", net: false, maxStrokes: { type: "fixed", strokes: 8 } });
  assert.deepEqual(GOLFGUTU.formPlay.maximumScore, { type: "netDoubleBogey" });
  assert.equal((encodeRuleset(GOLFGUTU) as any).formPlay, undefined);
  const fixed = rules("fastTak7");
  const json = encodeRuleset(fixed) as any;
  assert.deepEqual(json.formPlay.maximumScore, { type: "fixed", strokes: 7 });
  assert.deepEqual(decodeRuleset(JSON.parse(JSON.stringify(json))).formPlay.maximumScore, { type: "fixed", strokes: 7 });
  assert.deepEqual(validateRuleset(fixed), []);
  const off = golfgutuRules();
  off.formPlay.maximumScore = { type: "off" };
  assert.ok(validateRuleset(off).some((x) => x.field === "formPlay.maximumScore"));
  const big = golfgutuRules();
  big.formPlay.maximumScore = { type: "fixed", strokes: 21 };
  assert.ok(validateRuleset(big).some((x) => x.field === "formPlay.maximumScore"));
});

test("match: egne baller og én ball, ikke sammenlagt", () => {
  assert.ok(competitionSupported({ teamForm: { type: "individual" }, scoring: { type: "matchPlay" } }));
  assert.ok(competitionSupported({ teamForm: { type: "pairs", pairs: "fourball" }, scoring: { type: "matchPlay" } }));
  // Én ball per lag: enballmatch.test.ts (runden må spilles i lagformen).
  assert.ok(competitionSupported({ teamForm: { type: "pairs", pairs: "foursome" }, scoring: { type: "matchPlay" } }));
  assert.ok(!competitionSupported({ teamForm: { type: "pairs", pairs: "aggregate" }, scoring: { type: "matchPlay" } }));
});

test("match: samme hull som rundens match, men stopper når den er avgjort", () => {
  const r = runde("match");
  const rnd = round(r, [{ matchNo: 1, playerA: "a", playerB: "b" }]);
  const roster = ["a", "b", "c", "d"].map((id) => makePlayer(id));
  const comp = evaluateRoundCompetitions(rnd, roster, [decodeRoundCompetition(r.konkurranser[0])], GOLFGUTU)[0];
  const a = comp.rows.find((x) => x.players[0] === "a")!;
  for (let h = 0; h < 16; h++) assert.equal(holeWinner(rnd.matches[0], h, rnd, roster), a.holeValues.get(h), `hull ${h + 1}`);
  assert.equal(matchText(a.match!), "Vunnet 3&2");
  const pwa = matchStanding(rnd.matches[0], "a", rnd, roster)!;
  assert.equal(pwa.up, 1);
  assert.equal(pwa.played, 18);
});

test("match: stillingen som tekst, og side mot side fra lag mot lag", () => {
  const r = runde("match");
  const stored = (r.konkurranser as any[]).map((c, i) => ({
    id: c.id, roundID: "r", name: c.id, isMain: false, formatVersion: 1, sortOrder: i + 1,
    config: Object.fromEntries(Object.entries(c).filter(([k]) => k !== "id")),
  }));
  const sides = new Map([["a", 1], ["c", 1], ["b", 2], ["d", 2]]);
  const boards = competitionBoards({ competitions: stored, roundFormat: "stableford", frozen: null,
    live: { round: round(r), roster: [], rules: GOLFGUTU }, sides });
  const text = (id: string, p: string) => {
    const b = boards.find((x) => x.key === id)!;
    return competitionRowText(b, b.rows.find((x) => x.players.includes(p))!);
  };
  assert.equal(text("a-mot-b", "b"), "Tapt 3&2");
  assert.equal(text("a-mot-b-forste-ni", "a"), "Vunnet 2 opp");
  assert.equal(text("c-mot-d", "c"), "2 opp etter 9");
  assert.equal(text("side-mot-side", "c"), "Vunnet 6&4");
  // Uten egne sider: side 1 mot side 2.
  assert.equal(text("uten-sider", "a"), "Vunnet 6&4");
  assert.deepEqual(sidesAsEntrants(sides), [["a", "c"], ["b", "d"]]);
  assert.equal(sidesAsEntrants(new Map([["a", 1]])), null);
  assert.equal(engineCompetition(stored[5], "stableford", "k")?.entrants, null);
  assert.ok(boards.every((b) => b.isMatch));
  assert.equal(boards.find((b) => b.key === "foursome-match")?.supported, false);
  // Andre konkurranser er tekst som før.
  assert.equal(competitionRowText({ signed: false, isMatch: false }, { players: ["a"], score: 73, holes: 18, rank: 1, holeValues: new Map() }), "73");
});
