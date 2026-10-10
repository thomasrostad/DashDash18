// CourseTests.swift: bane og hull. Tall: Fixtures/bane.json.

import assert from "node:assert/strict";
import { test } from "node:test";
import {
  courseHasStrokeIndex,
  courseHoles,
  courseIsReady,
  DEFAULT_PAR,
  holesFromRows,
  holesWithOddLength,
  isValidPar,
  lengthMatchesPar,
  numberOfHoles,
} from "../src/course.ts";
import { decodeCourseHole, decodeCourseHoleRow, decodeRound, makeRound, type Course, type CourseHole, type PlayedHole } from "../src/models.ts";
import { fixture } from "./helpers.ts";

const fil = fixture("bane");
const course = (holes: CourseHole[] | null): Course => ({ id: null, name: null, par: null, courseRating: null, slopeRating: null, holes });

test("standardpar er par 72", () => {
  assert.deepEqual([...DEFAULT_PAR], fil.defaultPar);
  assert.equal(DEFAULT_PAR.reduce((a, b) => a + b, 0), 72);
});

test("par er et tall", () => {
  assert.ok(isValidPar(3) && isValidPar(6));
  assert.ok(!isValidPar(2) && !isValidPar(7) && !isValidPar(0) && !isValidPar(null));
});

test("bane er klar", () => {
  for (const sak of fil.baneErKlar) {
    const holes = sak.holes ? (sak.holes as any[]).map((h) => decodeCourseHole(h)) : null;
    assert.equal(courseIsReady(course(holes)), sak.klar, sak.navn);
  }
});

test("courseForRound", () => {
  assert.equal(fil.courseForRound.length, 20);
  for (const sak of fil.courseForRound) {
    const hull = courseHoles(decodeRound(sak.runde));
    const f = sak.forventet;
    if (f.par) assert.deepEqual(hull.map((h) => h.par), f.par, `${sak.navn}: par`);
    if (f.kortIndeks) assert.deepEqual(hull.map((h) => h.cardIndex), f.kortIndeks, `${sak.navn}: kortindeks`);
    if (f.strokeIndex) assert.deepEqual(hull.map((h) => h.strokeIndex), f.strokeIndex, `${sak.navn}: strokeIndex`);
    if (f.meters) assert.deepEqual(hull.map((h) => h.meters), f.meters, `${sak.navn}: meter`);
    if (f.parSum != null) assert.equal(hull.reduce((s, h) => s + h.par, 0), f.parSum, `${sak.navn}: parsum`);
    if (f.meter0 != null) assert.equal(hull[0].meters, f.meter0, `${sak.navn}: meter hull 1`);
    if (f.strokeIndexSortert) assert.deepEqual(hull.map((h) => h.strokeIndex).sort((a, b) => a - b), f.strokeIndexSortert);
    if (f.strokeIndex6 != null) assert.equal(hull[6].strokeIndex, f.strokeIndex6, `${sak.navn}: hull 7`);
  }
});

test("ni hull rangeres om til ni slagplasser", () => {
  const sak = fil.courseForRound.find((s: any) => s.navn.startsWith("ni egne hull"));
  const hull = courseHoles(decodeRound(sak.runde));
  const rang = hull.map((h) => h.strokeIndex);
  assert.ok(rang[6] === 1 && rang[4] === 2 && rang[1] === 3);
  assert.equal(rang[2], 9);
  assert.equal(hull[3].cardIndex, 9);
});

test("banehull fra rader", () => {
  const r = fil.banehullFraRader;
  const rows = (x: any[]) => x.map((y) => decodeCourseHoleRow(y));
  const atten = holesFromRows(rows(r.atten)).get("m")!;
  assert.equal(atten.length, 18);
  assert.deepEqual(atten.map((h) => h.par), fil.ektePar);
  assert.ok(atten[0].si === 1 && atten[17].si === 18);
  assert.ok(atten[0].meters === 300 && atten[17].meters === 317);
  assert.ok(courseIsReady(course(atten)));

  const utenLengde = holesFromRows(rows(r.utenLengde)).get("x")!;
  assert.equal(utenLengde[0].meters, null);
  assert.ok(courseIsReady(course(utenLengde)));
  assert.equal(holesFromRows(rows(r.ni)).get("n")!.length, 9);
  assert.deepEqual(holesFromRows(rows(r.stokket)).get("s")!.map((h) => h.par), fil.ektePar);

  const mangler = holesFromRows(rows(r.mangler7));
  assert.ok(mangler.has("h"));
  assert.equal(mangler.get("h"), null);
  assert.equal(holesFromRows(rows(r.tretten)).get("t"), null);
  assert.equal(holesFromRows([]).size, 0);

  const utenHcp = holesFromRows(rows(r.utenHcp)).get("u")!;
  assert.ok(courseIsReady(course(utenHcp)));
  assert.equal(utenHcp[0].si, null);
});

test("rader uten bane hoppes over", () => {
  const rader = [
    { courseId: null, holeNumber: 1, par: 4, hcpIndex: null, distanceMeters: null },
    { courseId: "", holeNumber: 1, par: 4, hcpIndex: null, distanceMeters: null },
  ];
  assert.equal(holesFromRows(rader).size, 0);
});

test("lengde passer paret", () => {
  for (const sak of fil.lengdePasserParet) {
    assert.equal(lengthMatchesPar(sak.par, sak.meters ?? null), sak.ok, `par ${sak.par} på ${sak.meters} m`);
  }
});

test("hull med rar lengde", () => {
  const bane: PlayedHole[] = (fil.ektePar as number[]).map((p, i) => ({ par: p, cardIndex: i + 1, meters: p === 3 ? 160 : p === 4 ? 370 : 480, strokeIndex: i + 1 }));
  assert.equal(holesWithOddLength(bane).length, 0);
  bane[3] = { par: 4, cardIndex: 4, meters: 165, strokeIndex: 4 };
  const funn = holesWithOddLength(bane);
  assert.equal(funn.length, 1);
  assert.deepEqual(funn[0], { number: 4, par: 4, meters: 165 });
});

test("bane har indeks", () => {
  const medSi: CourseHole[] = (fil.elisefarmPar as number[]).map((p, i) => ({ par: p, si: i + 1, meters: null }));
  assert.ok(courseHasStrokeIndex(course(medSi)));
  const enNull = medSi.map((h) => ({ ...h }));
  enNull[4].si = 0;
  assert.ok(!courseHasStrokeIndex(course(enNull)));
  const enMangler = medSi.map((h) => ({ ...h }));
  enMangler[4].si = null;
  assert.ok(!courseHasStrokeIndex(course(enMangler)));
  assert.ok(!courseHasStrokeIndex(course([])));
  assert.ok(!courseHasStrokeIndex(course(null)));
});

test("antall hull", () => {
  assert.equal(numberOfHoles(makeRound({ holeCount: 9 })), 9);
  assert.equal(numberOfHoles(makeRound({ holeCount: 18 })), 18);
  assert.equal(numberOfHoles(makeRound({ holeCount: null })), 18);
  assert.equal(numberOfHoles(makeRound({ holeCount: 7 })), 18);
  assert.equal(numberOfHoles(makeRound({ holeCount: 0 })), 18);
});
