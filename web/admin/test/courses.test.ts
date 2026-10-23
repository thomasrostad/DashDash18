// Lage og endre baner (pakke 2, punkt 4). Samme tilfeller som appens BanerDraftTests (DashDash18Tests/BanerTests.swift).
import { test } from "node:test";
import assert from "node:assert/strict";
import { DEFAULT_PAR } from "../../golfgutu-core/src/course.ts";
import {
  courseSummary, deleteErrorText, draftFromRows, draftPar, fillStandardPar, fillStandardText, holeList, newDraft,
  saveErrorText, saveParams, setHoleCount, tapPar, validate, type CourseDraft,
} from "../src/courses.ts";

function draft(pars: (number | null)[], name = "Testbanen"): CourseDraft {
  const d = newDraft(pars.length);
  return { ...d, name, holes: d.holes.map((h, i) => ({ ...h, par: pars[i] })) };
}
const standard18 = [...DEFAULT_PAR];
const standard9 = DEFAULT_PAR.slice(0, 9);
const errors = (d: CourseDraft) => validate(d).issues.filter((i) => i.blocking).map((i) => i.message);
const warnings = (d: CourseDraft) => validate(d).issues.filter((i) => !i.blocking).map((i) => i.message);

test("ny bane er tom og gjetter ikke par", () => {
  const d = newDraft();
  assert.equal(d.holes.length, 18);
  assert.ok(d.holes.every((h) => h.par === null));
  assert.equal(draftPar(d), null);
  assert.deepEqual(errors(d), ["Gi banen et navn."]);
  assert.deepEqual(warnings(d), ["Ingen par er skrevet inn. Banen lagres, men står som ikke satt opp."]);
});

test("banen uten par lagres som ikke satt opp", () => {
  const v = validate({ ...newDraft(), name: "Ny bane" }).values!;
  assert.equal(v.name, "Ny bane");
  assert.deepEqual(v.holes, []);
  assert.equal(v.externalName, null);
  assert.equal(v.courseRating, null);
  assert.equal(v.slopeRating, null);
});

test("gyldig bane med indeks", () => {
  let d = draft(standard18);
  d = { ...d, courseRatingText: "71,4", slopeText: " 128 ", externalName: "Testbanen GC",
    holes: d.holes.map((h, i) => ({ ...h, strokeIndexText: String(18 - i) })) };
  const r = validate(d);
  assert.deepEqual(r.issues, []);
  assert.equal(r.values!.courseRating, 71.4);
  assert.equal(r.values!.slopeRating, 128);
  assert.equal(r.values!.externalName, "Testbanen GC");
  assert.equal(r.values!.holes.length, 18);
  assert.deepEqual(r.values!.holes[0], { hole_number: 1, par: 4, stroke_index: 18, length_m: null });
  assert.equal(draftPar(d), 72);
  assert.deepEqual(saveParams("k1", null, r.values!), {
    p_club_id: "k1", p_course_id: null, p_name: "Testbanen", p_external_name: "Testbanen GC", p_course_rating: 71.4,
    p_slope_rating: 128, p_in_use: true, p_holes: r.values!.holes,
  });
});

test("manglende par på noen hull sperrer", () => {
  const pars: (number | null)[] = [...standard18];
  pars[2] = null; pars[11] = null;
  const d = draft(pars);
  assert.deepEqual(errors(d), ["Par mangler på hull 3 og 12. Les det av skjermen."]);
  assert.equal(validate(d).values, null);
});

test("lik indeks på to hull sperrer", () => {
  const d = draft(standard9);
  d.holes.forEach((h, i) => { h.strokeIndexText = String(i + 1); });
  d.holes[4].strokeIndexText = "2";
  assert.deepEqual(errors(d), ["Hull 2 og 5 har samme indeks (2)."]);
});

test("indeksen må være 1 til antall hull", () => {
  const d = draft(standard9);
  d.holes.forEach((h, i) => { h.strokeIndexText = String(i + 1); });
  d.holes[8].strokeIndexText = "10";
  d.holes[7].strokeIndexText = "0";
  assert.deepEqual(errors(d), ["Hull 8: indeks må være mellom 1 og 9, eller stå tom.", "Hull 9: indeks må være mellom 1 og 9, eller stå tom."]);
  d.holes[7].strokeIndexText = "x";
  assert.ok(errors(d).includes("Hull 8: indeks må være mellom 1 og 9, eller stå tom."));
});

test("manglende indeks er bare en advarsel", () => {
  const d = draft(standard9);
  d.holes[0].strokeIndexText = "1";
  assert.deepEqual(errors(d), []);
  assert.deepEqual(warnings(d), ["Indeks mangler på hull 2, 3, 4, 5, 6, 7, 8 og 9. Den trengs bare når appen selv deler ut slagene."]);
  assert.equal(validate(d).values!.holes[1].stroke_index, null);
});

test("rar lengde gir advarsel, men sperrer ikke", () => {
  const d = draft(standard9);
  d.holes[0].lengthText = "165"; d.holes[2].lengthText = "150"; d.holes[1].lengthText = "585";
  assert.deepEqual(errors(d), []);
  const w = warnings(d);
  assert.ok(w.includes("Hull 1: 165 m er uvanlig for en par 4. Stemmer det med skjermen?"));
  assert.ok(w.includes("Hull 2: 585 m er uvanlig for en par 5. Stemmer det med skjermen?"));
  assert.ok(!w.some((m) => m.startsWith("Hull 3:")));
  assert.equal(validate(d).values!.holes[0].length_m, 165);
});

test("lengde utenfor databasens grense og ugyldig par sperrer", () => {
  const d = draft(standard9);
  d.holes[0].lengthText = "701"; d.holes[1].lengthText = "49"; d.holes[2].lengthText = "lang";
  assert.deepEqual(errors(d), [1, 2, 3].map((n) => `Hull ${n}: lengden må være mellom 50 og 700 meter, eller stå tom.`));
  const p = draft(standard9);
  p.holes[3].par = 7;
  assert.deepEqual(errors(p), ["Hull 4: par må være mellom 3 og 6."]);
});

test("course rating og slope", () => {
  for (const [text, expected] of [["72", 72], ["71,4", 71.4], ["71.46", 71.5], ["", null], ["  ", null]] as const) {
    assert.equal(validate({ ...draft(standard9), courseRatingText: text }).values!.courseRating, expected, text);
  }
  for (const text of ["49,9", "90,1", "abc"]) {
    assert.deepEqual(errors({ ...draft(standard9), courseRatingText: text }), ["Course Rating må være et tall mellom 50 og 90, eller stå tom."], text);
  }
  for (const text of ["54", "156", "113,5", "x"]) {
    assert.deepEqual(errors({ ...draft(standard9), slopeText: text }), ["Slope må være et heltall mellom 55 og 155, eller stå tom."], text);
  }
});

test("navnets lengde, og navnet i simulatoren bare for simulatorbaner", () => {
  assert.deepEqual(errors(draft(standard9, "x".repeat(81))), ["Navnet kan ha høyst 80 tegn."]);
  const d = { ...draft(standard9, "x".repeat(80)), externalName: "y".repeat(81) };
  assert.deepEqual(errors(d), ["Navnet i simulatoren kan ha høyst 80 tegn."]);
  assert.deepEqual(errors({ ...d, kind: "course" }), []);
  assert.equal(validate({ ...d, externalName: "Sim", kind: "course" }).values!.externalName, null);
});

test("bytt antall hull beholder de ni første", () => {
  let d = draft(standard18);
  d.holes[0].strokeIndexText = "7";
  d = setHoleCount(d, 9);
  assert.equal(d.holes.length, 9);
  assert.equal(d.holes[0].strokeIndexText, "7");
  assert.equal(draftPar(d), 36);
  d = setHoleCount(d, 18);
  assert.equal(d.holes.length, 18);
  assert.deepEqual(d.holes[9], { number: 10, par: null, strokeIndexText: "", lengthText: "" });
  assert.equal(draftPar(d), null);
  assert.equal(setHoleCount(d, 12).holes.length, 18);
});

test("fyll standard par og trykk på par", () => {
  const d = newDraft(18);
  assert.equal(fillStandardText(d), "Fyll standard par 72");
  assert.equal(fillStandardText(newDraft(9)), "Fyll standard par 36");
  let e = tapPar(d, 3, 1);
  assert.equal(e.holes[0].par, 3);
  assert.equal(fillStandardText(e), "Fyll tomme hull med standard par");
  e = fillStandardPar(e);
  assert.equal(e.holes[0].par, 3, "par som er skrevet inn, røres ikke");
  assert.deepEqual(e.holes.slice(1).map((h) => h.par), standard18.slice(1));
  assert.equal(tapPar(e, 3, 1).holes[0].par, null, "trykk på valgt par igjen tømmer hullet");
});

test("fra lagrede rader", () => {
  const rows = [9, 8, 7, 6, 5, 4, 3, 2, 1].map((n) => ({ course_id: "c", hole_number: n, par: 4, stroke_index: n === 1 ? null : n, length_m: n * 50 }));
  const d = draftFromRows({ id: "c", club_id: "k", name: "Ni hull", external_name: null, course_rating: 35.5, slope_rating: 120, in_use: false }, rows);
  assert.equal(d.holes.length, 9);
  assert.equal(d.name, "Ni hull");
  assert.equal(d.courseRatingText, "35,5");
  assert.equal(d.slopeText, "120");
  assert.equal(d.inUse, false);
  assert.equal(d.kind, "simulator");
  assert.deepEqual(d.holes[0], { number: 1, par: 4, strokeIndexText: "", lengthText: "50" });
  assert.deepEqual(d.holes[8], { number: 9, par: 4, strokeIndexText: "9", lengthText: "450" });
  assert.equal(draftFromRows({ id: "c", club_id: "k", name: "x", external_name: null, course_rating: null, slope_rating: null, in_use: true }, []).holes.length, 18);
});

test("hulliste, oppsummering og feil", () => {
  assert.equal(holeList([4]), "hull 4");
  assert.equal(holeList([4, 9]), "hull 4 og 9");
  assert.equal(holeList([1, 2, 3]), "hull 1, 2 og 3");
  assert.equal(courseSummary([]), "Ikke satt opp");
  assert.equal(courseSummary(standard9.map((par, i) => ({ course_id: "c", hole_number: i + 1, par, stroke_index: null, length_m: null }))), "Par 36 · 9 hull");
  assert.equal(saveErrorText({ code: "23505", message: "duplicate key value violates unique constraint courses_club_name" }, "Holmenkollen"),
    "Det finnes allerede en bane som heter «Holmenkollen».");
  assert.equal(saveErrorText({ code: "23505", message: "course_holes_stroke_index_key" }, "x"), "To hull har samme indeks.");
  assert.match(deleteErrorText({ code: "23503", message: "fk" }), /^Banen er brukt i en runde/);
});
