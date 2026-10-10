// Domenet regelmotoren regner på (Models.swift, Match.swift, SidePrize.swift og CourseRules.swift
// sin `CourseHoleRow`). JSON-formen er Swift-motorens (camelCase), den samme som fixturene bruker.

import {
  asInt,
  asNumber,
  intKeyedMap,
  obj,
  optArray,
  optBool,
  optEnum,
  optInt,
  optNumber,
  optObject,
  optString,
  reqInt,
  reqNumber,
  reqString,
  stringKeyedMap,
  type JSONObject,
} from "./decode.ts";

/** Score per hull for én spiller: rundens 0-baserte hullindeks → slag. Et hull uten score står ikke her. */
export type HoleScores = Map<number, number>;

/** En spiller, med bare det regelmotoren trenger. */
export interface Player {
  id: string;
  name: string;
  /** Handicapindeks (WHS). `null` regnes som 0. */
  handicap: number | null;
  /** Seedet gruppe. `null` = ikke seedet. */
  seedGroup: number | null;
}

export function makePlayer(id: string, name = "", handicap: number | null = null, seedGroup: number | null = null): Player {
  return { id, name, handicap, seedGroup };
}

/** Ett hull i banebiblioteket. */
export interface CourseHole {
  par: number | null;
  /** Stroke index slik den står på scorekortet. */
  si: number | null;
  meters: number | null;
}

/** En bane. */
export interface Course {
  id: string | null;
  name: string | null;
  par: number | null;
  courseRating: number | null;
  slopeRating: number | null;
  holes: CourseHole[] | null;
}

/** Rundens egen overstyring av et hull (`round_holes`). */
export interface RoundHole {
  par: number | null;
  strokeIndex: number | null;
  meters: number | null;
}

/** Manuelt satt resultat i en match. */
export type MatchResult = "a" | "b" | "halved";

/** Fra lagret verdi: `A`/`B` (PWA) eller `a`/`b`/`halved`; all annen tekst er delt; tom tekst er ikke noe. */
export function matchResultFromStored(raw: string | null | undefined): MatchResult | null {
  if (raw === null || raw === undefined || raw === "") return null;
  switch (raw.toLowerCase()) {
    case "a":
      return "a";
    case "b":
      return "b";
    default:
      return "halved";
  }
}

/** En match i runden: to spillere, to lag, eller en trekant av tre spillere. */
export interface Match {
  matchNo: number | null;
  playerA: string | null;
  playerB: string | null;
  /** Satt = trekant. */
  playerC: string | null;
  /** Satt = lagmatch. */
  teamA: number | null;
  teamB: number | null;
  result: MatchResult | null;
}

export function makeMatch(m: Partial<Match> = {}): Match {
  return {
    matchNo: m.matchNo ?? null,
    playerA: m.playerA ?? null,
    playerB: m.playerB ?? null,
    playerC: m.playerC ?? null,
    teamA: m.teamA ?? null,
    teamB: m.teamB ?? null,
    result: m.result ?? null,
  };
}

/** `erTrekant`. */
export function isTriangle(m: Match): boolean {
  return (m.playerC ?? "") !== "";
}

/** `erLagmatch`. */
export function isTeamMatch(m: Match): boolean {
  return m.teamA !== null;
}

/** En runde (kveld), med bare feltene regelmotoren leser. */
export interface Round {
  id: string | null;
  /** Konkurranseform (`game_type`). */
  gameType: string | null;
  /** 9 eller 18. Alt annet regnes som 18 (se `numberOfHoles`). */
  holeCount: number | null;
  /** 9 betyr hull 10–18 på en 18-hullsbane (bare når runden er 9 hull). */
  holeStart: number | null;
  course: Course | null;
  /** Rundens egne hull, 0-basert indeks. */
  holes: Map<number, RoundHole> | null;
  /** Handicaptildeling lagret på runden. `null` betyr 1. */
  hcpAllowance: number | null;
  /** Simulatoren deler ut slagene. */
  hcpExtern: boolean;
  /** Lag: spiller-id → lagnummer. */
  teams: Map<string, number>;
  /** Score: spiller-id → hullindeks → slag. */
  holeScores: Map<string, HoleScores>;
  /** `felles`, `nettopar`, `null` (strengen) eller null (ikke avkortet). */
  avkortRegel: string | null;
  avkortetEtter: number | null;
  matches: Match[];
  ldEnabled: boolean;
  kpEnabled: boolean;
  ldHoleIndex: number | null;
  kpHoleIndex: number | null;
  /** Rundevekt. 1 til vanlig, 2 på en dobbeltrunde, 0: teller ikke. */
  weight: number;
  /** Kveldens dato, `YYYY-MM-DD`. */
  date: string | null;
  locked: boolean;
  /** Rundens frosne spillehandicap: spiller-id → handicap i hele slag. */
  playingHandicaps: Map<string, number>;
}

/** En runde med Swift-motorens standardverdier for feltene som ikke er gitt. */
export function makeRound(r: Partial<Round> = {}): Round {
  return {
    id: r.id ?? null,
    gameType: r.gameType ?? null,
    holeCount: r.holeCount ?? null,
    holeStart: r.holeStart ?? null,
    course: r.course ?? null,
    holes: r.holes ?? null,
    hcpAllowance: r.hcpAllowance ?? null,
    hcpExtern: r.hcpExtern ?? false,
    teams: r.teams ?? new Map(),
    holeScores: r.holeScores ?? new Map(),
    avkortRegel: r.avkortRegel ?? null,
    avkortetEtter: r.avkortetEtter ?? null,
    matches: r.matches ?? [],
    ldEnabled: r.ldEnabled ?? true,
    kpEnabled: r.kpEnabled ?? true,
    ldHoleIndex: r.ldHoleIndex ?? null,
    kpHoleIndex: r.kpHoleIndex ?? null,
    weight: r.weight ?? 1,
    date: r.date ?? null,
    locked: r.locked ?? false,
    playingHandicaps: r.playingHandicaps ?? new Map(),
  };
}

/** Kopi av en runde (Swift-runder er verdier). */
export function copyRound(r: Round): Round {
  return {
    ...r,
    holes: r.holes ? new Map(r.holes) : null,
    teams: new Map(r.teams),
    holeScores: new Map([...r.holeScores].map(([k, v]) => [k, new Map(v)])),
    matches: r.matches.map((m) => ({ ...m })),
    playingHandicaps: new Map(r.playingHandicaps),
  };
}

/** Et hull slik det spilles i runden (utdata fra `courseHoles`). */
export interface PlayedHole {
  par: number;
  /** Tallet som står på scorekortet. */
  cardIndex: number;
  meters: number | null;
  /** Rangen blant hullene som spilles (1 = vanskeligst). */
  strokeIndex: number;
}

/** En innmelding til longest drive eller nærmest pinnen. */
export type SideClaimKind = "drive" | "kp";

export interface SideClaim {
  id: string | null;
  kind: SideClaimKind;
  playerId: string;
  roundId: string | null;
  meters: number;
  holeIndex: number | null;
  /** ISO 8601. Avgjør rekkefølgen ved lik lengde, ikke poengene. */
  ts: string | null;
}

/** `SIDE_CLAIM_LABEL`. */
export function sideClaimLabel(kind: SideClaimKind): string {
  return kind === "drive" ? "Longest drive" : "Nærmest pinnen";
}

/** En rad fra `course_holes` med PWA-ens kolonner. */
export interface CourseHoleRow {
  courseId: string | null;
  holeNumber: number;
  par: number | null;
  hcpIndex: number | null;
  distanceMeters: number | null;
}

// MARK: JSON (Swift-motorens form)

export function decodePlayer(x: unknown, path = "$"): Player {
  const o = obj(x, path);
  return {
    id: reqString(o, "id", path),
    name: optString(o, "name", path) ?? "",
    handicap: optNumber(o, "handicap", path),
    seedGroup: optInt(o, "seedGroup", path),
  };
}

export function decodeCourseHole(x: unknown, path = "$"): CourseHole {
  const o = obj(x, path);
  return { par: optInt(o, "par", path), si: optInt(o, "si", path), meters: optNumber(o, "meters", path) };
}

export function decodeCourse(x: unknown, path = "$"): Course {
  const o = obj(x, path);
  const holes = optArray(o, "holes", path);
  return {
    id: optString(o, "id", path),
    name: optString(o, "name", path),
    par: optInt(o, "par", path),
    courseRating: optNumber(o, "courseRating", path),
    slopeRating: optNumber(o, "slopeRating", path),
    holes: holes ? holes.map((h, i) => decodeCourseHole(h, `${path}.holes[${i}]`)) : null,
  };
}

export function decodeRoundHole(x: unknown, path = "$"): RoundHole {
  const o = obj(x, path);
  return {
    par: optInt(o, "par", path),
    strokeIndex: optInt(o, "strokeIndex", path),
    meters: optNumber(o, "meters", path),
  };
}

export function decodeMatch(x: unknown, path = "$"): Match {
  const o = obj(x, path);
  return {
    matchNo: optInt(o, "matchNo", path),
    playerA: optString(o, "playerA", path),
    playerB: optString(o, "playerB", path),
    playerC: optString(o, "playerC", path),
    teamA: optInt(o, "teamA", path),
    teamB: optInt(o, "teamB", path),
    result: matchResultFromStored(optString(o, "result", path)),
  };
}

export function decodeHoleScores(x: unknown, path = "$"): HoleScores {
  return intKeyedMap(obj(x, path), path, asInt);
}

export function decodeRound(x: unknown, path = "$"): Round {
  const o = obj(x, path);
  const course = optObject(o, "course", path);
  const holes = optObject(o, "holes", path);
  const teams = optObject(o, "teams", path);
  const scores = optObject(o, "holeScores", path);
  const matches = optArray(o, "matches", path);
  const frozen = optObject(o, "playingHandicaps", path);
  return {
    id: optString(o, "id", path),
    gameType: optString(o, "gameType", path),
    holeCount: optInt(o, "holeCount", path),
    holeStart: optInt(o, "holeStart", path),
    course: course ? decodeCourse(course, `${path}.course`) : null,
    holes: holes ? intKeyedMap(holes, `${path}.holes`, decodeRoundHole) : null,
    hcpAllowance: optNumber(o, "hcpAllowance", path),
    hcpExtern: optBool(o, "hcpExtern", path) ?? false,
    teams: teams ? stringKeyedMap(teams, `${path}.teams`, asInt) : new Map(),
    holeScores: scores ? stringKeyedMap(scores, `${path}.holeScores`, decodeHoleScores) : new Map(),
    avkortRegel: optString(o, "avkortRegel", path),
    avkortetEtter: optNumber(o, "avkortetEtter", path),
    matches: matches ? matches.map((m, i) => decodeMatch(m, `${path}.matches[${i}]`)) : [],
    ldEnabled: optBool(o, "ldEnabled", path) ?? true,
    kpEnabled: optBool(o, "kpEnabled", path) ?? true,
    ldHoleIndex: optInt(o, "ldHoleIndex", path),
    kpHoleIndex: optInt(o, "kpHoleIndex", path),
    weight: optNumber(o, "weight", path) ?? 1,
    date: optString(o, "date", path),
    locked: optBool(o, "locked", path) ?? false,
    playingHandicaps: frozen ? stringKeyedMap(frozen, `${path}.playingHandicaps`, asNumber) : new Map(),
  };
}

export function decodeSideClaim(x: unknown, path = "$"): SideClaim {
  const o: JSONObject = obj(x, path);
  return {
    id: optString(o, "id", path),
    kind: optEnum(o, "kind", ["drive", "kp"] as const, path) ?? (() => { throw new Error(`${path}.kind mangler`); })(),
    playerId: reqString(o, "playerId", path),
    roundId: optString(o, "roundId", path),
    meters: reqNumber(o, "meters", path),
    holeIndex: optInt(o, "holeIndex", path),
    ts: optString(o, "ts", path),
  };
}

export function decodeCourseHoleRow(x: unknown, path = "$"): CourseHoleRow {
  const o = obj(x, path);
  return {
    courseId: optString(o, "courseId", path),
    holeNumber: reqInt(o, "holeNumber", path),
    par: optInt(o, "par", path),
    hcpIndex: optInt(o, "hcpIndex", path),
    distanceMeters: optNumber(o, "distanceMeters", path),
  };
}
