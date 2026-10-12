// bet-settle: gjør opp veddemål med vilkår når runden er låst (steg 11, sql/052).
// FORSLAG. Ikke deployet.
//
// Låses en runde med åpne veddemål som har vilkår, legger databasen runden i
// public.bet_settle_queue. Funksjonen vekkes av en Database Webhook på INSERT i køen og av
// pg_cron hvert femte minutt (sikkerhetsnett: feilede jobber, og runder som låses på nytt, som
// oppdaterer raden i stedet for å legge inn en ny). Den henter jobbene med bet_settle_jobs,
// regner utfallet med regelmotoren i TypeScript og skriver det med settle_round_bets. Det
// som ikke kan avgjøres av scorene, står åpent til arrangøren tar det for hånd.
//
// Secrets (Supabase → Edge Functions → Secrets), aldri i repoet:
//   BET_SETTLE_SECRET  delt hemmelighet; webhooken sender den som x-bet-secret
// Satt av Supabase selv: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY.
// Deploy med --no-verify-jwt (webhooken har ingen innlogging; hemmeligheten er vakten).

import { runOnce, safeEqual } from "./logic.ts";

const REQUIRED = ["SUPABASE_URL", "SUPABASE_SERVICE_ROLE_KEY", "BET_SETTLE_SECRET"] as const;
const JOBS_PER_CALL = 10;
const JSON_HEADERS = { "content-type": "application/json; charset=utf-8" };

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: JSON_HEADERS });
}

/** RPC mot PostgREST med service_role. Bare på serveren. */
function rpcFor(url: string, key: string) {
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
  if (request.method !== "POST") return json({ error: "POST forventet" }, 405);
  const env = Object.fromEntries(REQUIRED.map((k) => [k, Deno.env.get(k) ?? ""])) as Record<
    (typeof REQUIRED)[number],
    string
  >;
  const missing = REQUIRED.filter((k) => !env[k]);
  if (missing.length) return json({ error: `Mangler secrets: ${missing.join(", ")}` }, 500);
  if (!safeEqual(request.headers.get("x-bet-secret") ?? "", env.BET_SETTLE_SECRET)) {
    return json({ error: "Ikke tilgang" }, 401);
  }
  try {
    const summary = await runOnce(rpcFor(env.SUPABASE_URL, env.SUPABASE_SERVICE_ROLE_KEY), JOBS_PER_CALL);
    return json(summary);
  } catch (e) {
    return json({ error: e instanceof Error ? e.message : String(e) }, 502);
  }
});
