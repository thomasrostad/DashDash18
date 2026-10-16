// «Konkurranser i runden» og lag mot lag (sql/048): flere konkurranser på samme runde, lagret med
// round_competitions_set, og side 1/2 per spiller i set_round_setup. Ren logikk; kallene ligger i api.ts.

import {
  competitionBoards, formAxes, formById, frozenFromRows, sidesFromRaw, teamMatchResult,
  type CompetitionBoard, type MaxStrokes, type RyderCupResult, type ScoringMethod, type SnapshotFields, type StoredCompetition, type TeamForm,
} from "../../../golfgutu-core/src/index.ts";
import type { RoundGame } from "./game.ts";

type UUID = string;

/** Hvem som er med i konkurransen. */
export type EntrantMode =
  /** Alle med score (utelatt i config). */
  | "all"
  /** Bare de valgte. */
  | "selected"
  /** Rundens lag (par), eller par i båsene når runden ikke har lag. */
  | "teams"
  /** Grupper: rundens lag, ellers båsene (Amerikaner og Københavner). */
  | "groups"
  /** Match: side 1 mot side 2 i lag mot lag (utelatt i config; sidene leses fra round_players.side). */
  | "sides";

/** Maksimumscore: konkurransens eget tak, ellers `null` (regelsettets `formPlay.maximumScore`). */
export function maxStrokesOf(d: CompetitionDraft): MaxStrokes | null {
  const s = axesOf(d).scoring;
  return s.type === "maximumScore" ? s.maxStrokes ?? null : null;
}

/** Maksimumscore med eget tak (eller regelsettets, `null`). Formen blir aksene. */
export function withMaxStrokes(d: CompetitionDraft, cap: MaxStrokes | null): CompetitionDraft {
  const a = axesOf(d);
  if (a.scoring.type !== "maximumScore") return d;
  if (cap === null) return { ...d, form: "maks-score", teamForm: null, scoring: null };
  return { ...d, form: null, teamForm: a.teamForm, scoring: { type: "maximumScore", net: a.scoring.net, maxStrokes: cap } };
}

/** «tak netto dobbel bogey» eller «tak 8 slag». */
export function capText(cap: MaxStrokes): string {
  return cap.type === "fixed" ? `tak ${cap.strokes} slag` : cap.type === "netDoubleBogey" ? "tak netto dobbel bogey" : "uten tak";
}

/** Hullene som teller. `back` bare på 18 hull. */
export type HolesChoice = "all" | "front" | "back";

export type RecipeID = "bestball" | "maks" | "match" | "skins" | "front" | "back" | "amerikaner" | "kobenhavner";

export interface CompetitionDraft {
  /** Raden i round_competitions, eller null for en ny. */
  id: UUID | null;
  name: string;
  /** Katalogens form-id, eller null når aksene står for seg (bestball i par). */
  form: string | null;
  teamForm: TeamForm | null;
  scoring: ScoringMethod | null;
  entrants: EntrantMode;
  selected: UUID[];
  holes: HolesChoice;
  /** 0–1, eller null (fullt). */
  allowance: number | null;
}

export const MAX_COMPETITIONS = 10;

/** Oppskriftene i «Legg til». */
export const RECIPES: readonly { id: RecipeID; name: string; help: string }[] = [
  { id: "bestball", name: "Bestball i par", help: "Beste netto på hullet teller for paret." },
  { id: "maks", name: "Maksimumscore", help: "Slagspill med tak per hull (netto dobbel bogey eller fast antall)." },
  { id: "match", name: "Match", help: "To spillere, eller side 1 mot side 2, hull for hull." },
  { id: "skins", name: "Skins", help: "Hvert hull er ett skin. Likt gjør at det går videre." },
  { id: "front", name: "Første ni", help: "Samme form, bare hull 1–9." },
  { id: "back", name: "Siste ni", help: "Samme form, bare hull 10–18." },
  { id: "amerikaner", name: "Amerikaner", help: "Fire i gruppen deler 12 poeng per hull." },
  { id: "kobenhavner", name: "Københavner", help: "Tre i gruppen deler 6 poeng per hull." },
];

/** Ny konkurranse fra oppskriften. `mainForm` er rundens form (første og siste ni). */
export function recipeDraft(id: RecipeID, mainForm: string): CompetitionDraft {
  const base: CompetitionDraft = {
    id: null, name: RECIPES.find((r) => r.id === id)!.name, form: null, teamForm: null, scoring: null,
    entrants: "all", selected: [], holes: "all", allowance: null,
  };
  switch (id) {
    case "bestball":
      return { ...base, teamForm: { type: "pairs", pairs: "fourball" }, scoring: { type: "strokePlay", net: true }, entrants: "teams" };
    case "maks":
      return { ...base, form: "maks-score" };
    case "match":
      return { ...base, teamForm: { type: "individual" }, scoring: { type: "matchPlay" }, entrants: "selected" };
    case "skins":
      return { ...base, form: "skins" };
    case "front":
      return { ...base, form: mainForm, holes: "front" };
    case "back":
      return { ...base, form: mainForm, holes: "back" };
    case "amerikaner":
    case "kobenhavner":
      return { ...base, form: id, entrants: "groups" };
  }
}

/** Oppskriftene som passer runden: «Siste ni» bare på 18 hull. */
export function recipesFor(holeCount: number): typeof RECIPES {
  return RECIPES.filter((r) => r.id !== "back" || holeCount === 18);
}

/** Det runden er satt opp med (spillerne, lagene og båsene). */
export interface CompetitionContext {
  participants: readonly UUID[];
  teams: Readonly<Record<UUID, number>>;
  bays: readonly { memberID: UUID; bay: number; isMarker: boolean }[];
  holeCount: number;
  mainForm: string;
  /** Lag mot lag: side 1 eller 2 per spiller. */
  sides?: Readonly<Record<UUID, number>>;
}

function grouped(ids: readonly UUID[], key: (id: UUID) => number | undefined): UUID[][] {
  const groups = new Map<number, UUID[]>();
  for (const id of ids) {
    const k = key(id);
    if (k === undefined) continue;
    groups.set(k, [...(groups.get(k) ?? []), id]);
  }
  return [...groups.entries()].sort((a, b) => a[0] - b[0]).map(([, g]) => g);
}

function hasTeams(ctx: CompetitionContext): boolean {
  return ctx.participants.some((id) => ctx.teams[id] !== undefined);
}

/** Parene: rundens lag, ellers to og to i hver bås (markøren først). */
export function pairsFor(ctx: CompetitionContext): UUID[][] {
  if (hasTeams(ctx)) return grouped(ctx.participants, (id) => ctx.teams[id]);
  const inBay = new Set(ctx.participants);
  const out: UUID[][] = [];
  for (const bay of [...new Set(ctx.bays.map((s) => s.bay))].sort((a, b) => a - b)) {
    const seats = ctx.bays.filter((s) => s.bay === bay && inBay.has(s.memberID))
      .sort((a, b) => Number(b.isMarker) - Number(a.isMarker)).map((s) => s.memberID);
    for (let i = 0; i < seats.length; i += 2) out.push(seats.slice(i, i + 2));
  }
  return out;
}

/** Gruppene: rundens lag, ellers båsene. */
export function groupsFor(ctx: CompetitionContext): UUID[][] {
  if (hasTeams(ctx)) return grouped(ctx.participants, (id) => ctx.teams[id]);
  return grouped(ctx.participants, (id) => ctx.bays.find((s) => s.memberID === id)?.bay);
}

export function axesOf(d: CompetitionDraft): { teamForm: TeamForm; scoring: ScoringMethod } {
  if (d.form) return formAxes(formById(d.form));
  return { teamForm: d.teamForm ?? { type: "individual" }, scoring: d.scoring ?? { type: "stableford", net: true } };
}

/** Lagform med flere på siden (par eller lag). */
function isSideForm(t: TeamForm): boolean {
  return t.type !== "individual";
}

/**
 * `config` slik 048 godtar den: bare nøklene form, teamForm, scoring, entrants, holes og allowance, og bare de
 * som er satt. Hovedkonkurransen er `{form}`.
 */
export function competitionConfig(d: CompetitionDraft, ctx: CompetitionContext, isMain = false): Record<string, unknown> {
  if (isMain) return { form: ctx.mainForm };
  const config: Record<string, unknown> = {};
  if (d.form) config.form = d.form;
  else {
    const a = axesOf(d);
    config.teamForm = a.teamForm;
    config.scoring = a.scoring;
  }
  const inRound = new Set(ctx.participants);
  const { teamForm, scoring } = axesOf(d);
  let entrants: UUID[][] | null = null;
  switch (d.entrants) {
    case "all":
    case "sides": entrants = null; break;
    case "teams": entrants = pairsFor(ctx); break;
    case "groups": entrants = groupsFor(ctx); break;
    case "selected": {
      const ids = d.selected.filter((id) => inRound.has(id));
      // Poengspill og skins: de valgte er én gruppe. Ellers hver for seg.
      entrants = scoring.type === "pointsGame" || scoring.type === "skins" || isSideForm(teamForm) ? [ids] : ids.map((id) => [id]);
      break;
    }
  }
  if (entrants !== null) {
    entrants = entrants.map((g) => g.filter((id) => inRound.has(id))).filter((g) => g.length > 0);
    config.entrants = entrants;
  }
  const holes = holeRange(d.holes, ctx.holeCount);
  if (holes) config.holes = holes;
  if (d.allowance !== null) config.allowance = Math.max(0, Math.min(1, d.allowance));
  return config;
}

/** 0-basert og inkludert, som 048 og motoren. */
export function holeRange(h: HolesChoice, holeCount: number): { first: number; last: number } | null {
  if (h === "front" && holeCount === 18) return { first: 0, last: 8 };
  if (h === "back" && holeCount === 18) return { first: 9, last: 17 };
  return null;
}

/** Problemene som stopper lagringen, på norsk. */
export function competitionIssues(list: readonly CompetitionDraft[], ctx: CompetitionContext): string[] {
  const out: string[] = [];
  if (list.length + 1 > MAX_COMPETITIONS) out.push(`Høyst ${MAX_COMPETITIONS} konkurranser per runde.`);
  for (const d of list) {
    const name = d.name.trim();
    if (name.length === 0) out.push("Hver konkurranse må ha et navn.");
    else if (name.length > 60) out.push(`«${name.slice(0, 20)}…» har for langt navn (høyst 60 tegn).`);
    const label = name || "Konkurransen";
    if (d.holes !== "all" && ctx.holeCount !== 18) out.push(`${label}: første eller siste ni krever 18 hull.`);
    if (d.entrants === "selected" && d.selected.filter((id) => ctx.participants.includes(id)).length === 0) out.push(`${label}: velg minst én spiller.`);
    if (d.entrants === "teams" && pairsFor(ctx).every((p) => p.length < 2)) out.push(`${label}: sett lag først.`);
    if (d.allowance !== null && (d.allowance < 0 || d.allowance > 1)) out.push(`${label}: andelen må være 0–100 %.`);
    if (axesOf(d).scoring.type === "matchPlay") {
      if (d.entrants === "selected" && new Set(d.selected.filter((id) => ctx.participants.includes(id))).size !== 2) out.push(`${label}: velg to spillere.`);
      if (d.entrants !== "selected") {
        const sides = Object.entries(ctx.sides ?? {}).filter(([id]) => ctx.participants.includes(id)).map(([, s]) => s);
        if (!sides.includes(1) || !sides.includes(2)) out.push(`${label}: side 1 mot side 2 krever lag mot lag med to sider.`);
      }
    }
    const cap = maxStrokesOf(d);
    if (cap?.type === "fixed" && !(Number.isInteger(cap.strokes) && cap.strokes >= 3 && cap.strokes <= 20)) out.push(`${label}: taket må være 3–20 slag.`);
  }
  return [...new Set(out)];
}

/** Elementene til `round_competitions_set`: hovedkonkurransen først, så de andre i rekkefølge. */
export function competitionsPayload(list: readonly CompetitionDraft[], ctx: CompetitionContext, mainID: UUID | null = null): Record<string, unknown>[] {
  const main = { ...(mainID ? { id: mainID } : {}), name: formById(ctx.mainForm).name, is_main: true, format_version: 1, config: { form: ctx.mainForm }, sort_order: 0 };
  return [main, ...list.map((d, i) => ({
    ...(d.id ? { id: d.id } : {}),
    name: d.name.trim(),
    is_main: false,
    format_version: 1,
    config: competitionConfig(d, ctx),
    sort_order: i + 1,
  }))];
}

/** Lagret rad → utkast. Hvem som er med, gjettes fra formen (lag, grupper eller de valgte). */
export function draftFromStored(c: StoredCompetition): CompetitionDraft {
  const cfg = c.config;
  const form = typeof cfg.form === "string" ? cfg.form : null;
  const teamForm = (cfg.teamForm ?? null) as TeamForm | null;
  const scoring = (cfg.scoring ?? null) as ScoringMethod | null;
  const axes = form ? formAxes(formById(form)) : { teamForm: teamForm ?? { type: "individual" } as TeamForm, scoring: scoring ?? { type: "stableford", net: true } as ScoringMethod };
  const raw = Array.isArray(cfg.entrants) ? (cfg.entrants as unknown[]).filter(Array.isArray).map((g) => (g as unknown[]).map(String)) : null;
  const entrants: EntrantMode = raw === null ? (axes.scoring.type === "matchPlay" ? "sides" : "all")
    : axes.scoring.type === "matchPlay" && axes.teamForm.type === "individual" ? "selected"
    : isSideForm(axes.teamForm) ? "teams"
      : axes.scoring.type === "pointsGame" ? "groups" : "selected";
  const h = cfg.holes as { first?: number; last?: number } | undefined;
  const holes: HolesChoice = h?.first === 0 && h?.last === 8 ? "front" : h?.first === 9 && h?.last === 17 ? "back" : "all";
  return {
    id: c.id, name: c.name, form, teamForm: form ? null : teamForm, scoring: form ? null : scoring,
    entrants, selected: raw ? [...new Set(raw.flat().map((x) => x.toLowerCase()))] : [], holes,
    allowance: typeof cfg.allowance === "number" ? cfg.allowance : null,
  };
}

/** De lagrede radene → hovedkonkurransens id og de andre som utkast. */
export function draftsFromStored(rows: readonly StoredCompetition[]): { mainID: UUID | null; extras: CompetitionDraft[] } {
  const sorted = [...rows].sort((a, b) => a.sortOrder - b.sortOrder);
  return { mainID: sorted.find((c) => c.isMain)?.id ?? null, extras: sorted.filter((c) => !c.isMain).map(draftFromStored) };
}

/**
 * «Samme som sist» (`previous_round_setup.competitions`): de andre konkurransene som nye rader (uten id). Spiller-id-ene
 * er fra forrige runde; de som ikke er med nå, tas bort når den lagres.
 */
export function copiedCompetitions(rows: readonly StoredCompetition[]): CompetitionDraft[] {
  return draftsFromStored(rows).extras.map((d) => ({ ...d, id: null })).slice(0, MAX_COMPETITIONS - 1);
}

/** Kort linje under konkurransen: hvem, hull og andel. */
export function competitionSummary(d: CompetitionDraft, holeCount: number): string {
  const who = d.entrants === "all" ? "Alle" : d.entrants === "teams" ? "Parene" : d.entrants === "groups" ? "Gruppene"
    : d.entrants === "sides" ? "Side 1 mot side 2" : `${d.selected.length} valgt`;
  const holes = d.holes === "all" || holeCount !== 18 ? "alle hull" : d.holes === "front" ? "hull 1–9" : "hull 10–18";
  const parts = [who, holes];
  const cap = maxStrokesOf(d);
  if (cap) parts.push(capText(cap));
  if (d.allowance !== null) parts.push(`${Math.round(d.allowance * 100)} % handicap`);
  return parts.join(" · ");
}

// MARK: Lag mot lag

export type Side = 1 | 2;

/**
 * Sjekken fra set_round_setup (048): spillerne på samme lag er på samme side, og enten har alle på laget side
 * eller ingen. null når det er i orden.
 */
export function sideProblem(sides: Readonly<Record<UUID, Side>>, teams: Readonly<Record<UUID, number>>, participants: readonly UUID[]): string | null {
  const byTeam = new Map<number, (Side | undefined)[]>();
  for (const id of participants) {
    const t = teams[id];
    if (t === undefined) continue;
    byTeam.set(t, [...(byTeam.get(t) ?? []), sides[id]]);
  }
  for (const [, list] of byTeam) {
    const set = new Set(list.filter((s) => s !== undefined));
    const withSide = list.filter((s) => s !== undefined).length;
    if (set.size > 1 || (withSide > 0 && withSide !== list.length)) return "Spillerne på samme lag må være på samme side.";
  }
  return null;
}

/** «side» per spiller i `p_players` (bare når 048 er kjørt, så et gammelt oppsett ikke visker ut sidene). */
export function withSides<T extends { member_id: UUID }>(players: readonly T[], sides: Readonly<Record<UUID, Side>>): (T & { side: Side | null })[] {
  return players.map((p) => ({ ...p, side: sides[p.member_id] ?? null }));
}

/** Sidene fra `round_players` (rå rader med `side`). */
export function sidesFromRows(rows: readonly { member_id: string; side?: number | null }[]): Record<UUID, Side> {
  const out: Record<UUID, Side> = {};
  for (const r of rows) if (r.side === 1 || r.side === 2) out[r.member_id.toLowerCase()] = r.side;
  return out;
}

/** Sett laget på samme side som spilleren (så sjekken over holder når én flyttes). */
export function setSide(sides: Readonly<Record<UUID, Side>>, teams: Readonly<Record<UUID, number>>, id: UUID, side: Side | null): Record<UUID, Side> {
  const out = { ...sides };
  const team = teams[id];
  const ids = team === undefined ? [id] : Object.keys(teams).filter((x) => teams[x] === team);
  for (const x of ids) { if (side === null) delete out[x]; else out[x] = side; }
  return out;
}

// MARK: Resultatene på rundens side

export interface RoundFormats {
  competitions: StoredCompetition[];
  snapshot: SnapshotFields;
  sidePlayers: unknown[];
}

/**
 * Konkurransene og lag mot lag for runden: fra øyeblikksbildet (FrozenRound) når runden har det, ellers fra dagens
 * data. Vises når runden har andre konkurranser eller sider.
 */
export function roundResults(game: RoundGame, f: RoundFormats): { boards: CompetitionBoard[]; team: RyderCupResult | null; reconstructed: boolean } | null {
  const sides = sidesFromRaw(f.sidePlayers);
  if (!f.competitions.some((c) => !c.isMain) && sides.size === 0) return null;
  const frozen = frozenFromRows(f.snapshot, game.snapshot.players, game.rules, (m) => game.handicap(m));
  const boards = competitionBoards({
    competitions: f.competitions, roundFormat: game.snapshot.round.format, frozen,
    live: { round: game.round, roster: game.roster, rules: game.rules }, sides,
  });
  return {
    boards,
    team: teamMatchResult(game.round, sides, game.roster, frozen?.ruleset ?? game.rules),
    reconstructed: f.snapshot.snapshotSource === "backfill",
  };
}
