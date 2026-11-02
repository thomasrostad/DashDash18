// Guiden til spillformene (src/innhold/guide-spillformer.ts). Kjøres med `npm test`.
import { test } from "node:test";
import assert from "node:assert/strict";
import worker, { APP_STORE_URL } from "../src/index.ts";
import { guideSpillformer } from "../src/innhold/guide-spillformer.ts";

const BASE = "https://dashdash18.com";

function get(path: string): Promise<Response> {
  return worker.fetch(new Request(BASE + path));
}

test("guiden svarer på /guide/spillformer, også med skråstrek til slutt", async () => {
  for (const path of ["/guide/spillformer", "/guide/spillformer/"]) {
    const res = await get(path);
    assert.equal(res.status, 200, path);
    assert.equal(res.headers.get("content-type"), "text/html; charset=utf-8");
  }
});

test("én h1 og en h2 for hver spillform", async () => {
  const html = await (await get("/guide/spillformer")).text();
  assert.equal((html.match(/<h1>/g) ?? []).length, 1);
  const h2 = [...html.matchAll(/<h2>([^<]+)<\/h2>/g)].map((m) => m[1]);
  for (const form of ["Stableford", "Slagspill", "Matchspill", "Fourball", "Foursome", "Greensome",
                      "Chapman", "Texas scramble", "Florida scramble", "Amerikaner"]) {
    assert.ok(h2.some((h) => h.startsWith(form)), `h2 for ${form}`);
  }
  // Oversiktstabellen bruker stilen for tabeller (.tabell).
  assert.match(html, /<div class="tabell"><table>/);
});

test("lenker til kalkulatoren, turneringsguiden og App Store", async () => {
  const html = await (await get("/guide/spillformer")).text();
  assert.ok(html.includes('href="/stableford"'));
  assert.ok(html.includes('href="/guide/golfturnering"'));
  assert.ok(html.includes(`href="${APP_STORE_URL}"`));
  assert.doesNotMatch(html, /<script[^>]*src=/, "ingen eksterne skript");
  assert.doesNotMatch(html, /<img/, "ingen bilder");
});

test("ingen spillformer med innsats", async () => {
  const html = await (await get("/guide/spillformer")).text();
  assert.doesNotMatch(html, /skins|nassau|wolf|tipping|veddemål|betting|innsats|pott/i);
});

test("tittel, beskrivelse og JSON-LD (Article uten vurderinger)", async () => {
  const p = guideSpillformer;
  assert.ok(p.title.length >= 10 && p.title.length <= 70, `tittel ${p.title.length} tegn`);
  assert.ok(p.description.length >= 50 && p.description.length <= 160, `beskrivelse ${p.description.length} tegn`);
  const ld = p.jsonLd ?? {};
  assert.equal(ld["@type"], "Article");
  assert.equal(ld.inLanguage, "nb");
  assert.equal(ld.datePublished, p.lastmod);
  assert.ok(ld.headline && ld.author && ld.publisher && ld.dateModified);
  assert.equal("aggregateRating" in ld, false);
  const html = await (await get("/guide/spillformer")).text();
  assert.match(html, /<script type="application\/ld\+json" nonce="[0-9a-f]+">\{"@context":"https:\/\/schema\.org","@type":"Article"/);
});
