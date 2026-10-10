// HelperTests.swift: avrunding og sortering som i JS. Tall: Fixtures/hjelpere.json.

import assert from "node:assert/strict";
import { test } from "node:test";
import { jsRound, norwegianCompare, norwegianLess, round2, roundAwayFromZero, roundHalf, sortedBy, norwegianString } from "../src/jsmath.ts";
import { fixture } from "./helpers.ts";

const fil = fixture("hjelpere");

test("Math.round er floor(x + 0,5)", () => {
  for (const [x, want] of fil.jsRound) assert.equal(jsRound(x), want, `Math.round(${x})`);
  assert.equal(jsRound(-2.5), -2);
  assert.equal(jsRound(2.5), 3);
  // Swift-motoren regner floor(x + 0,5), ikke V8s Math.round: 0,49999999999999994 + 0,5 = 1.
  assert.equal(jsRound(0.49999999999999994), 1);
});

test("rund2", () => {
  for (const [x, want] of fil.rund2) assert.equal(round2(x), want, `rund2(${x})`);
});

test("nærmeste halve", () => {
  for (const [x, want] of fil.naermesteHalve) assert.equal(roundHalf(x), want, `halve av ${x}`);
});

test("norsk localeCompare", () => {
  for (const [a, b, want] of fil.localeCompare) assert.equal(norwegianCompare(a, b), want, `'${a}'.localeCompare('${b}', 'no')`);
});

test("norsk sortering av navn", () => {
  assert.deepEqual(sortedBy(fil.sortert.inn as string[], norwegianLess), fil.sortert.ut);
});

test("Swifts .rounded() er bort fra null", () => {
  assert.equal(roundAwayFromZero(2.5), 3);
  assert.equal(roundAwayFromZero(-2.5), -3);
  assert.equal(roundAwayFromZero(-2.4), -2);
  assert.equal(roundAwayFromZero(0.49999999999999994), 0);
  assert.equal(norwegianString(1.5), "1,5");
  assert.equal(norwegianString(-0), "0");
});
