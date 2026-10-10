import { useEffect, useState } from "react";
import type { RoundPlayerRow } from "../../../golfgutu-core/src/index.ts";
import { loadStartList, saveStartList, type ListRound, type StaffOption } from "./api.ts";
import { fillTimes, namesText, shotgun, startGroups, startListIssues, type StartGroupDraft } from "./startlist.ts";

interface RoundStart {
  round: ListRound;
  title: string;
  wave: number;
  groups: StartGroupDraft[];
}

/**
 * Startlista for spilledagen (StartListView): per runde puljen og gruppene med starttid, starthull, bås/tee og
 * funksjonær. Gruppene er båsene eller flightene fra runde-oppsettet. Lagres med `save_start_list`.
 */
export function StartListEditor({ eventID, rounds, names, onSaved }: {
  eventID: string; rounds: { round: ListRound; title: string; players: RoundPlayerRow[] }[]; names: Map<string, string>; onSaved: () => void;
}) {
  const [state, setState] = useState<RoundStart[] | null>(null);
  const [staff, setStaff] = useState<StaffOption[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [timing, setTiming] = useState<{ first: string; interval: number }>({ first: "18:00", interval: 10 });

  // Lastes én gang per sett med runder, så det som er endret ikke overskrives når siden tegnes på nytt.
  const key = rounds.map((r) => r.round.id).join(",");
  useEffect(() => {
    loadStartList(eventID, rounds.map((r) => r.round.id))
      .then(({ saved, staff }) => {
        setStaff(staff);
        setState(rounds.map((r) => ({
          round: r.round, title: r.title, wave: r.round.waveNo,
          groups: startGroups(r.players, saved.filter((s) => s.round_id === r.round.id), r.round.venue),
        })));
      })
      .catch((e) => setError((e as Error).message));
  }, [eventID, key]);

  if (!state) return error ? <p className="error">{error}</p> : <p className="muted">Henter startlista …</p>;

  const update = (ri: number, f: (r: RoundStart) => RoundStart) => setState(state.map((r, i) => (i === ri ? f(r) : r)));
  const updateGroup = (ri: number, gi: number, patch: Partial<StartGroupDraft>) =>
    update(ri, (r) => ({ ...r, groups: r.groups.map((g, i) => (i === gi ? { ...g, ...patch } : g)) }));

  async function save() {
    if (!state) return;
    const staffIDs = new Set(staff.map((s) => s.id));
    for (const r of state) {
      const issue = startListIssues(r.groups, r.wave, r.round.holeCount, staffIDs)[0];
      if (issue) { setError(`${r.title}: ${issue}`); return; }
    }
    setBusy(true); setError(null);
    try {
      for (const r of state) await saveStartList(r.round.id, r.wave, r.groups);
      onSaved();
    } catch (e) { setError((e as Error).message); }
    finally { setBusy(false); }
  }

  return (
    <div>
      <h3>Startliste</h3>
      {state.length === 0 && <p className="muted">Ingen runder å sette opp startliste for. Låste runder er ikke med.</p>}
      {state.map((r, ri) => (
        <div className="card" key={r.round.id}>
          <h3>{r.title}</h3>
          <div className="inline">
            <label className="check">Pulje
              <input type="number" min={1} max={20} value={r.wave} onChange={(e) => update(ri, (x) => ({ ...x, wave: Number(e.target.value) || 1 }))} />
            </label>
            <label className="check">Første tid
              <input type="time" value={timing.first} onChange={(e) => setTiming({ ...timing, first: e.target.value })} />
            </label>
            <label className="check">Minutter mellom
              <input type="number" min={0} max={60} value={timing.interval} onChange={(e) => setTiming({ ...timing, interval: Number(e.target.value) || 0 })} />
            </label>
            <button className="link" onClick={() => update(ri, (x) => ({ ...x, groups: fillTimes(x.groups, timing.first, timing.interval) }))}>Fyll inn tidene</button>
            <button className="link" onClick={() => update(ri, (x) => ({ ...x, groups: shotgun(x.groups, x.round.holeCount) }))}>Kanonstart</button>
          </div>
          {r.groups.length === 0 ? <p className="muted">Runden har ingen båser eller flighter ennå. Sett dem opp i runden først.</p> : (
            <table>
              <thead><tr><th>Gruppe</th><th>Spillere</th><th>Tid</th><th>Starthull</th><th>Bås eller tee</th><th>Funksjonær</th></tr></thead>
              <tbody>
                {r.groups.map((g, gi) => (
                  <tr key={g.groupNo}>
                    <td>{g.groupNo}</td>
                    <td>{namesText(g.memberIDs.map((id) => names.get(id) ?? "Ukjent"))}</td>
                    <td><input className="cell num" type="time" value={g.startsAt ?? ""} onChange={(e) => updateGroup(ri, gi, { startsAt: e.target.value || null })} /></td>
                    <td><input className="cell num" type="number" min={1} max={r.round.holeCount} value={g.startHole ?? ""}
                      onChange={(e) => updateGroup(ri, gi, { startHole: e.target.value ? Number(e.target.value) : null })} /></td>
                    <td><input className="cell" maxLength={40} value={g.resourceLabel} onChange={(e) => updateGroup(ri, gi, { resourceLabel: e.target.value })} /></td>
                    <td>
                      <select value={g.scorerID ?? ""} onChange={(e) => updateGroup(ri, gi, { scorerID: e.target.value || null })}>
                        <option value="">Ingen</option>
                        {staff.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
                      </select>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
      ))}
      {staff.length === 0 && <p className="muted small">Funksjonærer velges fra staben i turneringen. Legg dem til på turneringssiden.</p>}
      {error && <p className="error">{error}</p>}
      <div className="inline">
        <button className="primary" disabled={busy || state.length === 0} onClick={save}>Lagre startlista</button>
      </div>
    </div>
  );
}
