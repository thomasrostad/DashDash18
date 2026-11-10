import { useCallback, useEffect, useState } from "react";
import { adjustmentPointsText, POINTS_STEP, REASON_LIMIT, type Adjustment } from "../adjustments.ts";
import { addAdjustment, adjustments, deleteAdjustment } from "../adjustmentsApi.ts";
import { errorText } from "../supabase.ts";
import type { GroupTerm } from "../rounds/logic.ts";
import {
  CHALLENGE_DEFAULT, CHALLENGE_MAX_ROUNDS, challengeGroups, challengeProblem, lastChallengeRound, type ChallengeSetup,
} from "./challenge.ts";

/**
 * «Challenge etter runden» når alle er inne: navn, poeng og én vinner per bås (eller hele runden).
 * Hver vinner blir et tilleggspoeng for kvelden (sql/072), så tabellen og spillerne ser det med en gang.
 */
export function Challenge({ clubID, seasonID, eventID, players, name, term }: {
  clubID: string; seasonID: string; eventID: string;
  players: { memberID: string; group: number }[]; name: (memberID: string) => string; term: GroupTerm;
}) {
  const [setup, setSetup] = useState<ChallengeSetup>(CHALLENGE_DEFAULT);
  const [rows, setRows] = useState<Adjustment[] | null>(null);
  const [picked, setPicked] = useState<Record<number, string>>({});
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async (first = false) => {
    try {
      const all = (await adjustments(seasonID)).filter((a) => a.event_id === eventID);
      setRows(all);
      if (first) {
        const last = lastChallengeRound(CHALLENGE_DEFAULT, players, term, all.map((a) => a.reason));
        if (last > 0) setSetup((s) => ({ ...s, round: last }));
      }
    } catch (e) { setError(errorText(e)); }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [seasonID, eventID]);

  useEffect(() => { load(true); }, [load]);

  const groups = challengeGroups(setup, players, term);
  const problem = challengeProblem(setup);
  const winnerOf = (reason: string) => rows?.find((a) => a.reason === reason) ?? null;
  const allDone = rows !== null && groups.every((g) => winnerOf(g.reason));

  async function run(action: () => Promise<void>) {
    setBusy(true); setError(null);
    try { await action(); await load(); } catch (e) { setError(errorText(e)); } finally { setBusy(false); }
  }

  return (
    <div className="card kv-challenge">
      <div className="ph"><h2>Challenge etter runden</h2>{setup.round > 1 && <span className="muted">Runde {setup.round}</span>}</div>
      <p className="muted small">For eksempel CP knockout: alle i {term.definite} slår, lengst fra pinnen ryker. Vinneren får tilleggspoeng i tabellen med en gang.</p>
      {error && <p className="error">{error}</p>}
      <div className="inline-fields">
        <label>Navn
          <input type="text" maxLength={REASON_LIMIT} value={setup.name} onChange={(e) => setSetup({ ...setup, name: e.target.value })} />
        </label>
        <label>Poeng til vinneren
          <input type="number" min={POINTS_STEP} max={100} step={POINTS_STEP} value={setup.points} onChange={(e) => setSetup({ ...setup, points: Number(e.target.value) })} />
        </label>
        <label>Vinner
          <select value={setup.scope} onChange={(e) => setSetup({ ...setup, scope: e.target.value as ChallengeSetup["scope"] })}>
            <option value="group">Én per {term.singular}</option>
            <option value="all">Én for hele runden</option>
          </select>
        </label>
      </div>
      {problem && <p className="muted small">{problem}</p>}
      <ul className="plain">
        {groups.map((g) => {
          const won = winnerOf(g.reason);
          return (
            <li key={g.no} className="row-inline">
              <strong>{g.title}</strong>{" "}
              {won ? <>
                <span>{name(won.member_id)} {adjustmentPointsText(won.points)}</span>{" "}
                <button className="link" disabled={busy} onClick={() => run(() => deleteAdjustment(won.id))}>Angre</button>
              </> : <>
                <select value={picked[g.no] ?? ""} onChange={(e) => setPicked({ ...picked, [g.no]: e.target.value })}>
                  <option value="">Hvem vant?</option>
                  {g.members.map((m) => <option key={m} value={m}>{name(m)}</option>)}
                </select>{" "}
                <button className="secondary" disabled={busy || problem !== null || !picked[g.no]}
                  onClick={() => run(() => addAdjustment(clubID, seasonID, picked[g.no], eventID, setup.points, g.reason))}>Registrer</button>
              </>}
            </li>
          );
        })}
      </ul>
      {allDone && setup.round < CHALLENGE_MAX_ROUNDS && (
        <button className="link" disabled={busy} onClick={() => { setPicked({}); setSetup({ ...setup, round: setup.round + 1 }); }}>Én runde til</button>
      )}
    </div>
  );
}
