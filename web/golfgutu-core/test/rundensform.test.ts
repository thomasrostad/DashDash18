// RundensFormTests.swift: rundens resultat etter formen (`formResult`) og plasseringspoengene i tabellen.
// Tall: Fixtures/rundens-form.json (regnet for hånd, se «kilde»).

import assert from "node:assert/strict";
import { test } from "node:test";
import { formResult, placementPoints } from "../src/formplay.ts";
import { makePlayer, makeRound, type HoleScores, type Round } from "../src/models.ts";
import { decodeRuleset, encodeRuleset, golfgutuRules, type Ruleset } from "../src/ruleset.ts";
import { Season } from "../src/season.ts";
import { matchingTemplate, templateRules } from "../src/template.ts";
import { validateRuleset } from "../src/validation.ts";
import { fixture, map, TEST_COURSE } from "./helpers.ts";

const fil = fixture("rundens-form");

function round(gameType: string, id = gameType): Round {
  const holeScores = new Map<string, HoleScores>();
  for (const [p, list] of Object.entries(fil.scorer as Record<string, number[]>)) {
    holeScores.set(p, new Map(list.map((g, h) => [h, g] as [number, number])));
  }
  return makeRound({
    id, gameType, holeCount: 18, holeStart: 0, course: TEST_COURSE, hcpAllowance: 1,
    holeScores, locked: false, playingHandicaps: map(fil.spillehandicap),
  });
}

test("formresultatet", () => {
  for (const form of fil.former) {
    const result = formResult(round(form.gameType), [], golfgutuRules());
    if (form.rader === null) {
      assert.equal(result, null, form.gameType);
      continue;
    }
    assert.ok(result !== null, `${form.gameType}: mangler resultat`);
    assert.deepEqual(result.rows.map((r) => r.players), form.rader.map((r: any) => [r.spiller]), `${form.gameType}: rekkefølge`);
    assert.deepEqual(result.rows.map((r) => r.score), form.rader.map((r: any) => r.score), `${form.gameType}: sum`);
    assert.deepEqual(result.rows.map((r) => r.holes), form.rader.map((r: any) => r.hull), `${form.gameType}: hull`);
    assert.deepEqual(result.rows.map((r) => r.rank), form.rader.map((r: any) => r.plass), `${form.gameType}: plass`);
  }
});

// MARK: Plasseringspoeng

function placementRules(scale: number[]): Ruleset {
  const r = golfgutuRules();
  r.table.pointsSource = "placement";
  r.table.placementPoints = scale;
  return r;
}

const asObject = (m: Map<string, number>) => Object.fromEntries(m);

test("plasseringspoeng etter formen: b 11, a 12, c 16 gir 1., 2. og 3. plass", () => {
  const p = placementPoints(round("slag-netto"), [], placementRules([10, 6, 4]));
  assert.deepEqual(asObject(p), { b: 10, a: 6, c: 4 });
});

test("delt plass deler poengene for plassene, og plasser etter skalaen gir 0", () => {
  const r = round("slag-brutto");
  r.holeScores.set("b", new Map([[0, 4], [1, 5], [2, 3]])); // b går 12 som a
  const p = placementPoints(r, [], placementRules([10, 6]));
  assert.deepEqual(asObject(p), { a: 8, b: 8, c: 0 });
});

// Netto stableford har ikke noe formresultat: plassen kommer fra stablefordsummen. Netto: a 4 5 3
// (2 + 1 + 3 = 6), b 3 4 4 (3 + 2 + 2 = 7), c 4 5 7 (2 + 1 + 0 = 3). Stablefordveien (`roundPoints`)
// finner spilleren i troppen før spillehandicapet brukes.
test("plassering i netto stableford: fra stablefordsummen", () => {
  const roster = ["a", "b", "c"].map((id) => makePlayer(id, id.toUpperCase()));
  const p = placementPoints(round("stableford"), roster, placementRules([10, 6, 4]));
  assert.deepEqual(asObject(p), { b: 10, a: 6, c: 4 });
});

test("uten egen skala gjelder standarden (25, 20, 16 …)", () => {
  const p = placementPoints(round("stableford-brutto"), [], placementRules([]));
  assert.deepEqual(asObject(p), { a: 25, b: 20, c: 16 });
});

test("tabellen teller plasseringspoengene: to runder slagspill netto", () => {
  const rules = placementRules([10, 6, 4]);
  rules.table.counting = { unit: "round", best: null };
  const roster = ["a", "b", "c"].map((id) => makePlayer(id, id.toUpperCase()));
  const board = new Season(roster, [round("slag-netto"), round("slag-netto", "slag-netto-2")], [], rules).jacketBoard();
  assert.deepEqual(board.map((r) => r.player.id), ["b", "a", "c"]);
  assert.deepEqual(board.map((r) => r.total), [20, 12, 8]);
});

test("Golfgutu skriver ikke de nye feltene, så JSON-en er som før", () => {
  const table = JSON.stringify((encodeRuleset(golfgutuRules()) as any).table);
  assert.ok(!table.includes("placementPoints") && !table.includes("pointsSource"));
  const r = placementRules([10, 6]);
  const back = decodeRuleset(JSON.parse(JSON.stringify(encodeRuleset(r))));
  assert.deepEqual(back.table, r.table);
});

test("plasseringspoengene kan ikke være negative, og tabellen som teller runder kan ikke telle matcher", () => {
  const r = placementRules([10, -1]);
  const issues = validateRuleset(r);
  assert.ok(issues.some((i) => i.field === "table.placementPoints" && i.message === "Plasseringspoengene kan ikke være negative."));
  assert.ok(issues.some((i) => i.field === "table.counting.unit"
    && i.message === "Tabellen teller runder (stableford eller plassering), så den kan ikke telle matcher. Velg runder eller kvelder."));
});

test("slagspill-serien: plassering, slagspill netto som standard, og et eget oppsett", () => {
  const r = templateRules("strokeSeries");
  assert.equal(r.table.pointsSource, "placement");
  assert.equal(r.formats.defaultFormID, "slag-netto");
  for (const f of ["slag-netto", "slag-brutto", "maks-score"]) assert.ok(r.formats.allowedFormIDs.includes(f), f);
  assert.equal(matchingTemplate(r), "strokeSeries");
  assert.equal(matchingTemplate(templateRules("stablefordSeries")), "stablefordSeries");
  assert.deepEqual(validateRuleset(r), []);
});
