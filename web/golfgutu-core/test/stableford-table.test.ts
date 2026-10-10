// StablefordTableTests.swift og FrozenHandicapTests.swift. Tall: Fixtures/sesong-stableford.json og
// Fixtures/frosset-handicap.json.

import assert from "node:assert/strict";
import { test } from "node:test";
import { effectiveHandicap } from "../src/handicap.ts";
import { copyRound, decodePlayer, decodeRound, decodeSideClaim } from "../src/models.ts";
import { decodeRuleset, GOLFGUTU } from "../src/ruleset.ts";
import { Season } from "../src/season.ts";
import { templateRules } from "../src/template.ts";
import { validateRuleset } from "../src/validation.ts";
import { fixture, map, obj, stablefordRounds } from "./helpers.ts";

const sf = fixture("sesong-stableford");
const sfPlayers = (sf.spillere as any[]).map((p) => decodePlayer(p));
const sfClaims = (sf.claims as any[]).map((c) => decodeSideClaim(c));

test("stableford-tabellen: fixturen", () => {
  const rounds = stablefordRounds(sf);
  for (const sak of sf.saker) {
    const rules = decodeRuleset(sak.regelsett);
    assert.equal(rules.table.pointsSource, "stableford", sak.navn);
    assert.deepEqual(validateRuleset(rules), [], sak.navn);
    const season = new Season(sfPlayers, rounds, sfClaims, rules);
    sf.runder.forEach((r: any, i: number) => assert.deepEqual(obj(season.roundPoints(i)), r.poeng));
    const board = season.jacketBoard();
    assert.deepEqual(board.map((r) => r.player.id), sak.tavle.map((t: any) => t.id), sak.navn);
    board.forEach((row, i) => {
      const want = sak.tavle[i];
      assert.equal(row.total, want.total, `${sak.navn} ${want.id} total`);
      assert.equal(row.roundPoints, want.runder, `${sak.navn} ${want.id} runder`);
      assert.equal(row.side, want.side);
      assert.equal(row.played, want.spilte);
      assert.equal(row.stableford, want.stableford);
      assert.ok(row.duel === 0 && row.matches === 0 && row.holes === 0);
    });
    for (const [pid, want] of Object.entries<any>(sak.per)) {
      const sel = season.tableSelection(pid);
      assert.ok(sel.matches.counting.length === 0 && sel.matches.dropped.length === 0);
      assert.deepEqual(sel.rounds.counting.map((r) => r.roundID ?? ""), want.tellende, `${sak.navn} ${pid}`);
      assert.deepEqual(sel.rounds.dropped.map((r) => r.roundID ?? ""), want["strøket"], `${sak.navn} ${pid}`);
      const key = (s: { roundID: string | null; kind: string }) => `${s.roundID ?? ""}:${s.kind}`;
      assert.deepEqual(sel.sidePrizes.counting.map(key), want.tellendeSide);
      assert.deepEqual(sel.sidePrizes.dropped.map(key), want["strøketSide"]);
    }
  }
});

test("stableford-tabellen: Golfgutu teller matcher som før", () => {
  const season = new Season(sfPlayers, stablefordRounds(sf), sfClaims);
  const bjorn = season.tableSelection("b");
  assert.equal(bjorn.matches.counting.length, 1);
  assert.ok(bjorn.rounds.counting.length === 0 && bjorn.rounds.dropped.length === 0);
  const row = season.jacketBoard().find((r) => r.player.id === "b")!;
  assert.equal(row.roundPoints, 0);
  assert.equal(row.duel, 1);
});

test("stableford-tabellen: match som enhet regnes som runde", () => {
  const rules = templateRules("stablefordSeries");
  rules.table.counting = { unit: "match", best: 2 };
  assert.deepEqual(validateRuleset(rules).map((i) => i.field), ["table.counting.unit"]);
  const perRound = templateRules("stablefordSeries");
  perRound.table.counting = { unit: "round", best: 2 };
  const a = new Season(sfPlayers, stablefordRounds(sf), sfClaims, rules);
  const b = new Season(sfPlayers, stablefordRounds(sf), sfClaims, perRound);
  assert.deepEqual(a.jacketBoard(), b.jacketBoard());
  assert.equal(a.jacketBoard().find((r) => r.player.id === "a")?.total, 80);
});

test("stableford-serien", () => {
  const board = new Season(sfPlayers, stablefordRounds(sf), sfClaims, templateRules("stablefordSeries")).jacketBoard();
  assert.deepEqual(board.map((r) => r.player.id), ["b", "a", "c", "d"]);
  assert.deepEqual(board.map((r) => r.total), [158, 155, 132, 0]);
  assert.deepEqual(board.map((r) => r.side), [0, 0, 0, 0]);
  assert.deepEqual(board.map((r) => r.stableford), [158, 155, 132, 0]);
});

// MARK: Frosset handicap (FrozenHandicapTests.swift)

const fh = fixture("frosset-handicap");
const fhPlayers = (fh.spillere as any[]).map((p) => decodePlayer(p));
const fhRounds = (fh.runder as any[]).map((r) => decodeRound(r));
const fhFrozen = new Map(Object.entries(fh.spillehandicap as Record<string, Record<string, number>>).map(([k, v]) => [k, map(v)]));

function check(season: Season, f: any) {
  assert.deepEqual(season.rounds.map((_, i) => obj(season.roundPoints(i))), f.rundePoeng);
  for (const [pid, expected] of Object.entries<any[]>(f.matcher)) {
    const got = season.matchResults(pid).counting.map((r) => JSON.stringify({ roundId: r.roundID ?? "", poeng: r.points, hull: r.holes }));
    assert.deepEqual(new Set(got), new Set(expected.map((e) => JSON.stringify({ roundId: e.roundId, poeng: e.poeng, hull: e.hull }))), `matcher for ${pid}`);
  }
  const board = season.jacketBoard();
  assert.deepEqual(board.map((r) => r.player.id), f.jakketavle.map((j: any) => j.id));
  board.forEach((row, i) => {
    const e = f.jakketavle[i];
    assert.deepEqual([row.total, row.duel, row.side, row.matches, row.holes, row.played, row.stableford], [e.total, e.duell, e.side, e.matcher, e.hull, e.spilte, e.stableford], e.id);
  });
}

test("frosset handicap: uten regnes fra troppen", () => {
  check(new Season(fhPlayers, fhRounds), fh.troppen);
});

test("frosset handicap gjelder per runde", () => {
  check(new Season(fhPlayers, fhRounds, [], GOLFGUTU, fhFrozen), fh.frosset);
});

test("frosset handicap på runden gir samme svar", () => {
  const rounds = fhRounds.map((r) => {
    const c = copyRound(r);
    c.playingHandicaps = new Map(fhFrozen.get(r.id ?? "") ?? []);
    return c;
  });
  check(new Season(fhPlayers, rounds), fh.frosset);
});

test("overstyringen vinner over runden", () => {
  const r1 = copyRound(fhRounds[0]);
  r1.playingHandicaps = map({ b: 9 });
  const season = new Season(fhPlayers, [r1, fhRounds[1]], [], GOLFGUTU, fhFrozen);
  assert.deepEqual(obj(season.roundPoints(0)), fh.frosset.rundePoeng[0]);
});

test("spillere uten frosset tall regnes fra troppen", () => {
  const season = new Season(fhPlayers, fhRounds, [], GOLFGUTU, new Map([["r1", map({ b: 18 })]]));
  assert.deepEqual(obj(season.roundPoints(0)), fh.frosset.rundePoeng[0]);
  assert.deepEqual(obj(season.roundPoints(1)), fh.troppen.rundePoeng[1]);
});

test("simulatoren gir fortsatt null", () => {
  const r = copyRound(fhRounds[0]);
  r.hcpExtern = true;
  r.playingHandicaps = map({ b: 18 });
  assert.equal(effectiveHandicap(fhPlayers[1], r, fhPlayers), 0);
});

test("frosset tall er effektivt handicap", () => {
  const r = copyRound(fhRounds[0]);
  r.playingHandicaps = map({ b: 18 });
  assert.equal(effectiveHandicap(fhPlayers[1], r, fhPlayers), 18);
  assert.equal(effectiveHandicap(fhPlayers[0], r, fhPlayers), 0);
});

test("runden dekodes uten feltet", () => {
  assert.equal(decodeRound({ id: "x" }).playingHandicaps.size, 0);
});
