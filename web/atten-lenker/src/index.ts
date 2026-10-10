import { fetchTVPayload, normalizeTVCode, tvBoardPage, tvCodePage, type TVEnv } from "./tv.ts";
// Atten på https://dashdash18.com: filen som kobler domenet til appen (universelle lenker),
// og en enkel side for invitasjonslenker når appen ikke er installert.
//
// Ingen sporing, ingen cookies, ingen eksterne skript eller fonter.

/// Teksten til den som ikke har appen. Bytt til App Store-lenken når appen er ute,
/// f.eks. `Last ned Atten fra <a href="https://apps.apple.com/…">App Store</a>.` (HTML er lov her).
export const GET_THE_APP_HTML =
  "Har du ikke appen? Atten er i testing – spør den som inviterte deg om en TestFlight-invitasjon.";

/// Personvernerklæringen, når den er publisert (samme adresse som `LegalLinks.privacy` i appen).
/// null: ingen lenke på forsiden.
export const PRIVACY_URL: string | null = null;

export const APP_ID = "JNMQJPCV24.com.dashdash18.app";
const APP_SCHEME = "dashdash";

/// Samme alfabet og lengde som `InviteCode` i appen (Crockford base32 uten I, L, O og U).
const INVITE_ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";
const INVITE_LENGTH = 10;

type InviteKind = "klubb" | "runde" | "konkurranse";

export const AASA = {
  applinks: {
    details: [
      {
        appIDs: [APP_ID],
        components: [{ "/": "/klubb/*" }, { "/": "/runde/*" }, { "/": "/konkurranse/*" }],
      },
    ],
  },
};

const AASA_PATHS = new Set(["/.well-known/apple-app-site-association", "/apple-app-site-association"]);

const KINDS: Record<InviteKind, { what: string; joinHint: string }> = {
  klubb: { what: "en klubb", joinHint: "Eller skriv inn koden i appen når du blir med i en klubb." },
  runde: { what: "en runde", joinHint: "Eller skriv inn koden under Spill → Bli med med kode." },
  konkurranse: { what: "en turnering", joinHint: "Eller skriv inn koden under Turneringer → Bli med med kode." },
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
                      connectSelf = false): Response {
  return new Response(isHead ? null : body, {
    status,
    headers: {
      ...SECURITY_HEADERS,
      "Content-Type": "text/html; charset=utf-8",
      "Cache-Control": cache,
      "Content-Security-Policy":
        `default-src 'none'; style-src 'unsafe-inline'; script-src 'nonce-${nonce}'; ` +
        (connectSelf ? "connect-src 'self'; " : "") +
        "base-uri 'none'; form-action 'none'; frame-ancestors 'none'",
    },
  });
}

function escapeHTML(text: string): string {
  return text
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
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
  a { color: var(--gul); }
`;

function page(title: string, content: string, nonce: string, script = ""): string {
  return `<!doctype html>
<html lang="nb">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex">
<meta name="theme-color" content="#1C483A">
<title>${escapeHTML(title)}</title>
<style>${STYLE}</style>
</head>
<body>
<main>
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
<p class="liten">${escapeHTML(info.joinHint)}</p>
<p class="liten">${GET_THE_APP_HTML}</p>`;
  return page("Invitasjon til Atten", content, nonce, COPY_SCRIPT);
}

function invalidInvitePage(nonce: string): string {
  const content = `
<h1>Denne invitasjonen virker ikke</h1>
<p>Lenken er ufullstendig eller feil. Be den som inviterte deg om å sende den på nytt, eller om koden.</p>
<p class="liten">${GET_THE_APP_HTML}</p>`;
  return page("Ugyldig invitasjon – Atten", content, nonce);
}

function homePage(nonce: string): string {
  const privacy = PRIVACY_URL ? `<p class="liten"><a href="${escapeHTML(PRIVACY_URL)}">Personvern</a></p>` : "";
  const content = `
<h1>Atten</h1>
<p>Atten er en app for å føre golfrunder og turneringer med gjengen.</p>
${privacy}`;
  return page("Atten", content, nonce);
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

  const { pathname } = new URL(request.url);

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

  const nonce = crypto.randomUUID().replace(/-/g, "");

  if (pathname === "/") {
    return htmlResponse(homePage(nonce), 200, nonce, "public, max-age=3600", isHead);
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

  const invite = matchInvite(pathname);
  if (invite) {
    const code = normalizeCode(invite.kind, invite.raw);
    if (!code) return htmlResponse(invalidInvitePage(nonce), 404, nonce, "public, max-age=300", isHead);
    return htmlResponse(invitePage(invite.kind, code, nonce), 200, nonce, "public, max-age=300", isHead);
  }

  return htmlResponse(notFoundPage(nonce), 404, nonce, "public, max-age=300", isHead);
}

export default {
  fetch(request: Request, env: TVEnv): Promise<Response> {
    return handle(request, env);
  },
};
