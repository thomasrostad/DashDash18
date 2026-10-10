import { useCallback, useEffect, useState } from "react";
import { capitalized, formById, norwegianCompare, scoreNameLabel, TRUNCATION_RULES, truncationRuleName, type Ruleset, type TruncationRule } from "../../../golfgutu-core/src/index.ts";
import { longDate } from "../text.ts";
import { deleteRound, deleteSummary, loadGame, lockRound, saveCut, saveHole, type ListRound } from "./api.ts";
import {
  correctionButtonTitle, correctionChanged, correctionCurrentText, correctionDoneText, correctionNotice, correctionOutcome,
  correctionParams, cutHint, cutRuleHelp, cutLineText, cutOptionTitle, cutPreview, cutSummary, defaultCutChoice, newCorrection, roundTable,
  signed, stepCorrection, type CutChoice, type RoundGame, type ScoreCorrection,
} from "./game.ts";
import { deleteButtonTitle, deleteMessage, deleteNoun, roundStatusText, type DeleteSummary } from "./logic.ts";

/**
 * Rundens side for arrangøren (RoundTableView, AvkortView): spillere × hull med brutto, sum og poeng, og
 * handlingene på runden (rett en score, avkort, lås, slett). Trykk en rute for å rette den.
 */
export function RoundView({ round, title, rules, myMemberID, openCut, onLeft }: {
  round: ListRound; title: string; rules: Ruleset; myMemberID: string | null; openCut: boolean; onLeft: (text: string) => void;
}) {
  const [game, setGame] = useState<RoundGame | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [correction, setCorrection] = useState<ScoreCorrection | null>(null);
  const [cut, setCut] = useState<CutChoice | null>(null);
  const [pendingDelete, setPendingDelete] = useState<DeleteSummary | null>(null);

  const load = useCallback(async () => {
    try {
      const g = await loadGame(round.id, rules);
      setGame(g);
      return g;
    } catch (e) { setError((e as Error).message); return null; }
  }, [round.id, rules]);

  useEffect(() => {
    load().then((g) => { if (g && openCut && g.status === "active") setCut(defaultCutChoice(g)); });
  }, [load, openCut]);

  async function run(action: () => Promise<void>) {
    setBusy(true); setError(null); setNotice(null);
    try { await action(); } catch (e) { setError((e as Error).message); } finally { setBusy(false); }
  }

  if (!game) return error ? <p className="error">{error}</p> : <p className="muted">Henter runden …</p>;

  const table = roundTable(game);
  const sortedPlayers = game.snapshot.players.map((p) => p.memberID).sort((a, b) => norwegianCompare(game.name(a), game.name(b)));
  const header = [
    game.snapshot.eventDate ? capitalized(longDate(game.snapshot.eventDate)) : null,
    game.snapshot.course?.name ?? "Ingen bane",
    `${game.holeCount} hull`,
    formById(game.snapshot.round.format).name,
    cutSummary(game)?.toLowerCase() ?? null,
    roundStatusText(game.status).toLowerCase(),
  ].filter(Boolean).join(" · ");

  return (
    <div>
      <h3>{title}</h3>
      <p className="muted">{header}</p>
      {error && <p className="error">{error}</p>}
      {notice && <p className="ok">{notice}</p>}
      <div className="inline">
        <button className="link" disabled={busy} onClick={() => sortedPlayers[0] && setCorrection(newCorrection(game, sortedPlayers[0], 0))}>Rett en score</button>
        {game.status === "active" && <>
          <button className="link" disabled={busy} onClick={() => setCut(defaultCutChoice(game))}>Avkort runden …</button>
          <button className="link" disabled={busy} onClick={() => {
            if (!confirm(`Låse ${title}? Runden er ferdig og teller i turneringen. En låst runde kan ikke bli kladd igjen eller slettes.`)) return;
            run(async () => { await lockRound(round.id); onLeft(`${title} er låst og teller i turneringen.`); });
          }}>Lås runden …</button>
          <button className="link" disabled={busy} onClick={() => run(async () => setPendingDelete(await deleteSummary(round)))}>Slett runden …</button>
        </>}
        <button className="link" disabled={busy} onClick={() => run(async () => { await load(); })}>Oppdater</button>
      </div>

      {pendingDelete && (
        <div className="card confirm">
          <h3>Slett {deleteNoun(pendingDelete)} · {title}</h3>
          <p className="pre">{deleteMessage(pendingDelete)}</p>
          <div className="inline">
            <button className="danger" disabled={busy} onClick={() => run(async () => { const text = await deleteRound(round.id); onLeft(text); })}>{deleteButtonTitle(pendingDelete)}</button>
            <button className="link" onClick={() => setPendingDelete(null)}>Avbryt</button>
          </div>
        </div>
      )}

      {correction && (() => {
        const outcome = correctionOutcome(game, correction);
        const notice = correctionNotice(game.status);
        return (
          <div className="card">
            <h3>Rett en score</h3>
            <div className="grid2 tight">
              <label>Spiller
                <select value={correction.memberID} onChange={(e) => setCorrection(newCorrection(game, e.target.value, correction.holeIndex))}>
                  {sortedPlayers.map((id) => <option key={id} value={id}>{game.name(id)}</option>)}
                </select>
              </label>
              <label>Hull
                <select value={correction.holeIndex} onChange={(e) => setCorrection(newCorrection(game, correction.memberID, Number(e.target.value)))}>
                  {game.holes.map((h, i) => <option key={i} value={i}>Hull {game.holeNumber(i)} · par {h.par}</option>)}
                </select>
              </label>
            </div>
            <p className="muted small">{correctionCurrentText(correction)}</p>
            <div className="stepper">
              <button className="link big" aria-label="Ett slag mindre" onClick={() => setCorrection(stepCorrection(correction, -1))}>−</button>
              <span className="strokes">{correction.strokes}</span>
              <button className="link big" aria-label="Ett slag mer" onClick={() => setCorrection(stepCorrection(correction, 1))}>+</button>
              <span className={`pill score-${outcome.name}`}>{scoreNameLabel(outcome.name)}</span>
              <span className="muted">{outcome.points} p</span>
            </div>
            <p className="muted small">Dette er en retting. Tallet erstatter det som står, for alle med én gang, og det lagres hvem som rettet.</p>
            {notice && <p className="small">{notice}</p>}
            <div className="inline">
              <button className="primary" disabled={busy || !correctionChanged(correction)} onClick={() => run(async () => {
                const params = correctionParams(game, correction, new Date());
                if (!params) return;
                const done = correctionDoneText(game, correction);
                await saveHole(params);
                setCorrection(null);
                setNotice(done);
                await load();
              })}>{correctionButtonTitle(game, correction)}</button>
              <button className="link" onClick={() => setCorrection(null)}>Avbryt</button>
            </div>
            {!correctionChanged(correction) && <p className="muted small">Ingen endring.</p>}
          </div>
        );
      })()}

      {cut && (() => {
        const preview = cutPreview(game, cut);
        const current = cutSummary(game);
        const locked = game.status === "locked";
        const confirmText = (c: CutChoice) => [
          `${truncationRuleName(c.rule)}. ${cutRuleHelp(c.rule)}`,
          ...(preview.losers > 0 ? [preview.losers === 1 ? "1 spiller mister poeng." : `${preview.losers} spillere mister poeng.`] : []),
          "Poengene regnes om for hele feltet med én gang.",
        ].join("\n");
        return (
          <div className="card">
            <h3>Avkort runden</h3>
            <p className="muted small">Runden avkortes for alle samtidig. Poengene regnes om med én gang, for hele feltet.</p>
            {current && <p className="small">{current}. Du kan endre valget eller fjerne avkortingen.</p>}
            {locked && <p className="error small">Runden er låst og kan ikke avkortes. Enkelthull rettes med «Rett en score».</p>}
            <fieldset>
              <legend>Hva skjer med hullene som ikke ble spilt</legend>
              {TRUNCATION_RULES.map((r: TruncationRule) => (
                <label key={r} className="check"><input type="radio" name="cutrule" checked={cut.rule === r} onChange={() => setCut({ ...cut, rule: r })} />{truncationRuleName(r)}</label>
              ))}
              <p className="muted small">{cutRuleHelp(cut.rule)}</p>
            </fieldset>
            <label>Runden stoppet etter
              <select value={cut.after} onChange={(e) => setCut({ ...cut, after: Number(e.target.value) })}>
                {Array.from({ length: game.holeCount }, (_, i) => i + 1).map((n) => <option key={n} value={n}>{cutOptionTitle(game, n)}</option>)}
              </select>
            </label>
            <p className="muted small">{cutHint(game, cut.rule)}</p>
            <h4>Dette endrer seg</h4>
            {preview.lines.length === 0 ? <p className="muted">Ingen poengsummer endrer seg av dette valget.</p> : (
              <ul className="plain">
                {preview.lines.map((l) => <li key={l.memberID} aria-label={cutLineText(l)}>{l.name} {l.before} → {l.after} <span className={l.diff < 0 ? "error" : "ok"}>{signed(l.diff)}</span></li>)}
              </ul>
            )}
            <div className="inline">
              <button className="danger" disabled={locked || busy} onClick={() => {
                if (!confirm(`Avkorte ${title} etter hull ${game.holeNumber(cut.after - 1)}?\n\n${confirmText(cut)}`)) return;
                run(async () => { await saveCut(game, cut, myMemberID); setCut(null); setNotice("Runden er avkortet. Poengene er regnet om."); await load(); });
              }}>Avkort etter {cutOptionTitle(game, cut.after).toLowerCase()} · {truncationRuleName(cut.rule).toLowerCase()}</button>
              {game.cutRule !== null && (
                <button className="link" disabled={locked || busy} onClick={() => {
                  if (!confirm(`Fjerne avkortingen av ${title}?\n\nHele runden teller igjen, og poengene regnes om.`)) return;
                  run(async () => { await saveCut(game, null, myMemberID); setCut(null); setNotice("Avkortingen er fjernet. Hele runden teller igjen."); await load(); });
                }}>Fjern avkorting</button>
              )}
              <button className="link" onClick={() => setCut(null)}>Avbryt</button>
            </div>
          </div>
        );
      })()}

      {table.rows.length === 0 ? <p className="muted">Runden har ingen deltakere.</p> : (
        <div className="scroll">
          <table className="scorecard">
            <thead>
              <tr><th className="name">Hull</th>{table.columns.map((c) => <th key={c.index} className={c.outside ? "outside" : ""}>{c.number}</th>)}<th>Slag</th><th>Poeng</th></tr>
              <tr className="par"><td className="name">Par</td>{table.columns.map((c) => <td key={c.index} className={c.outside ? "outside" : ""}>{c.par}</td>)}<td>{table.parTotal}</td><td></td></tr>
            </thead>
            <tbody>
              {table.rows.map((r) => (
                <tr key={r.memberID}>
                  <td className="name">{r.name}</td>
                  {r.cells.map((c) => (
                    <td key={c.index} className={`cell ${c.scoreName ? `score-${c.scoreName}` : ""} ${c.outside ? "outside" : ""}`}>
                      <button className="cellbtn" title={`${r.name}, hull ${game.holeNumber(c.index)}: ${c.strokes !== null ? `${c.strokes} slag` : "ikke ført"}. Trykk for å rette.`}
                        onClick={() => setCorrection(newCorrection(game, r.memberID, c.index))}>{c.strokes ?? "·"}</button>
                    </td>
                  ))}
                  <td>{r.strokes ?? "–"}</td>
                  <td><strong>{r.points}</strong></td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
      <p className="muted small">
        Brutto slag. Fargen er netto mot par, som på scorekortet.{table.hasOutside ? " Grå hull er utenfor avkortingen og teller ikke." : ""} Trykk en rute for å rette den.
      </p>
    </div>
  );
}
