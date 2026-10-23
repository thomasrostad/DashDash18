import { useEffect, useRef } from "react";
import { CAPTCHA_TEXT, TURNSTILE_SCRIPT, captchaErrorText } from "./captcha.ts";

interface TurnstileApi {
  render(el: HTMLElement, options: Record<string, unknown>): string;
  remove(id: string): void;
}
declare global {
  interface Window { turnstile?: TurnstileApi; attenTurnstile?: () => void }
}

let loading: Promise<TurnstileApi> | null = null;

/** Skriptet lastes én gang. `TURNSTILE_SCRIPT` kaller `attenTurnstile` når det er klart. */
function loadTurnstile(): Promise<TurnstileApi> {
  if (window.turnstile) return Promise.resolve(window.turnstile);
  loading ??= new Promise((resolve, reject) => {
    window.attenTurnstile = () => (window.turnstile ? resolve(window.turnstile) : reject(new Error("load")));
    const script = document.createElement("script");
    script.src = TURNSTILE_SCRIPT;
    script.async = true;
    script.onerror = () => { loading = null; script.remove(); reject(new Error("load")); };
    document.head.appendChild(script);
  });
  return loading;
}

/** Cloudflare Turnstile før koden sendes. Nytt token: `onToken(token)`; utløpt eller feil: `onToken(null)`.
 *  Et token kan bare brukes én gang, så forelderen gir en ny `key` etter hvert forsøk. */
export function Turnstile({ siteKey, onToken, onError }: {
  siteKey: string; onToken: (token: string | null) => void; onError: (message: string | null) => void;
}) {
  const box = useRef<HTMLDivElement>(null);
  const handlers = useRef({ onToken, onError });
  handlers.current = { onToken, onError };

  useEffect(() => {
    let id: string | null = null;
    let live = true;
    loadTurnstile().then((api) => {
      if (!live || !box.current) return;
      id = api.render(box.current, {
        sitekey: siteKey,
        language: "nb",
        callback: (token: string) => { handlers.current.onError(null); handlers.current.onToken(token); },
        "error-callback": (code: unknown) => { handlers.current.onToken(null); handlers.current.onError(captchaErrorText(String(code))); return true; },
        "expired-callback": () => handlers.current.onToken(null),
        "timeout-callback": () => { handlers.current.onToken(null); handlers.current.onError(CAPTCHA_TEXT.timedOut); },
      });
    }).catch(() => { if (live) handlers.current.onError(navigator.onLine ? CAPTCHA_TEXT.pageUnavailable : CAPTCHA_TEXT.offline); });
    return () => {
      live = false;
      if (id && window.turnstile) window.turnstile.remove(id);
    };
  }, [siteKey]);

  return <div ref={box} className="captcha" />;
}
