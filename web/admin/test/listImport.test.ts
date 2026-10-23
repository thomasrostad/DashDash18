// «Lim inn liste» i Troppen (#145) og deltakere (sql/060). Samme tilfeller som appens TroppImportTests og
// DeltakerImportTests, og handicapen mot den felles fixturen DashDash18Tests/DegFixtures.json.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import {
  countText, handicapIndex, handicapText, lineColumns, parseParticipantList, parseRosterList, participantEntries,
  participantsAddedText, problemText, rosterRows, splitLine, validLines,
} from "../src/listImport.ts";

const deg = JSON.parse(readFileSync(new URL("../../../DashDash18Tests/DegFixtures.json", import.meta.url), "utf8"));

test("handicap som i appen (DegFixtures.json)", () => {
  for (const g of deg.handicap.gyldige) assert.deepEqual(handicapIndex(g.tekst), { value: g.indeks }, g.tekst);
  for (const u of deg.handicap.ugyldige) assert.ok("error" in handicapIndex(u), u);
  for (const v of deg.handicap.visning) assert.equal(handicapText(v.indeks), v.tekst);
  assert.deepEqual(handicapIndex("-3"), { error: "Plusshandicap skrives med «+», f.eks. +2,3." });
});

test("navn og handicap fra én linje (TroppImport.split)", () => {
  const cases: [string, string, string][] = [
    ["Kari Nordmann", "Kari Nordmann", ""],
    ["Kari Nordmann 18,4", "Kari Nordmann", "18,4"],
    ["Kari Nordmann, 18.4", "Kari Nordmann", "18.4"],
    ["Kari Nordmann;+2,3", "Kari Nordmann", "+2,3"],
    ["Kari Nordmann\t\t12", "Kari Nordmann", "12"],
    ["Hole 19", "Hole", "19"],
    ["Per Olav Ås", "Per Olav Ås", ""],
    ["Kari Nordmann;18,4;12-3456", "Kari Nordmann", "18,4"],
  ];
  for (const [line, name, handicap] of cases) assert.deepEqual(splitLine(line), { name, handicap }, line);
});

test("navn, handicap og NGF-nummer (TroppImport.columns)", () => {
  const cases: [string, string, string, string][] = [
    ["Kari Nordmann", "Kari Nordmann", "", ""],
    ["Kari Nordmann 18,4", "Kari Nordmann", "18,4", ""],
    ["Kari Nordmann;18,4;12-3456", "Kari Nordmann", "18,4", "12-3456"],
    ["Kari Nordmann\t18,4\t1234567", "Kari Nordmann", "18,4", "1234567"],
    ["Kari Nordmann;;12-3456", "Kari Nordmann", "", "12-3456"],
    ["Kari Nordmann;12-3456", "Kari Nordmann", "", "12-3456"],
    ["Kari Nordmann\t\t12", "Kari Nordmann", "12", ""],
    ["Kari Nordmann;-2", "Kari Nordmann", "-2", ""],
  ];
  for (const [line, name, handicap, ngf] of cases) assert.deepEqual(lineColumns(line), { name, handicap, ngf }, line);
});

test("Troppen: feil per linje, finnes fra før og dobbelt", () => {
  // «Borte» er arkivert, så navnet er ledig; forelderen sender bare navnene som er tatt.
  const lines = parseRosterList("Kari Nordmann 18,4\n\nanne\nBorte 10\nKari nordmann\nOla 70\nPer -2", ["Anne"]);
  assert.deepEqual(lines.map((l) => l.name), ["Kari Nordmann", "anne", "Borte", "Kari nordmann", "Ola", "Per"]);
  assert.deepEqual(lines.map((l) => problemText(l)), [null, "Finnes i troppen fra før", null, "Står allerede i lista",
    "Handicap må være mellom +10 og 54.", "Plusshandicap skrives med «+», f.eks. +2,3."]);
  assert.equal(lines[0].handicapIndex, 18.4);
  assert.deepEqual(validLines(lines).map((l) => l.name), ["Kari Nordmann", "Borte"]);
  assert.equal(countText(lines), "2 av 6 legges til");
  assert.deepEqual(rosterRows("k1", lines), [
    { club_id: "k1", display_name: "Kari Nordmann", handicap_index: 18.4 },
    { club_id: "k1", display_name: "Borte", handicap_index: 10 },
  ]);
});

test("høyst 200 i Troppen og 300 deltakere", () => {
  const text = (n: number) => Array.from({ length: n }, (_, i) => `Spiller ${i + 1}`).join("\n");
  assert.equal(parseRosterList(text(250), []).length, 200);
  assert.equal(parseParticipantList(text(350), []).length, 300);
});

test("deltakere: dobbelt, påmeldte og ulike NGF-nummer", () => {
  const text = "Kari Nordmann;18,4;12-3456\n\nOla Hansen 22\nkari nordmann\nKari Nordmann;;99-9999\nPer Påmeldt\nOla 70";
  const lines = parseParticipantList(text, ["Per påmeldt"]);
  assert.deepEqual(lines.map((l) => l.name), ["Kari Nordmann", "Ola Hansen", "kari nordmann", "Kari Nordmann", "Per Påmeldt", "Ola"]);
  assert.deepEqual(lines.map((l) => l.problem?.kind ?? null), [null, null, "repeated", null, "exists", "invalid"]);
  assert.equal(lines[0].ngfNumber, "12-3456");
  assert.equal(lines[1].ngfNumber, null);
  assert.equal(validLines(lines).length, 3);
  assert.equal(problemText(lines[2], true), "Står allerede i lista");
  assert.equal(problemText(lines[4], true), "Er påmeldt fra før");
  // Samme navn som et medlem er greit: deltakere kan hete det samme.
  assert.equal(parseParticipantList("Anne", []).at(0)?.problem, null);
});

test("deltakerne sendes som i appen, uten tomme verdier", () => {
  const lines = parseParticipantList("Kari Nordmann;+2,3;12-3456\nOla", []);
  assert.deepEqual(participantEntries(lines), [
    { display_name: "Kari Nordmann", handicap_index: -2.3, ngf_number: "12-3456" },
    { display_name: "Ola" },
  ]);
  assert.equal(participantsAddedText(0), "Ingen nye. Alle var påmeldt fra før.");
  assert.equal(participantsAddedText(12), "12 lagt til");
});
