import { useState } from "react";
import { canSendCode, otpOptions } from "./captcha.ts";
import { config, errorText, supabase } from "./supabase.ts";
import { Turnstile } from "./Turnstile.tsx";

const Arrow = () => (
  <svg viewBox="0 0 14 14" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
    <path d="M1.5 7h11M8 2.5 12.5 7 8 11.5" />
  </svg>
);

/** E-postkode, som i appen. Bare brukere som finnes (logg inn i appen første gang).
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
