// «Tabeller» mot appens fasit: fixturene til golfgutu-core (tavla.json og tavla.forventet.json, regnet av
// appens egen Swift-kode) gjennom web-adminens sammenstilling, så tabellen på nettet er den samme som i appen.

import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { encodeRuleset, snapshotHasInward, snapshotScorecard, snapshotTotal, templateRules, type RoundsGrid, type RoundSnapshot } from "../../golfgutu-core/src/index.ts";
import { BOM, buildCsv, cellText, fileName, gridCsv, gridTotal, tableCsv } from "../src/standings/csv.ts";
import { competitionData, cupView, leagueView, seasonView, type CompetitionRaw } from "../src/standings/model.ts";

const read = (name: string) => JSON.parse(readFileSync(new URL(`../../golfgutu-core/test/fixtures/${name}`, import.meta.url), "utf8"));
const fx = read("tavla.json");
const want = read("tavla.forventet.json");
const td = fx.tavlaData;

const grid = (g: RoundsGrid) => ({ columns: g.columns, rows: g.rows.map((r) => ({ ...r })), bestPoints: g.bestPoints, bestStrokes: g.bestStrokes });
const shown = (rows: { placeText: string; name: string; totalText: string; detail: string; isMe: boolean }[]) =>
  rows.map((r) => ({ placeText: r.placeText, name: r.name, totalText: r.totalText, detail: r.detail, isMe: r.isMe }));

fx.sesonger.forEach((s: unknown, i: number) => {
  test(`serien som Tavla i appen: ${(s as { name: string }).name}`, () => {
    const v = seasonView(td, s, fx.me);
    assert.equal(v.title, want.tavla[i].seasonName);
    assert.deepEqual(shown(v.rows), shown(want.tavla[i].rows));
    assert.deepEqual(v.rows.map((r) => r.numbers.total), want.tavla[i].rows.map((r: { total: number }) => r.total));
    assert.deepEqual(grid(v.grid), want.tavla[i].rounds);
  });
});

/** Det `loadCompetition` henter, bygd av fixturen: alle rundene koblet til konkurransen. */
function raw(competition: Record<string, unknown>, extra: Partial<CompetitionRaw> = {}): CompetitionRaw {
  return {
    competition,
    participants: [],
    links: td.rounds.map((r: { id: string }) => ({ competition_id: competition.id, round_id: r.id, source: "manual" })),
    rounds: td.rounds,
    roundHoles: td.round_holes,
    players: td.players,
    matches: td.matches,
    scores: td.scores,
    claims: td.claims,
    courses: td.courses,
    courseHoles: td.course_holes,
    events: td.events,
    clubMembers: td.members,
    roundMembers: td.members,
    seasons: [fx.sesonger[0]],
    roster: [],
    roundParticipants: [],
    profiles: [],
    cupMatches: [],
    ...extra,
  };
}

const club = td.members[0].club_id;
const comp = (kind: string, clubID: string | null, entry: string, rules: unknown, id = "00000000-0000-0000-0000-000000009100") => ({
  id, kind, name: "Konkurranse", club_id: clubID, owner_id: null, season_id: null, status: "active", entry, rules,
  starts_on: null, ends_on: null, is_main: false,
});
const leagueComp = comp("league", club, "club", { version: 2, competition: { league: { bestRounds: 3 } } });
const funComp = comp("fun", null, "open", encodeRuleset(templateRules("fun")));

[leagueComp, funComp].forEach((c, i) => {
  test(`${c.kind} som appen (CompetitionQueries.detail → LeagueStandings)`, () => {
    const v = leagueView(competitionData(raw(c)), { memberID: fx.me, profileID: null });
    const w = want.konkurranser[i].standings;
    assert.equal(v.summary, w.rulesSummary);
    // Fasiten merker «deg» som gjesten med medlems-id-en din i morroturneringen uten klubb. Appen (og
    // web-admin) kjenner deg igjen som medlem eller profil (`myEntrants`), så der er ingen rad din.
    const mine = (rows: { isMe: boolean }[]) => rows.map((r) => ({ ...r, isMe: c.kind === "fun" ? false : r.isMe }));
    assert.deepEqual(shown(v.rows), mine(shown(w.rows)));
    assert.deepEqual(grid(v.grid), { ...w.rounds, rows: mine(w.rounds.rows) });
  });
});

/** Scorekortene slik fasiten skriver dem (alle spillere, Ut og Inn). */
function cards(snapshots: readonly RoundSnapshot[]) {
  return snapshots.flatMap((s) => s.players.flatMap((p) => (snapshotHasInward(s) ? [false, true] : [false]).map((inward) => {
    const card = snapshotScorecard(s, p.memberID, inward);
    return {
      roundID: s.round.id, memberID: p.memberID, inward, hasInward: snapshotHasInward(s), name: card.name, cardInward: card.inward,
      total: snapshotTotal(s, p.memberID), sumPar: card.sumPar, sumStrokes: card.sumStrokes, sumPoints: card.sumPoints, lines: card.lines,
    };
  })));
}

test("scorekortet bak rutene er appens (serie og liga)", () => {
  assert.deepEqual(cards(seasonView(td, fx.sesonger[0], fx.me).snapshots), want.scorekort.tavla);
  assert.deepEqual(cards(leagueView(competitionData(raw(leagueComp)), { memberID: fx.me, profileID: null }).snapshots), want.scorekort.liga);
});

test("en løs runde får navn fra round_roster, dagen den startet og ingen klubb", () => {
  const r0 = td.rounds[0];
  const loose = { ...r0, club_id: null, event_id: null, started_at: "2026-06-01T22:30:00Z" };
  const roster = td.players.filter((p: { round_id: string }) => p.round_id === r0.id)
    .map((p: { member_id: string }, k: number) => ({ round_id: r0.id, player_id: p.member_id, club_id: null, display_name: k === 0 ? "  " : `Gjest ${k}`, profile_id: null, is_guest: true }));
  const d = competitionData(raw(comp("fun", null, "open", encodeRuleset(templateRules("fun"))), { rounds: [loose], roster, clubMembers: [], roundMembers: [] }));
  const s = d.snapshots[0];
  assert.equal(s.eventDate, "2026-06-02");
  assert.equal(s.names.get(roster[0].player_id), "Spiller");
  assert.equal(s.names.get(roster[1].player_id), "Gjest 1");
  const v = leagueView(d, { memberID: null, profileID: null });
  assert.equal(v.rows.length, roster.length);
  assert.ok(v.rows.some((r) => r.name === "Gjest 1"));
});

test("cupen som appen (CupStandings med navn fra påmeldingene)", () => {
  const cupID = "00000000-0000-0000-0000-000000009200";
  const pid = (i: number) => `00000000-0000-0000-0000-${String(500 + i).padStart(12, "0")}`;
  const participants = [0, 1, 2, 3, 4, 5].map((i) => ({ id: pid(i), competition_id: cupID, member_id: td.members[i].id, profile_id: null, status: "active" }));
  const pairings = want.cup.pairings as { slot: number; a: string; b: string | null }[];
  const rows = pairings.map((p, i) => ({
    id: `00000000-0000-0000-0000-${String(900 + i).padStart(12, "0")}`, competition_id: cupID, round_no: 1, slot: p.slot,
    player_a: p.a, player_b: p.b, winner: p.b === null ? p.a : null, walkover: false, result: null as string | null, round_id: null,
  }));
  const first = rows.findIndex((r) => r.player_b !== null);
  rows[first].winner = rows[first].player_b;
  rows[first].result = "3&2";
  const last = rows.map((r) => r.player_b !== null).lastIndexOf(true);
  rows[last].winner = rows[last].player_a;
  rows[last].walkover = true;
  const c = comp("cup", club, "listed", { version: 2 }, cupID);
  const d = competitionData(raw(c, { participants, links: [], cupMatches: rows }));
  const v = cupView(d, rows, { memberID: td.members[5].id, profileID: null });
  assert.deepEqual(v.rounds, want.cup.rounds);
  assert.deepEqual(v.roundTitles, want.cup.roundTitles);
  assert.equal(v.champion, want.cup.champion?.name ?? null);
});

test("CSV: BOM, semikolon, desimalkomma og anførselstegn", () => {
  assert.equal(cellText(5.5), "5,5");
  assert.equal(cellText(-2), "-2");
  assert.equal(cellText(null), "");
  const csv = buildCsv([["Navn", "Poeng"], ["Kåre «K» \"den store\"", 5.5], ["A;B", null]]);
  assert.ok(csv.startsWith(BOM));
  assert.equal(csv, `${BOM}Navn;Poeng\r\n"Kåre «K» ""den store""";5,5\r\n"A;B";\r\n`);
  assert.equal(fileName("Vår/2026", "tabell"), "Vår 2026 tabell.csv");
});

test("CSV av tabellen og «Alle runder» for serien", () => {
  const v = seasonView(td, fx.sesonger[0], fx.me);
  const lines = tableCsv(v).slice(BOM.length).split("\r\n");
  assert.equal(lines[0], "Plass;Navn;Poeng;Duell;Sidepremier;Matcher;Hull;Stableford;Kvelder;Detaljer");
  const r = want.tavla[0].rows[0];
  assert.equal(lines[1], [r.placeText, r.name, r.totalText, r.duelText, r.sideText, r.matches, r.holes, r.stableford, r.evenings, r.detail].join(";"));
  assert.equal(lines.length, v.rows.length + 2);

  const g = gridCsv(v.grid, "points").slice(BOM.length).split("\r\n");
  const c0 = v.grid.columns[0];
  assert.equal(g[0].split(";")[2], [c0.label, c0.date, c0.title].filter((x) => x).join(" · "));
  assert.equal(g[1].split(";").at(-1), String(v.grid.rows[0].pointsTotal));
  const toPar = gridCsv(v.grid, "toPar").slice(BOM.length).split("\r\n");
  assert.equal(toPar[1].split(";").at(-1), gridTotal(v.grid.rows[0], "toPar"));
});

test("CSV av «Alle runder» merker runder som ikke teller (beste N)", () => {
  const v = leagueView(competitionData(raw(leagueComp)), { memberID: fx.me, profileID: null });
  const text = gridCsv(v.grid, "points");
  const dropped = v.grid.rows.some((r) => r.counted?.some((x, n) => !x && r.points[n] !== null));
  assert.equal(text.includes("(teller ikke)"), dropped);
});
