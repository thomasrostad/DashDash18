import { useState } from "react";
import type { Competition } from "./data.ts";
import { isoWeekday, seriesDates, weekdayName, type ScheduleTemplate, type SeriesResult } from "./reuse.ts";
import { createEventSeries } from "./reuseApi.ts";
import { errorText } from "./supabase.ts";
import { longDate, todayISO } from "./text.ts";

/** Turneringene en serie kan høre til: klubbens som ikke er ferdige (serien trenger klubb og turnering). */
export function seriesChoices(comps: readonly Competition[]): Competition[] {
  return comps.filter((c) => c.status !== "finished" && c.kind !== "game" && c.club_id);
}

/**
 * «Lag serie» (sql/049): startdato, ukedag, antall, hver n-te uke, tid og sted, med datoene før lagring. Etter
 * lagring vises datoene som ble laget og de som ble hoppet over (turneringen hadde alt en dag der).
 */
export function SeriesForm({ comps, competitionID, schedule, onDone, onCancel }: {
  comps: Competition[];
  /** Fast turnering (etter «Ny turnering» fra mal). Ellers velges den. */
  competitionID?: string;
  schedule?: ScheduleTemplate | null;
  onDone: () => void; onCancel: () => void;
}) {
  const choices = seriesChoices(comps);
  const [choice, setChoice] = useState(competitionID
    ?? choices.find((c) => c.is_main && c.status === "active")?.id ?? choices[0]?.id ?? "");
  const today = todayISO();
  const [start, setStart] = useState(today);
  const [weekday, setWeekday] = useState(schedule?.weekday ?? isoWeekday(today));
  const [count, setCount] = useState(schedule?.count ?? 10);
  const [every, setEvery] = useState(schedule?.everyWeeks ?? 1);
  const [time, setTime] = useState(schedule?.startTime ?? "18:00");
  const [venue, setVenue] = useState(schedule?.venue ?? "");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [result, setResult] = useState<SeriesResult | null>(null);
  const preview = seriesDates(start, weekday, count, every);

  async function save(e: React.FormEvent) {
    e.preventDefault();
    if (!choice) { setError("Velg turneringen."); return; }
    setBusy(true); setError(null);
    try {
      setResult(await createEventSeries({ competitionID: choice, firstDate: start, weekday, count, everyWeeks: every, startTime: time || null, venue: venue || null }));
    } catch (err) { setError(errorText(err)); } finally { setBusy(false); }
  }

  if (result) {
    return (
      <div className="card">
        <h3>Serien er laget</h3>
        <p>{result.dates.length === 0 ? "Ingen nye datoer." : `${result.dates.length} ${result.dates.length === 1 ? "dato" : "datoer"}: ${result.dates.map((d) => longDate(d)).join(", ")}.`}</p>
        {result.skipped.length > 0 && <p className="muted">Hoppet over (fantes fra før): {result.skipped.map((d) => longDate(d)).join(", ")}.</p>}
        <div className="inline"><button className="primary" onClick={onDone}>Ferdig</button></div>
      </div>
    );
  }

  return (
    <form className="card" onSubmit={save}>
      <h3>Lag serie</h3>
      <div className="grid2 tight">
        {!competitionID && (
          <label>Turnering
            <select value={choice} onChange={(e) => setChoice(e.target.value)}>
              {choices.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
            </select>
          </label>
        )}
        <label>Fra og med<input type="date" required value={start} onChange={(e) => setStart(e.target.value)} /></label>
        <label>Ukedag
          <select value={weekday} onChange={(e) => setWeekday(Number(e.target.value))}>
            {[1, 2, 3, 4, 5, 6, 7].map((d) => <option key={d} value={d}>{weekdayName(d)}</option>)}
          </select>
        </label>
        <label>Antall<input type="number" min={1} max={52} value={count} onChange={(e) => setCount(Math.min(52, Math.max(1, Number(e.target.value))))} /></label>
        <label>Hver
          <select value={every} onChange={(e) => setEvery(Number(e.target.value))}>
            {[1, 2, 3, 4, 5, 6, 7, 8].map((n) => <option key={n} value={n}>{n === 1 ? "uke" : `${n}. uke`}</option>)}
          </select>
        </label>
        <label>Tid<input type="time" value={time} onChange={(e) => setTime(e.target.value)} /></label>
        <label>Sted<input value={venue} maxLength={80} onChange={(e) => setVenue(e.target.value)} /></label>
      </div>
      {preview.length > 0 && <p className="muted small">{preview.map((d) => longDate(d)).join(", ")}</p>}
      <p className="muted small">Datoer turneringen alt har, hoppes over.</p>
      {error && <p className="error">{error}</p>}
      <div className="inline">
        <button className="primary" disabled={busy || !choice || preview.length === 0}>Lag {preview.length} {preview.length === 1 ? "dato" : "datoer"}</button>
        <button type="button" className="link" onClick={onCancel}>{competitionID ? "Hopp over" : "Avbryt"}</button>
      </div>
    </form>
  );
}
