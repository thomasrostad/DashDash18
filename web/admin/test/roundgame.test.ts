// Avkorting, «Avslutt kvelden», rundetabellen og retting. Sakene og tallene er de samme som i appens
// DashDash18Tests/AvslutningTests.swift (fra PWA-ens avkorting-test.js og rundene-test.js), og
// startlista fra TurneringKjerneTests.swift.
import { test } from "node:test";
import assert from "node:assert/strict";
import { makeSnapshot, type RoundRow } from "../../golfgutu-core/src/index.ts";
import {
  closeCheck, closePrompt, closeSummary, correctionButtonTitle, correctionChanged, correctionCurrentText, correctionDoneText,
  correctionNotice, correctionOutcome, correctionParams, cutHint, cutLineText, cutOptionTitle, cutPatch, cutPatchMatches,
  cutPreview, cutRuleHelp, cutSummary, defaultCutChoice, newCorrection, playersMissingHoles, roundTable, RoundGame, stepCorrection,
  STROKE_MAX, STROKE_MIN,
} from "../src/rounds/game.ts";
import { fillTimes, shotgun, startGroups, startListIssues, startListParams } from "../src/rounds/startlist.ts";

const id = (n: number) => `00000000-0000-0000-0000-${String(n).padStart(12, "0")}`;
const roundID = id(801), courseID = id(802);
const PAR = [4, 5, 3, 4, 4, 3, 5, 4, 4, 4, 3, 5, 4, 4, 3, 4, 5, 4];

function row(p: Partial<RoundRow> = {}): RoundRow {
  return {
    id: roundID, clubID: id(800), eventID: id(803), courseID, roundNo: 1, name: null, status: "active", holeCount: 18,
    firstHole: 1, teeTime: null, format: "stableford", handicapAllowance: 1, externalHandicap: false, weight: 1,
    ldEnabled: true, ldHoleIndex: null, kpEnabled: true, kpHoleIndex: null, cutRule: null, cutAfter: null, venue: null,
    teeID: null, teeName: null, courseRating: null, slopeRating: null, teePar: null, ...p,
  };
}

function game(players: [number, string, number | null][], scores: Record<number, Record<number, number>>, round = row()): RoundGame {
  return new RoundGame(makeSnapshot(round, {
    players: players.map(([n, , hcp]) => ({ roundID, memberID: id(n), clubID: id(800), handicapIndex: hcp, seedGroup: null, playingHandicap: null, bayNo: null, isMarker: false, teamNo: null })),
    names: new Map(players.map(([n, name]) => [id(n), name])),
    course: { id: courseID, clubID: id(800), name: "Testbanen", externalName: null, courseRating: 72, slopeRating: 113, inUse: true },
    courseHoles: PAR.map((par, i) => ({ courseID, holeNumber: i + 1, par, strokeIndex: i + 1, lengthM: null })),
    scores: Object.entries(scores).flatMap(([m, holes]) => Object.entries(holes).map(([hole, strokes]) => ({ roundID, memberID: id(Number(m)), holeIndex: Number(hole), strokes }))),
  }));
}

const parScores = (n: number) => Object.fromEntries(PAR.slice(0, n).map((p, i) => [i, p]));
const players: [number, string, number | null][] = [[1, "Anders", 0], [2, "Bjørn", 0], [3, "Cato", 0], [4, "Dag", 0]];
// avkorting-test.js: Anders rakk 18, Bjørn 14, Cato 16. Dag møtte ikke opp.
const avkorting = (round = row()) => game(players, { 1: parScores(18), 2: parScores(14), 3: parScores(16) }, round);

test("laveste felles hull er 14, og et hoppet hull stopper opptellingen", () => {
  assert.equal(avkorting().lowestCommonHole, 14);
  const g = game([[1, "Anders", 0], [2, "Bjørn", 0]], { 1: { 0: 4, 1: 5, 2: 3, 6: 5 }, 2: parScores(10) });
  assert.equal(g.lowestCommonHole, 3);
});

test("forslaget er felles etter laveste felles hull, ellers hele runden", () => {
  assert.deepEqual(defaultCutChoice(avkorting()), { rule: "felles", after: 14 });
  const empty = game(players, {});
  assert.deepEqual(defaultCutChoice(empty), { rule: "felles", after: 18 });
  assert.equal(cutHint(empty, "felles"), "Ingen har ført noe ennå.");
  const saved = avkorting(row({ cutRule: "net_par", cutAfter: 12 }));
  assert.deepEqual(defaultCutChoice(saved), { rule: "nettopar", after: 12 });
  assert.equal(cutSummary(saved), "Avkortet etter hull 12 · uspilte hull gir netto par");
});

test("felles koster Anders åtte og Cato fire; netto par gir tilbake; null endrer ingenting", () => {
  const common = cutPreview(avkorting(), { rule: "felles", after: 14 });
  assert.equal(common.countingHoles, 14);
  assert.equal(common.holes, 18);
  assert.deepEqual(common.lines.map(cutLineText), ["Anders 36 → 28 (−8)", "Cato 32 → 28 (−4)"]);
  assert.equal(common.losers, 2);
  const net = cutPreview(avkorting(), { rule: "nettopar", after: 14 });
  assert.equal(net.countingHoles, 18);
  assert.deepEqual(net.lines.map(cutLineText), ["Cato 32 → 36 (+4)", "Bjørn 28 → 36 (+8)"]);
  assert.equal(net.losers, 0);
  const zero = cutPreview(avkorting(), { rule: "null", after: 14 });
  assert.equal(zero.countingHoles, 18);
  assert.deepEqual(zero.lines, []);
});

test("hjelpeteksten og hullnavnene", () => {
  const g = avkorting();
  assert.equal(cutHint(g, "felles"), "Alle som har begynt har ført til og med hull 14. Med denne regelen er det tallet du vil ha.");
  assert.ok(cutHint(g, "null").endsWith("Regelen over fyller hullene i stedet for å kutte dem."));
  assert.equal(cutRuleHelp("null"), "Hele runden teller. Hull uten score gir ingenting, den som rakk flest hull vinner mest på det.");
  assert.equal(cutOptionTitle(g, 14), "Hull 14 · laveste felles");
  assert.equal(cutOptionTitle(g, 15), "Hull 15");
  const back9 = game([[1, "Anders", 0]], { 1: parScores(3) }, row({ holeCount: 9, firstHole: 10 }));
  assert.equal(cutOptionTitle(back9, 5), "Hull 14");
  assert.equal(cutOptionTitle(back9, 3), "Hull 12 · laveste felles");
});

test("lagringen skriver alle fire felt, og fjerning skriver null", () => {
  const set = cutPatch({ rule: "felles", after: 14 }, id(42), new Date(1_790_000_000_000));
  assert.equal(set.cut_rule, "common");
  assert.equal(set.cut_after, 14);
  assert.equal(set.cut_by, id(42));
  assert.ok(typeof set.cut_at === "string");
  assert.deepEqual(cutPatch(null, id(42), new Date()), { cut_rule: null, cut_after: null, cut_by: null, cut_at: null });
  assert.ok(cutPatchMatches(cutPatch({ rule: "nettopar", after: 14 }, null, new Date()), { cut_rule: "net_par", cut_after: 14 }));
  assert.ok(!cutPatchMatches(cutPatch({ rule: "nettopar", after: 14 }, null, new Date()), { cut_rule: null, cut_after: null }));
  assert.ok(cutPatchMatches(cutPatch(null, null, new Date()), { cut_rule: null, cut_after: null }));
});

test("avslutt kvelden: spørsmålet foreslår avkorting", () => {
  assert.equal(playersMissingHoles(avkorting()), 2);
  assert.equal(playersMissingHoles(avkorting(row({ cutRule: "common", cutAfter: 14 }))), 0);
  const prompt = closePrompt([closeCheck(avkorting(), "Runde 1 – Testbanen")])!;
  assert.equal(prompt.title, "Avslutte Runde 1 – Testbanen?");
  assert.equal(prompt.suggestCut, roundID);
  assert.equal(prompt.lines[0], "2 spillere har ikke ført alle 18 hullene. Uspilte hull gir 0 poeng slik runden står nå, så den som rakk færrest hull taper på det.");
  assert.equal(prompt.lines.at(-1), "Runden låses og teller i turneringen.");

  const cut = closePrompt([closeCheck(avkorting(row({ cutRule: "common", cutAfter: 14 })), "Runde 1")])!;
  assert.equal(cut.suggestCut, null);
  assert.equal(cut.lines[0], "Avkortet etter hull 14 · tell til laveste felles hull.");
  const zero = avkorting(row({ cutRule: "zero", cutAfter: 14 }));
  assert.equal(playersMissingHoles(zero), 2);
  assert.equal(closePrompt([closeCheck(zero, "Runde 1")])!.suggestCut, null);
  assert.equal(closePrompt([]), null);
});

test("meldingen sier hva som er låst", () => {
  assert.equal(closeSummary(["Runde 1"], [], []), "Runde 1 er låst. Kvelden er ferdig, og neste kveld står øverst.");
  assert.equal(closeSummary(["Runde 1", "Runde 2"], ["Runde 3"], []),
    "Låst: Runde 1, Runde 2. Kladden Runde 3 er ikke spilt. Kvelden er ikke ferdig før den er startet og låst, eller slettet.");
  assert.equal(closeSummary([], [], ["Runde 1"]), "Ble ikke låst: Runde 1. Prøv igjen.");
  assert.equal(closeSummary(["Runde 1"], [], [], "playingDay"), "Runde 1 er låst. Spilledagen er ferdig, og neste spilledag står øverst.");
});

// GAMMEL: låst, Trackman fordeler. Thomas og Bjørn har ført, Cato er med uten score.
const gammel = () => game([[1, "Thomas", 12], [2, "Bjørn", 8], [3, "Cato", 20]],
  { 1: { 0: 4, 1: 5, 2: 3 }, 2: { 0: 5, 1: 6, 2: 4 } }, row({ status: "locked", externalHandicap: true }));

test("tabellen har de som har ført, flest poeng øverst", () => {
  const t = roundTable(gammel());
  assert.deepEqual(t.rows.map((r) => r.name), ["Thomas", "Bjørn"]);
  assert.equal(t.columns.length, 18);
  assert.equal(t.columns.at(-1)?.number, 18);
  assert.equal(t.parTotal, 72);
  assert.deepEqual(t.rows.map((r) => r.points), [6, 3]);
  assert.deepEqual(t.rows.map((r) => r.strokes), [12, 15]);
  assert.equal(t.rows[1].cells[1].strokes, 6);
  assert.equal(t.rows[1].cells[1].scoreName, "bogey");
  assert.equal(t.rows[1].cells[5].strokes, null);
  assert.ok(!t.hasOutside);
  const empty = roundTable(game([[1, "Thomas", 0], [2, "Bjørn", 0]], {}));
  assert.deepEqual(empty.rows.map((r) => r.name), ["Bjørn", "Thomas"]);
  assert.ok(empty.rows.every((r) => r.strokes === null && r.points === 0));
  const cut = roundTable(avkorting(row({ cutRule: "common", cutAfter: 14 })));
  assert.equal(cut.countingHoles, 14);
  assert.deepEqual(cut.columns.filter((c) => c.outside).map((c) => c.number), [15, 16, 17, 18]);
  assert.deepEqual(cut.rows.map((r) => r.points), [28, 28, 28]);
});

test("retting: ruten åpner med tallet som står, og sendes som ett hull", () => {
  const g = gammel();
  let c = newCorrection(g, id(2), 1);
  assert.deepEqual([c.original, c.strokes, correctionChanged(c)], [6, 6, false]);
  assert.equal(correctionButtonTitle(g, c), "Lagre rettingen");
  assert.equal(correctionParams(g, c, new Date()), null);
  assert.equal(correctionCurrentText(c), "Står nå: 6 slag.");
  c = stepCorrection(c, -1);
  assert.equal(correctionButtonTitle(g, c), "Lagre 5 på hull 2");
  assert.equal(correctionDoneText(g, c), "Hull 2 for Bjørn er rettet fra 6 til 5.");
  const at = new Date(1_790_000_000_000);
  assert.deepEqual(correctionParams(g, c, at), {
    p_round_id: roundID, p_hole_index: 1, p_scores: [{ member_id: id(2), strokes: 5 }], p_recorded_at: at.toISOString(),
  });
  assert.deepEqual(correctionOutcome(g, c), { name: "par", points: 2 });
});

test("retting: tomt hull starter på par, og stepperen holder seg innenfor grensene", () => {
  const g = gammel();
  const empty = newCorrection(g, id(3), 1);
  assert.deepEqual([empty.original, empty.strokes, correctionChanged(empty)], [null, 5, true]);
  assert.equal(correctionCurrentText(empty), "Ikke lagret.");
  assert.equal(correctionDoneText(g, empty), "Hull 2 for Cato er rettet til 5.");
  let c = newCorrection(g, id(1), 2);
  for (let i = 0; i < 10; i++) c = stepCorrection(c, -1);
  assert.equal(c.strokes, STROKE_MIN);
  for (let i = 0; i < 30; i++) c = stepCorrection(c, 1);
  assert.equal(c.strokes, STROKE_MAX);
  assert.ok(correctionNotice("locked") !== null);
  assert.equal(correctionNotice("active"), null);
});

// MARK: Startlista

const slPlayers = [{ memberID: id(1), bayNo: 1 }, { memberID: id(2), bayNo: 1 }, { memberID: id(3), bayNo: 2 }, { memberID: id(4), bayNo: 3 }, { memberID: id(5), bayNo: null }];

test("startlista: gruppene er båsene, og det som er lagret legges på", () => {
  const saved = [{ round_id: id(600), group_no: 2, starts_at: "18:10:00", start_hole: 10, resource_label: "Trackman 2", scorer_id: id(77) }];
  const groups = startGroups(slPlayers, saved, "simulator");
  assert.deepEqual(groups.map((x) => x.groupNo), [1, 2, 3]);
  assert.deepEqual(groups[0].memberIDs, [id(1), id(2)]);
  assert.equal(groups[0].resourceLabel, "Bås 1");
  assert.equal(groups[1].startsAt, "18:10");
  assert.equal(groups[1].resourceLabel, "Trackman 2");
  assert.equal(groups[1].scorerID, id(77));
  assert.equal(startGroups(slPlayers, [], "course")[0].resourceLabel, "");
  assert.deepEqual(startGroups([{ memberID: id(1), bayNo: null }], [], null), []);
});

test("startlista: tider, kanonstart, sjekker og parametre", () => {
  const groups = startGroups(slPlayers, [], "course");
  assert.deepEqual(fillTimes(groups, "23:50", 10).map((x) => x.startsAt), ["23:50", "00:00", "00:10"]);
  assert.deepEqual(fillTimes(groups, "kl 18", 10), groups);
  const first = groups.map((x, i) => (i === 0 ? { ...x, startsAt: "09:00" } : x));
  const shot = shotgun(first, 2);
  assert.deepEqual(shot.map((x) => x.startHole), [1, 2, 1]);
  assert.deepEqual(shot.map((x) => x.startsAt), ["09:00", "09:00", "09:00"]);

  let sim = startGroups(slPlayers, [], "simulator");
  assert.deepEqual(startListIssues(sim, 1, 18, new Set()), []);
  assert.deepEqual(startListIssues(sim, 0, 18, new Set()), ["Puljen må være mellom 1 og 20."]);
  sim = sim.map((x, i) => (i === 0 ? { ...x, startHole: 10 } : x));
  assert.deepEqual(startListIssues(sim, 1, 9, new Set()), ["Starthullet må være mellom 1 og 9."]);
  sim = sim.map((x, i) => (i === 0 ? { ...x, startHole: null } : i === 1 ? { ...x, scorerID: id(77) } : x));
  assert.deepEqual(startListIssues(sim, 1, 18, new Set()), ["En funksjonær er ikke lenger i staben."]);
  assert.deepEqual(startListIssues(sim, 1, 18, new Set([id(77)])), []);
  sim = sim.map((x, i) => (i === 2 ? { ...x, startsAt: "25:00" } : x));
  assert.deepEqual(startListIssues(sim, 1, 18, new Set([id(77)])), ["Starttiden må være på formen TT:MM."]);

  const labelled = groups.map((x, i) => (i === 0 ? { ...x, resourceLabel: "  Tee 10 " } : x));
  const p = startListParams(id(600), 2, labelled);
  assert.equal(p.p_wave_no, 2);
  assert.equal(p.p_groups[0].resource_label, "Tee 10");
  assert.equal(p.p_groups[1].resource_label, null);
  assert.ok(JSON.stringify(p.p_groups[1]).includes('"scorer_id":null'));
});
