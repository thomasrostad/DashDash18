// bet-settle: logikken uten nettverk. Henter låste runder med åpne veddemål fra køen
// (bet_settle_jobs), regner utfallet med regelmotoren i TypeScript (settleJob, samme regnestykke
// som feiingen på arrangørens telefon) og skriver det med settle_round_bets. Feiler en jobb,
// meldes det med bet_settle_failed, og de andre jobbene går videre.
//
// Motoren importeres fra repoet (web/golfgutu-core). `supabase functions deploy` pakker
// modulgrafen fra prosjektroten (repoet), så filene utenfor supabase/ kommer med. Skulle en
// pakking bare ta med supabase/, må importen peke på en kopi; ikke dupliser motoren for hånd.

import { settleJob, type SettleOutcome } from "../../../web/golfgutu-core/src/app/betsettle.ts";

/** RPC mot databasen (PostgREST med service_role i index.ts, en falsk i testene). */
export type Rpc = <T>(name: string, params: Record<string, unknown>) => Promise<T>;

export interface JobSummary {
  round_id: string;
  settled: number;
  unknown: number;
  error?: string;
  /** Svaret fra settle_round_bets. */
  response?: unknown;
}

export interface RunSummary {
  jobs: number;
  settled: number;
  unknown: number;
  failed: number;
  rounds: JobSummary[];
}

function roundIdOf(job: unknown): string | null {
  if (job && typeof job === "object" && typeof (job as Record<string, unknown>).round_id === "string") {
    return (job as Record<string, string>).round_id;
  }
  return null;
}

/** Én runde av køen: hent, regn, skriv. Kaster bare når selve hentingen feiler. */
export async function runOnce(rpc: Rpc, limit = 10): Promise<RunSummary> {
  const jobs = (await rpc<unknown[] | null>("bet_settle_jobs", { p_limit: limit })) ?? [];
  const summary: RunSummary = { jobs: jobs.length, settled: 0, unknown: 0, failed: 0, rounds: [] };
  for (const job of jobs) {
    const roundId = roundIdOf(job);
    if (roundId === null) {
      summary.failed++;
      summary.rounds.push({ round_id: "", settled: 0, unknown: 0, error: "jobben mangler round_id" });
      continue;
    }
    let outcome: SettleOutcome | null = null;
    try {
      outcome = settleJob(job);
      const response = await rpc<unknown>("settle_round_bets", { p_round_id: roundId, p_results: outcome.results });
      summary.settled += outcome.results.length;
      summary.unknown += outcome.unknown.length;
      summary.rounds.push({ round_id: roundId, settled: outcome.results.length, unknown: outcome.unknown.length, response });
    } catch (e) {
      const error = (e instanceof Error ? e.message : String(e)).slice(0, 500);
      summary.failed++;
      summary.rounds.push({
        round_id: roundId, settled: 0, unknown: outcome?.unknown.length ?? 0, error,
      });
      try {
        await rpc<unknown>("bet_settle_failed", { p_round_id: roundId, p_error: error });
      } catch {
        // Kan ikke melde feilen: jobben står i køen og prøves igjen ved neste vekking.
      }
    }
  }
  return summary;
}

/** Sammenlikner uten å lekke lengden av felles prefiks via tid. */
export function safeEqual(a: string, b: string): boolean {
  const x = new TextEncoder().encode(a);
  const y = new TextEncoder().encode(b);
  let diff = x.length ^ y.length;
  for (let i = 0; i < Math.max(x.length, y.length); i++) diff |= (x[i] ?? 0) ^ (y[i] ?? 0);
  return diff === 0;
}
