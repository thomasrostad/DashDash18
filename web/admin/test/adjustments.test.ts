// Tilleggspoeng (sql/072). Samme grenser og tekster som appens Tilleggspoeng (TilleggspoengModel.swift),
// men kvarte poeng, så 0,25 for en closest to pin-konkurranse går.
import { test } from "node:test";
import assert from "node:assert/strict";
import { adjustmentInsert, adjustmentPointsText, adjustmentProblem } from "../src/adjustments.ts";

test("det som mangler før tillegget kan lagres", () => {
  assert.equal(adjustmentProblem(null, 1, "CTP"), "Velg en spiller.");
  assert.equal(adjustmentProblem("m1", 0, "CTP"), "Poengene kan ikke være 0.");
  assert.equal(adjustmentProblem("m1", 101, "CTP"), "Høyst 100 poeng av gangen.");
  assert.equal(adjustmentProblem("m1", 0.125, "CTP"), "Poengene kan ha høyst to desimaler.");
  assert.equal(adjustmentProblem("m1", 1, "   "), "Skriv en grunn.");
  assert.equal(adjustmentProblem("m1", 1, "x".repeat(81)), "Grunnen kan ha høyst 80 tegn.");
  assert.equal(adjustmentProblem("m1", 0.25, "CTP-konkurranse"), null);
  assert.equal(adjustmentProblem("m1", -0.5, "Rettelse"), null);
});

test("poengene med fortegn og desimalkomma", () => {
  assert.equal(adjustmentPointsText(1), "+1");
  assert.equal(adjustmentPointsText(0.25), "+0,25");
  assert.equal(adjustmentPointsText(-0.5), "−0,5");
});

test("raden som sendes, med trimmet grunn og uten kveld", () => {
  assert.deepEqual(adjustmentInsert("c", "s", "m", null, 0.25, "  CTP  "),
    { club_id: "c", season_id: "s", member_id: "m", event_id: null, points: 0.25, reason: "CTP" });
});
