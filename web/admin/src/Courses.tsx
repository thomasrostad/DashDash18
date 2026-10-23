import { useCallback, useEffect, useState } from "react";
import {
  HOLE_COUNTS, PAR_CHOICES, courseSummary, draftFromRows, draftPar, fillStandardPar, fillStandardText, kindText, newDraft,
  setHole, setHoleCount, tapPar, validate, type CourseDraft, type CourseHoleRow, type CourseRow,
} from "./courses.ts";
import { clubCourses, deleteCourse, saveCourse } from "./coursesApi.ts";
import { errorText } from "./supabase.ts";

/** Fanen «Baner»: klubbens baner, og lage eller endre én, som BanerAdminView og CourseEditView i appen. */
export function Courses({ clubID }: { clubID: string }) {
  const [courses, setCourses] = useState<CourseRow[] | null>(null);
  const [holes, setHoles] = useState<CourseHoleRow[]>([]);
  const [editing, setEditing] = useState<{ id: string | null; draft: CourseDraft } | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);

  const load = useCallback(async () => {
    setError(null);
    try { const r = await clubCourses(clubID); setCourses(r.courses); setHoles(r.holes); }
    catch (e) { setError(errorText(e)); }
  }, [clubID]);

  useEffect(() => { load(); }, [load]);

  if (editing) {
    return (
      <CourseEditor clubID={clubID} id={editing.id} initial={editing.draft}
        onDone={(message) => { setEditing(null); setNotice(message); load(); }} onCancel={() => setEditing(null)} />
    );
  }

  return (
    <section>
      <div className="inline">
        <button className="primary" onClick={() => { setNotice(null); setEditing({ id: null, draft: newDraft() }); }}>Ny bane</button>
      </div>
      <p className="muted">Simulatorbaner og ekte baner klubben spiller. Banen kan velges når en runde settes opp, når alle hullene har par.</p>
      {error && <p className="error">{error}</p>}
      {notice && <p className="ok">{notice}</p>}
      {!courses ? <p className="muted">Henter …</p> : courses.length === 0 ? <p className="muted">Ingen baner ennå.</p> : (
        <table>
          <thead><tr><th>Bane</th><th>Type</th><th>Hull</th><th>I bruk</th></tr></thead>
          <tbody>
            {courses.map((c) => {
              const own = holes.filter((h) => h.course_id === c.id);
              return (
                <tr key={c.id} className={c.in_use ? "click" : "click past"}
                  onClick={() => { setNotice(null); setEditing({ id: c.id, draft: draftFromRows(c, own) }); }}>
                  <td>{c.name}{c.external_name && <span className="muted"> · {c.external_name}</span>}</td>
                  <td>{kindText(c.kind)}</td>
                  <td>{courseSummary(own)}</td>
                  <td>{c.in_use ? "Ja" : "Nei"}</td>
                </tr>
              );
            })}
          </tbody>
        </table>
      )}
    </section>
  );
}

function CourseEditor({ clubID, id, initial, onDone, onCancel }: {
  clubID: string; id: string | null; initial: CourseDraft; onDone: (message: string) => void; onCancel: () => void;
}) {
  const [d, setD] = useState(initial);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const v = validate(d);
  const errors = v.issues.filter((i) => i.blocking);
  const warnings = v.issues.filter((i) => !i.blocking);
  const missing = d.holes.filter((h) => h.par === null);
  const source = d.kind === "simulator" ? "skjermen" : "scorekortet";
  const par = draftPar(d);

  async function save() {
    if (!v.values) return;
    setBusy(true); setError(null);
    try { await saveCourse(clubID, id, v.values); onDone(`${v.values.name} er lagret.`); }
    catch (e) { setError(errorText(e)); }
    finally { setBusy(false); }
  }

  async function remove() {
    if (!id || !confirm(`Slette ${initial.name || "banen"}? Banen og hullene forsvinner fra biblioteket.`)) return;
    setBusy(true); setError(null);
    try { await deleteCourse(id); onDone(`${initial.name} er slettet.`); }
    catch (e) { setError(errorText(e)); }
    finally { setBusy(false); }
  }

  return (
    <section>
      <button className="link" onClick={onCancel}>← Alle baner</button>
      <h2>{id ? d.name || "Bane" : "Ny bane"}</h2>
      <div className="grid2">
        <div className="card">
          <h3>Banen</h3>
          <form onSubmit={(e) => e.preventDefault()}>
            <label>Navn<input value={d.name} maxLength={80} onChange={(e) => setD({ ...d, name: e.target.value })} /></label>
            <div className="inline">
              <label>Type
                <select value={d.kind} onChange={(e) => setD({ ...d, kind: e.target.value as CourseDraft["kind"] })}>
                  <option value="simulator">Simulator</option><option value="course">Ekte bane</option>
                </select>
              </label>
              <label>Antall hull
                <select value={d.holes.length} onChange={(e) => setD(setHoleCount(d, Number(e.target.value)))}>
                  {HOLE_COUNTS.map((n) => <option key={n} value={n}>{n} hull</option>)}
                </select>
              </label>
            </div>
            {d.kind === "simulator" && (
              <label>Navn i simulatoren (valgfritt)
                <input value={d.externalName} maxLength={80} onChange={(e) => setD({ ...d, externalName: e.target.value })} />
              </label>
            )}
            <p className="muted">{d.kind === "simulator"
              ? "Navnet i simulatoren er det dere slår opp i båsen, hvis det er et annet enn vårt."
              : "En ekte bane spilles ute. Les tallene av scorekortet."}</p>
          </form>
          <h4>Rating (valgfritt)</h4>
          <div className="inline">
            <label>Course Rating<input inputMode="decimal" placeholder="Par" value={d.courseRatingText} onChange={(e) => setD({ ...d, courseRatingText: e.target.value })} /></label>
            <label>Slope<input inputMode="numeric" placeholder="113" value={d.slopeText} onChange={(e) => setD({ ...d, slopeText: e.target.value })} /></label>
          </div>
          <p className="muted">Tomt felt regnes som banens par og slope 113. Da får spilleren handicapindeksen sin rett, som når simulatoren deler ut slagene.</p>
          <label className="check"><input type="checkbox" checked={d.inUse} onChange={(e) => setD({ ...d, inUse: e.target.checked })} />I bruk</label>
        </div>

        <div className="card">
          <h3>Par{par !== null && ` ${par}`}</h3>
          <p className="muted">
            {missing.length === 0 ? "Banen kan velges når en runde settes opp." : `Banen er klar når alle hullene har par. Les dem av ${source}. Indeks, lengde og rating er valgfritt.`}
            {missing.length > 0 && ` Standardforslaget er bare et utgangspunkt: sjekk hvert hull mot ${source}.`}
          </p>
          {missing.length > 0 && <button type="button" className="tab" onClick={() => setD(fillStandardPar(d))}>{fillStandardText(d)}</button>}
          <table className="holes">
            <thead><tr><th>Hull</th><th>Par</th><th>Indeks</th><th>Meter</th></tr></thead>
            <tbody>
              {d.holes.map((h) => (
                <tr key={h.number}>
                  <td>{h.number}</td>
                  <td>
                    <div className="par-buttons" role="group" aria-label={`Par på hull ${h.number}`}>
                      {PAR_CHOICES.map((p) => (
                        <button key={p} type="button" className={h.par === p ? "par on" : "par"} aria-pressed={h.par === p}
                          onClick={() => setD(tapPar(d, p, h.number))}>{p}</button>
                      ))}
                    </div>
                  </td>
                  <td><input className="cell num" inputMode="numeric" aria-label={`Indeks på hull ${h.number}`} value={h.strokeIndexText}
                    onChange={(e) => setD(setHole(d, h.number, { strokeIndexText: e.target.value }))} /></td>
                  <td><input className="cell num" inputMode="numeric" aria-label={`Lengde i meter på hull ${h.number}`} value={h.lengthText}
                    onChange={(e) => setD(setHole(d, h.number, { lengthText: e.target.value }))} /></td>
                </tr>
              ))}
            </tbody>
          </table>
          <p className="muted">Trykk par for hvert hull. Trykk en gang til for å tømme. Indeksen sier hvilke hull som gir slag først. Den trengs bare når appen selv deler ut slagene. Deler simulatoren ut slagene, kan den stå tom.</p>
        </div>
      </div>

      {errors.length > 0 && <ul className="plain error">{errors.map((i) => <li key={i.message}>{i.message}</li>)}</ul>}
      {warnings.length > 0 && <ul className="plain muted">{warnings.map((i) => <li key={i.message}>{i.message}</li>)}</ul>}
      {error && <p className="error">{error}</p>}
      <div className="inline">
        <button className="primary" disabled={busy || !v.values} onClick={save}>Lagre</button>
        <button className="link" disabled={busy} onClick={onCancel}>Avbryt</button>
        <span className="spacer" />
        {id && <button className="danger" disabled={busy} onClick={remove}>Slett banen</button>}
      </div>
      {id && <p className="muted">Sletting går bare når ingen runder bruker banen.</p>}
    </section>
  );
}
