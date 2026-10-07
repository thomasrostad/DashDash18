// delete-account: sletter kontoen til den som er logget inn (fase 17, App Store 5.1.1(v)).
// FORSLAG. Ikke deployet. Krever sql/019_konto_og_moderering.sql.
//
// Appen kaller funksjonen med brukerens egen innlogging (Authorization: Bearer <JWT>) og
// { "confirm": "SLETT" }. Funksjonen
//   1. finner brukeren fra JWT-en (GET /auth/v1/user), aldri fra innholdet i forespørselen,
//   2. sletter portretter og trådbilder i Storage (account_storage_objects),
//   3. anonymiserer i databasen (delete_account_data): «Slettet spiller», scorene står,
//      meldinger, reaksjoner, push og blokkeringer slettes,
//   4. sletter auth-brukeren (auth.admin.deleteUser). Profilen følger med (cascade).
// Hvert steg tåler å kjøres på nytt, så appen kan prøve igjen hvis noe feiler underveis.
//
// Secrets: ingen egne. SUPABASE_URL, SUPABASE_ANON_KEY og SUPABASE_SERVICE_ROLE_KEY settes
// av Supabase selv. Service role-nøkkelen forlater aldri funksjonen.
//
// Deploy (når godkjent): supabase functions deploy delete-account
// (JWT-sjekken i Supabase står PÅ: bare innloggede kommer inn.)

import {
  bearerToken,
  type DeletionResult,
  failure,
  isConfirmed,
  removalBatches,
  statusFor,
  type StorageObject,
} from "./logic.ts";

const JSON_HEADERS = { "content-type": "application/json; charset=utf-8" };

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: JSON_HEADERS });
}

async function call(url: string, key: string, init: RequestInit & { bearer?: string } = {}): Promise<unknown> {
  const response = await fetch(url, {
    ...init,
    headers: {
      apikey: key,
      authorization: `Bearer ${init.bearer ?? key}`,
      "content-type": "application/json",
      ...(init.headers ?? {}),
    },
  });
  const text = await response.text();
  if (!response.ok) throw new Error(`${response.status} ${text.slice(0, 200)}`);
  return text ? JSON.parse(text) : null;
}

Deno.serve(async (request) => {
  if (request.method !== "POST") return json({ error: "POST forventet" }, 405);

  const url = Deno.env.get("SUPABASE_URL") ?? "";
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (!url || !anonKey || !serviceKey) return json({ error: "Mangler konfigurasjon" }, 500);

  const jwt = bearerToken(request.headers.get("authorization"));
  if (!jwt) return json({ error: "Ikke innlogget" }, 401);

  let body: unknown = null;
  try {
    body = await request.json();
  } catch {
    // tomt eller ugyldig
  }
  if (!isConfirmed(body)) return json({ error: "Mangler bekreftelse" }, 400);

  // 1. Hvem er dette? Spør Auth med brukerens eget token.
  let userId: string;
  try {
    const user = await call(`${url}/auth/v1/user`, anonKey, { method: "GET", bearer: jwt }) as { id?: string };
    if (!user?.id) return json({ error: "Ikke innlogget" }, 401);
    userId = user.id;
  } catch {
    return json({ error: "Ikke innlogget" }, 401);
  }

  const rpc = (name: string, params: Record<string, unknown>) =>
    call(`${url}/rest/v1/rpc/${name}`, serviceKey, { method: "POST", body: JSON.stringify(params) });

  // 2. Filene.
  let removed = 0;
  try {
    const objects = await rpc("account_storage_objects", { p_user_id: userId }) as StorageObject[];
    for (const batch of removalBatches(objects ?? [])) {
      await call(`${url}/storage/v1/object/${batch.bucket}`, serviceKey, {
        method: "DELETE",
        body: JSON.stringify({ prefixes: batch.paths }),
      });
      removed += batch.paths.length;
    }
  } catch (error) {
    const result = failure("files", error, removed);
    return json(result, statusFor(result));
  }

  // 3. Databasen.
  let summary: Record<string, unknown>;
  try {
    summary = await rpc("delete_account_data", { p_user_id: userId }) as Record<string, unknown>;
  } catch (error) {
    const result = failure("anonymize", error, removed);
    return json(result, statusFor(result));
  }

  // 4. Innloggingen.
  try {
    await call(`${url}/auth/v1/admin/users/${userId}`, serviceKey, { method: "DELETE" });
  } catch (error) {
    const result = failure("auth_user", error, removed);
    return json(result, statusFor(result));
  }

  const result: DeletionResult = { ok: true, removedFiles: removed, summary };
  return json(result);
});
