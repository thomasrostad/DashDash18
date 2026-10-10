// CompetitionsTests.swift: liga, morroturnering og cup. Fasit: Fixtures/konkurranser.json.

import assert from "node:assert/strict";
import { test } from "node:test";
import {
  bracketSize,
  cupBracket,
  cupDecide,
  cupDraw,
  cupOpponent,
  cupSeeded,
  isEliminated,
  leaguePlacings,
  leagueTable,
  readyMatches,
  seedPositions,
  SplitMix64,
  type CupEntrant,
  type LeagueRound,
} from "../src/competitions.ts";
import { makePlayer, makeRound, type Round } from "../src/models.ts";
import { competitionRulesOf, decodeCupRules, decodeRuleset, GOLFGUTU, golfgutuRules, LEAGUE_TEMPLATE, standardCompetitionRules, type CupTie, type LeagueRules } from "../src/ruleset.ts";
import { fixture, map } from "./helpers.ts";

const fil = fixture("konkurranser");

function rulesFor(l: any): LeagueRules {
  // Overstyringene leses som i regelsettet: feltene som mangler, får malen.
  const ruleset = decodeRuleset({ competition: { [l.malen]: l.regler }, version: 2 });
  return l.malen === "fun" ? competitionRulesOf(ruleset).fun : competitionRulesOf(ruleset).league;
}

const leagueRound = (r: any): LeagueRound => ({ id: r.id, stableford: map(r.stableford as Record<string, number>) });

for (const l of fil.liga) {
  test(`ligatabell: ${l.navn}`, () => {
    const rows = leagueTable(l.pameldte, (l.runder as any[]).map(leagueRound), rulesFor(l));
    assert.deepEqual(rows.map((r) => r.playerID), l.forventet.map((f: any) => f.id));
    rows.forEach((row, i) => {
      const f = l.forventet[i];
      assert.equal(row.place, f.plass, `${f.id} plass`);
      assert.ok(Math.abs(row.total - f.total) < 1e-9, `${f.id} total ${row.total}`);
      assert.ok(row.played === f.spilt && row.wins === f.seire && row.stableford === f.stableford, f.id);
      assert.equal(row.bestRound, f.beste ?? null, `${f.id} beste`);
      assert.deepEqual(row.results.map((r) => [r.roundID, r.place, r.points, r.counted]), f.runder, `${f.id} runder`);
    });
  });
}

test("ikke påmeldt tar ingen plass", () => {
  const p = leaguePlacings({ id: "r", stableford: map({ x: 45, a: 20, b: 10 }) }, new Set(["a", "b"]), LEAGUE_TEMPLATE);
  assert.deepEqual(p.get("a"), { place: 1, points: 11 });
  assert.deepEqual(p.get("b"), { place: 2, points: 9 });
  assert.equal(p.get("x"), undefined);
});

test("beste 1 velger den tidligste ved likt", () => {
  const rules = { ...standardCompetitionRules().league, bestRounds: 1 };
  const rows = leagueTable(["a", "b"], [
    { id: "r1", stableford: map({ a: 30, b: 20 }) },
    { id: "r2", stableford: map({ a: 25, b: 20 }) },
  ], rules);
  assert.deepEqual(rows[0].results.map((r) => r.counted), [true, false]);
  assert.equal(rows[0].stableford, 30);
});

test("seedplasser og trestørrelse", () => {
  for (const [size, want] of Object.entries(fil.seedplasser)) assert.deepEqual(seedPositions(Number(size)), want);
  assert.equal(bracketSize(2), 2);
  assert.equal(bracketSize(3), 4);
  assert.equal(bracketSize(5), 8);
  assert.equal(bracketSize(8), 8);
  assert.equal(bracketSize(9), 16);
});

for (const s of fil.seeding) {
  test(`seeding: ${s.navn}`, () => {
    const deltakere: CupEntrant[] = (s.deltakere as any[]).map((d) => ({ id: d.id, name: d.name ?? "", handicap: d.handicap ?? null, rank: d.rank ?? null }));
    const rules = decodeCupRules(s.regler);
    assert.deepEqual(cupSeeded(deltakere, rules, s.frø), s.forventet);
    assert.deepEqual(cupSeeded([...deltakere].reverse(), rules, s.frø), s.forventet, "baklengs");
  });
}

test("SplitMix64 referanse", () => {
  assert.equal(new SplitMix64(0).next(), 0xe220a8397b1dcdafn);
});

for (const t of fil.tre) {
  test(`tre: ${t.navn}`, () => {
    const draw = cupDraw(t.seedet);
    assert.deepEqual(draw, t.forsteRunde, "første runde");
    const b = cupBracket(draw, (t.resultater as any[]).map((r) => ({ round: r.round, slot: r.slot, winner: r.winner, walkover: r.walkover ?? false })));
    assert.deepEqual(b.rounds.map((r) => r.map((m) => [m.a, m.b, m.winner])), t.forventet.runder, "treet");
    assert.equal(b.champion, t.forventet.mester ?? null, "mester");
    assert.deepEqual(readyMatches(b).map((m) => [m.round, m.slot]), t.forventet.klare, "klare");
    for (const [spiller, motstander] of Object.entries(t.forventet.motstander)) assert.equal(cupOpponent(b, spiller), motstander ?? null, `motstander for ${spiller}`);
    assert.deepEqual(new Set((t.seedet as string[]).filter((id) => isEliminated(b, id))), new Set(t.forventet.ute), "ute");
  });
}

test("for få deltakere", () => {
  assert.deepEqual(cupDraw(["a"]), []);
  assert.deepEqual(cupBracket([], []).rounds, []);
});

test("ugyldig trekning krasjer ikke", () => {
  const b = cupBracket([{ slot: 0, a: "a", b: "b" }, { slot: 0, a: "c", b: "d" }, { slot: 2, a: "e", b: null }], [{ round: 1, slot: 0, winner: "c", walkover: false }]);
  assert.deepEqual(b.rounds.map((r) => r.length), [4, 2, 1]);
  assert.deepEqual(b.rounds[0].map((m) => m.a), ["c", null, "e", null]);
  assert.ok(b.rounds[1][0].a === "c" && b.rounds[1][1].a === "e" && b.rounds[1][1].b === null);
});

// MARK: Kampen i en runde

function round(a: number[], b: number[], hcp: [number, number] = [0, 0]): Round {
  return makeRound({
    holeCount: 9,
    holeScores: new Map([["a", new Map(a.map((x, i) => [i, x]))], ["b", new Map(b.map((x, i) => [i, x]))]]),
    playingHandicaps: new Map([["a", hcp[0]], ["b", hcp[1]]]),
  });
}

function rulesWithTie(tie: CupTie) {
  const r = golfgutuRules();
  r.competition = { ...standardCompetitionRules(), cup: { seeding: "random", tie } };
  return r;
}

const roster = [makePlayer("a"), makePlayer("b")];

test("avgjort før 18", () => {
  const r = round([4, 4, 4, 4, 4, 4, 4], [5, 5, 5, 4, 4, 4, 4]);
  assert.deepEqual(cupDecide("a", "b", r, roster, rulesWithTie("suddenDeath")), { kind: "won", winner: "a", up: 3, remaining: 2, tie: null });
});

test("pågår og ikke startet", () => {
  const r = round([4, 4, 4], [5, 4, 4]);
  assert.deepEqual(cupDecide("a", "b", r, roster, GOLFGUTU), { kind: "inProgress", up: 1, played: 3, remaining: 6 });
  assert.deepEqual(cupDecide("b", "a", r, roster, GOLFGUTU), { kind: "inProgress", up: -1, played: 3, remaining: 6 });
  assert.deepEqual(cupDecide("a", "b", round([], []), roster, GOLFGUTU), { kind: "notStarted" });
});

test("likt etter siste hull", () => {
  const r = round([4, 4, 4, 4, 4, 4, 4, 5, 4], [5, 4, 4, 4, 4, 4, 4, 4, 4]);
  assert.deepEqual(cupDecide("a", "b", r, roster, rulesWithTie("suddenDeath")), { kind: "tied" });
  assert.deepEqual(cupDecide("a", "b", r, roster, rulesWithTie("countback")), { kind: "won", winner: "b", up: 0, remaining: 0, tie: "countback" });
  assert.deepEqual(cupDecide("a", "b", r, roster, rulesWithTie("higherSeed"), map({ a: 3, b: 2 })), { kind: "won", winner: "b", up: 0, remaining: 0, tie: "higherSeed" });
  assert.deepEqual(cupDecide("a", "b", r, roster, rulesWithTie("higherSeed")), { kind: "tied" });
  assert.deepEqual(cupDecide("a", "b", r, roster, rulesWithTie("lowerHandicap")), { kind: "tied" });
});

test("lavest handicap ved likt", () => {
  const r = round([4, 4, 4, 4, 4, 4, 4, 4, 4], [5, 5, 4, 4, 4, 4, 4, 4, 4], [10, 12]);
  assert.deepEqual(cupDecide("a", "b", r, roster, rulesWithTie("lowerHandicap")), { kind: "won", winner: "a", up: 0, remaining: 0, tie: "lowerHandicap" });
  assert.deepEqual(cupDecide("a", "b", r, roster, rulesWithTie("countback")), { kind: "tied" });
});
