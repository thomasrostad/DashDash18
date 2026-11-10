// Oppstillingstavla: bås, lag og matcher på ett sted (src/rounds/lineup.ts).
import { test } from "node:test";
import assert from "node:assert/strict";
import { formById, golfgutuRules } from "../../golfgutu-core/src/index.ts";
import { autoLineup, lineupMatches, lineupOf, placePlayer, teamsPerBay } from "../src/rounds/lineup.ts";
import { newDraft, type RosterMember, type RoundDraft } from "../src/rounds/logic.ts";

const scramble = formById("scramble-2");
const stableford = formById("stableford");
const ids = ["a", "b", "c", "d", "e", "f", "g", "h"];
const roster: RosterMember[] = ids.map((id, i) => ({ id, name: id.toUpperCase(), handicap: (i + 1) * 3, seed: null }));

function draft(): RoundDraft {
  return newDraft({ roundID: "r", eventID: "e", roundNo: 1, teeTime: null, participants: [...ids], source: "signups", rules: golfgutuRules() });
}

// Torsdag 12.11 før rettingen: Strypet alene på lag 1, tre på lag 2 i bås 1.
function thursday(): RoundDraft {
  const d = draft();
  return {
    ...d, formID: "scramble-2",
    bays: ids.map((id, i) => ({ memberID: id, bay: i < 4 ? 1 : 2, isMarker: i === 3 || i === 5 })),
    teams: { a: 1, b: 2, c: 2, d: 2, e: 3, f: 3, g: 4, h: 4 },
  };
}

test("to lag per bås når et lag er halve båsen", () => {
  assert.equal(teamsPerBay(scramble, 4), 2);
  assert.equal(teamsPerBay(formById("scramble-4"), 4), 1);
  assert.equal(teamsPerBay(stableford, 4), 4);
});

test("tavla viser 1 mot 3 i båsen (scramble tillater ujevne lag, så det er en merknad)", () => {
  const l = lineupOf(thursday(), scramble, true, 4, 2);
  assert.deepEqual(l.bays.map((b) => b.teams.map((t) => [t.team, t.members.length, t.missing])), [
    [[1, 1, 1], [2, 3, -1]],
    [[3, 2, 0], [4, 2, 0]],
  ]);
  assert.deepEqual(l.bays[0].notes, ["Lag 1 mangler én.", "Lag 2 har 1 for mange."]);
  assert.deepEqual(l.bays[0].problems, []);
  assert.deepEqual(l.bays[1].notes, []);
  // Foursome tillater ikke ujevne lag: da stopper det.
  const strict = lineupOf({ ...thursday(), formID: "foursome" }, formById("foursome"), true, 4, 2);
  assert.deepEqual(strict.bays[0].problems, ["Lag 1 mangler én.", "Lag 2 har 1 for mange."]);
  assert.deepEqual(l.problems, []);
});

test("flytt Næsset til lag 1: begge båsene går opp, og matchene er lag mot lag i båsen", () => {
  const d = placePlayer(thursday(), "c", { kind: "bay", bay: 1, team: 1 }, roster);
  const l = lineupOf(d, scramble, true, 4, 2);
  assert.deepEqual(l.bays.flatMap((b) => [...b.problems, ...b.notes]), []);
  assert.deepEqual(lineupMatches(d).map((m) => [m.teamA, m.teamB]), [[1, 2], [3, 4]]);
});

test("tom bås får tomme lag å legge spillere i, og første spiller blir markør", () => {
  const l = lineupOf(thursday(), scramble, true, 4, 3);
  assert.equal(l.bays.length, 3);
  assert.deepEqual(l.bays[2].teams.map((t) => [t.team, t.members.length]), [[5, 0], [6, 0]]);
  const d = placePlayer(thursday(), "h", { kind: "bay", bay: 3, team: 5 }, roster);
  assert.equal(d.bays.find((s) => s.memberID === "h")?.isMarker, true);
  assert.equal(d.teams.h, 5);
});

test("ut av båsen og ut av runden", () => {
  const off = placePlayer(thursday(), "a", { kind: "unseated" }, roster);
  assert.deepEqual(lineupOf(off, scramble, true, 4, 2).unseated, ["a"]);
  assert.equal(off.teams.a, undefined);
  const out = placePlayer(thursday(), "a", { kind: "out" }, roster);
  assert.equal(out.participants.includes("a"), false);
  const back = placePlayer(out, "a", { kind: "bay", bay: 1, team: 1 }, roster);
  assert.equal(back.participants.includes("a"), true);
});

test("fordel automatisk: jevne lag etter handicap, to lag per bås, markør i hver", () => {
  const d = autoLineup(draft(), roster, scramble, true, 4, 2);
  const l = lineupOf(d, scramble, true, 4, 2);
  assert.deepEqual(l.bays.flatMap((b) => b.problems), []);
  // Slangevis: a+h, b+g, c+f, d+e — summen av handicap er lik (27) på alle lag.
  const sum = (t: number) => ids.filter((id) => d.teams[id] === t).reduce((s, id) => s + roster.find((m) => m.id === id)!.handicap!, 0);
  assert.deepEqual([1, 2, 3, 4].map(sum), [27, 27, 27, 27]);
  assert.deepEqual(lineupMatches(d).map((m) => [m.teamA, m.teamB]), [[1, 2], [3, 4]]);
});

test("uten lagform: slangevis på båsene og markør i hver", () => {
  const d = autoLineup(draft(), roster, stableford, false, 4, 2);
  const l = lineupOf(d, stableford, false, 4, 2);
  assert.deepEqual(l.bays.map((b) => b.members.length), [4, 4]);
  assert.deepEqual(l.bays.map((b) => b.marker !== undefined), [true, true]);
  assert.deepEqual(l.bays.flatMap((b) => b.teams), []);
});
