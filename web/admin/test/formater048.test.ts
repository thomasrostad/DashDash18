// Steg 7 (sql/048): konkurranser i runden, lag mot lag, øyeblikksbildet og «Samme som sist».

import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import {
  COMPETITION_CONFIG_KEYS, competitionBoards, formById, DEFAULT_PAR, decodeCourseHoleRecord, decodeCourseRow, decodeHoleScoreRow, decodeRoundMatchRow,
  decodeRoundPlayerRow, decodeRoundRow, decodeStoredCompetition, encodeRuleset, frozenFromRows, GOLFGUTU, makeSnapshot, snapshotFields,
  type StoredCompetition,
} from "../../golfgutu-core/src/index.ts";
import {
  chosenTeams, competitionConfig, competitionIssues, competitionsPayload, competitionSummary, copiedCompetitions, draftFromStored, groupsFor, holeRange,
  isOneBallMatch, maxStrokesOf, pairsFor, recipeDraft, recipesFor, teamNumbers, withMatchTeam, roundResults, setSide, sideProblem, sidesFromRows, withMaxStrokes, withSides, type CompetitionContext,
} from "../src/rounds/competitions.ts";
import { RoundGame } from "../src/rounds/game.ts";
import { newDraft } from "../src/rounds/logic.ts";
import { applyPreviousCompetitions, applyPreviousPlayers, decodePreviousSetup } from "../src/reuse.ts";

const A = "00000000-0000-0000-0000-00000000000a";
const B = "00000000-0000-0000-0000-00000000000b";
const C = "00000000-0000-0000-0000-00000000000c";
const D = "00000000-0000-0000-0000-00000000000d";

const ctx = (o: Partial<CompetitionContext> = {}): CompetitionContext => ({
  participants: [A, B, C, D], teams: {},
  bays: [{ memberID: A, bay: 1, isMarker: true }, { memberID: B, bay: 1, isMarker: false }, { memberID: C, bay: 2, isMarker: false }, { memberID: D, bay: 2, isMarker: true }],
  holeCount: 18, mainForm: "stableford", ...o,
});

// MARK: config og nøklene i 048

test("config har bare nøklene 048 godtar, og hovedkonkurransen er {form}", () => {
  for (const r of recipesFor(18)) {
    const cfg = competitionConfig({ ...recipeDraft(r.id, "stableford"), allowance: 0.5 }, ctx({ teams: { [A]: 1, [B]: 1, [C]: 2, [D]: 2 } }));
    for (const k of Object.keys(cfg)) assert.ok((COMPETITION_CONFIG_KEYS as readonly string[]).includes(k), `${r.id}: ${k}`);
    assert.ok("form" in cfg || ("teamForm" in cfg && "scoring" in cfg), r.id);
  }
  assert.deepEqual(competitionConfig(recipeDraft("skins", "stableford"), ctx(), true), { form: "stableford" });
  const payload = competitionsPayload([recipeDraft("skins", "stableford")], ctx(), "11111111-1111-1111-1111-111111111111");
  assert.deepEqual(Object.keys(payload[0]).sort(), ["config", "format_version", "id", "is_main", "name", "sort_order"]);
  assert.deepEqual(payload[0], { id: "11111111-1111-1111-1111-111111111111", name: formById("stableford").name, is_main: true, format_version: 1, config: { form: "stableford" }, sort_order: 0 });
  assert.deepEqual(payload[1], { name: "Skins", is_main: false, format_version: 1, config: { form: "skins" }, sort_order: 1 });
  assert.equal("allowance" in (payload[0].config as object), false);
});

test("oppskriftene: bestball, skins, første og siste ni, Amerikaner og Københavner", () => {
  const teams = { [A]: 1, [B]: 1, [C]: 2, [D]: 2 };
  assert.deepEqual(competitionConfig(recipeDraft("bestball", "stableford"), ctx({ teams })), {
    teamForm: { type: "pairs", pairs: "fourball" }, scoring: { type: "strokePlay", net: true }, entrants: [[A, B], [C, D]],
  });
  // Uten lag: to og to i båsen, markøren først.
  assert.deepEqual(pairsFor(ctx()), [[A, B], [D, C]]);
  assert.deepEqual(competitionConfig(recipeDraft("skins", "slag-netto"), ctx()), { form: "skins" });
  assert.deepEqual(competitionConfig(recipeDraft("front", "slag-netto"), ctx()), { form: "slag-netto", holes: { first: 0, last: 8 } });
  assert.deepEqual(competitionConfig(recipeDraft("back", "stableford"), ctx()), { form: "stableford", holes: { first: 9, last: 17 } });
  assert.deepEqual(competitionConfig(recipeDraft("amerikaner", "stableford"), ctx()), { form: "amerikaner", entrants: [[A, B], [C, D]] });
  assert.deepEqual(competitionConfig(recipeDraft("kobenhavner", "stableford"), ctx({ teams: { [A]: 2, [B]: 1, [C]: 1, [D]: 2 } })),
    { form: "kobenhavner", entrants: [[B, C], [A, D]] });
  assert.deepEqual(groupsFor(ctx()), [[A, B], [C, D]]);
  // Siste ni bare på 18 hull.
  assert.equal(recipesFor(9).some((r) => r.id === "back"), false);
  assert.equal(holeRange("back", 9), null);
});

test("valgte spillere, andel og de som ikke er med", () => {
  const d = { ...recipeDraft("front", "stableford"), entrants: "selected" as const, selected: [A, C, "00000000-0000-0000-0000-0000000000ff"], allowance: 0.75 };
  assert.deepEqual(competitionConfig(d, ctx()), { form: "stableford", entrants: [[A], [C]], holes: { first: 0, last: 8 }, allowance: 0.75 });
  assert.deepEqual(competitionConfig({ ...recipeDraft("skins", "stableford"), entrants: "selected", selected: [B, D] }, ctx()), { form: "skins", entrants: [[B, D]] });
});

test("problemene før lagring", () => {
  assert.deepEqual(competitionIssues([recipeDraft("skins", "stableford")], ctx()), []);
  assert.ok(competitionIssues([{ ...recipeDraft("skins", "stableford"), name: " " }], ctx())[0].includes("navn"));
  assert.ok(competitionIssues([recipeDraft("back", "stableford")], ctx({ holeCount: 9 }))[0].includes("18 hull"));
  assert.ok(competitionIssues([{ ...recipeDraft("skins", "stableford"), entrants: "selected" }], ctx())[0].includes("minst én"));
  assert.ok(competitionIssues([recipeDraft("bestball", "stableford")], ctx({ participants: [A], bays: [{ memberID: A, bay: 1, isMarker: true }] }))[0].includes("lag først"));
  assert.ok(competitionIssues(Array.from({ length: 10 }, () => recipeDraft("skins", "stableford")), ctx())[0].includes("Høyst 10"));
});

test("lagret rad → utkast → samme config", () => {
  const teams = { [A]: 1, [B]: 1, [C]: 2, [D]: 2 };
  for (const r of recipesFor(18)) {
    const cfg = competitionConfig(recipeDraft(r.id, "stableford"), ctx({ teams }));
    const row = decodeStoredCompetition({ id: "22222222-2222-2222-2222-222222222222", round_id: "x", name: r.name, is_main: false, format_version: 1, config: cfg, sort_order: 1 })!;
    const back = draftFromStored(row);
    assert.equal(back.id, "22222222-2222-2222-2222-222222222222");
    assert.deepEqual(competitionConfig(back, ctx({ teams })), cfg, r.id);
  }
});

// MARK: lag mot lag

test("sidene: samme lag på samme side, og hele laget eller ingen", () => {
  const teams = { [A]: 1, [B]: 1, [C]: 2, [D]: 2 };
  assert.equal(sideProblem({ [A]: 1, [B]: 1, [C]: 2, [D]: 2 }, teams, [A, B, C, D]), null);
  assert.equal(sideProblem({ [A]: 1, [B]: 2 }, teams, [A, B, C, D]), "Spillerne på samme lag må være på samme side.");
  assert.equal(sideProblem({ [A]: 1 }, teams, [A, B, C, D]), "Spillerne på samme lag må være på samme side.");
  assert.equal(sideProblem({ [A]: 1, [C]: 1 }, {}, [A, B, C, D]), null);
  // Én flyttes, laget følger med.
  assert.deepEqual(setSide({}, teams, A, 2), { [A]: 2, [B]: 2 });
  assert.deepEqual(setSide({ [A]: 2, [B]: 2 }, teams, B, null), {});
  assert.deepEqual(withSides([{ member_id: A, bay_no: 1 }, { member_id: B, bay_no: 1 }], { [A]: 1 }),
    [{ member_id: A, bay_no: 1, side: 1 }, { member_id: B, bay_no: 1, side: null }]);
  assert.deepEqual(sidesFromRows([{ member_id: A.toUpperCase(), side: 2 }, { member_id: B, side: null }, { member_id: C, side: 3 }]), { [A]: 2 });
});

// MARK: «Samme som sist»

test("«Samme som sist» kopierer konkurransene som nye rader og sidene", () => {
  const raw = {
    round_id: "33333333-3333-3333-3333-333333333333", round_no: 2, format: "stableford",
    players: [{ member_id: A, bay_no: 1, is_marker: true, team_no: null, side: 1 }, { member_id: B, bay_no: 1, is_marker: false, team_no: null, side: 2 }],
    matches: [],
    competitions: [
      { name: "Stableford", is_main: true, format_version: 1, config: { form: "stableford" }, sort_order: 0 },
      { name: "Skins", is_main: false, format_version: 1, config: { form: "skins", entrants: [[A, C]] }, sort_order: 1 },
    ],
  };
  const prev = decodePreviousSetup(raw)!;
  assert.equal(prev.competitions.length, 2);
  const roster = [A, B].map((id) => ({ id, name: id, handicap: 10, seed: null, userID: null }));
  const base = newDraft({ roundID: "r", eventID: "e", roundNo: 3, teeTime: null, participants: [A, B], source: "signups", rules: GOLFGUTU });
  const d = applyPreviousCompetitions(applyPreviousPlayers({ ...base, sides: {} }, prev, roster), prev);
  assert.deepEqual(d.sides, { [A]: 1, [B]: 2 });
  assert.equal(d.competitions!.length, 1);
  assert.equal(d.competitions![0].id, null);
  // C er ikke med i den nye runden og tas bort når den lagres.
  assert.deepEqual(competitionConfig(d.competitions![0], { ...ctx(), participants: d.participants }), { form: "skins", entrants: [[A]] });
  // Uten 048: ingen konkurranser og ingen sider i svaret.
  const old = decodePreviousSetup({ ...raw, competitions: undefined, players: [{ member_id: A, bay_no: 1, is_marker: true, team_no: null }] })!;
  assert.deepEqual(old.competitions, []);
  assert.equal(applyPreviousPlayers(base, old, roster).sides, undefined);
  assert.deepEqual(copiedCompetitions([]), []);
});

// MARK: øyeblikksbildet og resultatene

const fixture = JSON.parse(readFileSync(new URL("../../golfgutu-core/test/fixtures/tavla.json", import.meta.url), "utf8")).tavlaData;
const ROUND = "00000000-0000-0000-0000-000000000101";

function game(): RoundGame {
  const raw = fixture.rounds.find((r: { id: string }) => r.id === ROUND);
  const round = decodeRoundRow(raw);
  return new RoundGame(makeSnapshot(round, {
    players: fixture.players.filter((p: { round_id: string }) => p.round_id === ROUND).map((x: unknown) => decodeRoundPlayerRow(x)),
    matches: fixture.matches.filter((p: { round_id: string }) => p.round_id === ROUND).map((x: unknown) => decodeRoundMatchRow(x)),
    scores: fixture.scores.filter((p: { round_id: string }) => p.round_id === ROUND).map((x: unknown) => decodeHoleScoreRow(x)),
    course: decodeCourseRow(fixture.courses.find((c: { id: string }) => c.id === round.courseID)),
    courseHoles: fixture.course_holes.filter((h: { course_id: string }) => h.course_id === round.courseID).map((x: unknown) => decodeCourseHoleRecord(x)),
    rules: GOLFGUTU,
    names: new Map(fixture.members.map((m: { id: string; display_name: string }) => [m.id, m.display_name])),
  }));
}

const extra = (name: string, config: Record<string, unknown>): StoredCompetition =>
  ({ id: `44444444-4444-4444-4444-44444444444${name.length % 10}`, roundID: ROUND, name, isMain: false, formatVersion: 1, config, sortOrder: 1 });
const main: StoredCompetition = { id: "55555555-5555-5555-5555-555555555555", roundID: ROUND, name: "Stableford", isMain: true, formatVersion: 1, config: { form: "stableford" }, sortOrder: 0 };

test("uten øyeblikksbilde regnes det fra dagens data: hovedkonkurransen er rundens stableford", () => {
  const g = game();
  const fields = snapshotFields({ format: "stableford", external_handicap: false });
  assert.equal(frozenFromRows(fields, g.snapshot.players, g.rules), null);
  const r = roundResults(g, { competitions: [main, extra("Skins", { form: "skins" })], snapshot: fields, sidePlayers: [] })!;
  assert.equal(r.boards.length, 2);
  const stableford = r.boards[0];
  assert.ok(stableford.supported && stableford.isMain);
  for (const row of stableford.rows) assert.equal(row.score, g.total(row.players[0]), g.name(row.players[0]));
  assert.ok(r.boards[1].supported);
  assert.equal(r.team, null);
  // Uten andre konkurranser eller sider vises ingenting ekstra.
  assert.equal(roundResults(g, { competitions: [main], snapshot: fields, sidePlayers: [] }), null);
});

test("FrozenRound fra rules_snapshot og holes_snapshot: samme hull gir samme svar, rettet par endrer det", () => {
  const g = game();
  const holes = g.holes.map((h, i) => ({ hole: i + 1, par: h.par, cardIndex: h.cardIndex, meters: h.meters, strokeIndex: h.strokeIndex }));
  const raw = { format: "stableford", external_handicap: false, rules_snapshot: encodeRuleset(GOLFGUTU), holes_snapshot: { holes }, snapshot_source: "start" };
  const frozen = frozenFromRows(snapshotFields(raw), g.snapshot.players, GOLFGUTU, (m) => g.handicap(m))!;
  assert.equal(frozen.holes.length, 18);
  assert.equal(frozen.gameType, "stableford");
  for (const p of g.snapshot.players) assert.equal(frozen.playingHandicaps.get(p.memberID), g.handicap(p.memberID));
  const comps = [main, extra("Første ni", { form: "stableford", holes: { first: 0, last: 8 } })];
  const live = competitionBoards({ competitions: comps, roundFormat: "stableford", frozen: null, live: { round: g.round, roster: g.roster, rules: g.rules } });
  const fromSnapshot = competitionBoards({ competitions: comps, roundFormat: "stableford", frozen, live: { round: g.round, roster: g.roster, rules: g.rules } });
  assert.deepEqual(fromSnapshot, live);

  // Par ett høyere på alle hull: ett poeng mer per hull spilt.
  const harder = frozenFromRows(snapshotFields({ ...raw, holes_snapshot: { holes: holes.map((h) => ({ ...h, par: h.par + 1 })) } }), g.snapshot.players, GOLFGUTU, (m) => g.handicap(m))!;
  const changed = competitionBoards({ competitions: [main], roundFormat: "stableford", frozen: harder, live: { round: g.round, roster: g.roster, rules: g.rules } })[0];
  let sumBefore = 0, sumAfter = 0;
  for (const row of changed.rows) {
    const before = live[0].rows.find((x) => x.players[0] === row.players[0])!;
    // Høyst ett poeng mer per hull (laveste hullpoeng er 0).
    assert.ok(row.score >= before.score && row.score <= before.score + row.holes);
    sumBefore += before.score; sumAfter += row.score;
  }
  assert.ok(sumAfter > sumBefore);
  // Par mangler i øyeblikksbildet: standardbanen.
  const noPar = frozenFromRows(snapshotFields({ ...raw, holes_snapshot: { holes: holes.map((h) => ({ ...h, par: null })) } }), g.snapshot.players, GOLFGUTU)!;
  assert.deepEqual(noPar.holes.map((h) => h.par), DEFAULT_PAR);
  // Regelsettet mangler (runde uten turnering): dagens regler.
  assert.equal(frozenFromRows(snapshotFields({ ...raw, rules_snapshot: null }), g.snapshot.players, GOLFGUTU)!.ruleset, GOLFGUTU);
  // Rekonstruert: vises som det.
  assert.equal(roundResults(g, { competitions: comps, snapshot: snapshotFields({ ...raw, snapshot_source: "backfill" }), sidePlayers: [] })!.reconstructed, true);
});

test("ikke støttet ennå: foursome i en runde som ikke spilles i foursome; match uten sider gir ingen rader", () => {
  const g = game();
  const r = roundResults(g, {
    competitions: [main, extra("Foursome", { form: "foursome" }), extra("Match", { teamForm: { type: "individual" }, scoring: { type: "matchPlay" } })],
    snapshot: snapshotFields({ format: "stableford" }), sidePlayers: [],
  })!;
  assert.deepEqual(r.boards.map((b) => b.supported), [true, false, true]);
  assert.deepEqual(r.boards[2].rows, []);
  assert.equal(r.boards[2].isMatch, true);
});

test("maksimumscore og match: slag med tak, og side 1 mot side 2 fra lag mot lag", () => {
  const g = game();
  const ids = g.snapshot.players.map((p) => p.memberID);
  const sidePlayers = ids.map((id, i) => ({ member_id: id, side: i % 2 === 0 ? 1 : 2 }));
  const r = roundResults(g, {
    competitions: [main, extra("Maks", { form: "maks-score" }),
      extra("Lagmatch", { teamForm: { type: "individual" }, scoring: { type: "matchPlay" } }),
      extra("To", { teamForm: { type: "individual" }, scoring: { type: "matchPlay" }, entrants: [[ids[0]], [ids[1]]] })],
    snapshot: snapshotFields({ format: "stableford" }), sidePlayers,
  })!;
  const [, maks, sides, two] = r.boards;
  assert.ok(maks.supported && !maks.higherIsBetter && !maks.isMatch);
  // Taket kan bare ta slag bort.
  for (const row of maks.rows) {
    const gross = [...(g.round.holeScores.get(row.players[0])?.values() ?? [])].reduce((a, b) => a + b, 0);
    assert.ok(row.score <= gross, g.name(row.players[0]));
  }
  assert.ok(sides.supported && sides.isMatch);
  assert.deepEqual(sides.rows.map((x) => x.players.length).sort(), [Math.floor(ids.length / 2), Math.ceil(ids.length / 2)].sort());
  assert.equal(two.rows.length, 2);
  assert.equal(two.rows[0].score, -two.rows[1].score);
});

test("oppskriftene maksimumscore og match: config, hvem og problemene", () => {
  assert.deepEqual(competitionConfig(recipeDraft("maks", "stableford"), ctx()), { form: "maks-score" });
  const fixed = withMaxStrokes(recipeDraft("maks", "stableford"), { type: "fixed", strokes: 8 });
  assert.deepEqual(competitionConfig(fixed, ctx()), {
    teamForm: { type: "individual" }, scoring: { type: "maximumScore", net: true, maxStrokes: { type: "fixed", strokes: 8 } },
  });
  assert.deepEqual(maxStrokesOf(withMaxStrokes(fixed, null)), null);
  assert.equal(withMaxStrokes(fixed, null).form, "maks-score");
  assert.ok(competitionSummary(fixed, 18).includes("tak 8 slag"));
  assert.ok(competitionIssues([withMaxStrokes(fixed, { type: "fixed", strokes: 30 })], ctx())[0].includes("3–20"));

  const match = { ...recipeDraft("match", "stableford"), selected: [A, C] };
  assert.deepEqual(competitionConfig(match, ctx()), { teamForm: { type: "individual" }, scoring: { type: "matchPlay" }, entrants: [[A], [C]] });
  assert.deepEqual(competitionIssues([match], ctx()), []);
  assert.ok(competitionIssues([{ ...match, selected: [A] }], ctx())[0].includes("to spillere"));
  const sides = { ...match, entrants: "sides" as const };
  assert.deepEqual(competitionConfig(sides, ctx()), { teamForm: { type: "individual" }, scoring: { type: "matchPlay" } });
  assert.ok(competitionIssues([sides], ctx())[0].includes("lag mot lag"));
  assert.deepEqual(competitionIssues([sides], ctx({ sides: { [A]: 1, [B]: 2, [C]: 1, [D]: 2 } })), []);
  assert.equal(competitionSummary(sides, 18).startsWith("Side 1 mot side 2"), true);
  // Tilbake fra lagringen: uten sider er det side mot side, med to er det de valgte.
  const stored = (config: Record<string, unknown>): StoredCompetition => ({ id: null, roundID: null, name: "M", isMain: false, formatVersion: 1, config, sortOrder: 1 });
  assert.equal(draftFromStored(stored(competitionConfig(sides, ctx()))).entrants, "sides");
  assert.equal(draftFromStored(stored(competitionConfig(match, ctx()))).entrants, "selected");
});

test("match med én ball per lag: rundens to lag eller to valgte lag", () => {
  const E = "00000000-0000-0000-0000-00000000000e";
  const F = "00000000-0000-0000-0000-00000000000f";
  const two = ctx({ mainForm: "foursome", teams: { [A]: 1, [B]: 1, [C]: 2, [D]: 2 } });
  const m = recipeDraft("match", "foursome");
  assert.ok(isOneBallMatch(m));
  assert.equal(m.entrants, "sides");
  // Rundens to lag: ingen entrants i config (motoren tar lagene).
  assert.deepEqual(competitionConfig(m, two), { teamForm: { type: "pairs", pairs: "foursome" }, scoring: { type: "matchPlay" } });
  assert.deepEqual(competitionIssues([m], two), []);
  assert.equal(competitionSummary(m, 18).startsWith("Rundens to lag"), true);
  // Stableford-runde: matchen er som før (to spillere).
  assert.ok(!isOneBallMatch(recipeDraft("match", "stableford")));
  // Tre lag: velg to.
  const three = ctx({ mainForm: "foursome", participants: [A, B, C, D, E, F], teams: { [A]: 1, [B]: 1, [C]: 2, [D]: 2, [E]: 3, [F]: 3 } });
  assert.deepEqual(teamNumbers(three), [1, 2, 3]);
  assert.ok(competitionIssues([m], three)[0].includes("nøyaktig to lag"));
  const picked = withMatchTeam(withMatchTeam(m, three, 0, 1), three, 1, 3);
  assert.deepEqual(chosenTeams(picked, three), [1, 3]);
  assert.deepEqual(competitionConfig(picked, three).entrants, [[A, B], [E, F]]);
  assert.deepEqual(competitionIssues([picked], three), []);
  assert.ok(competitionIssues([withMatchTeam(picked, three, 1, 1)], three)[0].includes("velg to lag"));
  // Runden spilles ikke i foursome.
  assert.ok(competitionIssues([picked], { ...three, mainForm: "stableford" }).some((x) => x.includes("samme lagform")));
  // Tilbake fra lagringen.
  const stored = (config: Record<string, unknown>): StoredCompetition => ({ id: null, roundID: null, name: "M", isMain: false, formatVersion: 1, config, sortOrder: 1 });
  const back = draftFromStored(stored(competitionConfig(picked, three)));
  assert.equal(back.entrants, "twoTeams");
  assert.deepEqual(chosenTeams(back, three), [1, 3]);
  assert.equal(draftFromStored(stored(competitionConfig(m, two))).entrants, "sides");
});

test("lag mot lag: matchene gir poeng til sidene", () => {
  const g = game();
  // Match 1 sine to spillere på hver sin side; de andre matchene teller ikke.
  const m1 = g.round.matches[0];
  const sidePlayers = [{ member_id: m1.playerA, side: 1 }, { member_id: m1.playerB, side: 2 }];
  const r = roundResults(g, { competitions: [], snapshot: snapshotFields({ format: "stableford" }), sidePlayers })!;
  assert.ok(r.team);
  assert.deepEqual(r.team!.table.map((x) => x.side).sort(), [1, 2]);
  const decided = r.team!.matches.filter((m) => m.state === "decided");
  assert.equal(decided.length, 1);
  assert.ok(r.team!.matches.some((m) => m.state === "invalid"));
  const total = r.team!.table.reduce((s, x) => s + x.points, 0);
  assert.equal(total, decided.length * (GOLFGUTU.formPlay.teamMatch.win + GOLFGUTU.formPlay.teamMatch.loss) - decided.filter((m) => m.outcomeA === 0.5).length * (GOLFGUTU.formPlay.teamMatch.win + GOLFGUTU.formPlay.teamMatch.loss - 2 * GOLFGUTU.formPlay.teamMatch.draw));
  // Bare hovedkonkurransen (ingen rader): rundens form.
  assert.equal(r.boards.length, 1);
  assert.equal(r.boards[0].isMain, true);
});
