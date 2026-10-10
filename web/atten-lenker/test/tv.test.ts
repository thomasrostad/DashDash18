import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { buildTVPayload, normalizeTVCode, tvBoardPage } from "../src/tv.ts";
import { handle } from "../src/index.ts";

const fixture = JSON.parse(readFileSync(new URL("../../golfgutu-core/test/fixtures/tavla.json", import.meta.url), "utf8"));
const expected = JSON.parse(readFileSync(new URL("../../golfgutu-core/test/fixtures/tavla.forventet.json", import.meta.url), "utf8"));

test("koden normaliseres", () => {
  assert.equal(normalizeTVCode("abcde fghjk"), "ABCDEFGHJK");
  assert.equal(normalizeTVCode("ABCDE-FGHJK"), "ABCDEFGHJK");
  assert.equal(normalizeTVCode("ABCDEFGHJ1"), null); // 1 er ikke i alfabetet
  assert.equal(normalizeTVCode("kort"), null);
});

test("TV-tabellen er appens tabell (samme regelmotor og tekster)", () => {
  const season = fixture.sesonger[0];
  const board = { ...fixture.tavlaData, competition: { name: season.name, season_id: season.id, club_id: season.club_id,
    status: season.status, rules: season.rules, club_name: "Golfgutu Invitational" } };
  const tv = buildTVPayload(board);
  // Fasiten er laget av appens Swift-kode (tools/swift-tavla i golfgutu-core).
  const app = expected.tavla[0] as { rows: { placeText: string; name: string; totalText: string; detail: string }[] };
  assert.ok(tv.rows.length > 0);
  assert.match(tv.played, /av \d+ (kveld|kvelder|spilledag|spilledager) spilt/);
  assert.deepEqual(tv.rows.map((r) => [r.place, r.name, r.total, r.detail]),
                   app.rows.map((r) => [r.placeText, r.name, r.totalText, r.detail]));
  assert.ok(tv.latest === null || tv.latest.lines.every((l, i, a) => i === 0 || a[i - 1].points >= l.points));
});

test("TV for liga er appens ligatabell (sql/043)", () => {
  const d = fixture.tavlaData;
  const club = d.members[0].club_id;
  const id = "00000000-0000-0000-0000-000000009100";
  const dates = new Map(d.events.map((e: { id: string; event_date: string }) => [e.id, e.event_date]));
  const names = new Map(d.members.map((m: { id: string; display_name: string }) => [m.id, m.display_name]));
  // Slik tv_competition_data leverer det: datoen på runden, navnene fra round_roster.
  const board = {
    ...d,
    events: undefined,
    competition: { id, name: "Onsdagsligaen", kind: "league", status: "active", season_id: null, club_id: club, owner_id: null,
      entry: "club", rules: { version: 2, competition: { league: { bestRounds: 3 } } }, starts_on: null, ends_on: null, is_main: false,
      club_name: "Golfgutu Invitational" },
    participants: [],
    links: d.rounds.map((r: { id: string }) => ({ competition_id: id, round_id: r.id })),
    rounds: d.rounds.map((r: { event_id: string }) => ({ ...r, event_date: dates.get(r.event_id) ?? null })),
    roster: d.players.map((p: { round_id: string; member_id: string }) => ({ round_id: p.round_id, player_id: p.member_id, display_name: names.get(p.member_id) ?? null })),
    round_participants: [],
    profiles: [],
    cup_matches: [],
  };
  const tv = buildTVPayload(board);
  const app = expected.konkurranser[0];
  assert.equal(app.kind, "league");
  const want = app.standings as { rows: { placeText: string; name: string; totalText: string; detail: string }[]; rounds: { columns: { title: string }[] } };
  assert.ok(tv.rows.length > 0);
  assert.deepEqual(tv.rows.map((r) => [r.place, r.name, r.total, r.detail]),
                   want.rows.map((r) => [r.placeText, r.name, r.totalText, r.detail]));
  assert.equal(tv.latest?.title, want.rounds.columns.at(-1)?.title);
  assert.equal(tv.name, "Onsdagsligaen");
});

test("TV for cup viser runden som pågår", () => {
  const d = fixture.tavlaData;
  const id = "00000000-0000-0000-0000-000000009200";
  const pid = (i: number) => `00000000-0000-0000-0000-${String(500 + i).padStart(12, "0")}`;
  const match = (no: number, slot: number, a: string, b: string | null, winner: string | null, result: string | null) =>
    ({ id: `${no}-${slot}`, competition_id: id, round_no: no, slot, player_a: a, player_b: b, winner, walkover: false, result, round_id: null });
  const board = {
    competition: { id, name: "Klubbcupen", kind: "cup", status: "active", season_id: null, club_id: d.members[0].club_id, owner_id: null,
      entry: "listed", rules: { version: 2 }, starts_on: null, ends_on: null, is_main: false, club_name: null },
    participants: [0, 1, 2, 3].map((i) => ({ id: pid(i), competition_id: id, member_id: d.members[i].id, profile_id: null, status: "active" })),
    members: d.members,
    cup_matches: [match(1, 0, pid(0), pid(3), pid(0), "3&2"), match(1, 1, pid(1), pid(2), null, null)],
  };
  const tv = buildTVPayload(board);
  assert.equal(tv.played, "Semifinale");
  assert.equal(tv.rows.length, 2);
  assert.equal(tv.rows[0].detail, "3&2");
  assert.equal(tv.rows[0].total, d.members[0].display_name);
});

test("TV-sidene", async () => {
  const home = await handle(new Request("https://dashdash18.com/tv"));
  assert.equal(home.status, 200);
  const page = await handle(new Request("https://dashdash18.com/tv/ABCDEFGHJK"));
  assert.equal(page.status, 200);
  assert.match(page.headers.get("Content-Security-Policy") ?? "", /connect-src 'self'/);
  const lower = await handle(new Request("https://dashdash18.com/tv/abcdefghjk"));
  assert.equal(lower.status, 302);
  const bad = await handle(new Request("https://dashdash18.com/tv/xx.json"));
  assert.equal(bad.status, 404);
  assert.ok(tvBoardPage("ABCDEFGHJK", "n").includes('/tv/ABCDEFGHJK.json'));
});
