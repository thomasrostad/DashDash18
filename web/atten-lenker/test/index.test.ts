// Kjøres med Node 24 uten Cloudflare: `npm test` (eller `node --test test/`).
import { test } from "node:test";
import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";
import worker, { normalizeCode, normalizeFollowCode, APP_ID, APP_STORE_URL } from "../src/index.ts";

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
            components: [{ "/": "/klubb/*" }, { "/": "/runde/*" }, { "/": "/konkurranse/*" }, { "/": "/folg/*" }],
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
    assert.match(html, /href="https:\/\/apps\.apple\.com\/no\/app\/atten\/id6820031728"/);
    // Turneringen (sql/060): stegene for å ta plassen sin.
    assert.equal(html.includes("Velg navnet ditt på lista"), path.startsWith("/konkurranse/"), `${path}: stegene`);
    // Ingen eksterne skript eller ressurser.
    assert.doesNotMatch(html, /<script[^>]*src=/);
    // Eneste lenke ut er App Store. Smart App Banner og del-kortet peker tilbake til dashdash18.com.
    assert.doesNotMatch(html.replaceAll("https://apps.apple.com/no/app/atten/id6820031728", "").replaceAll(BASE, ""), /https?:\/\//);
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
  assert.match(html, /<h1>Golfkvelden med gjengen/);
  assert.doesNotMatch(html, /<script/);
  // Søk: forsiden skal indekseres, ha beskrivelse, kanonisk adresse og lenke til App Store.
  assert.doesNotMatch(html, /noindex/);
  assert.match(html, /<meta name="description" content="[^"]{50,160}">/);
  assert.match(html, /<link rel="canonical" href="https:\/\/dashdash18\.com\/">/);
  assert.match(html, /<meta name="apple-itunes-app" content="app-id=6820031728">/);
  assert.ok(html.includes(`href="${APP_STORE_URL}"`), "forsiden lenker til App Store");
  for (const word of ["golfturnering", "Scorekort", "Tavla", "Liga", "golfgjeng"]) {
    assert.ok(html.includes(word), `forsiden har søkeordet ${word}`);
  }
  for (const path of ["/personvern", "/vilkar", "/support"]) {
    assert.ok(html.includes(`href="${path}"`), `forsiden lenker til ${path}`);
  }
});

test("alt annet er 404, med egen side i samme stil", async () => {
  for (const path of ["/klubb", "/runde/ABCDE12345/mer", "/Runde/ABCDE12345", "/index.html", "/.well-known/", "/kart.js.map"]) {
    const res = await get(path);
    assert.equal(res.status, 404, path);
    assert.equal(res.headers.get("content-type"), "text/html; charset=utf-8", path);
    const html = await res.text();
    assert.match(html, /<title>Fant ikke siden – Atten<\/title>/, path);
    assert.equal((html.match(/<h1>/g) ?? []).length, 1, path);
    assert.match(html, /<a class="knapp" href="\/">Til forsiden<\/a>/, path);
    assert.ok(html.includes(`href="${APP_STORE_URL}"`), `${path}: lenke til App Store`);
    assert.match(html, /<meta name="robots" content="noindex">/, path);
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

test("følgekoden (sql/054): side med lenke til appen, ugyldig kode gir 404", async () => {
  const res = await get("/folg/abcd-efgh");
  assert.equal(res.status, 200);
  const html = await res.text();
  assert.match(html, /Åpne Atten for å følge/);
  assert.ok(html.includes('<span class="kode">ABCD-EFGH</span>'));
  assert.ok(html.includes('href="dashdash://folg/ABCDEFGH"'));
  // Eneste lenke ut er App Store (resten er dashdash18.com i Smart App Banner og del-kortet).
  assert.doesNotMatch(html.replaceAll("https://apps.apple.com/no/app/atten/id6820031728", "").replaceAll(BASE, ""), /https?:\/\//);
  assert.equal((await get("/folg/ABCDEFG1")).status, 404);
  assert.equal((await get("/folg/")).status, 404);
  assert.equal(normalizeFollowCode(" abcd efgh "), "ABCDEFGH");
  assert.equal(normalizeFollowCode("ABCDEFGO"), null);
  assert.equal(normalizeFollowCode("ABCDEFGHJ"), null);
});

test("robots.txt og sitemap.xml: forsiden, personvern, vilkår og support indekseres", async () => {
  const robots = await get("/robots.txt");
  assert.equal(robots.status, 200);
  assert.match(robots.headers.get("content-type") ?? "", /^text\/plain/);
  const text = await robots.text();
  assert.match(text, /Sitemap: https:\/\/dashdash18\.com\/sitemap\.xml/);
  for (const path of ["/tavla/", "/tv/", "/kalender/"]) assert.ok(text.includes(`Disallow: ${path}`), path);
  const sitemap = await get("/sitemap.xml");
  assert.equal(sitemap.status, 200);
  assert.match(sitemap.headers.get("content-type") ?? "", /^application\/xml/);
  const xml = await sitemap.text();
  const locs = [...xml.matchAll(/<loc>([^<]+)<\/loc>/g)].map((m) => m[1]);
  assert.deepEqual(locs, INDEXED.map((path) => BASE + path));
  // Hver side i sitemap.xml svarer 200, kan indekseres og har seg selv som kanonisk adresse.
  for (const path of INDEXED) {
    const res = await get(path);
    assert.equal(res.status, 200, path);
    const html = await res.text();
    assert.doesNotMatch(html, /noindex/, path);
    assert.ok(html.includes(`<link rel="canonical" href="${BASE + path}">`), `${path}: kanonisk adresse`);
  }
});

test("invitasjoner: noindex og Smart App Banner som åpner riktig lenke", async () => {
  const res = await get("/runde/ABCDE12345");
  const html = await res.text();
  assert.match(html, /<meta name="robots" content="noindex">/);
  assert.match(html, /<meta name="apple-itunes-app" content="app-id=6820031728, app-argument=https:\/\/dashdash18\.com\/runde\/ABCDE12345">/);
});

test("andre sider er fortsatt noindex, og står ikke i sitemap.xml", async () => {
  for (const path of ["/finnes-ikke", "/runde/ABCDE12345", "/folg/ABCDEFGH", "/tv", "/tavla/ABCDE12345"]) {
    const html = await (await get(path)).text();
    assert.match(html, /<meta name="robots" content="noindex">/, path);
    assert.doesNotMatch(html, /rel="canonical"/, path);
  }
});

const INDEXED = ["/", "/personvern", "/vilkar", "/support"];

test("indekserte sider: egen tittel, beskrivelse og del-kort med bilde", async () => {
  const titles = new Set<string>();
  const descriptions = new Set<string>();
  for (const path of INDEXED) {
    const html = await (await get(path)).text();
    const title = /<title>([^<]+)<\/title>/.exec(html)?.[1] ?? "";
    const description = /<meta name="description" content="([^"]+)">/.exec(html)?.[1] ?? "";
    assert.ok(title.length >= 10 && title.length <= 70, `${path}: tittel «${title}»`);
    assert.ok(description.length >= 50 && description.length <= 160, `${path}: beskrivelse (${description.length} tegn)`);
    titles.add(title);
    descriptions.add(description);
    assert.equal((html.match(/<h1>/g) ?? []).length, 1, `${path}: én h1`);
    assert.ok(html.includes(`<meta property="og:url" content="${BASE + path}">`), `${path}: og:url`);
    assert.ok(html.includes(`<meta property="og:title" content="${title}">`), `${path}: og:title`);
    assert.ok(html.includes(`<meta property="og:description" content="${description}">`), `${path}: og:description`);
    assert.match(html, /<meta property="og:type" content="website">/, path);
    assert.match(html, /<meta property="og:image" content="https:\/\/dashdash18\.com\/og\.png">/, path);
    assert.match(html, /<meta name="twitter:card" content="summary_large_image">/, path);
  }
  assert.equal(titles.size, INDEXED.length, "titlene er unike");
  assert.equal(descriptions.size, INDEXED.length, "beskrivelsene er unike");
});

test("alle HTML-sider: lang=nb, tittel og ikoner som finnes i public/", async () => {
  for (const path of ["/", "/personvern", "/vilkar", "/support", "/runde/ABCDE12345", "/folg/ABCDEFGH",
                      "/runde/FEIL", "/finnes-ikke", "/tv", "/tv/ABCDE12345", "/tavla/ABCDE12345", "/tavla/x"]) {
    const res = await get(path);
    const html = await res.text();
    assert.match(html, /<html lang="nb">/, path);
    assert.match(html, /<title>[^<]*Atten[^<]*<\/title>/, path);
    assert.match(html, /<link rel="icon" href="\/favicon\.svg" type="image\/svg\+xml">/, path);
    assert.match(html, /<link rel="apple-touch-icon" href="\/apple-touch-icon\.png">/, path);
    assert.match(res.headers.get("content-security-policy") ?? "", /img-src 'self'/, path);
  }
  for (const file of ["favicon.ico", "favicon.svg", "apple-touch-icon.png", "og.png"]) {
    assert.ok(existsSync(new URL(`../public/${file}`, import.meta.url)), `public/${file}`);
  }
  // og.png er 1200 × 630 (bredde og høyde står i PNG-hodet).
  const png = readFileSync(new URL("../public/og.png", import.meta.url));
  assert.deepEqual([png.readUInt32BE(16), png.readUInt32BE(20)], [1200, 630]);
});

test("invitasjoner og følgekoden: egen tittel og del-kort", async () => {
  const cases: [string, string][] = [
    ["/klubb/ABCDEF123456", "Invitasjon til en klubb – Atten"],
    ["/runde/ABCDE12345", "Invitasjon til en runde – Atten"],
    ["/konkurranse/ABCDE12345", "Invitasjon til en turnering – Atten"],
    ["/folg/ABCDEFGH", "Følg i Atten"],
  ];
  for (const [path, title] of cases) {
    const html = await (await get(path)).text();
    assert.ok(html.includes(`<title>${title}</title>`), path);
    assert.ok(html.includes(`<meta property="og:title" content="${title}">`), path);
    assert.ok(html.includes(`<meta property="og:url" content="${BASE + path}">`), path);
  }
});

test("ingen ord om pengespill på sidene", async () => {
  for (const path of ["/", "/support", "/runde/ABCDE12345", "/finnes-ikke"]) {
    assert.doesNotMatch(await (await get(path)).text(), /tipping|veddemål|betting/i, path);
  }
});
