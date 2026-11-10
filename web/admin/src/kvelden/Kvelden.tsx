import { useCallback, useEffect, useLayoutEffect, useRef, useState } from "react";
import { capitalized } from "../../../golfgutu-core/src/index.ts";
import { updateMember, type Competition, type EventRow, type Member } from "../data.ts";
import { errorText } from "../supabase.ts";
import { lockRound } from "../rounds/api.ts";
import { termNumbered } from "../rounds/logic.ts";
import { longDate } from "../text.ts";
import { loadLive, loadNextDay, type LiveRound, type NextDay } from "./api.ts";
import { clockText, feedOf, gapsOf, groupsOf, phaseOf, type KvFeedItem, type KvGroup } from "./model.ts";
import { Challenge } from "./Challenge.tsx";
import "./kvelden.css";

const POLL_MS = 20000;
const still = () => matchMedia("(prefers-reduced-motion: reduce)").matches;
const isoDay = (d: Date) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;

/** FLIP: elementene med samme nøkkel glir fra der de var til der de er nå. */
function useFlip(deps: unknown[]) {
  const nodes = useRef(new Map<string, HTMLElement>());
  const before = useRef(new Map<string, DOMRect>());
  const ref = (key: string) => (el: HTMLElement | null) => {
    if (el) { const old = nodes.current.get(key); if (old && old !== el) before.current.set(key, old.getBoundingClientRect()); nodes.current.set(key, el); }
  };
  const snapshot = () => { before.current = new Map([...nodes.current].map(([k, el]) => [k, el.getBoundingClientRect()])); };
  useLayoutEffect(() => {
    if (still()) { before.current.clear(); return; }
    for (const [key, el] of nodes.current) {
      const a = before.current.get(key);
      if (!a || !el.isConnected) continue;
      const b = el.getBoundingClientRect();
      const dx = a.left - b.left, dy = a.top - b.top;
      if (!dx && !dy) continue;
      el.style.transition = "none";
      el.style.transform = `translate(${dx}px, ${dy}px)`;
      requestAnimationFrame(() => requestAnimationFrame(() => { el.style.transition = "transform .9s cubic-bezier(.25,.8,.25,1)"; el.style.transform = ""; }));
    }
    before.current.clear();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, deps);
  return { ref, snapshot };
}

/**
 * Kvelden: startsiden for arrangøren. Under runden: banen med flightene der de er, kveldens tabell, det som
 * trenger deg og de siste hendelsene. Etter: vinneren og «Lås runden». Før: neste spilledag og hva som mangler.
 * Hentes på nytt hvert 20. sekund mens siden er synlig.
 */
export function Kvelden({ clubID, days, comps, roster, canMembers, canRounds, onOpen }: {
  clubID: string; days: EventRow[]; comps: Competition[]; roster: Member[]; canMembers: boolean; canRounds: boolean;
  onOpen: (tab: "terminliste" | "tropp") => void;
}) {
  const [live, setLive] = useState<LiveRound | null | undefined>(undefined);
  const [next, setNext] = useState<NextDay | null | undefined>(undefined);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [pending, setPending] = useState(() => roster.filter((m) => m.status === "pending"));
  useEffect(() => setPending(roster.filter((m) => m.status === "pending")), [roster]);
  const flip = useFlip([live]);

  const load = useCallback(async (quiet = false) => {
    if (!quiet) setError(null);
    try {
      const l = await loadLive(clubID, days, comps);
      flip.snapshot();
      setLive(l);
      if (!l) setNext(await loadNextDay(clubID, days, comps, isoDay(new Date())));
    } catch (e) { setError(errorText(e)); setLive((x) => (x === undefined ? null : x)); setNext((x) => (x === undefined ? null : x)); }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [clubID, days, comps]);

  useEffect(() => { load(); }, [load]);
  useEffect(() => {
    const id = setInterval(() => { if (document.visibilityState === "visible") load(true); }, POLL_MS);
    return () => clearInterval(id);
  }, [load]);

  async function approve(m: Member) {
    setBusy(m.id); setError(null);
    try { await updateMember(clubID, m.id, { status: "active" }); setPending((p) => p.filter((x) => x.id !== m.id)); setNotice(`${m.display_name} er med i troppen.`); }
    catch (e) { setError(errorText(e)); } finally { setBusy(null); }
  }
  async function lock(l: LiveRound) {
    setBusy("lock"); setError(null);
    try {
      const ok = await lockRound(l.round.id);
      setNotice(ok ? "Runden er låst. Tabellen i turneringen er oppdatert." : "Runden ble ikke låst. Hent siden på nytt og prøv igjen.");
      if (ok) await load();
    } catch (e) { setError(errorText(e)); } finally { setBusy(null); }
  }

  if (live === undefined) return <p className="muted">Henter kvelden …</p>;

  const messages = <>{error && <p className="error">{error}</p>}{notice && <p className="ok">{notice}</p>}</>;
  if (!live) return <div className="kv">{messages}<Before next={next} pending={canMembers ? pending : []} busy={busy} onApprove={approve} onOpen={onOpen} canRounds={canRounds} /></div>;

  const { game, table, players, scores, term } = live;
  const holeCount = game.holeCount;
  const groups = groupsOf(players, scores, holeCount);
  const gaps = gapsOf(players, scores, groups, holeCount);
  const phase = phaseOf(scores, groups);
  const feed = feedOf(players, scores, groups, 7);
  const groupName = (n: number) => (n === 0 ? "Uten " + term.singular : termNumbered(term, n));
  const title = live.round.name ?? `Runde ${live.round.roundNo}`;
  const subtitle = [live.competition?.name, game.snapshot.course?.name].filter(Boolean).join(", ");
  const inGroups = groups.filter((g) => g.done);
  const inCount = inGroups.reduce((s, g) => s + g.members.length, 0);
  const out = groups.filter((g) => !g.done);
  const leader = table.rows[0];
  const needs = gaps.length + (canMembers ? pending.length : 0);
  const started = live.round.startedAt ? clockText(live.round.startedAt) : null;

  const head = (
    <div className="kv-head">
      <div>
        <p className="kv-eyebrow">
          <span className={phase === "etter" ? "pill done" : "pill live"}>{phase === "etter" ? "Alle er inne" : "Pågår"}</span>
          {[started && `Startet ${started}`, `${holeCount} hull`, groups.length > 1 ? `${groups.length} ${term.plural}` : null].filter(Boolean).join(" · ")}
        </p>
        <h1><span className="loud">{title}</span> {subtitle && <span className="soft">{subtitle}</span>}</h1>
      </div>
      <div className="btns">
        <button className="secondary" onClick={() => onOpen("terminliste")}>Åpne runden</button>
        {phase === "etter" && canRounds && <button className="primary" disabled={busy === "lock"} onClick={() => lock(live)}>{busy === "lock" ? "Låser …" : "Lås runden"}</button>}
      </div>
    </div>
  );

  if (phase === "etter") {
    const drives = game.snapshot.sideClaims.filter((c) => c.kind === "drive").sort((a, b) => b.meters - a.meters)[0];
    const closest = game.snapshot.sideClaims.filter((c) => c.kind === "kp").sort((a, b) => a.meters - b.meters)[0];
    return (
      <div className="kv">
        {messages}{head}
        <div className="kv-after">
          <div className="kv-winner">
            <span className="muted">Kveldens vinner</span>
            <p className="kv-wname"><span className="loud">{leader?.name ?? "–"}</span></p>
            <p className="kv-wpts"><b>{leader?.points ?? 0}</b> poeng</p>
            {(drives || closest) && (
              <div className="kv-sides">
                {drives && <div><span>Lengste drive</span><b>{game.name(drives.memberID)}</b><em>{drives.holeIndex !== null ? `hull ${game.holeNumber(drives.holeIndex)} · ` : ""}{Math.round(drives.meters)} m</em></div>}
                {closest && <div><span>Nærmest pinnen</span><b>{game.name(closest.memberID)}</b><em>{closest.holeIndex !== null ? `hull ${game.holeNumber(closest.holeIndex)} · ` : ""}{closest.meters.toLocaleString("nb-NO", { maximumFractionDigits: 1 })} m</em></div>}
              </div>
            )}
          </div>
          <div className="card kv-table">
            <div className="ph"><h2>Kveldens tabell</h2><span className="muted">Stableford</span></div>
            <table><tbody>
              {table.rows.map((r, i) => <tr key={r.memberID} className={i === 0 ? "lead" : ""}><td className="pl">{i + 1}</td><td>{r.name}</td><td className="r strong">{r.points}</td></tr>)}
            </tbody></table>
          </div>
        </div>
        {canRounds && live.event && live.competition?.season_id && (
          <Challenge clubID={clubID} seasonID={live.competition.season_id} eventID={live.event.id}
            players={players.map((p) => ({ memberID: p.memberID, group: p.group }))} name={(m) => game.name(m)} term={term} />
        )}
        <p className="muted kv-locknote">Når runden er låst, kan ingen endre scorene, og den teller i turneringen.</p>
      </div>
    );
  }

  return (
    <div className="kv">
      {messages}{head}
      <div className="kv-kpis">
        <div className="kk"><span>Inne</span><b><em>{inCount}</em> av {players.length}</b><small>{inGroups.length === 0 ? "Ingen er ferdige ennå" : `${inGroups.map((g) => groupName(g.no)).join(", ")} er ferdig`}</small></div>
        <div className="kk"><span>Siste {term.singular}</span><b><em>{out.length ? holeCount - Math.min(...out.map((g) => g.played)) : 0}</em> hull igjen</b><small>{out.length ? groupName(out.reduce((a, g) => (g.played < a.played ? g : a)).no) : "–"}</small></div>
        <div className="kk"><span>Leder i kveld</span><b>{leader ? `${leader.name.split(" ")[0]}, ${leader.points} p` : "–"}</b><small>{leader ? (leader.cells.filter((c) => c.strokes !== null).length >= holeCount ? "inne" : `gjennom ${leader.cells.filter((c) => c.strokes !== null).length}`) : ""}</small></div>
        <div className={needs ? "kk need" : "kk"}><span>Trenger deg</span><b><em>{needs}</em> {needs === 1 ? "ting" : "ting"}</b><small>{needs ? "Se til høyre" : "Alt er i orden"}</small></div>
      </div>

      <Course game={game} groups={groups} gaps={gaps.map((g) => g.group)} groupName={groupName} flip={flip.ref} term={term.plural} />

      <div className="kv-grid">
        <div className="card kv-table">
          <div className="ph"><h2>Kveldens tabell</h2><span className="muted">Stableford</span></div>
          <table>
            <thead><tr><th></th><th>Spiller</th><th>{capitalized(term.singular)}</th><th className="r">Gjennom</th><th className="r">Poeng</th></tr></thead>
            <tbody>
              {table.rows.map((r, i) => {
                const thru = r.cells.filter((c) => c.strokes !== null).length;
                const p = players.find((x) => x.memberID === r.memberID);
                return (
                  <tr key={r.memberID} ref={flip.ref("row:" + r.memberID)} className={i === 0 ? "lead" : ""}>
                    <td className="pl">{i + 1}</td><td className="nm">{r.name}</td><td className="fl">{p ? groupName(p.group) : ""}</td>
                    <td className={thru >= holeCount ? "r thru inn" : "r thru"}>{thru >= holeCount ? "Inne" : thru}</td><td className="r pts">{r.points}</td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
        <div className="kv-side">
          <div className={needs ? "card kv-needs" : "card kv-needs clear"}>
            <div className="ph"><h2>Trenger deg</h2></div>
            {gaps.map((g) => (
              <div key={`${g.memberID}:${g.holeIndex}`} className="kv-need">
                <div><b>Hull {game.holeNumber(g.holeIndex)} mangler score</b><span>{groupName(g.group)} · {game.name(g.memberID)}</span></div>
                <button className="primary small" onClick={() => onOpen("terminliste")}>Rett score</button>
              </div>
            ))}
            {canMembers && pending.map((m) => (
              <div key={m.id} className="kv-need">
                <div><b>{m.display_name} vil bli med</b><span>Troppen{m.handicap_index !== null ? ` · hcp ${m.handicap_index.toLocaleString("nb-NO")}` : ""}</span></div>
                <button className="secondary small" disabled={busy === m.id} onClick={() => approve(m)}>Godkjenn</button>
              </div>
            ))}
            {!needs && <p className="kv-allgood">Alt er i orden. <span className="soft">Nyt kvelden.</span></p>}
          </div>
          <div className="card kv-feed">
            <div className="ph"><h2>Siste</h2><span className="muted live-dot">oppdateres hvert 20. sekund</span></div>
            {feed.length === 0 ? <p className="muted">Ingen hull er lagret ennå.</p> : (
              <ol>{feed.map((f) => <li key={feedKey(f)}><time>{clockText(f.at)}</time><span>{feedText(f, game.holeNumber.bind(game), game.name.bind(game), groupName)}</span></li>)}</ol>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}

const feedKey = (f: KvFeedItem) => `${f.kind}:${f.at}:${"group" in f ? f.group : f.memberID}:${"holeIndex" in f ? f.holeIndex : ""}`;
function feedText(f: KvFeedItem, hole: (i: number) => number, name: (m: string) => string, groupName: (n: number) => string) {
  if (f.kind === "in") return <><b>{groupName(f.group)}</b> er inne</>;
  if (f.kind === "score") return <><b>{name(f.memberID)}</b> på hull {hole(f.holeIndex)} <span className="tag">{f.name}</span></>;
  return <>{groupName(f.group)} lagret hull {hole(f.holeIndex)}</>;
}

/** Banen nå: hullene i to rader, med hver gruppe på hullet den står på. */
function Course({ game, groups, gaps, groupName, flip, term }: {
  game: LiveRound["game"]; groups: KvGroup[]; gaps: number[]; groupName: (n: number) => string;
  flip: (key: string) => (el: HTMLElement | null) => void; term: string;
}) {
  const holes = game.holes.map((h, i) => ({ i, no: game.holeNumber(i), par: h.par }));
  const rows = holes.length > 9 ? [holes.slice(0, 9), holes.slice(9)] : [holes];
  const chip = (g: KvGroup) => (
    <span key={g.no} ref={flip("chip:" + g.no)} className={gaps.includes(g.no) ? "kv-chip warn" : "kv-chip"} title={g.members.map((m) => game.name(m)).join(", ")}>
      <i />{groupName(g.no)}
    </span>
  );
  return (
    <div className="kv-course">
      <div className="kv-ch"><h2>Banen nå</h2><span>{capitalized(term)} der de er, oppdatert når markøren lagrer</span></div>
      <div className="kv-rows">
        {rows.map((row, r) => (
          <div key={r} className="kv-row"><span className="kv-lbl">{rows.length > 1 ? (r === 0 ? "Ut" : "Inn") : "Hull"}</span>
            <div className="kv-holes">
              {row.map((h) => (
                <div key={h.i} className={h.par === 3 ? "kv-hole p3" : h.par === 5 ? "kv-hole p5" : "kv-hole"}>
                  <div className="hn"><b>{h.no}</b><span>par {h.par}</span></div>
                  {groups.filter((g) => !g.done && g.nextIndex === h.i).map(chip)}
                </div>
              ))}
            </div>
          </div>
        ))}
        <div className="kv-row"><span className="kv-lbl">Inne</span><div className="kv-in">{groups.filter((g) => g.done).map(chip)}</div></div>
      </div>
    </div>
  );
}

/** Før runden: neste spilledag og sjekklisten. */
function Before({ next, pending, busy, onApprove, onOpen, canRounds }: {
  next: NextDay | null | undefined; pending: Member[]; busy: string | null; onApprove: (m: Member) => void;
  onOpen: (tab: "terminliste" | "tropp") => void; canRounds: boolean;
}) {
  if (next === undefined) return <p className="muted">Henter neste spilledag …</p>;
  if (!next) return (
    <div className="kv-empty">
      <h1><span className="loud">Ingen kveld</span> <span className="soft">satt opp ennå.</span></h1>
      <p className="muted">Legg til en spilledag i terminlista, så dukker den opp her.</p>
      {canRounds && <button className="primary" onClick={() => onOpen("terminliste")}>Til terminlista</button>}
    </div>
  );
  const d = next.draft;
  const items: { ok: boolean; title: string; text: string }[] = [
    { ok: next.signups > 0, title: "Påmelding", text: next.signups > 0 ? `${next.signups} kommer${next.waitlisted ? ` · ${next.waitlisted} på venteliste` : ""}` : "Ingen har meldt seg på ennå" },
    { ok: !!d, title: "Runden", text: d ? "Satt opp som kladd" : "Ikke satt opp ennå" },
    { ok: !!d?.courseChosen, title: "Bane og tee", text: d?.courseChosen ? "Valgt" : "Ikke valgt" },
    { ok: !!d && d.players > 0 && d.grouped === d.players, title: "Flighter og markører", text: d && d.players > 0 ? `${d.grouped} av ${d.players} er fordelt` : "Ingen spillere i runden ennå" },
  ];
  const done = items.filter((i) => i.ok).length;
  return (
    <>
      <div className="kv-head">
        <div>
          <p className="kv-eyebrow"><span className="pill">Neste</span>{capitalized(longDate(next.event.event_date))}{next.event.start_time ? ` · ${next.event.start_time.slice(0, 5)}` : ""}</p>
          <h1><span className="loud">{next.competition?.name ?? "Spilledag"}</span> {next.event.venue && <span className="soft">{next.event.venue}</span>}</h1>
        </div>
        {canRounds && <div className="btns"><button className="primary" onClick={() => onOpen("terminliste")}>Sett opp runden</button></div>}
      </div>
      <div className="kv-ready">
        <div className="kv-meter"><b><em>{done}</em> av {items.length}</b><span>klart</span><div className="bar"><i style={{ width: `${(done / items.length) * 100}%` }} /></div></div>
        <ol className="card kv-check">
          {items.map((i) => <li key={i.title} className={i.ok ? "ok" : "todo"}><i /><div><b>{i.title}</b><span>{i.text}</span></div></li>)}
          {pending.map((m) => (
            <li key={m.id} className="todo"><i /><div><b>{m.display_name} vil bli med</b><span>Troppen</span></div>
              <button className="secondary small" disabled={busy === m.id} onClick={() => onApprove(m)}>Godkjenn</button></li>
          ))}
        </ol>
      </div>
    </>
  );
}
