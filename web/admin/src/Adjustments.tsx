import { useCallback, useEffect, useState } from "react";
import { events, type Competition, type EventRow, type Member } from "./data.ts";
import { adjustmentPointsText, adjustmentProblem, POINTS_MAX, POINTS_MIN, POINTS_STEP, REASON_LIMIT, type Adjustment } from "./adjustments.ts";
import { addAdjustment, adjustments, deleteAdjustment } from "./adjustmentsApi.ts";
import { errorText } from "./supabase.ts";
import { longDate } from "./text.ts";

/** Tilleggspoeng i sesongen, som appens TilleggspoengView: lista, «Legg til» og sletting. */
export function Adjustments({ competition, roster }: { competition: Competition; roster: Member[] }) {
  const seasonID = competition.season_id!;
  const clubID = competition.club_id!;
  const [rows, setRows] = useState<Adjustment[] | null>(null);
  const [days, setDays] = useState<EventRow[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [memberID, setMemberID] = useState("");
  const [points, setPoints] = useState(1);
  const [reason, setReason] = useState("");
  const [eventID, setEventID] = useState("");

  const players = roster.filter((m) => m.status === "active");
  const name = (id: string) => roster.find((m) => m.id === id)?.display_name ?? "Ukjent spiller";
  const dayText = (id: string | null) => {
    const e = id ? days.find((d) => d.id === id) : undefined;
    return e ? longDate(e.event_date) : null;
  };

  const load = useCallback(async () => {
    setError(null);
    try {
      const [a, e] = await Promise.all([adjustments(seasonID), events(clubID)]);
      setRows(a);
      setDays(e.filter((d) => d.season_id === seasonID).sort((x, y) => y.event_date.localeCompare(x.event_date)));
    } catch (e) { setError(errorText(e)); }
  }, [seasonID, clubID]);

  useEffect(() => { load(); }, [load]);

  async function run(action: () => Promise<void>, done: string) {
    setBusy(true); setError(null); setNotice(null);
    try { await action(); setNotice(done); await load(); return true; }
    catch (e) { setError(errorText(e)); return false; }
    finally { setBusy(false); }
  }

  const problem = adjustmentProblem(memberID || null, points, reason);

  return (
    <div className="card">
      <h3>Tilleggspoeng</h3>
      <p className="muted">Poeng du gir for hånd, for eksempel fra en konkurranse utenfor appen. De legges på totalen i tabellen, og grunnen vises for spillerne.</p>
      {error && <p className="error">{error}</p>}
      {notice && <p className="ok">{notice}</p>}
      {rows === null ? <p className="muted">Henter …</p> : rows.length === 0 ? <p className="muted">Ingen tilleggspoeng ennå.</p> : (
        <ul className="plain">
          {rows.map((r) => (
            <li key={r.id}>
              <strong>{name(r.member_id)}</strong> {adjustmentPointsText(r.points)}
              <span className="muted small"> · {[r.reason, dayText(r.event_id)].filter(Boolean).join(" · ")}</span>{" "}
              <button className="link" disabled={busy}
                onClick={() => confirm(`Slette tilleggspoenget? ${name(r.member_id)} mister ${adjustmentPointsText(r.points)} i tabellen.`)
                  && run(() => deleteAdjustment(r.id), "Tilleggspoenget er slettet.")}>Slett</button>
            </li>
          ))}
        </ul>
      )}
      <form onSubmit={async (e) => {
        e.preventDefault();
        if (problem) { setError(problem); return; }
        const ok = await run(() => addAdjustment(clubID, seasonID, memberID, eventID || null, points, reason),
          `${name(memberID)} fikk ${adjustmentPointsText(points)}.`);
        if (ok) { setMemberID(""); setPoints(1); setReason(""); setEventID(""); }
      }}>
        <h4>Nytt tilleggspoeng</h4>
        <label>Spiller
          <select value={memberID} onChange={(e) => setMemberID(e.target.value)}>
            <option value="">Velg</option>
            {players.map((m) => <option key={m.id} value={m.id}>{m.display_name}</option>)}
          </select>
        </label>
        <label>Poeng
          <input type="number" min={POINTS_MIN} max={POINTS_MAX} step={POINTS_STEP} value={points} onChange={(e) => setPoints(Number(e.target.value))} />
        </label>
        <label>Grunn
          <input type="text" maxLength={REASON_LIMIT} value={reason} placeholder="For eksempel «CTP-konkurranse»" onChange={(e) => setReason(e.target.value)} />
        </label>
        {days.length > 0 && (
          <label>Kveld (valgfritt)
            <select value={eventID} onChange={(e) => setEventID(e.target.value)}>
              <option value="">Ingen</option>
              {days.map((d) => <option key={d.id} value={d.id}>{longDate(d.event_date)}</option>)}
            </select>
          </label>
        )}
        <p className="muted small">Minuspoeng trekkes fra. Kvelden vises ved siden av grunnen.</p>
        <button className="primary" disabled={busy || problem !== null}>Gi tilleggspoeng</button>
      </form>
    </div>
  );
}
