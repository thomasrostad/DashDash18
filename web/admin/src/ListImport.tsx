import { useState } from "react";
import { countText, handicapText, problemText, validLines, type ImportLine } from "./listImport.ts";
import { errorText } from "./supabase.ts";

/** «Lim inn liste»: tekstfeltet, forhåndsvisningen (hva legges til, og hvorfor noe hoppes over) og knappen.
 *  Brukes av Troppen og av deltakerne i en turnering, som TroppImportView og ParticipantImportView i appen. */
export function ListImport({ title, intro, help, parse, participants = false, onAdd, children }: {
  title: string; intro?: string; help: string; parse: (text: string) => ImportLine[]; participants?: boolean;
  /** Lagrer linjene som kan legges til og gir meldingen som vises etterpå. */
  onAdd: (lines: ImportLine[]) => Promise<string>;
  /** Vises under meldingen når lista er lagret (f.eks. lenken til turneringen). */
  children?: React.ReactNode;
}) {
  const [text, setText] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [done, setDone] = useState<string | null>(null);
  const lines = parse(text);
  const valid = validLines(lines);

  async function add(e: React.FormEvent) {
    e.preventDefault();
    if (valid.length === 0) return;
    setBusy(true); setError(null); setDone(null);
    try { setDone(await onAdd(valid)); setText(""); }
    catch (err) { setError(errorText(err)); }
    finally { setBusy(false); }
  }

  return (
    <form className="card" onSubmit={add}>
      <h3>{title}</h3>
      {intro && <p className="muted">{intro}</p>}
      <label>Ett navn per linje
        <textarea rows={8} value={text} disabled={busy} spellCheck={false} autoCapitalize="words"
          onChange={(e) => { setText(e.target.value); setDone(null); }} />
      </label>
      <p className="muted">{help}</p>
      {lines.length > 0 && (
        <>
          <h4>{countText(lines)}</h4>
          <ul className="import-lines">
            {lines.map((l, i) => (
              <li key={i} className={l.problem ? "skipped" : ""}>
                <span aria-hidden>{l.problem ? "!" : "✓"}</span>
                <span>
                  <span className="name">{l.name || l.text}</span>
                  {l.problem && <span className="muted"> · {problemText(l, participants)}</span>}
                </span>
                {!l.problem && (
                  <span className="muted">
                    {l.handicapIndex !== null && `hcp ${handicapText(l.handicapIndex)}`}
                    {l.ngfNumber && `${l.handicapIndex !== null ? " · " : ""}NGF ${l.ngfNumber}`}
                  </span>
                )}
              </li>
            ))}
          </ul>
        </>
      )}
      <div className="inline">
        <button className="primary" disabled={busy || valid.length === 0}>{valid.length === 0 ? "Legg til" : `Legg til ${valid.length}`}</button>
      </div>
      {error && <p className="error">{error}</p>}
      {done && <><p className="ok">{done}</p>{children}</>}
    </form>
  );
}
