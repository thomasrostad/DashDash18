import { useState } from "react";
import { canSendCode, otpOptions } from "./captcha.ts";
import { config, errorText, supabase } from "./supabase.ts";
import { Turnstile } from "./Turnstile.tsx";

const Arrow = () => (
  <svg viewBox="0 0 14 14" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
    <path d="M1.5 7h11M8 2.5 12.5 7 8 11.5" />
  </svg>
);

/** Googles G i de fire fargene, fra Googles egen SVG. Retningslinjene: ikke endre form eller farger. */
const GoogleG = () => (
  <svg viewBox="0 0 48 48" aria-hidden="true">
    <path fill="#EA4335" d="M24 9.5c3.54 0 6.71 1.22 9.21 3.6l6.85-6.85C35.9 2.38 30.47 0 24 0 14.62 0 6.51 5.38 2.56 13.22l7.98 6.19C12.43 13.72 17.74 9.5 24 9.5z" />
    <path fill="#4285F4" d="M46.98 24.55c0-1.57-.15-3.09-.38-4.55H24v9.02h12.94c-.58 2.96-2.26 5.48-4.78 7.18l7.73 6c4.51-4.18 7.09-10.36 7.09-17.65z" />
    <path fill="#FBBC05" d="M10.53 28.59c-.48-1.45-.76-2.99-.76-4.59s.27-3.14.76-4.59l-7.98-6.19C.92 16.46 0 20.12 0 24c0 3.88.92 7.54 2.56 10.78l7.97-6.19z" />
    <path fill="#34A853" d="M24 48c6.48 0 11.93-2.13 15.89-5.81l-7.73-6c-2.15 1.45-4.92 2.3-8.16 2.3-6.26 0-11.57-4.22-13.47-9.91l-7.98 6.19C6.51 42.62 14.62 48 24 48z" />
  </svg>
);

/** Apple-logoen (Apples retningslinjer: samme farge som teksten). */
const AppleLogo = () => (
  <svg viewBox="0 0 814 1000" aria-hidden="true">
    <path fill="currentColor" d="M788.1 340.9c-5.8 4.5-108.2 62.2-108.2 190.5 0 148.4 130.3 200.9 134.2 202.2-.6 3.2-20.7 71.9-68.7 141.9-42.8 61.6-87.5 123.1-155.5 123.1s-85.5-39.5-164-39.5c-76.5 0-103.7 40.8-165.9 40.8s-105.6-57-155.5-127C46.7 790.7 0 663 0 541.8c0-194.4 126.4-297.5 250.8-297.5 66.1 0 121.2 43.4 162.7 43.4 39.5 0 101.1-46 176.3-46 28.5 0 130.9 2.6 198.3 99.2zm-234-181.5c31.1-36.9 53.1-88.1 53.1-139.3 0-7.1-.6-14.3-1.9-20.1-50.6 1.9-110.8 33.7-147.1 75.8-28.5 32.4-55.1 83.6-55.1 135.5 0 7.8 1.3 15.6 1.9 18.1 3.2.6 8.4 1.3 13.6 1.3 45.4 0 102.5-30.4 135.5-71.3z" />
  </svg>
);

/** Apple og Google (som i appen) eller e-postkode. E-postkoden gjelder bare brukere som finnes (logg inn i
 *  appen første gang). Apple og Google går via Supabase og tilbake hit; samme Apple-ID eller e-post gir samme
 *  konto. Apple på web krever Services ID og secret i Supabase (docs/apple-web.md).
 *  Med site key for Turnstile kommer sjekken før koden sendes (`CaptchaFeature`). */
export function SignIn() {
  const [email, setEmail] = useState("");
  const [code, setCode] = useState("");
  const [sent, setSent] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const siteKey = config?.turnstileSiteKey ?? null;
  const [captchaToken, setCaptchaToken] = useState<string | null>(null);
  const [captchaError, setCaptchaError] = useState<string | null>(null);
  // Et token kan bare brukes én gang: ny widget etter hvert forsøk.
  const [captchaRound, setCaptchaRound] = useState(0);
  const ready = canSendCode(email, !!siteKey, captchaToken);

  async function send(e: React.FormEvent) {
    e.preventDefault();
    if (!ready || busy) return;
    setBusy(true);
    setError(null);
    const { error } = await supabase.auth.signInWithOtp({ email: email.trim(), options: otpOptions(captchaToken) });
    setBusy(false);
    setCaptchaToken(null);
    setCaptchaRound((n) => n + 1);
    if (error) setError(errorText(error));
    else setSent(true);
  }

  // Ved suksess forlater siden seg selv; tilbake hit plukker supabase-js opp økta fra adressen.
  async function oauth(provider: "apple" | "google") {
    if (busy) return;
    setBusy(true);
    setError(null);
    const { error } = await supabase.auth.signInWithOAuth({ provider, options: { redirectTo: window.location.origin } });
    if (error) {
      setBusy(false);
      setError(errorText(error));
    }
  }

  async function verify(e: React.FormEvent) {
    e.preventDefault();
    if (busy || code.trim().length < 6) return;
    setBusy(true);
    setError(null);
    const { error } = await supabase.auth.verifyOtp({ email: email.trim(), token: code.trim(), type: "email" });
    setBusy(false);
    if (error) setError(errorText(error));
  }

  return (
    <div className="signin">
      {!sent && (
        <>
          <button type="button" className="apple" onClick={() => oauth("apple")} disabled={busy}><AppleLogo />Fortsett med Apple</button>
          <button type="button" className="google" onClick={() => oauth("google")} disabled={busy}><GoogleG />Fortsett med Google</button>
          <div className="or" aria-hidden="true">Eller</div>
        </>
      )}
      {!sent ? (
        <form onSubmit={send}>
          <div className="field">
            <input id="signin-email" type="email" autoComplete="email" required placeholder=" " value={email}
              onChange={(e) => setEmail(e.target.value)} />
            <label htmlFor="signin-email">E-post fra appen</label>
            <button type="submit" className={busy ? "go busy" : ready ? "go ready" : "go"} disabled={!ready || busy} aria-label="Send kode"><Arrow /></button>
          </div>
          {siteKey && <Turnstile key={captchaRound} siteKey={siteKey} theme="dark" onToken={setCaptchaToken} onError={setCaptchaError} />}
          {captchaError && <p className="error">{captchaError}</p>}
          <p className="note">Du logger inn med samme e-post som i appen.</p>
        </form>
      ) : (
        <form onSubmit={verify}>
          <div className="field">
            <input id="signin-code" inputMode="numeric" autoComplete="one-time-code" required placeholder=" " autoFocus value={code}
              className="code" onChange={(e) => setCode(e.target.value)} />
            <label htmlFor="signin-code">Kode fra e-posten</label>
            <button type="submit" className={busy ? "go busy" : code.trim().length >= 6 ? "go ready" : "go"} disabled={busy || code.trim().length < 6} aria-label="Logg inn"><Arrow /></button>
          </div>
          <p className="note">Vi sendte en kode til {email.trim()}. <button type="button" className="link onDark" onClick={() => { setSent(false); setCode(""); setError(null); }}>Bruk en annen e-post</button></p>
        </form>
      )}
      {error && <p className="error">{error}</p>}
    </div>
  );
}
