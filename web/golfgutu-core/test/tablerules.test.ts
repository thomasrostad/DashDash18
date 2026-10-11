// TableRulesTests.swift: tabellregler og playoff (steg 6). Tall: Fixtures/tabellregler.json (regnet for
// hånd) og Fixtures/trekning.json (trekningen, skrevet av Swift-motoren).

import assert from "node:assert/strict";
import { test } from "node:test";
import { addMeetings, avoidingRepeats, drawIssueCode, drawIssueMessage, meetings, randomTeams, repeats, swapTeams, validateDraw } from "../src/draw.ts";
import { decodeMatch, decodePlayer, decodeRound, makeRound, type Player, type Round } from "../src/models.ts";
import { decidePlayoff, hiddenHoleIndices, hidingLastHoles, suggestedPlayoffHoles } from "../src/playoff.ts";
import { decodeRuleset, encodeRuleset, GOLFGUTU, golfgutuRules, rulesetEquals } from "../src/ruleset.ts";
import { roundPoints } from "../src/scoring.ts";
import { Season } from "../src/season.ts";
import { changedFields } from "../src/template.ts";
import { drawMatches } from "../src/triangle.ts";
import { validateRuleset } from "../src/validation.ts";
import { fixture, obj, scoresFor, TEST_COURSE } from "./helpers.ts";

const fil = fixture("tabellregler");
const spillere: Player[] = (fil.spillere as any[]).map((p) => decodePlayer(p));

function runder(): Round[] {
  return (fil.runder as any[]).map((r) => makeRound({
    id: r.id, gameType: "stableford", holeCount: 18, holeStart: 0, course: TEST_COURSE, hcpAllowance: 1,
    holeScores: new Map(Object.entries(r.poeng as Record<string, number>).map(([k, v]) => [k, scoresFor(v)])),
    weight: r.vekt, date: r.dato, locked: true, counts: r.teller ?? true, pointsTable: r.poengtabell ?? null,
  }));
}

// MARK: Tabellen

test("tabellreglene", () => {
  const rounds = runder();
  for (const sak of fil.saker as any[]) {
    const rules = decodeRuleset(sak.regelsett);
    assert.deepEqual(validateRuleset(rules), [], sak.navn);
    const season = new Season(spillere, rounds, [], rules);
    const table = season.standings(sak.playoffVinner ?? null);
    assert.deepEqual(table.map((s) => s.row.player.id), sak.tavle.map((r: any) => r.id), `${sak.navn}: rekkefølge`);
    table.forEach((got, i) => {
      const want = sak.tavle[i];
      assert.equal(got.place, want.plass, `${sak.navn} ${want.id}: plass`);
      assert.equal(got.row.total, want.total, `${sak.navn} ${want.id}: total`);
      assert.equal(got.row.evenings, want.kvelder, `${sak.navn} ${want.id}: kvelder`);
      assert.equal(got.row.qualified, want.plass !== null, `${sak.navn} ${want.id}: kvalifisert`);
      assert.equal(got.playoffPending ? "venter" : got.wonPlayoff ? "vant" : null, want.playoff, `${sak.navn} ${want.id}: playoff`);
    });
    if (sak.playoffVinner === undefined) {
      assert.deepEqual(season.jacketBoard().map((r) => r.player.id), sak.tavle.map((r: any) => r.id), `${sak.navn}: jakketavla`);
    }
  }
});

test("kveld som ikke teller er vekt 0", () => {
  const rules = decodeRuleset(fil.saker[0].regelsett);
  const notCounting = runder();
  const weightZero = notCounting.map((r) => (r.counts ? r : { ...r, counts: true, weight: 0 }));
  assert.deepEqual(new Season(spillere, notCounting, [], rules).jacketBoard(), new Season(spillere, weightZero, [], rules).jacketBoard());
  assert.deepEqual(new Season(spillere, notCounting).stablefordBoard(), new Season(spillere, weightZero).stablefordBoard());
});

test("poengtabell og vekt", () => {
  const rules = decodeRuleset(fil.saker[1].regelsett);
  rules.table.pointsTables.halv = { multiplier: 0.5 };
  const rounds = runder();
  rounds[3].weight = 2;
  rounds[0].pointsTable = "halv";
  const season = new Season(spillere, rounds, [], rules);
  assert.equal(season.effectiveWeight(rounds[3]), 4);
  assert.equal(season.effectiveWeight(rounds[0]), 0.5);
  assert.equal(season.jacketBoard().find((r) => r.player.id === "A")!.total, 215);
  rounds[1].pointsTable = "finnes ikke";
  rounds[4].pointsTable = "finale";
  const s2 = new Season(spillere, rounds, [], rules);
  assert.equal(s2.effectiveWeight(rounds[1]), 1);
  assert.equal(s2.effectiveWeight(rounds[4]), 0);
  rounds[1].pointsTable = "constructor";
  assert.equal(new Season(spillere, rounds, [], rules).effectiveWeight(rounds[1]), 1);
});

test("snitt med beste N", () => {
  const rules = decodeRuleset(fil.saker[0].regelsett);
  rules.table.aggregation = "average";
  rules.table.counting = { unit: "evening", best: 2 };
  const rows = new Map(new Season(spillere, runder(), [], rules).jacketBoard().map((r) => [r.player.id, r]));
  assert.equal(rows.get("A")!.total, 37.5);
  assert.equal(rows.get("B")!.total, 35);
  assert.equal(rows.get("D")!.total, 22.5);
  assert.equal(rows.get("A")!.evenings, 4);
});

test("Golfgutu har standardverdiene", () => {
  assert.equal(GOLFGUTU.table.minEvenings, null);
  assert.equal(GOLFGUTU.table.aggregation, "sum");
  assert.deepEqual(GOLFGUTU.table.pointsTables, {});
  assert.equal(GOLFGUTU.table.tieRule, "tiebreaks");
  assert.equal(GOLFGUTU.formats.drawMethod, "standings");
  const r = makeRound();
  assert.equal(r.counts, true);
  assert.equal(r.pointsTable, null);
  assert.equal(r.hideLastHoles, 0);
});

// MARK: JSON

test("JSON fram og tilbake", () => {
  const rules = golfgutuRules();
  rules.table.minEvenings = 3;
  rules.table.aggregation = "average";
  rules.table.pointsTables = { finale: { multiplier: 2 }, trening: { multiplier: 0 } };
  rules.table.tieRule = "playoff";
  rules.formats.drawMethod = "avoidRepeats";
  const json = encodeRuleset(rules) as any;
  assert.ok(rulesetEquals(decodeRuleset(JSON.parse(JSON.stringify(json))), rules));
  assert.equal(json.table.minEvenings, 3);
  assert.equal(json.table.aggregation, "average");
  assert.equal(json.table.tieRule, "playoff");
  assert.deepEqual(json.table.pointsTables.finale, { multiplier: 2 });
  assert.equal(json.formats.drawMethod, "avoidRepeats");
  assert.deepEqual(new Set(changedFields(rules, golfgutuRules())), new Set([
    "formats.drawMethod", "table.aggregation", "table.minEvenings", "table.pointsTables", "table.tieRule",
  ]));
});

test("standardverdiene skrives ikke", () => {
  const json = encodeRuleset(golfgutuRules()) as any;
  for (const k of ["minEvenings", "aggregation", "pointsTables", "tieRule"]) assert.equal(k in json.table, false, k);
  assert.equal("drawMethod" in json.formats, false);
});

test("rundens nye felt", () => {
  const r = decodeRound({ id: "r", counts: false, pointsTable: "finale", hideLastHoles: 3 });
  assert.equal(r.counts, false);
  assert.equal(r.pointsTable, "finale");
  assert.equal(r.hideLastHoles, 3);
  const old = decodeRound({ id: "r" });
  assert.ok(old.counts && old.pointsTable === null && old.hideLastHoles === 0);
});

test("gyldighetssjekk", () => {
  const rules = golfgutuRules();
  rules.table.minEvenings = 8;
  rules.table.pointsTables = { finale: { multiplier: -1 }, "": { multiplier: 1 } };
  const fields = new Set(validateRuleset(rules).map((i) => i.field));
  assert.ok(fields.has("table.minEvenings"));
  assert.ok(fields.has("table.pointsTables.finale"));
  assert.ok(fields.has("table.pointsTables"));
  rules.table.minEvenings = -1;
  assert.ok(validateRuleset(rules).some((i) => i.field === "table.minEvenings"));
  rules.table.minEvenings = 0;
  rules.table.pointsTables = {};
  assert.deepEqual(validateRuleset(rules), []);
});

// MARK: Playoff

test("playoff", () => {
  const roster: Player[] = (fil.playoff.spillere as any[]).map((p) => decodePlayer(p));
  for (const sak of fil.playoff.saker as any[]) {
    const round = makeRound({ id: "playoff", gameType: "stableford", holeCount: 18, holeStart: 0, course: TEST_COURSE, hcpAllowance: sak.andel });
    const d = decidePlayoff(sak.spillere, sak.hull, new Map(Object.entries(sak.slag as Record<string, number[]>)), round, roster);
    const f = sak.forventet;
    if (f.vinner !== undefined) assert.deepEqual(d, { kind: "won", winner: f.vinner, position: f.avgjort }, sak.navn);
    else assert.deepEqual(d, { kind: "pending", remaining: f.igjen, next: f.neste }, sak.navn);
  }
});

test("playoff: forslag til hull", () => {
  assert.deepEqual(suggestedPlayoffHoles(makeRound({ holeCount: 18 })), [17, 0, 17]);
  assert.deepEqual(suggestedPlayoffHoles(makeRound({ holeCount: 9 })), [8, 0, 8]);
});

test("playoff: vinner utenfor gruppa endrer ingenting", () => {
  const season = new Season(spillere, runder(), [], decodeRuleset(fil.saker[2].regelsett));
  const table = season.standings("C");
  assert.ok(table.slice(0, 2).every((s) => s.place === 1 && s.playoffPending));
});

// MARK: Skjul de siste hullene

test("skjul de siste hullene", () => {
  const players: Player[] = [decodePlayer({ id: "A", name: "Anne" }), decodePlayer({ id: "B", name: "Bjørn" })];
  for (const sak of fil.skjul.saker as any[]) {
    const round = makeRound({
      id: "r", gameType: "stableford", holeCount: sak.holeCount, holeStart: sak.holeStart, course: TEST_COURSE, hcpAllowance: 1,
      holeScores: new Map([["A", scoresFor(36)], ["B", scoresFor(36)]]), locked: sak.locked, hideLastHoles: sak.hideLastHoles,
    });
    assert.deepEqual(hiddenHoleIndices(round), sak.skjulte, sak.navn);
    const view = hidingLastHoles(round, new Set(sak.viser));
    assert.deepEqual(obj(roundPoints(view, players)), sak.poeng, sak.navn);
  }
});

// MARK: Trekning

test("manuell trekning", () => {
  for (const sak of fil.manuell.saker as any[]) {
    assert.deepEqual(validateDraw(sak.grupper, sak.deltakere).map(drawIssueCode), sak.feil, sak.navn);
  }
  assert.ok(drawIssueMessage({ kind: "duplicate", id: "A" }).includes("A"));
});

test("tidligere møter", () => {
  const m = fil["møter"];
  const rounds = (m.runder as any[]).map((r) => makeRound({ id: r.id, matches: (r.matches as any[]).map((x) => decodeMatch(x)) }));
  const got = meetings(rounds);
  assert.deepEqual(obj(got), m.forventet);
  assert.equal(repeats(m.gjentakelser.grupper, got), m.gjentakelser.antall);
});

test("uten gjentakelser gir færre (samme trekning som Swift)", () => {
  const t = fixture("trekning");
  const players: Player[] = (t.spillere as any[]).map((p) => decodePlayer(p));
  const prevTable = new Map<string, number>();
  const prevAvoid = new Map<string, number>();
  let repTable = 0;
  let repAvoid = 0;
  const table: string[][][] = [];
  const avoid: string[][][] = [];
  for (let k = 0; k < t.omganger; k++) {
    const x = drawMatches(players, k, new Map());
    const y = avoidingRepeats(players, prevAvoid, k + 1);
    repTable += repeats(x, prevTable);
    repAvoid += repeats(y, prevAvoid);
    addMeetings(x, prevTable);
    addMeetings(y, prevAvoid);
    table.push(x);
    avoid.push(y);
    assert.deepEqual(y.flat().sort(), players.map((p) => p.id).sort());
  }
  assert.ok(repAvoid < repTable);
  assert.deepEqual(table, t.tabell);
  assert.deepEqual(avoid, t.utenGjentakelser);
  assert.equal(repTable, t.gjentakelserTabell);
  assert.equal(repAvoid, t.gjentakelserUten);

  const oddPlayers: Player[] = (t.oddetall.spillere as any[]).map((p) => decodePlayer(p));
  const odd = avoidingRepeats(oddPlayers, new Map(), t.oddetall["frø"]);
  assert.deepEqual(odd, t.oddetall.grupper);
  assert.deepEqual(validateDraw(odd, oddPlayers.map((p) => p.id)), []);
  assert.deepEqual(obj(randomTeams(t.lag.spillere, t.lag["størrelse"], t.lag["frø"])), t.lag.lag);
});

test("gjentakbar med frø", () => {
  const players = [1, 2, 3, 4, 5, 6].map((i) => decodePlayer({ id: `p${i}`, name: `Spiller ${i}` }));
  const prev = new Map([["p1|p2", 1], ["p3|p4", 2]]);
  assert.deepEqual(avoidingRepeats(players, prev, 7), avoidingRepeats(players, prev, 7));
  assert.equal(repeats(avoidingRepeats(players, prev, 7), prev), 0);
  assert.deepEqual(avoidingRepeats(players.slice(0, 1), new Map(), 1), []);
});

test("sesongens trekning", () => {
  const m = fil["møter"];
  const rounds = (m.runder as any[]).map((r) => makeRound({ id: r.id, matches: (r.matches as any[]).map((x) => decodeMatch(x)) }));
  const players = ["A", "B", "C", "D"].map((id) => decodePlayer({ id, name: id }));
  const rules = golfgutuRules();
  const standings = new Season(players, rounds, [], rules);
  assert.deepEqual(standings.draw(players, 0, 1), standings.drawMatches(players, 0));
  rules.formats.drawMethod = "avoidRepeats";
  const groups = new Season(players, rounds, [], rules).draw(players, 0, 1)!;
  assert.equal(repeats(groups, meetings(rounds)), 0);
  rules.formats.drawMethod = "manual";
  assert.equal(new Season(players, rounds, [], rules).draw(players, 0, 1), null);
});

test("bytt lag", () => {
  const teams = new Map([["A", 1], ["B", 1], ["C", 2], ["D", 2]]);
  assert.deepEqual(obj(swapTeams(teams, "A", "C")), { A: 2, B: 1, C: 1, D: 2 });
  assert.deepEqual(obj(swapTeams(teams, "A", "B")), obj(teams));
  assert.deepEqual(obj(swapTeams(teams, "A", "X")), obj(teams));
  const random = randomTeams(["A", "B", "C", "D", "E"], 2, 3);
  assert.deepEqual([...random.keys()].sort(), ["A", "B", "C", "D", "E"]);
  const sizes = new Map<number, number>();
  for (const t of random.values()) sizes.set(t, (sizes.get(t) ?? 0) + 1);
  assert.deepEqual([...sizes.values()].sort(), [1, 2, 2]);
});
