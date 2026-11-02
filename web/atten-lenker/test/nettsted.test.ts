// Rammen rundt nettstedet (src/nettsted.ts): meny, topp med høydekurver, blokker og bunn.
import { test } from "node:test";
import assert from "node:assert/strict";
import worker from "../src/index.ts";
import { CONTENT_PAGES } from "../src/innhold.ts";
import { headingText, joinSegments, splitSections, topoSVG } from "../src/nettsted.ts";

const BASE = "https://dashdash18.com";
const INDEXED = ["/", "/personvern", "/vilkar", "/support", ...CONTENT_PAGES.map((p) => p.path)];
const LANDING = new Set(["/", ...CONTENT_PAGES.filter((p) => p.landing).map((p) => p.path)]);

async function html(path: string): Promise<string> {
  return (await worker.fetch(new Request(BASE + path))).text();
}

test("alle indekserte sider har menyen, én h1, bunnen og høydekurvene", async () => {
  for (const path of [...INDEXED, "/finnes-ikke"]) {
    const body = await html(path);
    assert.equal((body.match(/<nav class="meny wrap" aria-label="Hovedmeny">/g) ?? []).length, 1, `${path}: meny`);
    for (const href of ["/stableford", "/guide/golfturnering", "/guide/golfliga", "/guide/spillformer", "/for-klubber", "https://admin.dashdash18.com"]) {
      assert.ok(body.includes(`href="${href}"`), `${path}: menyen lenker til ${href}`);
    }
    assert.equal((body.match(/<h1[ >]/g) ?? []).length, 1, `${path}: én h1`);
    // Salgssidene (forsiden og /for-klubber) har sin egen <main>, se test/salgsside.test.ts.
    assert.match(body, /<main class="(dok|salg)">/, path);
    assert.match(body, /<footer class="bunn">/, path);
    assert.match(body, /<svg class="kurver"[^>]*aria-hidden="true"/, path);
    // Skriftene er selvhostet og lastes tidlig. Ingenting hentes fra andre domener.
    assert.ok(body.includes('<link rel="preload" href="/fonts/archivo-latin.woff2" as="font" type="font/woff2" crossorigin>'), path);
    assert.ok(body.includes('<link rel="preload" href="/fonts/newsreader-latin.woff2" as="font" type="font/woff2" crossorigin>'), path);
    assert.match(body, /font-display: swap/, path);
    assert.doesNotMatch(body, /url\(["']?https?:/, `${path}: ingen eksterne skrifter eller bilder i CSS`);
    // Utseendet trenger ikke skript. Salgssidene har ett inline-skript med nonce for bevegelsen (progressiv forbedring).
    const scripts = body.match(/<script(?![^>]*application\/ld\+json)[^>]*>/g) ?? [];
    assert.deepEqual(scripts.map((s) => s.replace(/[0-9a-f]{32}/, "N")), LANDING.has(path) ? ['<script nonce="N">'] : [], `${path}: skript`);
  }
});

test("menyen markerer siden du er på", async () => {
  assert.match(await html("/stableford"), /<a class="n" href="\/stableford" aria-current="page">Kalkulator<\/a>/);
  assert.match(await html("/for-klubber"), /<a class="n" href="\/for-klubber" aria-current="page">For klubber<\/a>/);
  const guide = await html("/guide/golfliga");
  assert.match(guide, /<summary class="n aktiv">Guider<\/summary>/);
  assert.match(guide, /<a class="" href="\/guide\/golfliga" aria-current="page">/);
});

test("toppen: eyebrow, h1 med gull kursiv del og ingress, med samme tekst som før", async () => {
  for (const p of CONTENT_PAGES.filter((c) => !c.landing)) {
    assert.ok(p.heading, `${p.path}: har heading`);
    const h1 = /<h1>([\s\S]*?)<\/h1>/.exec(p.render ? p.render(new URLSearchParams()) : p.content)?.[1];
    assert.equal(headingText(p.heading!), h1, `${p.path}: loud + soft er teksten i h1`);
    const body = await html(p.path);
    assert.match(body, /<div class="hero">\n<p class="eyebrow"><b>/, p.path);
    if (p.heading!.soft) assert.ok(body.includes(`<span class="soft">${p.heading!.soft}</span></h1>`), p.path);
    assert.match(body, /<\/h1>\n<p class="ingress">/, p.path);
    // Teksten i h1 er uendret for søkemotorene.
    const shown = /<h1>([\s\S]*?)<\/h1>/.exec(body)![1].replace(/<[^>]+>/g, "");
    assert.equal(shown, h1, p.path);
  }
});

test("toppen har knapper: egne fra innholdet, ellers App Store og arrangør; ikke over kalkulatoren", async () => {
  const klubb = await html("/for-klubber");
  assert.match(klubb, /<div class="knapper">\n<a class="knapp" href="https:\/\/apps\.apple\.com[^"]+" rel="noopener">Last ned Atten fra App Store<\/a>\s*<a class="knapp" href="https:\/\/admin\.dashdash18\.com" rel="noopener">Logg inn som arrangør<\/a>\n<\/div>/);
  const guide = await html("/guide/golfturnering");
  assert.match(guide, /<div class="knapper">\n<a class="knapp" href="https:\/\/apps\.apple\.com/);
  assert.ok(guide.includes(">Logg inn som arrangør</a>\n</div>"));
  assert.doesNotMatch(await html("/stableford"), /class="knapper"/);
});

test("hver h2 blir en blokk, men skjemaet deles ikke", async () => {
  const guide = await html("/guide/spillformer");
  const h2 = (guide.match(/<h2>/g) ?? []).length;
  assert.equal((guide.match(/<section class="blokk">\n<h2>/g) ?? []).length, h2);
  const calc = await html("/stableford");
  const form = /<form[\s\S]*?<\/form>/.exec(calc)![0];
  assert.ok(form.includes("<h2>Steg 1: spillehandicap og slag per hull</h2>"), "steg 1 står i skjemaet");
  assert.match(calc, /<div class="blokk enkel">\n<form method="get"/);
  const { lead, sections } = splitSections("<p>a</p><form><h2>i</h2></form><h2>x</h2><ul><li>y</li></ul><h2>z</h2>");
  assert.equal(lead, "<p>a</p><form><h2>i</h2></form>");
  assert.deepEqual(sections.map((s) => s.heading), ["<h2>x</h2>", "<h2>z</h2>"]);
});

test("personvern, vilkår, support og 404 får rammen uten topp; invitasjonene er uendret", async () => {
  for (const path of ["/personvern", "/finnes-ikke"]) {
    const body = await html(path);
    assert.match(body, /<article class="ark">\s*<h1>/, path);
    assert.doesNotMatch(body, /class="hero"/, path);
  }
  const invite = await html("/runde/ABCDE12345");
  assert.doesNotMatch(invite, /Hovedmeny|class="kurver"|archivo/, "invitasjonen har sin egen stil");
  assert.match(invite, /<p class="merke">Atten<\/p>/);
});

test("høydekurvene: lukkede ringer settes sammen, SVG-en er liten og uten skript", () => {
  // En firkant av fire linjestykker blir én linje.
  const lines = joinSegments([[0, 0, 10, 0], [10, 10, 0, 10], [10, 0, 10, 10], [0, 10, 0, 0]]);
  assert.equal(lines.length, 1);
  assert.equal(lines[0].length, 10);
  const svg = topoSVG();
  assert.match(svg, /^<svg class="kurver" viewBox="0 0 1440 760"/);
  assert.equal((svg.match(/<path /g) ?? []).length, 2);
  assert.ok(svg.length < 16000, `SVG-en er ${svg.length} tegn`);
  assert.doesNotMatch(svg, /<script|on\w+=/);
  assert.equal(topoSVG(), svg, "regnes én gang");
});
