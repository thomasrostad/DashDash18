// verify-purchase: sjekker et kjøp i appen og skriver entitlements (fase 17, StoreKit 2).
// FORSLAG. Ikke deployet. Krever sql/023_kjop.sql.
//
// Appen kaller funksjonen etter et kjøp (og ved «Gjenopprett kjøp») med brukerens egen
// innlogging og { transactionId, competitionId?, clubId? }. Funksjonen
//   1. finner brukeren fra JWT-en (GET /auth/v1/user),
//   2. henter transaksjonen selv fra App Store Server API (appstore.ts), så appen ikke kan
//      dikte opp et kjøp,
//   3. sjekker app, produkt og konto (logic.ts),
//   4. skriver raden med record_purchase (service_role; bare serveren skriver entitlements),
//      og kobler et forbrukbart kjøp til turneringen når kjøperen styrer den.
// Appen fullfører transaksjonen (transaction.finish()) først når svaret er ok.
//
// Secrets (Supabase → Edge Functions → Secrets), aldri i repoet:
//   APPSTORE_ISSUER_ID, APPSTORE_KEY_ID, APPSTORE_PRIVATE_KEY, APPSTORE_BUNDLE_ID
// Satt av Supabase selv: SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY.
//
// Senere: App Store Server Notifications V2 (refusjon, fornyelse) til en egen funksjon som
// verifiserer x5c-kjeden. Til da fanges en refusjon neste gang appen gjenoppretter.

import { fetchSignedTransaction, makeApiToken } from "./appstore.ts";
import {
  decodeJwsPayload,
  parseRequest,
  PurchaseError,
  recordFromTransaction,
  statusForError,
  type TransactionPayload,
} from "./logic.ts";

const REQUIRED = [
  "SUPABASE_URL",
  "SUPABASE_ANON_KEY",
  "SUPABASE_SERVICE_ROLE_KEY",
  "APPSTORE_ISSUER_ID",
  "APPSTORE_KEY_ID",
  "APPSTORE_PRIVATE_KEY",
  "APPSTORE_BUNDLE_ID",
] as const;

const JSON_HEADERS = { "content-type": "application/json; charset=utf-8" };

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: JSON_HEADERS });
}

Deno.serve(async (request) => {
  if (request.method !== "POST") return json({ error: "POST forventet" }, 405);

  const env = Object.fromEntries(REQUIRED.map((k) => [k, Deno.env.get(k) ?? ""])) as Record<
    typeof REQUIRED[number],
    string
  >;
  const missing = REQUIRED.filter((k) => !env[k]);
  if (missing.length) return json({ error: `Mangler konfigurasjon: ${missing.join(", ")}` }, 500);

  const auth = request.headers.get("authorization") ?? "";
  if (!/^Bearer\s+\S+$/i.test(auth)) return json({ error: "Ikke innlogget" }, 401);

  try {
    const userResponse = await fetch(`${env.SUPABASE_URL}/auth/v1/user`, {
      headers: { apikey: env.SUPABASE_ANON_KEY, authorization: auth },
    });
    if (!userResponse.ok) return json({ error: "Ikke innlogget" }, 401);
    const user = await userResponse.json() as { id?: string };
    if (!user.id) return json({ error: "Ikke innlogget" }, 401);

    const verifyRequest = parseRequest(await request.json().catch(() => null));
    const token = await makeApiToken({
      issuerId: env.APPSTORE_ISSUER_ID,
      keyId: env.APPSTORE_KEY_ID,
      privateKeyPem: env.APPSTORE_PRIVATE_KEY,
      bundleId: env.APPSTORE_BUNDLE_ID,
    }, Math.floor(Date.now() / 1000));
    const { signedTransactionInfo } = await fetchSignedTransaction(verifyRequest.transactionId, token);
    const transaction = decodeJwsPayload<TransactionPayload>(signedTransactionInfo);
    const record = recordFromTransaction(transaction, {
      userId: user.id,
      bundleId: env.APPSTORE_BUNDLE_ID,
      request: verifyRequest,
      now: new Date(),
    });

    const saved = await fetch(`${env.SUPABASE_URL}/rest/v1/rpc/record_purchase`, {
      method: "POST",
      headers: {
        apikey: env.SUPABASE_SERVICE_ROLE_KEY,
        authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({ p: record }),
    });
    const text = await saved.text();
    if (saved.status === 403 || text.includes("42501")) {
      throw new PurchaseError("wrong_account", "Kjøpet tilhører en annen konto");
    }
    if (!saved.ok) throw new Error(`record_purchase ${saved.status}: ${text.slice(0, 200)}`);
    return json({ ok: true, entitlement: JSON.parse(text) });
  } catch (error) {
    const code = error instanceof PurchaseError ? error.code : "server";
    return json({ ok: false, code, error: String((error as Error)?.message ?? error).slice(0, 300) }, statusForError(error));
  }
});
