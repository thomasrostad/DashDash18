import { useState } from "react";
import { saveRules, type Competition } from "./data.ts";
import { decodeRuleset, encodeRuleset, matchingTemplate, templateTitle, validateRuleset, type Ruleset } from "./engine.ts";
import { errorText } from "./supabase.ts";

/** De vanligste reglene, som «Tilpass reglene» i appen. Lagres som hele regelsettet (samme JSON som appen). */
export function RulesEditor({ competition, onSaved }: { competition: Competition; onSaved: () => void }) {
  const [rules, setRules] = useState<Ruleset>(() => decodeRuleset(competition.rules));
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const isSeason = competition.kind === "season";
  const finished = competition.status === "finished";
  const template = matchingTemplate(rules, undefined, competition.kind === "league");
  const league = competition.kind === "fun" ? rules.competition?.fun : competition.kind === "league" ? rules.competition?.league : null;
  const set = (f: (r: Ruleset) => void) => { const r = structuredClone(rules); f(r); setRules(r); setNotice(null); };

  async function save(e: React.FormEvent) {
    e.preventDefault();
    const issues = validateRuleset(rules);
    if (issues.length) { setError(issues[0].message); return; }
    setBusy(true); setError(null);
    try { await saveRules(competition, encodeRuleset(rules)); setNotice("Reglene er lagret."); onSaved(); }
    catch (err) { setError(errorText(err)); } finally { setBusy(false); }
  }

  return (
    <form className="card" onSubmit={save}>
      <h3>Reglene <span className="pill">{template ? templateTitle(template) : "Tilpasset"}</span></h3>
      {finished && <p className="muted">Turneringen er ferdig. Reglene kan ikke endres.</p>}
      <fieldset disabled={finished || busy}>
        {isSeason && <>
          <label>Antall kvelder/spilledager<input type="number" min={1} max={40} value={rules.evenings} onChange={(e) => set((r) => { r.evenings = Number(e.target.value); })} /></label>
          <label>Tabellen teller
            <select value={rules.table.pointsSource} onChange={(e) => set((r) => { r.table.pointsSource = e.target.value as Ruleset["table"]["pointsSource"]; })}>
              <option value="matches">Matcher</option><option value="stableford">Stableford-poeng</option>
            </select>
          </label>
          <label>Hvor mange teller
            <select value={rules.table.counting.best ?? ""} onChange={(e) => set((r) => { r.table.counting.best = e.target.value ? Number(e.target.value) : null; })}>
              <option value="">Alle</option>{Array.from({ length: 20 }, (_, i) => i + 1).map((n) => <option key={n} value={n}>De beste {n}</option>)}
            </select>
          </label>
          <label>En dag heter
            <select value={rules.dayTerm ?? "evening"} onChange={(e) => set((r) => { r.dayTerm = e.target.value as Ruleset["dayTerm"]; })}>
              <option value="evening">Kveld</option><option value="playingDay">Spilledag</option>
            </select>
          </label>
          <label className="check"><input type="checkbox" checked={rules.sidePrizes.longestDrive.enabled} onChange={(e) => set((r) => { r.sidePrizes.longestDrive.enabled = e.target.checked; })} />Longest drive gir poeng</label>
          <label className="check"><input type="checkbox" checked={rules.sidePrizes.closestToPin.enabled} onChange={(e) => set((r) => { r.sidePrizes.closestToPin.enabled = e.target.checked; })} />Nærmest pinnen gir poeng</label>
        </>}
        {league && <>
          <label>Hvor mange runder teller
            <select value={league.bestRounds ?? ""} onChange={(e) => set((r) => { const l = competition.kind === "fun" ? r.competition!.fun : r.competition!.league; l.bestRounds = e.target.value ? Number(e.target.value) : null; })}>
              <option value="">Alle</option>{Array.from({ length: 20 }, (_, i) => i + 1).map((n) => <option key={n} value={n}>De beste {n}</option>)}
            </select>
          </label>
          <label>Poeng for å spille en runde
            <input type="number" min={0} max={20} step={0.5} value={league.participationPoints}
              onChange={(e) => set((r) => { const l = competition.kind === "fun" ? r.competition!.fun : r.competition!.league; l.participationPoints = Number(e.target.value); })} />
          </label>
        </>}
        <label>Handicapandel (tomt: per form)
          <input type="number" min={0} max={100} step={5} value={rules.handicap.allowanceOverride === null ? "" : Math.round(rules.handicap.allowanceOverride * 100)}
            onChange={(e) => set((r) => { r.handicap.allowanceOverride = e.target.value === "" ? null : Number(e.target.value) / 100; })} />
        </label>
      </fieldset>
      {isSeason && competition.status === "active" && <p className="muted">Endrede regler gjelder også det som er spilt.</p>}
      {error && <p className="error">{error}</p>}
      {notice && <p className="ok">{notice}</p>}
      {!finished && <button className="primary" disabled={busy}>Lagre reglene</button>}
    </form>
  );
}
