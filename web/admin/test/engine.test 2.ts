import { test } from "node:test";
import assert from "node:assert/strict";
import { decodeRuleset, encodeRuleset, matchingTemplate, templateRules, validateRuleset } from "../src/engine.ts";

test("ny turnering får samme regelsett som appen", () => {
  const golfgutu = templateRules("matchSeries");
  assert.deepEqual(validateRuleset(golfgutu), []);
  // Ordet for dagen lagres bare når det er valgt, og er ikke en endring fra oppsettet.
  const r = templateRules("stablefordSeries");
  r.dayTerm = "playingDay";
  const json = encodeRuleset(r);
  assert.equal(json.dayTerm, "playingDay");
  assert.equal(matchingTemplate(decodeRuleset(json)), "stablefordSeries");
  assert.equal("dayTerm" in encodeRuleset(golfgutu), false);
});
