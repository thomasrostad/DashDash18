import { useCallback, useEffect, useState } from "react";
import type { EventRow, Member } from "./data.ts";
import { errorText } from "./supabase.ts";
import { longDate } from "./text.ts";
import { entryDetail, logLine, signupText, summarize, summaryGroups, type SignupLogRow, type SignupStatus } from "./signups.ts";
import { addGuest, eveningData, removeGuest, setAnswer, signupLog, type EveningSignupData } from "./signupsApi.ts";

const CHOICES: { value: SignupStatus | ""; label: string }[] = [
  { value: "yes", label: "Kommer" }, { value: "maybe", label: "Usikker" }, { value: "no", label: "Kommer ikke" },
];

/** Påmeldingen på en dato: hvem som kommer, venteliste, gjester, endre svar og loggen (sql/045). */
export function EveningSignups({ event, roster, onBack }: { event: EventRow; roster: Member[]; onBack: () => void }) {
  const [data, setData] = useState<EveningSignupData | null>(null);
  const [log, setLog] = useState<SignupLogRow[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [guestName, setGuestName] = useState("");
  const [guestHost, setGuestHost] = useState("");
  const active = roster.filter((m) => m.status === "active").sort((a, b) => a.display_name.localeCompare(b.display_name, "nb"));
  const name = (id: string) => roster.find((m) => m.id === id)?.display_name;

  const load = useCallback(async () => {
    try { setData(await eveningData(event.id)); setError(null); } catch (err) { setError(errorText(err)); }
  }, [event.id]);
  useEffect(() => { load(); }, [load]);

  async function run(action: () => Promise<void>) {
    setBusy(true); setError(null);
    try { await action(); await load(); if (log) setLog(await signupLog(event.id)); }
    catch (err) { setError(errorText(err)); }
    finally { setBusy(false); }
  }

  if (!data) return <section><button className="link" onClick={onBack}>Tilbake</button>{error ? <p className="error">{error}</p> : <p className="muted">Henter …</p>}</section>;

  const summary = summarize(active, data.signups, data.guests, data.seen);
  const answer = (memberID: string) => data.signups.find((s) => s.member_id === memberID)?.status ?? "";

  return (
    <section>
      <div className="inline"><button className="link" onClick={onBack}>Tilbake</button></div>
      <h3>Påmelding {longDate(event.event_date)}</h3>
      <p>{signupText(data.signups, data.guests, active.length)}
        {data.settings?.max_players != null && <span className="muted"> · {summary.coming} av {data.settings.max_players} plasser</span>}</p>
      {error && <p className="error">{error}</p>}
      {summaryGroups(summary).filter((g) => g.entries.length > 0).map((g) => (
        <div key={g.title} className="card">
          <h4>{g.title} ({g.entries.length})</h4>
          <table>
            <tbody>
              {g.entries.map((e) => (
                <tr key={e.guestID ?? e.memberID}>
                  <td>{e.name}{entryDetail(e) && <span className="muted"> · {entryDetail(e)}</span>}{e.comment && <span className="muted"> «{e.comment}»</span>}</td>
                  <td className="actions">
                    {e.guestID ? (
                      <button className="link" disabled={busy} onClick={() => run(() => removeGuest(e.guestID!))}>Fjern</button>
                    ) : (
                      <select value={answer(e.memberID)} disabled={busy}
                        onChange={(ev) => run(() => setAnswer(event, e.memberID, (ev.target.value || null) as SignupStatus | null))}>
                        <option value="">Ikke svart</option>
                        {CHOICES.map((c) => <option key={c.value} value={c.value}>{c.label}</option>)}
                      </select>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      ))}
      {data.settings?.allow_guests && (
        <form className="card" onSubmit={(ev) => { ev.preventDefault(); if (!guestHost) { setError("Velg hvem gjesten kommer med."); return; }
          run(async () => { await addGuest(event.id, guestName, guestHost); setGuestName(""); }); }}>
          <h4>Ny gjest</h4>
          <div className="grid2 tight">
            <label>Gjest av
              <select value={guestHost} onChange={(ev) => setGuestHost(ev.target.value)}>
                <option value="">Velg medlem</option>
                {active.map((m) => <option key={m.id} value={m.id}>{m.display_name}</option>)}
              </select>
            </label>
            <label>Navn<input value={guestName} maxLength={60} onChange={(ev) => setGuestName(ev.target.value)} /></label>
          </div>
          <button className="primary" disabled={busy || !guestName.trim()}>Legg til</button>
        </form>
      )}
      {data.settings && (
        <div className="card">
          <h4>Logg</h4>
          {log === null ? <button className="link" onClick={async () => { try { setLog(await signupLog(event.id)); } catch (err) { setError(errorText(err)); } }}>Vis loggen</button>
            : log.length === 0 ? <p className="muted">Ingen endringer ennå.</p>
            : <ul>{log.map((r) => <li key={r.id}>{logLine(r, name)} <span className="muted">{new Date(r.changed_at).toLocaleString("nb-NO", { day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" })}</span></li>)}</ul>}
        </div>
      )}
    </section>
  );
}
