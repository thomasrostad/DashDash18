import { test } from "node:test";
import assert from "node:assert/strict";
import { kindText, longDate, timeText, todayISO } from "../src/text.ts";

test("norske datoer og tekster", () => {
  assert.equal(longDate("2026-10-08", new Date("2026-10-10")), "torsdag 8. oktober");
  assert.equal(longDate("2027-01-07", new Date("2026-10-10")), "torsdag 7. januar 2027");
  assert.equal(kindText("fun"), "Morroturnering");
  assert.equal(timeText("18:00:00"), "Kl. 18:00");
  assert.equal(timeText(null), null);
  assert.match(todayISO(new Date("2026-10-10T22:30:00Z")), /^2026-10-11$/);
});
