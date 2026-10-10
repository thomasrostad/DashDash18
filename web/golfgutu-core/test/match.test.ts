// MatchTests.swift: match hull for hull. Tall: Fixtures/match.json.

import assert from "node:assert/strict";
import { test } from "node:test";
import {
  holeDiff,
  holeMatchFor,
  holeWinner,
  isDecidedHoleByHole,
  matchesIn,
  matchInvolves,
  matchShortText,
  matchSides,
  matchStanding,
  matchText,
  outcomeForA,
  pointsForOutcome,
  sideHandicap,
  sideNet,
  strokeOffset,
} from "../src/match.ts";
import { decodeMatch, decodePlayer, decodeRound, isTriangle, matchResultFromStored } from "../src/models.ts";
import { golfgutuRules } from "../src/ruleset.ts";
import { countingHoles } from "../src/truncation.ts";
import { fixture } from "./helpers.ts";

const fil = fixture("match");
const saker = (fil.saker as any[]).map((s) => ({ ...s, spillere: (s.spillere as any[]).map((p) => decodePlayer(p)), runde: decodeRound(s.runde) }));
const sorted = (xs: string[]) => [...xs].sort();

test("alle sakene gir samme svar som PWA-en", () => {
  assert.equal(saker.length, 27);
  for (const sak of saker) {
    const r = sak.runde;
    const roster = sak.spillere;
    assert.equal(countingHoles(r), sak.tellendeHull, sak.navn);
    assert.equal(isDecidedHoleByHole(r), sak.avgjoresHullForHull, `${sak.navn}: avgjoresHullForHull`);
    for (const p of roster) {
      assert.equal(holeMatchFor(p.id, r)?.matchNo ?? null, sak.hullMatch[p.id] ?? null, `${sak.navn}: hullMatchFor ${p.id}`);
    }
    const ms = matchesIn(r);
    assert.equal(ms.length, sak.matcher.length);
    ms.forEach((m, i) => {
      const js = sak.matcher[i];
      const navn = `${sak.navn} match ${m.matchNo ?? 0}`;
      const s = matchSides(m, r);
      assert.deepEqual(sorted(s.a), sorted(js.sider.a), `${navn}: side A`);
      assert.deepEqual(sorted(s.b), sorted(js.sider.b), `${navn}: side B`);
      assert.deepEqual(s.c, js.sider.c ?? null, `${navn}: side C`);
      assert.equal(isTriangle(m), js.trekant, `${navn}: trekant`);
      for (const [pid, gjelder] of Object.entries(js.gjelder)) assert.equal(matchInvolves(m, pid, r), gjelder, `${navn}: gjelder ${pid}`);
      assert.equal(sideHandicap(s.a, r, roster), js.sideHandicapA, `${navn}: sideHandicap A`);
      assert.equal(sideHandicap(s.b, r, roster), js.sideHandicapB, `${navn}: sideHandicap B`);
      const lav = strokeOffset(m, r, roster);
      assert.equal(lav, js.matchSlag, `${navn}: matchSlag`);
      for (let h = 0; h < js.hullVinner.length; h++) {
        assert.equal(holeWinner(m, h, r, roster), js.hullVinner[h], `${navn}: hull ${h + 1}`);
        assert.equal(sideNet(s.a, h, lav, r, roster), js.sideNettoA[h], `${navn}: netto A hull ${h + 1}`);
        assert.equal(sideNet(s.b, h, lav, r, roster), js.sideNettoB[h], `${navn}: netto B hull ${h + 1}`);
      }
      const d = holeDiff(m, r, roster);
      assert.equal(d?.up ?? null, js.hullDiff?.opp ?? null, `${navn}: hullDiff`);
      assert.equal(d?.played ?? null, js.hullDiff?.spilt ?? null, `${navn}: hullDiff`);
      assert.equal(outcomeForA(m, r, roster), js.utfallForA, `${navn}: utfallForA`);
      for (const [pid, f] of Object.entries<any>(js.stilling)) {
        const st = matchStanding(m, pid, r, roster);
        if (f === null) {
          assert.equal(st, null, `${navn}: stilling ${pid}`);
          continue;
        }
        assert.ok(st !== null && st.up === f.opp && st.played === f.spilt && st.remaining === f.igjen && st.decided === f.avgjort, `${navn}: stilling ${pid}`);
        assert.deepEqual(sorted(st.opponents), sorted(f.motstandere), `${navn}: motstandere ${pid}`);
        assert.equal(matchText(st), f.tekst, `${navn}: tekst ${pid}`);
        assert.equal(matchShortText(st), f.kort, `${navn}: kort ${pid}`);
      }
    });
  }
});

test("PWA-testenes tall", () => {
  const sak = (navn: string) => saker.find((s) => s.navn === navn)!;
  const uten = sak("16 hull uavkortet");
  const m = uten.runde.matches[0];
  assert.deepEqual(holeDiff(m, uten.runde, uten.spillere), { up: -12, played: 16 });
  assert.equal(matchStanding(m, "b", uten.runde, uten.spillere)?.remaining, 2);
  const med = sak("avkortet felles etter 14");
  assert.deepEqual(holeDiff(m, med.runde, med.spillere), { up: -14, played: 14 });
  const st = matchStanding(m, "b", med.runde, med.spillere);
  assert.equal(st?.remaining, 0);
  assert.ok(matchText(st).startsWith("Vunnet"));
  const np = sak("nettopar etter 14");
  assert.equal(holeDiff(m, np.runde, np.spillere)?.played, 16);

  const h1 = sak("hull 1 fourball");
  const ms = h1.runde.matches;
  assert.equal(holeWinner(ms[1], 0, h1.runde, h1.spillere), 1);
  assert.equal(holeWinner(ms[0], 0, h1.runde, h1.spillere), null);
  assert.equal(matchShortText(matchStanding(ms[1], "e", h1.runde, h1.spillere)), "1 opp");
  assert.equal(matchShortText(matchStanding(ms[1], "h", h1.runde, h1.spillere)), "1 ned");
  assert.equal(matchShortText(matchStanding(ms[0], "a", h1.runde, h1.spillere)), "—");
  const tre = sak("bare trekant");
  assert.equal(isDecidedHoleByHole(tre.runde), false);
  assert.equal(holeMatchFor("a", tre.runde), null);

  const rb = sak("Rostad mot Breivik, lag på én");
  const rbSt = matchStanding(rb.runde.matches[0], "rostad", rb.runde, rb.spillere);
  assert.ok(rbSt?.up === -5 && rbSt?.played === 9);
  const tt = sak("to mot tre");
  assert.equal(matchStanding(tt.runde.matches[0], "alm", tt.runde, tt.spillere)?.up, -1);

  const ps = sak("scramble-2: lag på 5 mot lag på 5");
  assert.equal(strokeOffset(ps.runde.matches[0], ps.runde, ps.spillere), 5);
  assert.equal(sideHandicap(["g2a", "g2b"], ps.runde, ps.spillere), 5);
  assert.equal(sideHandicap(["g3", "g1"], ps.runde, ps.spillere), 5);
  const sd = sak("gruppe 2 mot gruppe 3");
  assert.equal(strokeOffset(sd.runde.matches[0], sd.runde, sd.spillere), 5);
  const full = golfgutuRules();
  full.formats.matchStrokes = "fullHandicap";
  assert.equal(strokeOffset(sd.runde.matches[0], sd.runde, sd.spillere, full), 0);
});

test("matchTekst: alle grenene", () => {
  assert.equal(fil.tekster.length, 15);
  for (const t of fil.tekster) {
    const st = t.stilling ? { up: t.stilling.opp, played: t.stilling.spilt, remaining: t.stilling.igjen, decided: t.stilling.avgjort, opponents: [] } : null;
    assert.equal(matchText(st), t.tekst, JSON.stringify(t.stilling));
    assert.equal(matchShortText(st), t.kort, JSON.stringify(t.stilling));
  }
  assert.equal(matchShortText(null), "—");
  assert.equal(matchText({ up: 3, played: 16, remaining: 2, decided: true, opponents: [] }), "Vunnet 3&2");
});

test("poeng for utfall", () => {
  for (const u of fil.poengForUtfall) assert.equal(pointsForOutcome(u.utfall), u.poeng);
  const annen = { win: 2, draw: 1, loss: 0 };
  assert.equal(pointsForOutcome(1, annen), 2);
  assert.equal(pointsForOutcome(0.5, annen), 1);
});

test("manuelt resultat", () => {
  assert.equal(matchResultFromStored("A"), "a");
  assert.equal(matchResultFromStored("b"), "b");
  assert.equal(matchResultFromStored("halved"), "halved");
  assert.equal(matchResultFromStored("H"), "halved");
  assert.equal(matchResultFromStored(""), null);
  assert.equal(matchResultFromStored(null), null);
  const m = decodeMatch({ playerA: "a", playerB: "b", result: "" });
  assert.ok(m.result === null && !isTriangle(m));
});
