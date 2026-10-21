// Turnstile-siden for innlogging med e-postkode (1.0.1, `CaptchaFeature` i appen).
import { test } from "node:test";
import assert from "node:assert/strict";
import worker from "../src/index.ts";
import { normalizeSiteKey, TURNSTILE_ORIGIN, TURNSTILE_SCRIPT } from "../src/captcha.ts";

const BASE = "https://dashdash18.com";
const KEY = "0x4AAAAAAAabcdefghijKLMN";

function get(path: string, method = "GET"): Promise<Response> {
  return worker.fetch(new Request(BASE + path, { method }), {});
}

test("captcha-siden laster Turnstile med nøkkelen fra adressen", async () => {
  for (const path of [`/captcha?sitekey=${KEY}`, `/captcha/?sitekey=${KEY}`]) {
    const res = await get(path);
    assert.equal(res.status, 200, path);
    assert.equal(res.headers.get("content-type"), "text/html; charset=utf-8");
    assert.equal(res.headers.get("cache-control"), "no-store");
    assert.equal(res.headers.get("set-cookie"), null);
    assert.equal(res.headers.get("referrer-policy"), "strict-origin");
    const html = await res.text();
    assert.ok(html.includes(`data-sitekey="${KEY}"`), "nøkkelen ligger i data-sitekey");
    assert.ok(html.includes(`src="${TURNSTILE_SCRIPT}"`), "Turnstile-skriptet");
    assert.match(TURNSTILE_SCRIPT, /render=explicit/);
    assert.match(TURNSTILE_SCRIPT, /onload=attenTurnstile/);
    // Svaret går til appen gjennom WKScriptMessageHandler «atten».
    assert.match(html, /messageHandlers\.atten/);
    for (const type of ["token", "error", "expired", "timeout", "interactive"]) {
      assert.ok(html.includes(`type: "${type}"`), `melding ${type}`);
    }
    // Funksjonen onload peker på, er definert før Turnstile-skriptet lastes.
    assert.ok(html.indexOf("window.attenTurnstile") < html.indexOf(TURNSTILE_SCRIPT));
  }
});

test("CSP slipper bare inn Turnstile, og begge skriptene har nonce-en", async () => {
  const res = await get(`/captcha?sitekey=${KEY}`);
  const csp = res.headers.get("content-security-policy") ?? "";
  assert.match(csp, /default-src 'none'/);
  assert.match(csp, new RegExp(`script-src 'nonce-[0-9a-f]+' ${TURNSTILE_ORIGIN};`));
  assert.match(csp, new RegExp(`frame-src ${TURNSTILE_ORIGIN};`));
  assert.match(csp, /frame-ancestors 'none'/);
  const nonce = /'nonce-([0-9a-f]+)'/.exec(csp)?.[1];
  assert.ok(nonce);
  const html = await res.text();
  const scripts = html.match(/<script[^>]*>/g) ?? [];
  assert.equal(scripts.length, 2);
  for (const tag of scripts) assert.ok(tag.includes(`nonce="${nonce}"`), tag);
  // Ingen andre eksterne adresser enn Turnstile.
  const urls = html.match(/https?:\/\/[^\s"'<>]+/g) ?? [];
  assert.ok(urls.length > 0);
  for (const found of urls) assert.ok(found.startsWith(`${TURNSTILE_ORIGIN}/`), found);
});

test("manglende eller ugyldig nøkkel gir 400 uten skript", async () => {
  for (const path of ["/captcha", "/captcha?sitekey=", "/captcha?sitekey=kort", `/captcha?sitekey=${KEY}%22%3E%3Cscript%3E`]) {
    const res = await get(path);
    assert.equal(res.status, 400, path);
    const html = await res.text();
    assert.doesNotMatch(html, /<script/, path);
    assert.match(html, /mangler nøkkelen/);
  }
});

test("HEAD gir ingen kropp, og POST avvises", async () => {
  const head = await get(`/captcha?sitekey=${KEY}`, "HEAD");
  assert.equal(head.status, 200);
  assert.equal(await head.text(), "");
  const post = await get(`/captcha?sitekey=${KEY}`, "POST");
  assert.equal(post.status, 405);
});

test("nøkkelen tolkes strengt", () => {
  assert.equal(normalizeSiteKey(KEY), KEY);
  assert.equal(normalizeSiteKey(` ${KEY} `), KEY);
  assert.equal(normalizeSiteKey("1x00000000000000000000AA"), "1x00000000000000000000AA"); // Cloudflares testnøkkel
  assert.equal(normalizeSiteKey(null), null);
  assert.equal(normalizeSiteKey(""), null);
  assert.equal(normalizeSiteKey("0x4AAA"), null);
  assert.equal(normalizeSiteKey(`${KEY}<b>`), null);
  assert.equal(normalizeSiteKey("A".repeat(101)), null);
});
