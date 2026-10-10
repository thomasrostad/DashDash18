// SeasonTests.swift: sesongtabellen. Tall: Fixtures/sesong.json (regnet ut av db-nytt.js).

import assert from "node:assert/strict";
import { test } from "node:test";
import { decodePlayer, decodeRound, decodeSideClaim, makeMatch, makePlayer, makeRound, type MatchResult, type Player, type Round, type SideClaim } from "../src/models.ts";
import { golfgutuRules, type Ruleset } from "../src/ruleset.ts";
import { eveningCount, eveningDates, formatPoints, matchSum, Season, type SeasonMatchResult } from "../src/season.ts";
import { drawMatches } from "../src/triangle.ts";
import { fixture, obj } from "./helpers.ts";

const fil = fixture("sesong");

interface Sak {
  navn: string;
  spillere: Player[];
  runder: Round[];
  claims: SideClaim[];
  raw: any;
}

function sak(raw: any): Sak {
  return {
    navn: raw.navn,
    spillere: (raw.spillere as any[]).map((p) => decodePlayer(p)),
    runder: (raw.runder as any[]).map((r) => decodeRound(r)),
    claims: (raw.claims as any[]).map((c) => decodeSideClaim(c)),
    raw,
  };
}

const saker = (fil.saker as any[]).map(sak);
const byName = (navn: string) => saker.find((s) => s.navn === navn)!;
const season = (s: Sak, rules?: Ruleset) => new Season(s.spillere, s.runder, s.claims, rules);

/** Sjekker alt i én sak mot db-nytt.js. */
function sjekk(s: Sak, ruleset: Ruleset = golfgutuRules(), hva = "") {
  const navn = hva || s.navn;
  const raw = s.raw;
  const se = new Season(s.spillere, s.runder, s.claims, ruleset);
  s.runder.forEach((r, i) => assert.deepEqual(obj(se.roundPoints(i)), raw.rundePoeng[i], `${navn}: rundepoeng ${r.id}`));
  const like = (a: SeasonMatchResult[], b: any[]) =>
    a.length === b.length && a.every((x, i) => x.roundID === b[i].roundId && x.matchNo === (b[i].matchNo ?? null) && x.points === b[i].poeng && x.holes === b[i].hull && x.isTriangle === b[i].trekant);
  for (const p of s.spillere) {
    const f = raw.per[p.id];
    assert.ok(f, `${navn}: mangler ${p.id}`);
    const d = se.matchResults(p.id);
    assert.ok(like(d.counting, f.teller), `${navn}: teller ${p.id}`);
    assert.ok(like(d.dropped, f.stroket), `${navn}: stroket ${p.id}`);
    const sum = matchSum(d.counting);
    assert.deepEqual([sum.points, sum.holes, sum.matches], [f.matchSum.poeng, f.matchSum.hull, f.matchSum.matcher], `${navn}: matchSum ${p.id}`);
    assert.equal(se.matchTotals(p.id).holes, f.matchHull, `${navn}: matchHullFor ${p.id}`);
    const side = se.sidePrizeResults(p.id);
    assert.deepEqual(side.map((x) => x.roundID ?? ""), f.sidepremier.map((x: any) => x.roundId), `${navn}: sidepremier ${p.id}`);
    assert.deepEqual(side.map((x) => x.kind), f.sidepremier.map((x: any) => x.type));
    assert.deepEqual(side.map((x) => x.shared), f.sidepremier.map((x: any) => x.delt));
    assert.deepEqual(side.map((x) => x.points), f.sidepremier.map((x: any) => x.poeng));
    assert.equal(se.sidePrizePoints(p.id), f.sidepremiePoeng, `${navn}: sidepremiePoengFor ${p.id}`);
    assert.deepEqual(s.runder.map((_, i) => se.weightedRoundPoints(i, p.id)), f.rundePoengVektet, `${navn}: rundePoengVektet ${p.id}`);
    const tr = se.countingRounds(p.id);
    assert.deepEqual(tr.counting.map((x) => x.roundID ?? ""), f.tellendeRunder.teller.map((x: any) => x.roundId), `${navn}: tellende runder ${p.id}`);
    assert.deepEqual(tr.counting.map((x) => x.points), f.tellendeRunder.teller.map((x: any) => x.poeng));
    assert.deepEqual(tr.dropped.map((x) => x.points), f.tellendeRunder.stroket.map((x: any) => x.poeng));
    assert.equal(se.stablefordTotal(p.id), f.seasonTotal, `${navn}: seasonTotalNytt ${p.id}`);
  }
  const tavle = se.jacketBoard();
  assert.deepEqual(tavle.map((r) => r.player.id), raw.jakketavle.map((j: any) => j.id), `${navn}: jakketavla rekkefølge`);
  tavle.forEach((r, i) => {
    const j = raw.jakketavle[i];
    assert.deepEqual([r.total, r.duel, r.side], [j.total, j.duell, j.side], `${navn}: jakketavla poeng ${j.id}`);
    assert.deepEqual([r.matches, r.holes, r.played, r.stableford], [j.matcher, j.hull, j.spilte, j.stableford], `${navn}: jakketavla ${j.id}`);
  });
  const st = se.stablefordBoard();
  assert.deepEqual(st.map((r) => r.player.id), raw.stablefordtavle.map((x: any) => x.id), `${navn}: stablefordtavla`);
  assert.deepEqual(st.map((r) => r.total), raw.stablefordtavle.map((x: any) => x.total));
  assert.deepEqual(st.map((r) => r.played), raw.stablefordtavle.map((x: any) => x.played));
  assert.deepEqual(st.map((r) => r.dropped), raw.stablefordtavle.map((x: any) => x.stroket));
  assert.deepEqual(eveningDates(s.runder), raw.kveldsDatoer, `${navn}: kveldsDatoer`);
  assert.equal(eveningCount(s.runder), raw.antallKvelder);
  for (const [dato, tall] of raw.rundeNummer) assert.equal(se.roundNumber(dato), tall, `${navn}: rundeNummerFor ${dato}`);
  for (const [dato, ferdig] of raw.kveldErFerdig) assert.equal(se.isEveningFinished(dato), ferdig, `${navn}: kveldErFerdig ${dato}`);
}

test("alle sakene gir samme svar som PWA-en", () => {
  assert.equal(saker.length, 22);
  for (const s of saker) sjekk(s);
});

test("PWA-testenes tall", () => {
  let s = season(byName("fem knepne seire og to knusende tap"));
  assert.deepEqual(s.matchTotals("a"), { points: 5, holes: -31, matches: 7 });
  assert.ok(s.matchTotals("b").points === 2 && s.matchTotals("b").holes === 31);
  assert.equal(s.matchResults("a").dropped.length, 0);
  s = season(byName("tre seire og fire tap"));
  assert.equal(s.matchResults("a").counting[0].holes, 18);
  s = season(byName("lagseier og longest drive"));
  assert.ok(s.matchTotals("a").points === 1 && s.matchTotals("b").points === 1);
  assert.ok(s.sidePrizePoints("a") === 1 && s.sidePrizePoints("b") === 0);
  assert.equal(s.jacketBoard().find((r) => r.player.id === "a")?.total, 2);
  assert.equal(season(byName("kvelden er verdt 3")).jacketBoard().find((r) => r.player.id === "a")?.total, 3);
  s = season(byName("lik lengde deler"));
  assert.ok(s.sidePrizePoints("a") === 0.5 && s.sidePrizePoints("c") === 0.5);
  assert.equal(s.sidePrizeResults("a")[0].shared, true);
  assert.equal(season(byName("sju lagseire")).matchTotals("a").points, 7);
  assert.equal(season(byName("seier og delt gir 1,5")).matchTotals("a").points, 1.5);
  assert.ok(season(byName("sesongstart")).jacketBoard().every((r) => r.total === 0));
  s = season(byName("duellen og stablefordet rangerer motsatt"));
  assert.ok(s.stablefordTotal("b") > s.stablefordTotal("a"));
  assert.equal(s.jacketBoard()[0].player.id, "a");
  const b0 = season(byName("vekt 0 teller ikke")).jacketBoard().find((r) => r.player.id === "b")!;
  assert.ok(b0.duel === 0 && b0.holes === 0 && b0.side === 0 && b0.played === 0);
  assert.equal(season(byName("de to svakeste strykes")).stablefordTotal("a"), 130);
  s = season(byName("fravær strykes"));
  assert.equal(s.stablefordTotal("b"), s.stablefordTotal("a"));
  assert.equal(season(byName("det tredje fraværet svir")).stablefordTotal("c"), 30 + 28 + 26 + 24);
  s = season(byName("vekten før utvelgelsen"));
  assert.equal(s.countingRounds("a").counting[0].points, 30);
  assert.equal(s.stablefordTotal("a"), 104);
  const tropp = season(byName("to som venter")).stablefordBoard();
  assert.equal(tropp.length, 4);
  assert.ok(tropp.some((r) => r.player.name === "Strypet" && r.total === 0 && r.played === 0));
  assert.deepEqual(tropp.slice(0, 2).map((r) => r.player.name), ["Rostad", "Næsset"]);
  s = season(byName("to konkurranser samme kveld, siste ni går"));
  assert.equal(eveningCount(s.rounds), 1);
  assert.equal(s.matchTotals("thuen").matches, 2);
  assert.ok(s.roundNumber("2026-09-28") === 1 && s.roundNumber("2026-10-05") === 2);
  assert.ok(!s.isEveningFinished("2026-09-28"));
  assert.ok(season(byName("to konkurranser samme kveld, begge låst")).isEveningFinished("2026-09-28"));
  assert.equal(eveningCount(season(byName("runde uten dato")).rounds), 1);
});

test("navn skiller til slutt (norsk sortering)", () => {
  const tavle = season(byName("trekant, manuelt resultat og vekt")).jacketBoard();
  assert.deepEqual(tavle.slice(-2).map((r) => r.player.name), ["Zorro", "Øyvind"]);
});

test("andre regelsett som PWA-en med andre konstanter", () => {
  assert.equal(fil.annetRegelsett.length, 8);
  for (const a of fil.annetRegelsett) {
    const r = golfgutuRules();
    const k = a.konstanter;
    if (k.POENG_SEIER != null) r.table.matchPoints.win = k.POENG_SEIER;
    if (k.POENG_DELT != null) r.table.matchPoints.draw = k.POENG_DELT;
    if (k.POENG_TAP != null) r.table.matchPoints.loss = k.POENG_TAP;
    if (k.TELLENDE_MATCHER != null) r.table.counting = { unit: "match", best: k.TELLENDE_MATCHER };
    if (k.TELLENDE_RUNDER != null) r.table.stablefordCounting = { unit: "round", best: k.TELLENDE_RUNDER };
    if (k.TREKANT_POENG != null) r.table.trianglePoints = k.TREKANT_POENG;
    sjekk(sak(a.sak), r, a.sak.navn);
  }
});

test("beste 3 og seier 2 poeng", () => {
  const s = byName("fem knepne seire og to knusende tap");
  assert.deepEqual(new Season(s.spillere, s.runder).jacketBoard().map((r) => r.total), [5, 2]);
  const tre = golfgutuRules();
  tre.table.counting = { unit: "match", best: 3 };
  const s3 = new Season(s.spillere, s.runder, [], tre);
  assert.deepEqual(s3.matchTotals("a"), { points: 3, holes: 3, matches: 3 });
  assert.deepEqual(s3.matchTotals("b"), { points: 2, holes: 35, matches: 3 });
  assert.equal(s3.matchResults("a").dropped.length, 4);
  assert.equal(s3.jacketBoard().find((r) => r.player.id === "a")?.played, 7);
  const to = golfgutuRules();
  to.table.matchPoints = { win: 2, draw: 1, loss: 0 };
  assert.deepEqual(new Season(s.spillere, s.runder, [], to).jacketBoard().map((r) => r.total), [10, 4]);

  const lik = byName("lik lengde deler");
  const av = golfgutuRules();
  av.sidePrizes.longestDrive.enabled = false;
  av.sidePrizes.closestToPin.enabled = false;
  assert.equal(season(lik, av).sidePrizePoints("a"), 0);
  const dobbel = golfgutuRules();
  dobbel.sidePrizes.longestDrive.points = 2;
  dobbel.sidePrizes.closestToPin.points = 2;
  assert.equal(season(lik, dobbel).sidePrizePoints("a"), 1);
  const hel = golfgutuRules();
  hel.sidePrizes.splitTies = false;
  assert.ok(season(lik, hel).sidePrizePoints("a") === 1 && season(lik, hel).sidePrizePoints("c") === 1);
  for (const kind of new Set(season(lik).sidePrizeResults("a").map((r) => r.kind))) {
    const en = golfgutuRules();
    if (kind === "drive") en.sidePrizes.longestDrive.enabled = false;
    else en.sidePrizes.closestToPin.enabled = false;
    assert.ok(!season(lik, en).sidePrizeResults("a").some((r) => r.kind === kind));
  }
});

test("tiebreak fra regelsettet", () => {
  const s = byName("duellen og stablefordet rangerer motsatt");
  const r = golfgutuRules();
  r.table.matchPoints = { win: 0, draw: 0, loss: 0 };
  assert.deepEqual(new Season(s.spillere, s.runder, [], r).jacketBoard().map((x) => x.player.id), ["a", "b"]);
  r.table.tiebreaks = ["stableford", "holeDifference"];
  assert.deepEqual(new Season(s.spillere, s.runder, [], r).jacketBoard().map((x) => x.player.id), ["b", "a"]);
  r.table.tiebreaks = [];
  assert.deepEqual(new Season(s.spillere, s.runder, [], r).jacketBoard().map((x) => x.player.id), ["a", "b"]);
});

/** To runder samme kveld (d1), så d2 og d3. Manuelle resultater, ett hull ført på standardbanen. */
function toRunderSammeKveld() {
  const spillere = [makePlayer("a", "Anders"), makePlayer("b", "Bjørn")];
  const runde = (id: string, dato: string, resultat: MatchResult, a: number, b: number) => makeRound({
    id,
    holeScores: new Map([["a", new Map([[0, a]])], ["b", new Map([[0, b]])]]),
    matches: [makeMatch({ matchNo: 1, playerA: "a", playerB: "b", result: resultat })],
    date: dato,
  });
  const runder = [runde("r1", "2026-05-04", "a", 4, 5), runde("r2", "2026-05-04", "a", 4, 5), runde("r3", "2026-05-11", "b", 5, 3), runde("r4", "2026-05-18", "halved", 4, 4)];
  const claims: SideClaim[] = [{ id: null, kind: "drive", playerId: "b", roundId: "r1", meters: 250, holeIndex: null, ts: null }];
  return { spillere, runder, claims };
}

test("kvelds-telling med to runder på én kveld", () => {
  const s = toRunderSammeKveld();
  const sesong = (endre: (r: Ruleset) => void) => {
    const r = golfgutuRules();
    endre(r);
    return new Season(s.spillere, s.runder, s.claims, r);
  };
  const total = (se: Season, id: string) => se.jacketBoard().find((r) => r.player.id === id)?.total;
  const alle = sesong(() => {});
  assert.ok(total(alle, "a") === 2.5 && total(alle, "b") === 2.5);
  const kveldAlle = sesong((r) => { r.table.counting = { unit: "evening", best: null }; });
  assert.deepEqual(kveldAlle.jacketBoard(), alle.jacketBoard());
  const beste1 = sesong((r) => { r.table.counting = { unit: "evening", best: 1 }; });
  assert.equal(total(beste1, "a"), 2);
  assert.deepEqual(beste1.matchResults("a").counting.map((x) => x.roundID), ["r1", "r2"]);
  assert.equal(beste1.matchResults("a").dropped.length, 2);
  assert.equal(total(beste1, "b"), 1);
  assert.equal(beste1.tableSelection("b").sidePrizes.counting.length, 1);
  assert.deepEqual(beste1.matchResults("b").counting.map((x) => x.roundID), ["r1", "r2"]);
  assert.equal(beste1.jacketBoard().find((r) => r.player.id === "a")?.played, 4);
  const match1 = sesong((r) => { r.table.counting = { unit: "match", best: 1 }; });
  assert.equal(total(match1, "a"), 1);
  assert.equal(total(match1, "b"), 2);
  const beste2 = sesong((r) => { r.table.counting = { unit: "evening", best: 2 }; });
  assert.equal(total(beste2, "a"), 2.5);
  assert.equal(total(beste2, "b"), 2);
  assert.deepEqual(beste2.matchResults("b").dropped.map((x) => x.roundID), ["r4"]);
  assert.equal(total(sesong((r) => { r.table.counting = { unit: "round", best: 1 }; }), "a"), 1);
  assert.ok(alle.stablefordTotal("a") === 7 && alle.stablefordTotal("b") === 7);
  const runder2 = sesong((r) => { r.table.stablefordCounting = { unit: "round", best: 2 }; });
  assert.ok(runder2.stablefordTotal("a") === 4 && runder2.stablefordTotal("b") === 5);
  const kveld1 = sesong((r) => { r.table.stablefordCounting = { unit: "evening", best: 1 }; });
  assert.equal(kveld1.stablefordTotal("a"), 4);
  assert.deepEqual(kveld1.countingRounds("a").counting.map((x) => x.roundID), ["r1", "r2"]);
  assert.equal(kveld1.stablefordTotal("b"), 3);
  const kveld2 = sesong((r) => { r.table.stablefordCounting = { unit: "evening", best: 2 }; });
  assert.equal(kveld2.stablefordTotal("a"), 6);
  assert.equal(kveld2.stablefordTotal("b"), 5);
  assert.deepEqual(kveld2.countingRounds("b").dropped.map((x) => x.roundID), ["r4"]);
  assert.equal(sesong((r) => { r.table.stablefordCounting = { unit: "evening", best: null }; }).stablefordTotal("a"), 7);
});

test("alle runder teller i stablefordsummen", () => {
  const s = byName("de to svakeste strykes");
  const r = golfgutuRules();
  r.table.stablefordCounting.best = null;
  assert.equal(new Season(s.spillere, s.runder, [], r).stablefordTotal("a"), 168);
});

test("fmtPoeng og matchSum", () => {
  for (const [inn, ut] of fil.fmtPoeng) {
    // Number(null) = 0, Number('x') = NaN.
    const x = inn === null ? 0 : typeof inn === "number" ? inn : NaN;
    assert.equal(formatPoints(x), ut, String(inn));
  }
  for (const s of fil.matchSum) {
    const res = (s.inn as any[]).map((x, i) => ({ roundIndex: i, roundID: null, matchNo: null, points: x.poeng, holes: x.hull, isTriangle: false }));
    assert.deepEqual(matchSum(res), { points: s.ut.poeng, holes: s.ut.hull, matches: s.ut.matcher });
  }
});

test("trekningen bruker tabellen", () => {
  const s = byName("trekant, manuelt resultat og vekt");
  const standing = new Map<string, number>();
  for (const p of s.spillere) standing.set(p.id, s.raw.per[p.id].matchSum.poeng);
  assert.deepEqual(season(s).drawMatches(s.spillere, 0), drawMatches(s.spillere, 0, standing));
});
