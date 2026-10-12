import { useEffect, useMemo, useState } from "react";
import type { Competition, Membership } from "../data.ts";
import { errorText, supabase } from "../supabase.ts";
import { kindText, statusText } from "../text.ts";
import { fileName, gridCsv, tableCsv, type GridMode } from "./csv.ts";
import type { CupGame, CupSide } from "../../../golfgutu-core/src/index.ts";
import {
  competitionData, cupFooter, cupView, leagueView, parsePlayoffHoles, playoffHoleNumbers, seasonView,
  type CupView, type PlayoffPanel, type StandingsView, type TableView,
} from "./model.ts";
import { loadCompetition, loadSeason, setPlayoffHoles, startPlayoff } from "./queries.ts";
import { hasTableRules } from "../rounds/api.ts";
import { RoundsGridView } from "./RoundsGridView.tsx";
import "./standings.css";

const shown = ["season", "league", "fun", "cup"];

/** Turneringen som vises først: den aktive hovedturneringen, ellers en hovedturnering, ellers den første
 *  som er i gang, ellers den første. Flere serier kan gå samtidig (sql/034). */
export function initial(comps: readonly Pick<Competition, "id" | "kind" | "is_main" | "status">[]): string | null {
  const list = comps.filter((c) => shown.includes(c.kind));
  return (list.find((c) => c.is_main && c.status === "active") ?? list.find((c) => c.is_main)
    ?? list.find((c) => c.status === "active") ?? list[0])?.id ?? null;
}

/** Last ned tekst som fil (CSV med BOM). */
export function download(name: string, text: string) {
  const url = URL.createObjectURL(new Blob([text], { type: "text/csv;charset=utf-8" }));
  const a = document.createElement("a");
  a.href = url;
  a.download = name;
  document.body.appendChild(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}

/** «Tabeller»: tabellen for en serie, liga eller morroturnering, «Alle runder» med scorekort, og cuptreet. */
export function Standings({ comps, membership }: { comps: Competition[]; membership: Membership }) {
  const list = useMemo(() => comps.filter((c) => shown.includes(c.kind)), [comps]);
  const [id, setID] = useState<string | null>(() => initial(comps));
  const [view, setView] = useState<StandingsView | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [reload, setReload] = useState(0);
  const [playoffReady, setPlayoffReady] = useState(false);
  const competition = list.find((c) => c.id === id) ?? null;

  // Playoffen kan startes når sql/047 er kjørt (kolonnene og RPC-ene kom samtidig).
  useEffect(() => { hasTableRules().then(setPlayoffReady, () => setPlayoffReady(false)); }, []);

  useEffect(() => {
    if (!competition) return;
    let cancelled = false;
    setBusy(true);
    setError(null);
    setView(null);
    (async () => {
      const { data } = await supabase.auth.getUser();
      const viewer = { memberID: membership.id, profileID: data.user?.id ?? null };
      if (competition.kind === "season") {
        const { tavlaData, season } = await loadSeason(competition);
        return seasonView(tavlaData, season, membership.id);
      }
      const raw = await loadCompetition(competition.id);
      const d = competitionData(raw);
      return competition.kind === "cup" ? cupView(d, raw.cupMatches, viewer) : leagueView(d, viewer);
    })()
      .then((v) => { if (!cancelled) setView(v); })
      .catch((e) => { if (!cancelled) setError(errorText(e)); })
      .finally(() => { if (!cancelled) setBusy(false); });
    return () => { cancelled = true; };
  }, [competition?.id, competition?.kind, membership.id, reload]); // eslint-disable-line react-hooks/exhaustive-deps

  if (list.length === 0) return <p className="muted">Ingen turneringer med tabell ennå.</p>;

  return (
    <section className="standings">
      <div className="inline no-print picker">
        <label className="pickerLabel">
          Turnering
          <select value={id ?? ""} onChange={(e) => setID(e.target.value)}>
            {list.map((c) => (
              <option key={c.id} value={c.id}>{c.name} · {kindText(c.kind)} · {statusText(c.status)}</option>
            ))}
          </select>
        </label>
      </div>
      {error && <p className="error">{error}</p>}
      {busy && <p className="muted">Henter og regner …</p>}
      {view?.kind === "table" && view.playoff && competition && (
        <PlayoffSection panel={view.playoff} competitionID={competition.id} canAct={playoffReady} onChanged={() => setReload((n) => n + 1)} />
      )}
      {view?.kind === "table" && <TableSection view={view} />}
      {view?.kind === "cup" && <CupSection view={view} />}
    </section>
  );
}

/**
 * Playoffen om førsteplassen (sql/047): «Start playoff» med de som står likt og forslaget til hull, og
 * «Legg til hull» når det fortsatt står likt. Scoren føres i appen (hull for hull, som en vanlig runde).
 */
function PlayoffSection({ panel, competitionID, canAct, onChanged }: {
  panel: PlayoffPanel; competitionID: string; canAct: boolean; onChanged: () => void;
}) {
  const [chosen, setChosen] = useState<Set<string>>(() => new Set(panel.tied.map((t) => t.id)));
  const [holes, setHoles] = useState(() => playoffHoleNumbers(panel.suggested, panel.firstHole));
  const [extra, setExtra] = useState(() => playoffHoleNumbers(panel.suggested.slice(0, 1), panel.firstHole));
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function run(action: () => Promise<void>) {
    setBusy(true); setError(null);
    try { await action(); onChanged(); } catch (e) { setError(errorText(e)); } finally { setBusy(false); }
  }

  const canStart = canAct && panel.round === null && panel.tied.length >= 2;
  return (
    <div className="card no-print">
      <h3>Playoff</h3>
      <p className="muted">{panel.text}</p>
      {error && <p className="error">{error}</p>}
      {canStart && (
        <>
          <div className="inline">
            {panel.tied.map((t) => (
              <label key={t.id} className="check"><input type="checkbox" checked={chosen.has(t.id)} onChange={(e) => {
                const next = new Set(chosen);
                if (e.target.checked) next.add(t.id); else next.delete(t.id);
                setChosen(next);
              }} />{t.name}</label>
            ))}
          </div>
          <label>Hull i rekkefølge
            <input value={holes} onChange={(e) => setHoles(e.target.value)} placeholder="18, 1, 18" />
          </label>
          <button className="primary" disabled={busy || chosen.size < 2 || parsePlayoffHoles(holes, panel.holeCount, panel.firstHole) === null}
            onClick={() => run(async () => {
              await startPlayoff(competitionID, [...chosen], parsePlayoffHoles(holes, panel.holeCount, panel.firstHole)!);
            })}>Start playoff</button>
        </>
      )}
      {canAct && panel.round?.canAddHoles && (
        <div className="inline">
          <label>Flere hull
            <input value={extra} onChange={(e) => setExtra(e.target.value)} placeholder="18" />
          </label>
          <button disabled={busy || parsePlayoffHoles(extra, panel.holeCount, panel.firstHole) === null}
            onClick={() => run(async () => {
              const more = parsePlayoffHoles(extra, panel.holeCount, panel.firstHole)!;
              await setPlayoffHoles(panel.round!.id, [...panel.round!.holes, ...more].slice(0, panel.holeCount));
            })}>Legg til hull</button>
        </div>
      )}
    </div>
  );
}

function TableSection({ view }: { view: TableView }) {
  const [mode, setMode] = useState<GridMode>("points");
  return (
    <>
      <div className="card">
        <div className="headRow">
          <div>
            <h2 className="printTitle">{view.title}</h2>
            <p className="muted">{view.summary}</p>
          </div>
          <span className="spacer" />
          <div className="inline no-print">
            <button className="link" onClick={() => download(fileName(view.title, "tabell"), tableCsv(view))}>Last ned CSV</button>
            <button className="link" onClick={() => window.print()}>Skriv ut</button>
          </div>
        </div>
        {view.rows.length === 0 ? <p className="muted">Ingen er med ennå. Tabellen fylles når en runde teller.</p> : (
          <table className="rank">
            <thead><tr><th className="num">Plass</th><th>Navn</th><th className="num">Poeng</th><th>Detaljer</th></tr></thead>
            <tbody>
              {view.rows.map((r) => (
                <tr key={r.id} className={r.isMe ? "me" : undefined}>
                  <td className="num muted">{r.placeText}</td>
                  <td><strong>{r.name}</strong></td>
                  <td className="num"><strong>{r.totalText}</strong></td>
                  <td className="muted">{r.detail}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
      <div className="card gridCard">
        <div className="headRow">
          <h3>Alle runder</h3>
          <span className="spacer" />
          <div className="inline no-print">
            <div className="segmented" role="group" aria-label="Vis">
              {([["points", "Poeng"], ["strokes", "Slag"], ["toPar", "Mot par"]] as [GridMode, string][]).map(([m, label]) => (
                <button key={m} className={m === mode ? "seg active" : "seg"} onClick={() => setMode(m)}>{label}</button>
              ))}
            </div>
            {view.grid.columns.length > 0 && (
              <button className="link" onClick={() => download(fileName(view.title, "alle runder"), gridCsv(view.grid, mode))}>Last ned CSV</button>
            )}
          </div>
        </div>
        <RoundsGridView grid={view.grid} snapshots={view.snapshots} mode={mode} />
      </div>
    </>
  );
}

function CupSection({ view }: { view: CupView }) {
  return (
    <div className="card">
      <div className="headRow">
        <div>
          <h2 className="printTitle">{view.title}</h2>
          {view.champion && <p><strong>Vinner: {view.champion}</strong></p>}
        </div>
        <span className="spacer" />
        <button className="link no-print" onClick={() => window.print()}>Skriv ut</button>
      </div>
      {view.rounds.length === 0 ? <p className="muted">Cupen er ikke trukket ennå.</p> : (
        <div className="bracket">
          {view.rounds.map((games, i) => (
            <div key={i} className="bracketRound">
              <h4>{view.roundTitles[i]}</h4>
              {games.map((g) => (
                <div key={g.slot} className={g.a?.isMe || g.b?.isMe ? "cupGame me" : "cupGame"}>
                  <CupSideLine game={g} side={g.a} />
                  {g.isBye ? <div className="muted small">Walkover (bye)</div> : <CupSideLine game={g} side={g.b} />}
                  <div className="muted small">{cupFooter(g)}</div>
                </div>
              ))}
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

/** Én spiller i en cupkamp: seed, navn og hake for vinneren (`CupGameCard.line`). */
function CupSideLine({ game, side }: { game: CupGame; side: CupSide | null }) {
  const won = side !== null && side.participantID === game.winner;
  return (
    <div className={won ? "cupSide won" : "cupSide"}>
      {side?.seed != null && <span className="seed">{side.seed}</span>}
      <span className={side ? undefined : "muted"}>{side?.name ?? "–"}</span>
      {won && <span className="ok" aria-label="vant">✓</span>}
    </div>
  );
}
