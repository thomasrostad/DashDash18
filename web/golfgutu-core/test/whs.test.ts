// WHSTests.swift. Tall: Fixtures/whs.json.

import assert from "node:assert/strict";
import { test } from "node:test";
import {
  decodeWHSScore,
  lowHandicapIndex,
  maximumHoleScore,
  roundTenth,
  scoreDifferential,
  selection,
  strokesReceived,
  whsCourseHandicap,
  whsHistory,
} from "../src/whs.ts";
import { fixture } from "./helpers.ts";

const fil = fixture("whs");

test("banehandicap", () => {
  for (const c of fil.banehandicap) assert.equal(whsCourseHandicap(c.index, c.slope, c.courseRating, c.par), c.forventet, `indeks ${c.index}`);
});

test("slag fått og plusshandicap", () => {
  for (const s of fil.slagFatt) assert.equal(strokesReceived(s.banehandicap, s.indeks), s.forventet, `CH ${s.banehandicap}, indeks ${s.indeks}`);
});

test("høyeste hullscore", () => {
  for (const m of fil.hoyesteHullscore) assert.equal(maximumHoleScore(m.par, m.indeks, m.banehandicap ?? null), m.forventet);
});

test("score differential", () => {
  for (const d of fil.differential) assert.equal(scoreDifferential(d.justert, d.courseRating, d.slope), d.forventet);
});

test("tabellen for færre enn 20", () => {
  for (const u of fil.utvalg) {
    const sel = selection(u.scorer);
    assert.equal(sel?.lowest ?? null, u.laveste ?? null, `${u.scorer} scorer`);
    assert.equal(sel?.adjustment ?? null, u.justering ?? null, `${u.scorer} scorer`);
  }
});

test("netto dobbel bogey", () => {
  for (const n of fil.nettoDobbelBogey) {
    const rev = whsHistory([decodeWHSScore(n.score)]);
    assert.equal(rev.length, 1);
    assert.equal(rev[0].courseHandicap, n.banehandicap ?? null, n.navn);
    assert.equal(rev[0].adjustedGross, n.justert, n.navn);
    assert.equal(rev[0].differential, n.differential, n.navn);
  }
});

test("indeksen runde for runde", () => {
  for (const h of fil.historikk) {
    const rev = whsHistory((h.scorer as any[]).map((s) => decodeWHSScore(s)));
    assert.deepEqual(rev.map((r) => r.index), h.indekser, h.navn);
    assert.deepEqual(rev.map((r) => r.exceptionalReduction), h.reduksjon, h.navn);
    assert.deepEqual(rev.map((r) => r.capped), h.grense, h.navn);
  }
});

test("sortert på dato", () => {
  const h = fil.historikk[0];
  const scores = (h.scorer as any[]).map((s) => decodeWHSScore(s)).reverse();
  assert.deepEqual(whsHistory(scores).map((r) => r.index), h.indekser);
});

test("ni hull gir ingen differential", () => {
  const s = decodeWHSScore(fil.nettoDobbelBogey[0].score);
  s.holes = s.holes.slice(0, 9);
  assert.equal(whsHistory([s]).length, 0);
});

test("laveste indeks ser 365 dager bakover", () => {
  const est = fil.lavesteIndeks.etablert;
  for (const sak of fil.lavesteIndeks.saker) assert.equal(lowHandicapIndex(est, sak.sisteScore), sak.forventet ?? null, sak.sisteScore);
});

test("avrunding til tidel", () => {
  assert.equal(roundTenth(12.25), 12.3);
  assert.equal(roundTenth(-0.05), -0.1);
  assert.equal(roundTenth(5.424), 5.4);
});
