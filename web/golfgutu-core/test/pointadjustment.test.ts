// PointAdjustmentTests.swift: tilleggspoeng. Tall: Fixtures/tilleggspoeng.json, med rundene fra
// Fixtures/sesong-stableford.json.

import assert from "node:assert/strict";
import { test } from "node:test";
import { decodePlayer, decodePointAdjustment, decodeSideClaim } from "../src/models.ts";
import { decodeRuleset, GOLFGUTU, roundTablePoints } from "../src/ruleset.ts";
import { Season } from "../src/season.ts";
import { validateRuleset } from "../src/validation.ts";
import { fixture, stablefordRounds } from "./helpers.ts";

const fil = fixture("tilleggspoeng");
const sf = fixture("sesong-stableford");
const players = (sf.spillere as any[]).map((p) => decodePlayer(p));
const claims = (sf.claims as any[]).map((c) => decodeSideClaim(c));
const adjustments = (fil.tillegg as any[]).map((a) => decodePointAdjustment(a));

test("tilleggspoeng: fixturen", () => {
  const rounds = stablefordRounds(sf);
  for (const sak of fil.saker) {
    const rules = decodeRuleset(sak.regelsett);
    assert.deepEqual(validateRuleset(rules), [], sak.navn);
    const board = new Season(players, rounds, claims, rules, new Map(), adjustments).jacketBoard();
    assert.deepEqual(board.map((r) => r.player.id), sak.tavle.map((t: any) => t.id), sak.navn);
    board.forEach((row, i) => {
      const want = sak.tavle[i];
      assert.equal(row.total, want.total, `${sak.navn} ${want.id} total`);
      assert.equal(row.adjustment, want.tillegg, `${sak.navn} ${want.id} tillegg`);
    });
  }
});

test("tilleggspoeng: per spiller", () => {
  const season = new Season(players, stablefordRounds(sf), claims, GOLFGUTU, new Map(), adjustments);
  assert.deepEqual(season.adjustmentsFor("a").map((a) => a.reason), ["CP knockout challenge"]);
  assert.equal(season.adjustmentPoints("c"), -2);
  assert.equal(season.adjustmentPoints("ukjent"), 5);
  assert.ok(!season.jacketBoard().some((r) => r.player.id === "ukjent"));
});

test("tilleggspoeng: Golfgutu uendret uten tillegg", () => {
  const rounds = stablefordRounds(sf);
  const before = new Season(players, rounds, claims);
  assert.deepEqual(new Season(players, rounds, claims, GOLFGUTU, new Map(), []).jacketBoard(), before.jacketBoard());
  assert.ok(before.jacketBoard().every((r) => r.adjustment === 0));
  const withAdj = new Season(players, rounds, claims, GOLFGUTU, new Map(), adjustments);
  for (const old of before.jacketBoard()) {
    const row = withAdj.jacketBoard().find((r) => r.player.id === old.player.id)!;
    const extra = withAdj.adjustmentPoints(old.player.id);
    assert.equal(row.total, roundTablePoints(GOLFGUTU, old.total + extra));
    assert.equal(row.adjustment, extra);
    assert.deepEqual([row.duel, row.side, row.matches, row.holes, row.stableford], [old.duel, old.side, old.matches, old.holes, old.stableford]);
  }
});
