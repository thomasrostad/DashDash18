// Tabellene for web-admin, regnet med regelmotoren i TypeScript (web/golfgutu-core) på samme måte som
// appen: Tavla for serien (TavlaStandings), liga og morro (CompetitionScope + LeagueStandings) og cupen
// (CupStandings). Rene funksjoner uten nettverk, så de kan testes med fixturene til golfgutu-core.

import {
  CompetitionScope,
  CupStandings,
  decodeClubMember,
  decodeCompetitionMatch,
  decodeCompetitionParticipant,
  decodeCompetitionRound,
  decodeCompetitionRow,
  decodeCourseHoleRecord,
  decodeCourseRow,
  decodeEvent,
  decodeHoleScoreRow,
  decodeProfile,
  decodeRoundHoleRow,
  decodeRoundMatchRow,
  decodeRoundParticipant,
  decodeRoundPlayerRow,
  decodeRoundRow,
  decodeSeasonRow,
  decodeSideClaimRow,
  decodeTavlaData,
  dayMany,
  dayTitle,
  GOLFGUTU,
  LeagueStandings,
  makeSnapshot,
  PersonDirectory,
  rulesetDay,
  tavlaInput,
  TavlaStandings,
  tavlaToJSON,
  type ClubMemberRow,
  type CompetitionInput,
  type CompetitionParticipantRow,
  type CompetitionRow,
  type CupGame,
  type Entrant,
  type RoundsGrid,
  type RoundSnapshot,
  type Ruleset,
  type SeasonRow,
} from "../../../golfgutu-core/src/index.ts";
import { todayISO } from "../text.ts";

/** En rad i tabellen slik appen viser den (`DDRankRow`): plass, navn, poeng og linja under. */
export interface TableRow {
  id: string;
  placeText: string;
  name: string;
  totalText: string;
  detail: string;
  isMe: boolean;
  /** Tallene bak, til eksporten. */
  numbers: Record<string, number | null>;
}

/** Serie, liga eller morro: tabellen, «Alle runder» og rundene bak (til scorekortet). */
export interface TableView {
  kind: "table";
  title: string;
  /** Linja under tabellen («Plassering 10–8–6 … · alle runder teller», «3 av 7 kvelder spilt»). */
  summary: string;
  rows: TableRow[];
  /** Overskriftene for `numbers` i eksporten, i rekkefølge. */
  numberColumns: { key: string; label: string }[];
  grid: RoundsGrid;
  snapshots: RoundSnapshot[];
}

export interface CupView {
  kind: "cup";
  title: string;
  rounds: CupGame[][];
  roundTitles: string[];
  champion: string | null;
}

export type StandingsView = TableView | CupView;

// MARK: Serien (Tavla)

/** Serien: svaret fra `tavla_data` og sesongraden → tabellen som Tavla i appen. `me`: medlems-id-en din. */
export function seasonView(tavlaData: unknown, seasonRow: unknown, me: string | null): TableView {
  const t = new TavlaStandings(tavlaInput(decodeTavlaData(tavlaData), decodeSeasonRow(seasonRow)), me);
  const j = tavlaToJSON(t);
  const day = rulesetDay(t.rules);
  const played = `${j.eveningsPlayed} av ${j.eveningsTotal} ${dayMany(day)} med poeng`;
  const numberColumns = j.countsStableford
    ? [{ key: "total", label: "Poeng" }, { key: "roundPoints", label: "Rundepoeng" }, { key: "side", label: "Sidepremier" },
       { key: "played", label: "Runder" }, { key: "stableford", label: "Stableford" }, { key: "evenings", label: dayTitle(day) + "er" }]
    : [{ key: "total", label: "Poeng" }, { key: "duel", label: "Duell" }, { key: "side", label: "Sidepremier" },
       { key: "matches", label: "Matcher" }, { key: "holes", label: "Hull" }, { key: "stableford", label: "Stableford" },
       { key: "evenings", label: dayTitle(day) + "er" }];
  return {
    kind: "table",
    title: j.seasonName,
    summary: played,
    rows: j.rows.map((r) => ({
      id: r.memberID, placeText: r.placeText, name: r.name, totalText: r.totalText, detail: r.detail, isMe: r.isMe,
      numbers: { total: r.total, duel: r.duel, side: r.side, matches: r.matches, holes: r.holes, stableford: r.stableford,
        evenings: r.evenings, roundPoints: r.roundPoints, played: r.played },
    })),
    numberColumns,
    grid: j.rounds,
    snapshots: t.snapshots,
  };
}

// MARK: Liga, morro og cup (CompetitionQueries.detail)

/** `round_roster`: spillerne i en runde med navn og profil. */
export interface RoundRosterRow {
  round_id: string;
  player_id: string;
  club_id: string | null;
  display_name: string | null;
  profile_id: string | null;
  is_guest?: boolean | null;
}

/** Alt som hentes for én liga, cup eller morroturnering, rått fra databasen. */
export interface CompetitionRaw {
  competition: unknown;
  participants: unknown[];
  links: unknown[];
  /** De koblede rundene som er i gang eller låst (med `started_at` for løse runder). */
  rounds: unknown[];
  roundHoles: unknown[];
  players: unknown[];
  matches: unknown[];
  scores: unknown[];
  claims: unknown[];
  courses: unknown[];
  courseHoles: unknown[];
  /** Kveldene rundene hører til. */
  events: unknown[];
  /** Troppen i konkurransens klubb (alle statuser). */
  clubMembers: unknown[];
  /** Troppene i klubbene rundene hører til (navnene i runden). */
  roundMembers: unknown[];
  /** Sesongene kveldene hører til, og de aktive sesongene i rundenes klubber (regelsettet per runde). */
  seasons: unknown[];
  roster: RoundRosterRow[];
  roundParticipants: unknown[];
  profiles: unknown[];
  /** Cupkampene. */
  cupMatches: unknown[];
}

export interface CompetitionData {
  competition: CompetitionRow;
  participants: CompetitionParticipantRow[];
  scope: CompetitionScope;
  directory: PersonDirectory;
  input: CompetitionInput;
  snapshots: RoundSnapshot[];
}

const lower = (s: string | null | undefined) => (s ? s.toLowerCase() : null);

/** `LooseRoundInfo.name`: navnet som er skrevet inn, ellers «Spiller». */
function looseName(text: string | null): string {
  const t = (text ?? "").trim();
  return t === "" ? "Spiller" : t;
}

/** `CompetitionQueries.rosterMembers`: spillerne i klubbrundene som medlemmer, med navn og profil. */
export function rosterMembers(roster: readonly RoundRosterRow[]): ClubMemberRow[] {
  return roster.filter((r) => r.club_id).map((r) => ({
    id: r.player_id.toLowerCase(), clubID: r.club_id!.toLowerCase(), userID: lower(r.profile_id), displayName: r.display_name ?? "",
    handicapIndex: null, seedGroup: null, isOrganizer: false, isTreasurer: false, status: "archived", avatarPath: null,
  }));
}

/**
 * Rundene som `RoundSnapshot`, som `RundeQueries.snapshot`: en klubbrunde får navn fra troppen, datoen fra
 * kvelden og regelsettet til kveldens sesong (ellers klubbens aktive, ellers Golfgutu-oppsettet). En løs runde
 * får navn fra `round_roster`, dagen den startet (Oslo) og Golfgutu-oppsettet.
 */
export function competitionSnapshots(raw: CompetitionRaw): RoundSnapshot[] {
  const at = (key: string, i: number) => `$.${key}[${i}]`;
  const roundHoles = raw.roundHoles.map((x, i) => decodeRoundHoleRow(x, at("roundHoles", i)));
  const players = raw.players.map((x, i) => decodeRoundPlayerRow(x, at("players", i)));
  const matches = raw.matches.map((x, i) => decodeRoundMatchRow(x, at("matches", i)));
  const scores = raw.scores.map((x, i) => decodeHoleScoreRow(x, at("scores", i)));
  const claims = raw.claims.map((x, i) => decodeSideClaimRow(x, at("claims", i)));
  const courses = raw.courses.map((x, i) => decodeCourseRow(x, at("courses", i)));
  const courseHoles = raw.courseHoles.map((x, i) => decodeCourseHoleRecord(x, at("courseHoles", i)));
  const events = raw.events.map((x, i) => decodeEvent(x, at("events", i)));
  const roundMembers = raw.roundMembers.map((x, i) => decodeClubMember(x, at("roundMembers", i)));
  const seasons: SeasonRow[] = raw.seasons.map((x, i) => decodeSeasonRow(x, at("seasons", i)));

  const rulesFor = (clubID: string, seasonID: string | null): Ruleset => {
    if (seasonID !== null) {
      const s = seasons.find((x) => x.id === seasonID);
      if (s) return s.rules;
    }
    return seasons.find((x) => x.clubID === clubID && x.status === "active")?.rules ?? GOLFGUTU;
  };

  return raw.rounds.map((x, i) => {
    const round = decodeRoundRow(x, at("rounds", i));
    const startedAt = (x as { started_at?: string | null }).started_at ?? null;
    const base = {
      roundHoles: roundHoles.filter((h) => h.roundID === round.id),
      players: players.filter((p) => p.roundID === round.id),
      matches: matches.filter((m) => m.roundID === round.id),
      scores: scores.filter((s) => s.roundID === round.id),
      sideClaims: claims.filter((c) => c.roundID === round.id),
      course: round.courseID !== null ? courses.find((c) => c.id === round.courseID) ?? null : null,
      courseHoles: round.courseID !== null ? courseHoles.filter((h) => h.courseID === round.courseID) : [],
    };
    if (round.clubID === null || round.eventID === null) {
      const names = new Map<string, string>();
      for (const r of raw.roster) {
        if (r.round_id.toLowerCase() !== round.id) continue;
        const id = r.player_id.toLowerCase();
        if (!names.has(id)) names.set(id, looseName(r.display_name));
      }
      const day = startedAt !== null && !Number.isNaN(Date.parse(startedAt)) ? todayISO(new Date(startedAt)) : null;
      return makeSnapshot(round, { ...base, names, eventDate: day, rules: GOLFGUTU });
    }
    const names = new Map<string, string>();
    for (const m of roundMembers) if (m.clubID === round.clubID && !names.has(m.id)) names.set(m.id, m.displayName);
    const event = events.find((e) => e.id === round.eventID) ?? null;
    return makeSnapshot(round, { ...base, names, eventDate: event?.eventDate ?? null, rules: rulesFor(round.clubID, event?.seasonID ?? null) });
  });
}

/** `CompetitionQueries.detail`: personene bak spillerne, de påmeldte og det tabellen regnes av. */
export function competitionData(raw: CompetitionRaw): CompetitionData {
  const competition = decodeCompetitionRow(raw.competition, "$.competition");
  const participants = raw.participants.map((x, i) => decodeCompetitionParticipant(x, `$.participants[${i}]`));
  const links = raw.links.map((x, i) => decodeCompetitionRound(x, `$.links[${i}]`));
  const members = raw.clubMembers.map((x, i) => decodeClubMember(x, `$.clubMembers[${i}]`));
  const directory = new PersonDirectory(
    [...members, ...rosterMembers(raw.roster)],
    raw.roundParticipants.map((x, i) => decodeRoundParticipant(x, `$.roundParticipants[${i}]`)),
    raw.profiles.map((x, i) => decodeProfile(x, `$.profiles[${i}]`)),
  );
  const scope = new CompetitionScope(competition, links, participants);
  const snapshots = competitionSnapshots(raw);
  return {
    competition,
    participants: participants.filter((p) => p.competitionID === competition.id),
    scope,
    directory,
    input: scope.input(snapshots, directory),
    snapshots,
  };
}

/** `CompetitionScope.entrant(for:directory:)`: personen bak en påmelding. */
export function participantEntrant(d: CompetitionData, p: CompetitionParticipantRow): Entrant | null {
  if (p.memberID !== null) return { kind: "member", id: p.memberID };
  if (p.profileID === null) return null;
  const club = d.competition.clubID;
  const m = club !== null ? d.directory.member(club, p.profileID) : null;
  return m !== null ? { kind: "member", id: m.id } : { kind: "profile", id: p.profileID };
}

/** Den som ser på: medlemmet i klubben og profilen (`CompetitionAccess.myEntrants`). */
export interface Viewer {
  memberID: string | null;
  profileID: string | null;
}

function myEntrants(v: Viewer): Entrant[] {
  const out: Entrant[] = [];
  if (v.memberID) out.push({ kind: "member", id: v.memberID.toLowerCase() });
  if (v.profileID) out.push({ kind: "profile", id: v.profileID.toLowerCase() });
  return out;
}

/** Liga og morro: tabellen og «Alle runder» som i appen (`LeagueStandings`). */
export function leagueView(d: CompetitionData, viewer: Viewer): TableView {
  const l = new LeagueStandings(d.input, myEntrants(viewer));
  return {
    kind: "table",
    title: d.competition.name,
    summary: l.rulesSummary,
    rows: l.rows.map((r) => ({
      id: `${r.entrant.kind}:${r.entrant.id}`, placeText: l.placeText(r), name: r.name, totalText: LeagueStandings.points(r.total),
      detail: l.detail(r), isMe: r.isMe,
      numbers: { total: r.total, played: r.played, wins: r.wins, bestRound: r.bestRound, stableford: r.stableford },
    })),
    numberColumns: [{ key: "total", label: "Poeng" }, { key: "played", label: "Runder" }, { key: "wins", label: "Seire" },
      { key: "bestRound", label: "Beste runde" }, { key: "stableford", label: "Stableford" }],
    grid: l.roundGrid(),
    snapshots: l.snapshots,
  };
}

/** Cupen: treet med navn og seeder (`CompetitionsModel.content`). */
export function cupView(d: CompetitionData, matches: readonly unknown[], viewer: Viewer): CupView {
  const rows = matches.map((x, i) => decodeCompetitionMatch(x, `$.cupMatches[${i}]`));
  const names = new Map<string, string>();
  for (const p of d.participants) {
    if (names.has(p.id)) continue;
    const e = participantEntrant(d, p);
    names.set(p.id, e !== null ? d.directory.name(e, null) : "");
  }
  const memberID = viewer.memberID?.toLowerCase() ?? null;
  const profileID = viewer.profileID?.toLowerCase() ?? null;
  const mine = new Set(d.participants.filter((p) => (memberID !== null && p.memberID === memberID) || (profileID !== null && p.profileID === profileID)).map((p) => p.id));
  const cup = new CupStandings(rows, names, mine);
  return { kind: "cup", title: d.competition.name, rounds: cup.rounds, roundTitles: cup.roundTitles, champion: cup.champion?.name ?? null };
}

/** Teksten under en cupkamp, som `CupGameCard.footer`. */
export function cupFooter(game: CupGame): string {
  if (game.walkover) return "Walkover";
  if (game.result !== null) return game.result;
  switch (game.state) {
    case "waiting":
      return "Venter";
    case "ready":
      return "Klar";
    case "decided":
      return game.isBye ? "" : "Avgjort";
  }
}
