import { useState } from "react";
import { deleteEvent, saveEvent, type Competition, type EventInput, type EventRow, type Member } from "./data.ts";
import { errorText } from "./supabase.ts";
import { longDate, timeText, todayISO } from "./text.ts";
import { DayRounds } from "./rounds/DayRounds.tsx";

/** Terminlista: kvelder og spilledager for alle turneringene i klubben, med ny, endre, slette og komité. */
export function Schedule({ clubID, days, comps, roster, committees, onChanged }: {
  clubID: string; days: EventRow[]; comps: Competition[]; roster: Member[]; committees: Record<string, string[]>; onChanged: () => void;
}) {
  const [editing, setEditing] = useState<EventRow | "new" | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [roundsFor, setRoundsFor] = useState<EventRow | null>(null);
  const today = todayISO();
  const nameOf = (e: EventRow) =>
    comps.find((c) => (e.season_id && c.season_id === e.season_id) || (!e.season_id && e.competition_id && c.id === e.competition_id))?.name ?? "Klubbens egen";

  async function remove(e: EventRow) {
    if (!confirm(`Slette ${longDate(e.event_date)}? Påmeldingene og sosialkomiteen slettes også.`)) return;
    setError(null);
    try { await deleteEvent(e.id); onChanged(); } catch (err) { setError(errorText(err)); }
  }

  if (roundsFor) {
    return <DayRounds clubID={clubID} event={roundsFor} days={days} comps={comps} onBack={() => { setRoundsFor(null); onChanged(); }} />;
  }

  return (
    <section>
      <div className="inline"><button className="primary" onClick={() => setEditing("new")}>Ny dato</button></div>
      {error && <p className="error">{error}</p>}
      {editing && (
        <EventForm clubID={clubID} event={editing === "new" ? null : editing} comps={comps} roster={roster}
          committee={editing === "new" ? [] : committees[editing.id] ?? []}
          lastVenue={days.at(-1)?.venue ?? ""} onDone={() => { setEditing(null); onChanged(); }} onCancel={() => setEditing(null)} />
      )}
      {days.length === 0 ? <p className="muted">Ingen kvelder eller spilledager ennå.</p> : (
        <table>
          <thead><tr><th>Dato</th><th>Tid</th><th>Sted</th><th>Turnering</th><th>Komité</th><th></th></tr></thead>
          <tbody>
            {days.map((e) => (
              <tr key={e.id} className={e.event_date < today ? "past" : ""}>
                <td>{longDate(e.event_date)}</td>
                <td>{timeText(e.start_time) ?? "–"}</td>
                <td>{e.venue ?? "–"}</td>
                <td>{nameOf(e)}</td>
                <td className="muted">{(committees[e.id] ?? []).map((id) => roster.find((m) => m.id === id)?.display_name ?? "?").join(", ")}</td>
                <td className="actions">
                  <button className="link" onClick={() => setRoundsFor(e)}>Runder</button>
                  <button className="link" onClick={() => setEditing(e)}>Endre</button>
                  <button className="link" onClick={() => remove(e)}>Slett</button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </section>
  );
}

function EventForm({ clubID, event, comps, roster, committee, lastVenue, onDone, onCancel }: {
  clubID: string; event: EventRow | null; comps: Competition[]; roster: Member[]; committee: string[];
  lastVenue: string; onDone: () => void; onCancel: () => void;
}) {
  const choices = comps.filter((c) => c.status !== "finished" && c.kind !== "game" && (c.kind === "season" ? c.season_id : c.club_id));
  const initialChoice = event
    ? (comps.find((c) => (event.season_id && c.season_id === event.season_id) || (!event.season_id && event.competition_id === c.id))?.id ?? "")
    : (choices.find((c) => c.is_main)?.id ?? choices[0]?.id ?? "");
  const [choice, setChoice] = useState(initialChoice);
  const [date, setDate] = useState(event?.event_date ?? "");
  const [time, setTime] = useState(event?.start_time?.slice(0, 5) ?? "18:00");
  const [venue, setVenue] = useState(event?.venue ?? lastVenue ?? "");
  const [note, setNote] = useState(event?.note ?? "");
  const [members, setMembers] = useState<string[]>(committee);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function save(e: React.FormEvent) {
    e.preventDefault();
    const c = comps.find((x) => x.id === choice);
    const input: EventInput = {
      event_date: date, start_time: time ? `${time}:00` : null, venue, note,
      season_id: c?.kind === "season" ? c.season_id : null,
      competition_id: c && c.kind !== "season" ? c.id : null,
    };
    setBusy(true); setError(null);
    try { await saveEvent(clubID, event?.id ?? null, input, members); onDone(); }
    catch (err) { setError(errorText(err)); }
    finally { setBusy(false); }
  }

  const active = roster.filter((m) => m.status === "active");
  return (
    <form className="card" onSubmit={save}>
      <h3>{event ? `Endre ${longDate(event.event_date)}` : "Ny dato"}</h3>
      <div className="grid2 tight">
        <label>Dato<input type="date" required value={date} onChange={(e) => setDate(e.target.value)} /></label>
        <label>Tid<input type="time" value={time} onChange={(e) => setTime(e.target.value)} /></label>
        <label>Sted<input value={venue} maxLength={80} onChange={(e) => setVenue(e.target.value)} /></label>
        <label>Turnering
          <select value={choice} onChange={(e) => setChoice(e.target.value)}>
            {choices.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
            <option value="">Klubbens egen (uten turnering)</option>
          </select>
        </label>
      </div>
      <label>Notat<input value={note} maxLength={200} onChange={(e) => setNote(e.target.value)} /></label>
      <fieldset>
        <legend>Sosialkomité</legend>
        <div className="chips">
          {active.map((m) => (
            <label key={m.id} className="check chip">
              <input type="checkbox" checked={members.includes(m.id)}
                onChange={(e) => setMembers(e.target.checked ? [...members, m.id] : members.filter((x) => x !== m.id))} />
              {m.display_name}
            </label>
          ))}
        </div>
      </fieldset>
      {error && <p className="error">{error}</p>}
      <div className="inline">
        <button className="primary" disabled={busy || !date}>Lagre</button>
        <button type="button" className="link" onClick={onCancel}>Avbryt</button>
      </div>
    </form>
  );
}
