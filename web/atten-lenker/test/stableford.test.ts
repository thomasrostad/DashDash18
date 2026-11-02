// Stableford-kalkulatoren (/stableford). Kjøres med `npm test`.
// Banehandicap og slag fått sjekkes mot WHS-fixturen til regelmotoren (Packages/GolfgutuCore, ingen kopi).
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import worker, { APP_STORE_URL } from "../src/index.ts";
import {
  courseHandicap,
  holeResults,
  parseQuery,
  playingHandicap,
  ranks,
  stablefordPoints,
  strokeSummary,
  strokesForRank,
  STABLEFORD,
  type StablefordInput,
} from "../src/innhold/stableford.ts";

const WHS = JSON.parse(readFileSync(new URL("../../../Packages/GolfgutuCore/Tests/GolfgutuCoreTests/Fixtures/whs.json", import.meta.url), "utf8"));

function get(path: string): Promise<Response> {
  return worker.fetch(new Request("https://dashdash18.com" + path));
}

function input(over: Partial<StablefordInput> = {}): StablefordInput {
  return { index: 12.4, slope: 125, courseRating: 71.2, par: 72, allowance: 95, holes: 18, ...over };
}

test("banehandicap og slag fått: WHS-fixturen fra regelmotoren", () => {
  for (const c of WHS.banehandicap) {
    assert.equal(courseHandicap(input({ index: c.index, slope: c.slope, courseRating: c.courseRating, par: c.par, holes: 18 })), c.forventet, `indeks ${c.index}`);
  }
  for (const s of WHS.slagFatt) assert.equal(strokesForRank(s.banehandicap, s.indeks, 18), s.forventet, `CH ${s.banehandicap}, indeks ${s.indeks}`);
});

test("spillehandicap: andel og avrunding (,5 bort fra null)", () => {
  assert.equal(playingHandicap(13, 95), 12); // 12,35
  assert.equal(playingHandicap(10, 95), 10); // 9,5
  assert.equal(playingHandicap(36, 95), 34); // 34,2
  assert.equal(playingHandicap(13, 100), 13);
  assert.equal(playingHandicap(13, 0), 0);
  assert.equal(playingHandicap(-1, 95), -1); // −0,95
  assert.equal(playingHandicap(-1, 50), -1); // −0,5
});

test("9 hull: indeksen halveres, slagene fordeles på ni hull", () => {
  const nine = input({ holes: 9, courseRating: 35.6, par: 36 });
  assert.equal(courseHandicap(nine), 6); // 6,2 × 125/113 − 0,4 = 6,46
  assert.equal(playingHandicap(6, 95), 6); // 5,7
  assert.deepEqual(Array.from({ length: 9 }, (_, i) => strokesForRank(6, i + 1, 9)), [1, 1, 1, 1, 1, 1, 0, 0, 0]);
  assert.deepEqual(Array.from({ length: 9 }, (_, i) => strokesForRank(11, i + 1, 9)), [2, 2, 1, 1, 1, 1, 1, 1, 1]);
  // Indekser fra 18-hullskortet (oddetall) rangeres 1–9.
  const holes = [1, 3, 5, 7, 9, 11, 13, 15, 17].map((si, i) => ({ hole: i + 1, par: 4, strokeIndex: si, gross: null }));
  assert.deepEqual([...ranks(holes, 9).values()], [1, 2, 3, 4, 5, 6, 7, 8, 9]);
});

test("plusshandicap gir slag tilbake på de letteste hullene", () => {
  assert.equal(courseHandicap(input({ index: -2, slope: 130, courseRating: 73, par: 72 })), -1);
  assert.deepEqual(strokeSummary(-1, 18), ["Ingen slag på hullene med indeks 1–17.", "Du gir 1 slag tilbake på hullet med indeks 18."]);
  assert.deepEqual(strokeSummary(-3, 18), ["Ingen slag på hullene med indeks 1–15.", "Du gir 1 slag tilbake på hullene med indeks 16–18."]);
  // Par 4 på indeks 18 med 4 slag: netto 5, 1 poeng.
  assert.equal(stablefordPoints(4, strokesForRank(-1, 18, 18), 4), 1);
  assert.equal(stablefordPoints(4, strokesForRank(-1, 17, 18), 4), 2);
});

test("stablefordpoeng: 2 + par + slag fått − slag, aldri under 0", () => {
  assert.equal(stablefordPoints(4, 1, 5), 2); // netto par
  assert.equal(stablefordPoints(3, 0, 4), 1); // bogey
  assert.equal(stablefordPoints(5, 1, 4), 4); // netto eagle
  assert.equal(stablefordPoints(4, 0, 6), 0); // dobbel bogey
  assert.equal(stablefordPoints(4, 0, 11), 0); // aldri under 0
  assert.equal(stablefordPoints(4, 2, 3), 5);
  assert.deepEqual(strokeSummary(12, 18), ["Du får 1 slag på hullene med indeks 1–12.", "Ingen slag på hullene med indeks 13–18."]);
  assert.deepEqual(strokeSummary(20, 18), ["Du får 2 slag på hullene med indeks 1–2.", "Du får 1 slag på hullene med indeks 3–18."]);
  assert.deepEqual(strokeSummary(0, 18), ["Du får ingen slag. Netto er det samme som brutto på alle hullene."]);
});

test("en hel runde: netto par på alle hull gir 36 poeng", () => {
  const holes = Array.from({ length: 18 }, (_, i) => ({ hole: i + 1, par: 4, strokeIndex: i + 1, gross: i < 12 ? 5 : 4 }));
  const r = holeResults(holes, 12, 18);
  assert.equal(r.reduce((s, h) => s + h.points!, 0), 36);
});

test("skjemaet leser komma, plusstegn og prosent", () => {
  const p = parseQuery(new URLSearchParams("indeks=%2B2%2C1&slope=130&cr=73&par=72&andel=85%25"));
  assert.deepEqual(p.errors, []);
  assert.equal(p.input?.index, -2.1);
  assert.equal(p.input?.allowance, 85);
  assert.equal(parseQuery(new URLSearchParams("indeks=-2,1&slope=130&cr=73&par=72")).input?.index, -2.1);
  assert.equal(parseQuery(new URLSearchParams("indeks=18,4&slope=130&cr=73&par=72&andel=")).input?.allowance, 95);
  assert.equal(parseQuery(new URLSearchParams("utm_source=x")).submitted, false);
});

test("siden: SEO, én h1, JSON-LD, lenker og CSP som tillater skjemaet", async () => {
  const res = await get("/stableford");
  assert.equal(res.status, 200);
  const html = await res.text();
  assert.ok(STABLEFORD.title.length >= 10 && STABLEFORD.title.length <= 70, `tittel ${STABLEFORD.title.length}`);
  assert.ok(STABLEFORD.description.length >= 50 && STABLEFORD.description.length <= 160, `beskrivelse ${STABLEFORD.description.length}`);
  assert.equal(html.match(/<h1[ >]/g)?.length, 1);
  assert.ok(html.includes('<link rel="canonical" href="https://dashdash18.com/stableford">'));
  assert.ok(html.includes('"@type":"WebApplication"'));
  assert.ok(!html.includes("aggregateRating"));
  assert.ok(html.includes('href="/guide/spillformer"'));
  assert.ok(html.includes('href="/guide/golfturnering"'));
  assert.ok(html.includes(`href="${APP_STORE_URL}"`));
  assert.ok(html.includes('<form method="get" action="/stableford#resultat"'));
  assert.ok(!/<script(?![^>]*application\/ld\+json)/.test(html), "ingen skript utenom JSON-LD");
  const csp = res.headers.get("content-security-policy")!;
  assert.match(csp, /form-action 'self'/);
  assert.match(csp, /script-src 'nonce-/);
  // Andre sider sender fortsatt ikke skjema.
  assert.match((await get("/")).headers.get("content-security-policy")!, /form-action 'none'/);
  // Alle feltene har label.
  for (const id of ["indeks", "slope", "cr", "par", "andel"]) assert.ok(html.includes(`<label for="${id}">`), id);
});

test("svaret regnes på serveren, med samme kanoniske adresse", async () => {
  const res = await get("/stableford?hull=18&indeks=12%2C4&slope=125&cr=71%2C2&par=72&andel=95");
  assert.equal(res.status, 200);
  const html = await res.text();
  assert.ok(html.includes('<link rel="canonical" href="https://dashdash18.com/stableford">'));
  assert.match(html, /Banehandicap<\/span> <strong>13<\/strong>/);
  assert.match(html, /Spillehandicap \(95 %\)<\/span> <strong>12<\/strong>/);
  assert.ok(html.includes("Du får 1 slag på hullene med indeks 1–12."));
  assert.ok(html.includes('value="12,4"'), "feltene fylles igjen");
  assert.ok(!html.includes('role="alert"'));
});

test("poeng hull for hull, også 9 hull med indekser fra 18-hullskortet", async () => {
  const q = new URLSearchParams("hull=9&indeks=12,4&slope=125&cr=35,6&par=36&andel=95");
  const si = [1, 3, 5, 7, 9, 11, 13, 15, 17];
  si.forEach((s, i) => {
    q.set(`par${i + 1}`, "4");
    q.set(`si${i + 1}`, String(s));
    q.set(`slag${i + 1}`, "5");
  });
  const html = await (await get("/stableford?" + q)).text();
  // Spillehandicap 6: ett slag på de seks vanskeligste. 6 × 2 + 3 × 1 = 15 poeng.
  assert.match(html, /<strong>15 poeng<\/strong> etter 9 hull \(3 under netto par\)/);
  assert.ok(html.includes("<details id=\"hull\" open>"));
});

test("ugyldig input gir vennlig feilmelding, ikke 500", async () => {
  const cases: [string, RegExp][] = [
    ["indeks=abc&slope=125&cr=71,2&par=72", /Handicapindeks må være et tall/],
    ["indeks=60&slope=125&cr=71,2&par=72", /Handicapindeks må være et tall/],
    ["indeks=12&slope=999&cr=71,2&par=72", /Slope må være et helt tall fra 55 til 155/],
    ["indeks=12&slope=125&cr=&par=72", /Fyll inn course rating/],
    ["indeks=12&slope=125&cr=71,2&par=72&andel=150", /Handicapandel må være et helt tall/],
    ["indeks=12&slope=125&cr=71,2&par=72&par1=4&si1=1&par2=4&si2=1", /Indeks 1 står på både hull 1 og hull 2/],
    ["indeks=12&slope=125&cr=71,2&par=72&slag1=5", /Hull 1: fyll inn både par og indeks/],
    ["indeks=12&slope=125&cr=71,2&par=72&par1=9&si1=1", /Hull 1: par må være 3, 4, 5 eller 6/],
    ["hull=9&indeks=12&slope=125&cr=35,6&par=36&par1=4&si1=11", /alle ni hullene ha indeks/],
    ["indeks=%3Cscript%3E&slope=125&cr=71,2&par=72", /Handicapindeks må være et tall/],
  ];
  for (const [q, message] of cases) {
    const res = await get("/stableford?" + q);
    assert.equal(res.status, 200, q);
    const html = await res.text();
    assert.ok(html.includes('role="alert"'), q);
    assert.match(html, message, q);
    assert.ok(!html.includes("<script>"), `escapet: ${q}`);
  }
  // Feltet med feil er merket.
  assert.ok((await (await get("/stableford?indeks=abc&slope=125&cr=71,2&par=72")).text()).includes('value="abc" aria-invalid="true"'));
});
