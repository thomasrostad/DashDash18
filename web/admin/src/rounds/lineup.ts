// Oppstillingstavla: bås, lag og matcher på ett sted. Lagene ligger i båsen, og i lagformer blir matchene
// lag mot lag i samme bås. Ren logikk (testes i test/lineup.test.ts). Lagres som før: `round_players.bay_no`,
// `team_no` og `round_matches`, så appen og databasen ser det samme som med de gamle kortene.

import type { CompetitionForm } from "../../../golfgutu-core/src/index.ts";
import {
  bayNumbers, excludePlayer, includePlayer, makeMarker, membersIn, markerIn, moveSeat, seatFor, teamMatch,
  type MatchDraft, type RosterMember, type RoundDraft, type UUID,
} from "./logic.ts";

export interface LineupTeam {
  team: number;
  members: UUID[];
  /** Plasser som mangler (> 0) eller er for mange (< 0) i forhold til formens lagstørrelse. */
  missing: number;
}

export interface LineupBay {
  bay: number;
  members: UUID[];
  marker: UUID | undefined;
  /** Lagformer: lagene i båsen, med tomme lag så det er plass å legge spillere. Ellers tom. */
  teams: LineupTeam[];
  over: boolean;
  /** Stopper starten av runden. */
  problems: string[];
  /** Lov, men verdt å se på (ujevne lag i en form som tillater det). */
  notes: string[];
}

export interface Lineup {
  bays: LineupBay[];
  /** Med i runden, men uten bås. */
  unseated: UUID[];
  /** Med, i bås, men uten lag (bare lagformer). */
  teamless: UUID[];
  problems: string[];
}

/** Så mange lag får plass i en bås: to når et lag er halve båsen eller mindre, ellers ett. */
export function teamsPerBay(form: CompetitionForm, maxPerBay: number): number {
  return Math.max(1, Math.floor(maxPerBay / Math.max(1, form.teamSize)));
}

/** Tavla slik kladden står: båsene med lag og plasser, og det som ikke er plassert. */
export function lineupOf(d: RoundDraft, form: CompetitionForm, teamForm: boolean, maxPerBay: number, bayCount: number): Lineup {
  const used = bayNumbers(d.bays);
  const numbers = [...new Set([...used, ...Array.from({ length: bayCount }, (_, i) => i + 1)])].sort((a, b) => a - b);
  const perBay = teamsPerBay(form, maxPerBay);
  const allTeams = new Set(Object.entries(d.teams).filter(([id]) => d.participants.includes(id)).map(([, t]) => t));
  let nextFree = 1;
  const free = () => { while (allTeams.has(nextFree)) nextFree++; allTeams.add(nextFree); return nextFree; };
  const problems: string[] = [];
  const bays = numbers.map((bay): LineupBay => {
    const members = membersIn(d.bays, bay).filter((id) => d.participants.includes(id));
    const marker = markerIn(d.bays, bay);
    const teams: LineupTeam[] = [];
    if (teamForm) {
      const inBay = [...new Set(members.map((id) => d.teams[id]).filter((t): t is number => t !== undefined))].sort((a, b) => a - b);
      for (const team of inBay) {
        const m = members.filter((id) => d.teams[id] === team);
        teams.push({ team, members: m, missing: form.teamSize - m.length });
      }
      while (teams.length < perBay) teams.push({ team: free(), members: [], missing: form.teamSize });
    }
    const bayProblems: string[] = [];
    const notes: string[] = [];
    const over = members.length > maxPerBay;
    if (over) bayProblems.push(`Flere enn ${maxPerBay}.`);
    if (members.length > 0 && marker === undefined) bayProblems.push("Ingen markør.");
    for (const t of teams) {
      if (t.members.length === 0) continue;
      const list = form.allowsUnevenTeams ? notes : bayProblems;
      if (t.missing > 0) list.push(`Lag ${t.team} mangler ${t.missing === 1 ? "én" : t.missing}.`);
      if (t.missing < 0) list.push(`Lag ${t.team} har ${-t.missing} for mange.`);
    }
    if (teamForm && teams.filter((t) => t.members.length > 0).length === 1 && perBay > 1) bayProblems.push("Laget har ingen å spille mot.");
    return { bay, members, marker, teams, over, problems: bayProblems, notes };
  });
  const unseated = d.participants.filter((id) => !seatFor(d.bays, id));
  const teamless = teamForm ? d.participants.filter((id) => seatFor(d.bays, id) && d.teams[id] === undefined) : [];
  if (unseated.length > 0) problems.push(unseated.length === 1 ? "Én spiller er ikke plassert." : `${unseated.length} spillere er ikke plassert.`);
  if (teamless.length > 0) problems.push(teamless.length === 1 ? "Én spiller har ikke lag." : `${teamless.length} spillere har ikke lag.`);
  return { bays: bays.filter((b) => b.members.length > 0 || b.bay <= bayCount), unseated, teamless, problems };
}

export type LineupTarget =
  | { kind: "bay"; bay: number; team?: number }
  | { kind: "unseated" }
  | { kind: "out" };

/** Flytter en spiller til en bås (og et lag), ut av båsene, eller ut av runden. */
export function placePlayer(d: RoundDraft, id: UUID, target: LineupTarget, roster: readonly RosterMember[]): RoundDraft {
  if (target.kind === "out") return excludePlayer(d, id);
  let out = d.participants.includes(id) ? d : includePlayer(d, id, roster);
  if (target.kind === "unseated") {
    const teams = { ...out.teams };
    delete teams[id];
    return { ...out, bays: moveSeat(out.bays, id, null), teams };
  }
  const bays = moveSeat(out.bays, id, target.bay);
  // Første i en tom bås blir markør.
  const withMarker = markerIn(bays, target.bay) === undefined ? makeMarker(bays, id) : bays;
  const teams = { ...out.teams };
  if (target.team !== undefined) teams[id] = target.team;
  else delete teams[id];
  out = { ...out, bays: withMarker, teams };
  return out;
}

/** Lagformer: lag mot lag i samme bås (laveste mot neste). Et lag alene i båsen møter laget alene i neste slike bås. */
export function lineupMatches(d: RoundDraft): MatchDraft[] {
  const teamsIn = (bay: number) => [...new Set(membersIn(d.bays, bay).filter((id) => d.participants.includes(id))
    .map((id) => d.teams[id]).filter((t): t is number => t !== undefined))].sort((a, b) => a - b);
  const out: MatchDraft[] = [];
  const alone: number[] = [];
  for (const bay of bayNumbers(d.bays)) {
    const t = teamsIn(bay);
    for (let i = 0; i + 1 < t.length; i += 2) out.push(teamMatch(t[i], t[i + 1]));
    if (t.length % 2 === 1) alone.push(t[t.length - 1]);
  }
  for (let i = 0; i + 1 < alone.length; i += 2) out.push(teamMatch(alone[i], alone[i + 1]));
  return out;
}

/**
 * «Fordel automatisk»: jevne lag etter handicap (beste med dårligste, slangevis), lagene parvis i båsene,
 * og første på hvert lag i båsen som markør. Uten lagform: slangevis etter handicap på båsene.
 * Spillere uten handicap regnes som 54.
 */
export function autoLineup(d: RoundDraft, roster: readonly RosterMember[], form: CompetitionForm, teamForm: boolean, maxPerBay: number, bayCount: number): RoundDraft {
  const hcp = (id: UUID) => roster.find((m) => m.id === id)?.handicap ?? 54;
  const sorted = [...d.participants].sort((a, b) => hcp(a) - hcp(b));
  if (!teamForm) {
    const n = Math.max(1, bayCount);
    const seats = sorted.map((id, i) => {
      const round = Math.floor(i / n);
      const pos = i % n;
      return { memberID: id, bay: (round % 2 === 0 ? pos : n - 1 - pos) + 1, isMarker: false };
    });
    let bays = seats;
    for (let b = 1; b <= n; b++) { const first = bays.find((s) => s.bay === b); if (first) bays = makeMarker(bays, first.memberID); }
    return { ...d, bays };
  }
  const size = Math.max(1, form.teamSize);
  const teamCount = Math.max(2, Math.ceil(sorted.length / size));
  const teamsList: UUID[][] = Array.from({ length: teamCount }, () => []);
  sorted.forEach((id, i) => {
    const round = Math.floor(i / teamCount);
    const pos = i % teamCount;
    teamsList[round % 2 === 0 ? pos : teamCount - 1 - pos].push(id);
  });
  const perBay = teamsPerBay(form, maxPerBay);
  const teams: Record<UUID, number> = {};
  let bays: { memberID: UUID; bay: number; isMarker: boolean }[] = [];
  teamsList.forEach((members, i) => {
    const team = i + 1;
    const bay = Math.floor(i / perBay) + 1;
    for (const id of members) { teams[id] = team; bays.push({ memberID: id, bay, isMarker: false }); }
  });
  for (const b of new Set(bays.map((s) => s.bay))) { const first = bays.find((s) => s.bay === b); if (first) bays = makeMarker(bays, first.memberID); }
  return { ...d, teams, bays };
}
