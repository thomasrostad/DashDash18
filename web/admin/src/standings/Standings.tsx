import { useEffect, useMemo, useState } from "react";
import type { Competition, Membership } from "../data.ts";
import { errorText, supabase } from "../supabase.ts";
import { kindText, statusText } from "../text.ts";
import { fileName, gridCsv, tableCsv, type GridMode } from "./csv.ts";
import type { CupGame, CupSide } from "../../../golfgutu-core/src/index.ts";
import { competitionData, cupFooter, cupView, leagueView, seasonView, type CupView, type StandingsView, type TableView } from "./model.ts";
import { loadCompetition, loadSeason } from "./queries.ts";
import { RoundsGridView } from "./RoundsGridView.tsx";
import "./standings.css";

const shown = ["season", "league", "fun", "cup"];

/** Turneringen som vises først: hovedturneringen, ellers den første som er i gang, ellers den første. */
function initial(comps: Competition[]): string | null {
  const list = comps.filter((c) => shown.includes(c.kind));
  return (list.find((c) => c.is_main) ?? list.find((c) => c.status === "active") ?? list[0])?.id ?? null;
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
  const competition = list.find((c) => c.id === id) ?? null;

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
  }, [competition?.id, competition?.kind, membership.id]); // eslint-disable-line react-hooks/exhaustive-deps

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
      {view?.kind === "table" && <TableSection view={view} />}
      {view?.kind === "cup" && <CupSection view={view} />}
    </section>
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
