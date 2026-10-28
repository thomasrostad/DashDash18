// PlayRulesTests.swift: maks slag per hull, låst kort og antall skjulte hull. Tall: Fixtures/maks-slag.json
// (regnet for hånd).

import assert from "node:assert/strict";
import { test } from "node:test";
import { decodeMatch, decodePlayer, makeRound, type Player, type Round } from "../src/models.ts";
import { holeWinner } from "../src/match.ts";
import { cappingStrokes, strokeLimit } from "../src/play.ts";
import { hiddenHoleIndices } from "../src/playoff.ts";
import { decodeMaxStrokes, decodeRuleset, encodeRuleset, golfgutuRules, GOLFGUTU, maxStrokesLimit, STANDARD_PLAY, type MaxStrokes, type Ruleset } from "../src/ruleset.ts";
import { roundPoints } from "../src/scoring.ts";
import { Season } from "../src/season.ts";
import { validateRuleset } from "../src/validation.ts";
import { fixture, obj, TEST_COURSE } from "./helpers.ts";

const fil = fixture("maks-slag");
const spillere: Player[] = (fil.spillere as any[]).map((p) => decodePlayer(p));
const scores = (list: number[]) => new Map(list.map((v, i) => [i, v] as [number, number]));
const listOf = (m: Map<number, number>) => [...m].sort((a, b) => a[0] - b[0]).map(([, v]) => v);

function runde(gameType = "stableford"): Round {
  return makeRound({
    id: "r1", gameType, holeCount: 18, holeStart: 0, course: TEST_COURSE, hcpAllowance: 1,
    holeScores: new Map(Object.entries(fil.slag as Record<string, number[]>).map(([k, v]) => [k, scores(v)])),
    weight: 1, date: "2026-10-15", locked: true,
  });
}

function regler(m: MaxStrokes): Ruleset {
  const r = golfgutuRules();
  r.play.maxStrokes = m;
  return r;
}

test("grensen per hull", () => {
  for (const g of fil.grense as any[]) {
    assert.equal(maxStrokesLimit(decodeMaxStrokes(g.regel), g.par, g.slagFatt), g.grense);
  }
});

test("kappet runde og poeng", () => {
  const round = runde();
  for (const sak of fil.saker as any[]) {
    const rules = regler(decodeMaxStrokes(sak.regel));
    const capped = cappingStrokes(round, spillere, rules);
    for (const [id, want] of Object.entries(sak.kappet as Record<string, number[]>)) {
      assert.deepEqual(listOf(capped.holeScores.get(id)!), want, `${sak.navn} ${id}`);
    }
    assert.deepEqual(obj(roundPoints(capped, spillere, rules)), sak.stableford, sak.navn);
    const gross = Object.fromEntries([...capped.holeScores].map(([k, v]) => [k, [...v.values()].reduce((a, b) => a + b, 0)]));
    assert.deepEqual(gross, sak.brutto, sak.navn);
  }
});

test("grensen for en spiller", () => {
  const round = runde();
  assert.equal(strokeLimit(round, 0, "A", spillere, GOLFGUTU), null);
  assert.equal(strokeLimit(round, 0, "A", spillere, regler({ type: "netDoubleBogey" })), 7);
  assert.equal(strokeLimit(round, 0, "B", spillere, regler({ type: "netDoubleBogey" })), 6);
  assert.equal(strokeLimit(round, 0, "B", spillere, regler({ type: "fixed", strokes: 6 })), 6);
  assert.equal(strokeLimit(round, 99, "B", spillere, regler({ type: "fixed", strokes: 6 })), null);
});

test("sesongen bruker grensen", () => {
  const round = runde("match");
  round.matches = [decodeMatch({ matchNo: 1, playerA: "A", playerB: "B" })];
  for (const sak of fil.saker as any[]) {
    const season = new Season(spillere, [round], [], regler(decodeMaxStrokes(sak.regel)));
    const r = season.rounds[0];
    for (const [id, want] of Object.entries(sak.kappet as Record<string, number[]>)) {
      assert.deepEqual(listOf(r.holeScores.get(id)!), want, `${sak.navn} ${id}`);
    }
    const winner = holeWinner(r.matches[0], 0, r, spillere, season.ruleset);
    assert.equal(winner, ({ A: 1, delt: 0, B: -1 } as Record<string, number>)[sak.matchHull1], sak.navn);
  }
});

test("Golfgutu er uendret", () => {
  const round = runde();
  assert.deepEqual(GOLFGUTU.play, STANDARD_PLAY);
  assert.equal(cappingStrokes(round, spillere, GOLFGUTU), round);
  assert.equal(new Season(spillere, [round]).rounds[0], round);
  assert.equal("play" in encodeRuleset(GOLFGUTU), false);
  assert.deepEqual(validateRuleset(golfgutuRules()), []);
});

test("JSON leses og skrives", () => {
  for (const sak of fil.json as any[]) {
    const rules = decodeRuleset({ version: 2, play: sak.inn });
    assert.deepEqual(rules.play, { maxStrokes: sak.maxStrokes, lockSubmittedCards: sak.lockSubmittedCards, hiddenHoles: sak.hiddenHoles, shankPosts: sak.shankPosts, teammatesScore: sak.teammatesScore });
    const out = encodeRuleset(rules);
    assert.deepEqual(decodeRuleset(out), rules);
    assert.equal("play" in out, sak.inn.maxStrokes !== undefined);
  }
});

test("ugyldige verdier", () => {
  for (const sak of fil.ugyldig as any[]) {
    const rules = decodeRuleset({ version: 2, play: sak.play });
    assert.deepEqual(validateRuleset(rules).map((i) => i.field), [sak.felt]);
  }
});

test("skjul de siste N hullene", () => {
  for (const sak of fil.skjul as any[]) {
    const round = makeRound({ id: "r", holeCount: sak.holeCount, holeStart: sak.holeStart, course: TEST_COURSE, hideLastHoles: sak.hideLastHoles });
    assert.deepEqual(hiddenHoleIndices(round), sak.skjulte, sak.navn);
  }
});
