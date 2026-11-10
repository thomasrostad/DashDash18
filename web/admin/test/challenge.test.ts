// «Challenge etter runden» (Kvelden): grunnene og gruppene som blir tilleggspoeng. Samme tall i appen
// (DashDash18Tests/RoundChallengeTests.swift).
import { test } from "node:test";
import assert from "node:assert/strict";
import { CHALLENGE_DEFAULT, challengeGroups, challengeProblem, challengeReason, lastChallengeRound } from "../src/kvelden/challenge.ts";
import { BAY_TERM, FLIGHT_TERM } from "../src/rounds/logic.ts";

const players = [
  { memberID: "a", group: 1 }, { memberID: "b", group: 2 }, { memberID: "c", group: 1 }, { memberID: "d", group: 2 },
];

test("grunnen har samme form som 22.10", () => {
  assert.equal(challengeReason("CP knockout", 1, "group", BAY_TERM, 1), "CP knockout, bås 1");
  assert.equal(challengeReason("CP knockout", 2, "group", BAY_TERM, 2), "CP knockout runde 2, bås 2");
  assert.equal(challengeReason("CTP", 1, "group", FLIGHT_TERM, 3), "CTP, flight 3");
  assert.equal(challengeReason("  CTP  ", 1, "all", BAY_TERM, 0), "CTP");
  assert.equal(challengeReason("CTP", 3, "all", BAY_TERM, 0), "CTP runde 3");
  // Høyst 80 tegn: navnet kortes, halen står.
  const long = challengeReason("x".repeat(100), 2, "group", BAY_TERM, 1);
  assert.equal([...long].length, 80);
  assert.ok(long.endsWith(" runde 2, bås 1"));
});

test("én vinner per bås, eller hele runden når ingen har bås", () => {
  const g = challengeGroups(CHALLENGE_DEFAULT, players, BAY_TERM);
  assert.deepEqual(g.map((x) => [x.no, x.title, x.members, x.reason]), [
    [1, "Bås 1", ["a", "c"], "CP knockout, bås 1"],
    [2, "Bås 2", ["b", "d"], "CP knockout, bås 2"],
  ]);
  const all = challengeGroups({ ...CHALLENGE_DEFAULT, scope: "all" }, players, BAY_TERM);
  assert.deepEqual(all.map((x) => [x.no, x.title, x.members.length, x.reason]), [[0, "Hele runden", 4, "CP knockout"]]);
  const noBays = challengeGroups(CHALLENGE_DEFAULT, players.map((p) => ({ ...p, group: 0 })), BAY_TERM);
  assert.deepEqual(noBays.map((x) => x.title), ["Hele runden"]);
  const someWithout = challengeGroups(CHALLENGE_DEFAULT, [...players, { memberID: "e", group: 0 }], BAY_TERM);
  assert.deepEqual(someWithout.map((x) => x.title), ["Bås 1", "Bås 2", "Uten bås"]);
});

test("navn og poeng må være i orden", () => {
  assert.equal(challengeProblem(CHALLENGE_DEFAULT), null);
  assert.equal(challengeProblem({ ...CHALLENGE_DEFAULT, name: " " }), "Gi challengen et navn.");
  assert.equal(challengeProblem({ ...CHALLENGE_DEFAULT, points: 0 }), "Vinneren må få mer enn 0 poeng.");
  assert.equal(challengeProblem({ ...CHALLENGE_DEFAULT, points: 0.125 }), "Poengene kan ha høyst to desimaler.");
});

test("fortsetter på runden dere var på", () => {
  assert.equal(lastChallengeRound(CHALLENGE_DEFAULT, players, BAY_TERM, []), 0);
  assert.equal(lastChallengeRound(CHALLENGE_DEFAULT, players, BAY_TERM, ["CP knockout, bås 2"]), 1);
  assert.equal(lastChallengeRound(CHALLENGE_DEFAULT, players, BAY_TERM, ["CP knockout, bås 1", "CP knockout runde 2, bås 1", "Noe annet"]), 2);
});
