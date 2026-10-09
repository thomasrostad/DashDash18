// Kjøres med Node 24 uten Cloudflare: `npm test` (eller `node --test test/`).
import { test } from "node:test";
import assert from "node:assert/strict";
import worker, { normalizeCode, APP_ID } from "../src/index.ts";

const BASE = "https://dashdash18.com";

function get(path: string, method = "GET"): Promise<Response> {
  return worker.fetch(new Request(BASE + path, { method }));
}

test("AASA på begge adressene, som JSON uten omdirigering", async () => {
  for (const path of ["/.well-known/apple-app-site-association", "/apple-app-site-association"]) {
    const res = await get(path);
    assert.equal(res.status, 200, path);
    assert.equal(res.headers.get("content-type"), "application/json");
    assert.equal(res.headers.get("cache-control"), "public, max-age=3600");
    assert.equal(res.headers.get("location"), null);
    assert.equal(res.headers.get("set-cookie"), null);
    const body = await res.json();
    assert.deepEqual(body, {
      applinks: {
        details: [
          {
            appIDs: [APP_ID],
            components: [{ "/": "/klubb/*" }, { "/": "/runde/*" }, { "/": "/konkurranse/*" }],
          },
        ],
      },
    });
  }
  assert.equal(APP_ID, "JNMQJPCV24.com.dashdash18.app");
});

test("invitasjonsside for klubb, runde og konkurranse", async () => {
  const cases: [string, string, string][] = [
    ["/klubb/ABCDEF123456", "ABCDEF123456", "dashdash://klubb/ABCDEF123456"],
    ["/runde/ABCDE12345", "ABCDE-12345", "dashdash://runde/ABCDE12345"],
    ["/konkurranse/ABCDE12345/", "ABCDE-12345", "dashdash://konkurranse/ABCDE12345"],
  ];
  for (const [path, shown, appLink] of cases) {
    const res = await get(path);
    assert.equal(res.status, 200, path);
    assert.equal(res.headers.get("content-type"), "text/html; charset=utf-8");
    assert.equal(res.headers.get("set-cookie"), null);
    const csp = res.headers.get("content-security-policy") ?? "";
    assert.match(csp, /default-src 'none'/);
    const html = await res.text();
    assert.match(html, /Du er invitert til Atten/);
    assert.ok(html.includes(`<span class="kode">${shown}</span>`), `${path}: koden vises`);
    assert.ok(html.includes(`href="${appLink}"`), `${path}: lenke til appen`);
    assert.match(html, /Åpne i Atten/);
    assert.match(html, /TestFlight-invitasjon/);
    // Ingen eksterne skript eller ressurser.
    assert.doesNotMatch(html, /<script[^>]*src=/);
    assert.doesNotMatch(html, /https?:\/\//);
    // Det innebygde skriptet har nonce-en fra CSP-en.
    const nonce = /'nonce-([0-9a-f]+)'/.exec(csp)?.[1];
    assert.ok(nonce && html.includes(`<script nonce="${nonce}">`));
  }
});

test("koden tolkes som i appen", () => {
  assert.equal(normalizeCode("runde", "abcde-fghjk"), "ABCDEFGHJK");
  assert.equal(normalizeCode("runde", "ABCDE OIL23"), "ABCDE01123");
  assert.equal(normalizeCode("runde", "ABCDEFGHJ"), null); // 9 tegn
  assert.equal(normalizeCode("runde", "ABCDEFGHJKM"), null); // 11 tegn
  assert.equal(normalizeCode("konkurranse", "ABCDEFGHJU"), null); // U finnes ikke
  assert.equal(normalizeCode("klubb", "abc-def"), "ABCDEF");
  assert.equal(normalizeCode("klubb", "ABCDE"), null); // for kort
  assert.equal(normalizeCode("klubb", "A".repeat(17)), null); // for lang
  assert.equal(normalizeCode("klubb", "ABCDEFÆØ"), null);
  assert.equal(normalizeCode("klubb", "ABC<DEF>"), null);
});

test("små bokstaver i adressen gir koden med store", async () => {
  const html = await (await get("/runde/abcde-12345")).text();
  assert.ok(html.includes('href="dashdash://runde/ABCDE12345"'));
});

test("ugyldig kode gir en vennlig feilside", async () => {
  for (const path of ["/runde/FOR-KORT", "/konkurranse/ABCDEFGHJU", "/klubb/%3Cscript%3E", "/klubb/", "/runde/%E0%A4%A"]) {
    const res = await get(path);
    assert.equal(res.status, 404, path);
    const html = await res.text();
    assert.match(html, /Denne invitasjonen virker ikke/, path);
    assert.doesNotMatch(html, /<script>/, path);
    assert.doesNotMatch(html, /dashdash:\/\//, path);
  }
});

test("forsiden", async () => {
  const res = await get("/");
  assert.equal(res.status, 200);
  const html = await res.text();
  assert.match(html, /<h1>Atten<\/h1>/);
  assert.doesNotMatch(html, /<script/);
  assert.doesNotMatch(html, /Personvern/); // ikke publisert ennå
});

test("alt annet er 404", async () => {
  for (const path of ["/klubb", "/runde/ABCDE12345/mer", "/Runde/ABCDE12345", "/favicon.ico", "/index.html", "/.well-known/"]) {
    const res = await get(path);
    assert.equal(res.status, 404, path);
    assert.match(await res.text(), /Fant ikke siden/, path);
  }
});

test("HEAD uten innhold, andre metoder avvises", async () => {
  const head = await get("/.well-known/apple-app-site-association", "HEAD");
  assert.equal(head.status, 200);
  assert.equal(head.headers.get("content-type"), "application/json");
  assert.equal(await head.text(), "");
  const post = await get("/", "POST");
  assert.equal(post.status, 405);
  assert.equal(post.headers.get("allow"), "GET, HEAD");
});
