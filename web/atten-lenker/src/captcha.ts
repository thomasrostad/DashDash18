import { escapeHTML } from "./html.ts";
// CAPTCHA for innlogging med e-postkode (1.0.1, `CaptchaFeature` i appen).
//
// Appen åpner `https://dashdash18.com/captcha?sitekey=…` i en liten WKWebView. Siden viser
// Cloudflare Turnstile og sender svaret tilbake til appen med
// `window.webkit.messageHandlers.atten.postMessage(...)`. Appen legger tokenet ved
// `signInWithOTP` som `captchaToken`. Site key-en kommer fra appkonfigen, ikke herfra, så samme
// side virker for test og prod.
//
// Meldingene til appen (`type`): "token" (med `token`), "error" (med `code`), "expired", "timeout"
// og "interactive" (Turnstile vil at du trykker; appen viser da widgeten).

export const TURNSTILE_ORIGIN = "https://challenges.cloudflare.com";
export const TURNSTILE_SCRIPT = `${TURNSTILE_ORIGIN}/turnstile/v0/api.js?render=explicit&onload=attenTurnstile`;

/// Site key-en slik Cloudflare lager dem (f.eks. `0x4AAAAAAA…`), eller null.
/// Testnøklene til Cloudflare (`1x00000000000000000000AA` osv.) godtas også.
export function normalizeSiteKey(raw: string | null): string | null {
  if (raw === null) return null;
  const key = raw.trim();
  return /^[0-9A-Za-z_-]{20,100}$/.test(key) ? key : null;
}

const HEADERS: Record<string, string> = {
  "X-Content-Type-Options": "nosniff",
  // Turnstile ser på hvilken side den ligger på. Bare opphavet sendes, aldri adressen med nøkkelen.
  "Referrer-Policy": "strict-origin",
  "X-Frame-Options": "DENY",
  "Cache-Control": "no-store",
};

function csp(nonce: string): string {
  return `default-src 'none'; style-src 'unsafe-inline'; script-src 'nonce-${nonce}' ${TURNSTILE_ORIGIN}; ` +
    `frame-src ${TURNSTILE_ORIGIN}; connect-src ${TURNSTILE_ORIGIN}; ` +
    "base-uri 'none'; form-action 'none'; frame-ancestors 'none'";
}

const STYLE = `
  :root { color-scheme: light dark; --skog: #1C483A; --krem: #FFF9DF; }
  * { box-sizing: border-box; }
  html, body { margin: 0; background: transparent; }
  body { display: flex; flex-direction: column; align-items: center; justify-content: center; min-height: 100vh;
    padding: 8px; color: var(--skog);
    font: 15px/1.4 -apple-system, BlinkMacSystemFont, "Helvetica Neue", Helvetica, Arial, sans-serif; }
  @media (prefers-color-scheme: dark) { body { color: var(--krem); } }
  #widget { min-height: 65px; }
  .info { margin: 8px 0 0; text-align: center; opacity: .8; }
`;

/// Skriptet på siden. Ingen data fra adressen havner i koden: nøkkelen leses fra `data-sitekey`.
const SCRIPT = `
  const handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.atten;
  function send(message) {
    if (handler) handler.postMessage(message);
  }
  if (!handler) {
    document.getElementById("info").hidden = false;
  }
  window.attenTurnstile = function () {
    const box = document.getElementById("widget");
    try {
      turnstile.render(box, {
        sitekey: box.dataset.sitekey,
        appearance: "interaction-only",
        callback: function (token) { send({ type: "token", token: token }); },
        "error-callback": function (code) { send({ type: "error", code: String(code) }); return true; },
        "expired-callback": function () { send({ type: "expired" }); },
        "timeout-callback": function () { send({ type: "timeout" }); },
        "before-interactive-callback": function () { send({ type: "interactive" }); },
      });
    } catch (error) {
      send({ type: "error", code: "render" });
    }
  };
  // Skriptlinja kommer etter denne koden, så feilen fanges på dokumentet (error bobler ikke, men fanges
  // på vei ned med «true»).
  document.addEventListener("error", function (event) {
    if (event.target && event.target.id === "turnstile-script") send({ type: "error", code: "load" });
  }, true);
`;

function captchaPage(siteKey: string, nonce: string): string {
  return `<!doctype html>
<html lang="nb">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex">
<title>Sikkerhetssjekk – Atten</title>
<style>${STYLE}</style>
</head>
<body>
<div id="widget" data-sitekey="${escapeHTML(siteKey)}"></div>
<p class="info" id="info" hidden>Denne siden brukes av Atten-appen ved innlogging.</p>
<script nonce="${nonce}">${SCRIPT}</script>
<script nonce="${nonce}" id="turnstile-script" src="${TURNSTILE_SCRIPT}" async defer></script>
</body>
</html>
`;
}

function missingKeyPage(): string {
  return `<!doctype html>
<html lang="nb">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex">
<title>Sikkerhetssjekk – Atten</title>
<style>${STYLE}</style>
</head>
<body>
<p class="info">Denne siden brukes av Atten-appen ved innlogging. Adressen mangler nøkkelen.</p>
</body>
</html>
`;
}

/// `/captcha?sitekey=…`. Ugyldig eller manglende nøkkel gir 400.
export function captchaResponse(url: URL, isHead: boolean): Response {
  const siteKey = normalizeSiteKey(url.searchParams.get("sitekey"));
  const nonce = crypto.randomUUID().replace(/-/g, "");
  const body = siteKey ? captchaPage(siteKey, nonce) : missingKeyPage();
  return new Response(isHead ? null : body, {
    status: siteKey ? 200 : 400,
    headers: { ...HEADERS, "Content-Type": "text/html; charset=utf-8", "Content-Security-Policy": csp(nonce) },
  });
}
