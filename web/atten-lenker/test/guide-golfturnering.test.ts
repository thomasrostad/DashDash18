// Kjøres med Node 24 uten Cloudflare: `npm test` (eller `node --test test/`).
import { test } from "node:test";
import assert from "node:assert/strict";
import worker, { APP_STORE_URL } from "../src/index.ts";

const BASE = "https://dashdash18.com";
const PATH = "/guide/golfturnering";

function get(path: string): Promise<Response> {
  return worker.fetch(new Request(BASE + path));
}

test("guiden til golfturnering svarer 200 og lenker videre", async () => {
  const res = await get(PATH);
  assert.equal(res.status, 200);
  const html = await res.text();
  assert.equal(html.match(/<h1>/g)?.length, 1, "én h1");
  const title = /<title>([^<]+)<\/title>/.exec(html)?.[1] ?? "";
  assert.ok(title.length >= 10 && title.length <= 70, `tittelen er ${title.length} tegn`);
  const description = /<meta name="description" content="([^"]+)">/.exec(html)?.[1] ?? "";
  assert.ok(description.length >= 50 && description.length <= 160, `beskrivelsen er ${description.length} tegn`);
  assert.ok(html.includes(`<link rel="canonical" href="${BASE}${PATH}">`));
  assert.ok(html.includes('href="/guide/spillformer"'));
  assert.ok(html.includes('href="/stableford"'));
  assert.ok(html.includes(`href="${APP_STORE_URL}"`));
  assert.doesNotMatch(html, /tipping|veddemål|betting|innsats|kroner/i);
});

test("guiden til golfturnering har Article som JSON-LD og står i sitemap", async () => {
  const html = await (await get(PATH)).text();
  const json = /<script type="application\/ld\+json"[^>]*>([^<]+)<\/script>/.exec(html)?.[1] ?? "{}";
  const data = JSON.parse(json);
  assert.equal(data["@type"], "Article");
  assert.equal(data.inLanguage, "nb");
  assert.equal(data.author?.name, "Atten");
  assert.equal(data.publisher?.name, "Atten");
  assert.equal(data.aggregateRating, undefined);
  assert.ok((await (await get("/sitemap.xml")).text()).includes(`<loc>${BASE}${PATH}</loc>`));
});
