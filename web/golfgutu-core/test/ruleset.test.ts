// RulesetTests.swift, RulesetTemplateTests.swift og DayTermTests.swift. Tall: Fixtures/regelsett*.json.

import assert from "node:assert/strict";
import { test } from "node:test";
import { dayCount, dayMany, dayOne, dayPossessive, dayThe, dayTheMany, dayTitle, dayToday, capitalized } from "../src/dayterm.ts";
import { ALL_FORMS, formById } from "../src/forms.ts";
import { rulesetSetup, rulesetSuggestions, setupIsOK } from "../src/formsetup.ts";
import { effectiveHandicap, teamHandicap } from "../src/handicap.ts";
import { stableStringify } from "../src/jsmath.ts";
import { makePlayer, makeRound } from "../src/models.ts";
import {
  allowanceFor,
  competitionRulesOf,
  decodeRuleset,
  encodeRuleset,
  GOLFGUTU,
  golfgutuRules,
  roundTablePoints,
  rulesetDay,
  rulesetEquals,
  standardCompetitionRules,
  teamHandicapRule,
} from "../src/ruleset.ts";
import { holePoints } from "../src/scoring.ts";
import {
  changedFields,
  closestTemplate,
  matchingTemplate,
  RULESET_TEMPLATES,
  stablefordSeriesLeagueRules,
  templateDifferences,
  templateLeagueRules,
  templateRules,
  templateSummary,
  templateTitle,
} from "../src/template.ts";
import { pointsForEmptyHole } from "../src/truncation.ts";
import { validateCompetitionRules, validateRuleset } from "../src/validation.ts";
import { fixture, fixtureText } from "./helpers.ts";

const roundtrip = (r: ReturnType<typeof golfgutuRules>) => decodeRuleset(JSON.parse(JSON.stringify(encodeRuleset(r))));

test("Golfgutu gjengir PWA-en", () => {
  const k = fixture("regelsett").konstanter;
  const g = GOLFGUTU;
  assert.equal(g.evenings, k.SESONG_RUNDER);
  assert.ok(k.TELLENDE_MATCHER === 0);
  assert.deepEqual(g.table.counting, { unit: "match", best: null });
  assert.deepEqual(g.table.stablefordCounting, { unit: "round", best: k.TELLENDE_RUNDER });
  assert.deepEqual(g.table.matchPoints, { win: k.POENG_SEIER, draw: k.POENG_DELT, loss: k.POENG_TAP });
  assert.deepEqual(g.handicap.seedingGroups.map((x) => x.number), k.SEEDING_GRUPPER.map((x: any) => x.nr));
  assert.deepEqual(g.handicap.seedingGroups.map((x) => x.handicap), k.SEEDING_GRUPPER.map((x: any) => x.hcp));
  assert.equal(g.formats.maxPerBay, k.SPILLERE_PER_BAAS);
  assert.equal(g.formats.defaultFormID, k.FORM_STANDARD);
  assert.deepEqual(g.sidePrizes.longestDrive, { enabled: true, points: k.SIDEPREMIE_POENG });
  assert.deepEqual(g.sidePrizes.closestToPin, { enabled: true, points: k.SIDEPREMIE_POENG });
  assert.equal(g.handicap.externalHandicap, k.HCP_EXTERN_NY_RUNDE);
  assert.equal(g.handicap.allowanceOverride, null);
  assert.deepEqual(g.leadCheckpoints, k.LEDELSE_SJEKKPUNKT);
  assert.deepEqual(g.scoring, { netParPoints: 2, minimumPoints: 0 });
  assert.deepEqual(g.table.trianglePoints, [1, 0.5, 0]);
  assert.equal(g.table.roundingStep, 0.5);
  assert.ok(g.sidePrizes.splitTies);
  assert.equal(g.formats.matchStrokes, "lowestFromScratch");
  assert.deepEqual(g.formats.allowedFormIDs, ALL_FORMS.map((f) => f.id));
  assert.deepEqual(teamHandicapRule(g, "scramble-4"), { method: "weighted", weights: [0.25, 0.2, 0.15, 0.1] });
  for (const f of ALL_FORMS) if (f.teamSize === 2) assert.deepEqual(teamHandicapRule(g, f.id), { method: "average" });
  assert.deepEqual(teamHandicapRule(g, "fourball-4"), { method: "lowest" });
});

test("andel for ny runde", () => {
  const andeler = fixture("regelsett").andelForNyRunde;
  assert.equal(andeler.length, ALL_FORMS.length);
  for (const a of andeler) assert.equal(allowanceFor(GOLFGUTU, formById(a.formId)), a.andel, a.formId);
  const fast = golfgutuRules();
  fast.handicap.allowanceOverride = 0.85;
  assert.equal(allowanceFor(fast, formById("stableford")), 0.85);
});

test("malen som JSON", () => {
  assert.ok(rulesetEquals(decodeRuleset(fixture("regelsett-golfgutu")), GOLFGUTU));
  assert.ok(rulesetEquals(roundtrip(golfgutuRules()), GOLFGUTU));
  assert.equal(encodeRuleset(GOLFGUTU).version, 2);
});

test("versjon 1 leses fortsatt", () => {
  const v1 = decodeRuleset(fixture("regelsett-golfgutu-v1"));
  assert.ok(rulesetEquals(v1, GOLFGUTU));
  assert.ok(rulesetEquals(decodeRuleset({ version: 1 }), GOLFGUTU));
  const annet = decodeRuleset({
    countingEvenings: 3, stablefordCountingEvenings: null, maxPerBay: 3,
    matchPoints: { win: 3, draw: 1, loss: 0 }, sidePrizes: { enabled: false, points: 2 },
  });
  assert.deepEqual(annet.table.counting, { unit: "match", best: 3 });
  assert.deepEqual(annet.table.stablefordCounting, { unit: "round", best: null });
  assert.equal(annet.formats.maxPerBay, 3);
  assert.deepEqual(annet.table.matchPoints, { win: 3, draw: 1, loss: 0 });
  assert.deepEqual(annet.sidePrizes.longestDrive, { enabled: false, points: 2 });
  assert.deepEqual(annet.sidePrizes.closestToPin, { enabled: false, points: 2 });
  const delvis = decodeRuleset({ version: 2, evenings: 5, table: { roundingStep: null } });
  assert.equal(delvis.evenings, 5);
  assert.equal(delvis.table.roundingStep, null);
  assert.deepEqual(delvis.table.matchPoints, GOLFGUTU.table.matchPoints);
  assert.deepEqual(delvis.handicap, GOLFGUTU.handicap);
  assert.deepEqual(delvis.leadCheckpoints, GOLFGUTU.leadCheckpoints);
  assert.deepEqual(v1.leadCheckpoints, [3, 6, 9, 12, 15, 18]);
});

test("ledelsens sjekkpunkter", () => {
  const egne = decodeRuleset({ version: 2, leadCheckpoints: [9, 18] });
  assert.deepEqual(egne.leadCheckpoints, [9, 18]);
  assert.equal(validateRuleset(egne).length, 0);
  assert.deepEqual(decodeRuleset({ version: 2, leadCheckpoints: [] }).leadCheckpoints, []);
  assert.deepEqual(roundtrip(egne).leadCheckpoints, [9, 18]);
});

test("regelverdier fra regelsettet", () => {
  const r = golfgutuRules();
  assert.equal(holePoints(4, 5, 0, 1, 18, r), 1);
  r.scoring.netParPoints = 3;
  assert.equal(holePoints(4, 5, 0, 1, 18, r), 2);
  r.scoring.netParPoints = 2;
  assert.equal(holePoints(4, 9, 0, 1, 18, r), 0);
  r.scoring.minimumPoints = -1;
  assert.equal(holePoints(4, 9, 0, 1, 18, r), -1);
  const avkortet = makeRound({ avkortRegel: "nettopar" });
  assert.equal(pointsForEmptyHole(avkortet), 2);
  r.scoring.netParPoints = 3;
  assert.equal(pointsForEmptyHole(avkortet, r), 3);

  const a = makePlayer("a", "", 12), b = makePlayer("b", "", 6);
  const lag = makeRound({ gameType: "scramble-2", holeCount: 18, hcpAllowance: 1 });
  assert.equal(teamHandicap(lag, [a, b]), 9);
  const laveste = golfgutuRules();
  laveste.handicap.teamHandicap["scramble-2"] = { method: "lowest" };
  assert.equal(teamHandicap(lag, [a, b], laveste), 6);
  laveste.handicap.teamHandicap["scramble-2"] = { method: "weighted", weights: [0.5, 0.25] };
  assert.equal(teamHandicap(lag, [a, b], laveste), 6);

  const andel = golfgutuRules();
  andel.handicap.formAllowances.stableford = 0.9;
  assert.equal(allowanceFor(andel, formById("stableford")), 0.9);
  delete andel.handicap.formAllowances.match;
  assert.equal(allowanceFor(andel, formById("match")), 1);

  const tabell = golfgutuRules();
  assert.equal(roundTablePoints(tabell, 1.3), 1.5);
  tabell.table.roundingStep = 1;
  assert.equal(roundTablePoints(tabell, 1.3), 1);
  tabell.table.roundingStep = null;
  assert.equal(roundTablePoints(tabell, 1.3), 1.3);

  const former = golfgutuRules();
  former.formats.allowedFormIDs = ["stableford", "match"];
  assert.deepEqual(rulesetSuggestions(former, 8).map((s) => s.id), ["stableford", "match"]);
});

test("regelsettet styrer funksjonene", () => {
  const b = makePlayer("b", "", 18.4, 2);
  const r = makeRound({ gameType: "stableford", holeCount: 18, course: { id: null, name: null, par: 72, courseRating: 74.1, slopeRating: 136, holes: null }, hcpAllowance: 0.95 });
  assert.equal(effectiveHandicap(b, r, [b], GOLFGUTU), 5);
  const annet = golfgutuRules();
  annet.handicap.seedingGroups = [{ number: 2, handicap: 7, name: "Gruppe 2" }];
  assert.equal(effectiveHandicap(b, r, [b], annet), 7);
  annet.handicap.seedingGroups = [];
  assert.equal(effectiveHandicap(b, r, [b], annet), 23);
  assert.ok(setupIsOK(rulesetSetup(GOLFGUTU, "scramble-4", 16)));
  const smaa = golfgutuRules();
  smaa.formats.maxPerBay = 3;
  assert.ok(!setupIsOK(rulesetSetup(smaa, "scramble-4", 16)));
  assert.ok(!rulesetSuggestions(smaa, 16).some((s) => s.id === "scramble-4"));
});

test("Golfgutu er gyldig", () => {
  assert.deepEqual(validateRuleset(GOLFGUTU), []);
});

test("annet oppsett fra JSON", () => {
  const r = decodeRuleset(fixture("regelsett-eksempel"));
  assert.deepEqual(validateRuleset(r), []);
  assert.equal(r.evenings, 5);
  assert.deepEqual(r.table.counting, { unit: "evening", best: 3 });
  assert.deepEqual(r.table.matchPoints, { win: 3, draw: 1, loss: 0 });
  assert.ok(!r.sidePrizes.longestDrive.enabled && !r.sidePrizes.closestToPin.enabled);
  assert.equal(r.table.roundingStep, null);
  assert.deepEqual(r.handicap.seedingGroups, []);
  assert.deepEqual(r.handicap.teamHandicap, GOLFGUTU.handicap.teamHandicap);
  assert.equal(allowanceFor(r, formById("stableford")), 1);
  assert.deepEqual(rulesetSuggestions(r, 8).map((s) => s.id), ["stableford", "match", "fourball", "scramble-2"]);
  assert.ok(rulesetEquals(roundtrip(r), r));
});

test("ugyldige regelsett", () => {
  const felt = (endre: (r: ReturnType<typeof golfgutuRules>) => void) => {
    const r = golfgutuRules();
    endre(r);
    return validateRuleset(r).map((i) => i.field);
  };
  assert.deepEqual(felt((r) => { r.evenings = 0; }), ["evenings"]);
  assert.deepEqual(felt((r) => { r.evenings = 5; r.table.counting = { unit: "evening", best: 6 }; }), ["table.counting.best"]);
  assert.deepEqual(felt((r) => { r.evenings = 5; r.table.counting = { unit: "evening", best: 5 }; }), []);
  assert.deepEqual(felt((r) => { r.table.counting = { unit: "match", best: 0 }; }), ["table.counting.best"]);
  assert.deepEqual(felt((r) => { r.table.counting = { unit: "match", best: 12 }; }), []);
  assert.deepEqual(felt((r) => { r.table.stablefordCounting = { unit: "evening", best: 8 }; }), ["table.stablefordCounting.best"]);
  assert.deepEqual(felt((r) => { r.table.stablefordCounting = { unit: "match", best: 5 }; }), ["table.stablefordCounting.unit"]);
  assert.deepEqual(felt((r) => { r.table.matchPoints.loss = -1; }), ["table.matchPoints.loss"]);
  assert.deepEqual(felt((r) => { r.table.matchPoints = { win: 1, draw: 2, loss: 0 }; }), ["table.matchPoints"]);
  assert.deepEqual(felt((r) => { r.sidePrizes.closestToPin.points = -1; }), ["sidePrizes.closestToPin.points"]);
  assert.deepEqual(felt((r) => { r.scoring.netParPoints = -2; r.scoring.minimumPoints = -5; }), ["scoring.netParPoints"]);
  assert.deepEqual(felt((r) => { r.scoring.minimumPoints = 3; }), ["scoring.minimumPoints"]);
  assert.deepEqual(felt((r) => { r.table.trianglePoints = [1, 0]; }), ["table.trianglePoints"]);
  assert.deepEqual(felt((r) => { r.table.trianglePoints = [1, 0.5, -1]; }), ["table.trianglePoints"]);
  assert.deepEqual(felt((r) => { r.table.trianglePoints = [0, 0.5, 1]; }), ["table.trianglePoints"]);
  assert.deepEqual(felt((r) => { r.table.roundingStep = 0; }), ["table.roundingStep"]);
  assert.deepEqual(felt((r) => { r.table.roundingStep = null; }), []);
  assert.deepEqual(felt((r) => { r.table.tiebreaks = ["stableford", "stableford"]; }), ["table.tiebreaks"]);
  assert.deepEqual(felt((r) => { r.handicap.allowanceOverride = 1.2; }), ["handicap.allowanceOverride"]);
  assert.deepEqual(felt((r) => { r.handicap.formAllowances.match = -0.1; }), ["handicap.formAllowances.match"]);
  assert.deepEqual(felt((r) => { r.handicap.seedingGroups.push({ number: 1, handicap: 3, name: "X" }); }), ["handicap.seedingGroups"]);
  assert.deepEqual(felt((r) => { r.handicap.teamHandicap["scramble-4"] = { method: "weighted" }; }), ["handicap.teamHandicap.scramble-4"]);
  assert.deepEqual(felt((r) => { r.formats.maxPerBay = 0; }), ["formats.maxPerBay"]);
  assert.deepEqual(felt((r) => { r.formats.allowedFormIDs = []; }), ["formats.allowedFormIDs"]);
  assert.deepEqual(felt((r) => { r.formats.allowedFormIDs.push("golfball-bingo"); }), ["formats.allowedFormIDs"]);
  assert.deepEqual(felt((r) => { r.formats.allowedFormIDs = ["match"]; }), ["formats.defaultFormID"]);
  assert.deepEqual(felt((r) => { r.leadCheckpoints = [0, 9]; }), ["leadCheckpoints"]);
  assert.deepEqual(felt((r) => { r.leadCheckpoints = [9, 19]; }), ["leadCheckpoints"]);
  assert.deepEqual(felt((r) => { r.leadCheckpoints = [9, 6]; }), ["leadCheckpoints"]);
  assert.deepEqual(felt((r) => { r.leadCheckpoints = [9, 9]; }), ["leadCheckpoints"]);
  assert.deepEqual(felt((r) => { r.leadCheckpoints = [1, 18]; }), []);
  assert.deepEqual(felt((r) => { r.leadCheckpoints = []; }), []);

  let r = golfgutuRules();
  r.evenings = 5;
  r.table.counting = { unit: "evening", best: 6 };
  assert.equal(validateRuleset(r)[0].message, "Tabellen: beste 6 kvelder er flere enn de 5 kveldene i turneringen.");
  r = golfgutuRules();
  r.formats.allowedFormIDs = [];
  assert.equal(validateRuleset(r)[0].message, "Minst én konkurranseform må være tillatt.");
});

// MARK: Oppsettene (RulesetTemplateTests.swift)

test("oppsettene er gyldige", () => {
  for (const t of RULESET_TEMPLATES) {
    assert.deepEqual(validateRuleset(templateRules(t)), [], t);
    assert.deepEqual(validateCompetitionRules(competitionRulesOf(templateRules(t))), [], t);
    assert.ok(templateTitle(t) !== "" && templateSummary(t) !== "");
  }
});

test("matchspill-serien er Golfgutu; cup og morro er konkurransemalen", () => {
  assert.ok(rulesetEquals(templateRules("matchSeries"), GOLFGUTU));
  assert.equal(GOLFGUTU.table.pointsSource, "matches");
  const expected = golfgutuRules();
  expected.competition = standardCompetitionRules();
  assert.ok(rulesetEquals(templateRules("cup"), expected));
  assert.ok(rulesetEquals(templateRules("fun"), expected));
});

test("stableford-serien", () => {
  const r = templateRules("stablefordSeries");
  assert.equal(r.table.pointsSource, "stableford");
  assert.deepEqual(r.table.counting, { unit: "evening", best: 5 });
  assert.deepEqual(r.table.stablefordCounting, { unit: "evening", best: 5 });
  assert.equal(r.evenings, GOLFGUTU.evenings);
  assert.ok(!r.sidePrizes.longestDrive.enabled && !r.sidePrizes.closestToPin.enabled);
  assert.deepEqual(r.handicap.seedingGroups, []);
  assert.equal(allowanceFor(r, formById("stableford")), 0.95);
  assert.equal(r.competition, null);
  assert.deepEqual(templateDifferences("stablefordSeries", GOLFGUTU), [
    "handicap.seedingGroups", "sidePrizes.closestToPin.enabled", "sidePrizes.longestDrive.enabled",
    "table.counting.best", "table.counting.unit", "table.pointsSource",
    "table.stablefordCounting.unit", "table.tiebreaks",
  ]);
});

test("gjenkjenning", () => {
  assert.equal(matchingTemplate(GOLFGUTU), "matchSeries");
  assert.equal(matchingTemplate(templateRules("stablefordSeries")), "stablefordSeries");
  assert.equal(matchingTemplate(templateRules("fun"), ["fun"]), "fun");
  assert.equal(matchingTemplate(templateRules("fun"), ["cup"]), "cup");
  assert.equal(matchingTemplate(GOLFGUTU, ["stablefordSeries"]), null);
  const tilpasset = templateRules("stablefordSeries");
  tilpasset.evenings = 10;
  tilpasset.table.counting.best = 7;
  assert.equal(matchingTemplate(tilpasset), null);
  assert.deepEqual(templateDifferences("stablefordSeries", tilpasset), ["evenings", "table.counting.best"]);
  assert.equal(closestTemplate(tilpasset, ["stablefordSeries", "matchSeries"]), "stablefordSeries");
  const golf = golfgutuRules();
  golf.table.matchPoints.win = 2;
  assert.deepEqual(templateDifferences("matchSeries", golf), ["table.matchPoints.win"]);
  assert.equal(closestTemplate(golf, ["stablefordSeries", "matchSeries"]), "matchSeries");
  assert.equal(closestTemplate(golf, []), null);
});

test("endringer i små felt", () => {
  const r = golfgutuRules();
  assert.deepEqual(changedFields(r, GOLFGUTU), []);
  r.handicap.formAllowances.stableford = 1;
  r.competition = standardCompetitionRules();
  r.tips.defaultStakePoints += 1;
  assert.deepEqual(changedFields(r, GOLFGUTU), ["competition", "handicap.formAllowances.stableford", "tips.defaultStakePoints"]);
});

test("Golfgutu-JSON er uendret, byte for byte", () => {
  const encoded = encodeRuleset(GOLFGUTU);
  const fx = fixture("regelsett-golfgutu");
  for (const key of Object.keys(fx)) assert.deepEqual(encoded[key], fx[key], key);
  assert.equal((encoded.table as any).pointsSource, undefined);
  // regelsett-golfgutu-hel.json er skrevet av Swifts JSONEncoder med `.sortedKeys`.
  assert.equal(stableStringify(encoded), fixtureText("regelsett-golfgutu-hel"));
  assert.ok(rulesetEquals(decodeRuleset(fixture("regelsett-golfgutu-hel")), GOLFGUTU));
  assert.equal(stableStringify(encodeRuleset(roundtrip(golfgutuRules()))), stableStringify(encoded));
});

test("pointsSource rundtur", () => {
  for (const t of RULESET_TEMPLATES) assert.ok(rulesetEquals(roundtrip(templateRules(t)), templateRules(t)), t);
  assert.equal((encodeRuleset(templateRules("stablefordSeries")).table as any).pointsSource, "stableford");
  assert.equal(decodeRuleset({ version: 2, table: { tiebreaks: [] } }).table.pointsSource, "matches");
  assert.equal(decodeRuleset(fixture("regelsett-golfgutu-v1")).table.pointsSource, "matches");
});

test("validering av pointsSource", () => {
  const r = templateRules("stablefordSeries");
  r.table.counting = { unit: "match", best: null };
  assert.deepEqual(validateRuleset(r).map((i) => i.field), ["table.counting.unit"]);
  r.table.pointsSource = "matches";
  assert.deepEqual(validateRuleset(r), []);
});

test("privat stableford-serie kjennes igjen som liga", () => {
  const league = templateLeagueRules("stablefordSeries");
  assert.deepEqual(league.competition?.league, stablefordSeriesLeagueRules());
  assert.equal(stablefordSeriesLeagueRules().scoring, "stableford");
  assert.equal(stablefordSeriesLeagueRules().participationPoints, 0);
  assert.equal(stablefordSeriesLeagueRules().bestRounds, 5);
  assert.deepEqual(validateRuleset(league), []);
  assert.equal(matchingTemplate(league, ["stablefordSeries", "matchSeries"], true), "stablefordSeries");
  assert.equal(matchingTemplate(league, ["stablefordSeries", "matchSeries"]), null);
  assert.deepEqual(templateDifferences("stablefordSeries", league, true), []);
  assert.equal(closestTemplate(league, ["matchSeries", "stablefordSeries"], true), "stablefordSeries");
  const tuned = templateLeagueRules("stablefordSeries");
  tuned.competition!.league.bestRounds = 3;
  assert.equal(matchingTemplate(tuned, ["stablefordSeries"], true), null);
  assert.deepEqual(templateDifferences("stablefordSeries", tuned, true), ["competition.league.bestRounds"]);
  assert.ok(rulesetEquals(templateLeagueRules("matchSeries"), templateRules("matchSeries")));
});

// MARK: Ordet for dagen (DayTermTests.swift)

test("ordformene", () => {
  assert.deepEqual([dayOne("evening"), dayThe("evening"), dayMany("evening"), dayTheMany("evening")], ["kveld", "kvelden", "kvelder", "kveldene"]);
  assert.deepEqual([dayOne("playingDay"), dayThe("playingDay"), dayMany("playingDay"), dayTheMany("playingDay")], ["spilledag", "spilledagen", "spilledager", "spilledagene"]);
  assert.ok(dayToday("evening") === "I kveld" && dayToday("playingDay") === "I dag");
  assert.equal(dayTitle("playingDay"), "Spilledag");
  assert.equal(capitalized("kvelden"), "Kvelden");
  assert.ok(dayPossessive("playingDay") === "spilledagens" && dayPossessive("evening") === "kveldens");
  assert.ok(dayCount("evening", 1) === "1 kveld" && dayCount("playingDay", 3) === "3 spilledager");
});

test("Golfgutu sier kveld; ordet er ikke en regel", () => {
  assert.equal(GOLFGUTU.dayTerm, null);
  assert.equal(rulesetDay(GOLFGUTU), "evening");
  assert.ok(!JSON.stringify(encodeRuleset(GOLFGUTU)).includes("dayTerm"));
  const rules = templateRules("stablefordSeries");
  rules.dayTerm = "playingDay";
  const back = roundtrip(rules);
  assert.ok(rulesetEquals(back, rules) && rulesetDay(back) === "playingDay");
  const g = golfgutuRules();
  g.dayTerm = "playingDay";
  assert.equal(matchingTemplate(g), "matchSeries");
  assert.deepEqual(templateDifferences("matchSeries", g), []);
  assert.equal(closestTemplate(g), "matchSeries");
});

test("konkurransereglene i regelsettet", () => {
  assert.equal(GOLFGUTU.competition, null);
  assert.deepEqual(competitionRulesOf(GOLFGUTU), standardCompetitionRules());
  assert.equal(encodeRuleset(GOLFGUTU).competition, undefined);
  const r = golfgutuRules();
  r.competition = {
    league: { scoring: "stableford", placementPoints: [5, 3, 1], participationPoints: 2, bestRounds: null, tiebreaks: ["stableford"] },
    fun: standardCompetitionRules().fun,
    cup: { seeding: "ranking", tie: "countback" },
  };
  assert.ok(rulesetEquals(roundtrip(r), r));
  const delvis = decodeRuleset({ version: 2, competition: { league: { bestRounds: 4 }, cup: { tie: "higherSeed" } } });
  assert.equal(competitionRulesOf(delvis).league.bestRounds, 4);
  assert.deepEqual(competitionRulesOf(delvis).league.placementPoints, standardCompetitionRules().league.placementPoints);
  assert.deepEqual(competitionRulesOf(delvis).fun, standardCompetitionRules().fun);
  assert.deepEqual(competitionRulesOf(delvis).cup, { seeding: "random", tie: "higherSeed" });
  assert.equal(competitionRulesOf(decodeRuleset({ version: 2, competition: { fun: { bestRounds: null } } })).fun.bestRounds, null);
  assert.equal(decodeRuleset({ version: 1 }).competition, null);
});

test("validering av konkurransereglene", () => {
  assert.deepEqual(validateCompetitionRules(standardCompetitionRules()), []);
  const c = standardCompetitionRules();
  c.league.placementPoints = [5, 8];
  c.league.bestRounds = 0;
  c.fun.participationPoints = -1;
  c.fun.tiebreaks = ["wins", "wins"];
  assert.deepEqual(new Set(validateCompetitionRules(c).map((i) => i.field)), new Set([
    "competition.league.placementPoints", "competition.league.bestRounds",
    "competition.fun.participationPoints", "competition.fun.tiebreaks",
  ]));
});
