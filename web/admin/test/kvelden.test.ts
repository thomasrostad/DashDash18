import { test } from "node:test";
import assert from "node:assert/strict";
import { feedOf, gapsOf, groupsOf, phaseOf, type KvPlayer, type KvScore } from "../src/kvelden/model.ts";

const P = (memberID: string, group: number): KvPlayer => ({ memberID, name: memberID.toUpperCase(), group, isMarker: false });
const t = (min: number) => new Date(Date.UTC(2026, 9, 28, 17, min)).toISOString();
const S = (memberID: string, holeIndex: number, min: number, scoreName: KvScore["scoreName"] = "par"): KvScore => ({ memberID, holeIndex, recordedAt: t(min), scoreName });
const players = [P("a", 1), P("b", 1), P("c", 2), P("d", 2)];

test("gruppene: hvor de står, og når de er inne", () => {
  const scores = [
    ...[0, 1, 2].flatMap((h) => [S("a", h, h * 10), S("b", h, h * 10)]),
    S("c", 0, 5), S("d", 0, 5),
  ];
  const g = groupsOf(players, scores, 3);
  assert.deepEqual(g.map((x) => [x.no, x.played, x.nextIndex, x.done]), [[1, 3, null, true], [2, 1, 1, false]]);
  assert.equal(g[0].lastAt, t(20));
});

test("gruppene: start på hull 10 (indeks 9) går videre og rundt", () => {
  const scores = [S("c", 9, 1), S("d", 9, 1), S("c", 10, 9), S("d", 10, 9)];
  const g = groupsOf(players, scores, 18).find((x) => x.no === 2)!;
  assert.equal(g.nextIndex, 11);
  const end = [16, 17].flatMap((h, i) => [S("c", h, 20 + i), S("d", h, 20 + i)]);
  assert.equal(groupsOf(players, [...scores, ...end], 18).find((x) => x.no === 2)!.nextIndex, 0, "etter 18 kommer 1");
});

test("gruppene: ingen score ennå står på første hull", () => {
  const g = groupsOf(players, [], 18);
  assert.deepEqual(g.map((x) => x.nextIndex), [0, 0]);
  assert.equal(phaseOf([], g), "for");
});

test("hull som mangler: bare når gruppa har gått videre", () => {
  const scores = [S("a", 0, 1), S("b", 0, 1), S("a", 1, 10), S("a", 2, 20), S("b", 2, 20), S("a", 3, 30)];
  const groups = groupsOf(players, scores, 18);
  // b mangler hull 2 (indeks 1). Hull 4 (indeks 3) er det gruppa står på, og teller ikke ennå.
  assert.deepEqual(gapsOf(players, scores, groups, 18), [{ memberID: "b", group: 1, holeIndex: 1 }]);
});

test("siste: birdie foran vanlig hull, inne når gruppa er ferdig, nyeste først", () => {
  const scores = [
    S("a", 0, 1), S("b", 0, 1, "birdie"),
    S("a", 1, 12, "eagle"), S("b", 1, 12, "birdie"),
    S("c", 0, 6), S("d", 0, 7),
  ];
  const groups = groupsOf(players, scores, 2);
  const feed = feedOf(players, scores, groups);
  assert.deepEqual(feed.map((f) => f.kind === "score" ? `${f.memberID} ${f.name} ${f.holeIndex}` : f.kind === "hole" ? `gruppe ${f.group} hull ${f.holeIndex}` : `gruppe ${f.group} inne`), [
    "gruppe 1 inne", "a eagle 1", "gruppe 2 hull 0", "b birdie 0",
  ]);
  assert.equal(phaseOf(scores, groups), "under");
});

test("fasen: etter når alle er inne", () => {
  const scores = ["a", "b", "c", "d"].flatMap((m) => [S(m, 0, 1), S(m, 1, 2)]);
  assert.equal(phaseOf(scores, groupsOf(players, scores, 2)), "etter");
});
