// Salgssidene (src/salgsside.ts): forsiden og /for-klubber har delene fra forsiden på admin.dashdash18.com,
// server-rendret og lesbare uten skript, med søkeordene i h2 som før.
import { test } from "node:test";
import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";
import worker, { APP_STORE_URL } from "../src/index.ts";
import { CONTENT_PAGES } from "../src/innhold.ts";
import { LANDING_SCRIPT } from "../src/salgsside.ts";
import { DEMO_PLAYERS } from "../../admin/src/landing/demo.ts";
import { FAIRWAY, KVELD, PHOTO_CREDIT } from "../../admin/src/landing/markup.ts";
import { LANDING_STYLE } from "../../admin/src/landing/style.ts";

const BASE = "https://dashdash18.com";

async function html(path: string): Promise<{ res: Response; body: string }> {
  const res = await worker.fetch(new Request(BASE + path));
  return { res, body: await res.text() };
}
const h2s = (body: string) => [...body.matchAll(/<h2>([^<]+)<\/h2>/g)].map((m) => m[1].toLowerCase()).join(" | ");
const text = (s: string) => s.replace(/<[^>]+>/g, "");

test("forsiden og /for-klubber har delene fra admin-forsiden", async () => {
  for (const path of ["/", "/for-klubber"]) {
    const { body } = await html(path);
    assert.match(body, /<div class="landing">\n<main class="salg">\n<header class="hero">\n<svg class="kurver"/, `${path}: toppen med høydekurvene`);
    assert.match(body, /<p class="name in-1"><b>/, `${path}: linja over overskriften`);
    assert.match(body, /<section class="morning"><div class="wrap">\n<p class="read">(<span class="w">|<span class="soft">)/, `${path}: setningen`);
    assert.match(body, /<p class="by">[^<]+<\/p>/, path);
    assert.match(body, /<section class="know" id="bli-kjent">/, `${path}: Bli kjent`);
    assert.equal((body.match(/<article class="kcard[^"]*" data-inview>/g) ?? []).length, 5, `${path}: fem kort i raden`);
    assert.match(body, /<div class="rail" role="region" aria-label="Bli kjent med [^"]+" tabindex="0">/, path);
    assert.match(body, /<div class="photo" data-parallax><img src="\/landing\/kveld\.jpg"/, `${path}: fotobåndet`);
    assert.match(body, /<section class="close" id="ny">/, `${path}: avslutningen`);
    assert.ok(body.includes(`${PHOTO_CREDIT} · dashdash18.com`), `${path}: bildene er kreditert`);
    assert.ok(body.includes(`<div class="knapper">\n<a class="knapp" href="${APP_STORE_URL}" rel="noopener">`), `${path}: App Store i toppen`);
    // Ingen innlogging på dashdash18.com, den står på admin.
    assert.doesNotMatch(body, /<input|<form/, path);
  }
});

test("toppen: h1 har samme tekst som før, men delt i linjer og en kursiv del", async () => {
  const cases: [string, string][] = [
    ["/", "Golfkvelden med gjengen, samlet i én app"],
    ["/for-klubber", "Tabellen er ferdig før dere er i baren."],
  ];
  for (const [path, h1] of cases) {
    const { body } = await html(path);
    const inner = /<h1>([\s\S]*?)<\/h1>/.exec(body)![1];
    assert.equal(text(inner), h1, path);
    assert.match(inner, /^<span class="loud"><span class="ln"><span>[^<]+<\/span><\/span> <span class="ln">/, `${path}: linjene`);
    assert.match(inner, /<span class="soft in-2">[^<]+<\/span>$/, `${path}: den kursive delen`);
  }
});

test("/for-klubber: tavla med eksempeltabellen i toppen, knapper til App Store og arrangør", async () => {
  const { body } = await html("/for-klubber");
  const tv = /<div class="tv"[\s\S]*?<\/table>/.exec(body)![0];
  assert.match(tv, /eksempel/);
  assert.deepEqual([...tv.matchAll(/<td class="nm">([^<]+)</g)].map((m) => m[1]), DEMO_PLAYERS.map((p) => p.name),
                   "alle radene står i HTML-en (uten skript)");
  assert.match(body, /<div class="knapper">\n<a class="knapp" href="https:\/\/apps\.apple\.com[^"]+" rel="noopener">Last ned Atten fra App Store<\/a>\n<a class="knapp" href="https:\/\/admin\.dashdash18\.com" rel="noopener">Logg inn som arrangør<\/a>\n<\/div>/);
  assert.ok(body.includes('<a class="knapp" href="mailto:hei@dashdash18.com">'), "e-post i avslutningen");
  assert.match(body, /<span class="loud">Bli kjent med<\/span><span class="soft">Arrangør\.<\/span>/);
  // Søkeordene står fortsatt i h2, nå i tekstdelene.
  const h2 = h2s(body);
  for (const word of ["turneringssystem", "golfturnering", "golfsimulator", "golfliga"]) assert.ok(h2.includes(word), `h2 med «${word}»: ${h2}`);
  assert.equal((body.match(/<section class="del">\n<h2>/g) ?? []).length, 7, "hver h2 fra innholdet er en del");
});

test("forsiden: telefonen med scorekortet, golfgjengen, simulatorkvelden, tavla og lenkene til kalkulatoren og guidene", async () => {
  const { body } = await html("/");
  assert.match(body, /<div class="in-3"><div class="screen"><div class="phone" data-telefon>/, "telefonen i toppen");
  assert.match(body, /eksempel/);
  for (const eb of ["Tavla", "Golfgjengen", "Simulatorkvelden", "Baner", "Spillformer"]) {
    assert.ok(body.includes(`<p class="eb">${eb}</p>`), `kortet ${eb}`);
  }
  for (const p of CONTENT_PAGES.filter((c) => c.path !== "/for-klubber")) {
    assert.ok(body.includes(`<li><a href="${p.path}">`), `lenke til ${p.path}`);
  }
  assert.ok(body.includes('<a class="knapp" href="/for-klubber">For klubber og sentre</a>'));
  const h2 = h2s(body);
  for (const word of ["liga", "golfgjeng", "stableford"]) assert.ok(h2.includes(word), `h2 med «${word}»: ${h2}`);
  const all = text(body).toLowerCase();
  for (const word of ["golfturnering", "scorekort", "tavle", "liga", "golfgjeng"]) assert.ok(all.includes(word), word);
});

test("uten skript står alt ferdig: skjult starttilstand bare under .live", () => {
  // Regler som gjør noe usynlig (opacity 0 eller svak), utenom nøkkelbildene, gjelder bare når live.ts har satt `.live`.
  const css = LANDING_STYLE.replace(/@keyframes[^{]+\{(?:[^{}]*\{[^}]*\})*[^}]*\}/g, "");
  const hidden = [...css.matchAll(/([^{}]+)\{[^}]*opacity:\s*(?:0|\.14)\s*[;}]/g)].map((m) => m[1].trim());
  assert.ok(hidden.length >= 4, hidden.join(" / "));
  for (const selector of hidden) {
    if (/prefers-reduced-motion/.test(selector)) continue;
    for (const part of selector.split(",")) assert.match(part, /\.live/, `«${part.trim()}» skjuler uten skript`);
  }
  assert.match(LANDING_STYLE, /\.landing:not\(\.live\) \.paddles \{ display: none; \}/, "pilene vises bare med skript");
});

test("bevegelsen: ett inline-skript med nonce fra CSP-en, selvstendig og uten __name", async () => {
  for (const path of ["/", "/for-klubber"]) {
    const { res, body } = await html(path);
    const nonce = /'nonce-([0-9a-f]+)'/.exec(res.headers.get("content-security-policy") ?? "")![1];
    const scripts = [...body.matchAll(/<script nonce="([0-9a-f]+)">([\s\S]*?)<\/script>/g)];
    assert.equal(scripts.length, 1, path);
    assert.equal(scripts[0][1], nonce, path);
    assert.equal(scripts[0][2], LANDING_SCRIPT, path);
  }
  assert.doesNotThrow(() => new Function(LANDING_SCRIPT), "skriptet er gyldig JavaScript");
  assert.doesNotMatch(LANDING_SCRIPT, /__name|import /);
  // Wrangler (esbuild) setter ellers inn __name(...) inne i funksjonen, og den finnes ikke i nettleseren.
  assert.match(readFileSync(new URL("../wrangler.toml", import.meta.url), "utf8"), /^keep_names = false$/m);
  // Andre sider har ikke salgssidens deler eller skript.
  const { body } = await html("/guide/golfliga");
  assert.doesNotMatch(body, /class="landing"|<script nonce/);
});

/** Bredde og høyde fra JPEG-hodet (SOF-markøren). */
function jpegSize(file: Buffer): [number, number] {
  for (let i = 2; i < file.length;) {
    const marker = file[i + 1], length = file.readUInt16BE(i + 2);
    if (marker >= 0xc0 && marker <= 0xc3) return [file.readUInt16BE(i + 7), file.readUInt16BE(i + 5)];
    i += 2 + length;
  }
  throw new Error("fant ikke størrelsen");
}

test("bildene: kopier fra web-admin, med riktig bredde og høyde og lazy-lasting", async () => {
  for (const p of [FAIRWAY, KVELD]) {
    const file = new URL(`../public${p.src}`, import.meta.url);
    assert.ok(existsSync(file), p.src);
    assert.deepEqual(jpegSize(readFileSync(file)), [p.width, p.height], p.src);
    assert.deepEqual(readFileSync(file), readFileSync(new URL(`../../admin/public${p.src}`, import.meta.url)), `${p.src} er lik på admin`);
  }
  const { body } = await html("/for-klubber");
  for (const img of body.match(/<img [^>]+>/g) ?? []) {
    assert.match(img, / width="\d+" height="\d+" loading="lazy" decoding="async"/, img);
    assert.match(img, / alt="[^"]+"/, img);
  }
});
