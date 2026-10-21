import { fetchTVPayload, normalizeTVCode, tvBoardPage, tvCodePage, type TVEnv } from "./tv.ts";
import { calendarResponse } from "./kalender.ts";
import { fetchSharePayload, REFRESH_SECONDS, shareInvalidPage, sharePage, type SharePayload } from "./tavla.ts";
import { escapeHTML } from "./html.ts";
import { legalPage } from "./juridisk.ts";
import { captchaResponse } from "./captcha.ts";
// Atten på https://dashdash18.com: filen som kobler domenet til appen (universelle lenker),
// og en enkel side for invitasjonslenker når appen ikke er installert.
//
// Ingen sporing, ingen cookies, ingen eksterne skript eller fonter. Unntaket er /captcha, som laster
// Cloudflare Turnstile (src/captcha.ts).

/// Teksten til den som ikke har appen. Bytt til App Store-lenken når appen er ute,
/// f.eks. `Last ned Atten fra <a href="https://apps.apple.com/…">App Store</a>.` (HTML er lov her).
export const GET_THE_APP_HTML =
  'Har du ikke appen? Last ned Atten fra <a href="https://apps.apple.com/no/app/atten/id6820031728" rel="noopener">App Store</a>.';

export const APP_ID = "JNMQJPCV24.com.dashdash18.app";

/// App Store-id-en til Atten (apps.apple.com/no/app/atten/id6820031728).
export const APP_STORE_ID = "6820031728";
export const APP_STORE_URL = `https://apps.apple.com/no/app/atten/id${APP_STORE_ID}`;
const SITE = "https://dashdash18.com";

/// Smart App Banner i Safari: «Hent» eller «Åpne» øverst på siden. `appArgument` sendes til appen når
/// den åpnes fra banneret (samme https-adresse som de universelle lenkene).
function smartBanner(appArgument?: string): string {
  const content = appArgument ? `app-id=${APP_STORE_ID}, app-argument=${appArgument}` : `app-id=${APP_STORE_ID}`;
  return `<meta name="apple-itunes-app" content="${escapeHTML(content)}">`;
}
const APP_SCHEME = "dashdash";

/// Samme alfabet og lengde som `InviteCode` i appen (Crockford base32 uten I, L, O og U).
const INVITE_ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";
const INVITE_LENGTH = 10;

type InviteKind = "klubb" | "runde" | "konkurranse";

/// Følgekoden (sql/054, `follow_codes`): 8 tegn uten I, O, 0 og 1. Samme som `FollowLink` i appen.
const FOLLOW_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
const FOLLOW_LENGTH = 8;

/// Følgekoden slik appen tolker den, eller null.
export function normalizeFollowCode(raw: string): string | null {
  const cleaned = raw.toUpperCase().replace(/[\s-]/g, "");
  if (cleaned.length !== FOLLOW_LENGTH) return null;
  for (const char of cleaned) {
    if (!FOLLOW_ALPHABET.includes(char)) return null;
  }
  return cleaned;
}

export const AASA = {
  applinks: {
    details: [
      {
        appIDs: [APP_ID],
        components: [{ "/": "/klubb/*" }, { "/": "/runde/*" }, { "/": "/konkurranse/*" }, { "/": "/folg/*" }],
      },
    ],
  },
};

const AASA_PATHS = new Set(["/.well-known/apple-app-site-association", "/apple-app-site-association"]);

const KINDS: Record<InviteKind, { what: string; joinHint: string; steps?: string[] }> = {
  klubb: { what: "en klubb", joinHint: "Eller skriv inn koden i appen når du blir med i en klubb." },
  runde: { what: "en runde", joinHint: "Eller skriv inn koden under Spill → «Har du en kode?»." },
  konkurranse: {
    what: "en turnering",
    joinHint: "Eller skriv inn koden under Turneringer → «Har du en kode?».",
    // sql/060: arrangøren har ofte lagt deg inn fra før. Du tar plassen din og fører ditt eget kort.
    steps: [
      "Hent Atten og logg inn med Apple eller e-post. Det tar et minutt.",
      "Trykk på lenken igjen, eller «Åpne i Atten» under.",
      "Velg navnet ditt på lista, eller meld deg på som ny.",
      "Før ditt eget kort og følg tabellen underveis.",
    ],
  },
};

/// Koden slik appen tolker den, eller null når den ikke kan være en kode av denne typen.
/// Klubb: `ClubInput.normalizedJoinCode` (6–16 bokstaver og tall). Runde og konkurranse:
/// `InviteCode` (10 tegn, O blir 0, I og L blir 1).
export function normalizeCode(kind: InviteKind, raw: string): string | null {
  const cleaned = raw.toUpperCase().replace(/[\s-]/g, "");
  if (kind === "klubb") {
    return /^[A-Z0-9]{6,16}$/.test(cleaned) ? cleaned : null;
  }
  const mapped = cleaned.replace(/O/g, "0").replace(/[IL]/g, "1");
  if (mapped.length !== INVITE_LENGTH) return null;
  for (const char of mapped) {
    if (!INVITE_ALPHABET.includes(char)) return null;
  }
  return mapped;
}

/// «ABCDE-FGHJK» for runde- og konkurransekoder, som i appen. Klubbkoden vises som den er.
function displayCode(kind: InviteKind, code: string): string {
  if (kind === "klubb") return code;
  return `${code.slice(0, INVITE_LENGTH / 2)}-${code.slice(INVITE_LENGTH / 2)}`;
}

const SECURITY_HEADERS: Record<string, string> = {
  "X-Content-Type-Options": "nosniff",
  "Referrer-Policy": "no-referrer",
  "X-Frame-Options": "DENY",
};

function htmlResponse(body: string, status: number, nonce: string, cache: string, isHead: boolean,
                      connectSelf = false, fontSelf = false): Response {
  return new Response(isHead ? null : body, {
    status,
    headers: {
      ...SECURITY_HEADERS,
      "Content-Type": "text/html; charset=utf-8",
      "Cache-Control": cache,
      "Content-Security-Policy":
        `default-src 'none'; style-src 'unsafe-inline'; script-src 'nonce-${nonce}'; ` +
        (connectSelf ? "connect-src 'self'; " : "") +
        (fontSelf ? "font-src 'self'; " : "") +
        "base-uri 'none'; form-action 'none'; frame-ancestors 'none'",
    },
  });
}

const STYLE = `
  :root { color-scheme: light; --skog: #1C483A; --krem: #FFF9DF; --gul: #F5C842; }
  * { box-sizing: border-box; }
  body { margin: 0; min-height: 100vh; display: flex; align-items: center; justify-content: center;
    padding: 24px 16px; background: var(--skog); color: var(--krem);
    font: 17px/1.5 -apple-system, BlinkMacSystemFont, "Helvetica Neue", Helvetica, Arial, sans-serif; }
  main { width: 100%; max-width: 420px; text-align: center; }
  .merke { font-weight: 800; letter-spacing: .02em; font-size: 15px; text-transform: uppercase; color: var(--gul); margin: 0 0 24px; }
  h1 { font-size: 28px; line-height: 1.2; margin: 0 0 8px; }
  p { margin: 0 0 16px; }
  .kode { display: block; margin: 24px 0 8px; padding: 16px; border-radius: 16px; background: var(--krem); color: var(--skog);
    font: 700 32px/1.2 ui-monospace, "SF Mono", Menlo, monospace; letter-spacing: .06em; user-select: all; -webkit-user-select: all;
    overflow-wrap: anywhere; }
  .kopier { appearance: none; border: 0; background: none; color: var(--krem); font: inherit; font-size: 15px;
    text-decoration: underline; cursor: pointer; padding: 8px; }
  .knapp { display: block; margin: 24px 0 16px; padding: 16px; border-radius: 999px; background: var(--gul); color: var(--skog);
    font-weight: 700; text-decoration: none; }
  .liten { font-size: 15px; opacity: .85; }
  .steg { text-align: left; margin: 0 0 16px; padding-left: 24px; }
  .steg li { margin: 0 0 8px; }
  a { color: var(--gul); }
  .lenker a { margin: 0 8px; }
  /* Personvern, vilkår og support (src/juridisk.ts): lengre tekst, venstrestilt. */
  main.dok { max-width: 680px; text-align: left; }
  .dok h2 { font-size: 21px; line-height: 1.3; margin: 32px 0 8px; }
  .dok ul { margin: 0 0 16px; padding-left: 24px; }
  .dok li { margin: 0 0 6px; }
  .dok code { font: .9em ui-monospace, "SF Mono", Menlo, monospace; }
  .tabell { overflow-x: auto; -webkit-overflow-scrolling: touch; margin: 0 0 16px; }
  .tabell table { border-collapse: collapse; min-width: 560px; font-size: 15px; line-height: 1.4; }
  .tabell th, .tabell td { text-align: left; vertical-align: top; padding: 8px 12px 8px 0; border-bottom: 1px solid rgba(255, 249, 223, .25); }
  .tabell th { color: var(--gul); }
`;

/// `index`: siden skal vises i Google (bare forsiden). `head`: ekstra meta-tagger (allerede escapet).
function page(title: string, content: string, nonce: string, script = "", mainClass = "",
              options: { index?: boolean; head?: string } = {}): string {
  return `<!doctype html>
<html lang="nb">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
${options.index ? "" : '<meta name="robots" content="noindex">\n'}${options.head ?? ""}
<meta name="theme-color" content="#1C483A">
<title>${escapeHTML(title)}</title>
<style>${STYLE}</style>
</head>
<body>
<main${mainClass ? ` class="${mainClass}"` : ""}>
<p class="merke">Atten</p>
${content}
</main>
${script ? `<script nonce="${nonce}">${script}</script>` : ""}
</body>
</html>
`;
}

const COPY_SCRIPT = `
  const knapp = document.getElementById("kopier");
  if (knapp && navigator.clipboard) {
    knapp.hidden = false;
    knapp.addEventListener("click", async () => {
      try {
        await navigator.clipboard.writeText(knapp.dataset.kode);
        knapp.textContent = "Kopiert";
      } catch {
        knapp.textContent = "Marker koden og kopier den";
      }
    });
  }
`;

function invitePage(kind: InviteKind, code: string, nonce: string): string {
  const info = KINDS[kind];
  const appLink = `${APP_SCHEME}://${kind}/${code}`;
  const content = `
<h1>Du er invitert til Atten</h1>
<p>Noen vil ha deg med i ${info.what}. Åpne invitasjonen i appen, eller bruk koden.</p>
<span class="kode">${escapeHTML(displayCode(kind, code))}</span>
<button type="button" class="kopier" id="kopier" data-kode="${escapeHTML(code)}" hidden>Kopier koden</button>
<a class="knapp" href="${escapeHTML(appLink)}">Åpne i Atten</a>
${info.steps ? `<ol class="steg">${info.steps.map((step) => `<li>${escapeHTML(step)}</li>`).join("")}</ol>` : ""}
<p class="liten">${escapeHTML(info.joinHint)}</p>
<p class="liten">${GET_THE_APP_HTML}</p>`;
  return page("Invitasjon til Atten", content, nonce, COPY_SCRIPT, "",
              { head: smartBanner(`${SITE}/${kind}/${code}`) + "\n" });
}

/// `/folg/KODE`: QR-koden for å følge noen. Appen åpner lenken selv; uten appen vises denne.
function followPage(code: string, nonce: string): string {
  const appLink = `${APP_SCHEME}://folg/${code}`;
  const content = `
<h1>Åpne Atten for å følge</h1>
<p>Noen vil at du skal følge dem i Atten.</p>
<span class="kode">${escapeHTML(`${code.slice(0, FOLLOW_LENGTH / 2)}-${code.slice(FOLLOW_LENGTH / 2)}`)}</span>
<a class="knapp" href="${escapeHTML(appLink)}">Åpne i Atten</a>
<p class="liten">Eller skriv inn koden under Deg → Følger → Skann kode.</p>
<p class="liten">${GET_THE_APP_HTML}</p>`;
  return page("Følg i Atten", content, nonce);
}

function invalidInvitePage(nonce: string): string {
  const content = `
<h1>Denne invitasjonen virker ikke</h1>
<p>Lenken er ufullstendig eller feil. Be den som inviterte deg om å sende den på nytt, eller om koden.</p>
<p class="liten">${GET_THE_APP_HTML}</p>`;
  return page("Ugyldig invitasjon – Atten", content, nonce);
}

const HOME_TITLE = "Atten – golfapp for golfgjengen: turnering, scorekort og tavle";
const HOME_DESCRIPTION =
  "Atten samler golfkvelden med gjengen: påmelding, båser, scorekort hull for hull og en tavle som oppdateres mens dere spiller. Liga og cup hele sesongen.";

/// Forsiden er den eneste siden Google skal finne. Ordene her er de samme som i App Store
/// (golfturnering, scorekort, tavle, liga, golfgjeng), så nettsøk og App Store-søk peker samme vei.
function homePage(nonce: string): string {
  const head = [
    `<meta name="description" content="${escapeHTML(HOME_DESCRIPTION)}">`,
    `<link rel="canonical" href="${SITE}/">`,
    `<meta property="og:type" content="website">`,
    `<meta property="og:url" content="${SITE}/">`,
    `<meta property="og:title" content="${escapeHTML(HOME_TITLE)}">`,
    `<meta property="og:description" content="${escapeHTML(HOME_DESCRIPTION)}">`,
    `<meta property="og:locale" content="nb_NO">`,
    smartBanner(),
    "",
  ].join("\n");
  const content = `
<h1>Golfkvelden med gjengen, samlet i én app</h1>
<p>Atten er golfappen for gjengen som spiller sammen hele sesongen. Påmelding, båser, scorekort og tavle, uten regneark.</p>
<a class="knapp" href="${APP_STORE_URL}" rel="noopener">Last ned Atten fra App Store</a>
<ul class="steg">
<li><strong>Påmelding og båser:</strong> meld deg på kvelden og se hvem du spiller med.</li>
<li><strong>Scorekort hull for hull:</strong> stableford, slagspill og matchspill med handicap.</li>
<li><strong>Tavla:</strong> resultatene oppdateres mens dere spiller.</li>
<li><strong>Liga og cup:</strong> golfturnering over hele sesongen, med vinnerjakke til slutt.</li>
<li><strong>Gjengen:</strong> inviter med lenke og start en ny golfgjeng på et minutt.</li>
</ul>
<p class="liten">Gratis for iPhone. Ingen reklame og ingen sporing.</p>
<p class="liten lenker"><a href="/personvern">Personvern</a> <a href="/vilkar">Vilkår</a> <a href="/support">Support</a></p>`;
  return page(HOME_TITLE, content, nonce, "", "", { index: true, head });
}

const ROBOTS_TXT = `User-agent: *
Allow: /
Disallow: /tavla/
Disallow: /tv/
Disallow: /kalender/
Disallow: /captcha

Sitemap: ${SITE}/sitemap.xml
`;

const SITEMAP_XML = `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
<url><loc>${SITE}/</loc></url>
</urlset>
`;

function textResponse(body: string, contentType: string, isHead: boolean): Response {
  return new Response(isHead ? null : body, {
    status: 200,
    headers: { ...SECURITY_HEADERS, "Content-Type": contentType, "Cache-Control": "public, max-age=86400" },
  });
}

function notFoundPage(nonce: string): string {
  const content = `
<h1>Fant ikke siden</h1>
<p><a href="/">Til forsiden</a></p>`;
  return page("Fant ikke siden – Atten", content, nonce);
}

/// `/klubb/KODE`, `/runde/KODE` eller `/konkurranse/KODE` (også med / til slutt). null: ikke en invitasjonsadresse.
function matchInvite(pathname: string): { kind: InviteKind; raw: string } | null {
  const match = /^\/(klubb|runde|konkurranse)\/([^/]*)\/?$/.exec(pathname);
  if (!match) return null;
  let raw: string;
  try {
    raw = decodeURIComponent(match[2]);
  } catch {
    raw = "";
  }
  return { kind: match[1] as InviteKind, raw };
}

export async function handle(request: Request, env: TVEnv = {}): Promise<Response> {
  const method = request.method.toUpperCase();
  const isHead = method === "HEAD";
  if (method !== "GET" && !isHead) {
    return new Response(null, { status: 405, headers: { ...SECURITY_HEADERS, Allow: "GET, HEAD" } });
  }

  const url = new URL(request.url);
  const { pathname } = url;

  // Lastes ned av Apple (via CDN-et deres) når appen installeres. Må være JSON uten omdirigering.
  if (AASA_PATHS.has(pathname)) {
    return new Response(isHead ? null : JSON.stringify(AASA), {
      status: 200,
      headers: {
        ...SECURITY_HEADERS,
        "Content-Type": "application/json",
        "Cache-Control": "public, max-age=3600",
      },
    });
  }

  // For søkemotorer: bare forsiden skal indekseres.
  if (pathname === "/robots.txt") return textResponse(ROBOTS_TXT, "text/plain; charset=utf-8", isHead);
  if (pathname === "/sitemap.xml") return textResponse(SITEMAP_XML, "application/xml; charset=utf-8", isHead);

  // Kalenderabonnement (steg 10, sql/051): personlig lenke, iCalendar.
  const calendar = /^\/kalender\/([^/]+)\.ics$/.exec(pathname);
  if (calendar) {
    return calendarResponse(calendar[1], env, isHead);
  }

  // CAPTCHA (Turnstile) for innlogging med e-postkode. Appen åpner siden i en WKWebView.
  if (pathname === "/captcha" || pathname === "/captcha/") {
    return captchaResponse(url, isHead);
  }

  const nonce = crypto.randomUUID().replace(/-/g, "");

  if (pathname === "/") {
    return htmlResponse(homePage(nonce), 200, nonce, "public, max-age=3600", isHead);
  }

  // Personvern, vilkår og support (App Store). Teksten kommer fra docs/*.md via `npm run juridisk`.
  const legal = legalPage(pathname);
  if (legal) {
    return htmlResponse(page(legal.title, legal.content, nonce, "", "dok"), 200, nonce, "public, max-age=3600", isHead);
  }

  // TV-visning med kode (fase 26, sql/041).
  if (pathname === "/tv" || pathname === "/tv/") {
    return htmlResponse(tvCodePage(nonce), 200, nonce, "public, max-age=3600", isHead);
  }
  const tv = /^\/tv\/([^/]+?)(\.json)?$/.exec(pathname);
  if (tv) {
    const code = normalizeTVCode(tv[1]);
    if (tv[2]) {
      const payload = code ? await fetchTVPayload(code, env).catch(() => undefined) : null;
      if (payload === undefined) {
        return new Response(JSON.stringify({ error: "Fikk ikke hentet tabellen" }), {
          status: 502, headers: { ...SECURITY_HEADERS, "Content-Type": "application/json", "Cache-Control": "no-store" } });
      }
      return new Response(isHead ? null : JSON.stringify(payload ?? { error: "Ukjent kode" }), {
        status: payload ? 200 : 404,
        headers: { ...SECURITY_HEADERS, "Content-Type": "application/json", "Cache-Control": "no-store" },
      });
    }
    if (!code) return htmlResponse(tvCodePage(nonce), 404, nonce, "no-store", isHead);
    if (code !== tv[1]) return Response.redirect(new URL(`/tv/${code}`, request.url).toString(), 302);
    return htmlResponse(tvBoardPage(code, nonce), 200, nonce, "no-store", isHead, true);
  }

  // Tavla i nettleseren for tilskuere (sql/056): lenken fra «Del tavla» i appen.
  const share = /^\/tavla\/([^/]+?)(\.json)?\/?$/.exec(pathname);
  if (share) {
    let raw = "";
    try { raw = decodeURIComponent(share[1]); } catch { raw = ""; }
    const code = normalizeTVCode(raw);
    if (share[2]) return shareJSON(code, env, isHead);
    if (!code) return htmlResponse(shareInvalidPage(), 404, nonce, "public, max-age=300", isHead, false, true);
    if (code !== share[1]) return Response.redirect(new URL(`/tavla/${code}`, request.url).toString(), 302);
    return htmlResponse(sharePage(code, nonce), 200, nonce, "no-store", isHead, true, true);
  }

  const follow = /^\/folg\/([^/]*)\/?$/.exec(pathname);
  if (follow) {
    let raw = "";
    try {
      raw = decodeURIComponent(follow[1]);
    } catch {
      raw = "";
    }
    const code = normalizeFollowCode(raw);
    if (!code) return htmlResponse(invalidInvitePage(nonce), 404, nonce, "public, max-age=300", isHead);
    return htmlResponse(followPage(code, nonce), 200, nonce, "public, max-age=300", isHead);
  }

  const invite = matchInvite(pathname);
  if (invite) {
    const code = normalizeCode(invite.kind, invite.raw);
    if (!code) return htmlResponse(invalidInvitePage(nonce), 404, nonce, "public, max-age=300", isHead);
    return htmlResponse(invitePage(invite.kind, code, nonce), 200, nonce, "public, max-age=300", isHead);
  }

  return htmlResponse(notFoundPage(nonce), 404, nonce, "public, max-age=300", isHead);
}

const JSON_HEADERS = { ...SECURITY_HEADERS, "Content-Type": "application/json", "Cache-Control": "no-store" };

/**
 * /tavla/KODE.json. Mange tilskuere på samme lenke spør like ofte: svaret holdes i Cloudflares hurtigbuffer
 * (i datasenteret) i halve oppdateringstiden, så Supabase får høyst ett kall per kode per datasenter.
 */
async function shareJSON(code: string | null, env: TVEnv, isHead: boolean): Promise<Response> {
  if (!code) return new Response(isHead ? null : JSON.stringify({ error: "Ukjent kode" }), { status: 404, headers: JSON_HEADERS });
  const cache = (globalThis as { caches?: { default?: Cache } }).caches?.default;
  const key = new Request(`https://dashdash18.com/tavla/${code}.json`);
  const hit = cache ? await cache.match(key).catch(() => undefined) : undefined;
  let body: string | null = hit ? await hit.text() : null;
  let status = hit ? hit.status : 200;
  if (body === null) {
    let payload: SharePayload | null | undefined;
    try { payload = await fetchSharePayload(code, env); } catch { payload = undefined; }
    if (payload === undefined) {
      return new Response(JSON.stringify({ error: "Fikk ikke hentet tabellen" }), { status: 502, headers: JSON_HEADERS });
    }
    status = payload ? 200 : 404;
    body = JSON.stringify(payload ?? { error: "Ukjent kode" });
    if (cache) {
      const ttl = Math.floor(REFRESH_SECONDS / 2);
      await cache.put(key, new Response(body, { status, headers: { "Content-Type": "application/json", "Cache-Control": `public, max-age=${ttl}` } }))
        .catch(() => undefined);
    }
  }
  return new Response(isHead ? null : body, { status, headers: JSON_HEADERS });
}

export default {
  fetch(request: Request, env: TVEnv): Promise<Response> {
    return handle(request, env);
  },
};
