// Tavla i nettleseren for tilskuere (sql/058). Kjøres med `npm test`, uten Cloudflare og Supabase.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { buildSharePayload, scorecards, sharePage } from "../src/tavla.ts";
import { buildTVPayload, seasonStandings } from "../src/tv.ts";
import { handle } from "../src/index.ts";

const fixture = JSON.parse(readFileSync(new URL("../../golfgutu-core/test/fixtures/tavla.json", import.meta.url), "utf8"));
const expected = JSON.parse(readFileSync(new URL("../../golfgutu-core/test/fixtures/tavla.forventet.json", import.meta.url), "utf8"));
const env = { SUPABASE_URL: "https://eksempel.supabase.co", SUPABASE_KEY: "publiserbar" };

const season = fixture.sesonger[0];
const board = { ...fixture.tavlaData, competition: { name: season.name, season_id: season.id, club_id: season.club_id,
  status: season.status, rules: season.rules, club_name: "Golfgutu Invitational" } };

test("tabellen er TV-ens (og appens) tabell, med spilleren bak hver rad", () => {
  const share = buildSharePayload(board);
  const tv = buildTVPayload(board);
  assert.equal(share.kind, "season");
  assert.equal(share.name, tv.name);
  assert.equal(share.played, tv.played);
  assert.deepEqual(share.rows.map(({ id: _id, ...r }) => r), tv.rows);
  const app = expected.tavla[0] as { rows: { memberID: string }[] };
  assert.deepEqual(share.rows.map((r) => r.id), app.rows.map((r) => r.memberID.toLowerCase()));
});

test("«Alle runder» er appens rutenett", () => {
  const share = buildSharePayload(board);
  const want = expected.tavla[0].rounds as { columns: { title: string; isOngoing: boolean }[]; rows: { name: string; points: (number | null)[] }[] };
  assert.ok(share.rounds !== null);
  assert.deepEqual(share.rounds!.columns.map((c) => [c.title, c.ongoing]), want.columns.map((c) => [c.title, c.isOngoing]));
  assert.deepEqual(share.rounds!.rows.map((r) => [r.name, r.points]), want.rows.map((r) => [r.name, r.points]));
});

test("scorekortene er appens (RoundGame.scorecard), Ut og Inn i ett", () => {
  const share = buildSharePayload(board);
  const want = expected.scorekort.tavla as { roundID: string; memberID: string; inward: boolean; total: number;
    lines: { number: number; par: number; strokes: number | null; points: number | null; scoreName: string | null }[] }[];
  assert.ok(want.length > 0);
  for (const id of Object.keys(share.cards)) assert.ok(share.rounds!.columns.some((c) => c.id === id), "kort for en runde i rutenettet");
  for (const w of want) {
    const card = share.cards[w.roundID]?.[w.memberID];
    assert.ok(card, `kort for ${w.memberID} i ${w.roundID}`);
    assert.equal(card.total, w.total);
    // Ut- og Inn-kortet fra appen står etter hverandre i nettkortet.
    const lines = w.lines.map((l) => ({ n: l.number, par: l.par, s: l.strokes, p: l.points, k: l.scoreName }));
    const at = w.inward && card.holes.length > 9 ? 9 : 0;
    assert.deepEqual(card.holes.slice(at, at + lines.length), lines);
  }
  // Hver spiller i rutenettet med poeng i en runde har et kort der.
  const t = seasonStandings(board);
  assert.deepEqual(Object.keys(scorecards(t.snapshots)).sort(), Object.keys(share.cards).sort());
});

test("liga og cup", () => {
  const d = fixture.tavlaData;
  const id = "00000000-0000-0000-0000-000000009100";
  const dates = new Map(d.events.map((e: { id: string; event_date: string }) => [e.id, e.event_date]));
  const names = new Map(d.members.map((m: { id: string; display_name: string }) => [m.id, m.display_name]));
  const league = buildSharePayload({
    ...d, events: undefined,
    competition: { id, name: "Onsdagsligaen", kind: "league", status: "active", season_id: null, club_id: d.members[0].club_id, owner_id: null,
      entry: "club", rules: { version: 2, competition: { league: { bestRounds: 3 } } }, starts_on: null, ends_on: null, is_main: false, club_name: null },
    participants: [], links: d.rounds.map((r: { id: string }) => ({ competition_id: id, round_id: r.id })),
    rounds: d.rounds.map((r: { event_id: string }) => ({ ...r, event_date: dates.get(r.event_id) ?? null })),
    roster: d.players.map((p: { round_id: string; member_id: string }) => ({ round_id: p.round_id, player_id: p.member_id, display_name: names.get(p.member_id) ?? null })),
    round_participants: [], profiles: [], cup_matches: [],
  });
  assert.equal(league.kind, "league");
  const want = expected.konkurranser[0].standings as { rows: { placeText: string; name: string }[] };
  assert.deepEqual(league.rows.map((r) => [r.place, r.name]), want.rows.map((r) => [r.placeText, r.name]));
  assert.ok(league.rounds!.rows.some((r) => r.counted !== null), "beste N: rutene som ikke teller er merket");
  for (const r of league.rounds!.rows) for (const [n, c] of league.rounds!.columns.entries()) {
    if (r.points[n] !== null) assert.ok(league.cards[c.id]?.[r.id], "kort bak hver rute med poeng");
  }

  const cup = buildSharePayload({
    competition: { id, name: "Klubbcupen", kind: "cup", status: "active", season_id: null, club_id: d.members[0].club_id, owner_id: null,
      entry: "listed", rules: { version: 2 }, starts_on: null, ends_on: null, is_main: false, club_name: null },
    participants: [], members: d.members, cup_matches: [],
  });
  assert.equal(cup.kind, "cup");
  assert.equal(cup.rounds, null);
  assert.deepEqual(cup.cards, {});
});

test("siden og adressene", async () => {
  const page = await handle(new Request("https://dashdash18.com/tavla/ABCDEFGHJK"), env);
  assert.equal(page.status, 200);
  const csp = page.headers.get("Content-Security-Policy") ?? "";
  assert.match(csp, /connect-src 'self'/);
  assert.match(csp, /font-src 'self'/);
  assert.match(csp, /script-src 'nonce-/);
  const html = await page.text();
  assert.match(html, /\/tavla\/ABCDEFGHJK\.json/);
  assert.match(html, /Få Atten-appen/);
  assert.match(html, /Alle runder/);
  assert.match(html, /lang="nb"/);
  assert.equal((await handle(new Request("https://dashdash18.com/tavla/abcde-fghjk"), env)).status, 302);
  assert.equal((await handle(new Request("https://dashdash18.com/tavla/feil"), env)).status, 404);
  assert.equal((await handle(new Request("https://dashdash18.com/tavla/feil.json"), env)).status, 404);
  assert.ok(sharePage("ABCDEFGHJK", "n").includes('nonce="n"'));
});

test("JSON: henter med koden, 404 når delingen er slått av, 502 når Supabase svikter", async () => {
  const original = globalThis.fetch;
  const calls: { url: string; body: string }[] = [];
  let reply: () => Response = () => new Response(JSON.stringify(board), { status: 200 });
  globalThis.fetch = (async (url: string | URL | Request, init?: RequestInit) => {
    calls.push({ url: String(url), body: String(init?.body) });
    return reply();
  }) as typeof fetch;
  try {
    const ok = await handle(new Request("https://dashdash18.com/tavla/ABCDEFGHJK.json"), env);
    assert.equal(ok.status, 200);
    assert.equal(ok.headers.get("Cache-Control"), "no-store");
    const body = await ok.json() as { name: string; rows: unknown[] };
    assert.equal(body.name, buildSharePayload(board).name);
    assert.equal(calls[0].url, "https://eksempel.supabase.co/rest/v1/rpc/tv_board_data");
    assert.deepEqual(JSON.parse(calls[0].body), { p_code: "ABCDEFGHJK" });

    reply = () => new Response(JSON.stringify({ code: "P0002", message: "Fant ingen TV-visning for koden" }), { status: 400 });
    assert.equal((await handle(new Request("https://dashdash18.com/tavla/ABCDEFGHJK.json"), env)).status, 404);

    reply = () => new Response("{}", { status: 500 });
    assert.equal((await handle(new Request("https://dashdash18.com/tavla/ABCDEFGHJK.json"), env)).status, 502);
  } finally {
    globalThis.fetch = original;
  }
});
