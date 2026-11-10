import { useState } from "react";
import type { CompetitionForm } from "../../../golfgutu-core/src/index.ts";
import { autoLineup, lineupMatches, lineupOf, placePlayer, type LineupTarget } from "./lineup.ts";
import { makeMarker, MAX_BAYS, termNumbered, termPluralTitle, type GroupTerm, type RosterMember, type RoundDraft, type UUID } from "./logic.ts";

/**
 * Oppstillingstavla: båsene med lagene i, spillerne som brikker. Trykk på en spiller og så på plassen
 * (eller dra den dit). ★ gjør spilleren til markør i båsen. I lagformer blir matchene lag mot lag i båsen.
 */
export function LineupBoard({ draft, form, teamForm, maxPerBay, bays, setBays, roster, term, withMatches, onChange }: {
  draft: RoundDraft; form: CompetitionForm; teamForm: boolean; maxPerBay: number;
  bays: number; setBays: (n: number) => void; roster: readonly RosterMember[]; term: GroupTerm;
  /** Tabellen teller matcher: lagformene får matchene fra tavla. */
  withMatches: boolean;
  onChange: (d: RoundDraft) => void;
}) {
  const [picked, setPicked] = useState<UUID | null>(null);
  const lineup = lineupOf(draft, form, teamForm, maxPerBay, bays);
  const name = (id: UUID) => roster.find((m) => m.id === id)?.name ?? "Ukjent";
  const hcp = (id: UUID) => roster.find((m) => m.id === id)?.handicap;
  const outside = roster.filter((m) => !draft.participants.includes(m.id));

  function apply(d: RoundDraft) {
    onChange(teamForm && withMatches ? { ...d, matches: lineupMatches(d) } : d);
  }
  function drop(target: LineupTarget, id: UUID | null = picked) {
    if (!id) return;
    apply(placePlayer(draft, id, target, roster));
    setPicked(null);
  }
  const dropProps = (target: LineupTarget) => ({
    onClick: () => drop(target),
    onDragOver: (e: React.DragEvent) => e.preventDefault(),
    onDrop: (e: React.DragEvent) => { e.preventDefault(); drop(target, e.dataTransfer.getData("text/plain") || null); },
    className: picked ? "lu-drop armed" : "lu-drop",
  });

  function chip(id: UUID, marker = false, showStar = true) {
    const h = hcp(id);
    return (
      <span key={id} role="button" tabIndex={0} draggable
        className={["lu-chip", picked === id ? "picked" : "", marker ? "marker" : ""].join(" ")}
        onDragStart={(e) => { e.dataTransfer.setData("text/plain", id); setPicked(id); }}
        onClick={(e) => {
          // Er en annen spiller valgt, går trykket videre til plassen (laget) brikken står i.
          if (picked && picked !== id) return;
          e.stopPropagation(); setPicked(picked === id ? null : id);
        }}
        onKeyDown={(e) => { if (e.key === "Enter" || e.key === " ") { e.preventDefault(); setPicked(picked === id ? null : id); } }}>
        <span className="lu-name">{name(id)}</span>
        {h !== null && h !== undefined && <span className="lu-hcp">{h.toLocaleString("nb-NO")}</span>}
        {showStar && (
          <button type="button" className={marker ? "lu-star on" : "lu-star"} title={marker ? "Markør" : "Gjør til markør"}
            aria-label={marker ? `${name(id)} er markør` : `Gjør ${name(id)} til markør`}
            onClick={(e) => { e.stopPropagation(); if (!marker) onChange({ ...draft, bays: makeMarker(draft.bays, id) }); }}>★</button>
        )}
      </span>
    );
  }

  const matchText = teamForm && withMatches
    ? lineupMatches(draft).map((m) => `Lag ${m.teamA} mot lag ${m.teamB}`).join(" · ")
    : null;

  return (
    <div className="card lu">
      <div className="lu-head">
        <h3>Oppstilling</h3>
        <div className="inline">
          <label className="check">{termPluralTitle(term)}
            <input type="number" min={1} max={MAX_BAYS} value={bays} onChange={(e) => setBays(Math.max(1, Math.min(MAX_BAYS, Number(e.target.value) || 1)))} />
          </label>
          <button type="button" className="secondary" onClick={() => { apply(autoLineup(draft, roster, form, teamForm, maxPerBay, bays)); setPicked(null); }}>Fordel automatisk</button>
        </div>
      </div>
      <p className="muted small">
        {picked ? `Trykk der ${name(picked)} skal stå.` : "Trykk på en spiller og så på plassen, eller dra. ★ er markøren."}
        {teamForm ? " Fordel automatisk lager jevne lag etter handicap." : " Fordel automatisk sprer handicapene jevnt på båsene."}
      </p>

      <div className="lu-bays">
        {lineup.bays.map((b) => (
          <section key={b.bay} className={b.problems.length ? "lu-bay bad" : b.notes.length ? "lu-bay warn" : "lu-bay"}>
            <header>
              <strong>{termNumbered(term, b.bay)}</strong>
              <span className={b.over ? "error small" : "muted small"}>{b.members.length} av {maxPerBay}</span>
            </header>
            {teamForm ? (
              <div className={b.teams.length === 2 ? "lu-teams vs" : "lu-teams"}>
                {b.teams.map((t, i) => [
                  b.teams.length === 2 && i === 1 ? <span key="mot" className="lu-mot" aria-hidden>mot</span> : null,
                  <div key={t.team} {...dropProps({ kind: "bay", bay: b.bay, team: t.team })}>
                    <div className={t.members.length > 0 && t.missing !== 0 ? "lu-team off" : "lu-team"}>
                      <span className="lu-label">Lag {t.team}</span>
                      {t.members.map((id) => chip(id, b.marker === id))}
                      {t.members.length === 0 && <span className="lu-empty">Tomt</span>}
                    </div>
                  </div>,
                ])}
              </div>
            ) : (
              <div {...dropProps({ kind: "bay", bay: b.bay })}>
                <div className="lu-team">
                  {b.members.map((id) => chip(id, b.marker === id))}
                  {b.members.length === 0 && <span className="lu-empty">Tom</span>}
                </div>
              </div>
            )}
            {[...b.problems.map((p) => ["error", p]), ...b.notes.map((p) => ["warn", p])].map(([kind, p]) => (
              <p key={p} className={`${kind} small`}>{p}</p>
            ))}
          </section>
        ))}
      </div>

      <div className="lu-pools">
        <div {...dropProps({ kind: "unseated" })}>
          <div className="lu-team">
            <span className="lu-label">Med, uten {term.singular}</span>
            {lineup.unseated.map((id) => chip(id, false, false))}
            {lineup.teamless.map((id) => chip(id, false, false))}
            {lineup.unseated.length + lineup.teamless.length === 0 && <span className="lu-empty">Alle er plassert</span>}
          </div>
        </div>
        <div {...dropProps({ kind: "out" })}>
          <div className="lu-team">
            <span className="lu-label">Ikke med</span>
            {outside.map((m) => chip(m.id, false, false))}
            {outside.length === 0 && <span className="lu-empty">Alle er med</span>}
          </div>
        </div>
      </div>

      {lineup.problems.map((p) => <p key={p} className="error small">{p}</p>)}
      {matchText && <p className="muted small">Matcher: {matchText || "ingen ennå"}</p>}
    </div>
  );
}
