import { useMemo, useState } from "react";
import { allowanceFor, courseHoles, formSetup, isTeamForm, rulesetSuggestions, suggestedClosestToPinHole, suggestedLongestDriveHole } from "../../../golfgutu-core/src/index.ts";
import { loadSlopeCatalog, loadSourceCourses, saveDraft, startRound, type DayData, type ListRound } from "./api.ts";
import {
  coreCourseWithTee, courseItemReady, courseSummary, filterSlope, previousTeeID, slopePlace, suggestedTee, teeDetail,
  teeGenderTitle, SLOPE_PICKER_LIMIT, type CourseItem, type SlopeCourse,
} from "./courses.ts";
import {
  applySidePrize, bayCount as highestBay, bayNumbers, coreRound, draftForm, prepareSetup, excludePlayer, formChoices,
  groupTerm, includePlayer, isTeamMatch, isTriangleMatch, makeMarker, markerIn, membersIn, moveSeat, playerMatch,
  playersSummary, redrawMatches, reshuffleBays, roundTitle, seatFor, setCourse, setForm, setStart, setVenue, setupIssues,
  sidePrizeChoice, startOptions, startProblems, startTitle, suggestedTeams, teamMatch, teamProblem, termCount, termNumbered,
  termPluralTitle, venueTitle, WEIGHTS, MAX_BAYS, type MatchDraft, type RoundDraft,
} from "./logic.ts";

/**
 * «Sett opp runden» og «Fortsett kladd», som appens hurtigstart (RundeQuickStartView, RundeCourseStartSteps,
 * RundeBaysStep, RundeSetupStep): bane og tee, start, spillere og båser, form, lag, matcher, sidepremier og
 * vekt og handicap. Lagres som kladd eller startes med de samme RPC-ene som appen.
 */
export function RoundSetup({ clubID, data, initial, titleOf, onCancel, onDone }: {
  clubID: string; data: DayData; initial: RoundDraft; titleOf: (r: ListRound) => string;
  onCancel: () => void; onDone: (text: string) => void;
}) {
  // Som `onAppear` i appen: lag og matcher klare, og uten valg mellom simulator og ekte bane følger stedet banen.
  const [draft, setDraft] = useState<RoundDraft>(() => {
    let d = prepareSetup(initial, data.rules, data.roster);
    const ready = data.courses.filter(courseItemReady);
    const showsVenue = new Set(ready.map((c) => c.kind)).size > 1;
    const c = data.courses.find((x) => x.course.id === d.courseID);
    if (!d.isSaved && !showsVenue && c) d = setVenue(d, c.kind === "course" ? "course" : "simulator", data.rules);
    return d;
  });
  const [courses, setCourses] = useState<CourseItem[]>(data.courses);
  const [bays, setBays] = useState(Math.max(1, highestBay(draft.bays)));
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const rules = data.rules;
  const roster = data.roster;
  const name = (id: string) => roster.find((m) => m.id === id)?.name ?? "Ukjent";

  const item = courses.find((c) => c.course.id === draft.courseID) ?? null;
  const core = item ? coreCourseWithTee(item, draft.teeID) : null;
  const term = groupTerm(draft.venue);
  const form = draftForm(draft);
  const holes = courseHoles(coreRound(draft, core));
  const ready = courses.filter(courseItemReady);
  const courseCheck = item ? { name: item.course.name, isReady: courseItemReady(item) } : null;
  const saveIssues = setupIssues(draft, courseCheck, rules, roster, false);
  const blocking = data.allRounds.find((r) => r.status === "active" && r.id !== draft.roundID) ?? null;
  const problems = startProblems(setupIssues(draft, courseCheck, rules, roster, true), term, blocking ? titleOf(blocking) : null);
  const title = roundTitle(draft.roundNo, item?.course.name);

  function selectCourse(c: CourseItem) {
    let d = setVenue(draft, c.kind === "course" ? "course" : "simulator", rules);
    d = setCourse(d, c.course.id, c.holes.length);
    if (d.teeID === null && c.tees.length > 0) d = { ...d, teeID: suggestedTee(c.tees, previousTeeID(data.allRounds, c.course.id))?.id ?? null };
    setDraft(d);
  }

  async function act(start: boolean) {
    setBusy(true); setError(null);
    try {
      const ctx = { clubID, rules, roster, course: item };
      if (start) {
        await startRound(ctx, draft, titleOf);
        onDone(`${title} er startet.`);
      } else {
        await saveDraft(ctx, draft);
        onDone(`${title} er lagret som kladd. Bare arrangørene ser den.`);
      }
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="setup">
      <h3>{draft.isSaved ? `Fortsett kladd · ${title}` : `Sett opp ${title}`}</h3>

      <div className="card">
        <h3>Bane</h3>
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
            let d = setVenue(draft, "course", rules);
            d = setCourse(d, loaded.course.id, loaded.holes.length);
            setDraft({ ...d, teeID: suggestedTee(loaded.tees, previousTeeID(data.allRounds, loaded.course.id))?.id ?? null });
          } catch (e) { setError((e as Error).message); }
        }} />
      </div>

      <div className="card">
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

      <div className="card">
        <h3>Spillere og {term.plural} · {playersSummary(draft)}</h3>
        <p className="muted small">{draft.participantSource === "everyone"
          ? "Ingen har svart «Kommer» ennå, så alle står som med. Ta ut dem som ikke kommer."
          : draft.participantSource === "signups"
            ? `De som har svart «Kommer» er med. «Bland på nytt» fordeler på ${termCount(term, bays)}, med duellpartnere i samme ${term.singular} og én markør i hver.`
            : `De som er satt opp i kladden. «Bland på nytt» fordeler på ${termCount(term, bays)}.`}</p>
        <div className="inline">
          <label className="check">{termPluralTitle(term)}
            <input type="number" min={1} max={Math.max(1, Math.min(MAX_BAYS, draft.participants.length))} value={bays}
              onChange={(e) => setBays(Math.max(1, Math.min(MAX_BAYS, Number(e.target.value) || 1)))} />
          </label>
          <button className="link" onClick={() => setDraft(reshuffleBays(draft, bays))}>Bland på nytt</button>
        </div>
        <div className="bays">
          {bayNumbers(draft.bays).map((bay) => {
            const ids = membersIn(draft.bays, bay);
            const marker = markerIn(draft.bays, bay);
            const over = ids.length > rules.formats.maxPerBay;
            return (
              <div key={bay} className="bay">
                <h4>{termNumbered(term, bay)} <span className={over ? "error small" : "muted small"}>{ids.length}{over ? ` · over ${rules.formats.maxPerBay}` : ""}</span></h4>
                {ids.map((id) => seatRow(id))}
                {marker === undefined && <p className="error small">Ingen markør. Velg «Gjør til markør» på en av dem.</p>}
              </div>
            );
          })}
          {draft.participants.some((id) => !seatFor(draft.bays, id)) && (
            <div className="bay">
              <h4>Uten {term.singular}</h4>
              {draft.participants.filter((id) => !seatFor(draft.bays, id)).map((id) => seatRow(id))}
            </div>
          )}
        </div>
        {roster.some((m) => !draft.participants.includes(m.id)) && (
          <>
            <h4>Ikke med</h4>
            <div className="chips">
              {roster.filter((m) => !draft.participants.includes(m.id)).map((m) => (
                <button key={m.id} className="link" onClick={() => setDraft(prepareSetup(includePlayer(draft, m.id, roster), rules, roster))}>+ {m.name}</button>
              ))}
            </div>
            <p className="muted small">Trykk for å ta med. Han havner i {term.definite} med færrest.</p>
          </>
        )}
      </div>

      <div className="card">
        <h3>Form</h3>
        <select value={draft.formID} onChange={(e) => setDraft(setForm(draft, e.target.value, rules, roster))}>
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

      {isTeamForm(form) && (
        <div className="card">
          <h3>Lag · {form.teamSize} per lag</h3>
          {(() => {
            const count = draft.participants.length;
            const numbers = Math.max(2, form.allowsUnevenTeams ? count : Math.floor((count + form.teamSize - 1) / form.teamSize));
            return draft.participants.map((id) => (
              <label key={id} className="row-inline">{name(id)}
                <select value={draft.teams[id] ?? ""} onChange={(e) => {
                  const teams = { ...draft.teams };
                  if (e.target.value) teams[id] = Number(e.target.value); else delete teams[id];
                  setDraft(redrawMatches({ ...draft, teams }, roster));
                }}>
                  <option value="">Uten lag</option>
                  {Array.from({ length: numbers }, (_, i) => i + 1).map((n) => <option key={n} value={n}>Lag {n}</option>)}
                </select>
              </label>
            ));
          })()}
          <button className="link" onClick={() => setDraft(redrawMatches({ ...draft, teams: suggestedTeams(draft.participants, form, rules.formats.maxPerBay) }, roster))}>Foreslå lag</button>
          {(() => { const p = teamProblem(draft.teams, draft.participants, form, rules.formats.maxPerBay); return p ? <p className="error small">{p}</p> : null; })()}
        </div>
      )}

      {rules.table.pointsSource === "matches" && (
        <div className="card">
          <h3>Matcher</h3>
          {draft.matches.length === 0 && <p className="muted">Ingen matcher</p>}
          {draft.matches.map((m, i) => (
            matchRow(i, m)
          ))}
          <div className="inline">
            <button className="link" onClick={() => setDraft({ ...draft, matches: [...draft.matches, isTeamForm(form) ? teamMatch(1, 2) : playerMatch(null, null)] })}>Ny match</button>
            <button className="link" onClick={() => setDraft(redrawMatches(draft, roster))}>Trekk matchene på nytt</button>
            <button className="link" onClick={() => setDraft(reshuffleBays(draft, bays))}>Sett matchene sammen i {term.definitePlural}</button>
          </div>
        </div>
      )}

      <div className="card">
        <h3>Sidepremier</h3>
        <div className="grid2 tight">
          {sidePrize("Longest drive", draft.ldEnabled, draft.ldHoleIndex, suggestedLongestDriveHole(coreRound(draft, core)),
            (v) => setDraft({ ...draft, ldEnabled: v.enabled, ldHoleIndex: v.holeIndex }))}
          {sidePrize("Nærmest pinnen", draft.kpEnabled, draft.kpHoleIndex, suggestedClosestToPinHole(coreRound(draft, core)),
            (v) => setDraft({ ...draft, kpEnabled: v.enabled, kpHoleIndex: v.holeIndex }))}
        </div>
      </div>

      <details className="card" open={draft.weight !== 1 || (!draft.externalHandicap && draft.allowance !== allowanceDefault())}>
        <summary><strong>Avansert</strong></summary>
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
      <div className="inline sticky-actions">
        <button className="link" disabled={busy || saveIssues.length > 0} onClick={() => act(false)}>Lagre som kladd</button>
        <button className="primary" disabled={busy || problems.length > 0} onClick={() => act(true)}>Start runden</button>
        <button className="link" disabled={busy} onClick={onCancel}>Avbryt</button>
      </div>
    </div>
  );

  function allowanceDefault(): number {
    return allowanceFor(rules, form);
  }

  function seatRow(id: string) {
    const seat = seatFor(draft.bays, id);
    const highest = Math.max(highestBay(draft.bays), bays);
    const options = Array.from({ length: Math.min(highest + 1, MAX_BAYS) }, (_, i) => i + 1);
    return (
      <div className="seat" key={id}>
        <span>{name(id)}{seat?.isMarker && <span className="pill">Markør</span>}</span>
        <select value={seat?.bay ?? ""} onChange={(e) => {
          const v = e.target.value;
          if (v === "out") setDraft(prepareSetup(excludePlayer(draft, id), rules, roster));
          else setDraft({ ...draft, bays: moveSeat(draft.bays, id, Number(v)) });
        }}>
          {!seat && <option value="">Uten {term.singular}</option>}
          {options.map((b) => <option key={b} value={b}>{b > highest ? `Ny ${term.singular} ${b}` : termNumbered(term, b)}</option>)}
          <option value="out">Ikke med</option>
        </select>
        {seat && !seat.isMarker && <button className="link" onClick={() => setDraft({ ...draft, bays: makeMarker(draft.bays, id) })}>Gjør til markør</button>}
      </div>
    );
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
          {holes.map((h, i) => <option key={i} value={i}>Hull {i + offset} · par {h.par}{i === suggestion ? " (forslag)" : ""}</option>)}
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
      if (!catalog) { try { setCatalog(await loadSlopeCatalog()); } catch (e) { setError((e as Error).message); } }
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
