// App-mappingen mot appens egen Swift-kode: test/fixtures/tavla.json (svaret fra tavla_data og tre
// sesongrader) og fasiten test/fixtures/tavla.forventet.json, regnet av TavlaStandings, RoundsGrid,
// CompetitionScope og LeagueStandings i appen (tools/swift-tavla/kjor.sh).

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { CompetitionScope, CupStandings, LeagueStandings, PersonDirectory, type CompetitionRow, type Entrant } from "../src/app/competition.ts";
import { decodeSeasonRow, decodeTavlaData } from "../src/app/rows.ts";
import { shortDate, standingsFromTavlaData, tavlaInput, TavlaStandings, tavlaToJSON, toParText, type RoundsGrid } from "../src/app/tavla.ts";
import { decodeRuleset } from "../src/ruleset.ts";
import { templateRules } from "../src/template.ts";

const read = (name: string) => JSON.parse(readFileSync(new URL(`fixtures/${name}`, import.meta.url), "utf8"));
const fx = read("tavla.json");
const want = read("tavla.forventet.json");
const data = decodeTavlaData(fx.tavlaData);

function grid(g: RoundsGrid) {
  return {
    columns: g.columns,
    rows: g.rows.map((r) => ({ ...r })),
    bestPoints: g.bestPoints,
    bestStrokes: g.bestStrokes,
  };
}

function tavla(t: TavlaStandings) {
  const j = tavlaToJSON(t);
  return {
    seasonName: j.seasonName,
    status: j.status,
    countsStableford: j.countsStableford,
    hasResults: j.hasResults,
    eveningsPlayed: j.eveningsPlayed,
    eveningsTotal: j.eveningsTotal,
    roundColumns: j.roundColumns,
    rows: j.rows,
    rounds: grid(j.rounds),
    roundTitles: t.snapshots.map((_, i) => t.roundTitle(i)),
    birdies: Object.fromEntries(t.rows.map((r) => [r.memberID, t.birdies(r.memberID)])),
    longestDrive: Object.fromEntries(t.rows.map((r) => [r.memberID, t.longestDrive(r.memberID)])),
  };
}

function league(l: LeagueStandings) {
  return {
    rulesSummary: l.rulesSummary,
    hasResults: l.hasResults,
    roundCount: l.roundCount,
    roundTitles: Object.fromEntries(l.roundTitles),
    rows: l.rows.map((r) => ({
      entrant: r.entrant.id, name: r.name, place: r.place, total: r.total, played: r.played, wins: r.wins,
      bestRound: r.bestRound, stableford: r.stableford, isMe: r.isMe, placeText: l.placeText(r),
      totalText: LeagueStandings.points(r.total), detail: l.detail(r), results: r.results,
    })),
    rounds: grid(l.roundGrid()),
  };
}

fx.sesonger.forEach((s: any, i: number) => {
  test(`Tavla som appen: ${s.name}`, () => {
    const t = new TavlaStandings(tavlaInput(data, decodeSeasonRow(s)), fx.me);
    const got = tavla(t);
    const w = want.tavla[i];
    // Felt for felt først, så feilen er lett å lese.
    for (const key of Object.keys(w)) assert.deepEqual(got[key as keyof typeof got], w[key], key);
    assert.deepEqual(got, w);
  });
});

test("standingsFromTavlaData gir det samme i ett kall", () => {
  const j = standingsFromTavlaData(fx.tavlaData, fx.sesonger[0], fx.me.toUpperCase());
  assert.deepEqual(j.rows, want.tavla[0].rows);
  assert.deepEqual(grid(j.rounds), want.tavla[0].rounds);
});

function competition(kind: "league" | "fun", clubID: string | null, entry: "club" | "open", rules: CompetitionRow["rules"]): CompetitionRow {
  return { id: "00000000-0000-0000-0000-000000009100", kind, name: "Konkurranse", clubID, ownerID: null, seasonID: null, status: "active", entry, rules, startsOn: null, endsOn: null, isMain: false };
}

test("liga og morro som appen", () => {
  const candidates = tavlaInput(data, decodeSeasonRow(fx.sesonger[0])).rounds;
  const directory = new PersonDirectory(data.members);
  const club = data.members[0].clubID;
  const comps = [
    competition("league", club, "club", decodeRuleset({ version: 2, competition: { league: { bestRounds: 3 } } })),
    competition("fun", null, "open", templateRules("fun")),
  ];
  comps.forEach((c, i) => {
    const links = data.rounds.map((r) => ({ competitionID: c.id, roundID: r.id }));
    const input = new CompetitionScope(c, links).input(candidates, directory);
    const me: Entrant[] = input.entrants.filter((e) => e.id === fx.me);
    const got = league(new LeagueStandings(input, me));
    const w = want.konkurranser[i];
    assert.equal(w.kind, c.kind);
    for (const key of Object.keys(w.standings)) assert.deepEqual(got[key as keyof typeof got], w.standings[key], `${c.kind}: ${key}`);
  });
});

test("cup som appen", () => {
  const pid = (i: number) => `00000000-0000-0000-0000-${String(500 + i).padStart(12, "0")}`;
  const cupID = "00000000-0000-0000-0000-000000009200";
  const entrants = [0, 1, 2, 3, 4, 5].map((i) => ({ id: pid(i), competitionID: cupID, memberID: data.members[i].id, profileID: null, status: "active" as const }));
  const names = new Map([0, 1, 2, 3, 4, 5].map((i) => [pid(i), data.members[i].displayName]));
  const handicaps = new Map<string, number>();
  for (const i of [0, 1, 2, 3, 4, 5]) if (data.members[i].handicapIndex !== null) handicaps.set(pid(i), data.members[i].handicapIndex!);
  const pairings = CupStandings.pairings(entrants, names, handicaps, new Map(), { seeding: "handicap", tie: "countback" }, 0);
  const rows = pairings.map((p, i) => ({
    id: `m${i}`, competitionID: cupID, roundNo: 1, slot: p.slot, playerA: p.a, playerB: p.b,
    winner: p.b === null ? p.a : null, walkover: false, result: null as string | null, roundID: null,
  }));
  const first = rows.findIndex((r) => r.playerB !== null);
  rows[first].winner = rows[first].playerB;
  rows[first].result = "3&2";
  const last = rows.map((r) => r.playerB !== null).lastIndexOf(true);
  rows[last].winner = rows[last].playerA;
  rows[last].walkover = true;
  const cup = new CupStandings(rows, names, new Set([pid(5)]));
  const w = want.cup;
  assert.deepEqual(pairings, w.pairings);
  assert.deepEqual(cup.rounds, w.rounds);
  assert.deepEqual(cup.roundTitles, w.roundTitles);
  assert.deepEqual(cup.champion, w.champion);
  assert.deepEqual(cup.myNext, w.myNext);
});

test("små tekster", () => {
  assert.equal(toParText(0), "E");
  assert.equal(toParText(3), "+3");
  assert.equal(toParText(-2), "−2");
  assert.equal(shortDate("2026-10-08"), "8.10");
  assert.equal(shortDate("tull"), "tull");
  assert.equal(LeagueStandings.points(11), "11");
  assert.equal(LeagueStandings.points(6.5), "6,5");
  assert.equal(LeagueStandings.points(19 / 3), "6,33");
});
