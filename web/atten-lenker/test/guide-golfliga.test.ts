// Guiden til golfliga og cup (src/innhold/guide-golfliga.ts). Kjøres med `npm test`.
import { test } from "node:test";
import assert from "node:assert/strict";
import worker, { APP_STORE_URL } from "../src/index.ts";

const BASE = "https://dashdash18.com";

test("guide golfliga: 200, lenker videre og App Store", async () => {
  const res = await worker.fetch(new Request(BASE + "/guide/golfliga"));
  assert.equal(res.status, 200);
  const html = await res.text();
  assert.equal((html.match(/<h1>/g) ?? []).length, 1);
  for (const href of ["/guide/golfturnering", "/guide/spillformer", "/stableford", APP_STORE_URL]) {
    assert.ok(html.includes(`href="${href}"`), href);
  }
  assert.match(html, /<script type="application\/ld\+json" nonce="[^"]+">\{"@context":"https:\/\/schema\.org","@type":"Article"/);
  assert.doesNotMatch(html, /aggregateRating|tipping|veddemål|betting|innsats/i);
});
