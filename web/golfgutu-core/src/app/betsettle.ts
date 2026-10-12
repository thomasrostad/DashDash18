// Oppgjøret av veddemål på serveren når runden låses (sql/052, supabase/functions/bet-settle).
// Samme regnestykke som feiingen på arrangørens telefon (`BetsBoard.sweepPlan` i
// DashDash18/Features/Vedd/BetsBoard.swift): runden bygges av radene som i Kveld og Tavla
// (`makeRoundFromSnapshot`, `snapshotRoster`, `claimFromRow`), og hvert veddemål får `betVerdict`
// med regelsettet til der veddemålet hører hjemme (turneringen eller runden).

import { betVerdict, decodeBetCondition, type BetVerdict } from "../bets.ts";
import { obj, optArray, optInt, optObject, optString, reqString } from "../decode.ts";
import { decodeRuleset, GOLFGUTU, type Ruleset } from "../ruleset.ts";
import { makeRoundFromSnapshot, makeSnapshot, snapshotRoster } from "./roundgame.ts";
import { decodeTavlaData, type UUID } from "./rows.ts";
import { claimFromRow } from "./tavla.ts";

/** Ett veddemål i en jobb fra `bet_settle_jobs`. */
export interface SettleJobBet {
  id: UUID;
  /** Vilkåret slik databasen lagrer det (uten runde; runden er jobbens). */
  condition: unknown;
  closedAt: string | null;
  /** Regelsettet (jsonb) for turneringen eller runden. `null`: Golfgutu-oppsettet. */
  rules: unknown;
}

/** En jobb fra `bet_settle_jobs`: én låst runde med de åpne veddemålene som har vilkår. */
export interface SettleJob {
  roundID: UUID;
  attempts: number;
  data: unknown;
  bets: SettleJobBet[];
}

export interface SettleResult {
  bet_id: UUID;
  verdict: BetVerdict;
}

/** Svaret: det som kan avgjøres, og det som står igjen til arrangøren. */
export interface SettleOutcome {
  round_id: UUID;
  results: SettleResult[];
  unknown: UUID[];
}

export function decodeSettleJob(x: unknown, path = "$"): SettleJob {
  const o = obj(x, path);
  return {
    roundID: reqString(o, "round_id", path).toLowerCase(),
    attempts: optInt(o, "attempts", path) ?? 0,
    data: optObject(o, "data", path) ?? {},
    bets: (optArray(o, "bets", path) ?? []).map((b, i) => {
      const p = `${path}.bets[${i}]`;
      const bo = obj(b, p);
      return {
        id: reqString(bo, "id", p).toLowerCase(),
        condition: bo["condition"] ?? null,
        closedAt: optString(bo, "closed_at", p),
        rules: bo["rules"] ?? null,
      };
    }),
  };
}

const lower = (x: unknown): unknown => (typeof x === "string" ? x.toLowerCase() : x);

/** Regner utfallet for alle veddemålene i jobben. Kaster når dataene ikke kan leses. */
export function settleJob(raw: unknown): SettleOutcome {
  const job = decodeSettleJob(raw);
  const data = decodeTavlaData(job.data, "$.data");
  const round = data.rounds.find((r) => r.id.toLowerCase() === job.roundID);
  if (round === undefined) throw new Error(`Runden ${job.roundID} mangler i dataene`);
  const results: SettleResult[] = [];
  const unknown: UUID[] = [];
  const cache = new Map<string, Ruleset>();
  for (const bet of job.bets) {
    const key = bet.rules === null ? "" : JSON.stringify(bet.rules);
    let rules = cache.get(key);
    if (rules === undefined) {
      rules = bet.rules === null ? GOLFGUTU : decodeRuleset(bet.rules, `$.bets.${bet.id}.rules`);
      cache.set(key, rules);
    }
    const c = bet.condition;
    if (c === null || typeof c !== "object") { unknown.push(bet.id); continue; }
    const co = c as Record<string, unknown>;
    const condition = decodeBetCondition({
      ...co, round: round.id, player: lower(co.player ?? null), a: lower(co.a ?? null), b: lower(co.b ?? null),
    }, `$.bets.${bet.id}.condition`);
    const snap = makeSnapshot(round, {
      roundHoles: data.roundHoles.filter((h) => h.roundID === round.id),
      players: data.players.filter((p) => p.roundID === round.id),
      matches: data.matches.filter((m) => m.roundID === round.id),
      scores: data.scores.filter((s) => s.roundID === round.id),
      sideClaims: data.claims.filter((s) => s.roundID === round.id),
      course: data.courses.find((x) => x.id === round.courseID) ?? null,
      courseHoles: data.courseHoles.filter((h) => h.courseID === round.courseID),
      eventDate: round.eventID !== null ? data.events.find((e) => e.id === round.eventID)?.eventDate ?? null : null,
      rules,
    });
    const verdict = betVerdict(makeRoundFromSnapshot(snap), condition, snapshotRoster(snap),
      snap.sideClaims.map(claimFromRow), rules);
    if (verdict === null) unknown.push(bet.id);
    else results.push({ bet_id: bet.id, verdict });
  }
  return { round_id: job.roundID, results, unknown };
}
