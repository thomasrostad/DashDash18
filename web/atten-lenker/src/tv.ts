// TV-visning med kode (fase 26, sql/041): dashdash18.com/tv/KODE på en skjerm uten appen.
// Workeren henter rådataene med tv_board_data(kode) og regner tabellen med regelmotoren i
// TypeScript (web/golfgutu-core), med samme tall og tekster som Tavla i appen.

import {
  CompetitionScope, CupStandings, decodeCompetitionMatch, decodeCompetitionParticipant, decodeCompetitionRound,
  decodeCompetitionRow, decodeProfile, decodeRoundParticipant, decodeTavlaData, LeagueStandings, makeSnapshot,
  decodeRoundRow, HIDDEN_HOLES_NOTE, hidesLastHoles, isPlayoff, PersonDirectory, type RoundsGrid, type UUID,
  decodeSeasonRow, tavlaInput, TavlaStandings, tavlaToJSON,
  competitionBoards, competitionRowText, competitionScoreText, decodeRuleset, decodeStoredCompetition, frozenFromRows, makeRoundFromSnapshot,
  sidesFromRaw, snapshotFields, snapshotHandicap, snapshotRoster, teamMatchResult, type Ruleset, type StoredCompetition, type TavlaData,
} from "../../golfgutu-core/src/index.ts";
import { ICON_LINKS } from "./html.ts";
import { SITE_FONTS, SITE_STYLE, topoSVG } from "./nettsted.ts";
import { LANDING_HEAD_STYLE } from "./salgsside.ts";

export interface TVEnv {
  SUPABASE_URL?: string;
  SUPABASE_KEY?: string;
}

/** Det TV-siden viser: navn, tabell og siste runde. */
export interface TVPayload {
  name: string;
  club: string | null;
  played: string;
  rows: { place: string; name: string; total: string; detail: string }[];
  latest: { title: string; ongoing: boolean; lines: { name: string; points: number }[] } | null;
  /**
   * «De siste hullene vises når runden er låst» (sql/047): en runde som går, skjuler de siste hullene, og
   * serveren sender ikke scorene på dem til TV-en. null ellers.
   */
  note: string | null;
  /**
   * De andre konkurransene i runden som går (eller siste runde med dem), sql/048: små paneler med de fem beste.
   * Bare navn som alt er i svaret. Tom uten 048.
   */
  extras: { title: string; lines: { name: string; score: string }[] }[];
  /** Lag mot lag i samme runde: poengene per side. null uten sider. */
  teams: { title: string; lines: { name: string; score: string }[] } | null;
  /**
   * Tittelen delt opp for utseendet (02.11.2026): navnet (store versaler), regelen (gull kursiv, null uten) og hvor
   * langt den har kommet. Samme tekst som `name` og `played`, bare delt.
   */
  heading: { title: string; rule: string | null; progress: string };
  /** Turnering med kvelder, liga/morro eller cup: overskriftene over tabellen. */
  kind: "season" | "league" | "cup";
  /**
   * Poengene per runde («Alle runder» i appen) som små ruter i tabellen. `rows` står i samme rekkefølge som `rows`
   * over (null når spilleren ikke er i rutenettet). `counted`: teller runden (beste N), null når alle teller. null uten runder.
   */
  rounds: {
    labels: string[];
    ongoing: boolean[];
    rows: ({ points: (number | null)[]; counted: boolean[] | null } | null)[];
  } | null;
}

/** Notisen når en vanlig runde som går, skjuler de siste hullene. Playoffen teller ikke med. */
export function hiddenHolesNote(board: Record<string, unknown>): string | null {
  const rounds = list(board, "rounds").map((x) => decodeRoundRow(x));
  return rounds.some((r) => r.status === "active" && !isPlayoff(r) && hidesLastHoles(r)) ? HIDDEN_HOLES_NOTE : null;
}

/** Koden slik serveren lagrer den: 10 tegn, store bokstaver, uten mellomrom. */
export function normalizeTVCode(raw: string): string | null {
  const code = decodeURIComponent(raw).replace(/[\s-]/g, "").toUpperCase();
  return /^[A-HJ-NP-Z2-9]{10}$/.test(code) ? code : null;
}

/** Svaret fra tv_board_data → det TV-en viser. Rent, uten nett (testes med fixturen fra golfgutu-core). */
export function buildTVPayload(board: Record<string, unknown>): TVPayload {
  if ((board.competition as { season_id?: string | null }).season_id == null) return competitionPayload(board);
  const comp = board.competition as {
    name: string; season_id: string; club_id: string; status: string; rules: Record<string, unknown>; club_name?: string | null;
  };
  const t = tavlaToJSON(seasonStandings(board));
  const playingDay = (comp.rules as { dayTerm?: string })?.dayTerm === "playingDay";
  const total = t.eveningsTotal;
  const unit = playingDay ? (total === 1 ? "spilledag" : "spilledager") : (total === 1 ? "kveld" : "kvelder");
  const played = `${t.eveningsPlayed} av ${total} ${unit} spilt`;
  return {
    name: t.countsStableford ? t.seasonName : `Jakkeracet · ${t.seasonName}`,
    club: comp.club_name ?? null,
    played,
    rows: t.rows.map((r) => ({ place: r.placeText, name: r.name, total: r.totalText, detail: r.detail })),
    // «Alle runder» har ikke playoffen (sql/047), så siste runde er alltid en vanlig runde.
    latest: latestRound(t.rounds),
    note: hiddenHolesNote(board),
    ...extraPanels(board, safeRules(comp.rules), () => new Map(list(board, "members").flatMap((x) => {
      const m = x as { id?: string; display_name?: string | null };
      return m.id && m.display_name ? [[m.id.toLowerCase(), m.display_name] as [string, string]] : [];
    }))),
    heading: { title: t.seasonName, rule: t.countsStableford ? null : "Jakkeracet", progress: played },
    kind: "season",
    rounds: roundPoints(t.rounds, t.rows.map((r) => r.memberID)),
  };
}

/** Sesongen (turnering med kvelder): appens Tavla regnet fra svaret, med rundene bak («Alle runder», scorekortene). */
export function seasonStandings(board: Record<string, unknown>): TavlaStandings {
  const comp = board.competition as { season_id: string; club_id: string; name: string; status: string; rules: unknown };
  const season = { id: comp.season_id, club_id: comp.club_id, name: comp.name, status: comp.status, rules: comp.rules };
  return new TavlaStandings(tavlaInput(decodeTavlaData(board), decodeSeasonRow(season)));
}

function safeRules(raw: unknown): Ruleset | null {
  try { return decodeRuleset(raw); } catch { return null; }
}

const NO_PANELS = { extras: [] as TVPayload["extras"], teams: null as TVPayload["teams"] };

/**
 * Panelene for de andre konkurransene (sql/048). Runden er den som går, ellers den siste med konkurranser eller
 * sider. Regnes fra øyeblikksbildet når runden har det, ellers fra dagens data, med regelmotoren som appen.
 */
export function extraPanels(board: Record<string, unknown>, rules: Ruleset | null,
  namesFor: (roundID: UUID) => Map<UUID, string>): Pick<TVPayload, "extras" | "teams"> {
  if (rules === null) return NO_PANELS;
  const comps = list(board, "round_competitions").map(decodeStoredCompetition).filter((c): c is StoredCompetition => c !== null && c.roundID !== null);
  const rawPlayers = list(board, "players");
  if (comps.length === 0 && !rawPlayers.some((p) => (p as { side?: unknown })?.side === 1 || (p as { side?: unknown })?.side === 2)) return NO_PANELS;
  let data: TavlaData;
  try { data = decodeTavlaData({ ...board, events: [] }); } catch { return NO_PANELS; }
  const rawRounds = list(board, "rounds") as Record<string, unknown>[];
  const sidesIn = (id: UUID) => sidesFromRaw(rawPlayers.filter((p) => String((p as { round_id?: string }).round_id ?? "").toLowerCase() === id));
  const candidates = data.rounds.filter((r) => r.status !== "draft" && !isPlayoff(r)
    && (comps.some((c) => c.roundID === r.id && !c.isMain) || sidesIn(r.id).size > 0));
  const round = candidates.filter((r) => r.status === "active").at(-1) ?? candidates.at(-1);
  if (!round) return NO_PANELS;
  const names = namesFor(round.id);
  const snapshot = makeSnapshot(round, {
    roundHoles: data.roundHoles.filter((h) => h.roundID === round.id),
    players: data.players.filter((p) => p.roundID === round.id),
    matches: data.matches.filter((m) => m.roundID === round.id),
    scores: data.scores.filter((x) => x.roundID === round.id),
    course: data.courses.find((c) => c.id === round.courseID) ?? null,
    courseHoles: data.courseHoles.filter((h) => h.courseID === round.courseID),
    rules, names,
  });
  const live = makeRoundFromSnapshot(snapshot);
  const roster = snapshotRoster(snapshot);
  const raw = rawRounds.find((r) => String(r.id).toLowerCase() === round.id) ?? {};
  const frozen = frozenFromRows(snapshotFields(raw), snapshot.players, rules, (m) => snapshotHandicap(snapshot, m, live, roster));
  const name = (id: string) => names.get(id) ?? "Ukjent";
  const extras = competitionBoards({
    competitions: comps.filter((c) => c.roundID === round.id), roundFormat: round.format, frozen,
    live: { round: live, roster, rules }, sides: sidesIn(round.id),
  }).filter((b) => !b.isMain).map((b) => ({
    title: b.name,
    lines: b.supported
      ? b.rows.slice(0, 5).map((r) => ({ name: `${r.rank}. ${r.players.map(name).join(" og ")}`, score: competitionRowText(b, r) }))
      : [{ name: "Ikke støttet ennå", score: "" }],
  }));
  const team = teamMatchResult(live, sidesIn(round.id), roster, frozen?.ruleset ?? rules);
  return {
    extras,
    teams: team ? { title: "Lag mot lag", lines: team.table.map((r) => ({ name: `Side ${r.side}`, score: competitionScoreText(r.points) })) } : null,
  };
}

/** Poengene per runde for radene i tabellen (`ids` i tabellens rekkefølge), fra rundeoversikten. */
export function roundPoints(grid: RoundsGrid, ids: readonly UUID[]): TVPayload["rounds"] {
  if (grid.columns.length === 0) return null;
  const byID = new Map(grid.rows.map((r) => [r.playerID.toLowerCase(), r]));
  return {
    labels: grid.columns.map((c) => c.label),
    ongoing: grid.columns.map((c) => c.isOngoing),
    rows: ids.map((id) => {
      const r = byID.get(id.toLowerCase());
      return r ? { points: r.points, counted: r.counted } : null;
    }),
  };
}

/** Siste kolonne i rundeoversikten: de åtte beste i runden. */
function latestRound(grid: RoundsGrid): TVPayload["latest"] {
  const n = grid.columns.length - 1;
  if (n < 0) return null;
  return {
    title: grid.columns[n].title,
    ongoing: grid.columns[n].isOngoing,
    lines: grid.rows
      .filter((r) => r.points[n] !== null)
      .map((r) => ({ name: r.name, points: r.points[n] as number }))
      .sort((a, b) => b.points - a.points || a.name.localeCompare(b.name, "no"))
      .slice(0, 8),
  };
}

const list = (board: Record<string, unknown>, key: string): unknown[] => (Array.isArray(board[key]) ? (board[key] as unknown[]) : []);

/** Liga, morro og cup (sql/043, tv_competition_data): samme mapping som turneringssiden i appen. */
function competitionPayload(board: Record<string, unknown>): TVPayload {
  const raw = board.competition as Record<string, unknown> & { club_name?: string | null };
  const comp = decodeCompetitionRow(raw);
  const club = raw.club_name ?? null;

  if (comp.kind === "cup") {
    const participants = list(board, "participants").map((x) => decodeCompetitionParticipant(x));
    const profiles = list(board, "profiles").map((x) => decodeProfile(x));
    const roundParticipants = list(board, "round_participants").map((x) => decodeRoundParticipant(x));
    const directory = new PersonDirectory(decodeTavlaData({ ...board, events: [] }).members, roundParticipants, profiles);
    const names = new Map<UUID, string>();
    for (const p of participants) {
      const n = p.memberID !== null ? directory.members.get(p.memberID)?.displayName : p.profileID !== null ? directory.profiles.get(p.profileID)?.displayName : null;
      names.set(p.id, n ?? "Ukjent");
    }
    const cup = new CupStandings(list(board, "cup_matches").map((x) => decodeCompetitionMatch(x)), names);
    const i = cup.rounds.findIndex((r) => r.some((g) => g.winner === null && !g.isBye));
    const at = i < 0 ? cup.rounds.length - 1 : i;
    const games = at < 0 ? [] : cup.rounds[at].filter((g) => !g.isBye);
    const played = cup.champion !== null ? `Vinner: ${cup.champion.name}` : at < 0 ? "Ikke trukket ennå" : cup.roundTitles[at];
    return {
      name: comp.name,
      club,
      played,
      rows: games.map((g) => ({
        place: "",
        name: `${g.a?.name ?? "?"} – ${g.b?.name ?? "?"}`,
        total: g.winner === null ? "" : (g.winner === g.a?.participantID ? g.a?.name : g.b?.name) ?? "",
        detail: g.walkover ? "W.O." : g.result ?? "",
      })),
      latest: null,
      note: null,
      ...NO_PANELS,
      heading: { title: comp.name, rule: null, progress: played },
      kind: "cup",
      rounds: null,
    };
  }

  const { league: l, names } = leagueStandings(board);
  const progress = `${l.roundCount} ${l.roundCount === 1 ? "runde" : "runder"} spilt`;
  const grid = l.roundGrid();
  return {
    name: comp.name,
    club,
    played: `${progress} · ${l.rulesSummary}`,
    rows: l.rows.map((r) => ({ place: l.placeText(r), name: r.name, total: LeagueStandings.points(r.total), detail: l.detail(r) })),
    latest: latestRound(grid),
    note: hiddenHolesNote(board),
    ...extraPanels(board, comp.rules, (id) => names.get(id) ?? new Map()),
    heading: { title: comp.name, rule: l.rulesSummary, progress },
    kind: "league",
    rounds: roundPoints(grid, l.rows.map((r) => r.entrant.id)),
  };
}

/** Liga og morro: appens ligatabell regnet fra svaret, og navnene per runde. */
export function leagueStandings(board: Record<string, unknown>): { league: LeagueStandings; names: Map<UUID, Map<UUID, string>> } {
  const comp = decodeCompetitionRow(board.competition);
  const participants = list(board, "participants").map((x) => decodeCompetitionParticipant(x));
  const profiles = list(board, "profiles").map((x) => decodeProfile(x));
  const roundParticipants = list(board, "round_participants").map((x) => decodeRoundParticipant(x));
  const data = decodeTavlaData({ ...board, events: [] });
  const directory = new PersonDirectory(data.members, roundParticipants, profiles);
  // Navn fra troppen i runden (klubbrunde) eller deltakerne (løs runde), dato fra kvelden/spilledagen.
  const names = new Map<UUID, Map<UUID, string>>();
  for (const x of list(board, "roster")) {
    const r = x as { round_id: string; player_id: string; display_name: string | null };
    const m = names.get(r.round_id.toLowerCase()) ?? new Map<UUID, string>();
    if (r.display_name !== null) m.set(r.player_id.toLowerCase(), r.display_name);
    names.set(r.round_id.toLowerCase(), m);
  }
  const dates = new Map<UUID, string | null>();
  for (const x of list(board, "rounds")) {
    const r = x as { id: string; event_date?: string | null };
    dates.set(r.id.toLowerCase(), r.event_date ?? null);
  }
  const snapshots = data.rounds.map((round) => makeSnapshot(round, {
    roundHoles: data.roundHoles.filter((h) => h.roundID === round.id),
    players: data.players.filter((p) => p.roundID === round.id),
    matches: data.matches.filter((m) => m.roundID === round.id),
    scores: data.scores.filter((s) => s.roundID === round.id),
    sideClaims: data.claims.filter((c) => c.roundID === round.id),
    course: data.courses.find((c) => c.id === round.courseID) ?? null,
    courseHoles: data.courseHoles.filter((h) => h.courseID === round.courseID),
    eventDate: dates.get(round.id) ?? null,
    rules: comp.rules,
    names: names.get(round.id) ?? new Map(),
  }));
  const links = list(board, "links").map((x) => decodeCompetitionRound(x));
  const input = new CompetitionScope(comp, links, participants).input(snapshots, directory);
  return { league: new LeagueStandings(input), names };
}

/** Henter med koden. null: ugyldig, utløpt eller tilbaketrukket kode (P0002). */
export async function fetchTVPayload(code: string, env: TVEnv): Promise<TVPayload | null> {
  if (!env.SUPABASE_URL || !env.SUPABASE_KEY) throw new Error("Workeren mangler SUPABASE_URL eller SUPABASE_KEY.");
  const res = await fetch(`${env.SUPABASE_URL}/rest/v1/rpc/tv_board_data`, {
    method: "POST",
    headers: { apikey: env.SUPABASE_KEY, "Content-Type": "application/json" },
    body: JSON.stringify({ p_code: code }),
  });
  if (!res.ok) {
    // PostgREST svarer 500 (eller 400/404) med koden P0002 når koden er ukjent, utløpt eller trukket tilbake.
    const body = (await res.json().catch(() => ({}))) as { code?: string };
    if (body.code === "P0002") return null;
    throw new Error(`tv_board_data svarte ${res.status}`);
  }
  return buildTVPayload((await res.json()) as Record<string, unknown>);
}

// Utseendet (02.11.2026): samme uttrykk som tavla på TV-en på forsiden (demoTavla i web/admin/src/landing/markup.ts).
// Stilen er den samme som salgssidene bruker, nettstedets (SITE_STYLE: skrifter, farger, høydekurver, .soft, .wordmark)
// og forsidens (LANDING_HEAD_STYLE: .tv med .bar, .ttl, tabellen, rutene og .field). TV_STYLE under gjør bare demoen
// stor nok til en hel skjerm og legger til kortene ved siden av. Høydekurvene er den faste SVG-en fra nettsted.ts:
// ingen bevegelse i bakgrunnen på en skjerm som står på hele kvelden.

/** Måleenheten: 1 % av høyden på en liggende skjerm, mindre når vinduet er smalt. Alle størrelser regnes fra den. */
const TV_STYLE = `
  .tvflate [hidden] { display: none !important; }
  html, body { height: 100%; overflow: hidden; }
  .landing.tvflate { --u: min(1vh, .75vw); --dim: #8FA398; position: fixed; inset: 0; isolation: isolate; overflow: hidden;
    background: var(--night); color: var(--on-dark); font-size: max(14px, calc(2.2 * var(--u))); }
  .tvflate .kurver { opacity: .5; }
  .tvflate::before { content: ""; position: absolute; inset: 0; z-index: -1; pointer-events: none;
    background: radial-gradient(120% 90% at 25% 30%, transparent 35%, rgba(10, 23, 18, .85) 100%); }

  /* hele skjermen er TV-en: uten ramme og fot, og med plass til lange tabeller */
  .landing .tv.vegg { aspect-ratio: auto; height: 100%; background: none; border-radius: 0; padding: 0; box-shadow: none; }
  .landing .tv.vegg .scr { background: none; border-radius: 0; color: var(--on-dark);
    padding: max(16px, calc(3.4 * var(--u))) max(16px, calc(4.4 * var(--u))) max(12px, calc(2.4 * var(--u))); gap: max(8px, calc(1.6 * var(--u))); }
  .landing .tv.vegg .bar { font-size: max(13px, calc(2.1 * var(--u))); gap: 1em; }
  .landing .tv.vegg .bar > span:first-child { min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .tv.vegg .bar .hoyre { display: flex; align-items: baseline; gap: .9em; flex-shrink: 0; }
  .tv.vegg .klokke { font-size: 1.45em; color: var(--on-dark); font-weight: 500; font-variant-numeric: tabular-nums; }
  .landing .tv.vegg .ttl { gap: .2em .45em; }
  .landing .tv.vegg .ttl .loud { font-size: max(32px, calc(7.6 * var(--u))); overflow-wrap: anywhere; }
  .landing .tv.vegg .ttl .soft { font-size: max(18px, calc(3.7 * var(--u))); color: var(--gold); }

  .tv.vegg .innhold { flex: 1; min-height: 0; display: flex; gap: max(14px, calc(3.4 * var(--u))); }
  .tv.vegg .tavle { flex: 1; min-width: 0; display: flex; flex-direction: column; min-height: 0; }
  .tv.vegg .rader { flex: 1; min-height: 0; overflow: hidden; }
  .landing .tv.vegg table { font-size: max(16px, calc(3.4 * var(--u))); border-collapse: collapse; }
  .landing .tv.vegg tbody td { height: max(48px, calc(6.8 * var(--u))); padding: 0; vertical-align: middle; }
  .landing .tv.vegg td.pl { width: 2.4em; padding-right: .5em; font-size: .78em; white-space: nowrap; }
  .landing .tv.vegg td.nm { width: 100%; max-width: 0; }
  .tv.vegg td.nm .n, .tv.vegg td.nm .dt { display: block; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .tv.vegg td.nm .n { line-height: 1.1; }
  .tv.vegg td.nm .dt { font-size: .5em; font-weight: 400; color: var(--dim); margin-top: .3em; }
  .tv.vegg td.nm .dt b { color: var(--gold); font-weight: 600; }
  .landing .tv.vegg td.pts { padding-left: .8em; font-size: 1.12em; white-space: nowrap; }
  .tv.vegg .rdc { white-space: nowrap; }
  .landing .tv.vegg th.r { padding-left: .8em; }
  .landing .tv.vegg .rd { margin-left: 1.2em; }
  .tv.vegg thead .rd { font-size: 1em; }
  .tv.vegg thead .rd i { background: none; padding: 0; }
  .tv.vegg .rd i.na { color: var(--gold); box-shadow: inset 0 0 0 1px rgba(228, 199, 103, .45); }
  .tv.vegg .rd i.tom { opacity: .35; }
  .tv.vegg tr.lead td.pl, .tv.vegg tr.lead .dt { color: var(--dim); }
  .tv.vegg tr.ute td { opacity: .6; }

  /* kortene ved siden av: siste runde, lag mot lag og de andre konkurransene */
  .tv.vegg .siden { width: min(34%, calc(56 * var(--u))); display: flex; flex-direction: column; gap: max(10px, calc(2 * var(--u))); min-height: 0; overflow: hidden; }
  .tv.vegg .kort { background: rgba(255, 255, 255, .04); box-shadow: inset 0 0 0 1px rgba(255, 255, 255, .08); border-radius: max(10px, calc(1.8 * var(--u)));
    padding: max(12px, calc(2.2 * var(--u))) max(14px, calc(2.6 * var(--u))); min-width: 0; }
  .landing .tv.vegg .kort .bar { font-size: max(12px, calc(1.8 * var(--u))); text-transform: uppercase; letter-spacing: .08em; }
  .landing .tv.vegg .kort .soft { display: block; font-size: max(17px, calc(3.2 * var(--u))); color: var(--gold); line-height: 1.1; margin: .2em 0 .35em; overflow-wrap: anywhere; }
  .landing .tv.vegg .kort table { font-size: max(14px, calc(2.6 * var(--u))); }
  .landing .tv.vegg .kort td { height: auto; padding: .36em 0; }
  .landing .tv.vegg .kort td.pl { width: 2em; padding-right: .4em; font-size: .8em; white-space: nowrap; }
  .landing .tv.vegg .kort td.nm { white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  .landing .tv.vegg .kort tr:last-child td { border-bottom: 0; }
  .tv.vegg #extras { display: flex; flex-direction: column; gap: max(10px, calc(2 * var(--u))); }
  .landing .tv.vegg .kort.liten table { font-size: max(13px, calc(2 * var(--u))); }
  .landing .tv.vegg .kort.liten .bar { color: var(--gold); }

  /* nederst: merknaden, sideprikkene og navnet */
  .tv.vegg .fot { display: flex; align-items: center; gap: 1.4em; font-size: max(12px, calc(1.8 * var(--u))); color: var(--dim); min-height: 1.6em; }
  .tv.vegg .fot .note { font-family: var(--serif); font-style: italic; font-size: 1.15em; color: var(--on-dark); min-width: 0; }
  .tv.vegg .prikker { display: flex; gap: .55em; margin: 0 auto; }
  .tv.vegg .prikker i { width: .6em; height: .6em; border-radius: 50%; background: rgba(244, 241, 230, .22); }
  .tv.vegg .prikker i.on { background: var(--gold); }
  .tv.vegg .fot .wordmark { font-size: 1.3em; margin-left: auto; color: var(--on-dark-2); }
  .tv.vegg .prikker + .wordmark { margin-left: 0; }

  .tv.vegg .melding { margin: auto; text-align: center; max-width: 40em; }
  .tv.vegg .melding h1 .loud { font-size: max(30px, calc(6.4 * var(--u))); }
  .tv.vegg .melding p { color: var(--on-dark-2); font-size: 1.2em; margin-top: 1em; }

  /* smalt vindu (stående skjerm, mobil): kortene under tabellen */
  @media (max-aspect-ratio: 1 / 1) {
    .landing.tvflate { --u: min(1vh, 1.6vw); }
    .tv.vegg .innhold { flex-direction: column; }
    .tv.vegg .siden { width: 100%; flex: 0 1 auto; max-height: 42%; }
  }

  /* /tv: koden skrives inn som på nettsidene */
  .kodeside .inn { position: relative; height: 100%; display: flex; flex-direction: column; justify-content: center;
    padding: max(20px, calc(5 * var(--u))) max(20px, calc(7 * var(--u))); max-width: 1400px; margin: 0 auto; }
  .kodeside .inn > .wordmark { position: absolute; top: max(20px, calc(4 * var(--u))); left: max(20px, calc(7 * var(--u))); font-size: max(22px, calc(3 * var(--u))); }
  .kodeside h1 .loud { font-size: max(48px, calc(13 * var(--u))); color: var(--on-dark); }
  .kodeside h1 .soft { display: block; color: var(--gold); font-size: max(30px, calc(7 * var(--u))); line-height: 1.04; margin-top: .1em; }
  .kodeside .ingress { font-size: max(17px, calc(2.8 * var(--u))); color: var(--on-dark-2); max-width: 30em; margin: 1.1em 0 0; }
  .kodeside form { display: flex; flex-wrap: wrap; gap: max(12px, calc(1.6 * var(--u))); align-items: stretch; margin-top: max(24px, calc(4 * var(--u))); }
  .landing.kodeside .field { flex: 0 1 15em; font-size: max(17px, calc(2.8 * var(--u))); }
  .landing.kodeside .field input { height: 3.4em; font-size: 1em; padding: 1.25em 1em .3em; border-radius: .8em; text-transform: uppercase; }
  .landing.kodeside .field label { font-size: 1em; top: 1.05em; left: 1.1em; }
  .landing.kodeside .field input:focus + label, .landing.kodeside .field input:not(:placeholder-shown) + label { top: .5em; font-size: .62em; }
  .kodeside .knapp { min-height: 0; font-size: max(17px, calc(2.8 * var(--u))); padding: .9em 1.8em; border: 0; cursor: pointer; font-family: inherit; }
`;

const TV_HEAD_STYLE = SITE_STYLE + LANDING_HEAD_STYLE + TV_STYLE;

function shell(title: string, body: string, nonce: string, script: string): string {
  return `<!doctype html><html lang="nb"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="robots" content="noindex"><meta name="theme-color" content="#0A1712"><title>${title}</title>${ICON_LINKS}
${SITE_FONTS}<style>${TV_HEAD_STYLE}</style></head><body>${body}
<script nonce="${nonce}">${script}</script></body></html>`;
}

/** /tv: skriv inn koden (for en TV-nettleser uten tastatur er QR-lenken raskest). */
export function tvCodePage(nonce: string): string {
  return shell("TV-visning – Atten", `<div class="landing tvflate kodeside">${topoSVG()}<main class="inn">
<span class="wordmark">Atten<i>.</i></span>
<h1><span class="loud">Atten</span> <span class="soft">på TV</span></h1>
<p class="ingress">Skriv koden fra appen (Tavla → TV-visning → TV-kode).</p>
<form id="f"><div class="field"><input id="k" class="code" maxlength="11" autocomplete="off" autocapitalize="characters" spellcheck="false" autofocus placeholder=" ">
<label for="k">TV-kode</label></div><button class="knapp">Vis</button></form></main></div>`,
    nonce, `document.getElementById("f").addEventListener("submit",e=>{e.preventDefault();
const k=document.getElementById("k").value.replace(/[\\s-]/g,"").toUpperCase(); if(k) location.href="/tv/"+encodeURIComponent(k);});`);
}

/**
 * /tv/KODE: henter /tv/KODE.json hvert 15. sekund, bytter side hvert 10. sekund. Hvor mange rader som får plass,
 * måles på skjermen (radhøyden står i TV_STYLE), og rutene per runde vises så langt bredden rekker.
 */
export function tvBoardPage(code: string, nonce: string): string {
  const script = `
const url = "/tv/${code}.json"; let data = null, page = 0, rowH = 0;
const esc = s => String(s).replace(/[&<>"]/g, c => ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;"}[c]));
const $ = id => document.getElementById(id);
const shown = {};
function set(id, html){ if (shown[id] !== html) { shown[id] = html; $(id).innerHTML = html; } }
function clock(){ $("clock").textContent = new Date().toLocaleTimeString("nb-NO",{hour:"2-digit",minute:"2-digit"}); }
function detail(d){ return d.startsWith("Playoff · ") ? "<b>Playoff</b> · " + esc(d.slice(10)) : esc(d); }
function chipsFit(){
  const g = data.rounds; if (!g || !g.labels.length) return 0;
  const em = parseFloat(getComputedStyle($("rows")).fontSize) * .62;
  const n = Math.floor(($("tavle").clientWidth * .42 - 1.2 * em) / (2.4 * em));
  return n >= 3 ? Math.min(n, g.labels.length) : 0;
}
function chip(g, r, j){
  const p = r.points[j], c = [];
  if (r.counted && !r.counted[j]) c.push("x"); if (g.ongoing[j]) c.push("na"); if (p === null) c.push("tom");
  return "<i" + (c.length ? ' class="' + c.join(" ") + '"' : "") + ">" + (p === null ? "·" : p) + "</i>";
}
function lines(list){
  return "<table><tbody>" + list.map((x,i) => '<tr' + (i === 0 ? ' class="lead"' : "") + '><td class="pl">' + esc(x.n) + '</td><td class="nm">' + esc(x.name)
    + '</td><td class="r pts">' + esc(x.score) + "</td></tr>").join("") + "</tbody></table>";
}
function render(){
  if (!data) return;
  const h = data.heading || { title: data.name, rule: null, progress: data.played };
  $("tittel").textContent = h.title; $("regel").textContent = h.rule || ""; $("regel").hidden = !h.rule;
  $("played").textContent = (data.club ? data.club + " · " : "") + h.progress;
  const l = data.latest;
  $("live").hidden = !(l && l.ongoing);
  const g = data.rounds, n = chipsFit(), from = g ? g.labels.length - n : 0;
  const cup = data.kind === "cup";
  set("thead", "<tr><th></th><th>" + (cup ? "Kamp" : "Spiller") + "</th>"
    + (n ? '<th class="rdc"><span class="rd">' + g.labels.slice(from).map(x => "<i>" + esc(x) + "</i>").join("") + "</span></th>" : "")
    + '<th class="r">' + (cup ? "Vinner" : "Poeng") + "</th></tr>");
  if (!rowH) rowH = window.innerHeight * .075;
  const room = $("rader").clientHeight - $("thead").offsetHeight;
  const per = Math.max(3, Math.floor(room / rowH)), pages = Math.max(1, Math.ceil(data.rows.length / per));
  page = page % pages;
  set("rows", data.rows.slice(page * per, page * per + per).map((r, k) => {
    const i = page * per + k, cr = n && g.rows[i];
    const cls = (r.place.startsWith("1.") ? "lead" : "") + (r.place === "–" ? " ute" : "");
    return '<tr' + (cls.trim() ? ' class="' + cls.trim() + '"' : "") + ' style="animation-delay:' + (k * 60) + 'ms"><td class="pl">' + esc(r.place) + "</td>"
      + '<td class="nm"><span class="n">' + esc(r.name) + "</span>" + (r.detail ? '<span class="dt">' + detail(r.detail) + "</span>" : "") + "</td>"
      + (n ? '<td class="rdc">' + (cr ? '<span class="rd">' + cr.points.slice(from).map((_, j) => chip(g, cr, from + j)).join("") + "</span>" : "") + "</td>" : "")
      + '<td class="r pts">' + esc(r.total) + "</td></tr>";
  }).join(""));
  const tr = $("rows").rows[0];
  if (tr) { const h = Math.max(...Array.from($("rows").rows, x => x.getBoundingClientRect().height));
    if (Math.floor(room / h) !== Math.floor(room / rowH)) { rowH = h; return render(); } rowH = h; }
  set("dots", pages > 1 ? Array.from({length: pages}, (_, i) => '<i class="' + (i === page ? "on" : "") + '"></i>').join("") : "");
  set("latest", l ? '<div class="bar">' + (l.ongoing ? "<b>Pågår nå</b>" : "<span>Siste runde</span>") + '</div><span class="soft">' + esc(l.title) + "</span>"
    + lines(l.lines.map((x, i) => ({ n: (i + 1) + ".", name: x.name, score: x.points }))) : "");
  $("latest").hidden = !l;
  const panels = (data.teams ? [data.teams] : []).concat(data.extras || []);
  set("extras", panels.map(p => '<section class="kort liten"><div class="bar"><span>' + esc(p.title) + "</span></div>"
    + lines(p.lines.map(x => { const m = /^(\\d+\\.) (.*)$/.exec(x.name); return m ? { n: m[1], name: m[2], score: x.score } : { n: "", name: x.name, score: x.score }; })) + "</section>").join(""));
  $("siden").hidden = !l && !panels.length;
  // Kort som ikke får plass helt, vises ikke (heller enn å kuttes nederst).
  const bunn = $("siden").getBoundingClientRect().bottom + 1;
  for (const k of $("extras").children) { k.hidden = false; k.hidden = k.getBoundingClientRect().bottom > bunn; }
  $("note").textContent = data.note || ""; $("note").hidden = !data.note;
}
async function load(){
  try { const r = await fetch(url, {cache:"no-store"});
    if (r.status === 404) { $("scr").innerHTML = '<div class="melding"><h1><span class="loud">Fant ingen TV-visning</span></h1><p>Koden er feil, utløpt eller trukket tilbake. Lag en ny kode i appen.</p></div>'; return; }
    data = await r.json(); render();
  } catch(e) {}
}
clock(); setInterval(clock, 15000); load(); setInterval(load, 15000); setInterval(()=>{ page++; render(); }, 10000);
window.addEventListener("resize", () => { rowH = 0; render(); });`;
  return shell("Tavla på TV – Atten", `<div class="landing tvflate">${topoSVG()}<div class="tv vegg"><div class="scr" id="scr">
<div class="bar"><span id="played">Henter tabellen …</span><span class="hoyre"><b id="live" hidden>Live</b><span class="klokke" id="clock"></span></span></div>
<h1 class="ttl"><span class="loud" id="tittel">Atten</span><span class="soft" id="regel" hidden></span></h1>
<div class="innhold"><div class="tavle" id="tavle"><div class="rader" id="rader"><table><thead id="thead"></thead><tbody id="rows"></tbody></table></div></div>
<div class="siden" id="siden" hidden><section class="kort" id="latest" hidden></section><div id="extras"></div></div></div>
<div class="fot"><span class="note" id="note" hidden></span><span class="prikker" id="dots"></span><span class="wordmark">Atten<i>.</i></span></div>
</div></div></div>`, nonce, script);
}
