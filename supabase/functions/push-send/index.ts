// push-send: sender ventende jobber i push_queue til APNs (fase 8).
// FORSLAG. Ikke deployet. Se docs/push-oppsett.md.
//
// Vekkes av en Database Webhook på INSERT i public.push_queue (sql/010_push.sql).
// Hver vekking tar ALLE ventende jobber (claim_push_jobs), så en jobb som feilet
// sist, prøves igjen ved neste linje i aktivitetsloggen.
//
// Secrets (Supabase → Edge Functions → Secrets), aldri i repoet:
//   APNS_KEY_ID, APNS_TEAM_ID, APNS_PRIVATE_KEY, APNS_BUNDLE_ID
//   PUSH_HOOK_SECRET   delt hemmelighet; webhooken sender den som x-push-secret
// Satt av Supabase selv: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY.
//
// Logikken (hvem, hva, tekstene) ligger i logic.ts, APNs i apns.ts.

import { ApnsClient, sendAll } from "./apns.ts";
import { type JobPayload, planPush, summarize } from "./logic.ts";

const REQUIRED = [
  "SUPABASE_URL",
  "SUPABASE_SERVICE_ROLE_KEY",
  "APNS_KEY_ID",
  "APNS_TEAM_ID",
  "APNS_PRIVATE_KEY",
  "APNS_BUNDLE_ID",
  "PUSH_HOOK_SECRET",
] as const;

const JOBS_PER_CALL = 20;

const JSON_HEADERS = { "content-type": "application/json; charset=utf-8" };

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: JSON_HEADERS });
}

/** Sammenlikner uten å lekke lengden av felles prefiks via tid. */
function safeEqual(a: string, b: string): boolean {
  const x = new TextEncoder().encode(a);
  const y = new TextEncoder().encode(b);
  let diff = x.length ^ y.length;
  for (let i = 0; i < Math.max(x.length, y.length); i++) diff |= (x[i] ?? 0) ^ (y[i] ?? 0);
  return diff === 0;
}

/** RPC mot PostgREST med service_role. Bare på serveren. */
class Db {
  constructor(private readonly url: string, private readonly key: string) {}

  async rpc<T>(name: string, params: Record<string, unknown>): Promise<T> {
    const response = await fetch(`${this.url}/rest/v1/rpc/${name}`, {
      method: "POST",
      headers: {
        apikey: this.key,
        authorization: `Bearer ${this.key}`,
        "content-type": "application/json",
      },
      body: JSON.stringify(params),
    });
    const text = await response.text();
    if (!response.ok) throw new Error(`${name}: ${response.status} ${text.slice(0, 200)}`);
    return (text ? JSON.parse(text) : null) as T;
  }
}

interface QueueRow {
  id: number;
  attempts: number;
}

Deno.serve(async (request) => {
  if (request.method !== "POST") return json({ error: "POST forventet" }, 405);

  const env = Object.fromEntries(REQUIRED.map((k) => [k, Deno.env.get(k) ?? ""])) as Record<
    typeof REQUIRED[number],
    string
  >;
  const missing = REQUIRED.filter((k) => !env[k]);
  if (missing.length) return json({ error: `Mangler konfigurasjon: ${missing.join(", ")}` }, 500);

  if (!safeEqual(request.headers.get("x-push-secret") ?? "", env.PUSH_HOOK_SECRET)) {
    return json({ error: "Ikke autorisert" }, 401);
  }
  // Webhookens innhold (den nye raden) brukes ikke: køen er fasit.
  await request.body?.cancel();

  const db = new Db(env.SUPABASE_URL, env.SUPABASE_SERVICE_ROLE_KEY);
  const apns = new ApnsClient({
    keyId: env.APNS_KEY_ID,
    teamId: env.APNS_TEAM_ID,
    privateKeyPem: env.APNS_PRIVATE_KEY,
    bundleId: env.APNS_BUNDLE_ID,
  });

  let jobs: QueueRow[];
  try {
    jobs = await db.rpc<QueueRow[]>("claim_push_jobs", { p_limit: JOBS_PER_CALL });
  } catch (error) {
    return json({ error: String((error as Error).message ?? error) }, 502);
  }

  const report: Record<string, unknown>[] = [];
  for (const job of jobs ?? []) {
    try {
      const payload = await db.rpc<JobPayload | null>("push_job_payload", { p_job_id: job.id });
      if (!payload) {
        await db.rpc("finish_push_job", { p_job_id: job.id, p_ok: true, p_result: { skipped: "fant ikke jobben" } });
        continue;
      }
      const plan = planPush(payload, new Date());
      if (plan.skipped) {
        await db.rpc("finish_push_job", { p_job_id: job.id, p_ok: true, p_result: { skipped: plan.skipped } });
        report.push({ job: job.id, skipped: plan.skipped });
        continue;
      }
      const summary = summarize(await sendAll(apns, plan.notifications));
      const result = { sent: summary.sent, failed: summary.failed, removed: summary.deadTokens.length };
      await db.rpc("finish_push_job", {
        p_job_id: job.id,
        p_ok: summary.ok,
        p_result: result,
        p_error: summary.error ?? null,
        p_dead_tokens: summary.deadTokens,
      });
      report.push({ job: job.id, ...result, ...(summary.error ? { error: summary.error } : {}) });
    } catch (error) {
      const message = String((error as Error)?.message ?? error).slice(0, 500);
      report.push({ job: job.id, error: message });
      try {
        await db.rpc("finish_push_job", { p_job_id: job.id, p_ok: false, p_error: message });
      } catch {
        // Låsen går ut av seg selv etter to minutter.
      }
    }
  }
  return json({ jobs: report });
});
