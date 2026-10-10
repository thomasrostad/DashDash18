import { useEffect, useState } from "react";
import {
  holeNumber,
  makeRoundFromSnapshot,
  numberOfHoles,
  scoreNameLabel,
  snapshotScorecard,
  snapshotTotal,
  type RoundsGrid,
  type RoundSnapshot,
} from "../../../golfgutu-core/src/index.ts";
import { cellText, gridTotal, gridValue, isBest, type GridMode } from "./csv.ts";

/**
 * «Alle runder» som `RoundsLeaderboardView` i appen: plass og navn til venstre, én kolonne per runde, sum til
 * høyre. Beste i runden er gul, din rad er markert, en runde som pågår har en prikk, og runder som ikke teller
 * (beste N) er dempet. En rute åpner scorekortet.
 */
export function RoundsGridView({ grid, snapshots, mode }: { grid: RoundsGrid; snapshots: RoundSnapshot[]; mode: GridMode }) {
  const [target, setTarget] = useState<{ roundID: string; playerID: string } | null>(null);
  if (grid.columns.length === 0) return <p className="muted">Rundene dukker opp her når den første er spilt.</p>;
  const dimmed = grid.rows.some((r) => r.counted !== null);
  const snapshot = target ? snapshots.find((s) => s.round.id === target.roundID) ?? null : null;

  return (
    <>
      <div className="gridScroll">
        <table className="roundsGrid">
          <thead>
            <tr>
              <th className="sticky">Spiller</th>
              {grid.columns.map((c) => (
                <th key={c.roundID} className="num" title={c.title}>
                  {c.label}{c.isOngoing && <span className="ongoing" aria-label="pågår" />}
                  <div className="colDate">{c.date ?? ""}</div>
                </th>
              ))}
              <th className="num sum">Sum</th>
            </tr>
          </thead>
          <tbody>
            {grid.rows.map((row) => (
              <tr key={row.playerID} className={row.isMe ? "me" : undefined}>
                <td className="sticky"><span className="muted place">{row.place}</span> {row.name}</td>
                {grid.columns.map((c, n) => {
                  const v = gridValue(row, n, mode);
                  if (v === null || v === undefined) return <td key={c.roundID} className="num muted" aria-label={`${row.name}, ${c.title}: ikke med`}>–</td>;
                  const best = isBest(grid, row, n, mode);
                  const counts = row.counted?.[n] ?? true;
                  return (
                    <td key={c.roundID} className="num">
                      <button
                        className={`cell${best ? " best" : ""}${counts ? "" : " dim"}`}
                        onClick={() => setTarget({ roundID: c.roundID, playerID: row.playerID })}
                        title={`${c.title}: scorekortet`}
                        aria-label={`${row.name}, ${c.title}: ${cellText(v)}${best ? ", best i runden" : ""}${counts ? "" : ", teller ikke"}`}
                      >
                        {cellText(v)}
                      </button>
                    </td>
                  );
                })}
                <td className="num sum"><strong>{gridTotal(row, mode)}</strong></td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <p className="muted small">
        Trykk på en rute for scorekortet: slag og poeng hull for hull.
        {dimmed && " Dempede runder teller ikke i tabellen."}
        {mode !== "points" && " Slag gjelder hullene som er ført."}
      </p>
      {snapshot && target && <ScorecardDialog snapshot={snapshot} memberID={target.playerID} onClose={() => setTarget(null)} />}
    </>
  );
}

/** Scorekortet til én spiller i én runde (`ScorekortSheet`): Ut/Inn, par, slag og poeng per hull, sum. */
function ScorecardDialog({ snapshot, memberID, onClose }: { snapshot: RoundSnapshot; memberID: string; onClose: () => void }) {
  const [inward, setInward] = useState(false);
  const round = makeRoundFromSnapshot(snapshot);
  const holeCount = numberOfHoles(round);
  const hasInward = holeCount > 9;
  const card = snapshotScorecard(snapshot, memberID, inward);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => { if (e.key === "Escape") onClose(); };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [onClose]);

  return (
    <div className="overlay no-print" onClick={onClose}>
      <div className="card dialog" role="dialog" aria-modal="true" aria-label={`Scorekort for ${card.name}`} onClick={(e) => e.stopPropagation()}>
        <div className="headRow">
          <h3>{card.name}</h3>
          <span className="spacer" />
          <button className="link" onClick={onClose}>Ferdig</button>
        </div>
        {hasInward && (
          <div className="segmented" role="group" aria-label="Side">
            <button className={!inward ? "seg active" : "seg"} onClick={() => setInward(false)}>
              Ut · {holeNumber(round, 0)}–{holeNumber(round, 8)}
            </button>
            <button className={inward ? "seg active" : "seg"} onClick={() => setInward(true)}>
              Inn · {holeNumber(round, 9)}–{holeNumber(round, Math.min(17, holeCount - 1))}
            </button>
          </div>
        )}
        <p className="muted">{(snapshot.course?.name ?? "Runden") + " · " + (card.inward ? "Inn" : "Ut")}</p>
        <table className="scorecard">
          <thead><tr><th>Hull</th><th className="num">Par</th><th className="num">Slag</th><th className="num">Poeng</th></tr></thead>
          <tbody>
            {card.lines.map((l) => (
              <tr key={l.index}>
                <td>{l.number}</td>
                <td className="num muted">{l.par}</td>
                <td className="num">{l.strokes ?? "–"}</td>
                <td className="num">
                  {l.points === null ? <span className="muted">–</span> : (
                    <span className={`badge ${l.scoreName ?? ""}`} title={l.scoreName ? scoreNameLabel(l.scoreName) : undefined}>{l.points}</span>
                  )}
                </td>
              </tr>
            ))}
            <tr className="sumRow">
              <td>Sum</td>
              <td className="num">{card.sumPar}</td>
              <td className="num">{card.sumStrokes > 0 ? card.sumStrokes : "–"}</td>
              <td className="num"><strong>{card.sumPoints}</strong></td>
            </tr>
          </tbody>
        </table>
        <p className="totalLine"><span>Totalt i runden</span><strong>{snapshotTotal(snapshot, memberID)} poeng</strong></p>
      </div>
    </div>
  );
}
