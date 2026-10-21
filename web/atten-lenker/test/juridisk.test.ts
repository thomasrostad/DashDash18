// Personvern, vilkår og support (src/juridisk.ts). Kjøres med `npm test`.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import worker from "../src/index.ts";
import { inlineHTML, markdownToHTML } from "../src/juridisk.ts";
import { PERSONVERN_MD, VILKAR_MD } from "../src/juridisk-tekst.ts";

const BASE = "https://dashdash18.com";

function get(path: string, method = "GET"): Promise<Response> {
  return worker.fetch(new Request(BASE + path, { method }));
}

test("overskrifter og avsnitt", () => {
  const html = markdownToHTML("# Tittel\n\nFørste linje\nfortsetter her.\n\n## Del 2\n\nTekst.");
  assert.equal(html, "<h1>Tittel</h1>\n<p>Første linje fortsetter her.</p>\n<h2>Del 2</h2>\n<p>Tekst.</p>");
});

test("lister", () => {
  const html = markdownToHTML("Før:\n\n- en\n- to, med **fet**\n\nEtter.");
  assert.equal(html, "<p>Før:</p>\n<ul>\n<li>en</li>\n<li>to, med <strong>fet</strong></li>\n</ul>\n<p>Etter.</p>");
});

test("tabell med overskriftsrad, skillelinje og rader, pakket inn for vannrett rulling", () => {
  const html = markdownToHTML("| A | B |\n|---|---|\n| 1 | *x* |\n| 2 | `y` |");
  assert.equal(html,
    '<div class="tabell"><table>\n<thead><tr><th scope="col">A</th><th scope="col">B</th></tr></thead>\n' +
    "<tbody>\n<tr><td>1</td><td><em>x</em></td></tr>\n<tr><td>2</td><td><code>y</code></td></tr>\n</tbody>\n</table></div>");
});

test("en løs |-linje uten skillelinje blir et avsnitt", () => {
  assert.equal(markdownToHTML("| ikke tabell"), "<p>| ikke tabell</p>");
});

test("fet, kursiv, kode og lenker", () => {
  assert.equal(inlineHTML("**Deg → Slett konto** og *Sist endret*"), "<strong>Deg → Slett konto</strong> og <em>Sist endret</em>");
  assert.equal(inlineHTML("`**ikke fet**`"), "<code>**ikke fet**</code>");
  assert.equal(inlineHTML("[Datatilsynet](https://www.datatilsynet.no)"), '<a href="https://www.datatilsynet.no">Datatilsynet</a>');
  assert.equal(inlineHTML("[vilkår](/vilkar)"), '<a href="/vilkar">vilkår</a>');
  assert.equal(inlineHTML("[farlig](javascript:alert)"), "farlig");
  assert.equal(inlineHTML("[Oslo tingrett]"), "[Oslo tingrett]");
});

test("all tekst escapes", () => {
  const html = markdownToHTML('# <script>alert(1)</script>\n\nHei <script>x</script> & "du"\n\n- <img src=x onerror=alert(1)>\n\n| <b> |\n|---|\n| `<i>` |');
  assert.doesNotMatch(html, /<script|<img|<b>|<i>/);
  assert.ok(html.includes("&lt;script&gt;alert(1)&lt;/script&gt;"));
  assert.ok(html.includes("&amp; &quot;du&quot;"));
  assert.ok(html.includes("<code>&lt;i&gt;</code>"));
  assert.equal(inlineHTML('[x](https://a.no/"onmouseover=")'), '<a href="https://a.no/&quot;onmouseover=&quot;">x</a>');
});

test("juridisk-tekst.ts er generert fra docs/ (kjør `npm run juridisk`)", () => {
  const docs = new URL("../../../docs/", import.meta.url);
  assert.equal(PERSONVERN_MD, readFileSync(new URL("personvern.md", docs), "utf8"));
  assert.equal(VILKAR_MD, readFileSync(new URL("vilkar.md", docs), "utf8"));
});

test("skriptet varsler om uutfylte hakeparenteser, og --strict feiler", () => {
  const script = fileURLToPath(new URL("../scripts/juridisk.mjs", import.meta.url));
  const hasPlaceholders = /\[[^\]\n]*\](?!\()/.test(PERSONVERN_MD + VILKAR_MD);
  const dir = mkdtempSync(join(tmpdir(), "juridisk-"));
  let status = 0;
  let stderr = "";
  try {
    execFileSync(process.execPath, [script, "--strict", "--out", join(dir, "tekst.ts")], { stdio: "pipe" });
  } catch (error) {
    status = (error as { status: number }).status;
    stderr = String((error as { stderr: Buffer }).stderr);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
  if (hasPlaceholders) {
    assert.equal(status, 1);
    assert.match(stderr, /ADVARSEL: \d+ uutfylte hakeparenteser/);
  } else {
    assert.equal(status, 0);
  }
});

test("/personvern, /vilkar og /support, med og uten / til slutt", async () => {
  const cases: [string, RegExp][] = [
    ["/personvern", /<h1>Personvernerklæring for Atten<\/h1>/],
    ["/personvern/", /<h1>Personvernerklæring for Atten<\/h1>/],
    ["/vilkar", /<h1>Vilkår for bruk av Atten<\/h1>/],
    ["/vilkar/", /<h1>Vilkår for bruk av Atten<\/h1>/],
    ["/support", /<h1>Support for Atten<\/h1>/],
    ["/support/", /<h1>Support for Atten<\/h1>/],
  ];
  for (const [path, heading] of cases) {
    const res = await get(path);
    assert.equal(res.status, 200, path);
    assert.equal(res.headers.get("content-type"), "text/html; charset=utf-8", path);
    assert.equal(res.headers.get("cache-control"), "public, max-age=3600", path);
    assert.equal(res.headers.get("x-content-type-options"), "nosniff", path);
    assert.equal(res.headers.get("x-frame-options"), "DENY", path);
    assert.match(res.headers.get("content-security-policy") ?? "", /default-src 'none'.*script-src 'nonce-/, path);
    assert.equal(res.headers.get("set-cookie"), null, path);
    const html = await res.text();
    assert.match(html, heading, path);
    assert.match(html, /<main class="dok">/, path);
    assert.doesNotMatch(html, /<script/, path);
  }
});

test("personvern: tabellen kan rulles, og utkastsmerknaden vises ikke", async () => {
  const html = await (await get("/personvern")).text();
  assert.match(html, /<title>Personvernerklæring for Atten<\/title>/);
  assert.match(html, /<div class="tabell"><table>/);
  assert.match(html, /<em>Sist endret: 21\. oktober 2026\.<\/em>/);
  assert.doesNotMatch(html, /Utkast|LegalLinks/);
  assert.match(await (await get("/vilkar")).text(), /<strong>ikke lov<\/strong>/);
});

test("support: kontakt, sletting, rapportering og lenker", async () => {
  const html = await (await get("/support")).text();
  assert.ok(html.includes('href="mailto:personvern@dashdash18.com"'));
  assert.match(html, /Deg → Slett konto/);
  assert.match(html, /Hold inne på en melding i tråden/);
  assert.ok(html.includes('href="/personvern"'));
  assert.ok(html.includes('href="/vilkar"'));
});

test("HEAD gir tomt svar, og undersider gir 404", async () => {
  const head = await get("/personvern", "HEAD");
  assert.equal(head.status, 200);
  assert.equal(await head.text(), "");
  for (const path of ["/personvern/x", "/vilkar/x", "/support/x", "/Personvern", "/personvern.html"]) {
    const res = await get(path);
    assert.equal(res.status, 404, path);
    assert.match(await res.text(), /Fant ikke siden/, path);
  }
});
