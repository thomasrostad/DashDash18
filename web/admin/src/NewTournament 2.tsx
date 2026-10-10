import { useState } from "react";
import { createCompetition, createSeason, setPlaysWhenItSuits, type Competition } from "./data.ts";
import { encodeRuleset, RULESET_TEMPLATES, templateRules, templateSummary, templateTitle, validateRuleset, type RulesetTemplate } from "./engine.ts";
import { errorText } from "./supabase.ts";
import { todayISO } from "./text.ts";

/** «Ny turnering» som i appen: velg oppsett, navn og det viktigste. Reglene kommer fra samme maler (golfgutu-core). */
export function NewTournament({ clubID, comps, onDone, onCancel }: {
  clubID: string; comps: Competition[]; onDone: () => void; onCancel: () => void;
}) {
  const [template, setTemplate] = useState<RulesetTemplate | null>(null);
  return template === null ? (
    <section>
      <button className="link" onClick={onCancel}>← Avbryt</button>
      <h2>Ny turnering</h2>
      <div className="grid2">
        {RULESET_TEMPLATES.map((t) => (
          <button key={t} className="card choice" onClick={() => setTemplate(t)}>
            <strong>{templateTitle(t)}</strong>
            <span className="muted">{templateSummary(t)}</span>
          </button>
        ))}
      </div>
    </section>
  ) : (
    <Details clubID={clubID} template={template} comps={comps} onDone={onDone} onBack={() => setTemplate(null)} />
  );
}

function suggestedName(t: RulesetTemplate, taken: string[]): string {
  const now = new Date();
  const season = now.getMonth() >= 7 ? "Høst" : now.getMonth() >= 3 ? "Vår" : "Vinter";
  const base = t === "cup" ? `${season}cupen ${now.getFullYear()}` : t === "fun" ? `${season}morro ${now.getFullYear()}` : `${season} ${now.getFullYear()}`;
  let name = base; let n = 2;
  while (taken.some((x) => x.toLowerCase() === name.toLowerCase())) name = `${base} (${n++})`;
  return name;
}

function Details({ clubID, template, comps, onDone, onBack }: {
  clubID: string; template: RulesetTemplate; comps: Competition[]; onDone: () => void; onBack: () => void;
}) {
  const isSeries = template === "stablefordSeries" || template === "matchSeries";
  const base = templateRules(template);
  const today = todayISO();
  const [name, setName] = useState(suggestedName(template, comps.map((c) => c.name)));
  const [evenings, setEvenings] = useState(base.evenings);
  const [dayTerm, setDayTerm] = useState<"evening" | "playingDay">("playingDay");
  const [start, setStart] = useState(false);
  const [entry, setEntry] = useState(template === "cup" ? "listed" : "club");
  const [signupOpen, setSignupOpen] = useState(true);
  const [hasPeriod, setHasPeriod] = useState(false);
  const [startsOn, setStartsOn] = useState(today);
  const [endsOn, setEndsOn] = useState(today);
  const [whenItSuits, setWhenItSuits] = useState(false);
  const [best, setBest] = useState<number | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const activeMain = comps.find((c) => c.kind === "season" && c.status === "active");

  function rules() {
    const r = templateRules(template);
    if (isSeries) { r.evenings = evenings; r.dayTerm = dayTerm; }
    if (template === "fun" && r.competition) r.competition.fun.bestRounds = whenItSuits ? best : r.competition.fun.bestRounds;
    return r;
  }

  async function save(e: React.FormEvent) {
    e.preventDefault();
    const r = rules();
    const issues = validateRuleset(r);
    if (!name.trim()) { setError("Gi turneringen et navn."); return; }
    if (issues.length) { setError(issues[0].message); return; }
    if ((hasPeriod || whenItSuits) && endsOn < startsOn) { setError("Perioden slutter før den starter."); return; }
    setBusy(true); setError(null);
    try {
      if (isSeries) {
        await createSeason(clubID, name, encodeRuleset(r), start);
      } else {
        const period = hasPeriod || whenItSuits;
        const id = await createCompetition({
          clubID, kind: template as "cup" | "fun", name, entry: template === "cup" ? "listed" : entry, rules: encodeRuleset(r),
          startsOn: period ? startsOn : null, endsOn: period ? endsOn : null, signupOpen: (template === "cup" || entry === "listed") && signupOpen,
        });
        if (whenItSuits) await setPlaysWhenItSuits(id, true);
      }
      onDone();
    } catch (err) { setError(errorText(err)); } finally { setBusy(false); }
  }

  return (
    <section>
      <button className="link" onClick={onBack}>← Oppsettene</button>
      <h2>{templateTitle(template)}</h2>
      <form className="card" onSubmit={save}>
        <label>Navn<input required maxLength={60} value={name} onChange={(e) => setName(e.target.value)} /></label>
        {isSeries && <>
          <label>Antall {dayTerm === "playingDay" ? "spilledager" : "kvelder"}
            <input type="number" min={1} max={40} value={evenings} onChange={(e) => setEvenings(Number(e.target.value))} /></label>
          <label>En dag heter
            <select value={dayTerm} onChange={(e) => setDayTerm(e.target.value as "evening" | "playingDay")}>
              <option value="playingDay">Spilledag</option><option value="evening">Kveld</option>
            </select>
          </label>
          <label className="check"><input type="checkbox" checked={start} onChange={(e) => setStart(e.target.checked)} />Start turneringen nå</label>
          {start && activeMain && <p className="muted">«{activeMain.name}» er i gang. Den blir avsluttet når denne startes (klubben kan ha én serie i gang).</p>}
        </>}
        {!isSeries && <>
          {template === "fun" && (
            <label>Hvem er med
              <select value={entry} onChange={(e) => setEntry(e.target.value)}>
                <option value="club">Hele troppen</option><option value="listed">De påmeldte</option><option value="open">Alle som spiller en runde som teller</option>
              </select>
            </label>
          )}
          {(template === "cup" || entry === "listed") && (
            <label className="check"><input type="checkbox" checked={signupOpen} onChange={(e) => setSignupOpen(e.target.checked)} />Åpen påmelding</label>
          )}
          {template === "fun" && (
            <label className="check"><input type="checkbox" checked={whenItSuits} onChange={(e) => { setWhenItSuits(e.target.checked); if (e.target.checked) setHasPeriod(true); }} />Spill når det passer (rundene i perioden teller av seg selv)</label>
          )}
          {whenItSuits && (
            <label>Hvor mange runder teller
              <select value={best ?? ""} onChange={(e) => setBest(e.target.value ? Number(e.target.value) : null)}>
                <option value="">Alle runder</option>
                {[1, 2, 3, 4, 5, 6, 8, 10].map((n) => <option key={n} value={n}>De beste {n}</option>)}
              </select>
            </label>
          )}
          <label className="check"><input type="checkbox" checked={hasPeriod} disabled={whenItSuits} onChange={(e) => setHasPeriod(e.target.checked)} />Har en periode</label>
          {hasPeriod && (
            <div className="grid2 tight">
              <label>Fra<input type="date" value={startsOn} onChange={(e) => setStartsOn(e.target.value)} /></label>
              <label>Til<input type="date" value={endsOn} onChange={(e) => setEndsOn(e.target.value)} /></label>
            </div>
          )}
        </>}
        {error && <p className="error">{error}</p>}
        <div className="inline"><button className="primary" disabled={busy}>Lag turneringen</button></div>
      </form>
    </section>
  );
}
