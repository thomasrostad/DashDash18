import { useEffect, useState } from "react";
import { BRREG_ERRORS, lookUpName, normalizeOrgNumber } from "./brreg.ts";
import { clubSettings, saveClubSettings, type ClubSettings as Settings } from "./rolesApi.ts";
import { errorText } from "./supabase.ts";

/** Klubben: navn og organisasjonsnummer. «Hent navn» henter navnet fra Enhetsregisteret, og arrangøren bekrefter. */
export function ClubSettings({ clubID, onSaved }: { clubID: string; onSaved: (name: string) => void }) {
  const [settings, setSettings] = useState<Settings | null>(null);
  const [name, setName] = useState("");
  const [org, setOrg] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [done, setDone] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    clubSettings(clubID).then((s) => { setSettings(s); setName(s.name); setOrg(s.org_number ?? ""); })
      .catch((e) => setError(errorText(e)));
  }, [clubID]);

  async function fetchName() {
    setBusy(true); setError(null); setDone(null);
    const res = await lookUpName(org);
    setBusy(false);
    if (!res.ok) { setError(res.error); return; }
    if (confirm(`Bruke «${res.name}» som navn på klubben?`)) setName(res.name);
  }

  async function save(e: React.FormEvent) {
    e.preventDefault();
    if (!settings) return;
    const n = name.trim();
    if (n.length < 1 || n.length > 60) { setError("Klubben må ha et navn (1–60 tegn)."); return; }
    let number: string | null = null;
    if (settings.supportsOrgNumber && org.trim()) {
      number = normalizeOrgNumber(org);
      if (!number) { setError(BRREG_ERRORS.invalid); return; }
    }
    setBusy(true); setError(null); setDone(null);
    try {
      await saveClubSettings(clubID, n, number, settings.supportsOrgNumber);
      setSettings({ ...settings, name: n, org_number: number });
      setOrg(number ?? "");
      setDone("Lagret.");
      onSaved(n);
    } catch (err) { setError(errorText(err)); } finally { setBusy(false); }
  }

  if (!settings) return error ? <p className="error">{error}</p> : <p className="muted">Henter …</p>;

  return (
    <form className="card" onSubmit={save}>
      <h3>Klubben</h3>
      {error && <p className="error">{error}</p>}
      {done && <p className="muted">{done}</p>}
      <label>Navn<br /><input required maxLength={60} value={name} onChange={(e) => setName(e.target.value)} /></label>
      {settings.supportsOrgNumber && (
        <>
          <p />
          <label>Organisasjonsnummer (valgfritt)<br />
            <span className="inline">
              <input inputMode="numeric" maxLength={11} value={org} onChange={(e) => setOrg(e.target.value)} />
              <button type="button" className="link" disabled={busy || !normalizeOrgNumber(org)} onClick={fetchName}>Hent navn</button>
            </span>
          </label>
          <p className="muted">9 siffer. «Hent navn» henter navnet fra Brønnøysundregistrene.</p>
        </>
      )}
      <div className="inline"><button className="primary" disabled={busy}>Lagre</button></div>
    </form>
  );
}
