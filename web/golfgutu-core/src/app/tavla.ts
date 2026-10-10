// Tavla for én sesong (DashDash18/Features/Tavla/TavlaData.swift, TavlaStandings.swift og
// TavlaRounds.swift): fra svaret til RPC-en `tavla_data` til tabellens rader, med samme tall og tekster
// som appen, og «Alle runder» (poeng, slag og mot par per runde).

import { courseHoles, numberOfHoles } from "../course.ts";
import { capitalized, dayCount, dayMany, dayThe, dayTheMany, type DayTerm } from "../dayterm.ts";
import { effectiveHandicap } from "../handicap.ts";
import { norwegianLess, sortedBy } from "../jsmath.ts";
import { makePlayer, type Player, type SideClaim } from "../models.ts";
import { rulesetDay, type CountingUnit, type Ruleset } from "../ruleset.ts";
import { netStrokes } from "../scoring.ts";
import { eveningCount, formatPoints, Season } from "../season.ts";
import { makeRoundFromSnapshot, makeSnapshot, snapshotHandicap, snapshotRoster, type RoundSnapshot } from "./roundgame.ts";
import {
  decodeSeasonRow,
  decodeTavlaData,
  sideClaimTimestamp,
  type ClubMemberRow,
  type SeasonRow,
  type SeasonStatus,
  type SideClaimRow,
  type TavlaData,
  type UUID,
} from "./rows.ts";

/** Alt Tavla henter for én sesong, slik databasen leverer det. */
export interface TavlaInput {
  season: SeasonRow;
  /** Hele troppen, alle statuser. */
  members: ClubMemberRow[];
  /** Sesongens runder med alt under. */
  rounds: RoundSnapshot[];
}

/** `TavlaData.input(season:)`: rundene som `RoundSnapshot`, med samme mapping som Kveld. */
export function tavlaInput(data: TavlaData, season: SeasonRow): TavlaInput {
  const names = new Map<UUID, string>();
  for (const m of data.members) if (!names.has(m.id)) names.set(m.id, m.displayName);
  const dates = new Map<UUID, string>();
  for (const e of data.events) if (!dates.has(e.id)) dates.set(e.id, e.eventDate);
  const rounds = data.rounds.map((round) => makeSnapshot(round, {
    roundHoles: data.roundHoles.filter((h) => h.roundID === round.id),
    players: data.players.filter((p) => p.roundID === round.id),
    matches: data.matches.filter((m) => m.roundID === round.id),
    scores: data.scores.filter((s) => s.roundID === round.id),
    sideClaims: data.claims.filter((c) => c.roundID === round.id),
    course: data.courses.find((c) => c.id === round.courseID) ?? null,
    courseHoles: data.courseHoles.filter((h) => h.courseID === round.courseID),
    eventDate: round.eventID !== null ? dates.get(round.eventID) ?? null : null,
    rules: season.rules,
    names,
  }));
  return { season, members: data.members, rounds };
}

/** En rad i tabellen. */
export interface TavlaRow {
  memberID: UUID;
  name: string;
  /** 1, 2, 3 … i tabellens rekkefølge. */
  place: number;
  /** Duell (eller stablefordpoeng) + sidepremier, avrundet etter regelsettet. */
  total: number;
  duel: number;
  side: number;
  /** Tellende matcher. */
  matches: number;
  /** Hulldifferansen i de tellende matchene. */
  holes: number;
  /** Stablefordsummen etter regelsettet. */
  stableford: number;
  /** Kvelder spilleren har poeng i. */
  evenings: number;
  isMe: boolean;
  /** Tellende stablefordpoeng (vektet) når tabellen teller stableford, ellers 0. */
  roundPoints: number;
  /** Spilte runder når tabellen teller stableford (spilte matcher ellers). */
  played: number;
}

/** Norske navn på enhetene «beste N» telles i (`RuleNames.nouns`). */
export function unitNouns(unit: CountingUnit, term: DayTerm = "evening"): { plural: string; definite: string; definitePlural: string } {
  switch (unit) {
    case "match":
      return { plural: "matcher", definite: "matchen", definitePlural: "matchene" };
    case "round":
      return { plural: "runder", definite: "runden", definitePlural: "rundene" };
    case "evening":
      return { plural: dayMany(term), definite: dayThe(term), definitePlural: dayTheMany(term) };
  }
}

/** `SideClaimRow` → regelmotorens innmelding. */
export function claimFromRow(row: SideClaimRow): SideClaim {
  return { id: row.id, kind: row.kind, playerId: row.memberID, roundId: row.roundID, meters: row.meters, holeIndex: row.holeIndex, ts: sideClaimTimestamp(row) };
}

/** Rundens frosne handicap per spiller, runde-id → spiller-id → slag (som Kveld). */
export function playingHandicaps(snapshots: readonly RoundSnapshot[]): Map<string, Map<string, number>> {
  const out = new Map<string, Map<string, number>>();
  for (const s of snapshots) {
    const round = makeRoundFromSnapshot(s);
    const roster = snapshotRoster(s);
    const m = new Map<string, number>();
    for (const p of s.players) if (!m.has(p.memberID)) m.set(p.memberID, snapshotHandicap(s, p.memberID, round, roster));
    out.set(s.round.id, m);
  }
  return out;
}

/** Rundene i Tavlas rekkefølge: dato, så rundenummer. */
export function sortSnapshots(snapshots: readonly RoundSnapshot[]): RoundSnapshot[] {
  return sortedBy(snapshots, (a, b) => {
    const da = a.eventDate ?? "";
    const db = b.eventDate ?? "";
    return da !== db ? da < db : a.round.roundNo < b.round.roundNo;
  });
}

/**
 * Tavla for én sesong: tabellen, regnet av regelmotoren etter sesongens regelsett. Samme rader, tall og
 * tekster som `TavlaStandings` i appen.
 */
export class TavlaStandings {
  readonly seasonName: string;
  readonly status: SeasonStatus;
  readonly rules: Ruleset;
  readonly rows: TavlaRow[];
  /** Kvelder med poeng (to runder samme dato er én kveld). */
  readonly eveningsPlayed: number;
  readonly me: UUID | null;
  /** Rundene som teller, i tidsrekkefølge (samme som i `season`). */
  readonly snapshots: RoundSnapshot[];
  readonly season: Season;
  readonly claims: SideClaim[];

  constructor(input: TavlaInput, me: UUID | null = null) {
    this.me = me?.toLowerCase() ?? null;
    this.seasonName = input.season.name;
    this.status = input.season.status;
    this.rules = input.season.rules;

    const snapshots = sortSnapshots(input.rounds.filter((s) => s.round.status !== "draft"));
    this.snapshots = snapshots;
    const rounds = snapshots.map(makeRoundFromSnapshot);
    this.claims = snapshots.flatMap((s) => s.sideClaims).map(claimFromRow);

    // Troppen: aktive medlemmer, pluss alle som har spilt en runde i sesongen.
    const playedIDs = new Set(snapshots.flatMap((s) => s.players.map((p) => p.memberID)));
    const roster: Player[] = sortedBy(
      input.members.filter((m) => m.status === "active" || playedIDs.has(m.id)),
      (a, b) => norwegianLess(a.displayName, b.displayName),
    ).map((m) => makePlayer(m.id, m.displayName, m.handicapIndex, m.seedGroup));

    // Hver runde regnes med handicapet som ble frosset i den.
    const season = new Season(roster, rounds, this.claims, input.season.rules, playingHandicaps(snapshots));
    this.season = season;

    const withPoints = rounds.filter((_, i) => season.roundPoints(i).size > 0);
    this.eveningsPlayed = eveningCount(withPoints);

    this.rows = season.jacketBoard().map((r, i) => {
      const played = rounds.filter((_, n) => season.roundPoints(n).has(r.player.id));
      return {
        memberID: r.player.id,
        name: r.player.name,
        place: i + 1,
        total: r.total,
        duel: r.duel,
        side: r.side,
        matches: r.matches,
        holes: r.holes,
        stableford: r.stableford,
        evenings: eveningCount(played),
        isMe: r.player.id === this.me,
        roundPoints: r.roundPoints,
        played: r.played,
      };
    });
  }

  /** Kvelder i sesongen, fra regelsettet. */
  get eveningsTotal(): number {
    return this.rules.evenings;
  }

  get isEmpty(): boolean {
    return this.rows.length === 0;
  }

  /** Teller tabellen stableford? Da finnes ingen dueller, matcher eller hull. */
  get countsStableford(): boolean {
    return this.rules.table.pointsSource === "stableford";
  }

  /** Minst én kveld har gitt poeng. Før det er tabellen bare troppen i navnerekkefølge. */
  get hasResults(): boolean {
    return this.eveningsPlayed > 0 && this.rows.length > 0;
  }

  /** «+3 hull · 112 stableford · 4 kvelder», eller med stableford «6 kvelder · beste 5 teller». */
  detail(row: TavlaRow): string {
    const day = rulesetDay(this.rules);
    const evenings = dayCount(day, row.evenings);
    if (!this.countsStableford) {
      const holes = row.holes > 0 ? `+${row.holes}` : `${row.holes}`;
      return `${holes} hull · ${row.stableford} stableford · ${evenings}`;
    }
    const counting = this.rules.table.counting;
    if (counting.best === null) return evenings;
    const noun = unitNouns(counting.unit, day);
    return counting.best === 1 ? `${evenings} · beste ${noun.definite} teller` : `${evenings} · beste ${counting.best} teller`;
  }

  /** Kolonnene i «Runde for runde» på profilen. */
  get roundColumns(): string {
    return this.countsStableford ? "plass · stableford" : "plass · duell · stableford";
  }

  /** Hva poengene kommer fra: «4,5 fra 5 dueller · 1 fra sidepremier · +3 hull». `null` uten poeng. */
  basis(row: TavlaRow): string | null {
    const parts: string[] = [];
    if (this.countsStableford) {
      if (!(row.played > 0 || row.side > 0)) return null;
      if (row.played > 0) parts.push(`${this.points(row.roundPoints)} fra ${row.played === 1 ? "én runde" : `${row.played} runder`}`);
      if (row.side > 0) parts.push(`${this.points(row.side)} fra sidepremier`);
      return parts.join(" · ");
    }
    if (!(row.matches > 0 || row.side > 0)) return null;
    if (row.matches > 0) parts.push(`${this.points(row.duel)} fra ${row.matches === 1 ? "én duell" : `${row.matches} dueller`}`);
    if (row.side > 0) parts.push(`${this.points(row.side)} fra sidepremier`);
    if (row.matches > 0) parts.push(`${row.holes > 0 ? "+" : ""}${row.holes} hull`);
    return parts.join(" · ");
  }

  /** Plassen slik tabellen viser den: «3.», eller «–» før første kveld. */
  placeText(row: TavlaRow): string {
    return this.hasResults ? `${row.place}.` : "–";
  }

  row(member: UUID): TavlaRow | null {
    return this.rows.find((r) => r.memberID === member.toLowerCase()) ?? null;
  }

  /** `fmtPoeng` med regelsettets avrunding. */
  points(x: number): string {
    return formatPoints(x, this.rules);
  }

  /** Rundens navn: det lagrede navnet, ellers «Kveld N» (og «· runde M» når kvelden har flere). */
  roundTitle(index: number): string {
    const s = this.snapshots[index];
    const name = s.round.name?.replace(/^[\p{Zs}\t]+|[\p{Zs}\t]+$/gu, "") ?? "";
    if (name !== "") return name;
    const number = this.season.roundNumber(s.eventDate);
    const sameEvening = this.snapshots.filter((x) => x.eventDate === s.eventDate).length > 1;
    const day = capitalized(dayOneOf(this.rules));
    return sameEvening ? `${day} ${number} · runde ${s.round.roundNo}` : `${day} ${number}`;
  }

  /** Netto birdie eller bedre per hull gjennom sesongen. */
  birdies(member: UUID): number {
    const pid = member.toLowerCase();
    const player = this.season.players.find((p) => p.id === pid) ?? null;
    let count = 0;
    for (const round of this.season.rounds) {
      const scores = round.holeScores.get(pid);
      if (scores === undefined || scores.size === 0) continue;
      const course = courseHoles(round);
      const hcp = effectiveHandicap(player, round, this.season.players, this.rules);
      for (const [hole, gross] of scores) {
        if (!(hole >= 0 && hole < course.length)) continue;
        const h = course[hole];
        if (netStrokes(gross, hcp, h.strokeIndex, numberOfHoles(round)) - h.par <= -1) count++;
      }
    }
    return count;
  }

  /** Spillerens lengste innmeldte drive i sesongen. */
  longestDrive(member: UUID): number | null {
    const pid = member.toLowerCase();
    const m = this.claims.filter((c) => c.kind === "drive" && c.playerId === pid).map((c) => c.meters);
    return m.length > 0 ? Math.max(...m) : null;
  }

  /** «Alle runder» for sesongen. */
  roundGrid(): RoundsGrid {
    return makeRoundsGrid(this.snapshots, this.season, (i) => this.roundTitle(i),
      this.rows.map((r) => ({ playerID: r.memberID, name: r.name, place: `${r.place}.`, isMe: r.isMe, counted: null })));
  }
}

function dayOneOf(r: Ruleset): string {
  return rulesetDay(r) === "evening" ? "kveld" : "spilledag";
}

// MARK: Alle runder (TavlaRounds.swift)

export interface RoundsGridColumn {
  roundID: UUID;
  /** «1», «2», … i rekkefølge. */
  label: string;
  /** «8.10». */
  date: string | null;
  title: string;
  isOngoing: boolean;
}

export interface RoundsGridRow {
  playerID: UUID;
  name: string;
  place: string;
  isMe: boolean;
  /** Stablefordpoeng per kolonne, `null` når spilleren ikke var med. */
  points: (number | null)[];
  /** Slag per kolonne (bare førte hull). */
  strokes: (number | null)[];
  /** Slag i forhold til par på de førte hullene, per kolonne. */
  toPar: (number | null)[];
  /** Teller runden i tabellen? (Liga og morro med «beste N».) `null`: alle teller. */
  counted: boolean[] | null;
  pointsTotal: number;
  strokesTotal: number;
  toParTotal: number;
}

export interface RoundsGrid {
  columns: RoundsGridColumn[];
  rows: RoundsGridRow[];
  /** Beste poeng per kolonne. `null` uten verdier. */
  bestPoints: (number | null)[];
  /** Laveste slag per kolonne. `null` uten verdier. */
  bestStrokes: (number | null)[];
}

/** «+3», «E», «−2» (PGA-skrivemåten). */
export function toParText(x: number): string {
  return x === 0 ? "E" : x > 0 ? `+${x}` : `−${-x}`;
}

/** «2026-10-08» → «8.10». */
export function shortDate(date: string): string {
  const parts = date.split("-").filter((p) => p !== "");
  if (parts.length !== 3) return date;
  const d = swiftInt(parts[2]);
  const m = swiftInt(parts[1]);
  if (d === null || m === null) return date;
  return `${d}.${m}`;
}

/** Swifts `Int(String)`: valgfritt fortegn og sifre, ellers `null`. */
function swiftInt(s: string): number | null {
  return /^[+-]?[0-9]+$/.test(s) ? Number(s) : null;
}

const sum = (xs: (number | null)[]) => xs.reduce<number>((s, x) => s + (x ?? 0), 0);

/** Bygger rutenettet fra rundene (samme rekkefølge som `season`), poengene per runde og tabellens rader. */
export function makeRoundsGrid(
  snapshots: readonly RoundSnapshot[],
  season: Season,
  title: (index: number) => string,
  rows: readonly { playerID: UUID; name: string; place: string; isMe: boolean; counted: ReadonlySet<UUID> | null }[],
): RoundsGrid {
  const order = sortedBy(snapshots.map((_, i) => i), (a, b) => {
    const sa = snapshots[a], sb = snapshots[b];
    if ((sa.eventDate ?? "") !== (sb.eventDate ?? "")) return (sa.eventDate ?? "") < (sb.eventDate ?? "");
    return sa.round.roundNo < sb.round.roundNo;
  });
  const columns: RoundsGridColumn[] = order.map((i, n) => {
    const s = snapshots[i];
    return { roundID: s.round.id, label: `${n + 1}`, date: s.eventDate !== null ? shortDate(s.eventDate) : null, title: title(i), isOngoing: s.round.status === "active" };
  });
  const gridRows: RoundsGridRow[] = rows.map((row) => {
    const pid = row.playerID;
    const strokes: (number | null)[] = [];
    const toPar: (number | null)[] = [];
    for (const i of order) {
      const round = season.rounds[i];
      const scores = round.holeScores.get(pid);
      if (scores === undefined || scores.size === 0) {
        strokes.push(null);
        toPar.push(null);
      } else {
        const holes = courseHoles(round);
        let par = 0;
        let total = 0;
        for (const [h, g] of scores) {
          par += h >= 0 && h < holes.length ? holes[h].par : 0;
          total += g;
        }
        strokes.push(total);
        toPar.push(total - par);
      }
    }
    const points = order.map((i) => season.roundPoints(i).get(pid) ?? null);
    return {
      playerID: pid,
      name: row.name,
      place: row.place,
      isMe: row.isMe,
      points,
      strokes,
      toPar,
      counted: row.counted !== null ? order.map((i) => row.counted!.has(snapshots[i].round.id)) : null,
      pointsTotal: sum(points),
      strokesTotal: sum(strokes),
      toParTotal: sum(toPar),
    };
  });
  const best = (pick: (r: RoundsGridRow) => (number | null)[], f: (xs: number[]) => number) =>
    columns.map((_, n) => {
      const xs = gridRows.map((r) => pick(r)[n]).filter((x): x is number => x !== null);
      return xs.length > 0 ? f(xs) : null;
    });
  return {
    columns,
    rows: gridRows,
    bestPoints: best((r) => r.points, (xs) => Math.max(...xs)),
    bestStrokes: best((r) => r.strokes, (xs) => Math.min(...xs)),
  };
}

// MARK: Tavla som JSON (for en server eller nettside)

/** En rad med tekstene appen viser. */
export interface TavlaRowJSON extends TavlaRow {
  placeText: string;
  totalText: string;
  duelText: string;
  sideText: string;
  detail: string;
  basis: string | null;
}

export interface TavlaJSON {
  seasonName: string;
  status: SeasonStatus;
  countsStableford: boolean;
  hasResults: boolean;
  eveningsPlayed: number;
  eveningsTotal: number;
  roundColumns: string;
  rows: TavlaRowJSON[];
  rounds: RoundsGrid;
}

/** Tabellen og «Alle runder» som ren JSON, med tekstene appen viser. */
export function tavlaToJSON(t: TavlaStandings): TavlaJSON {
  return {
    seasonName: t.seasonName,
    status: t.status,
    countsStableford: t.countsStableford,
    hasResults: t.hasResults,
    eveningsPlayed: t.eveningsPlayed,
    eveningsTotal: t.eveningsTotal,
    roundColumns: t.roundColumns,
    rows: t.rows.map((r) => ({
      ...r,
      placeText: t.placeText(r),
      totalText: t.points(r.total),
      duelText: t.points(r.duel),
      sideText: t.points(r.side),
      detail: t.detail(r),
      basis: t.basis(r),
    })),
    rounds: t.roundGrid(),
  };
}

/**
 * Hele veien i ett kall: svaret fra `tavla_data` (JSON) og sesongraden (`seasons`: id, club_id, name,
 * status, rules) → tabellen som JSON. `me`: medlems-id-en til den som ser på (valgfri).
 */
export function standingsFromTavlaData(tavlaDataJSON: unknown, seasonRowJSON: unknown, me: string | null = null): TavlaJSON {
  const data = decodeTavlaData(tavlaDataJSON);
  const season = decodeSeasonRow(seasonRowJSON);
  return tavlaToJSON(new TavlaStandings(tavlaInput(data, season), me));
}
