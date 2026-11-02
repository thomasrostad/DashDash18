// HandicapWHSTests.swift. Tall: Fixtures/handicap-whs.json (golfreglene og som PWA-en).

import assert from "node:assert/strict";
import { test } from "node:test";
import { courseHandicap, effectiveHandicap, teamBasis, teamHandicapByIDs } from "../src/handicap.ts";
import { decodePlayer, decodeRound } from "../src/models.ts";
import { decodeRuleset, encodeRuleset, golfgutuRules, maxStrokesLimit, type HandicapCalculation, type Ruleset } from "../src/ruleset.ts";
import { handicapStrokes, roundNetTotal } from "../src/scoring.ts";
import { fixture } from "./helpers.ts";

const fil = fixture("handicap-whs");

function rulesFor(calculation: HandicapCalculation): Ruleset {
  const r = golfgutuRules();
  r.handicap.calculation = calculation;
  return r;
}

const saker = (fil.saker as any[]).map((s) => ({
  navn: s.navn as string,
  regning: s.regning as HandicapCalculation,
  spillere: (s.spillere as any[]).map((p) => decodePlayer(p)),
  runde: decodeRound(s.runde),
  sjekker: s.sjekker as any[],
}));

test("slag per hull", () => {
  for (const s of fil.slag) {
    for (const calc of ["pwa", "whs"] as const) {
      assert.equal(handicapStrokes(s.handicap, s.strokeIndex, s.antall, rulesFor(calc)), s[calc], `${calc}: ${JSON.stringify(s)}`);
    }
  }
});

test("uten regelsett er som PWA-en", () => {
  for (const s of fil.slag) assert.equal(handicapStrokes(s.handicap, s.strokeIndex, s.antall), s.pwa);
});

test("netto dobbel bogey", () => {
  for (const n of fil.nettoDobbelBogey) {
    assert.equal(maxStrokesLimit({ type: "netDoubleBogey" }, n.par, n.slag), n.forventet);
  }
});

test("dekoding", () => {
  for (const d of fil.dekoding) {
    assert.equal(decodeRuleset(d.regelsett).handicap.calculation, d.forventet, d.navn);
  }
});

test("feltet skrives bare for golfreglene", () => {
  assert.equal((encodeRuleset(golfgutuRules()).handicap as any).calculation, undefined);
  const whs = rulesFor("whs");
  assert.equal((encodeRuleset(whs).handicap as any).calculation, "whs");
  assert.equal(decodeRuleset(encodeRuleset(whs)).handicap.calculation, "whs");
});

test("sakene i fixturen", () => {
  assert.ok(saker.length >= 20);
  for (const sak of saker) {
    const rules = rulesFor(sak.regning);
    const spiller = (id: string | null) => sak.spillere.find((p) => p.id === id) ?? null;
    for (const s of sak.sjekker) {
      let svar: number;
      switch (s.fn) {
        case "effectiveHandicap": svar = effectiveHandicap(spiller(s.spiller), sak.runde, sak.spillere, rules); break;
        case "banehandicap": svar = courseHandicap(spiller(s.spiller), sak.runde, rules); break;
        case "lagGrunnlag": svar = teamBasis(spiller(s.spiller), sak.runde, rules); break;
        case "lagHandicap": svar = teamHandicapByIDs(sak.runde, s.spillere ?? [], sak.spillere, rules); break;
        case "stableford": svar = roundNetTotal(sak.runde, spiller(s.spiller), sak.spillere, rules); break;
        default: assert.fail(`ukjent funksjon ${s.fn}`);
      }
      assert.equal(svar, s.forventet, `${sak.navn}: ${s.fn}(${s.spiller ?? (s.spillere ?? []).join(",")})`);
    }
  }
});

test("pwa-sakene gir dagens tall", () => {
  for (const sak of saker.filter((s) => s.regning === "pwa")) {
    for (const p of sak.spillere) {
      assert.equal(effectiveHandicap(p, sak.runde, sak.spillere, rulesFor("pwa")), effectiveHandicap(p, sak.runde, sak.spillere), `${sak.navn}: ${p.id}`);
    }
  }
});
