// TriangleTests.swift: trekant og trekning. Tall: Fixtures/trekant.json.

import assert from "node:assert/strict";
import { test } from "node:test";
import { matchStanding, outcomeForA } from "../src/match.ts";
import { decodePlayer, decodeRound, makeMatch, makePlayer, makeRound } from "../src/models.ts";
import { decodeRuleset, golfgutuRules } from "../src/ruleset.ts";
import { roundNetTotal } from "../src/scoring.ts";
import { drawMatches, trianglePoints } from "../src/triangle.ts";
import { fixture, map, obj } from "./helpers.ts";

const fil = fixture("trekant");
const trekanter = (fil.trekanter as any[]).map((t) => ({ ...t, spillere: (t.spillere as any[]).map((p) => decodePlayer(p)), runde: decodeRound(t.runde) }));

test("trekantpoeng", () => {
  for (const t of trekanter) {
    const m = t.runde.matches[0];
    for (const p of t.spillere) {
      if (t.netto[p.id] === undefined) continue;
      assert.equal(roundNetTotal(t.runde, p, t.spillere), t.netto[p.id], `${t.navn}: netto ${p.id}`);
    }
    const svar = trianglePoints(m, t.runde, t.spillere);
    assert.deepEqual(obj(svar), t.poeng, t.navn);
    if (svar) assert.equal([...svar.values()].reduce((a, b) => a + b, 0), 1.5);
    assert.equal(matchStanding(m, "a", t.runde, t.spillere), null);
    assert.equal(outcomeForA(m, t.runde, t.spillere), t.utfallForA);
  }
});

test("trekant-testens tall", () => {
  const poeng = (navn: string) => {
    const t = trekanter.find((x) => x.navn === navn)!;
    return obj(trianglePoints(t.runde.matches[0], t.runde, t.spillere));
  };
  assert.deepEqual(poeng("36/18/0"), { a: 1, b: 0.5, c: 0 });
  assert.deepEqual(poeng("delt førsteplass"), { a: 0.75, b: 0.75, c: 0 });
  assert.deepEqual(poeng("alle likt"), { a: 0.5, b: 0.5, c: 0.5 });
  assert.deepEqual(poeng("delt andreplass"), { a: 1, b: 0.25, c: 0.25 });
  assert.equal(poeng("tredjemann mangler"), null);
});

test("ikke trekant gir null", () => {
  const r = makeRound({ holeScores: new Map([["a", new Map([[0, 4]])], ["b", new Map([[0, 4]])]]) });
  assert.equal(trianglePoints(makeMatch({ playerA: "a", playerB: "b" }), r, []), null);
});

test("plasspoeng fra regelsettet", () => {
  const t = trekanter.find((x) => x.navn === "delt førsteplass")!;
  const regler = golfgutuRules();
  assert.deepEqual(regler.table.trianglePoints, [1, 0.5, 0]);
  regler.table.trianglePoints = [3, 1, 0];
  assert.deepEqual(obj(trianglePoints(t.runde.matches[0], t.runde, t.spillere, regler)), { a: 2, b: 2, c: 0 });
  const gammelt = decodeRuleset({
    seedingGroups: [], externalHandicap: false, defaultFormID: "stableford", maxPerBay: 4, evenings: 7,
    matchPoints: { win: 1, draw: 0.5, loss: 0 }, sidePrizes: { enabled: true, points: 1 },
  });
  assert.deepEqual(gammelt.table.trianglePoints, [1, 0.5, 0]);
});

test("trekk matcher", () => {
  for (const t of fil.trekninger) {
    const deltakere = (t.deltakere as any[]).map((d) => makePlayer(d.id, d.name));
    assert.deepEqual(drawMatches(deltakere, t.omgang, map(t.stilling)), t.par, t.navn);
  }
});

test("trekk matcher: rekkefølgen", () => {
  const fem = ["a", "b", "c", "d", "e"].map((id) => makePlayer(id, "Spiller " + id.toUpperCase()));
  const par5 = drawMatches(fem, 0, new Map());
  assert.ok(par5.length === 2 && par5.filter((p) => p.length === 3).length === 1);
  assert.equal(par5.flat().length, 5);
  assert.ok(drawMatches(fem.slice(0, 4), 0, new Map()).every((p) => p.length === 2));
  assert.deepEqual(drawMatches(fem.slice(0, 3), 0, new Map()), [["a", "b", "c"]]);
  assert.deepEqual(drawMatches(fem.slice(0, 1), 0, new Map()), []);

  const sju = [["a", "Åse"], ["b", "Øyvind"], ["c", "Ærlig"], ["d", "Zorro"], ["e", "Anders"], ["f", "bjørn"], ["g", "Bjørn"]]
    .map(([id, name]) => makePlayer(id, name));
  assert.deepEqual(drawMatches(sju, 0, new Map()), [["e", "f"], ["g", "d"], ["c", "b", "a"]]);
  assert.deepEqual(drawMatches(sju, 1, new Map()), [["a", "b"], ["c", "d"], ["g", "f", "e"]]);
  const stilling = map({ a: 2, b: 0.5, c: 2, d: 1, e: 0, f: 3, g: 1 });
  assert.deepEqual(drawMatches(sju, 0, stilling), [["f", "c"], ["a", "g"], ["d", "b", "e"]]);
  assert.deepEqual(drawMatches(sju, 2, stilling), [["f", "c"], ["a", "g"], ["d", "b", "e"]]);
});
