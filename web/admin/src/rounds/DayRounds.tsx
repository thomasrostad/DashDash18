import { useCallback, useEffect, useMemo, useState } from "react";
import type { Competition, EventRow } from "../data.ts";
import { longDate, todayISO } from "../text.ts";
import { capitalized, dayThe } from "../../../golfgutu-core/src/index.ts";
import {
  deleteRound, deleteSummary, loadDay, loadGame, loadSetup, lockAll, lockRound, competitionFor,
  type DayData, type ListRound,
} from "./api.ts";
import { courseItemReady, previousTeeID, suggestedTee } from "./courses.ts";
import { closeCheck, closePrompt, closeSummary, type ClosePrompt } from "./game.ts";
import {
  allowsNewRound, applySuggestion, autoArrange, bayNumbers, defaultBayCount, deleteButtonTitle, deleteMessage, deleteNoun,
  draftParticipants, initialParticipants, newDraft, nextRoundNo, previousRound, redrawMatches, reshuffleBays, roundStatusText,
  roundSubtitle, roundTitle, savedDraft, type DeleteSummary, type RoundDraft,
} from "./logic.ts";
import { RoundSetup } from "./RoundSetup.tsx";
import { RoundView } from "./RoundView.tsx";
import { StartListEditor } from "./StartListEditor.tsx";
import "./rounds.css";

type View =
  | { kind: "list" }
  | { kind: "setup"; draft: RoundDraft }
  | { kind: "round"; round: ListRound; cut: boolean }
  | { kind: "startlist" };

/**
 * Rundene på én spilledag, som appens arrangørside (RundeAdminModel, RoundAdminActions, AvsluttKveldenSection):
 * lista med status, ny runde og kladd, start, lås, slett, «Avslutt kvelden», hele runden med retting og
 * avkorting, og startlista.
 */
export function DayRounds({ clubID, event, days, comps, onBack }: {
  clubID: string; event: EventRow; days: EventRow[]; comps: Competition[]; onBack: () => void;
}) {
  const [data, setData] = useState<DayData | null>(null);
  const [view, setView] = useState<View>({ kind: "list" });
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [pendingDelete, setPendingDelete] = useState<{ round: ListRound; summary: DeleteSummary } | null>(null);
  const [closing, setClosing] = useState<{ prompt: ClosePrompt; ids: string[] } | null>(null);

  const load = useCallback(async () => {
    try { setData(await loadDay(clubID, event, comps)); } catch (e) { setError((e as Error).message); }
  }, [clubID, event, comps]);

  useEffect(() => { load(); }, [load]);

  const term = data?.dayTerm ?? "evening";
  const courseName = useCallback((id: string | null) => data?.courses.find((c) => c.course.id === id)?.course.name ?? null, [data]);
  const titleOf = useCallback((r: { roundNo: number; courseID: string | null }) => roundTitle(r.roundNo, courseName(r.courseID)), [courseName]);
  const rounds = useMemo(() => (data?.allRounds ?? []).filter((r) => r.eventID === event.id).sort((a, b) => a.roundNo - b.roundNo), [data, event.id]);
  const clubActive = data?.allRounds.find((r) => r.status === "active") ?? null;
  // Kveldens runder, med runden som går selv om den hører til en annen kveld.
  const toClose = clubActive && !rounds.some((r) => r.id === clubActive.id) ? [...rounds, clubActive] : rounds;

  async function run(action: () => Promise<string | void>) {
    setBusy(true); setError(null); setNotice(null);
    try {
      const text = await action();
      if (text) setNotice(text);
    } catch (e) { setError((e as Error).message); }
    finally { setBusy(false); }
  }

  /** Ny runde: de påmeldte, forslaget fra forrige runde i turneringen, og gruppene fordelt automatisk. */
  function startNew() {
    if (!data) return;
    const ready = data.courses.filter(courseItemReady);
    const { ids, source } = initialParticipants(data.roster, data.signups);
    let d = newDraft({
      roundID: crypto.randomUUID(), eventID: event.id, roundNo: nextRoundNo(rounds), teeTime: event.start_time,
      participants: ids, source, rules: data.rules,
    });
    d = { ...d, courseID: ready[0]?.course.id ?? null };
    const sameTournament = days.filter((e) => (event.season_id ? e.season_id === event.season_id : e.competition_id === event.competition_id && !e.season_id));
    const tournamentRounds = data.allRounds.filter((r) => r.eventID !== null && sameTournament.some((e) => e.id === r.eventID));
    d = applySuggestion(d, previousRound(tournamentRounds, sameTournament, event.event_date),
      ready.map((c) => ({ id: c.course.id, isReady: true, holeCount: c.holes.length, teeIDs: c.tees.map((t) => t.id) })), data.rules);
    if (d.teeID === null) {
      const item = data.courses.find((c) => c.course.id === d.courseID);
      if (item) d = { ...d, teeID: suggestedTee(item.tees, previousTeeID(data.allRounds, item.course.id))?.id ?? null };
    }
    setView({ kind: "setup", draft: autoArrange(d, data.rules, data.roster) });
  }

  /** Kladden slik den er lagret. Uten oppsett: forslag som for en ny runde. */
  function edit(r: ListRound) {
    if (!data) return;
    run(async () => {
      const { players, matches } = await loadSetup(r.id);
      const { ids, source } = draftParticipants(data.roster, players, data.signups);
      let d = savedDraft(r, players, matches, ids, source);
      if (players.length === 0) {
        d = redrawMatches(d, data.roster);
        d = reshuffleBays(d, defaultBayCount(ids.length, data.rules.formats.maxPerBay));
      }
      setView({ kind: "setup", draft: d });
    });
  }

  function askDelete(r: ListRound) {
    run(async () => { setPendingDelete({ round: r, summary: await deleteSummary(r) }); });
  }

  function lock(r: ListRound) {
    if (!confirm(`Låse ${titleOf(r)}? Runden er ferdig og teller i turneringen. En låst runde kan ikke bli kladd igjen eller slettes.`)) return;
    run(async () => { await lockRound(r.id); await load(); return `${titleOf(r)} er låst og teller i turneringen.`; });
  }

  /** «Avslutt kvelden»: spør om avkorting når noen mangler hull, og låser alle pågående runder. */
  function askClose() {
    if (!data) return;
    run(async () => {
      const active = toClose.filter((r) => r.status === "active");
      const checks = [];
      for (const r of active) checks.push(closeCheck(await loadGame(r.id, data.rules), titleOf(r)));
      const prompt = closePrompt(checks, term);
      if (prompt) setClosing({ prompt, ids: active.map((r) => r.id) });
    });
  }

  function close(ids: string[]) {
    setClosing(null);
    run(async () => {
      const locked = await lockAll(ids);
      const names = (f: (r: ListRound) => boolean) => toClose.filter(f).map(titleOf);
      const text = closeSummary(
        names((r) => locked.has(r.id)), names((r) => r.status === "draft"), names((r) => ids.includes(r.id) && !locked.has(r.id)), term);
      await load();
      return text;
    });
  }

  const header = (
    <>
      <button className="link" onClick={view.kind === "list" ? onBack : () => { setView({ kind: "list" }); load(); }}>
        ← {view.kind === "list" ? "Terminlista" : `Rundene ${longDate(event.event_date)}`}
      </button>
      <h2>{capitalized(longDate(event.event_date))}</h2>
      <p className="muted">{competitionFor(event, comps)?.name ?? "Klubbens egen"}{event.venue ? ` · ${event.venue}` : ""}</p>
    </>
  );

  if (!data) return <section>{header}{error ? <p className="error">{error}</p> : <p className="muted">Henter rundene …</p>}</section>;

  if (view.kind === "setup") {
    return (
      <section>
        {header}
        <RoundSetup clubID={clubID} data={data} initial={view.draft} titleOf={titleOf}
          onCancel={() => setView({ kind: "list" })}
          onDone={async (text) => { setView({ kind: "list" }); setNotice(text); await load(); }} />
      </section>
    );
  }

  if (view.kind === "round") {
    return (
      <section>
        {header}
        <RoundView round={view.round} title={titleOf(view.round)} rules={data.rules} myMemberID={data.myMemberID} openCut={view.cut}
          onLeft={async (text) => { setView({ kind: "list" }); setNotice(text); await load(); }} />
      </section>
    );
  }

  if (view.kind === "startlist") {
    const names = new Map(data.roster.map((m) => [m.id, m.name]));
    const open = rounds.filter((r) => r.status !== "locked");
    return (
      <section>
        {header}
        <StartListEditor eventID={event.id} rounds={open.map((r) => ({ round: r, title: titleOf(r), players: data.players.get(r.id) ?? [] }))}
          names={names} onSaved={async () => { setView({ kind: "list" }); setNotice("Startlista er lagret."); await load(); }} />
      </section>
    );
  }

  const today = todayISO();
  const hasActive = toClose.some((r) => r.status === "active");
  return (
    <section>
      {header}
      {error && <p className="error">{error}</p>}
      {notice && <p className="ok">{notice}</p>}
      <div className="inline">
        {allowsNewRound(event.event_date, today) && <button className="primary" disabled={busy} onClick={startNew}>Sett opp runden</button>}
        {hasActive && <button className="primary" disabled={busy} onClick={askClose}>Avslutt {dayThe(term)}</button>}
        {rounds.some((r) => r.status !== "locked") && <button className="link" disabled={busy} onClick={() => setView({ kind: "startlist" })}>Startliste</button>}
      </div>

      {closing && (
        <div className="card confirm">
          <h3>{closing.prompt.title}</h3>
          {closing.prompt.lines.map((l) => <p key={l}>{l}</p>)}
          <div className="inline">
            <button className="danger" disabled={busy} onClick={() => close(closing.ids)}>Avslutt {dayThe(term)}</button>
            {closing.prompt.suggestCut && (() => {
              const r = toClose.find((x) => x.id === closing.prompt.suggestCut);
              return r ? <button className="link" onClick={() => { setClosing(null); setView({ kind: "round", round: r, cut: true }); }}>Avkort runden først</button> : null;
            })()}
            <button className="link" onClick={() => setClosing(null)}>Avbryt</button>
          </div>
        </div>
      )}

      {pendingDelete && (
        <div className="card confirm">
          <h3>Slett {deleteNoun(pendingDelete.summary)} · {titleOf(pendingDelete.round)}</h3>
          <p className="pre">{deleteMessage(pendingDelete.summary)}</p>
          <div className="inline">
            <button className="danger" disabled={busy} onClick={() => {
              const r = pendingDelete.round;
              setPendingDelete(null);
              run(async () => { const text = await deleteRound(r.id); await load(); return text; });
            }}>{deleteButtonTitle(pendingDelete.summary)}</button>
            <button className="link" onClick={() => setPendingDelete(null)}>Avbryt</button>
          </div>
        </div>
      )}

      {rounds.length === 0 ? <p className="muted">Ingen runder på denne datoen ennå.</p> : (
        <table>
          <thead><tr><th>Runde</th><th>Status</th><th></th></tr></thead>
          <tbody>
            {rounds.map((r) => {
              const players = data.players.get(r.id) ?? [];
              const bays = bayNumbers(players.filter((p) => p.bayNo !== null).map((p) => ({ memberID: p.memberID, bay: p.bayNo!, isMarker: p.isMarker }))).length;
              return (
                <tr key={r.id}>
                  <td><strong>{titleOf(r)}</strong><div className="muted small">{roundSubtitle(r, players.length, bays)}</div></td>
                  <td><span className={`pill status-${r.status}`}>{roundStatusText(r.status)}</span></td>
                  <td className="actions">
                    {r.status === "draft" && <button className="link" disabled={busy} onClick={() => edit(r)}>Fortsett</button>}
                    {r.status !== "draft" && <button className="link" disabled={busy} onClick={() => setView({ kind: "round", round: r, cut: false })}>Åpne</button>}
                    {r.status === "active" && <button className="link" disabled={busy} onClick={() => lock(r)}>Lås</button>}
                    {r.status !== "locked" && <button className="link" disabled={busy} onClick={() => askDelete(r)}>Slett</button>}
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      )}
      {clubActive && clubActive.eventID !== event.id && (
        <p className="muted">{titleOf(clubActive)} går på en annen dato. Den må låses før en ny runde kan starte.</p>
      )}
    </section>
  );
}
