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
// Valgfritt, e-post til dem uten push (av til alle fire er satt, se email.ts):
//   SMTP_HOST, SMTP_USER, SMTP_PASS, SMTP_FROM (og SMTP_PORT, standard 465)
//
// Logikken (hvem, hva, tekstene) ligger i logic.ts, APNs i apns.ts, e-posten i email.ts.
// Med sql/046: loggen per mottaker (push_log_result) skrives etter hver jobb. Feiler den
// (for eksempel uten 046), går jobben som før.

import { ApnsClient, sendAll } from "./apns.ts";
import { type EmailRecipient, emailEligible, sendEmails, smtpConfig, SmtpSender } from "./email.ts";
import {
  attachAlreadyNotified,
  attachBlocks,
  attachCompetitionBlocks,
  type BlockRow,
  DROP_WINDOW_MS,
  dropoutLookup,
  type DroppedRow,
  type JobPayload,
  type LogResult,
  type MemberLink,
  planPush,
  type PushPlan,
  pushLogResults,
  pushOriginators,
  type SendResult,
  summarize,
} from "./logic.ts";

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

  /** GET mot en tabell. service_role går forbi RLS. query er PostgREST-filtre. */
  async select<T>(table: string, query: string): Promise<T[]> {
    const response = await fetch(`${this.url}/rest/v1/${table}?${query}`, {
      headers: { apikey: this.key, authorization: `Bearer ${this.key}` },
    });
    const text = await response.text();
    if (!response.ok) throw new Error(`${table}: ${response.status} ${text.slice(0, 200)}`);
    return (text ? JSON.parse(text) : []) as T[];
  }
}

/**
 * Blokkeringene som angår jobben (sql/019, user_blocks): hvem i klubben har
 * blokkert noen av dem som står bak hendelsen. To små oppslag, bare når
 * noen står bak. Feiler et oppslag, kastes feilen, og jobben prøves igjen:
 * heller en forsinket push enn en push fra noen mottakeren har blokkert.
 */
async function withBlocks(db: Db, payload: JobPayload): Promise<JobPayload> {
  const originators = pushOriginators(payload);
  if (originators.length === 0) return payload;
  // Turnering uten klubb og personlige linjer (sql/054): mottakerne er profiler.
  if (payload.audience === "competition" || payload.audience === "person") {
    return withCompetitionBlocks(db, payload, originators);
  }
  const links = await db.select<MemberLink>(
    "club_members",
    `select=id,user_id&club_id=eq.${encodeURIComponent(payload.club.id ?? "")}&user_id=not.is.null`,
  );
  const users = [...new Set(links.filter((l) => originators.includes(l.id) && l.user_id).map((l) => l.user_id!))];
  if (users.length === 0) return payload;
  const blocks = await db.select<BlockRow>(
    "user_blocks",
    `select=blocker_id,blocked_id&blocked_id=in.(${users.map(encodeURIComponent).join(",")})`,
  );
  return blocks.length ? attachBlocks(payload, links, blocks) : payload;
}

/**
 * Turnering uten klubb (sql/046): mottakerne er profiler. De som står bak kan være
 * klubbmedlemmer (actor_member_id) eller profiler; klubbmedlemmene slås opp for innloggingen,
 * og user_blocks leses rett på innloggingene. Feiler et oppslag, prøves jobben igjen.
 */
async function withCompetitionBlocks(db: Db, payload: JobPayload, originators: string[]): Promise<JobPayload> {
  const list = originators.map(encodeURIComponent).join(",");
  const links = await db.select<MemberLink>("club_members", `select=id,user_id&id=in.(${list})&user_id=not.is.null`);
  const users = [...new Set([
    ...links.map((l) => l.user_id!).filter(Boolean),
    ...originators.filter((o) => !links.some((l) => l.id === o)),
  ])];
  const blocks = users.length
    ? await db.select<BlockRow>(
      "user_blocks",
      `select=blocker_id,blocked_id&blocked_id=in.(${users.map(encodeURIComponent).join(",")})`,
    )
    : [];
  return attachCompetitionBlocks(payload, links, blocks);
}

/** Loggen per mottaker (push_log_result, sql/046). Feiler den, går jobben som før. */
async function logResults(db: Db, jobId: number, results: LogResult[]): Promise<string | undefined> {
  if (results.length === 0) return undefined;
  try {
    await db.rpc("push_log_result", { p_job_id: jobId, p_results: results.slice(0, 5000) });
    return undefined;
  } catch (error) {
    return String((error as Error)?.message ?? error).slice(0, 200);
  }
}

/**
 * E-post til dem uten push (email.ts). Bare når SMTP er satt opp og jobben er en av linjene
 * som kan gå som e-post. Uten SMTP: ingenting, og ingen logg.
 */
async function runEmail(db: Db, payload: JobPayload, now: Date): Promise<Record<string, unknown> | undefined> {
  const config = smtpConfig((k) => Deno.env.get(k));
  if (!config || !emailEligible(payload, now)) return undefined;
  try {
    const recipients = await db.rpc<EmailRecipient[] | null>("push_email_recipients", { p_job_id: payload.job_id });
    if (!recipients?.length) return undefined;
    const logs = await sendEmails(new SmtpSender(config), payload, recipients);
    const logError = await logResults(db, payload.job_id, logs);
    return {
      email_sent: logs.filter((l) => l.status === "sent").length,
      email_failed: logs.filter((l) => l.status === "failed").length,
      ...(logError ? { log_error: logError } : {}),
    };
  } catch (error) {
    return { email_error: String((error as Error)?.message ?? error).slice(0, 200) };
  }
}

/**
 * Forfall (se logic.ts): er jobben appens «meldte forfall», hentes serverens
 * signup_dropped for samme kveld og medlem, og mottakerne der hoppes over.
 * Feiler oppslaget, sendes linja som før.
 */
async function withDropouts(db: Db, payload: JobPayload): Promise<JobPayload> {
  const lookup = dropoutLookup(payload);
  if (!lookup) return payload;
  const at = Date.parse(lookup.createdAt);
  if (!Number.isFinite(at)) return payload;
  const from = new Date(at - DROP_WINDOW_MS).toISOString();
  const to = new Date(at + DROP_WINDOW_MS).toISOString();
  try {
    const rows = await db.select<DroppedRow>(
      "activity",
      `select=recipients,created_at&kind=eq.signup_dropped&event_id=eq.${encodeURIComponent(lookup.eventId)}` +
        `&data->>member=eq.${encodeURIComponent(lookup.member)}` +
        `&created_at=gte.${encodeURIComponent(from)}&created_at=lte.${encodeURIComponent(to)}`,
    );
    return attachAlreadyNotified(payload, rows);
  } catch {
    return payload;
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
      // Først uten blokkeringene: hoppes jobben over uansett (gammel, av,
      // ingen mottakere), trengs ingen oppslag.
      const now = new Date();
      let plan: PushPlan = planPush(payload, now);
      let planned = payload;
      if (!plan.skipped) {
        planned = await withBlocks(db, await withDropouts(db, payload));
        plan = planPush(planned, now);
      }
      // E-posten går for seg, også når ingen skal ha push (det er da den trengs).
      const email = await runEmail(db, planned, now);
      if (plan.skipped) {
        const logError = await logResults(db, job.id, pushLogResults(planned, plan));
        await db.rpc("finish_push_job", { p_job_id: job.id, p_ok: true, p_result: { skipped: plan.skipped, ...email } });
        report.push({ job: job.id, skipped: plan.skipped, ...email, ...(logError ? { log_error: logError } : {}) });
        continue;
      }
      const sent: SendResult[] = await sendAll(apns, plan.notifications);
      const summary = summarize(sent);
      const logError = await logResults(db, job.id, pushLogResults(planned, plan, sent));
      const result = { sent: summary.sent, failed: summary.failed, removed: summary.deadTokens.length, ...email };
      await db.rpc("finish_push_job", {
        p_job_id: job.id,
        p_ok: summary.ok,
        p_result: result,
        p_error: summary.error ?? null,
        p_dead_tokens: summary.deadTokens,
      });
      report.push({
        job: job.id,
        ...result,
        ...(summary.error ? { error: summary.error } : {}),
        ...(logError ? { log_error: logError } : {}),
      });
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
