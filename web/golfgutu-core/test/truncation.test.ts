// TruncationTests.swift: avkorting. Tall: Fixtures/avkorting.json.

import assert from "node:assert/strict";
import { test } from "node:test";
import { decodeHoleScores, decodePlayer, decodeRound, makeRound } from "../src/models.ts";
import { roundNetTotal } from "../src/scoring.ts";
import {
  countingHoles,
  isTruncated,
  lowestCommonHole,
  pointsForEmptyHole,
  truncationCost,
  truncationRule,
  truncationRuleHelp,
  truncationRuleName,
  TRUNCATION_RULES,
  type TruncationRule,
} from "../src/truncation.ts";
import { fixture } from "./helpers.ts";

const fil = fixture("avkorting");
const spillere = (fil.spillere as any[]).map((p) => decodePlayer(p));

test("reglene er like PWA-en", () => {
  assert.deepEqual([...TRUNCATION_RULES], fil.regler.map((r: any) => r.id));
  TRUNCATION_RULES.forEach((r, i) => {
    assert.equal(truncationRuleName(r), fil.regler[i].navn);
    assert.equal(truncationRuleHelp(r), fil.regler[i].hjelp);
  });
});

test("avkortRegel", () => {
  assert.equal(truncationRule(makeRound({ avkortRegel: "null" })), "null");
  assert.equal(truncationRule(makeRound({ avkortRegel: null })), null);
  assert.equal(truncationRule(makeRound({ avkortRegel: "felles" })), "felles");
  assert.equal(truncationRule(makeRound({ avkortRegel: "" })), null);
});

test("tellende hull og poeng", () => {
  assert.equal(fil.saker.length, 10);
  for (const sak of fil.saker) {
    const r = decodeRound(sak.runde);
    const f = sak.forventet;
    assert.equal(countingHoles(r), f.tellendeHull, `${sak.navn}: tellendeHull`);
    assert.equal(isTruncated(r), f.erAvkortet, `${sak.navn}: erAvkortet`);
    if (f.poengForTomtHull != null) assert.equal(pointsForEmptyHole(r), f.poengForTomtHull);
    for (const p of spillere) assert.equal(roundNetTotal(r, p, spillere), f.poeng[p.id], `${sak.navn}: ${p.name}`);
  }
});

test("laveste felles hull", () => {
  for (const sak of fil.lavesteFellesHull) {
    const scores = new Map(Object.entries(sak.holeScores).map(([k, v]) => [k, decodeHoleScores(v)]));
    assert.equal(lowestCommonHole(makeRound({ holeCount: sak.holeCount, holeScores: scores })), sak.forventet, sak.navn);
  }
});

test("avkortingen koster", () => {
  const k = fil.avkortingenKoster;
  const roster = (k.spillere as any[]).map((p) => decodePlayer(p));
  const runde = decodeRound(k.runde);
  for (const sak of k.saker) {
    const rule = (TRUNCATION_RULES as readonly string[]).includes(sak.regel) ? (sak.regel as TruncationRule) : null;
    const svar = truncationCost(runde, sak.etter, rule, roster);
    const navn = `${sak.regel} etter ${sak.etter}`;
    assert.equal(svar.countingHoles, sak.tellende, `${navn}: tellende`);
    assert.equal(svar.holes, sak.av, `${navn}: av`);
    assert.deepEqual(svar.changes.map((c) => c.playerID), sak.endring.map((e: any) => e.spiller), `${navn}: rekkefølge`);
    assert.deepEqual(svar.changes.map((c) => c.before), sak.endring.map((e: any) => e.for));
    assert.deepEqual(svar.changes.map((c) => c.after), sak.endring.map((e: any) => e.etter));
    assert.deepEqual(svar.changes.map((c) => c.diff), sak.endring.map((e: any) => e.diff));
  }
  const felles = truncationCost(runde, 14, "felles", roster);
  assert.equal(felles.changes.length, 2);
  assert.ok(felles.changes[0].playerID === "a" && felles.changes[0].diff === -8);
  assert.ok(truncationCost(runde, 14, "nettopar", roster).changes.every((c) => c.diff >= 0));
});
