// Veddemål på og av (steg 11, sql/052). Samme bryter som appens BetsSwitchRow (DashDash18Tests/VeddOverallTests.swift).
import { test } from "node:test";
import assert from "node:assert/strict";
import { BETS_TOGGLE_HELP, betsErrorText, enabledFromRow, setEnabledParams, toggledText } from "../src/bets.ts";

test("bets_set_enabled får turneringen, tom runde og på/av", () => {
  assert.deepEqual(setEnabledParams("c1", true), { p_competition_id: "c1", p_round_id: null, p_enabled: true });
  assert.deepEqual(setEnabledParams("c1", false), { p_competition_id: "c1", p_round_id: null, p_enabled: false });
});

test("av som standard, og skjult uten 052", () => {
  assert.equal(enabledFromRow({ bets_enabled: true }, null), true);
  assert.equal(enabledFromRow({ bets_enabled: false }, null), false);
  assert.equal(enabledFromRow(null, null), false);
  // Ukjent kolonne: 052 er ikke kjørt.
  assert.equal(enabledFromRow(null, { code: "42703" }), null);
  assert.equal(enabledFromRow(null, { code: "PGRST204" }), null);
  assert.throws(() => enabledFromRow(null, { code: "42501" }));
});

test("tekstene", () => {
  assert.equal(toggledText(true), "Veddemål er slått på.");
  assert.match(toggledText(false), /gjøres opp som før/);
  assert.equal(betsErrorText({ code: "42501", message: "Bare arrangøren slår veddemål av og på" }), "Bare arrangøren slår veddemål av og på.");
  assert.equal(betsErrorText({ code: "PGRST202" }), "Veddemål kan ikke slås på før databasen er oppdatert.");
  assert.equal(betsErrorText({ code: "P0002", message: "Fant ikke turneringen" }), "Fant ikke turneringen");
  assert.ok(!BETS_TOGGLE_HELP.includes("—"));
});
