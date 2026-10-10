// Oppsettet av en runde for arrangøren, som i appen (DashDash18/Features/Admin/Runde: RoundDraft.swift,
// RoundSetup.swift, BayPlan.swift, QuickStartLogic.swift, RoundVenue.swift, RoundConfirmLogic.swift).
// Ren logikk uten nettverk og React, så den kan testes med node --test.

import {
  allowanceFor, allowedForms, drawMatches, effectiveHandicap, formById, formSetup, GOLFGUTU, isTeamForm, makePlayer,
  makeRound, norwegianCompare, roundAwayFromZero, suggestedClosestToPinHole, suggestedLongestDriveHole,
  type CompetitionForm, type Course, type Round, type Ruleset,
} from "../../../golfgutu-core/src/index.ts";

export type UUID = string;
export type RoundStatus = "draft" | "active" | "locked";

/** Et medlem i troppen, med det oppsettet trenger. */
export interface RosterMember {
  id: UUID;
  name: string;
  handicap: number | null;
  seed: number | null;
  userID?: string | null;
}

/** Norsk navnesortering, som `KveldQueries.sortedByName`. */
export function sortedByName<T extends { name: string }>(list: readonly T[]): T[] {
  return [...list].sort((a, b) => norwegianCompare(a.name, b.name));
}

// MARK: - Sted og ord for gruppene (RoundVenue.swift)

export type Venue = "simulator" | "course";

/** Kolonneverdien, `null` (eller ukjent tekst) er simulator. */
export function venueFromStored(stored: string | null | undefined): Venue {
  return stored === "course" ? "course" : "simulator";
}

export function venueTitle(v: Venue): string {
  return v === "course" ? "Ekte bane" : "Simulator";
}

/** «bås» i simulatoren, «flight» på ekte bane. Markør heter markør begge steder. */
export interface GroupTerm {
  singular: string;
  plural: string;
  definite: string;
  definitePlural: string;
}

export const BAY_TERM: GroupTerm = { singular: "bås", plural: "båser", definite: "båsen", definitePlural: "båsene" };
export const FLIGHT_TERM: GroupTerm = { singular: "flight", plural: "flighter", definite: "flighten", definitePlural: "flightene" };

export function groupTerm(v: Venue): GroupTerm {
  return v === "course" ? FLIGHT_TERM : BAY_TERM;
}

const cap = (s: string) => s.charAt(0).toUpperCase() + s.slice(1);

export const termTitle = (t: GroupTerm) => cap(t.singular);
export const termPluralTitle = (t: GroupTerm) => cap(t.plural);
/** «Bås 2» / «Flight 2». */
export const termNumbered = (t: GroupTerm, n: number) => `${termTitle(t)} ${n}`;
/** «1 bås», «3 båser». */
export const termCount = (t: GroupTerm, n: number) => `${n} ${n === 1 ? t.singular : t.plural}`;
/** «Bås 1 og 3». */
export const termNumberedList = (t: GroupTerm, numbers: readonly number[]) => `${termTitle(t)} ${numbers.join(" og ")}`;

// MARK: - Båser (BayPlan.swift)

export interface BaySeat {
  memberID: UUID;
  bay: number;
  isMarker: boolean;
}

/** Flest båser databasen tar imot (`round_players.bay_no between 1 and 12`). */
export const MAX_BAYS = 12;

export function seatFor(seats: readonly BaySeat[], id: UUID): BaySeat | undefined {
  return seats.find((s) => s.memberID === id);
}

/** Båsnumrene som er i bruk, stigende. */
export function bayNumbers(seats: readonly BaySeat[]): number[] {
  return [...new Set(seats.map((s) => s.bay))].sort((a, b) => a - b);
}

/** Høyeste båsnummer. 0 uten båser. */
export function bayCount(seats: readonly BaySeat[]): number {
  return seats.reduce((m, s) => Math.max(m, s.bay), 0);
}

export function membersIn(seats: readonly BaySeat[], bay: number): UUID[] {
  return seats.filter((s) => s.bay === bay).map((s) => s.memberID);
}

export function markerIn(seats: readonly BaySeat[], bay: number): UUID | undefined {
  return seats.find((s) => s.bay === bay && s.isMarker)?.memberID;
}

/** Båser som har spillere, men ingen markør. */
export function baysWithoutMarker(seats: readonly BaySeat[]): number[] {
  return bayNumbers(seats).filter((b) => markerIn(seats, b) === undefined);
}

export function bayCounts(seats: readonly BaySeat[]): Map<number, number> {
  const out = new Map<number, number>();
  for (const s of seats) out.set(s.bay, (out.get(s.bay) ?? 0) + 1);
  return out;
}

/** Så få båser som rommer alle, med regelsettets største antall per bås. Minst én. */
export function defaultBayCount(players: number, maxPerBay: number): number {
  const perBay = Math.max(1, maxPerBay);
  return Math.max(1, Math.floor((players + perBay - 1) / perBay));
}

/**
 * `foreslaatteBaaser`: de som er med, fordelt på `bays` båser. Hver match er en gruppe som holdes samlet,
 * resten står alene. Gruppene legges i båsen med færrest (ved likt den laveste), og den første i en tom bås
 * blir markør.
 */
export function suggestedBays(participants: readonly UUID[], matchGroups: readonly (readonly UUID[])[], bays: number): BaySeat[] {
  const count = Math.max(1, bays);
  const included = new Set(participants);
  const placed = new Set<UUID>();
  const groups: UUID[][] = [];
  for (const match of matchGroups) {
    const group = match.filter((id) => {
      if (!included.has(id) || placed.has(id)) return false;
      placed.add(id);
      return true;
    });
    if (group.length > 0) groups.push(group);
  }
  for (const id of participants) {
    if (!placed.has(id)) {
      placed.add(id);
      groups.push([id]);
    }
  }
  const filled = new Array<number>(count).fill(0);
  const seats: BaySeat[] = [];
  for (const group of groups) {
    let fewest = 0;
    for (let bay = 1; bay < count; bay++) if (filled[bay] < filled[fewest]) fewest = bay;
    group.forEach((id, i) => seats.push({ memberID: id, bay: fewest + 1, isMarker: filled[fewest] === 0 && i === 0 }));
    filled[fewest] += group.length;
  }
  return seats;
}

/**
 * `kartFlytt`: flytt spilleren til en bås (`null` = ut av båsene). En markør som flyttes, tar markørrollen
 * med seg hvis den nye båsen ikke har en, og båsen han forlot får den første som er igjen som ny markør.
 */
export function moveSeat(input: readonly BaySeat[], id: UUID, bay: number | null): BaySeat[] {
  const seats = input.map((s) => ({ ...s }));
  const index = seats.findIndex((s) => s.memberID === id);
  const from = index >= 0 ? seats[index].bay : null;
  const wasMarker = index >= 0 ? seats[index].isMarker : false;

  if (bay !== null) {
    const seat = { memberID: id, bay, isMarker: false };
    if (index >= 0) seats[index] = seat;
    else seats.push(seat);
    const hasMarker = seats.some((s) => s.bay === bay && s.isMarker);
    if (wasMarker && !hasMarker) {
      const i = seats.findIndex((s) => s.memberID === id);
      if (i >= 0) seats[i].isMarker = true;
    }
  } else if (index >= 0) {
    seats.splice(index, 1);
  }

  if (wasMarker && from !== null && from !== bay) {
    const left = seats.filter((s) => s.bay === from);
    if (left.length > 0 && !left.some((s) => s.isMarker)) left[0].isMarker = true;
  }
  return seats;
}

/** `kartMarkor`: gjør spilleren til markør i sin bås. */
export function makeMarker(input: readonly BaySeat[], id: UUID): BaySeat[] {
  const bay = seatFor(input, id)?.bay;
  if (bay === undefined) return [...input];
  return input.map((s) => (s.bay === bay ? { ...s, isMarker: s.memberID === id } : s));
}

/** `baasInn`: legg spilleren i båsen med færrest (ved likt den laveste). Uten båser: bås 1, som markør. */
export function addSeat(input: readonly BaySeat[], id: UUID): BaySeat[] {
  if (seatFor(input, id)) return [...input];
  const counts = bayCounts(input);
  const bays = [...counts.keys()].sort((a, b) => counts.get(a)! - counts.get(b)! || a - b);
  if (bays.length === 0) return [...input, { memberID: id, bay: 1, isMarker: true }];
  return [...input, { memberID: id, bay: bays[0], isMarker: false }];
}

/** Tar ut alle som ikke er med lenger, med samme markørregel som å flytte ut. */
export function keepOnly(input: readonly BaySeat[], participants: ReadonlySet<UUID>): BaySeat[] {
  let seats = [...input];
  for (const id of input.map((s) => s.memberID)) if (!participants.has(id)) seats = moveSeat(seats, id, null);
  return seats;
}

// MARK: - Deltakere (RoundSetup.swift)

export type ParticipantSource = "signups" | "everyone" | "saved";

export interface SignupRow {
  member_id: UUID;
  status: "yes" | "maybe" | "no" | string;
}

/** De som har svart «Kommer», i troppens rekkefølge. Har ingen svart «Kommer», er alle med. */
export function initialParticipants(roster: readonly RosterMember[], signups: readonly SignupRow[]): { ids: UUID[]; source: ParticipantSource } {
  const coming = new Set(signups.filter((s) => s.status === "yes").map((s) => s.member_id));
  const ids = roster.filter((m) => coming.has(m.id)).map((m) => m.id);
  if (ids.length === 0) return { ids: roster.map((m) => m.id), source: "everyone" };
  return { ids, source: "signups" };
}

/** Rediger kladd: de som er satt opp, i troppens rekkefølge. Er ingen satt opp ennå, gjelder påmeldingen. */
export function draftParticipants(roster: readonly RosterMember[], saved: readonly { memberID: UUID }[], signups: readonly SignupRow[]): { ids: UUID[]; source: ParticipantSource } {
  const inRound = new Set(saved.map((p) => p.memberID));
  const ids = roster.filter((m) => inRound.has(m.id)).map((m) => m.id);
  if (ids.length === 0) return initialParticipants(roster, signups);
  return { ids, source: "saved" };
}

// MARK: - Matcher

export interface MatchDraft {
  playerA: UUID | null;
  playerB: UUID | null;
  playerC: UUID | null;
  teamA: number | null;
  teamB: number | null;
  /** Manuelt resultat fra en lagret match. Beholdes uendret. */
  result: string | null;
}

export function playerMatch(a: UUID | null, b: UUID | null, c: UUID | null = null): MatchDraft {
  return { playerA: a, playerB: b, playerC: c, teamA: null, teamB: null, result: null };
}

export function teamMatch(a: number | null, b: number | null): MatchDraft {
  return { playerA: null, playerB: null, playerC: null, teamA: a, teamB: b, result: null };
}

export const isTeamMatch = (m: MatchDraft) => m.teamA !== null || m.teamB !== null;
export const isTriangleMatch = (m: MatchDraft) => m.playerC !== null;

/** Spillerne i matchen. For en lagmatch: lagkameratene slått opp i `teams`. */
export function matchMembers(m: MatchDraft, teams: Readonly<Record<UUID, number>> = {}): UUID[] {
  if (isTeamMatch(m)) {
    return Object.entries(teams)
      .filter(([, t]) => t === m.teamA || t === m.teamB)
      .sort(([ia, ta], [ib, tb]) => {
        const ra = ta === m.teamA ? 0 : 1;
        const rb = tb === m.teamA ? 0 : 1;
        return ra !== rb ? ra - rb : ia.toUpperCase() < ib.toUpperCase() ? -1 : ia.toUpperCase() > ib.toUpperCase() ? 1 : 0;
      })
      .map(([id]) => id);
  }
  return [m.playerA, m.playerB, m.playerC].filter((x): x is UUID => x !== null);
}

/** `trekkMatcher` (første omgang) for de som er med. Uten stilling sorteres det på navn (norsk). */
export function drawIndividual(participants: readonly RosterMember[]): MatchDraft[] {
  const players = participants.map((m) => makePlayer(m.id, m.name));
  return drawMatches(players, 0, new Map()).flatMap((ids) =>
    ids.length >= 2 ? [playerMatch(ids[0], ids[1], ids.length > 2 ? ids[2] : null)] : []);
}

/** Lag mot lag i lagnummerets rekkefølge: 1 mot 2, 3 mot 4. */
export function teamMatches(teams: Readonly<Record<UUID, number>>): MatchDraft[] {
  const numbers = [...new Set(Object.values(teams))].sort((a, b) => a - b);
  const out: MatchDraft[] = [];
  for (let i = 0; i + 1 < numbers.length; i += 2) out.push(teamMatch(numbers[i], numbers[i + 1]));
  return out;
}

/** Kan de lagrede matchene stå? Bare når de samme spillerne er med. */
export function canKeepMatches(matches: readonly MatchDraft[], participants: readonly UUID[], teams: Readonly<Record<UUID, number>>, teamForm: boolean): boolean {
  if (matches.length === 0) return false;
  if (teamForm) {
    const numbers = new Set(Object.values(teams));
    return matches.every((m) => isTeamMatch(m) && m.teamA !== null && m.teamB !== null && numbers.has(m.teamA) && numbers.has(m.teamB));
  }
  if (!matches.every((m) => !isTeamMatch(m))) return false;
  const inMatches = matches.flatMap((m) => matchMembers(m));
  const set = new Set(inMatches);
  const want = new Set(participants);
  return set.size === want.size && [...set].every((id) => want.has(id)) && inMatches.length === set.size;
}

/** Hva som er galt med matchene. Tom liste = i orden. */
export function matchProblems(matches: readonly MatchDraft[], participants: readonly UUID[], teams: Readonly<Record<UUID, number>>, names: ReadonlyMap<UUID, string>): string[] {
  const problems: string[] = [];
  const included = new Set(participants);
  const seen = new Map<UUID, number>();
  matches.forEach((match, i) => {
    const number = i + 1;
    if (isTeamMatch(match)) {
      if (match.teamA === null || match.teamB === null || match.teamA === match.teamB) {
        problems.push(`Match ${number} mangler to forskjellige lag.`);
        return;
      }
      const numbers = new Set(Object.values(teams));
      if (!numbers.has(match.teamA) || !numbers.has(match.teamB)) problems.push(`Match ${number} har et lag uten spillere.`);
      return;
    }
    const ids = matchMembers(match);
    if (match.playerA === null || match.playerB === null || new Set(ids).size !== ids.length) {
      problems.push(`Match ${number} mangler to forskjellige spillere.`);
      return;
    }
    for (const id of ids) {
      if (!included.has(id)) problems.push(`${names.get(id) ?? "En spiller"} i match ${number} er ikke med i runden.`);
      const other = seen.get(id);
      if (other !== undefined) problems.push(`${names.get(id) ?? "En spiller"} står i både match ${other} og ${number}.`);
      seen.set(id, number);
    }
  });
  return problems;
}

// MARK: - Lag

/** Forslag til lag: lagstørrelsene fra `oppsettForAntall`, fylt i deltakernes rekkefølge. */
export function suggestedTeams(participants: readonly UUID[], form: CompetitionForm, maxPerBay: number): Record<UUID, number> {
  const setup = formSetup(form, participants.length, maxPerBay);
  if (setup.kind !== "teams") return {};
  const teams: Record<UUID, number> = {};
  let i = 0;
  setup.split.sizes.forEach((size, number) => {
    for (let k = 0; k < size && i < participants.length; k++) teams[participants[i++]] = number + 1;
  });
  return teams;
}

/** `lesLagOppsett`: går lagene opp? `null` = i orden. */
export function teamProblem(teams: Readonly<Record<UUID, number>>, participants: readonly UUID[], form: CompetitionForm, maxPerBay: number): string | null {
  const withoutTeam = participants.filter((id) => teams[id] === undefined).length;
  const counts = new Map<number, number>();
  for (const id of participants) {
    const t = teams[id];
    if (t !== undefined) counts.set(t, (counts.get(t) ?? 0) + 1);
  }
  if (counts.size === 0) return "Sett opp lagene før du starter runden.";
  if (counts.size < 2) return "Det må være minst to lag.";
  if (withoutTeam > 0) return withoutTeam === 1 ? "Én av deltakerne har ikke lag." : `${withoutTeam} av deltakerne har ikke lag.`;
  const numbers = [...counts.keys()].sort((a, b) => a - b);
  if (form.allowsUnevenTeams) {
    const tooBig = numbers.filter((n) => counts.get(n)! > maxPerBay);
    if (tooBig.length > 0) return `Lag ${tooBig.join(" og ")} har flere enn ${maxPerBay}. Et lag får ikke plass i en bås da.`;
    return null;
  }
  const wrong = numbers.filter((n) => counts.get(n)! !== form.teamSize);
  if (wrong.length > 0) return `Lag ${wrong.join(" og ")} har ikke ${form.teamSize} spillere.`;
  return null;
}

// MARK: - Kladden (RoundDraft.swift)

export interface RoundDraft {
  roundID: UUID;
  isSaved: boolean;
  eventID: UUID;
  roundNo: number;
  courseID: UUID | null;
  teeID: UUID | null;
  holeCount: number;
  /** 1, eller 10 for siste ni på en 18-hullsbane. */
  firstHole: number;
  /** `HH:MM:SS`, eller null. */
  teeTime: string | null;
  participants: UUID[];
  participantSource: ParticipantSource;
  bays: BaySeat[];
  formID: string;
  teams: Record<UUID, number>;
  matches: MatchDraft[];
  ldEnabled: boolean;
  ldHoleIndex: number | null;
  kpEnabled: boolean;
  kpHoleIndex: number | null;
  weight: number;
  externalHandicap: boolean;
  allowance: number;
  venue: Venue;
}

export const draftForm = (d: RoundDraft) => formById(d.formID);

/** Siste ni kan bare spilles som 9 hull på en 18-hullsbane. */
export function canStartAtTen(holeCount: number, courseHoles: number | null): boolean {
  return holeCount === 9 && courseHoles === 18;
}

/** Ny runde med regelsettets standardverdier. */
export function newDraft(p: {
  roundID: UUID; eventID: UUID; roundNo: number; teeTime: string | null; participants: UUID[]; source: ParticipantSource; rules: Ruleset;
}): RoundDraft {
  const form = formById(p.rules.formats.defaultFormID);
  return {
    roundID: p.roundID, isSaved: false, eventID: p.eventID, roundNo: p.roundNo, courseID: null, teeID: null,
    holeCount: 18, firstHole: 1, teeTime: p.teeTime, participants: p.participants, participantSource: p.source,
    bays: suggestedBays(p.participants, [], defaultBayCount(p.participants.length, p.rules.formats.maxPerBay)),
    formID: form.id, teams: {}, matches: [],
    ldEnabled: p.rules.sidePrizes.longestDrive.enabled, ldHoleIndex: null,
    kpEnabled: p.rules.sidePrizes.closestToPin.enabled, kpHoleIndex: null,
    weight: 1, externalHandicap: p.rules.handicap.externalHandicap, allowance: allowanceFor(p.rules, form),
    venue: "simulator",
  };
}

/** Raden i `rounds` slik oppsettet trenger den. */
export interface SavedRound {
  id: UUID;
  eventID: UUID | null;
  roundNo: number;
  courseID: UUID | null;
  teeID: UUID | null;
  holeCount: number;
  firstHole: number;
  teeTime: string | null;
  format: string;
  handicapAllowance: number;
  externalHandicap: boolean;
  weight: number;
  ldEnabled: boolean;
  ldHoleIndex: number | null;
  kpEnabled: boolean;
  kpHoleIndex: number | null;
  venue: string | null;
}

export interface SavedPlayer {
  memberID: UUID;
  bayNo: number | null;
  isMarker: boolean;
  teamNo: number | null;
}

export interface SavedMatch {
  matchNo: number;
  playerA: UUID | null;
  playerB: UUID | null;
  playerC: UUID | null;
  teamA: number | null;
  teamB: number | null;
  result: string | null;
}

/** Kladden slik den er lagret. */
export function savedDraft(round: SavedRound, players: readonly SavedPlayer[], matches: readonly SavedMatch[], participants: UUID[], source: ParticipantSource): RoundDraft {
  const order = new Map(participants.map((id, i) => [id, i]));
  const seats = players
    .filter((p) => p.bayNo !== null)
    .map((p) => ({ memberID: p.memberID, bay: p.bayNo!, isMarker: p.isMarker }))
    .sort((a, b) => (order.get(a.memberID) ?? Number.MAX_SAFE_INTEGER) - (order.get(b.memberID) ?? Number.MAX_SAFE_INTEGER));
  const teams: Record<UUID, number> = {};
  for (const p of players) if (p.teamNo !== null) teams[p.memberID] = p.teamNo;
  return {
    roundID: round.id, isSaved: true, eventID: round.eventID ?? "", roundNo: round.roundNo,
    courseID: round.courseID, teeID: round.teeID, holeCount: round.holeCount, firstHole: round.firstHole,
    teeTime: round.teeTime, participants, participantSource: source, bays: seats, formID: round.format, teams,
    matches: [...matches].sort((a, b) => a.matchNo - b.matchNo).map((m) => ({
      playerA: m.playerA, playerB: m.playerB, playerC: m.playerC, teamA: m.teamA, teamB: m.teamB, result: m.result,
    })),
    ldEnabled: round.ldEnabled, ldHoleIndex: round.ldHoleIndex, kpEnabled: round.kpEnabled, kpHoleIndex: round.kpHoleIndex,
    weight: round.weight, externalHandicap: round.externalHandicap, allowance: round.handicapAllowance,
    venue: venueFromStored(round.venue),
  };
}

/** Bytter mellom simulator og ekte bane. På ekte bane fører dere brutto; i simulatoren gjelder regelsettets valg. */
export function setVenue(d: RoundDraft, venue: Venue, rules: Ruleset): RoundDraft {
  if (venue === d.venue) return d;
  return { ...d, venue, externalHandicap: venue === "simulator" ? rules.handicap.externalHandicap : false };
}

/** Trekker matchene på nytt: lag mot lag i lagformer, `trekkMatcher` ellers. */
export function redrawMatches(d: RoundDraft, roster: readonly RosterMember[]): RoundDraft {
  if (isTeamForm(draftForm(d))) {
    const teams: Record<UUID, number> = {};
    for (const [id, t] of Object.entries(d.teams)) if (d.participants.includes(id)) teams[id] = t;
    return { ...d, matches: teamMatches(teams) };
  }
  const included = new Set(d.participants);
  return { ...d, matches: drawIndividual(roster.filter((m) => included.has(m.id))) };
}

/** Lag og matcher klare for oppsettet (`handleStartRunde`). */
export function prepareSetup(d: RoundDraft, rules: Ruleset, roster: readonly RosterMember[]): RoundDraft {
  let out = d;
  const form = draftForm(d);
  if (isTeamForm(form) && Object.keys(d.teams).length === 0) {
    out = { ...out, teams: suggestedTeams(out.participants, form, rules.formats.maxPerBay) };
  }
  // Teller tabellen stableford, gir matcher ingen poeng, så de trekkes ikke.
  if (rules.table.pointsSource !== "matches") return { ...out, matches: [] };
  if (!canKeepMatches(out.matches, out.participants, out.teams, isTeamForm(form))) out = redrawMatches(out, roster);
  return out;
}

/** Skifter form: ny andel fra regelsettet, og lag og matcher legges på nytt. */
export function setForm(d: RoundDraft, id: string, rules: Ruleset, roster: readonly RosterMember[]): RoundDraft {
  const form = formById(id);
  const teams = isTeamForm(form) ? suggestedTeams(d.participants, form, rules.formats.maxPerBay) : {};
  return redrawMatches({ ...d, formID: id, allowance: allowanceFor(rules, form), teams }, roster);
}

/** Fordeler båsene på nytt, med duellpartnerne samlet. */
export function reshuffleBays(d: RoundDraft, count: number): RoundDraft {
  const groups = d.matches.map((m) => matchMembers(m, d.teams));
  return { ...d, bays: suggestedBays(d.participants, groups, count) };
}

/** Tar med en spiller: inn i båsen med færrest. */
export function includePlayer(d: RoundDraft, id: UUID, roster: readonly RosterMember[]): RoundDraft {
  if (d.participants.includes(id)) return d;
  const wanted = new Set([...d.participants, id]);
  return { ...d, participants: roster.map((m) => m.id).filter((x) => wanted.has(x)), bays: addSeat(d.bays, id) };
}

/** Tar ut en spiller fra runden, båsen, laget og matchene han sto i. */
export function excludePlayer(d: RoundDraft, id: UUID): RoundDraft {
  const teams = { ...d.teams };
  delete teams[id];
  return {
    ...d,
    participants: d.participants.filter((x) => x !== id),
    bays: moveSeat(d.bays, id, null),
    teams,
    matches: d.matches.filter((m) => isTeamMatch(m) || !matchMembers(m).includes(id)),
  };
}

/** Runden slik regelmotoren ser den: for forslag til LD- og KP-hull og for spillehandicap. */
export function coreRound(d: RoundDraft, course: Course | null): Round {
  const teams = new Map<string, number>();
  if (isTeamForm(draftForm(d))) for (const [id, t] of Object.entries(d.teams)) teams.set(id, t);
  return makeRound({
    id: d.roundID, gameType: d.formID, holeCount: d.holeCount, holeStart: d.firstHole === 10 ? 9 : 0, course,
    hcpAllowance: d.allowance, hcpExtern: d.externalHandicap, teams, ldEnabled: d.ldEnabled, kpEnabled: d.kpEnabled,
    ldHoleIndex: d.ldHoleIndex, kpHoleIndex: d.kpHoleIndex, weight: d.weight,
  });
}

/** Hullet som lagres for longest drive: det valgte, ellers forslaget. Lagres også når premien er av. */
export function ldHole(d: RoundDraft, course: Course | null): number {
  return d.ldHoleIndex !== null && d.ldHoleIndex < d.holeCount ? d.ldHoleIndex : suggestedLongestDriveHole(coreRound(d, course));
}

export function kpHole(d: RoundDraft, course: Course | null): number {
  return d.kpHoleIndex !== null && d.kpHoleIndex < d.holeCount ? d.kpHoleIndex : suggestedClosestToPinHole(coreRound(d, course));
}

// MARK: - Sjekk før lagring og start

export type RoundSetupIssue =
  | { kind: "noCourse" }
  | { kind: "courseNotReady"; name: string }
  | { kind: "tooFewPlayers" }
  | { kind: "bayWithoutMarker"; bays: number[] }
  | { kind: "formNotAllowed"; name: string }
  | { kind: "formNotSupported"; name: string }
  | { kind: "teams"; text: string }
  | { kind: "matches"; problems: string[] }
  | { kind: "sidePrizeOutsideRound"; holes: number };

export function issueMessage(issue: RoundSetupIssue, term: GroupTerm): string {
  switch (issue.kind) {
    case "noCourse": return "Velg en bane. Uten kjenner ikke appen parene.";
    case "courseNotReady": return `${issue.name} har ikke par på alle hull. Legg inn tallene under Banene først.`;
    case "tooFewPlayers": return "Det må være minst to spillere med.";
    case "bayWithoutMarker": return `${termNumberedList(term, issue.bays)} har ingen markør.`;
    case "formNotAllowed": return `${issue.name} er ikke tillatt i turneringens regelsett.`;
    case "formNotSupported": return `${issue.name} kan ikke føres i appen ennå. Velg en annen form.`;
    case "teams": return issue.text;
    case "matches": return issue.problems.join(" ");
    case "sidePrizeOutsideRound": return `Longest drive og nærmest pinnen må ligge innenfor de ${issue.holes} hullene.`;
  }
}

/** Færrest spillere en runde kan startes med. */
export const MINIMUM_PLAYERS = 2;

/**
 * Det som stopper en lagring. En kladd trenger en bane som er klar og en form som går an; start krever i
 * tillegg minst to spillere, markør i hver bås, lag som går opp og gyldige matcher.
 */
export function setupIssues(d: RoundDraft, course: { name: string; isReady: boolean } | null, rules: Ruleset, roster: readonly RosterMember[], forStart: boolean): RoundSetupIssue[] {
  const issues: RoundSetupIssue[] = [];
  if (course) {
    if (!course.isReady) issues.push({ kind: "courseNotReady", name: course.name });
  } else {
    issues.push({ kind: "noCourse" });
  }
  const form = draftForm(d);
  if (!rules.formats.allowedFormIDs.includes(form.id)) issues.push({ kind: "formNotAllowed", name: form.name });
  if (form.support === "mangler") issues.push({ kind: "formNotSupported", name: form.name });

  if (d.ldHoleIndex !== null && d.ldHoleIndex >= d.holeCount) issues.push({ kind: "sidePrizeOutsideRound", holes: d.holeCount });
  else if (d.kpHoleIndex !== null && d.kpHoleIndex >= d.holeCount) issues.push({ kind: "sidePrizeOutsideRound", holes: d.holeCount });

  if (!forStart) return issues;

  if (d.participants.length < MINIMUM_PLAYERS) issues.push({ kind: "tooFewPlayers" });
  const bays = keepOnly(d.bays, new Set(d.participants));
  const missing = baysWithoutMarker(bays);
  if (missing.length > 0) issues.push({ kind: "bayWithoutMarker", bays: missing });

  if (isTeamForm(form)) {
    const problem = teamProblem(d.teams, d.participants, form, rules.formats.maxPerBay);
    if (problem !== null) issues.push({ kind: "teams", text: problem });
  }
  const names = new Map(roster.map((m) => [m.id, m.name]));
  const problems = matchProblems(d.matches, d.participants, d.teams, names);
  if (problems.length > 0) issues.push({ kind: "matches", problems });
  return issues;
}

// MARK: - Det som sendes

/** Raden i `rounds` (upsert på id). Status settes for seg. Tomme felt sendes som null. */
export function roundWrite(d: RoundDraft, clubID: UUID, course: Course | null): Record<string, unknown> {
  return {
    id: d.roundID,
    club_id: clubID,
    event_id: d.eventID,
    round_no: d.roundNo,
    course_id: d.courseID,
    hole_count: d.holeCount,
    // Databasen tillater bare hull 10 for 9 hull (`rounds_first_hole_check`).
    first_hole: d.holeCount === 9 && d.firstHole === 10 ? 10 : 1,
    tee_time: d.teeTime,
    format: d.formID,
    // numeric(4,3): tre desimaler.
    handicap_allowance: roundAwayFromZero(d.allowance * 1000) / 1000,
    external_handicap: d.externalHandicap,
    weight: d.weight,
    ld_enabled: d.ldEnabled,
    ld_hole_index: ldHole(d, course),
    kp_enabled: d.kpEnabled,
    kp_hole_index: kpHole(d, course),
    venue: d.venue,
    tee_id: d.teeID,
  };
}

export interface PlayerEntry {
  member_id: UUID;
  bay_no: number | null;
  is_marker: boolean;
  team_no: number | null;
  playing_handicap: number | null;
}

export interface MatchEntry {
  match_no: number;
  player_a: UUID | null;
  player_b: UUID | null;
  player_c: UUID | null;
  team_a: number | null;
  team_b: number | null;
  result: string | null;
}

export interface SetupParams {
  p_round_id: UUID;
  p_players: PlayerEntry[];
  p_matches: MatchEntry[];
}

/**
 * Parameterne til `set_round_setup` og `start_round`. Spillere utenfor troppen tas ikke med.
 * Ved start regnes spillehandicapet med `effectiveHandicap` og lagres som rundens fasit; i en kladd null.
 */
export function setupParams(roundID: UUID, d: RoundDraft, roster: readonly RosterMember[], course: Course | null, rules: Ruleset, withPlayingHandicap: boolean): SetupParams {
  const byID = new Map(roster.map((m) => [m.id, m]));
  const ids = d.participants.filter((id) => byID.has(id));
  const bays = keepOnly(d.bays, new Set(ids));
  const teamForm = isTeamForm(draftForm(d));
  const corePlayers = ids.map((id) => {
    const m = byID.get(id)!;
    return makePlayer(id, m.name, m.handicap, m.seed);
  });
  const round = coreRound(d, course);
  const players = ids.map((id, i) => {
    const seat = seatFor(bays, id);
    return {
      member_id: id,
      bay_no: seat?.bay ?? null,
      is_marker: seat?.isMarker ?? false,
      team_no: teamForm ? d.teams[id] ?? null : null,
      playing_handicap: withPlayingHandicap ? Math.trunc(effectiveHandicap(corePlayers[i], round, corePlayers, rules)) : null,
    };
  });
  const matches = d.matches.map((m, i) => {
    const team = isTeamMatch(m);
    return {
      match_no: i + 1,
      player_a: team ? null : m.playerA, player_b: team ? null : m.playerB, player_c: team ? null : m.playerC,
      team_a: team ? m.teamA : null, team_b: team ? m.teamB : null,
      result: isTriangleMatch(m) ? null : m.result,
    };
  });
  return { p_round_id: roundID, p_players: players, p_matches: matches };
}

// MARK: - Visning og sletting

/** «Runde 2 – Pebble Beach». */
export function roundTitle(roundNo: number, courseName: string | null | undefined): string {
  return `Runde ${roundNo}` + (courseName ? ` – ${courseName}` : "");
}

export function roundStatusText(s: RoundStatus): string {
  return s === "draft" ? "Kladd" : s === "active" ? "Pågår" : "Låst";
}

/** Linja under runden i lista: «18 hull · Stableford (netto) · 12 med · 3 båser · Kl. 18:00». */
export function roundSubtitle(r: { holeCount: number; firstHole: number; format: string; venue: string | null; teeTime: string | null }, players: number, bays: number): string {
  const parts = [`${r.holeCount} hull` + (r.firstHole === 10 ? " fra hull 10" : ""), formById(r.format).name];
  if (players > 0) parts.push(`${players} med`);
  if (bays > 0) parts.push(termCount(groupTerm(venueFromStored(r.venue)), bays));
  if (r.teeTime) parts.push(`Kl. ${r.teeTime.slice(0, 5)}`);
  return parts.join(" · ");
}

/** Neste ledige rundenummer på kvelden. */
export function nextRoundNo(existing: readonly { roundNo: number }[]): number {
  return existing.reduce((m, r) => Math.max(m, r.roundNo), 0) + 1;
}

/** Kan det settes opp en ny runde på kvelden? Bare kvelder som ikke er passert. */
export function allowsNewRound(eventDate: string, today: string): boolean {
  return eventDate >= today;
}

/** Hva som følger med når en runde slettes (`rundenTarMedSeg`). */
export interface DeleteSummary {
  holeScores: number;
  playersWithScores: number;
  sideClaims: number;
  isDraft: boolean;
}

export const deleteNoun = (s: DeleteSummary) => (s.isDraft ? "kladden" : "runden");

export function deleteLines(s: DeleteSummary): string[] {
  const items: string[] = [];
  if (s.holeScores > 0) {
    items.push(`${s.holeScores} ` + (s.holeScores === 1 ? "ført hull" : "førte hull")
      + `, fra ${s.playersWithScores} ` + (s.playersWithScores === 1 ? "spiller" : "spillere"));
  }
  if (s.sideClaims > 0) items.push(`${s.sideClaims} ` + (s.sideClaims === 1 ? "innmeldt sidepremie" : "innmeldte sidepremier"));
  return items;
}

export function deleteMessage(s: DeleteSummary): string {
  const text: string[] = [];
  const items = deleteLines(s);
  if (items.length === 0) {
    text.push(s.isDraft ? "Ingen har sett den. Båsene og oppsettet forsvinner med den." : "Ingen har ført et hull. Runden er tom.");
  } else {
    text.push("Dette følger med ut, og kan ikke angres:");
    text.push(...items.map((x) => `• ${x}`));
  }
  text.push("Spillerne, banene og terminlista står igjen.");
  return text.join("\n");
}

export function deleteButtonTitle(s: DeleteSummary): string {
  return s.holeScores > 0 ? `Slett runden og ${s.holeScores} ` + (s.holeScores === 1 ? "ført hull" : "førte hull") : `Slett ${deleteNoun(s)}`;
}

/** Meldingen etter `delete_round`. */
export function deletedMessage(r: { round_no: number; hole_scores: number; side_claims: number }): string {
  const parts = [`Runde ${r.round_no} er slettet`];
  if (r.hole_scores > 0) parts.push(`${r.hole_scores} ` + (r.hole_scores === 1 ? "ført hull" : "førte hull"));
  if (r.side_claims > 0) parts.push(`${r.side_claims} ` + (r.side_claims === 1 ? "sidepremie" : "sidepremier"));
  return parts.length === 1 ? parts[0] + "." : parts[0] + ", med " + parts.slice(1).join(" og ") + ".";
}

// MARK: - Feil (DataError og RoundErrors)

/** `DataError.from`: norsk tekst etter SQLSTATE. */
export function dataErrorText(e: unknown): string {
  const err = e as { code?: string; message?: string } | null;
  const code = err?.code;
  const message = err?.message ?? String(e);
  if (/Failed to fetch|NetworkError|Load failed/i.test(message)) return "Ingen kontakt med serveren. Sjekk nettet og prøv igjen.";
  switch (code) {
    case "42501": return "Du har ikke tilgang til dette.";
    case "23505": return "Det finnes allerede.";
    case "22023": case "23514": case "23503": case "55000": case "P0002": return message;
    default: return code ? `Noe gikk galt: ${message}` : message;
  }
}

/** `start_round`: 23505 er én pågående runde per klubb, 55000 er at runden ikke er en kladd lenger. */
export function startErrorText(e: unknown): string {
  const code = (e as { code?: string } | null)?.code;
  if (code === "23505") return "En runde går allerede. Lås den før du starter en ny.";
  if (code === "55000") return "Bare en kladd kan startes. Last inn på nytt og sjekk.";
  return dataErrorText(e);
}

/** 23505 ved lagring er `rounds_unique_no_per_event`: to arrangører lagret samtidig. */
export function saveErrorText(e: unknown): string {
  const code = (e as { code?: string } | null)?.code;
  return code === "23505" ? "Kvelden har alt en runde med samme nummer. Last inn på nytt og prøv igjen." : dataErrorText(e);
}

// MARK: - Hurtigstart (QuickStartLogic.swift)

export interface StartChoice {
  firstHole: number;
  holeCount: number;
}

export const startTitle = (s: StartChoice) => `Hull ${s.firstHole} · ${s.holeCount} hull`;

/** Startvalgene for banen: 18 hull fra hull 1, 9 hull fra hull 1, og siste ni på en 18-hullsbane. */
export function startOptions(courseHoles: number | null): StartChoice[] {
  const options = [{ firstHole: 1, holeCount: 18 }, { firstHole: 1, holeCount: 9 }];
  if (canStartAtTen(9, courseHoles)) options.push({ firstHole: 10, holeCount: 9 });
  return options;
}

/** Setter start og antall hull. LD og KP går tilbake til forslaget når de havner utenfor runden. */
export function setStart(d: RoundDraft, start: StartChoice, courseHoles: number | null): RoundDraft {
  const holeCount = start.holeCount;
  return {
    ...d,
    holeCount,
    firstHole: canStartAtTen(holeCount, courseHoles) ? start.firstHole : 1,
    ldHoleIndex: d.ldHoleIndex !== null && d.ldHoleIndex >= holeCount ? null : d.ldHoleIndex,
    kpHoleIndex: d.kpHoleIndex !== null && d.kpHoleIndex >= holeCount ? null : d.kpHoleIndex,
  };
}

/** Ny bane: teen hører til banen, LD og KP tilbake til forslaget, og hull 10 bare der det går. */
export function setCourse(d: RoundDraft, id: UUID | null, courseHoles: number | null): RoundDraft {
  if (id === d.courseID) return d;
  return {
    ...d, courseID: id, teeID: null, ldHoleIndex: null, kpHoleIndex: null,
    firstHole: canStartAtTen(d.holeCount, courseHoles) ? d.firstHole : 1,
  };
}

/** En startet runde med dato, for forslaget fra forrige runde. */
export interface PreviousCandidate {
  id: UUID;
  status: RoundStatus;
  eventID: UUID | null;
  roundNo: number;
  courseID: UUID | null;
  teeID: UUID | null;
  holeCount: number;
  firstHole: number;
  ldHoleIndex: number | null;
  kpHoleIndex: number | null;
  weight: number;
  venue: string | null;
}

/**
 * Forrige runde i turneringen: den siste som er startet (pågår eller låst) på en kveld til og med denne, i
 * kveldsdato- og rundenummerets rekkefølge. Kladder teller ikke.
 */
export function previousRound<T extends PreviousCandidate>(rounds: readonly T[], events: readonly { id: UUID; event_date: string }[], upTo: string): T | null {
  const dates = new Map(events.map((e) => [e.id, e.event_date]));
  let best: { r: T; date: string } | null = null;
  for (const r of rounds) {
    if (r.status === "draft" || r.eventID === null) continue;
    const date = dates.get(r.eventID);
    if (date === undefined || date > upTo) continue;
    if (best === null || date > best.date || (date === best.date && r.roundNo > best.r.roundNo)) best = { r, date };
  }
  return best?.r ?? null;
}

/** Fyller inn det forrige runde valgte: sted, bane, start, LD- og KP-hull og vekt. Banen bare når den er klar. */
export function applySuggestion(d: RoundDraft, previous: PreviousCandidate | null, courses: readonly { id: UUID; isReady: boolean; holeCount: number; teeIDs: UUID[] }[], rules: Ruleset): RoundDraft {
  if (!previous) return d;
  let out = setVenue(d, venueFromStored(previous.venue), rules);
  out = { ...out, weight: previous.weight };
  const course = courses.find((c) => c.id === previous.courseID && c.isReady);
  if (!course) return out;
  const holeCount = previous.holeCount;
  return {
    ...out,
    courseID: course.id,
    teeID: previous.teeID !== null && course.teeIDs.includes(previous.teeID) ? previous.teeID : null,
    holeCount,
    firstHole: canStartAtTen(holeCount, course.holeCount) ? previous.firstHole : 1,
    ldHoleIndex: previous.ldHoleIndex !== null && previous.ldHoleIndex < holeCount ? previous.ldHoleIndex : null,
    kpHoleIndex: previous.kpHoleIndex !== null && previous.kpHoleIndex < holeCount ? previous.kpHoleIndex : null,
  };
}

/** Ny runde fordelt automatisk: lag og matcher, så gruppene med duellpartnerne samlet. */
export function autoArrange(d: RoundDraft, rules: Ruleset, roster: readonly RosterMember[]): RoundDraft {
  const prepared = prepareSetup(d, rules, roster);
  return reshuffleBays(prepared, defaultBayCount(prepared.participants.length, rules.formats.maxPerBay));
}

/** «12 påmeldt · 3 båser», «8 med · 2 flighter». */
export function playersSummary(d: RoundDraft): string {
  const count = d.participants.length;
  const who = d.participantSource === "signups" ? `${count} påmeldt` : `${count} med`;
  const groups = bayNumbers(keepOnly(d.bays, new Set(d.participants))).length;
  return groups > 0 ? `${who} · ${termCount(groupTerm(d.venue), groups)}` : who;
}

/** Det som stopper «Start runden». En runde som går, står først. */
export function startProblems(issues: readonly RoundSetupIssue[], term: GroupTerm, blockingTitle: string | null): string[] {
  const out: string[] = [];
  if (blockingTitle) out.push(`${blockingTitle} går fortsatt. Lagre denne som kladd, og start den når den andre er låst.`);
  return out.concat(issues.map((i) => issueMessage(i, term)));
}

// MARK: - «Flere valg» (RoundConfirmLogic.swift)

/** Valgene fra PWA-ens `vektValg`. */
export const WEIGHTS: readonly { value: number; title: string }[] = [
  { value: 1, title: "Vanlig runde" },
  { value: 1.5, title: "Halvannen" },
  { value: 2, title: "Dobbelt · avsluttende runde" },
  { value: 3, title: "Tredobbelt" },
  { value: 0, title: "Teller ikke sammenlagt" },
];

/** En sidepremie som én rad: av, eller hullet. `null` = av. */
export function sidePrizeChoice(enabled: boolean, holeIndex: number | null, suggestion: number): number | null {
  return enabled ? holeIndex ?? suggestion : null;
}

/** Av slår premien av og beholder hullet; forslaget lagres som `null`, så det følger banen. */
export function applySidePrize(choice: number | null, holeIndex: number | null, suggestion: number): { enabled: boolean; holeIndex: number | null } {
  if (choice === null) return { enabled: false, holeIndex };
  return { enabled: true, holeIndex: choice === suggestion ? null : choice };
}

/** De tillatte formene, og formen kladden har om den ikke er tillatt lenger. */
export function formChoices(rules: Ruleset, formID: string): CompetitionForm[] {
  const forms = allowedForms(rules);
  if (!forms.some((f) => f.id === formID)) forms.unshift(formById(formID));
  return forms;
}

export { GOLFGUTU };
