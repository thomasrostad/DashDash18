// Steg 6 i web-admin: tabellen med delt plass, uten plass og playoff (mot appens fasit), de nye reglene i
// «Reglene» (rulesform.ts) og trekningen og lagene i rundeoppsettet (logic.ts).

import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { avoidingRepeats, decodeRuleset, encodeRuleset, formById, GOLFGUTU, makePlayer, pairKey, randomTeams, validateRuleset, type Ruleset } from "../../golfgutu-core/src/index.ts";
import { tableCsv } from "../src/standings/csv.ts";
import { seasonView } from "../src/standings/model.ts";
import {
  addPointsTable, aggregationOptions, applyTipsTemplate, hasMinEvenings, minEveningsHelp, minEveningsLabel, pointsTableList,
  removePointsTable, renamePointsTable, setPointsTableMultiplier, setTipsQuestion, TIPS_QUESTION_TITLES, tipsTemplateOf,
  toggleMinEvenings,
} from "../src/rulesform.ts";
import {
  drawByPlan, drawFooter, drawIndividual, drawPlan, meetingsFromRows, newDraft, randomTeamsFor, redrawMatches,
  STANDINGS_PLAN, suggestedTeams, swapTwo, teamProblem, type DrawPlan, type RosterMember,
} from "../src/rounds/logic.ts";

const read = (name: string) => JSON.parse(readFileSync(new URL(`../../golfgutu-core/test/fixtures/${name}`, import.meta.url), "utf8"));
const fx = read("tavla.json");
const want = read("tavla.forventet.json");
const seasonIndex = (name: string) => fx.sesonger.findIndex((s: { name: string }) => s.name === name);
const clone = (r: Ruleset) => structuredClone(r);
/** JSON-en slik den lagres, med `table` og `formats` som objekter. */
const encoded = (r: Ruleset) => encodeRuleset(r) as { table: Record<string, unknown>; formats: Record<string, unknown> };

// MARK: Tabeller

test("playoff: delt førsteplass med merke, og de uten nok kvelder nederst uten plass", () => {
  const i = seasonIndex("Playoff 2026");
  const v = seasonView(fx.tavlaData, fx.sesonger[i], fx.me);
  assert.deepEqual(v.rows.map((r) => r.placeText), ["1.", "1.", "1.", "4.", "5.", "5.", "5.", "5.", "–", "–"]);
  assert.ok(v.rows.slice(0, 3).every((r) => r.detail.startsWith("Playoff · ")));
  assert.ok(v.rows.slice(3).every((r) => !r.detail.includes("Playoff")));
  assert.ok(v.rows.slice(-2).every((r) => r.detail.endsWith(" · minst 2 kvelder for plass")));
  // Samme som appen (fasiten er laget av appens Swift-kode).
  assert.deepEqual(v.rows.map((r) => [r.placeText, r.detail]), want.tavla[i].rows.map((r: { placeText: string; detail: string }) => [r.placeText, r.detail]));
  assert.ok(tableCsv(v).includes("–;"));
});

test("snitt med spilledager: uten plass sier «spilledager»", () => {
  const i = seasonIndex("Snitt 2026");
  const v = seasonView(fx.tavlaData, fx.sesonger[i], fx.me);
  const unranked = v.rows.filter((r) => r.placeText === "–");
  assert.equal(unranked.length, 4);
  assert.ok(unranked.every((r) => r.detail.endsWith(" · minst 3 spilledager for plass")));
});

test("Golfgutu: ingen merker og ingen uten plass", () => {
  const v = seasonView(fx.tavlaData, fx.sesonger[0], fx.me);
  assert.ok(v.rows.every((r) => r.placeText !== "–" && !r.detail.includes("Playoff") && !r.detail.includes("for plass")));
});

// MARK: Reglene

test("minste antall kvelder er av til det slås på", () => {
  const r = clone(GOLFGUTU);
  assert.equal(hasMinEvenings(r), false);
  assert.equal(minEveningsLabel(r), "Minste antall kvelder");
  toggleMinEvenings(r, true);
  assert.equal(r.table.minEvenings, 3);
  assert.equal(minEveningsHelp(r), "De med færre enn 3 kvelder står under tabellen uten plass.");
  assert.equal(encoded(r).table.minEvenings, 3);
  r.table.minEvenings = 9;
  assert.ok(validateRuleset(r).some((x) => x.field === "table.minEvenings"));
  toggleMinEvenings(r, false);
  assert.equal("minEvenings" in encoded(r).table, false);
  r.dayTerm = "playingDay";
  assert.equal(minEveningsLabel(r), "Minste antall spilledager");
  assert.deepEqual(aggregationOptions(r).map((o) => o.title), ["Sum", "Snitt per spilledag"]);
});

test("poengtabeller som liste, lagret som navn → gange", () => {
  const r = clone(GOLFGUTU);
  assert.equal(addPointsTable(r), "Finale");
  assert.equal(addPointsTable(r), "Tabell 2");
  assert.equal(renamePointsTable(r, "Tabell 2", "  Semifinale "), true);
  assert.equal(renamePointsTable(r, "Semifinale", "Finale"), false);
  assert.equal(renamePointsTable(r, "Semifinale", " "), false);
  setPointsTableMultiplier(r, "Semifinale", 1.5);
  assert.deepEqual(pointsTableList(r), [{ name: "Finale", multiplier: 2 }, { name: "Semifinale", multiplier: 1.5 }]);
  removePointsTable(r, "Finale");
  assert.deepEqual(validateRuleset(r), []);
  assert.deepEqual(decodeRuleset(encodeRuleset(r)).table.pointsTables, { Semifinale: { multiplier: 1.5 } });
  setPointsTableMultiplier(r, "Semifinale", -1);
  assert.ok(validateRuleset(r).some((x) => x.field === "table.pointsTables.Semifinale"));
});

test("snitt, playoff og trekning lagres bare når de er valgt", () => {
  const r = clone(GOLFGUTU);
  const plain = encoded(r);
  assert.equal("aggregation" in plain.table, false);
  assert.equal("tieRule" in plain.table, false);
  assert.equal("drawMethod" in plain.formats, false);
  r.table.aggregation = "average";
  r.table.tieRule = "playoff";
  r.formats.drawMethod = "manual";
  const back = decodeRuleset(encodeRuleset(r));
  assert.equal(back.table.aggregation, "average");
  assert.equal(back.table.tieRule, "playoff");
  assert.equal(back.formats.drawMethod, "manual");
});

// MARK: Trekning og lag

const roster: RosterMember[] = ["a", "b", "c", "d"].map((x) => ({ id: `00000000-0000-0000-0000-00000000000${x}`, name: x.toUpperCase(), handicap: 0, seed: null }));
const ids = roster.map((m) => m.id);

test("etter tabellen er som før, manuelt gir ingen matcher", () => {
  assert.deepEqual(drawByPlan(roster, STANDINGS_PLAN, 1), drawIndividual(roster));
  const manual: DrawPlan = { method: "manual", previous: new Map() };
  const d = redrawMatches(newDraft({ roundID: "00000000-0000-0000-0000-0000000000e1", eventID: "00000000-0000-0000-0000-0000000000e2", roundNo: 1, teeTime: null, participants: ids, source: "signups", rules: GOLFGUTU }), roster, manual);
  assert.deepEqual(d.matches, []);
  assert.equal(drawFooter(manual, []), "Du setter opp matchene selv.");
  assert.equal(drawFooter(STANDINGS_PLAN, []), null);
});

test("møtene fra før: spilte runder, ikke kladder eller runden som settes opp", () => {
  const m = (round: string, a: string, b: string, c: string | null = null) =>
    ({ roundID: round, matchNo: 1, playerA: a, playerB: b, playerC: c, teamA: null, teamB: null, result: null });
  const rounds = [{ id: "r1", status: "locked" }, { id: "r2", status: "draft" }, { id: "r3", status: "active" }];
  const matches = [m("r1", ids[0], ids[1]), m("r1", ids[2], ids[3], "x"), m("r2", ids[0], ids[2]), m("r3", ids[0], ids[3])];
  const rules = clone(GOLFGUTU);
  rules.formats.drawMethod = "avoidRepeats";
  const plan = drawPlan(rules, rounds, matches, new Map(), "r3");
  assert.equal(plan.method, "avoidRepeats");
  assert.deepEqual([...plan.previous.entries()].sort(), [
    [pairKey(ids[0], ids[1]), 1], [pairKey(ids[2], ids[3]), 1], [pairKey(ids[2], "x"), 1], [pairKey(ids[3], "x"), 1],
  ].sort());
  // Lagmatch: motstanderne på de to lagene, ikke lagkameratene.
  const players = new Map([["r1", ids.map((id, i) => ({ roundID: "r1", memberID: id, clubID: null, handicapIndex: 0, seedGroup: null, playingHandicap: null, bayNo: 1, isMarker: false, teamNo: i < 2 ? 1 : 2 }))]]);
  const team = meetingsFromRows([{ roundID: "r1", matchNo: 1, playerA: null, playerB: null, playerC: null, teamA: 1, teamB: 2, result: null }], players);
  assert.equal(team.size, 4);
  assert.equal(team.has(pairKey(ids[0], ids[1])), false);
});

test("uten gjentakelser unngår gamle motstandere, med motorens trekning", () => {
  const plan: DrawPlan = { method: "avoidRepeats", previous: new Map([[pairKey(ids[0], ids[1]), 1], [pairKey(ids[2], ids[3]), 1]]) };
  for (const seed of [1, 2, 3, 42]) {
    const matches = drawByPlan(roster, plan, seed);
    const core = avoidingRepeats(roster.map((r) => makePlayer(r.id, r.name)), plan.previous, seed);
    assert.deepEqual(matches.map((x) => [x.playerA, x.playerB, x.playerC].filter((y) => y !== null)), core);
    assert.equal(drawFooter(plan, matches), "Trekkes tilfeldig uten gjentakelser. Ingen har møtt hverandre før.");
  }
});

test("tilfeldige lag går opp, og to spillere kan bytte", () => {
  const eight = Array.from({ length: 8 }, (_, i) => `00000000-0000-0000-0000-00000000010${i}`);
  const form = formById("fourball");
  const teams = randomTeamsFor(eight, form, 4, 7);
  assert.deepEqual(Object.keys(teams).sort(), [...eight].sort());
  assert.equal(teamProblem(teams, eight, form, 4), null);
  const order = randomTeams(eight, 1, 7);
  assert.deepEqual(teams, suggestedTeams([...eight].sort((a, b) => order.get(a)! - order.get(b)!), form, 4));
  const a = eight.find((id) => teams[id] === 1)!;
  const b = eight.find((id) => teams[id] === 2)!;
  const swapped = swapTwo(teams, a, b);
  assert.equal(swapped[a], 2);
  assert.equal(swapped[b], 1);
  assert.deepEqual(swapTwo(teams, a, a), teams);
});

// MARK: Tippekupongen

test("tippekupongen: mal, spørsmål av og på, og JSON-en appen leser", () => {
  const r = clone(GOLFGUTU);
  assert.equal(tipsTemplateOf(r), "classic");
  applyTipsTemplate(r, "birdieHunt");
  assert.deepEqual(r.tips.questions, ["winner", "birdie", "birdieCount", "mostBirdies", "over"]);
  assert.equal(tipsTemplateOf(r), "birdieHunt");
  setTipsQuestion(r, "backNine", true);
  assert.deepEqual(r.tips.questions, ["winner", "backNine", "birdie", "birdieCount", "mostBirdies", "over"], "kupongens rekkefølge");
  assert.equal(tipsTemplateOf(r), null);
  setTipsQuestion(r, "backNine", false);
  assert.equal(tipsTemplateOf(r), "birdieHunt", "tilbake til malen");
  r.tips.birdieCountLine = 9.5;
  const tips = (encodeRuleset(r) as { tips: Record<string, unknown> }).tips;
  assert.deepEqual(tips.questions, r.tips.questions);
  assert.equal(tips.birdieCountLine, 9.5);
  assert.equal(tips.winnerPointsLine, undefined, "standard skrives ikke");
  assert.deepEqual(decodeRuleset(JSON.parse(JSON.stringify(encodeRuleset(r)))).tips, r.tips);
  applyTipsTemplate(r, "full");
  assert.equal(r.tips.questions.length, 9);
  assert.ok(r.tips.questions.every((q) => TIPS_QUESTION_TITLES[q].endsWith("?")));
  for (const q of [...r.tips.questions]) setTipsQuestion(r, q, false);
  assert.deepEqual(validateRuleset(r).map((i) => i.field), ["tips.questions"]);
  assert.deepEqual((encodeRuleset(GOLFGUTU) as { tips: Record<string, unknown> }).tips.questions, undefined);
});
