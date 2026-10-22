import { test } from "node:test";
import assert from "node:assert/strict";
import { GENERIC_ERROR, kindText, longDate, plainErrorText, timeText, todayISO } from "../src/text.ts";

test("feiltekst: norsk fra databasen vises, teknisk feil blir kort tekst", () => {
  assert.equal(plainErrorText({ code: "P0002", message: "Fant ikke turneringen" }), "Fant ikke turneringen");
  assert.equal(plainErrorText(new Error("Datoen står allerede i terminlista.")), "Datoen står allerede i terminlista.");
  assert.equal(plainErrorText({ code: "PGRST116", message: "JSON object requested, multiple (or no) rows returned" }), GENERIC_ERROR);
  assert.equal(plainErrorText({ code: "42501", message: "permission denied for table rounds" }), GENERIC_ERROR);
  assert.equal(plainErrorText({ code: "23505", message: "duplicate key value violates unique constraint \"x\"" }), GENERIC_ERROR);
  assert.equal(plainErrorText(new TypeError("Cannot read properties of undefined (reading 'id')")), GENERIC_ERROR);
  assert.equal(plainErrorText(null), GENERIC_ERROR);
});

test("norske datoer og tekster", () => {
  assert.equal(longDate("2026-10-08", new Date("2026-10-10")), "torsdag 8. oktober");
  assert.equal(longDate("2027-01-07", new Date("2026-10-10")), "torsdag 7. januar 2027");
  assert.equal(kindText("fun"), "Morroturnering");
  assert.equal(timeText("18:00:00"), "Kl. 18:00");
  assert.equal(timeText(null), null);
  assert.match(todayISO(new Date("2026-10-10T22:30:00Z")), /^2026-10-11$/);
});
