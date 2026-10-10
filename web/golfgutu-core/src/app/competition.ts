// Liga, morroturnering og cup slik appen viser dem (DashDash18/Features/Konkurranser/CompetitionScope.swift
// og CompetitionStandings.swift): hvem som er med, hvilke runder som teller, tabellen med tekstene, og
// cuptreet med navn og seeder.

import {
  bracketSizeOf,
  cupBracket,
  cupDecide,
  cupDraw,
  cupMatchState,
  cupSeeded,
  leagueTable,
  nextCupMatch,
  seedPositions,
  type CupBracket,
  type CupDecision,
  type CupEntrant,
  type CupMatchState,
  type CupPairing,
  type CupResult,
  type LeagueRoundResult,
} from "../competitions.ts";
import { DecodeError, obj, optBool, optEnum, optNumber, optObject, optString, reqInt, reqString } from "../decode.ts";
import { norwegianLess, sortedBy } from "../jsmath.ts";
import { makePlayer, type Player } from "../models.ts";
import { competitionRulesOf, decodeRuleset, type CupRules, type CupTie, type LeagueRules, type Ruleset } from "../ruleset.ts";
import { Season } from "../season.ts";
import { makeRoundFromSnapshot, snapshotRoster, type RoundSnapshot } from "./roundgame.ts";
import type { ClubMemberRow, SeasonRow, SeasonStatus, UUID } from "./rows.ts";
import { claimFromRow, makeRoundsGrid, playingHandicaps, sortSnapshots, type RoundsGrid, type TavlaInput } from "./tavla.ts";

// MARK: Radene

export type CompetitionKind = "season" | "league" | "cup" | "fun" | "game";
export type CompetitionEntry = "club" | "listed" | "open";

/** En konkurranse (`competitions`). */
export interface CompetitionRow {
  id: UUID;
  kind: CompetitionKind;
  name: string;
  clubID: UUID | null;
  ownerID: UUID | null;
  seasonID: UUID | null;
  status: SeasonStatus;
  entry: CompetitionEntry;
  rules: Ruleset;
  startsOn: string | null;
  endsOn: string | null;
  isMain: boolean;
}

/** Påmeldt i en konkurranse (`competition_participants`). */
export interface CompetitionParticipantRow {
  id: UUID;
  competitionID: UUID;
  memberID: UUID | null;
  profileID: UUID | null;
  status: "active" | "withdrawn";
}

/** En runde som teller i en konkurranse (`competition_rounds`). */
export interface CompetitionRoundRow {
  competitionID: UUID;
  roundID: UUID;
}

/** Deltaker i en løs runde (`round_participants`): en profil, eller en gjest. */
export interface RoundParticipantRow {
  id: UUID;
  roundID: UUID;
  profileID: UUID | null;
  displayName: string;
  handicapIndex: number | null;
}

/** Én person per innlogging (`profiles`). */
export interface ProfileRow {
  id: UUID;
  displayName: string | null;
  handicapIndex: number | null;
}

/** En cupkamp (`competition_matches`). Spillerne er påmeldte. */
export interface CompetitionMatchRow {
  id: UUID;
  competitionID: UUID;
  roundNo: number;
  slot: number;
  playerA: UUID | null;
  playerB: UUID | null;
  winner: UUID | null;
  walkover: boolean;
  result: string | null;
  roundID: UUID | null;
}

const lower = (s: string | null) => s?.toLowerCase() ?? null;

export function decodeCompetitionRow(x: unknown, path = "$"): CompetitionRow {
  const o = obj(x, path);
  const kind = optEnum(o, "kind", ["season", "league", "cup", "fun", "game"] as const, path);
  const status = optEnum(o, "status", ["planned", "active", "finished"] as const, path);
  const entry = optEnum(o, "entry", ["club", "listed", "open"] as const, path);
  const rules = optObject(o, "rules", path);
  if (kind === null || status === null || entry === null || rules === null) throw new DecodeError(path, "mangler kind, status, entry eller rules");
  return {
    id: reqString(o, "id", path).toLowerCase(),
    kind,
    name: reqString(o, "name", path),
    clubID: lower(optString(o, "club_id", path)),
    ownerID: lower(optString(o, "owner_id", path)),
    seasonID: lower(optString(o, "season_id", path)),
    status,
    entry,
    rules: decodeRuleset(rules, `${path}.rules`),
    startsOn: optString(o, "starts_on", path),
    endsOn: optString(o, "ends_on", path),
    isMain: optBool(o, "is_main", path) ?? false,
  };
}

export function decodeCompetitionParticipant(x: unknown, path = "$"): CompetitionParticipantRow {
  const o = obj(x, path);
  return {
    id: reqString(o, "id", path).toLowerCase(),
    competitionID: reqString(o, "competition_id", path).toLowerCase(),
    memberID: lower(optString(o, "member_id", path)),
    profileID: lower(optString(o, "profile_id", path)),
    status: optEnum(o, "status", ["active", "withdrawn"] as const, path) ?? "active",
  };
}

export function decodeCompetitionRound(x: unknown, path = "$"): CompetitionRoundRow {
  const o = obj(x, path);
  return { competitionID: reqString(o, "competition_id", path).toLowerCase(), roundID: reqString(o, "round_id", path).toLowerCase() };
}

export function decodeRoundParticipant(x: unknown, path = "$"): RoundParticipantRow {
  const o = obj(x, path);
  return {
    id: reqString(o, "id", path).toLowerCase(),
    roundID: reqString(o, "round_id", path).toLowerCase(),
    profileID: lower(optString(o, "profile_id", path)),
    displayName: reqString(o, "display_name", path),
    handicapIndex: optNumber(o, "handicap_index", path),
  };
}

export function decodeProfile(x: unknown, path = "$"): ProfileRow {
  const o = obj(x, path);
  return { id: reqString(o, "id", path).toLowerCase(), displayName: optString(o, "display_name", path), handicapIndex: optNumber(o, "handicap_index", path) };
}

export function decodeCompetitionMatch(x: unknown, path = "$"): CompetitionMatchRow {
  const o = obj(x, path);
  return {
    id: reqString(o, "id", path).toLowerCase(),
    competitionID: reqString(o, "competition_id", path).toLowerCase(),
    roundNo: reqInt(o, "round_no", path),
    slot: reqInt(o, "slot", path),
    playerA: lower(optString(o, "player_a", path)),
    playerB: lower(optString(o, "player_b", path)),
    winner: lower(optString(o, "winner", path)),
    walkover: optBool(o, "walkover", path) ?? false,
    result: optString(o, "result", path),
    roundID: lower(optString(o, "round_id", path)),
  };
}

// MARK: Personene

/** Personen bak en spiller i en runde, slik en konkurranse teller hen. */
export type Entrant = { kind: "member" | "profile" | "guest"; id: UUID };

/** Nøkkel for likhet (`Hashable`). */
export function entrantKey(e: Entrant): string {
  return `${e.kind}:${e.id}`;
}

/** Oppslag fra spiller-id-en i en runde til personen bak. */
export class PersonDirectory {
  readonly members = new Map<UUID, ClubMemberRow>();
  readonly participants = new Map<UUID, RoundParticipantRow>();
  readonly profiles = new Map<UUID, ProfileRow>();

  constructor(members: readonly ClubMemberRow[] = [], participants: readonly RoundParticipantRow[] = [], profiles: readonly ProfileRow[] = []) {
    for (const m of members) if (!this.members.has(m.id)) this.members.set(m.id, m);
    for (const p of participants) if (!this.participants.has(p.id)) this.participants.set(p.id, p);
    for (const p of profiles) if (!this.profiles.has(p.id)) this.profiles.set(p.id, p);
  }

  /** Medlemmet i klubben for en innlogging, om det finnes. */
  member(clubID: UUID, profile: UUID): ClubMemberRow | null {
    let best: ClubMemberRow | null = null;
    for (const m of this.members.values()) {
      if (m.clubID !== clubID || m.userID !== profile) continue;
      if (best === null || m.id < best.id) best = m;
    }
    return best;
  }

  /** Personen bak spilleren, sett fra en konkurranse som eies av `clubID` (eller ingen klubb). */
  entrant(playerID: UUID, clubID: UUID | null): Entrant {
    const member = this.members.get(playerID);
    if (member !== undefined) {
      if (member.clubID === clubID) return { kind: "member", id: member.id };
      if (member.userID !== null) return { kind: "profile", id: member.userID };
      return { kind: "guest", id: member.id };
    }
    const participant = this.participants.get(playerID);
    if (participant !== undefined) {
      if (participant.profileID === null) return { kind: "guest", id: participant.id };
      if (clubID !== null) {
        const m = this.member(clubID, participant.profileID);
        if (m !== null) return { kind: "member", id: m.id };
      }
      return { kind: "profile", id: participant.profileID };
    }
    // Ukjent: hører til konkurransens klubb, ellers bare runden.
    return clubID === null ? { kind: "guest", id: playerID } : { kind: "member", id: playerID };
  }

  /** Navnet å vise: troppen, profilen, deltakeren, ellers navnet runden hadde. */
  name(e: Entrant, fallback: string | null): string {
    switch (e.kind) {
      case "member":
        return this.members.get(e.id)?.displayName ?? fallback ?? "";
      case "profile":
        return this.profiles.get(e.id)?.displayName ?? fallback ?? "";
      case "guest":
        return this.participants.get(e.id)?.displayName ?? this.members.get(e.id)?.displayName ?? fallback ?? "";
    }
  }
}

// MARK: Hva konkurransen teller

/** Det en konkurranses tabell regnes av. */
export interface CompetitionInput {
  competition: CompetitionRow;
  entrants: Entrant[];
  /** Spillerne i tabellen, i norsk navnerekkefølge. `Player.id` = `Entrant.id`. */
  roster: Player[];
  /** Tellende runder i tidsrekkefølge, med spiller-id-er etter personen bak. */
  rounds: RoundSnapshot[];
}

/** Hvilke runder og hvem en konkurranse teller. */
export class CompetitionScope {
  readonly competition: CompetitionRow;
  readonly roundIDs: Set<UUID>;
  readonly participants: CompetitionParticipantRow[];

  constructor(competition: CompetitionRow, links: readonly CompetitionRoundRow[], participants: readonly CompetitionParticipantRow[] = []) {
    this.competition = competition;
    this.roundIDs = new Set(links.filter((l) => l.competitionID === competition.id).map((l) => l.roundID));
    this.participants = participants.filter((p) => p.competitionID === competition.id && p.status === "active");
  }

  /** Teller runden? Den må være koblet til konkurransen og startet. */
  counts(round: { id: UUID; status: string }): boolean {
    return this.roundIDs.has(round.id) && round.status !== "draft";
  }

  /** Rundene som teller blant de hentede, i Tavlas rekkefølge: dato, så rundenummer. */
  countedRounds(candidates: readonly RoundSnapshot[]): RoundSnapshot[] {
    return sortSnapshots(candidates.filter((s) => this.counts(s.round)));
  }

  /** Hvem som står i tabellen, i norsk navnerekkefølge. */
  entrants(counted: readonly RoundSnapshot[], directory: PersonDirectory): Entrant[] {
    const club = this.competition.clubID;
    const played = counted.flatMap((s) => s.players.map((p) => directory.entrant(p.memberID, club)));
    let chosen: Entrant[];
    switch (this.competition.entry) {
      case "club": {
        const active = [...directory.members.values()].filter((m) => m.clubID === club && m.status === "active").map((m): Entrant => ({ kind: "member", id: m.id }));
        chosen = [...active, ...played];
        break;
      }
      case "listed":
        chosen = [];
        for (const p of this.participants) {
          if (p.memberID !== null) { chosen.push({ kind: "member", id: p.memberID }); continue; }
          if (p.profileID === null) continue;
          const m = club !== null ? directory.member(club, p.profileID) : null;
          chosen.push(m !== null ? { kind: "member", id: m.id } : { kind: "profile", id: p.profileID });
        }
        break;
      case "open":
        chosen = played;
        break;
    }
    const seen = new Set<string>();
    const unique = chosen.filter((e) => (seen.has(entrantKey(e)) ? false : (seen.add(entrantKey(e)), true)));
    const names = new Map<string, string | null>();
    for (const s of counted) {
      for (const p of s.players) {
        const k = entrantKey(directory.entrant(p.memberID, club));
        if (!names.has(k)) names.set(k, s.names.get(p.memberID) ?? null);
      }
    }
    return sortedBy(unique, (a, b) => norwegianLess(directory.name(a, names.get(entrantKey(a)) ?? null), directory.name(b, names.get(entrantKey(b)) ?? null)));
  }

  /** Runden med spillerne gitt id etter personen bak, så samme person har samme id i alle runder. */
  rekeyed(snapshot: RoundSnapshot, directory: PersonDirectory): RoundSnapshot {
    const club = this.competition.clubID;
    const key = (id: UUID) => directory.entrant(id, club).id;
    const names = new Map<UUID, string>();
    for (const p of snapshot.players) {
      const e = directory.entrant(p.memberID, club);
      if (!names.has(e.id)) names.set(e.id, directory.name(e, snapshot.names.get(p.memberID) ?? null));
    }
    return {
      ...snapshot,
      players: snapshot.players.map((p) => ({ ...p, memberID: key(p.memberID) })),
      scores: snapshot.scores.map((h) => ({ ...h, memberID: key(h.memberID) })),
      matches: snapshot.matches.map((m) => ({
        ...m,
        playerA: m.playerA !== null ? key(m.playerA) : null,
        playerB: m.playerB !== null ? key(m.playerB) : null,
        playerC: m.playerC !== null ? key(m.playerC) : null,
      })),
      sideClaims: snapshot.sideClaims.map((c) => ({ ...c, memberID: key(c.memberID) })),
      names,
      rules: this.competition.rules,
    };
  }

  /** Grunnlaget for Tavla når konkurransen eies av en klubb og teller klubbens tropp (som jakkeracet). */
  tavlaInput(members: readonly ClubMemberRow[], candidates: readonly RoundSnapshot[]): TavlaInput | null {
    const c = this.competition;
    if (c.clubID === null || c.entry !== "club") return null;
    const season: SeasonRow = { id: c.seasonID ?? c.id, clubID: c.clubID, name: c.name, status: c.status, rules: c.rules };
    const rounds = this.countedRounds(candidates).map((s) => ({ ...s, rules: c.rules }));
    return { season, members: members.filter((m) => m.clubID === c.clubID), rounds };
  }

  /** Grunnlaget for en hvilken som helst konkurranse. */
  input(candidates: readonly RoundSnapshot[], directory: PersonDirectory): CompetitionInput {
    const counted = this.countedRounds(candidates);
    const entrants = this.entrants(counted, directory);
    const rounds = counted.map((s) => this.rekeyed(s, directory));
    const names = new Map<UUID, string>();
    for (const r of rounds) for (const [k, v] of r.names) if (!names.has(k)) names.set(k, v);
    const roster = entrants.map((e) => makePlayer(e.id, directory.name(e, names.get(e.id) ?? null), this.handicap(e, directory), e.kind === "member" ? directory.members.get(e.id)?.seedGroup ?? null : null));
    return { competition: this.competition, entrants, roster, rounds };
  }

  private handicap(e: Entrant, directory: PersonDirectory): number | null {
    switch (e.kind) {
      case "member":
        return directory.members.get(e.id)?.handicapIndex ?? null;
      case "profile":
        return directory.profiles.get(e.id)?.handicapIndex ?? null;
      case "guest":
        return directory.participants.get(e.id)?.handicapIndex ?? directory.members.get(e.id)?.handicapIndex ?? null;
    }
  }
}

/** Sesongen for en konkurranse: hver runde med handicapet som ble frosset i den. */
export function competitionSeason(input: CompetitionInput): Season {
  return new Season(
    input.roster,
    input.rounds.map(makeRoundFromSnapshot),
    input.rounds.flatMap((r) => r.sideClaims).map(claimFromRow),
    input.competition.rules,
    playingHandicaps(input.rounds),
  );
}

// MARK: Liga og morroturnering

/** «2026-10-01» → «1. okt». */
export function competitionShortDate(date: string): string {
  const parts = date.split("-").filter((p) => /^[+-]?[0-9]+$/.test(p)).map(Number);
  const months = ["jan", "feb", "mar", "apr", "mai", "jun", "jul", "aug", "sep", "okt", "nov", "des"];
  if (parts.length !== 3 || parts[1] < 1 || parts[1] > 12) return date;
  return `${parts[2]}. ${months[parts[1] - 1]}`;
}

const trimSpaces = (s: string) => s.replace(/^[\p{Zs}\t]+|[\p{Zs}\t]+$/gu, "");

export interface LeagueStandingsRow {
  entrant: Entrant;
  name: string;
  place: number;
  total: number;
  played: number;
  wins: number;
  bestRound: number | null;
  stableford: number;
  results: LeagueRoundResult[];
  isMe: boolean;
}

/** Liga og morroturnering: poeng per runde og beste N, etter konkurransens regler. */
export class LeagueStandings {
  readonly competition: CompetitionRow;
  readonly rules: LeagueRules;
  readonly rows: LeagueStandingsRow[];
  /** Rundene som teller: id → «1. okt · Pebble Beach». */
  readonly roundTitles: Map<UUID, string>;
  readonly roundCount: number;
  readonly snapshots: RoundSnapshot[];
  readonly season: Season;

  constructor(input: CompetitionInput, me: readonly Entrant[] = []) {
    this.competition = input.competition;
    const cr = competitionRulesOf(input.competition.rules);
    this.rules = input.competition.kind === "fun" ? cr.fun : cr.league;
    const season = competitionSeason(input);
    this.season = season;
    this.snapshots = input.rounds;
    const rounds = input.rounds.map((s, i) => ({ id: s.round.id, stableford: season.roundPoints(i) }));
    this.roundCount = rounds.length;
    this.roundTitles = new Map();
    for (const s of input.rounds) if (!this.roundTitles.has(s.round.id)) this.roundTitles.set(s.round.id, LeagueStandings.title(s));
    const byKey = new Map<string, { entrant: Entrant; player: Player }>();
    input.roster.forEach((p, i) => {
      if (!byKey.has(p.id)) byKey.set(p.id, { entrant: input.entrants[i], player: p });
    });
    const meKeys = new Set(me.map(entrantKey));
    this.rows = [];
    for (const r of leagueTable(input.roster.map((p) => p.id), rounds, this.rules)) {
      const hit = byKey.get(r.playerID);
      if (hit === undefined || hit.entrant === undefined) continue;
      this.rows.push({
        entrant: hit.entrant, name: hit.player.name, place: r.place, total: r.total, played: r.played, wins: r.wins,
        bestRound: r.bestRound, stableford: r.stableford, results: r.results, isMe: meKeys.has(entrantKey(hit.entrant)),
      });
    }
  }

  /** Minst én runde er spilt av en i tabellen. */
  get hasResults(): boolean {
    return this.rows.some((r) => r.played > 0);
  }

  placeText(row: LeagueStandingsRow): string {
    return this.hasResults ? `${row.place}.` : "–";
  }

  /** Poeng uten unødvendige desimaler: «11», «6,5», «6,33». */
  static points(x: number): string {
    const away = (y: number) => {
      const t = Math.trunc(y);
      return Math.abs(y - t) >= 0.5 ? t + Math.sign(y) : t;
    };
    const rounded = away(x * 100) / 100;
    if (rounded === away(rounded)) return String(Math.trunc(rounded) || 0);
    return rounded.toFixed(2).replace(/0+$/, "").replace(".", ",");
  }

  detail(row: LeagueStandingsRow): string {
    if (row.played <= 0) return "Ingen runder ennå";
    const parts = [row.played === 1 ? "1 runde" : `${row.played} runder`];
    if (this.rules.bestRounds !== null && row.played > this.rules.bestRounds) parts.push(`beste ${this.rules.bestRounds} teller`);
    if (row.wins > 0) parts.push(row.wins === 1 ? "1 seier" : `${row.wins} seire`);
    parts.push(`${row.stableford} stableford`);
    return parts.join(" · ");
  }

  /** «Plassering 10–8–6 … · + 1 for å spille · alle runder teller». */
  get rulesSummary(): string {
    const r = this.rules;
    const parts: string[] = [];
    if (r.scoring === "placement") {
      const list = r.placementPoints.slice(0, 3).map(LeagueStandings.points).join("–");
      parts.push(`Plassering ${list}${r.placementPoints.length > 3 ? " …" : ""}`);
    } else {
      parts.push("Stablefordpoeng");
    }
    if (r.participationPoints > 0) parts.push(`+ ${LeagueStandings.points(r.participationPoints)} for å spille`);
    parts.push(r.bestRounds !== null ? `beste ${r.bestRounds} runder teller` : "alle runder teller");
    return parts.join(" · ");
  }

  static title(s: RoundSnapshot): string {
    const date = s.eventDate !== null ? competitionShortDate(s.eventDate) : null;
    const own = s.round.name !== null ? trimSpaces(s.round.name) : null;
    const name = own !== null && own !== "" ? own : s.course?.name ?? null;
    return [date, name].filter((x): x is string => x !== null).join(" · ");
  }

  /** «Alle runder» for ligaen: tabellens rekkefølge, og hvilke runder som teller (beste N). */
  roundGrid(): RoundsGrid {
    return makeRoundsGrid(this.snapshots, this.season, (i) => LeagueStandings.title(this.snapshots[i]), this.rows.map((row) => ({
      playerID: row.entrant.id,
      name: row.name,
      place: this.placeText(row),
      isMe: row.isMe,
      counted: this.rules.bestRounds === null ? null : new Set(row.results.filter((r) => r.counted).map((r) => r.roundID)),
    })));
  }
}

// MARK: Cup

export interface CupSide {
  participantID: UUID;
  name: string;
  seed: number | null;
  isMe: boolean;
}

export interface CupGame {
  round: number;
  slot: number;
  a: CupSide | null;
  b: CupSide | null;
  winner: UUID | null;
  isBye: boolean;
  walkover: boolean;
  result: string | null;
  state: CupMatchState;
}

/** «1. runde», «Kvartfinale», «Semifinale», «Finale». */
export function cupRoundTitle(round: number, count: number): string {
  switch (count - round) {
    case 0:
      return "Finale";
    case 1:
      return "Semifinale";
    case 2:
      return "Kvartfinale";
    default:
      return `${round}. runde`;
  }
}

/** Navnet på regelen ved likt. */
export function cupTieText(t: CupTie): string {
  switch (t) {
    case "suddenDeath":
      return "Sudden death";
    case "countback":
      return "Siste hull som ikke var delt";
    case "higherSeed":
      return "Beste seed går videre";
    case "lowerHandicap":
      return "Lavest handicap går videre";
  }
}

/** «3&2», «2 opp», «Likt, avgjort: …», «Likt etter siste hull», «1 opp etter 5». */
export function cupResultText(d: CupDecision): string | null {
  switch (d.kind) {
    case "won":
      if (d.tie !== null) return `Likt, avgjort: ${cupTieText(d.tie).toLowerCase()}`;
      return d.remaining > 0 ? `${d.up}&${d.remaining}` : `${d.up} opp`;
    case "tied":
      return "Likt etter siste hull";
    case "inProgress":
      return d.up === 0 ? `Likt etter ${d.played}` : `${Math.abs(d.up)} ${d.up > 0 ? "opp" : "ned"} etter ${d.played}`;
    case "notStarted":
      return null;
  }
}

/** Cupen: treet fra trekningen og resultatene, med navn og «din neste kamp». */
export class CupStandings {
  readonly rounds: CupGame[][];
  readonly champion: CupSide | null;
  readonly myNext: CupGame | null;
  readonly bracket: CupBracket;

  /** `names`: påmeldt → navn. `me`: påmeldingene dine. */
  constructor(matches: readonly CompetitionMatchRow[], names: ReadonlyMap<UUID, string>, me: ReadonlySet<UUID> = new Set()) {
    const first = [...matches].filter((m) => m.roundNo === 1).sort((a, b) => a.slot - b.slot);
    const draw: CupPairing[] = first.filter((m) => m.playerA !== null).map((m) => ({ slot: m.slot, a: m.playerA!, b: m.playerB }));
    const results: CupResult[] = matches
      .filter((m) => m.winner !== null && !(m.roundNo === 1 && m.playerB === null))
      .map((m) => ({ round: m.roundNo, slot: m.slot, winner: m.winner!, walkover: m.walkover }));
    const bracket = cupBracket(draw, results);
    this.bracket = bracket;

    // Seedene følger plassene i første runde.
    const positions = seedPositions(bracketSizeOf(bracket));
    const seeds = new Map<string, number>();
    for (const p of draw) {
      if (!(p.slot * 2 + 1 < positions.length)) continue;
      const x = Math.min(positions[p.slot * 2], positions[p.slot * 2 + 1]);
      const y = Math.max(positions[p.slot * 2], positions[p.slot * 2 + 1]);
      seeds.set(p.a, x);
      if (p.b !== null) seeds.set(p.b, y);
    }
    const texts = new Map<string, string | null>();
    for (const m of matches) {
      const k = `${m.roundNo}:${m.slot}`;
      if (!texts.has(k)) texts.set(k, m.result);
    }
    const side = (id: string | null): CupSide | null =>
      id === null ? null : { participantID: id, name: names.get(id) ?? "Ukjent", seed: seeds.get(id) ?? null, isMe: me.has(id) };
    this.rounds = bracket.rounds.map((round) => round.map((m) => ({
      round: m.round, slot: m.slot, a: side(m.a), b: side(m.b), winner: m.winner, isBye: m.isBye, walkover: m.walkover,
      result: texts.get(`${m.round}:${m.slot}`) ?? null, state: cupMatchState(m),
    })));
    this.champion = side(bracket.champion);
    let next = null;
    for (const id of [...me].sort()) {
      next = nextCupMatch(bracket, id);
      if (next !== null) break;
    }
    this.myNext = next !== null ? this.rounds[next.round - 1][next.slot] : null;
  }

  get isDrawn(): boolean {
    return this.rounds.length > 0;
  }

  get roundTitles(): string[] {
    return this.rounds.map((_, i) => cupRoundTitle(i + 1, this.rounds.length));
  }

  /** Første runde for trekningen: de aktive påmeldte seedet etter cupens regel. */
  static pairings(participants: readonly CompetitionParticipantRow[], names: ReadonlyMap<UUID, string>, handicaps: ReadonlyMap<UUID, number>,
    ranks: ReadonlyMap<UUID, number>, rules: CupRules, seed: bigint | number): CupPairing[] {
    const entrants: CupEntrant[] = participants.filter((p) => p.status === "active").map((p) => ({
      id: p.id, name: names.get(p.id) ?? "", handicap: handicaps.get(p.id) ?? null, rank: ranks.get(p.id) ?? null,
    }));
    return cupDraw(cupSeeded(entrants, rules, seed));
  }

  /** Forslaget til resultat fra den siste tellende runden begge spilte. `null` når de ikke har spilt sammen. */
  static suggestion(game: CupGame, input: CompetitionInput, entrantOf: (participant: UUID) => Entrant | null): { roundID: UUID; decision: CupDecision } | null {
    if (game.a === null || game.b === null) return null;
    const ea = entrantOf(game.a.participantID);
    const eb = entrantOf(game.b.participantID);
    if (ea === null || eb === null) return null;
    const seeds = new Map<string, number>();
    if (game.a.seed !== null) seeds.set(ea.id, game.a.seed);
    if (game.b.seed !== null) seeds.set(eb.id, game.b.seed);
    for (const snapshot of [...input.rounds].reverse()) {
      const ids = new Set(snapshot.players.map((p) => p.memberID));
      if (!ids.has(ea.id) || !ids.has(eb.id)) continue;
      const decision = cupDecide(ea.id, eb.id, makeRoundFromSnapshot(snapshot), snapshotRoster(snapshot), input.competition.rules, seeds);
      return { roundID: snapshot.round.id, decision };
    }
    return null;
  }
}
