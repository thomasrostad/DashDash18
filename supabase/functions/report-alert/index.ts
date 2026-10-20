// report-alert: e-post når noen rapporterer innhold (fase 17, sql/063).
// FORSLAG. Ikke deployet.
//
// Apple krever at rapportert brukerinnhold følges opp innen 24 timer (App Store 1.2). Ved hver
// ny rad i public.content_reports kaller triggeren private.report_alert_kick() (pg_net) denne
// funksjonen med x-report-secret og {"report_id": "<uuid>"}. Funksjonen henter et lite
// sammendrag med report_alert_payload (service_role) og sender én e-post per mottaker.
//
// Secrets (Supabase → Edge Functions → Secrets), aldri i repoet:
//   REPORT_ALERT_SECRET  delt hemmelighet; samme verdi som Vault-hemmeligheten
//                        report_alert_secret, sendes som x-report-secret
//   REPORT_ALERT_TO      mottakerne, kommaseparert (f.eks. personvern@dashdash18.com)
//   SMTP_HOST, SMTP_USER, SMTP_PASS, SMTP_FROM (og SMTP_PORT, standard 465), som push-send
// Satt av Supabase selv: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY.
// Mangler SMTP eller mottakere: 200 med {"skipped": …}, og en linje i loggen.
//
// Deploy med --no-verify-jwt (triggeren har ingen innlogging; hemmeligheten er vakten), og fra
// roten av repoet, siden funksjonen importerer ../push-send/email.ts:
//   supabase functions deploy report-alert --no-verify-jwt --project-ref <ref>

import { smtpConfig, SmtpSender } from "../push-send/email.ts";
import { parseRecipients, type Rpc, runAlert } from "./logic.ts";

const JSON_HEADERS = { "content-type": "application/json; charset=utf-8" };

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: JSON_HEADERS });
}

/** RPC mot PostgREST med service_role. Bare på serveren. */
function rpcFor(url: string, key: string): Rpc {
  return async <T>(name: string, params: Record<string, unknown>): Promise<T> => {
    const response = await fetch(`${url}/rest/v1/rpc/${name}`, {
      method: "POST",
      headers: { apikey: key, authorization: `Bearer ${key}`, "content-type": "application/json" },
      body: JSON.stringify(params),
    });
    const text = await response.text();
    if (!response.ok) throw new Error(`${name}: ${response.status} ${text.slice(0, 200)}`);
    return (text ? JSON.parse(text) : null) as T;
  };
}

Deno.serve(async (request) => {
  if (request.method !== "POST") return json({ error: "method" }, 405);
  try {
    const env = (k: string) => Deno.env.get(k);
    const url = env("SUPABASE_URL") ?? "";
    const key = env("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    let body: unknown;
    try {
      body = await request.json();
    } catch {
      body = undefined;
    }
    const result = await runAlert({
      secret: env("REPORT_ALERT_SECRET") ?? "",
      header: request.headers.get("x-report-secret") ?? "",
      body,
      recipients: parseRecipients(env("REPORT_ALERT_TO")),
      smtp: smtpConfig(env),
      rpc: url && key ? rpcFor(url, key) : null,
      makeSender: (config) => new SmtpSender(config),
      log: (message) => console.error(message),
    });
    return json(result.body, result.status);
  } catch (error) {
    console.error(`report-alert: uventet feil: ${String((error as Error)?.message ?? error).slice(0, 300)}`);
    return json({ error: "internal" }, 500);
  }
});
