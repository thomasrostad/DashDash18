import { useEffect, useMemo, useState } from "react";
import { type Ruleset, allowanceFor, courseHoles, formSetup, isTeamForm, rulesetSuggestions, suggestedClosestToPinHole, suggestedLongestDriveHole } from "../../../golfgutu-core/src/index.ts";
import { applyPreviousPlayers, applyRoundTemplate, decodeRoundTemplate, encodeRoundTemplate, type PreviousSetup } from "../reuse.ts";
import { TemplateBar } from "../Templates.tsx";
import { longDate } from "../text.ts";
import { autoArrange } from "./logic.ts";
import { competitionContext, dayDrawPlan, lineupSharedAt, loadSlopeCatalog, loadSourceCourses, saveDraft, shareLineup, startRound, withFormats, type DayData, type ListRound } from "./api.ts";
import { CompetitionsCard, SidesCard } from "./CompetitionsSetup.tsx";
import { LineupBoard } from "./LineupBoard.tsx";
import { lineupOf } from "./lineup.ts";
import { checklistCount, setupChecklist, type ChecklistKey } from "./checklist.ts";
import {
  coreCourseWithTee, courseItemReady, courseSummary, filterSlope, previousTeeID, slopePlace, suggestedTee, teeDetail,
  teeGenderTitle, SLOPE_PICKER_LIMIT, type CourseItem, type SlopeCourse,
} from "./courses.ts";
import {
  applySidePrize, bayCount as highestBay, dataErrorText, drawFooter, STANDINGS_PLAN, coreRound, draftForm, prepareSetup, formChoices,
  groupTerm, isTeamMatch, isTriangleMatch, playerMatch,
  redrawMatches, reshuffleBays, roundTitle, setCourse, setForm, setStart, setVenue, setupIssues, venueAfterPick,
  sidePrizeChoice, startOptions, startProblems, startTitle, teamMatch,
  venueTitle, WEIGHTS, HIDE_LAST_HOLES, pointsTableChoices, type MatchDraft, type RoundDraft,
} from "./logic.ts";

/**
 * «Sett opp runden» og «Fortsett kladd», som appens hurtigstart (RundeQuickStartView, RundeCourseStartSteps,
 * RundeBaysStep, RundeSetupStep): bane og tee, start, spillere og båser, form, lag, matcher, sidepremier og
 * vekt og handicap. Lagres som kladd eller startes med de samme RPC-ene som appen.
 */
export function RoundSetup({ clubID, data, initial, titleOf, previous = null, canTemplates = false, onCancel, onDone }: {
  clubID: string; data: DayData; initial: RoundDraft; titleOf: (r: ListRound) => string;
  /** «Samme som sist» fra `previous_round_setup` (sql/049): spillerne og båsene som forslag. */
  previous?: PreviousSetup | null;
  /** «Lagre som mal» og «Bruk mal» (rettigheten rounds, sql/049). */
  canTemplates?: boolean;
  onCancel: () => void; onDone: (text: string) => void;
}) {
  // Som `onAppear` i appen: lag og matcher klare, og uten valg mellom simulator og ekte bane følger stedet banen.
  const [draft, setDraft] = useState<RoundDraft>(() => {
    let d = prepareSetup(initial, data.rules, data.roster, dayDrawPlan(data, initial.roundID));
    const ready = data.courses.filter(courseItemReady);
    const showsVenue = new Set(ready.map((c) => c.kind)).size > 1;
    const c = data.courses.find((x) => x.course.id === d.courseID);
    if (!d.isSaved && !showsVenue && c) d = setVenue(d, c.kind === "course" ? "course" : "simulator", data.rules);
    return d;
  });
  const [courses, setCourses] = useState<CourseItem[]>(data.courses);
  // Har arrangøren valgt sted selv, beholdes det når en bane fra slope.no velges (simulator på Oslo GK).
  const [venueChosen, setVenueChosen] = useState(draft.isSaved);
  const [bays, setBays] = useState(Math.max(1, highestBay(draft.bays)));
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  // sql/076: om spillerne ser oppstillingen før start.
  const [sharedAt, setSharedAt] = useState<string | null>(null);
  useEffect(() => {
    if (initial.isSaved) lineupSharedAt(initial.roundID).then(setSharedAt);
  }, [initial.isSaved, initial.roundID]);
  const rules = data.rules;
  const roster = data.roster;
  // sql/048: konkurransene og sidene. En lagret kladd henter dem; en ny runde starter tom (eller fra «Samme som sist»).
  const formats = data.formats === true;
  useEffect(() => {
    if (!formats) return;
    if (initial.isSaved && initial.competitions === undefined) {
      withFormats(initial).then((f) => setDraft((d) => ({ ...d, sides: f.sides, competitions: f.competitions, mainCompetitionID: f.mainCompetitionID, hadCompetitions: f.hadCompetitions })),
        (e) => setError(dataErrorText(e)));
    } else {
      setDraft((d) => ({ ...d, sides: d.sides ?? {}, competitions: d.competitions ?? [] }));
    }
  }, [formats, initial]);
  // Trekningen etter regelsettet (`formats.drawMethod`), med møtene i turneringens andre runder.
  const plan = useMemo(() => dayDrawPlan(data, draft.roundID), [data, draft.roundID]);
  const name = (id: string) => roster.find((m) => m.id === id)?.name ?? "Ukjent";

  const item = courses.find((c) => c.course.id === draft.courseID) ?? null;
  const core = item ? coreCourseWithTee(item, draft.teeID) : null;
  const term = groupTerm(draft.venue);
  const form = draftForm(draft);
  const holes = courseHoles(coreRound(draft, core));
  const ready = courses.filter(courseItemReady);
  const courseCheck = item ? { name: item.course.name, isReady: courseItemReady(item) } : null;
  const saveIssues = setupIssues(draft, courseCheck, rules, roster, false);
  const blocking = data.allRounds.find((r) => r.status === "active" && r.id !== draft.roundID && r.kind !== "playoff") ?? null;
  const problems = startProblems(setupIssues(draft, courseCheck, rules, roster, true), term, blocking ? titleOf(blocking) : null);
  const title = roundTitle(draft.roundNo, item?.course.name);
  // Sjekklista: samme sjekk som «Start runden», pluss tavlas røde og gule merknader.
  const lineup = lineupOf(draft, form, isTeamForm(form), rules.formats.maxPerBay, bays);
  const offset = draft.firstHole === 10 ? 10 : 1;
  const ld = sidePrizeChoice(draft.ldEnabled, draft.ldHoleIndex, suggestedLongestDriveHole(coreRound(draft, core)));
  const kp = sidePrizeChoice(draft.kpEnabled, draft.kpHoleIndex, suggestedClosestToPinHole(coreRound(draft, core)));
  const checklist = setupChecklist(setupIssues(draft, courseCheck, rules, roster, true), term, {
    bane: item ? [item.course.name, item.tees.find((t) => t.id === draft.teeID)?.name ? `tee ${item.tees.find((t) => t.id === draft.teeID)!.name}` : null, venueTitle(draft.venue)].filter(Boolean).join(" · ") : "Ikke valgt",
    start: [`Hull ${draft.firstHole}`, `${draft.holeCount} hull`, draft.teeTime?.slice(0, 5)].filter(Boolean).join(" · "),
    form: form.name,
    oppstilling: `${draft.participants.length} spillere i ${lineup.bays.filter((b) => b.members.length > 0).length} ${lineup.bays.filter((b) => b.members.length > 0).length === 1 ? term.singular : term.plural}`,
    sidepremier: [ld !== null ? `LD hull ${ld + offset}` : null, kp !== null ? `NP hull ${kp + offset}` : null].filter(Boolean).join(" · ") || "Av",
  }, lineup.bays.flatMap((b) => b.problems).concat(lineup.problems), lineup.bays.flatMap((b) => b.notes));
  const count = checklistCount(checklist);
  const jump = (key: ChecklistKey) => document.getElementById(`oppsett-${key}`)?.scrollIntoView({ behavior: "smooth", block: "start" });

  function selectCourse(c: CourseItem) {
    let d = setVenue(draft, venueAfterPick(draft.venue, c, venueChosen), rules);
    d = setCourse(d, c.course.id, c.holes.length);
    if (d.teeID === null && c.tees.length > 0) d = { ...d, teeID: suggestedTee(c.tees, previousTeeID(data.allRounds, c.course.id))?.id ?? null };
    setDraft(d);
  }

  async function act(start: boolean) {
    setBusy(true); setError(null);
    try {
      const ctx = { clubID, rules, roster, course: item, tableRules: data.tableRules, formats };
      if (start) {
        await startRound(ctx, draft, titleOf);
        onDone(`${title} er startet.`);
      } else {
        await saveDraft(ctx, draft);
        onDone(sharedAt
          ? `${title} er lagret som kladd. Spillerne ser den nye oppstillingen.`
          : `${title} er lagret som kladd. Bare arrangørene ser den.`);
      }
    } catch (e) {
      setError(dataErrorText(e));
    } finally {
      setBusy(false);
    }
  }

  /** «Lagre og vis for spillerne»: kladden lagres først, så ser spillerne det som står. */
  async function share(on: boolean) {
    setBusy(true); setError(null);
    try {
      if (on) {
        await saveDraft({ clubID, rules, roster, course: item, tableRules: data.tableRules, formats }, draft);
        await shareLineup(draft.roundID, true);
        onDone(`${title} er lagret, og spillerne ser oppstillingen. De har fått varsel.`);
      } else {
        setSharedAt(await shareLineup(draft.roundID, false));
      }
    } catch (e) {
      setError(dataErrorText(e));
    } finally {
      setBusy(false);
    }
  }

  const readyCourses = () => courses.filter(courseItemReady)
    .map((c) => ({ id: c.course.id, isReady: true, holeCount: c.holes.length, teeIDs: c.tees.map((t) => t.id) }));

  /** Spillerne fra sist, eller en ny trekning med dem som er med nå. */
  function usePlayers(fromLast: boolean) {
    if (!previous) return;
    let d = fromLast ? applyPreviousPlayers(draft, previous, roster) : { ...draft, participants: initial.participants, participantSource: initial.participantSource, teams: {}, matches: [] };
    d = fromLast ? prepareSetup(d, rules, roster, plan) : autoArrange(d, rules, roster, plan);
    setDraft(d);
    setBays(Math.max(1, highestBay(d.bays)));
  }

  return (
    <div className="setup-wrap">
    <div className="setup">
      <h3>{draft.isSaved ? `Fortsett kladd · ${title}` : `Sett opp ${title}`}</h3>

      {!draft.isSaved && previous && previous.players.length > 0 && (
        <div className="card">
          <h3>Samme som sist</h3>
          <p className="muted small">Banen og valgene er fylt inn fra runde {previous.roundNo}{previous.eventDate ? ` ${longDate(previous.eventDate)}` : ""}.</p>
          <div className="inline">
            <button type="button" onClick={() => usePlayers(true)}>Bruk spillerne fra sist</button>
            <button type="button" onClick={() => usePlayers(false)}>Ny trekning</button>
          </div>
        </div>
      )}

      {canTemplates && (
        <TemplateBar clubID={clubID} kind="round" payload={() => encodeRoundTemplate(draft)} onUse={(t) => {
          const d = applyRoundTemplate(draft, decodeRoundTemplate(t.payload), readyCourses(), rules.formats.allowedFormIDs, data.tableRules);
          setDraft(prepareSetup(d, rules, roster, plan));
        }} />
      )}

      <div className="card" id="oppsett-bane">
        <h3>Bane</h3>
        <p className="muted small">Hvor spiller dere?</p>
        <div className="segmented" role="group" aria-label="Hvor spiller dere?">
          {(["simulator", "course"] as const).map((v) => (
            <button key={v} type="button" className={v === draft.venue ? "seg active" : "seg"}
              onClick={() => { setVenueChosen(true); setDraft(setVenue(draft, v, rules)); }}>{venueTitle(v)}</button>
          ))}
        </div>
        {draft.venue === "simulator" && item?.kind === "course" && (
          <p className="muted small">Ekte bane spilt i simulatoren: parene og indeksene fra banen gjelder.</p>
        )}
        <label>Bane
          <select value={draft.courseID ?? ""} onChange={(e) => { const c = courses.find((x) => x.course.id === e.target.value); if (c) selectCourse(c); }}>
            {draft.courseID === null && <option value="">Velg</option>}
            {(["simulator", "course"] as const).map((kind) => {
              const list = courses.filter((c) => c.kind === kind && (courseItemReady(c) || c.course.id === draft.courseID));
              return list.length === 0 ? null : (
                <optgroup key={kind} label={kind === "course" ? "Ekte baner" : "Simulatorbaner"}>
                  {list.map((c) => <option key={c.course.id} value={c.course.id}>{c.course.name}{c.isFromSource ? " (slope.no)" : ""}</option>)}
                </optgroup>
              );
            })}
          </select>
        </label>
        {item && <p className="muted small">{courseSummary(item)} · {venueTitle(draft.venue)}</p>}
        {ready.length === 0 && <p className="muted small">Klubben har ingen baner som er klare. Velg en fra slope.no, eller legg inn parene i appen under Banene.</p>}
        {item && item.tees.length > 0 && (
          <label>Tee
            <select value={draft.teeID ?? ""} onChange={(e) => setDraft({ ...draft, teeID: e.target.value || null })}>
              <option value="">Banens tall</option>
              {item.tees.map((t) => <option key={t.id} value={t.id}>{t.name} ({teeGenderTitle(t.gender).toLowerCase()}) · {teeDetail(t)}</option>)}
            </select>
          </label>
        )}
        <SlopePicker exclude={new Set(courses.map((c) => c.course.id))} onPick={async (s) => {
          setError(null);
          try {
            const [loaded] = await loadSourceCourses([s.id]);
            if (!loaded || !courseItemReady(loaded)) throw new Error(`Fant ikke hullene til «${s.name}». Prøv igjen senere.`);
            setCourses([...courses.filter((c) => c.course.id !== loaded.course.id), loaded]);
            let d = setVenue(draft, venueAfterPick(draft.venue, loaded, venueChosen), rules);
            d = setCourse(d, loaded.course.id, loaded.holes.length);
            setDraft({ ...d, teeID: suggestedTee(loaded.tees, previousTeeID(data.allRounds, loaded.course.id))?.id ?? null });
          } catch (e) { setError(dataErrorText(e)); }
        }} />
      </div>

      <div className="card" id="oppsett-start">
        <h3>Start</h3>
        <div className="grid2 tight">
          <label>Hull og antall
            <select value={`${draft.firstHole}/${draft.holeCount}`} onChange={(e) => {
              const [firstHole, holeCount] = e.target.value.split("/").map(Number);
              setDraft(setStart(draft, { firstHole, holeCount }, item?.holes.length ?? null));
            }}>
              {startOptions(item?.holes.length ?? null).map((s) => <option key={`${s.firstHole}/${s.holeCount}`} value={`${s.firstHole}/${s.holeCount}`}>{startTitle(s)}</option>)}
            </select>
          </label>
          <label>Første tee
            <input type="time" value={draft.teeTime?.slice(0, 5) ?? ""} onChange={(e) => setDraft({ ...draft, teeTime: e.target.value ? `${e.target.value}:00` : null })} />
          </label>
        </div>
      </div>

      <div className="card" id="oppsett-form">
        <h3>Form</h3>
        <select value={draft.formID} onChange={(e) => setDraft(setForm(draft, e.target.value, rules, roster, plan))}>
          {formChoices(rules, draft.formID).map((f) => (
            <option key={f.id} value={f.id}>{f.name}{f.support === "delvis" ? " · ikke ferdig" : f.support === "mangler" ? " · ikke støttet ennå" : ""}</option>
          ))}
        </select>
        {(() => {
          const setup = formSetup(form, draft.participants.length, rules.formats.maxPerBay);
          if (setup.kind !== "impossible") return <p className="muted small">{form.help}</p>;
          const suggestions = rulesetSuggestions(rules, draft.participants.length);
          return (
            <>
              <p className="error small">{setup.reason}</p>
              {suggestions.length > 0 && <p className="muted small">Går opp med {draft.participants.length}: {suggestions.map((s) => `${s.name} (${s.text})`).join(", ")}.</p>}
            </>
          );
        })()}
      </div>

      <div id="oppsett-oppstilling" />
      <LineupBoard draft={draft} form={form} teamForm={isTeamForm(form)} maxPerBay={rules.formats.maxPerBay}
        bays={bays} setBays={setBays} roster={roster} term={term} withMatches={rules.table.pointsSource === "matches"}
        onChange={setDraft} />

      {formats && draft.competitions && (
        <CompetitionsCard list={draft.competitions} ctx={competitionContext(draft)} name={name}
          onChange={(competitions) => setDraft({ ...draft, competitions })} />
      )}

      {formats && draft.sides && (
        <SidesCard participants={draft.participants} sides={draft.sides} teams={competitionContext(draft).teams} name={name}
          onChange={(sides) => setDraft({ ...draft, sides })} />
      )}

      {rules.table.pointsSource === "matches" && !isTeamForm(form) && (
        <div className="card">
          <h3>Matcher</h3>
          {draft.matches.length === 0 && <p className="muted">Ingen matcher</p>}
          {draft.matches.map((m, i) => (
            matchRow(i, m)
          ))}
          <div className="inline">
            <button className="link" onClick={() => setDraft({ ...draft, matches: [...draft.matches, isTeamForm(form) ? teamMatch(1, 2) : playerMatch(null, null)] })}>Ny match</button>
            {plan.method === "manual"
              ? <button className="link" onClick={() => setDraft(redrawMatches(draft, roster, STANDINGS_PLAN))}>Foreslå matcher etter tabellen</button>
              : <button className="link" onClick={() => setDraft(redrawMatches(draft, roster, plan))}>Trekk matchene på nytt</button>}
            <button className="link" onClick={() => setDraft(reshuffleBays(draft, bays))}>Sett matchene sammen i {term.definitePlural}</button>
          </div>
          {!isTeamForm(form) && drawFooter(plan, draft.matches) && <p className="muted small">{drawFooter(plan, draft.matches)}</p>}
        </div>
      )}

      <div className="card" id="oppsett-sidepremier">
        <h3>Sidepremier</h3>
        <div className="grid2 tight">
          {sidePrize("Longest drive", draft.ldEnabled, draft.ldHoleIndex, suggestedLongestDriveHole(coreRound(draft, core)),
            (v) => setDraft({ ...draft, ldEnabled: v.enabled, ldHoleIndex: v.holeIndex }))}
          {sidePrize("Nærmest pinnen", draft.kpEnabled, draft.kpHoleIndex, suggestedClosestToPinHole(coreRound(draft, core)),
            (v) => setDraft({ ...draft, kpEnabled: v.enabled, kpHoleIndex: v.holeIndex }))}
        </div>
      </div>

      <details className="card" open={draft.weight !== 1 || (!draft.externalHandicap && draft.allowance !== allowanceDefault())
        || !draft.counts || draft.pointsTable !== null || draft.hideLastHoles > 0}>
        <summary><strong>Avansert</strong></summary>
        {data.tableRules && <TableRulesFields rules={rules} value={draft} onChange={(v) => setDraft({ ...draft, ...v })} />}
        <label>Hvor mye runden teller
          <select value={draft.weight} onChange={(e) => setDraft({ ...draft, weight: Number(e.target.value) })}>
            {WEIGHTS.map((w) => <option key={w.value} value={w.value}>{w.title}</option>)}
          </select>
        </label>
        {draft.venue === "simulator" && (
          <label className="check"><input type="checkbox" checked={draft.externalHandicap} onChange={(e) => setDraft({ ...draft, externalHandicap: e.target.checked })} />Trackman fordeler slagene</label>
        )}
        {!draft.externalHandicap && (
          <div className="inline">
            <label className="check">Handicapandel (%)
              <input type="number" min={0} max={100} step={5} value={Math.round(draft.allowance * 100)}
                onChange={(e) => setDraft({ ...draft, allowance: Math.max(0, Math.min(100, Number(e.target.value) || 0)) / 100 })} />
            </label>
            {draft.allowance !== allowanceDefault() && (
              <button className="link" onClick={() => setDraft({ ...draft, allowance: allowanceDefault() })}>Tilbake til regelsettets {Math.round(allowanceDefault() * 100)} %</button>
            )}
          </div>
        )}
      </details>

      {problems.length > 0 && (
        <div className="card">
          <h3>Før runden kan starte</h3>
          <ul className="plain">{problems.map((p) => <li key={p} className="error">{p}</li>)}</ul>
        </div>
      )}
      {error && <p className="error">{error}</p>}
      {sharedAt && (
        <p className="muted small">
          Spillerne ser oppstillingen. Endringer vises for dem når du lagrer.{" "}
          <button className="link" disabled={busy} onClick={() => share(false)}>Skjul for spillerne</button>
        </p>
      )}
      <div className="inline sticky-actions">
        <button className="link" disabled={busy || saveIssues.length > 0} onClick={() => act(false)}>Lagre som kladd</button>
        {!sharedAt && (
          <button className="link" disabled={busy || saveIssues.length > 0 || draft.participants.length === 0} onClick={() => share(true)}>Lagre og vis for spillerne</button>
        )}
        <button className="primary" disabled={busy || problems.length > 0} onClick={() => act(true)}>Start runden</button>
        <button className="link" disabled={busy} onClick={onCancel}>Avbryt</button>
      </div>
    </div>
    <aside className="checklist" aria-label="Sjekkliste">
      <div className="checklist-head">
        <strong>{count.ready === count.total ? "Klar til start" : "Sjekkliste"}</strong>
        <span className="muted small">{count.ready} av {count.total} klart</span>
      </div>
      <div className="checklist-bar"><span style={{ width: `${(count.ready / count.total) * 100}%` }} /></div>
      <ol>
        {checklist.map((c) => (
          <li key={c.key}>
            <button type="button" className={`check-item ${c.state}`} onClick={() => jump(c.key)}>
              <span className="check-dot" aria-hidden>{c.state === "ok" ? "✓" : c.state === "warn" ? "!" : "•"}</span>
              <span className="check-text"><b>{c.title}</b><span>{c.text}</span></span>
            </button>
          </li>
        ))}
      </ol>
      {problems.length > checklist.filter((c) => c.state === "bad").length && <p className="muted small">{problems[0]}</p>}
    </aside>
    </div>
  );

  function allowanceDefault(): number {
    return allowanceFor(rules, form);
  }

  function matchRow(index: number, match: MatchDraft) {
    const update = (m: MatchDraft) => setDraft({ ...draft, matches: draft.matches.map((x, i) => (i === index ? m : x)) });
    const teamNumbers = [...new Set(Object.values(draft.teams))].sort((a, b) => a - b);
    const playerSelect = (value: string | null, set: (v: string | null) => void, allowNone: boolean) => (
      <select value={value ?? ""} onChange={(e) => set(e.target.value || null)}>
        <option value="" disabled={!allowNone}>{allowNone ? "Ingen (duell)" : "Velg"}</option>
        {draft.participants.map((id) => <option key={id} value={id}>{name(id)}</option>)}
      </select>
    );
    return (
      <div className="match" key={index}>
        <strong>Match {index + 1}</strong>
        {isTeamMatch(match) ? (
          <>
            <select value={match.teamA ?? ""} onChange={(e) => update({ ...match, teamA: Number(e.target.value) })}>
              {teamNumbers.map((n) => <option key={n} value={n}>Lag {n}</option>)}
            </select>
            <span>mot</span>
            <select value={match.teamB ?? ""} onChange={(e) => update({ ...match, teamB: Number(e.target.value) })}>
              {teamNumbers.map((n) => <option key={n} value={n}>Lag {n}</option>)}
            </select>
          </>
        ) : (
          <>
            {playerSelect(match.playerA, (v) => update({ ...match, playerA: v }), false)}
            <span>mot</span>
            {playerSelect(match.playerB, (v) => update({ ...match, playerB: v }), false)}
            {playerSelect(match.playerC, (v) => update({ ...match, playerC: v }), true)}
            {isTriangleMatch(match) && <span className="muted small">En trekant avgjøres på poengsum, ikke hull mot hull.</span>}
          </>
        )}
        <button className="link" onClick={() => setDraft({ ...draft, matches: draft.matches.filter((_, i) => i !== index) })}>Fjern</button>
      </div>
    );
  }

  function sidePrize(label: string, enabled: boolean, hole: number | null, suggestion: number,
    onChange: (v: { enabled: boolean; holeIndex: number | null }) => void) {
    const choice = sidePrizeChoice(enabled, hole, suggestion);
    const offset = draft.firstHole === 10 ? 10 : 1;
    return (
      <label>{label}
        <select value={choice ?? ""} onChange={(e) => onChange(applySidePrize(e.target.value === "" ? null : Number(e.target.value), hole, suggestion))}>
          <option value="">Av</option>
          {holes.map((h, i) => <option key={i} value={i}>Hull {i + offset} · par {h.par}{h.meters ? ` · ${Math.round(h.meters)} m` : ""}{i === suggestion ? " (forslag)" : ""}</option>)}
        </select>
      </label>
    );
  }
}

/** «Fra slope.no»: banene med hull, søkt lokalt. Lista hentes første gang den åpnes. */
function SlopePicker({ exclude, onPick }: { exclude: Set<string>; onPick: (c: SlopeCourse) => Promise<void> }) {
  const [open, setOpen] = useState(false);
  const [catalog, setCatalog] = useState<SlopeCourse[] | null>(null);
  const [query, setQuery] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const hits = useMemo(() => (catalog ? filterSlope(catalog, query, exclude).slice(0, SLOPE_PICKER_LIMIT) : []), [catalog, query, exclude]);

  if (!open) {
    return <button className="link" onClick={async () => {
      setOpen(true);
      if (!catalog) { try { setCatalog(await loadSlopeCatalog()); } catch (e) { setError(dataErrorText(e)); } }
    }}>Fra slope.no …</button>;
  }
  return (
    <fieldset>
      <legend>Fra slope.no</legend>
      <input placeholder="Søk etter bane eller sted" value={query} onChange={(e) => setQuery(e.target.value)} />
      {error && <p className="error small">{error}</p>}
      {!catalog && !error && <p className="muted small">Henter banene …</p>}
      <ul className="plain">
        {hits.map((c) => (
          <li key={c.id}>
            <button className="link" disabled={busy} onClick={async () => { setBusy(true); await onPick(c); setBusy(false); setOpen(false); }}>{c.name}</button>
            <span className="muted small">Ekte bane{slopePlace(c) ? ` · ${slopePlace(c)}` : ""}</span>
          </li>
        ))}
      </ul>
      <p className="muted small">Banene med par, indeks og lengde per hull. Velg tee etterpå: teens hull, course rating og slope gjelder i runden. Hull, slope og course rating fra slope.no.</p>
      <button className="link" onClick={() => setOpen(false)}>Lukk</button>
    </fieldset>
  );
}

/** sql/047: «Teller ikke i tabellen», poengtabell og «Skjul de tre siste hullene». Også i RoundView. */
export function TableRulesFields({ rules, value, onChange, disabled = false }: {
  rules: Ruleset; value: TableRulesValue; onChange: (v: TableRulesValue) => void; disabled?: boolean;
}) {
  const choices = pointsTableChoices(rules, value.pointsTable);
  return (
    <>
      <label className="check"><input type="checkbox" disabled={disabled} checked={!value.counts}
        onChange={(e) => onChange({ ...value, counts: !e.target.checked })} />Teller ikke i tabellen</label>
      {value.counts && choices.length > 1 && (
        <label>Poengtabell
          <select disabled={disabled} value={value.pointsTable ?? ""} onChange={(e) => onChange({ ...value, pointsTable: e.target.value || null })}>
            {choices.map((c) => <option key={c.value ?? ""} value={c.value ?? ""}>{c.title}</option>)}
          </select>
        </label>
      )}
      <label className="check"><input type="checkbox" disabled={disabled} checked={value.hideLastHoles > 0}
        onChange={(e) => onChange({ ...value, hideLastHoles: e.target.checked ? HIDE_LAST_HOLES : 0 })} />Skjul de tre siste hullene</label>
      {value.hideLastHoles > 0 && <p className="muted">Spillerne ser sine egne. Alle andre ser dem når runden er låst.</p>}
    </>
  );
}

export interface TableRulesValue { counts: boolean; pointsTable: string | null; hideLastHoles: number }
