import { useState } from "react";
import { createCompetition, createSeason, setPlaysWhenItSuits, type Competition } from "./data.ts";
import { decodeRuleset, encodeRuleset, RULESET_TEMPLATES, templateRules, templateSummary, templateTitle, validateRuleset, type Ruleset, type RulesetTemplate } from "./engine.ts";
import { decodeTournamentTemplate, encodeTournamentTemplate, weekdayName, type ScheduleTemplate, type SetupTemplate, type TournamentTemplate } from "./reuse.ts";
import { SeriesForm } from "./SeriesForm.tsx";
import { TemplateBar } from "./Templates.tsx";
import { supabase, errorText } from "./supabase.ts";
import { todayISO } from "./text.ts";

/** «Ny turnering» som i appen: velg oppsett, navn og det viktigste. Reglene kommer fra samme maler (golfgutu-core). */
export function NewTournament({ clubID, comps, canTemplates = false, onDone, onCancel }: {
  clubID: string; comps: Competition[];
  /** Egne maler for turneringer (rettigheten tournaments, sql/049). */
  canTemplates?: boolean;
  onDone: () => void; onCancel: () => void;
}) {
  const [template, setTemplate] = useState<RulesetTemplate | null>(null);
  /** Malen arrangøren valgte («Bruk mal»), med en nøkkel så skjemaet fylles på nytt. */
  const [fromTemplate, setFromTemplate] = useState<{ key: string; value: TournamentTemplate } | null>(null);
  function use(t: SetupTemplate) {
    const value = decodeTournamentTemplate(t.payload);
    const setup = value.template ?? setupFor(value.kind);
    if (!setup) return;
    setTemplate(setup);
    setFromTemplate({ key: `${t.id}-${Date.now()}`, value });
  }
  return template === null ? (
    <section>
      <button className="link" onClick={onCancel}>← Avbryt</button>
      <h2>Ny turnering</h2>
      {canTemplates && <TemplateBar clubID={clubID} kind="tournament" canSave={false} payload={() => ({})} onUse={use} />}
      <div className="grid2">
        {RULESET_TEMPLATES.map((t) => (
          <button key={t} className="card choice" onClick={() => setTemplate(t)}>
            <strong>{templateTitle(t)}</strong>
            <span className="muted">{templateSummary(t)}</span>
          </button>
        ))}
      </div>
    </section>
  ) : (
    <Details key={fromTemplate?.key ?? template} clubID={clubID} template={template} comps={comps} initial={fromTemplate?.value ?? null}
      canTemplates={canTemplates} onUseTemplate={use} onDone={onDone} onBack={() => { setTemplate(null); setFromTemplate(null); }} />
  );
}

/** Oppsettet for en mal uten `template` (eldre eller laget et annet sted). */
function setupFor(kind: TournamentTemplate["kind"]): RulesetTemplate | null {
  return kind === "cup" ? "cup" : kind === "fun" ? "fun" : kind === "season" || kind === "league" ? "stablefordSeries" : null;
}

/** Regelsettet fra malen, eller oppsettets når malen mangler eller ikke kan leses. */
function rulesFrom(t: TournamentTemplate | null, template: RulesetTemplate): Ruleset {
  if (t?.rules) { try { return decodeRuleset(t.rules); } catch { /* oppsettets regler */ } }
  return templateRules(template);
}

/** Turneringen som ble laget: konkurransens id (sesongens speil for en serie). */
async function competitionIDForSeason(seasonID: string): Promise<string | null> {
  const { data } = await supabase.from("competitions").select("id").eq("season_id", seasonID).maybeSingle();
  return (data as { id: string } | null)?.id ?? null;
}

function suggestedName(t: RulesetTemplate, taken: string[]): string {
  const now = new Date();
  const season = now.getMonth() >= 7 ? "Høst" : now.getMonth() >= 3 ? "Vår" : "Vinter";
  const base = t === "cup" ? `${season}cupen ${now.getFullYear()}` : t === "fun" ? `${season}morro ${now.getFullYear()}` : `${season} ${now.getFullYear()}`;
  let name = base; let n = 2;
  while (taken.some((x) => x.toLowerCase() === name.toLowerCase())) name = `${base} (${n++})`;
  return name;
}

function Details({ clubID, template, comps, initial, canTemplates, onUseTemplate, onDone, onBack }: {
  clubID: string; template: RulesetTemplate; comps: Competition[]; initial: TournamentTemplate | null;
  canTemplates: boolean; onUseTemplate: (t: SetupTemplate) => void; onDone: () => void; onBack: () => void;
}) {
  // Alle oppsettene utenom cup og morro er serier i klubben (sesong), også de fra steg 7.
  const isSeries = template !== null && template !== "cup" && template !== "fun";
  const base = rulesFrom(initial, template);
  const today = todayISO();
  const [name, setName] = useState(suggestedName(template, comps.map((c) => c.name)));
  const [evenings, setEvenings] = useState(base.evenings);
  const [dayTerm, setDayTerm] = useState<"evening" | "playingDay">(initial && base.dayTerm === "evening" ? "evening" : "playingDay");
  const [start, setStart] = useState(false);
  const [asMain, setAsMain] = useState(true);
  const [entry, setEntry] = useState<string>(template === "cup" ? "listed" : initial?.entry ?? "club");
  const [signupOpen, setSignupOpen] = useState(initial?.signupOpen ?? true);
  /** Fast spilledag (sql/049): lagres i malen, og «Lag serie» tilbys etter at turneringen er laget. */
  const [schedule, setSchedule] = useState<ScheduleTemplate | null>(initial?.schedule ?? null);
  /** Turneringen er laget og har en plan: «Lag serie» før vi er ferdige. */
  const [seriesFor, setSeriesFor] = useState<string | null>(null);
  const [hasPeriod, setHasPeriod] = useState(false);
  const [startsOn, setStartsOn] = useState(today);
  const [endsOn, setEndsOn] = useState(today);
  const [whenItSuits, setWhenItSuits] = useState(false);
  const [best, setBest] = useState<number | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  // Flere serier kan gå samtidig (sql/034), men bare én er hovedturneringen.
  const activeMain = comps.find((c) => c.kind === "season" && c.status === "active" && c.is_main);

  function rules() {
    const r = rulesFrom(initial, template);
    if (isSeries) { r.evenings = evenings; r.dayTerm = dayTerm; }
    if (template === "fun" && r.competition) r.competition.fun.bestRounds = whenItSuits ? best : r.competition.fun.bestRounds;
    return r;
  }

  async function save(e: React.FormEvent) {
    e.preventDefault();
    const r = rules();
    const issues = validateRuleset(r);
    if (!name.trim()) { setError("Gi turneringen et navn."); return; }
    if (issues.length) { setError(issues[0].message); return; }
    if ((hasPeriod || whenItSuits) && endsOn < startsOn) { setError("Perioden slutter før den starter."); return; }
    setBusy(true); setError(null);
    try {
      let createdID: string | null = null;
      if (isSeries) {
        const seasonID = await createSeason(clubID, name, encodeRuleset(r), start, !activeMain || asMain);
        if (schedule) createdID = await competitionIDForSeason(seasonID);
      } else {
        const period = hasPeriod || whenItSuits;
        const id = await createCompetition({
          clubID, kind: template as "cup" | "fun", name, entry: template === "cup" ? "listed" : entry, rules: encodeRuleset(r),
          startsOn: period ? startsOn : null, endsOn: period ? endsOn : null, signupOpen: (template === "cup" || entry === "listed") && signupOpen,
        });
        if (whenItSuits) await setPlaysWhenItSuits(id, true);
        createdID = id;
      }
      if (schedule && createdID) { setSeriesFor(createdID); return; }
      onDone();
    } catch (err) { setError(errorText(err)); } finally { setBusy(false); }
  }

  function payload(): Record<string, unknown> {
    return encodeTournamentTemplate({
      template, kind: isSeries ? "season" : (template as "cup" | "fun"), rules: encodeRuleset(rules()), schedule,
      venue: schedule?.venue ?? null, entry: template === "cup" ? "listed" : (entry as "listed" | "club" | "open"),
      signupOpen, maxEntrants: initial?.maxEntrants ?? null,
    });
  }

  if (seriesFor) {
    return (
      <section>
        <h2>{name.trim()} er laget</h2>
        <SeriesForm comps={[]} competitionID={seriesFor} schedule={schedule} onDone={onDone} onCancel={onDone} />
      </section>
    );
  }

  return (
    <section>
      <button className="link" onClick={onBack}>← Oppsettene</button>
      <h2>{templateTitle(template)}</h2>
      <form className="card" onSubmit={save}>
        <label>Navn<input required maxLength={60} value={name} onChange={(e) => setName(e.target.value)} /></label>
        {isSeries && <>
          <label>Antall {dayTerm === "playingDay" ? "spilledager" : "kvelder"}
            <input type="number" min={1} max={40} value={evenings} onChange={(e) => setEvenings(Number(e.target.value))} /></label>
          <label>En dag heter
            <select value={dayTerm} onChange={(e) => setDayTerm(e.target.value as "evening" | "playingDay")}>
              <option value="playingDay">Spilledag</option><option value="evening">Kveld</option>
            </select>
          </label>
          <label className="check"><input type="checkbox" checked={start} onChange={(e) => setStart(e.target.checked)} />Start turneringen nå</label>
          {start && activeMain && (
            <fieldset>
              <legend>Skal serien erstatte hovedturneringen?</legend>
              <label className="check"><input type="radio" name="asMain" checked={asMain} onChange={() => setAsMain(true)} />Erstatt</label>
              <label className="check"><input type="radio" name="asMain" checked={!asMain} onChange={() => setAsMain(false)} />Kjør ved siden av</label>
              <p className="muted">{asMain
                ? `«${activeMain.name}» blir ferdig, og serien blir hovedturnering.`
                : `Begge går, og «${activeMain.name}» er fortsatt hovedturneringen.`}</p>
            </fieldset>
          )}
        </>}
        {!isSeries && <>
          {template === "fun" && (
            <label>Hvem er med
              <select value={entry} onChange={(e) => setEntry(e.target.value)}>
                <option value="club">Hele troppen</option><option value="listed">De påmeldte</option><option value="open">Alle som spiller en runde som teller</option>
              </select>
            </label>
          )}
          {(template === "cup" || entry === "listed") && (
            <label className="check"><input type="checkbox" checked={signupOpen} onChange={(e) => setSignupOpen(e.target.checked)} />Åpen påmelding</label>
          )}
          {template === "fun" && (
            <label className="check"><input type="checkbox" checked={whenItSuits} onChange={(e) => { setWhenItSuits(e.target.checked); if (e.target.checked) setHasPeriod(true); }} />Spill når det passer (rundene i perioden teller av seg selv)</label>
          )}
          {whenItSuits && (
            <label>Hvor mange runder teller
              <select value={best ?? ""} onChange={(e) => setBest(e.target.value ? Number(e.target.value) : null)}>
                <option value="">Alle runder</option>
                {[1, 2, 3, 4, 5, 6, 8, 10].map((n) => <option key={n} value={n}>De beste {n}</option>)}
              </select>
            </label>
          )}
          <label className="check"><input type="checkbox" checked={hasPeriod} disabled={whenItSuits} onChange={(e) => setHasPeriod(e.target.checked)} />Har en periode</label>
          {hasPeriod && (
            <div className="grid2 tight">
              <label>Fra<input type="date" value={startsOn} onChange={(e) => setStartsOn(e.target.value)} /></label>
              <label>Til<input type="date" value={endsOn} onChange={(e) => setEndsOn(e.target.value)} /></label>
            </div>
          )}
        </>}
        {canTemplates && (
          <fieldset>
            <legend>Fast spilledag</legend>
            <label className="check"><input type="checkbox" checked={schedule !== null}
              onChange={(e) => setSchedule(e.target.checked ? { weekday: 4, everyWeeks: 1, count: Math.min(52, evenings || 10), startTime: "18:00", venue: null } : null)} />Lag serie etterpå</label>
            {schedule && (
              <div className="grid2 tight">
                <label>Ukedag
                  <select value={schedule.weekday} onChange={(e) => setSchedule({ ...schedule, weekday: Number(e.target.value) })}>
                    {[1, 2, 3, 4, 5, 6, 7].map((d) => <option key={d} value={d}>{weekdayName(d)}</option>)}
                  </select>
                </label>
                <label>Antall<input type="number" min={1} max={52} value={schedule.count}
                  onChange={(e) => setSchedule({ ...schedule, count: Math.min(52, Math.max(1, Number(e.target.value))) })} /></label>
                <label>Hver
                  <select value={schedule.everyWeeks} onChange={(e) => setSchedule({ ...schedule, everyWeeks: Number(e.target.value) })}>
                    {[1, 2, 3, 4, 5, 6, 7, 8].map((n) => <option key={n} value={n}>{n === 1 ? "uke" : `${n}. uke`}</option>)}
                  </select>
                </label>
                <label>Tid<input type="time" value={schedule.startTime ?? ""} onChange={(e) => setSchedule({ ...schedule, startTime: e.target.value || null })} /></label>
                <label>Sted<input value={schedule.venue ?? ""} maxLength={80} onChange={(e) => setSchedule({ ...schedule, venue: e.target.value || null })} /></label>
              </div>
            )}
          </fieldset>
        )}
        {error && <p className="error">{error}</p>}
        <div className="inline"><button className="primary" disabled={busy}>Lag turneringen</button></div>
      </form>
      {canTemplates && <TemplateBar clubID={clubID} kind="tournament" payload={payload} onUse={onUseTemplate} />}
    </section>
  );
}
