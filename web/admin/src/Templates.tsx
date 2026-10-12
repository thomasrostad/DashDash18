import { useCallback, useEffect, useState } from "react";
import { templateNameError, type SetupTemplate, type TemplateKind } from "./reuse.ts";
import { deleteTemplate, reuseAvailable, saveTemplate, templates } from "./reuseApi.ts";
import { errorText } from "./supabase.ts";

/**
 * Egne maler (sql/049): «Bruk mal», «Lagre som mal» og en liten liste for å gi nytt navn og slette.
 * Skjules når 049 mangler. Klubbens maler (web-admin er alltid i en klubb).
 */
export function TemplateBar({ clubID, kind, payload, onUse, canSave = true }: {
  clubID: string; kind: TemplateKind; payload: () => Record<string, unknown>; onUse: (t: SetupTemplate) => void;
  /** Av der det ikke finnes noe å lagre (steg 1 i «Ny turnering»). */
  canSave?: boolean;
}) {
  const [available, setAvailable] = useState(false);
  const [list, setList] = useState<SetupTemplate[]>([]);
  const [chosen, setChosen] = useState("");
  const [name, setName] = useState("");
  const [showsList, setShowsList] = useState(false);
  const [notice, setNotice] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const load = useCallback(async () => {
    if (!(await reuseAvailable())) { setAvailable(false); return; }
    try { setList(await templates(clubID, kind)); setAvailable(true); } catch (e) { setError(errorText(e)); }
  }, [clubID, kind]);
  useEffect(() => { load(); }, [load]);

  if (!available || (!canSave && list.length === 0)) return null;

  async function run(action: () => Promise<string>) {
    setBusy(true); setError(null); setNotice(null);
    try { setNotice(await action()); await load(); } catch (e) { setError(errorText(e)); } finally { setBusy(false); }
  }

  function save() {
    const problem = templateNameError(name, list, kind);
    if (problem) { setError(problem); return; }
    run(async () => {
      const saved = await saveTemplate({ id: null, clubID, kind, name, payload: payload() });
      setName("");
      return `Lagret som «${saved.name}».`;
    });
  }

  function rename(t: SetupTemplate) {
    const next = prompt("Nytt navn", t.name);
    if (next === null || next.trim() === t.name) return;
    const problem = templateNameError(next, list, kind, t.id);
    if (problem) { setError(problem); return; }
    run(async () => { await saveTemplate({ id: t.id, clubID, kind, name: next, payload: t.payload }); return "Navnet er endret."; });
  }

  function remove(t: SetupTemplate) {
    if (!confirm(`Slette malen «${t.name}»?`)) return;
    run(async () => { await deleteTemplate(t.id); return `«${t.name}» er slettet.`; });
  }

  return (
    <div className="card">
      <h3>Maler</h3>
      <div className="grid2 tight">
        {list.length > 0 && (
          <label>Bruk mal
            <span className="inline">
              <select value={chosen} onChange={(e) => setChosen(e.target.value)}>
                <option value="">Velg</option>
                {list.map((t) => <option key={t.id} value={t.id}>{t.name}</option>)}
              </select>
              <button type="button" disabled={!chosen || busy} onClick={() => {
                const t = list.find((x) => x.id === chosen);
                if (t) { onUse(t); setNotice(`Fylt inn fra «${t.name}».`); }
              }}>Bruk</button>
            </span>
          </label>
        )}
        {canSave && (
          <label>Lagre som mal
            <span className="inline">
              <input value={name} maxLength={60} placeholder="Navn" onChange={(e) => setName(e.target.value)} />
              <button type="button" disabled={busy || !name.trim()} onClick={save}>Lagre</button>
            </span>
          </label>
        )}
      </div>
      {list.length > 0 && <button type="button" className="link" onClick={() => setShowsList(!showsList)}>{showsList ? "Skjul malene" : `Endre maler (${list.length})`}</button>}
      {showsList && (
        <ul className="plain">
          {list.map((t) => (
            <li key={t.id} className="inline">
              <span>{t.name}</span>
              <button type="button" className="link" disabled={busy} onClick={() => rename(t)}>Gi nytt navn</button>
              <button type="button" className="link" disabled={busy} onClick={() => remove(t)}>Slett</button>
            </li>
          ))}
        </ul>
      )}
      {notice && <p className="muted small">{notice}</p>}
      {error && <p className="error">{error}</p>}
    </div>
  );
}
