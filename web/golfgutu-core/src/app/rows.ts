// Radene fra databasen slik appen leser dem (DashDash18/Data/Rows.swift og FoundationRows.swift), med
// kolonnenavnene fra Postgres (snake_case). UUID-er holdes som tekst med små bokstaver; appen bruker
// `UUID.uuidString` (store bokstaver), men rekkefølgen og likheten er den samme.

import {
  DecodeError,
  obj,
  optArray,
  optBool,
  optEnum,
  optInt,
  optNumber,
  optObject,
  optString,
  reqBool,
  reqInt,
  reqNumber,
  reqString,
  type JSONObject,
} from "../decode.ts";
import { decodeRuleset, type Ruleset } from "../ruleset.ts";

/** UUID som tekst med små bokstaver (Swift `UUID` er lik uansett store eller små bokstaver). */
export type UUID = string;

function uuid(o: JSONObject, key: string, path: string): UUID {
  return reqString(o, key, path).toLowerCase();
}

function optUUID(o: JSONObject, key: string, path: string): UUID | null {
  return optString(o, key, path)?.toLowerCase() ?? null;
}

function list<T>(o: JSONObject, key: string, path: string, f: (x: unknown, path: string) => T): T[] {
  return (optArray(o, key, path) ?? []).map((x, i) => f(x, `${path}.${key}[${i}]`));
}

export type MemberStatus = "active" | "pending" | "archived";
export type SeasonStatus = "planned" | "active" | "finished";
export type RoundStatus = "draft" | "active" | "locked";

export interface ClubMemberRow {
  id: UUID;
  clubID: UUID;
  userID: UUID | null;
  displayName: string;
  handicapIndex: number | null;
  seedGroup: number | null;
  isOrganizer: boolean;
  isTreasurer: boolean;
  status: MemberStatus;
  avatarPath: string | null;
}

export interface SeasonRow {
  id: UUID;
  clubID: UUID;
  name: string;
  status: SeasonStatus;
  /** Regelsettet. Felt som mangler, får Golfgutu-verdien. */
  rules: Ruleset;
}

export interface EventRow {
  id: UUID;
  clubID: UUID;
  seasonID: UUID | null;
  /** `YYYY-MM-DD`. */
  eventDate: string;
  startTime: string | null;
  venue: string | null;
  note: string | null;
  competitionID: UUID | null;
}

export interface CourseRow {
  id: UUID;
  clubID: UUID | null;
  name: string;
  externalName: string | null;
  courseRating: number | null;
  slopeRating: number | null;
  inUse: boolean;
}

export interface CourseHoleRecord {
  courseID: UUID;
  holeNumber: number;
  par: number;
  strokeIndex: number | null;
  lengthM: number | null;
}

export interface RoundRow {
  id: UUID;
  clubID: UUID | null;
  eventID: UUID | null;
  courseID: UUID | null;
  roundNo: number;
  name: string | null;
  status: RoundStatus;
  holeCount: number;
  /** 1, eller 10 for «siste ni» på en 18-hullsbane. */
  firstHole: number;
  teeTime: string | null;
  /** Id fra konkurranseform-katalogen. */
  format: string;
  handicapAllowance: number;
  externalHandicap: boolean;
  weight: number;
  ldEnabled: boolean;
  ldHoleIndex: number | null;
  kpEnabled: boolean;
  kpHoleIndex: number | null;
  /** `common`, `net_par` eller `zero`. */
  cutRule: string | null;
  cutAfter: number | null;
  venue: string | null;
  teeID: UUID | null;
  teeName: string | null;
  courseRating: number | null;
  slopeRating: number | null;
  teePar: number | null;
  /** Runden teller i tabellen (sql/047). Uten kolonnen: `true`. */
  counts: boolean;
  /** Poengtabellen runden peker på (`table.pointsTables`), eller `null` (sql/047). */
  pointsTable: string | null;
  /** Antall hull til slutt som skjules til runden er låst («skjul de tre siste»: 3). Uten kolonnen: 0. */
  hideLastHoles: number;
  /** `normal` eller `playoff` (sql/047). Uten kolonnen: `normal`. */
  kind: RoundKind;
  /** Turneringen playoffen avgjør (bare når `kind` er `playoff`). */
  playoffFor: UUID | null;
  /** Playoff-hullene i rekkefølge (rundens 0-baserte hull, kan gjentas). Score for nummer i har `hole_index` i. */
  playoffHoles: number[] | null;
}

/** En vanlig runde eller en playoff om førsteplassen (sql/047). */
export type RoundKind = "normal" | "playoff";

/** Er runden en playoff? Den teller aldri og står ikke i lister over vanlige runder. */
export function isPlayoff(round: { kind?: RoundKind | string | null }): boolean {
  return round.kind === "playoff";
}

/** Overstyring av ett hull for én runde. `holeIndex` er rundens 0-baserte hull. */
export interface RoundHoleRow {
  roundID: UUID;
  holeIndex: number;
  par: number | null;
  strokeIndex: number | null;
  lengthM: number | null;
}

/** Deltaker i runden med frosset handicap, bås, markør og lag. */
export interface RoundPlayerRow {
  roundID: UUID;
  memberID: UUID;
  clubID: UUID | null;
  handicapIndex: number | null;
  seedGroup: number | null;
  playingHandicap: number | null;
  bayNo: number | null;
  isMarker: boolean;
  teamNo: number | null;
}

export interface RoundMatchRow {
  roundID: UUID;
  matchNo: number;
  playerA: UUID | null;
  playerB: UUID | null;
  playerC: UUID | null;
  teamA: number | null;
  teamB: number | null;
  /** `a`, `b`, `halved` eller null (regnes fra hullene). */
  result: string | null;
}

/** Brutto slag. Ingen rad = hullet er ikke ført. */
export interface HoleScoreRow {
  roundID: UUID;
  memberID: UUID;
  holeIndex: number;
  strokes: number;
}

export type SideClaimKindRow = "drive" | "kp";

export interface SideClaimRow {
  id: UUID;
  roundID: UUID;
  memberID: UUID;
  kind: SideClaimKindRow;
  meters: number;
  holeIndex: number | null;
  /** `created_at` slik Postgres gir den, eller null. */
  createdAt: string | null;
}

/** `created_at` som regelmotorens `ts`: ISO 8601 i UTC med millisekunder (som appens `timestamp`). */
export function sideClaimTimestamp(row: SideClaimRow): string | null {
  if (row.createdAt === null) return null;
  const t = Date.parse(row.createdAt);
  return Number.isNaN(t) ? null : new Date(t).toISOString();
}

// MARK: JSON inn

export function decodeClubMember(x: unknown, path = "$"): ClubMemberRow {
  const o = obj(x, path);
  return {
    id: uuid(o, "id", path),
    clubID: uuid(o, "club_id", path),
    userID: optUUID(o, "user_id", path),
    displayName: reqString(o, "display_name", path),
    handicapIndex: optNumber(o, "handicap_index", path),
    seedGroup: optInt(o, "seed_group", path),
    isOrganizer: optBool(o, "is_organizer", path) ?? false,
    isTreasurer: optBool(o, "is_treasurer", path) ?? false,
    status: optEnum(o, "status", ["active", "pending", "archived"] as const, path) ?? "active",
    avatarPath: optString(o, "avatar_path", path),
  };
}

export function decodeSeasonRow(x: unknown, path = "$"): SeasonRow {
  const o = obj(x, path);
  const rules = optObject(o, "rules", path);
  if (rules === null) throw new DecodeError(`${path}.rules`, "mangler");
  const status = optEnum(o, "status", ["planned", "active", "finished"] as const, path);
  if (status === null) throw new DecodeError(`${path}.status`, "mangler");
  return { id: uuid(o, "id", path), clubID: uuid(o, "club_id", path), name: reqString(o, "name", path), status, rules: decodeRuleset(rules, `${path}.rules`) };
}

export function decodeEvent(x: unknown, path = "$"): EventRow {
  const o = obj(x, path);
  return {
    id: uuid(o, "id", path),
    clubID: uuid(o, "club_id", path),
    seasonID: optUUID(o, "season_id", path),
    eventDate: reqString(o, "event_date", path),
    startTime: optString(o, "start_time", path),
    venue: optString(o, "venue", path),
    note: optString(o, "note", path),
    competitionID: optUUID(o, "competition_id", path),
  };
}

export function decodeCourseRow(x: unknown, path = "$"): CourseRow {
  const o = obj(x, path);
  return {
    id: uuid(o, "id", path),
    clubID: optUUID(o, "club_id", path),
    name: reqString(o, "name", path),
    externalName: optString(o, "external_name", path),
    courseRating: optNumber(o, "course_rating", path),
    slopeRating: optInt(o, "slope_rating", path),
    inUse: optBool(o, "in_use", path) ?? true,
  };
}

export function decodeCourseHoleRecord(x: unknown, path = "$"): CourseHoleRecord {
  const o = obj(x, path);
  return {
    courseID: uuid(o, "course_id", path),
    holeNumber: reqInt(o, "hole_number", path),
    par: reqInt(o, "par", path),
    strokeIndex: optInt(o, "stroke_index", path),
    lengthM: optInt(o, "length_m", path),
  };
}

export function decodeRoundRow(x: unknown, path = "$"): RoundRow {
  const o = obj(x, path);
  const status = optEnum(o, "status", ["draft", "active", "locked"] as const, path);
  if (status === null) throw new DecodeError(`${path}.status`, "mangler");
  return {
    id: uuid(o, "id", path),
    clubID: optUUID(o, "club_id", path),
    eventID: optUUID(o, "event_id", path),
    courseID: optUUID(o, "course_id", path),
    roundNo: reqInt(o, "round_no", path),
    name: optString(o, "name", path),
    status,
    holeCount: reqInt(o, "hole_count", path),
    firstHole: reqInt(o, "first_hole", path),
    teeTime: optString(o, "tee_time", path),
    format: reqString(o, "format", path),
    handicapAllowance: reqNumber(o, "handicap_allowance", path),
    externalHandicap: reqBool(o, "external_handicap", path),
    weight: reqNumber(o, "weight", path),
    ldEnabled: reqBool(o, "ld_enabled", path),
    ldHoleIndex: optInt(o, "ld_hole_index", path),
    kpEnabled: reqBool(o, "kp_enabled", path),
    kpHoleIndex: optInt(o, "kp_hole_index", path),
    cutRule: optString(o, "cut_rule", path),
    cutAfter: optInt(o, "cut_after", path),
    venue: optString(o, "venue", path),
    teeID: optUUID(o, "tee_id", path),
    teeName: optString(o, "tee_name", path),
    courseRating: optNumber(o, "course_rating", path),
    slopeRating: optInt(o, "slope_rating", path),
    teePar: optInt(o, "tee_par", path),
    counts: optBool(o, "counts", path) ?? true,
    pointsTable: optString(o, "points_table", path),
    hideLastHoles: optInt(o, "hide_last_holes", path) ?? 0,
    kind: optString(o, "kind", path) === "playoff" ? "playoff" : "normal",
    playoffFor: optUUID(o, "playoff_for", path),
    playoffHoles: optArray(o, "playoff_holes", path)?.map((x, i) => {
      if (typeof x !== "number" || !Number.isInteger(x)) throw new DecodeError(`${path}.playoff_holes[${i}]`, "ventet et heltall");
      return x;
    }) ?? null,
  };
}

export function decodeRoundHoleRow(x: unknown, path = "$"): RoundHoleRow {
  const o = obj(x, path);
  return {
    roundID: uuid(o, "round_id", path),
    holeIndex: reqInt(o, "hole_index", path),
    par: optInt(o, "par", path),
    strokeIndex: optInt(o, "stroke_index", path),
    lengthM: optInt(o, "length_m", path),
  };
}

export function decodeRoundPlayerRow(x: unknown, path = "$"): RoundPlayerRow {
  const o = obj(x, path);
  return {
    roundID: uuid(o, "round_id", path),
    memberID: uuid(o, "member_id", path),
    clubID: optUUID(o, "club_id", path),
    handicapIndex: optNumber(o, "handicap_index", path),
    seedGroup: optInt(o, "seed_group", path),
    playingHandicap: optInt(o, "playing_handicap", path),
    bayNo: optInt(o, "bay_no", path),
    isMarker: optBool(o, "is_marker", path) ?? false,
    teamNo: optInt(o, "team_no", path),
  };
}

export function decodeRoundMatchRow(x: unknown, path = "$"): RoundMatchRow {
  const o = obj(x, path);
  return {
    roundID: uuid(o, "round_id", path),
    matchNo: reqInt(o, "match_no", path),
    playerA: optUUID(o, "player_a", path),
    playerB: optUUID(o, "player_b", path),
    playerC: optUUID(o, "player_c", path),
    teamA: optInt(o, "team_a", path),
    teamB: optInt(o, "team_b", path),
    result: optString(o, "result", path),
  };
}

export function decodeHoleScoreRow(x: unknown, path = "$"): HoleScoreRow {
  const o = obj(x, path);
  return {
    roundID: uuid(o, "round_id", path),
    memberID: uuid(o, "member_id", path),
    holeIndex: reqInt(o, "hole_index", path),
    strokes: reqInt(o, "strokes", path),
  };
}

export function decodeSideClaimRow(x: unknown, path = "$"): SideClaimRow {
  const o = obj(x, path);
  const kind = optEnum(o, "kind", ["drive", "kp"] as const, path);
  if (kind === null) throw new DecodeError(`${path}.kind`, "mangler");
  return {
    id: uuid(o, "id", path),
    roundID: uuid(o, "round_id", path),
    memberID: uuid(o, "member_id", path),
    kind,
    meters: reqNumber(o, "meters", path),
    holeIndex: optInt(o, "hole_index", path),
    createdAt: optString(o, "created_at", path),
  };
}

/** Tilleggspoeng (sql/072): poeng arrangøren gir en spiller for hånd, med en grunn. */
export interface PointAdjustmentRow {
  id: UUID;
  clubID: UUID;
  seasonID: UUID;
  memberID: UUID;
  /** Kvelden tillegget hører til, eller `null`. Bare til visning. */
  eventID: UUID | null;
  points: number;
  reason: string;
}

export function decodePointAdjustmentRow(x: unknown, path = "$"): PointAdjustmentRow {
  const o = obj(x, path);
  return {
    id: uuid(o, "id", path),
    clubID: uuid(o, "club_id", path),
    seasonID: uuid(o, "season_id", path),
    memberID: uuid(o, "member_id", path),
    eventID: optUUID(o, "event_id", path),
    points: reqNumber(o, "points", path),
    reason: reqString(o, "reason", path),
  };
}

/** Svaret fra RPC-en `tavla_data` (sql/036): rådata for én sesong. */
export interface TavlaData {
  events: EventRow[];
  members: ClubMemberRow[];
  rounds: RoundRow[];
  roundHoles: RoundHoleRow[];
  players: RoundPlayerRow[];
  matches: RoundMatchRow[];
  claims: SideClaimRow[];
  courses: CourseRow[];
  courseHoles: CourseHoleRecord[];
  scores: HoleScoreRow[];
  /** Tilleggspoeng (sql/072). Tom før 072 er kjørt. */
  adjustments: PointAdjustmentRow[];
}

/** `tavla_data`-JSON → `TavlaData`. Lister som mangler, er tomme. */
export function decodeTavlaData(x: unknown, path = "$"): TavlaData {
  const o = obj(x, path);
  return {
    events: list(o, "events", path, decodeEvent),
    members: list(o, "members", path, decodeClubMember),
    rounds: list(o, "rounds", path, decodeRoundRow),
    roundHoles: list(o, "round_holes", path, decodeRoundHoleRow),
    players: list(o, "players", path, decodeRoundPlayerRow),
    matches: list(o, "matches", path, decodeRoundMatchRow),
    claims: list(o, "claims", path, decodeSideClaimRow),
    courses: list(o, "courses", path, decodeCourseRow),
    courseHoles: list(o, "course_holes", path, decodeCourseHoleRecord),
    scores: list(o, "scores", path, decodeHoleScoreRow),
    adjustments: list(o, "adjustments", path, decodePointAdjustmentRow),
  };
}
