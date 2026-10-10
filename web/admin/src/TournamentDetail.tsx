import { useCallback, useEffect, useState } from "react";
import {
  addStaff, deleteTournament, participants, removeStaff, saveSignupSettings, setPlaysWhenItSuits, signupSettings, staff,
  waitlist, type Competition, type Member, type Participant, type SignupSettings, type StaffRow, type WaitlistEntry,
} from "./data.ts";
import { errorText } from "./supabase.ts";
import { kindText, longDate, statusText } from "./text.ts";

/** Én turnering: påmeldte, påmelding og venteliste, stab, «Spill når det passer» og sletting. */
export function TournamentDetail({ competition, roster, onBack, onChanged }: {
  competition: Competition; roster: Member[]; onBack: () => void; onChanged: () => void;
}) {
  const [people, setPeople] = useState<Participant[] | null>(null);
  const [settings, setSettings] = useState<SignupSettings | null>(null);
  const [queue, setQueue] = useState<WaitlistEntry[]>([]);
  const [crew, setCrew] = useState<StaffRow[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const isSeries = competition.kind === "league" || competition.kind === "fun";

  const load = useCallback(async () => {
    setError(null);
    try {
      const [p, s, w, c] = await Promise.all([
        participants(competition.id, roster), signupSettings(competition.id),
        waitlist(competition.id).catch(() => []), staff(competition.id),
      ]);
      setPeople(p); setSettings(s); setQueue(w); setCrew(c);
    } catch (e) { setError(errorText(e)); }
  }, [competition.id, roster]);

  useEffect(() => { load(); }, [load]);

  async function run(action: () => Promise<void>, done: string) {
    setBusy(true); setError(null); setNotice(null);
    try { await action(); setNotice(done); await load(); onChanged(); }
    catch (e) { setError(errorText(e)); }
    finally { setBusy(false); }
  }

  const active = people?.filter((p) => p.status === "active") ?? [];
  const staffCandidates = roster.filter((m) => m.user_id && m.status === "active" && !crew.some((s) => s.profile_id === m.user_id));

  return (
    <section>
      <button className="link" onClick={onBack}>← Alle turneringer</button>
      <h2>{competition.name}</h2>
      <p className="muted">
        {kindText(competition.kind)} · {statusText(competition.status)}
        {competition.starts_on && ` · ${longDate(competition.starts_on)}${competition.ends_on ? ` – ${longDate(competition.ends_on)}` : ""}`}
        {competition.is_main && " · Hovedturnering"}
      </p>
      {error && <p className="error">{error}</p>}
      {notice && <p className="ok">{notice}</p>}

      <div className="grid2">
        <div className="card">
          <h3>Påmeldte ({active.length}{settings?.max_entrants ? ` av ${settings.max_entrants}` : ""})</h3>
          {!people ? <p className="muted">Henter …</p> : active.length === 0 ? <p className="muted">Ingen påmeldte ennå.</p> : (
            <ul className="plain">{active.map((p) => <li key={p.id}>{p.name}</li>)}</ul>
          )}
          {queue.length > 0 && (
            <>
              <h4>Venteliste</h4>
              <ol className="plain">
                {queue.map((w) => (
                  <li key={w.id}>{w.display_name}{w.offer_expires_at && <span className="pill">Tilbud til {new Date(w.offer_expires_at).toLocaleString("nb-NO", { dateStyle: "short", timeStyle: "short" })}</span>}</li>
                ))}
              </ol>
            </>
          )}
        </div>

        {settings && competition.kind !== "season" && (
          <form className="card" onSubmit={(e) => { e.preventDefault(); run(() => saveSignupSettings(competition.id, settings), "Påmeldingen er lagret."); }}>
            <h3>Påmelding</h3>
            <label className="check"><input type="checkbox" checked={settings.signup_open} onChange={(e) => setSettings({ ...settings, signup_open: e.target.checked })} />Åpen for påmelding</label>
            <label>Hvem kan melde seg på
              <select value={settings.signup_audience} onChange={(e) => setSettings({ ...settings, signup_audience: e.target.value as SignupSettings["signup_audience"] })}>
                <option value="members">Medlemmer i klubben</option>
                <option value="anyone">Alle med lenken</option>
              </select>
            </label>
            {settings.signup_audience === "anyone" && (
              <label className="check"><input type="checkbox" checked={settings.listed} onChange={(e) => setSettings({ ...settings, listed: e.target.checked })} />Vis i «Finn turneringer»</label>
            )}
            <label>Plasser (tomt: ingen grense)
              <input type="number" min={2} max={500} value={settings.max_entrants ?? ""} onChange={(e) => setSettings({ ...settings, max_entrants: e.target.value ? Number(e.target.value) : null })} />
            </label>
            <label className="check"><input type="checkbox" checked={settings.waitlist_enabled} onChange={(e) => setSettings({ ...settings, waitlist_enabled: e.target.checked })} />Venteliste når det er fullt</label>
            <button className="primary" disabled={busy}>Lagre påmeldingen</button>
          </form>
        )}
      </div>

      <div className="grid2">
        <div className="card">
          <h3>Stab</h3>
          <p className="muted">Arrangører styrer turneringen. Funksjonærer fører for gruppene de er satt på.</p>
          <ul className="plain">
            {crew.map((s) => (
              <li key={s.profile_id}>{s.name} <span className="pill">{s.role === "organizer" ? "Arrangør" : "Funksjonær"}</span>
                <button className="link" disabled={busy} onClick={() => run(() => removeStaff(competition.id, s.profile_id), `${s.name} er tatt ut av staben.`)}>Fjern</button>
              </li>
            ))}
          </ul>
          {staffCandidates.length > 0 && (
            <form onSubmit={(e) => {
              e.preventDefault();
              const f = new FormData(e.currentTarget);
              const who = String(f.get("who")); const role = String(f.get("role")) as StaffRow["role"];
              if (who) run(() => addStaff(competition.id, who, role), "Lagt til i staben.");
            }}>
              <div className="inline">
                <select name="who" defaultValue="">
                  <option value="" disabled>Velg fra troppen</option>
                  {staffCandidates.map((m) => <option key={m.id} value={m.user_id!}>{m.display_name}</option>)}
                </select>
                <select name="role" defaultValue="scorer"><option value="scorer">Funksjonær</option><option value="organizer">Arrangør</option></select>
                <button className="primary" disabled={busy}>Legg til</button>
              </div>
            </form>
          )}
        </div>

        <div className="card">
          {isSeries && (
            <>
              <h3>Spill når det passer</h3>
              <p className="muted">Påmeldte spiller når det passer i perioden. Rundene teller av seg selv, og de beste teller i tabellen.</p>
              <label className="check">
                <input type="checkbox" checked={!!competition.auto_count} disabled={busy}
                  onChange={(e) => run(() => setPlaysWhenItSuits(competition.id, e.target.checked), e.target.checked ? "Rundene i perioden teller nå av seg selv." : "Slått av.")} />
                Runder i perioden teller av seg selv
              </label>
            </>
          )}
          <DeleteTournament competition={competition} busy={busy} onDelete={(typed) => run(async () => {
            const r = await deleteTournament(competition.id, typed);
            setNotice(`${r.name} er slettet.`);
            onBack();
          }, "Slettet.")} />
        </div>
      </div>
    </section>
  );
}

function DeleteTournament({ competition, busy, onDelete }: { competition: Competition; busy: boolean; onDelete: (typed: string) => void }) {
  const [typed, setTyped] = useState("");
  const matches = typed.trim().toLowerCase() === competition.name.trim().toLowerCase() && typed.trim() !== "";
  return (
    <form onSubmit={(e) => { e.preventDefault(); if (matches) onDelete(typed); }}>
      <h3>Slett turneringen</h3>
      <p className="muted">Kveldene, rundene, resultatene, påmeldingene og veddemålene slettes for godt. Runder som bare teller også her, blir stående. Skriv navnet for å bekrefte.</p>
      <input placeholder={competition.name} value={typed} onChange={(e) => setTyped(e.target.value)} />
      <button className="danger" disabled={busy || !matches}>Slett for godt</button>
    </form>
  );
}
