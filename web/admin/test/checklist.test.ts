// Sjekklista i rundeoppsettet (src/rounds/checklist.ts).
import { test } from "node:test";
import assert from "node:assert/strict";
import { checklistCount, setupChecklist } from "../src/rounds/checklist.ts";
import { BAY_TERM, issueMessage } from "../src/rounds/logic.ts";

const summary = { bane: "Oslo Golfklubb · tee 63", start: "Hull 1 · 18 hull · 17:00", form: "Scramble (2-mann)", oppstilling: "8 spillere i 2 båser", sidepremier: "LD hull 9 · NP hull 8" };

test("alt i orden: sammendraget på hver linje", () => {
  const items = setupChecklist([], BAY_TERM, summary);
  assert.deepEqual(items.map((i) => [i.key, i.state, i.text]), [
    ["bane", "ok", "Oslo Golfklubb · tee 63"], ["start", "ok", "Hull 1 · 18 hull · 17:00"], ["form", "ok", "Scramble (2-mann)"],
    ["oppstilling", "ok", "8 spillere i 2 båser"], ["sidepremier", "ok", "LD hull 9 · NP hull 8"],
  ]);
  assert.deepEqual(checklistCount(items), { ready: 5, total: 5 });
});

test("hver sjekk havner i sin del, med samme tekst som «Før runden kan starte»", () => {
  const items = setupChecklist([{ kind: "noCourse" }, { kind: "bayWithoutMarker", bays: [2] }, { kind: "tooFewPlayers" }], BAY_TERM, summary);
  const bane = items.find((i) => i.key === "bane")!;
  assert.equal(bane.state, "bad");
  assert.equal(bane.text, issueMessage({ kind: "noCourse" }, BAY_TERM));
  const lineup = items.find((i) => i.key === "oppstilling")!;
  assert.equal(lineup.state, "bad");
  assert.ok(lineup.text.endsWith("(+1)"));
  assert.deepEqual(checklistCount(items), { ready: 3, total: 5 });
});

test("tavlas røde feil stopper, gule merknader varsler", () => {
  const red = setupChecklist([], BAY_TERM, summary, ["Ingen markør."]);
  assert.deepEqual(red.find((i) => i.key === "oppstilling"), { key: "oppstilling", title: "Oppstilling", state: "bad", text: "Ingen markør." });
  const yellow = setupChecklist([], BAY_TERM, summary, [], ["Lag 1 mangler én."]);
  assert.equal(yellow.find((i) => i.key === "oppstilling")!.state, "warn");
  assert.deepEqual(checklistCount(yellow), { ready: 5, total: 5 });
});
