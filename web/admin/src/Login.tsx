import { useState } from "react";
import { errorText, supabase } from "./supabase.ts";

/** E-postkode, som i appen. Bare brukere som finnes (logg inn i appen første gang). */
export function Login() {
  const [email, setEmail] = useState("");
  const [code, setCode] = useState("");
  const [sent, setSent] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function send(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    const { error } = await supabase.auth.signInWithOtp({ email: email.trim(), options: { shouldCreateUser: false } });
    setBusy(false);
    if (error) setError(errorText(error));
    else setSent(true);
  }

  async function verify(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    const { error } = await supabase.auth.verifyOtp({ email: email.trim(), token: code.trim(), type: "email" });
    setBusy(false);
    if (error) setError(errorText(error));
  }

  return (
    <main className="center">
      <div className="card narrow">
        <h1>Atten · Arrangør</h1>
        <p className="muted">Planlegg turneringer, terminliste og tropp fra datamaskinen. Samme innlogging som i appen.</p>
        {!sent ? (
          <form onSubmit={send}>
            <label>E-post<input type="email" autoComplete="email" required value={email} onChange={(e) => setEmail(e.target.value)} /></label>
            <button className="primary" disabled={busy || !email.includes("@")}>Send kode</button>
          </form>
        ) : (
          <form onSubmit={verify}>
            <p className="muted">Koden er sendt til {email}.</p>
            <label>Kode<input inputMode="numeric" autoComplete="one-time-code" required value={code} onChange={(e) => setCode(e.target.value)} /></label>
            <button className="primary" disabled={busy || code.trim().length < 6}>Logg inn</button>
            <button type="button" className="link" onClick={() => { setSent(false); setCode(""); }}>Annen e-post</button>
          </form>
        )}
        {error && <p className="error">{error}</p>}
      </div>
    </main>
  );
}
