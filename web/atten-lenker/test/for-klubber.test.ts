// /for-klubber: siden svarer, har de to valgene og sier ingenting som ikke er dokumentert.
import { test } from "node:test";
import assert from "node:assert/strict";
import worker, { APP_STORE_URL } from "../src/index.ts";
import { ADMIN_URL, FOR_KLUBBER } from "../src/innhold/for-klubber.ts";

const BASE = "https://dashdash18.com";

async function html(path = "/for-klubber"): Promise<{ res: Response; body: string }> {
  const res = await worker.fetch(new Request(BASE + path));
  return { res, body: await res.text() };
}

test("/for-klubber svarer og kan indekseres", async () => {
  for (const path of ["/for-klubber", "/for-klubber/"]) {
    const { res, body } = await html(path);
    assert.equal(res.status, 200, path);
    assert.doesNotMatch(body, /<meta name="robots" content="noindex">/, path);
    assert.ok(body.includes(`<link rel="canonical" href="${BASE}/for-klubber">`), path);
  }
  const sitemap = await (await worker.fetch(new Request(BASE + "/sitemap.xml"))).text();
  assert.ok(sitemap.includes(`<loc>${BASE}/for-klubber</loc>`));
});

test("/for-klubber: begge handlingene, App Store og arrangør på web", async () => {
  const { body } = await html();
  assert.equal(ADMIN_URL, "https://admin.dashdash18.com");
  assert.ok(body.includes(`class="knapp" href="${APP_STORE_URL}"`), "App Store-knappen");
  assert.ok(body.includes(`class="knapp" href="${ADMIN_URL}"`), "Logg inn som arrangør");
  assert.ok(body.includes(">Logg inn som arrangør</a>"));
  assert.ok(body.includes('href="/guide/golfturnering"'));
  assert.ok(body.includes('href="/guide/golfliga"'));
});

test("/for-klubber: søkeordene står i tittel og overskrifter", () => {
  const h2 = [...FOR_KLUBBER.content.matchAll(/<h2>([^<]+)<\/h2>/g)].map((m) => m[1].toLowerCase()).join(" | ");
  for (const word of ["turneringssystem", "golfturnering", "golfsimulator", "golfliga"]) {
    assert.ok(h2.includes(word), `h2 med «${word}»: ${h2}`);
  }
  assert.match(FOR_KLUBBER.title, /golfklubber/i);
  assert.equal((FOR_KLUBBER.content.match(/<h1>/g) ?? []).length, 1);
});

test("/for-klubber: ingen priser, tall, vurderinger eller eksterne skript", async () => {
  const { body } = await html();
  const text = FOR_KLUBBER.content.replace(/<[^>]+>/g, " ").replace(/dashdash18/g, "");
  assert.doesNotMatch(text, /\bkr\b|kroner|NOK|,-|\bpris|abonnement|gratis|rabatt/i, "ingen priser");
  assert.doesNotMatch(text, /\d/, "ingen tall i teksten");
  assert.doesNotMatch(text, /stjerner|vurdering|anmeldelse|kunder|«[^»]*»\s*–/i, "ingen vurderinger eller sitater");
  assert.doesNotMatch(JSON.stringify(FOR_KLUBBER.jsonLd), /aggregateRating|review|ratingValue|offers|price/i);
  assert.doesNotMatch(body, /<script[^>]+src=/, "ingen eksterne skript");
});
