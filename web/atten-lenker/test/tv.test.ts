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
