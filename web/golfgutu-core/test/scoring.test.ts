// ScoringTests.swift: slag og poeng. Tall: Fixtures/poeng.json.

import assert from "node:assert/strict";
import { test } from "node:test";
import { courseHoles } from "../src/course.ts";
import { decodePlayer, decodeRound, makeRound, type RoundHole } from "../src/models.ts";
import { GOLFGUTU } from "../src/ruleset.ts";
import { handicapStrokes, holePoints, pointsFromScores, roundNetTotal, roundNetTotalWithHandicap, scoreName, scoreNameLabel } from "../src/scoring.ts";
import { fixture } from "./helpers.ts";

const fil = fixture("poeng");
const saker = (fil.roundNetTotal as any[]).map((s) => ({
  navn: s.navn as string,
  spillere: (s.spillere as any[]).map((p) => decodePlayer(p)),
  runde: decodeRound(s.runde),
  forventet: s.forventet as Record<string, number>,
}));

test("handicapStrokesForHole", () => {
  for (const s of fil.handicapStrokesForHole) {
    assert.equal(handicapStrokes(s.handicap, s.strokeIndex, s.antall), s.forventet, s.navn);
  }
});

test("slag på de fem vanskeligste av ni", () => {
  const ph = fil.baneoppsettPerHull;
  const holes = new Map<number, RoundHole>();
  for (let i = 0; i < 9; i++) holes.set(i, { par: ph.elisefarmPar[i], strokeIndex: ph.elisefarmSi[i], meters: null });
  const r = makeRound({ holeCount: 9, holes });
  const medSlag = courseHoles(r).map((h, i) => ({ h, i })).filter(({ h }) => handicapStrokes(5, h.strokeIndex, 9) > 0).map(({ i }) => i + 1);
  assert.deepEqual(medSlag, [2, 4, 5, 7, 8]);
});

test("brutto: banens vanskeligste og letteste", () => {
  const sak = saker.find((s) => s.navn.startsWith("par rundt brutto"))!;
  const hull = courseHoles(sak.runde);
  assert.ok(hull[1].par === 5 && hull[1].strokeIndex === 1);
  assert.ok(hull[10].par === 3 && hull[10].strokeIndex === 18);
  const medSlag = hull.filter((h) => handicapStrokes(7, h.strokeIndex, 18) > 0).map((h) => h.strokeIndex).sort((a, b) => a - b);
  assert.deepEqual(medSlag, [1, 2, 3, 4, 5, 6, 7]);
});

test("pointsForHole", () => {
  for (const p of fil.pointsForHole) {
    assert.equal(holePoints(p.par, p.brutto, p.handicap, p.strokeIndex, p.antall), p.forventet, p.navn);
  }
  assert.notEqual(holePoints(3, 4, 0, 1, 9), holePoints(5, 4, 0, 1, 9));
  assert.ok(holePoints(4, 5, 17, 1, 9) > holePoints(4, 5, 0, 1, 9));
});

test("scoreNameForHole", () => {
  for (const n of fil.scoreNameForHole) {
    assert.equal(scoreName(n.par, n.brutto, n.handicap, n.strokeIndex, n.antall), n.forventet);
  }
  assert.equal(scoreNameLabel("dobbel"), "Dobbel");
});

test("baneoppsett per hull", () => {
  const ph = fil.baneoppsettPerHull;
  const elise = new Map<number, RoundHole>();
  for (let i = 0; i < 18; i++) elise.set(i, { par: ph.elisefarmPar[i], strokeIndex: ph.elisefarmSi[i], meters: null });
  const perHull = (holes: Map<number, RoundHole> | null, hcp: number) => {
    const c = courseHoles(makeRound({ holeCount: 18, holes }));
    return (ph.slag as number[]).map((s, i) => holePoints(c[i].par, s, hcp, c[i].strokeIndex, 18));
  };
  const sum = (xs: number[]) => xs.reduce((a, b) => a + b, 0);
  const a9 = perHull(null, 9), b9 = perHull(elise, 9);
  assert.deepEqual(a9, ph.hcp9.standard);
  assert.deepEqual(b9, ph.hcp9.elisefarm);
  assert.equal(a9.filter((x, i) => x !== b9[i]).length, 11);
  assert.notEqual(sum(a9), sum(b9));
  assert.notEqual(sum(perHull(null, 0)), sum(perHull(elise, 0)));
  const a18 = perHull(null, 18), b18 = perHull(elise, 18);
  assert.deepEqual(a18, ph.hcp18.standard);
  assert.deepEqual(b18, ph.hcp18.elisefarm);
  assert.equal(sum(a18), sum(b18));
  assert.ok(a18.some((x, i) => x !== b18[i]));
});

test("roundNetTotal", () => {
  for (const sak of saker) {
    for (const p of sak.spillere) {
      assert.equal(roundNetTotal(sak.runde, p, sak.spillere), sak.forventet[p.id], `${sak.navn}: ${p.id}`);
    }
  }
});

test("banebytte og tropp: relasjonene", () => {
  const sum = (prefix: string) => saker.find((s) => s.navn.startsWith(prefix))!.forventet;
  assert.notDeepEqual(sum("banebytte: uten bane"), sum("banebytte: Elisefarm"));
  assert.deepEqual(sum("banebytte: flat bane"), sum("banebytte: uten bane"));
  const tropp = sum("tropp:");
  assert.ok(tropp.a > tropp.b);
});

test("ingen score gir null", () => {
  const r = makeRound({ holeCount: 18, avkortRegel: "nettopar" });
  assert.equal(pointsFromScores(new Map(), r, 10), 0);
  assert.equal(roundNetTotalWithHandicap(r, null, 10), 0);
  assert.equal(GOLFGUTU.scoring.netParPoints, 2);
});
