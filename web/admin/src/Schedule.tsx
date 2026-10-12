import { useEffect, useState } from "react";
import { deleteEvent, saveEvent, type Competition, type EventInput, type EventRow, type Member } from "./data.ts";
import { errorText } from "./supabase.ts";
import { longDate, timeText, todayISO } from "./text.ts";
import { DayRounds } from "./rounds/DayRounds.tsx";
import { EveningSignups } from "./EveningSignups.tsx";
import { settingsForm, type EveningSettings, type SettingsForm } from "./signups.ts";
import { eveningSettings, saveSettings } from "./signupsApi.ts";
import { seriesText } from "./reuse.ts";
import { reuseAvailable, seriesFor, updateEventSeries, type SeriesRow } from "./reuseApi.ts";
import { SeriesForm } from "./SeriesForm.tsx";

/** Terminlista: kvelder og spilledager for alle turneringene i klubben, med ny, endre, slette og komité. */
export function Schedule({ clubID, days, comps, roster, committees, onChanged, canTournaments = true, canRounds = true }: {
  clubID: string; days: EventRow[]; comps: Competition[]; roster: Member[]; committees: Record<string, string[]>; onChanged: () => void;
  /** Rettighetene (sql/044): serier krever tournaments, maler for runder krever rounds. */
  canTournaments?: boolean; canRounds?: boolean;
}) {
  const [editing, setEditing] = useState<EventRow | "new" | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [roundsFor, setRoundsFor] = useState<EventRow | null>(null);
  const [signupsFor, setSignupsFor] = useState<EventRow | null>(null);
  /** Tak, frister og gjester per dato (sql/045). null: 045 er ikke kjørt, så feltene skjules. */
  const [settings, setSettings] = useState<Record<string, EveningSettings> | null>(null);
  /** Serier (sql/049). null: 049 er ikke kjørt, så «Lag serie» og valget for serien skjules. */
  const [series, setSeries] = useState<{ eventSeries: Record<string, string>; series: Record<string, SeriesRow> } | null>(null);
  const [makingSeries, setMakingSeries] = useState(false);
  const [notice, setNotice] = useState<string | null>(null);
  const today = todayISO();
  const ids = days.map((d) => d.id).join(",");
  useEffect(() => {
    let live = true;
    reuseAvailable().then(async (ok) => {
      const s = ok ? await seriesFor(clubID) : null;
      if (live) setSeries(s);
    });
    return () => { live = false; };
  }, [clubID, ids]);
  const seriesOf = (e: EventRow): SeriesRow | null => {
    const id = series?.eventSeries[e.id];
    return id ? series?.series[id] ?? null : null;
  };
  useEffect(() => {
    let live = true;
    eveningSettings(ids ? ids.split(",") : []).then((s) => { if (live) setSettings(s); });
    return () => { live = false; };
  }, [ids]);
  const nameOf = (e: EventRow) =>
    comps.find((c) => (e.season_id && c.season_id === e.season_id) || (!e.season_id && e.competition_id && c.id === e.competition_id))?.name ?? "Klubbens egen";

  async function remove(e: EventRow) {
    if (!confirm(`Slette ${longDate(e.event_date)}? Påmeldingene og sosialkomiteen slettes også.`)) return;
    setError(null);
    try { await deleteEvent(e.id); onChanged(); } catch (err) { setError(errorText(err)); }
  }

  if (signupsFor) {
    return <EveningSignups event={signupsFor} roster={roster} onBack={() => { setSignupsFor(null); onChanged(); }} />;
  }

  if (roundsFor) {
    return <DayRounds clubID={clubID} event={roundsFor} days={days} comps={comps} canTemplates={canRounds} onBack={() => { setRoundsFor(null); onChanged(); }} />;
  }

  return (
    <section>
      <div className="inline">
        <button className="primary" onClick={() => { setEditing("new"); setNotice(null); }}>Ny dato</button>
        {series && canTournaments && <button onClick={() => { setMakingSeries(true); setNotice(null); }}>Lag serie</button>}
      </div>
      {error && <p className="error">{error}</p>}
      {notice && <p className="muted">{notice}</p>}
      {makingSeries && (
        <SeriesForm comps={comps} onDone={() => { setMakingSeries(false); onChanged(); }} onCancel={() => setMakingSeries(false)} />
      )}
      {editing && (
        <EventForm clubID={clubID} event={editing === "new" ? null : editing} comps={comps} roster={roster}
          committee={editing === "new" ? [] : committees[editing.id] ?? []}
          settings={settings === null ? null : settingsForm(editing === "new" ? null : settings[editing.id])}
          lastVenue={days.at(-1)?.venue ?? ""} inSeries={editing !== "new" && series !== null && seriesOf(editing) !== null} days={days}
          onDone={(text) => { setEditing(null); setNotice(text ?? null); onChanged(); }} onCancel={() => setEditing(null)} />
      )}
      {days.length === 0 ? <p className="muted">Ingen kvelder eller spilledager ennå.</p> : (
        <table>
          <thead><tr><th>Dato</th><th>Tid</th><th>Sted</th><th>Turnering</th><th>Komité</th><th></th></tr></thead>
          <tbody>
            {days.map((e) => (
              <tr key={e.id} className={e.event_date < today ? "past" : ""}>
                <td>{longDate(e.event_date)}{seriesOf(e) && <div className="muted small">{seriesText(seriesOf(e)!)}</div>}</td>
                <td>{timeText(e.start_time) ?? "–"}</td>
                <td>{e.venue ?? "–"}</td>
                <td>{nameOf(e)}</td>
                <td className="muted">{(committees[e.id] ?? []).map((id) => roster.find((m) => m.id === id)?.display_name ?? "?").join(", ")}</td>
                <td className="actions">
                  <button className="link" onClick={() => setSignupsFor(e)}>Påmelding</button>
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

function EventForm({ clubID, event, comps, roster, committee, settings, lastVenue, inSeries, days, onDone, onCancel }: {
  clubID: string; event: EventRow | null; comps: Competition[]; roster: Member[]; committee: string[];
  /** null: sql/045 er ikke kjørt. */
  settings: SettingsForm | null;
  /** Datoen hører til en serie (sql/049): dato, tid og sted endres med update_event_series. */
  inSeries: boolean; days: EventRow[];
  lastVenue: string; onDone: (text?: string) => void; onCancel: () => void;
}) {
  const [scope, setScope] = useState<"one" | "future">("one");
  const [rules, setRules] = useState<SettingsForm | null>(settings);
  const choices = comps.filter((c) => c.status !== "finished" && c.kind !== "game" && (c.kind === "season" ? c.season_id : c.club_id));
  const initialChoice = event
    ? (comps.find((c) => (event.season_id && c.season_id === event.season_id) || (!event.season_id && event.competition_id === c.id))?.id ?? "")
    : (choices.find((c) => c.is_main && c.status === "active")?.id ?? choices.find((c) => c.is_main)?.id ?? choices[0]?.id ?? "");
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
    try {
      let text: string | undefined;
      if (event && inSeries) {
        // Dato, tid og sted for denne (og eventuelt de neste) i serien i én transaksjon.
        const moved = date !== event.event_date;
        const changed = moved || (input.start_time ?? null) !== (event.start_time ?? null) || (venue.trim() || null) !== (event.venue ?? null);
        if (changed || scope === "future") {
          const r = await updateEventSeries({ eventID: event.id, scope, startTime: time || null, venue: venue || null, newDate: moved ? date : null });
          if (r.skipped.length > 0) {
            const skipped = r.skipped.map((id) => days.find((d) => d.id === id)?.event_date).filter((d): d is string => !!d);
            text = `Ikke endret (passert eller startet): ${skipped.map((d) => longDate(d)).join(", ")}.`;
          }
        }
      }
      const id = await saveEvent(clubID, event?.id ?? null, input, members);
      if (rules && settings && JSON.stringify(rules) !== JSON.stringify(settings)) await saveSettings(id, rules);
      onDone(text);
    }
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
      {inSeries && (
        <fieldset>
          <legend>Datoen er en del av en serie</legend>
          <label className="check"><input type="radio" name="scope" checked={scope === "one"} onChange={() => setScope("one")} />Bare denne</label>
          <label className="check"><input type="radio" name="scope" checked={scope === "future"} onChange={() => setScope("future")} />Denne og fremtidige</label>
          {scope === "future" && <p className="muted small">Tid og sted gjelder de neste i serien. Ny dato flytter dem like mange dager. Passerte og startede røres ikke.</p>}
        </fieldset>
      )}
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
      {rules && (
        <fieldset>
          <legend>Påmelding</legend>
          <div className="grid2 tight">
            <label className="check"><input type="checkbox" checked={rules.hasMax} onChange={(e) => setRules({ ...rules, hasMax: e.target.checked })} />Maks antall</label>
            {rules.hasMax && <label>Plasser<input type="number" min={1} max={500} value={rules.maxPlayers}
              onChange={(e) => setRules({ ...rules, maxPlayers: Number(e.target.value) })} /></label>}
            <label>Påmeldingsfrist<input type="datetime-local" value={rules.signupDeadline}
              onChange={(e) => setRules({ ...rules, signupDeadline: e.target.value })} /></label>
            <label>Avmeldingsfrist<input type="datetime-local" value={rules.withdrawDeadline}
              onChange={(e) => setRules({ ...rules, withdrawDeadline: e.target.value })} /></label>
            <label className="check"><input type="checkbox" checked={rules.allowGuests} onChange={(e) => setRules({ ...rules, allowGuests: e.target.checked })} />Tillat gjester</label>
          </div>
          <p className="muted">Alt er av som standard. Tom frist betyr ingen frist. Når datoen er full, havner nye på ventelista.</p>
        </fieldset>
      )}
      {error && <p className="error">{error}</p>}
      <div className="inline">
        <button className="primary" disabled={busy || !date}>Lagre</button>
        <button type="button" className="link" onClick={onCancel}>Avbryt</button>
      </div>
    </form>
  );
}
