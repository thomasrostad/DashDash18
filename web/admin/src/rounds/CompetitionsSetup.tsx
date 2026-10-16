import { useState } from "react";
import { formById } from "../../../golfgutu-core/src/index.ts";
import {
  axesOf, chosenTeams, competitionIssues, competitionSummary, isOneBallMatch, MAX_COMPETITIONS, maxStrokesOf, recipeDraft, recipesFor, setSide,
  sideProblem, teamNumbers, withMatchTeam, withMaxStrokes,
  type CompetitionContext, type CompetitionDraft, type EntrantMode, type HolesChoice, type RecipeID, type Side,
} from "./competitions.ts";

/**
 * «Konkurranser i runden» (sql/048): hovedkonkurransen er formen over, og de andre legges til fra oppskrifter.
 * Hvem som er med, hull og andel ligger bak «Avansert».
 */
export function CompetitionsCard({ list, ctx, name, onChange }: {
  list: CompetitionDraft[]; ctx: CompetitionContext; name: (id: string) => string; onChange: (list: CompetitionDraft[]) => void;
}) {
  const [open, setOpen] = useState<number | null>(null);
  const issues = competitionIssues(list, ctx);
  const update = (i: number, d: CompetitionDraft) => onChange(list.map((x, j) => (j === i ? d : x)));
  return (
    <div className="card">
      <h3>Konkurranser i runden</h3>
      <ul className="plain">
        <li><strong>{formById(ctx.mainForm).name}</strong> <span className="muted small">Hovedkonkurransen · alle · alle hull</span></li>
        {list.map((d, i) => (
          <li key={i}>
            <strong>{d.name || "Uten navn"}</strong> <span className="muted small">{competitionSummary(d, ctx.holeCount)}</span>{" "}
            <button className="link" onClick={() => setOpen(open === i ? null : i)}>{open === i ? "Lukk" : "Avansert"}</button>
            <button className="link" onClick={() => { onChange(list.filter((_, j) => j !== i)); setOpen(null); }}>Fjern</button>
            {open === i && <CompetitionDetails d={d} ctx={ctx} name={name} onChange={(x) => update(i, x)} />}
          </li>
        ))}
      </ul>
      {list.length + 1 < MAX_COMPETITIONS && (
        <label>Legg til
          <select value="" onChange={(e) => { if (e.target.value) onChange([...list, recipeDraft(e.target.value as RecipeID, ctx.mainForm)]); }}>
            <option value="">Velg</option>
            {recipesFor(ctx.holeCount).map((r) => <option key={r.id} value={r.id}>{r.name} · {r.help}</option>)}
          </select>
        </label>
      )}
      {issues.map((x) => <p key={x} className="error small">{x}</p>)}
    </div>
  );
}

function CompetitionDetails({ d, ctx, name, onChange }: {
  d: CompetitionDraft; ctx: CompetitionContext; name: (id: string) => string; onChange: (d: CompetitionDraft) => void;
}) {
  const scoring = axesOf(d).scoring;
  const isMatch = scoring.type === "matchPlay";
  const cap = maxStrokesOf(d);
  const oneBall = isOneBallMatch(d);
  const teams = teamNumbers(ctx);
  const chosen = chosenTeams(d, ctx);
  const teamName = (t: number) => `Lag ${t}: ${ctx.participants.filter((id) => ctx.teams[id] === t).map(name).join(" og ")}`;
  const entrantChoices: { value: EntrantMode; title: string }[] = oneBall ? [
    { value: "sides", title: "Rundens to lag" },
    { value: "twoTeams", title: "To valgte lag" },
  ] : isMatch ? [
    { value: "selected", title: "To valgte spillere" },
    { value: "sides", title: "Side 1 mot side 2 (lag mot lag)" },
  ] : [
    { value: "all", title: "Alle" },
    { value: "selected", title: "Valgte spillere" },
    { value: "teams", title: "Parene (lagene, ellers to og to i båsen)" },
    { value: "groups", title: "Gruppene (lagene, ellers båsene)" },
  ];
  return (
    <fieldset>
      <label>Navn<input value={d.name} maxLength={60} onChange={(e) => onChange({ ...d, name: e.target.value })} /></label>
      <label>Hvem er med
        <select value={isMatch && d.entrants === "all" ? "sides" : d.entrants} onChange={(e) => {
          const mode = e.target.value as EntrantMode;
          // To valgte lag: de to første til å begynne med.
          if (mode === "twoTeams" && chosen.length < 2 && teams.length >= 2) onChange(withMatchTeam(withMatchTeam({ ...d, selected: [] }, ctx, 0, teams[0]), ctx, 1, teams[1]));
          else onChange({ ...d, entrants: mode });
        }}>
          {entrantChoices.map((c) => <option key={c.value} value={c.value}>{c.title}</option>)}
        </select>
      </label>
      {oneBall && d.entrants === "twoTeams" && (
        <div className="inline">
          {([0, 1] as const).map((i) => (
            <label key={i}>Lag {i + 1}
              <select value={chosen[i] ?? ""} onChange={(e) => { if (e.target.value) onChange(withMatchTeam(d, ctx, i, Number(e.target.value))); }}>
                {chosen[i] === undefined && <option value="">Velg</option>}
                {teams.map((t) => <option key={t} value={t}>{teamName(t)}</option>)}
              </select>
            </label>
          ))}
        </div>
      )}
      {oneBall && <p className="muted small">Lagets ene score teller på hullet, med lagets handicap etter reglene. Matchen er over når ett lag er flere hull opp enn det er igjen.</p>}
      {d.entrants === "selected" && (
        <div className="chips">
          {ctx.participants.map((id) => (
            <label key={id} className="check"><input type="checkbox" checked={d.selected.includes(id)}
              onChange={(e) => onChange({ ...d, selected: e.target.checked ? [...d.selected, id] : d.selected.filter((x) => x !== id) })} />{name(id)}</label>
          ))}
        </div>
      )}
      {scoring.type === "maximumScore" && (
        <div className="inline">
          <label>Tak per hull
            <select value={cap?.type === "fixed" ? "fixed" : "rules"}
              onChange={(e) => onChange(withMaxStrokes(d, e.target.value === "fixed" ? { type: "fixed", strokes: 8 } : null))}>
              <option value="rules">Som regelsettet (standard netto dobbel bogey)</option>
              <option value="fixed">Fast antall slag</option>
            </select>
          </label>
          {cap?.type === "fixed" && (
            <label className="check">Slag
              <input type="number" min={3} max={20} step={1} value={cap.strokes}
                onChange={(e) => onChange(withMaxStrokes(d, { type: "fixed", strokes: Math.max(3, Math.min(20, Math.round(Number(e.target.value) || 3))) }))} />
            </label>
          )}
        </div>
      )}
      <label>Hull
        <select value={d.holes} onChange={(e) => onChange({ ...d, holes: e.target.value as HolesChoice })}>
          <option value="all">Alle</option>
          {ctx.holeCount === 18 && <option value="front">1–9</option>}
          {ctx.holeCount === 18 && <option value="back">10–18</option>}
        </select>
      </label>
      <div className="inline">
        <label className="check"><input type="checkbox" checked={d.allowance !== null}
          onChange={(e) => onChange({ ...d, allowance: e.target.checked ? 1 : null })} />Egen handicapandel</label>
        {d.allowance !== null && (
          <label className="check">Andel (%)
            <input type="number" min={0} max={100} step={5} value={Math.round(d.allowance * 100)}
              onChange={(e) => onChange({ ...d, allowance: Math.max(0, Math.min(100, Number(e.target.value) || 0)) / 100 })} />
          </label>
        )}
      </div>
      <p className="muted small">Andelen gjelder spillehandicapet i runden.</p>
    </fieldset>
  );
}

/** Lag mot lag (sql/048): side 1 eller 2 per spiller. Et lag følger spilleren. */
export function SidesCard({ participants, sides, teams, name, onChange }: {
  participants: string[]; sides: Record<string, Side>; teams: Record<string, number>; name: (id: string) => string;
  onChange: (sides: Record<string, Side>) => void;
}) {
  const used = Object.keys(sides).length > 0;
  const problem = sideProblem(sides, teams, participants);
  return (
    <details className="card" open={used}>
      <summary><strong>Lag mot lag</strong></summary>
      <p className="muted small">Del spillerne i to sider. Matchene gir poeng til siden.</p>
      {participants.map((id) => (
        <label key={id} className="row-inline">{name(id)}{teams[id] !== undefined ? ` · lag ${teams[id]}` : ""}
          <select value={sides[id] ?? ""} onChange={(e) => onChange(setSide(sides, teams, id, e.target.value ? (Number(e.target.value) as Side) : null))}>
            <option value="">Ingen side</option>
            <option value="1">Side 1</option>
            <option value="2">Side 2</option>
          </select>
        </label>
      ))}
      {used && <button className="link" onClick={() => onChange({})}>Ta bort sidene</button>}
      {problem && <p className="error small">{problem}</p>}
    </details>
  );
}
