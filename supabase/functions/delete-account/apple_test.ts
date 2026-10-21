// Tester for Apple-tilbaketrekkingen i delete-account. Kjøres med
//   deno test supabase/functions/delete-account/
// Ingen nettverk: fetch er falsk, og nøkkelen lages i testen.

import { deepStrictEqual as eq, ok, strictEqual as is } from "node:assert/strict";
import {
  APPLE_AUDIENCE,
  APPLE_REVOKE_URL,
  APPLE_TOKEN_URL,
  appleCodeFrom,
  type AppleConfig,
  appleConfigFrom,
  appleSubjectOf,
  base64url,
  CLIENT_SECRET_TTL_SECONDS,
  importAppleKey,
  makeClientSecret,
  pemToPkcs8,
  revokeAppleToken,
  revokeLogLine,
  subjectFromIdToken,
} from "./apple.ts";

const NOW_MS = 1_760_000_000_000;
const NOW_S = Math.floor(NOW_MS / 1000);
const SUB = "001234.abcdef0123456789.1234";

async function testKey(): Promise<{ pem: string; publicKey: CryptoKey }> {
  const pair = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
  const pkcs8 = new Uint8Array(await crypto.subtle.exportKey("pkcs8", pair.privateKey));
  let bin = "";
  for (const b of pkcs8) bin += String.fromCharCode(b);
  const lines = btoa(bin).match(/.{1,64}/g)!.join("\n");
  return { pem: `-----BEGIN PRIVATE KEY-----\n${lines}\n-----END PRIVATE KEY-----\n`, publicKey: pair.publicKey };
}

function config(pem: string): AppleConfig {
  return { teamId: "TEAM123456", keyId: "KEY1234567", privateKeyPem: pem, clientId: "com.dashdash18.app" };
}

function decodePart(part: string): Record<string, unknown> {
  const padded = part.replace(/-/g, "+").replace(/_/g, "/") + "===".slice((part.length + 3) % 4);
  return JSON.parse(atob(padded));
}

function fromBase64url(part: string): ArrayBuffer {
  const bin = atob(part.replace(/-/g, "+").replace(/_/g, "/") + "===".slice((part.length + 3) % 4));
  return Uint8Array.from(bin, (c) => c.charCodeAt(0)).buffer as ArrayBuffer;
}

/** Et ID-token slik Apple gir det (signaturen er ikke ekte, og den sjekkes ikke). */
function idToken(sub: string): string {
  const enc = (value: unknown) => base64url(new TextEncoder().encode(JSON.stringify(value)));
  return `${enc({ alg: "RS256", kid: "x" })}.${enc({ iss: APPLE_AUDIENCE, sub, aud: "com.dashdash18.app" })}.c2ln`;
}

interface Call {
  url: string;
  params: Record<string, string>;
}

/** Falsk fetch: svarer i rekkefølge og husker kallene. */
function fakeFetch(responses: (Response | Error)[]) {
  const calls: Call[] = [];
  const fetcher = (url: string, init: RequestInit) => {
    calls.push({ url, params: Object.fromEntries(new URLSearchParams(String(init.body))) });
    const next = responses.shift();
    if (!next) throw new Error("uventet kall");
    return next instanceof Error ? Promise.reject(next) : Promise.resolve(next);
  };
  return { calls, fetcher };
}

const jsonResponse = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });

// --- Client secret (JWT) ---

Deno.test("client secret er en ES256-JWT med riktige claims, og signaturen holder", async () => {
  const { pem, publicKey } = await testKey();
  const cfg = config(pem);
  const jwt = await makeClientSecret(await importAppleKey(pem), cfg, NOW_S);
  const [h, c, s] = jwt.split(".");
  eq(decodePart(h), { alg: "ES256", kid: "KEY1234567" });
  eq(decodePart(c), {
    iss: "TEAM123456",
    iat: NOW_S,
    exp: NOW_S + CLIENT_SECRET_TTL_SECONDS,
    aud: "https://appleid.apple.com",
    sub: "com.dashdash18.app",
  });
  const signature = fromBase64url(s);
  is(signature.byteLength, 64); // r||s, ikke DER
  const valid = await crypto.subtle.verify(
    { name: "ECDSA", hash: "SHA-256" },
    publicKey,
    signature,
    new TextEncoder().encode(`${h}.${c}`),
  );
  is(valid, true);
  ok(!/[=+/]/.test(jwt), "base64url uten fyll");
});

Deno.test("levetiden er høyst seks måneder, slik Apple krever", () => {
  ok(CLIENT_SECRET_TTL_SECONDS > 0 && CLIENT_SECRET_TTL_SECONDS <= 15_777_000);
});

Deno.test("nøkkelen godtas med «\\n» i stedet for linjeskift", async () => {
  const { pem } = await testKey();
  const escaped = pem.replace(/\n/g, "\\n");
  eq(pemToPkcs8(escaped), pemToPkcs8(pem));
  await importAppleKey(escaped);
});

Deno.test("en nøkkel som ikke er PEM, gir en tydelig feil", () => {
  let message = "";
  try {
    pemToPkcs8("ikke en nøkkel!");
  } catch (error) {
    message = (error as Error).message;
  }
  is(message, "APPLE_PRIVATE_KEY er ikke en PEM-nøkkel");
});

// --- Secrets, kode og Apple-ID ---

Deno.test("alle fire secrets må finnes, ellers listes de som mangler", () => {
  const env: Record<string, string> = {
    APPLE_TEAM_ID: "TEAM123456",
    APPLE_KEY_ID: " KEY1234567 ",
    APPLE_PRIVATE_KEY: "pem",
    APPLE_CLIENT_ID: "com.dashdash18.app",
  };
  const full = appleConfigFrom((n) => env[n]);
  eq(full.missing, []);
  is(full.config?.keyId, "KEY1234567");
  const partial = appleConfigFrom((n) => (n === "APPLE_KEY_ID" || n === "APPLE_PRIVATE_KEY" ? undefined : env[n]));
  is(partial.config, null);
  eq(partial.missing, ["APPLE_KEY_ID", "APPLE_PRIVATE_KEY"]);
  eq(appleConfigFrom(() => "  ").missing.length, 4);
});

Deno.test("koden leses fra forespørselen bare når den ser riktig ut", () => {
  is(appleCodeFrom({ confirm: "SLETT", appleAuthorizationCode: " c0de.0.abc " }), "c0de.0.abc");
  is(appleCodeFrom({ confirm: "SLETT" }), null);
  is(appleCodeFrom({ appleAuthorizationCode: "" }), null);
  is(appleCodeFrom({ appleAuthorizationCode: 42 }), null);
  is(appleCodeFrom({ appleAuthorizationCode: "a b" }), null);
  is(appleCodeFrom({ appleAuthorizationCode: "x".repeat(2000) }), null);
  is(appleCodeFrom(null), null);
});

Deno.test("Apple-ID-en hentes fra identitetene til brukeren", () => {
  is(
    appleSubjectOf({
      identities: [{ provider: "email", id: "u" }, { provider: "apple", identity_data: { sub: SUB } }],
    }),
    SUB,
  );
  is(appleSubjectOf({ identities: [{ provider: "apple", id: SUB, identity_data: {} }] }), SUB);
  is(appleSubjectOf({ identities: [{ provider: "email", id: "u", identity_data: { sub: "u" } }] }), null);
  is(appleSubjectOf({ identities: [] }), null);
  is(appleSubjectOf({}), null);
  is(appleSubjectOf(null), null);
});

Deno.test("sub leses fra ID-tokenet", () => {
  is(subjectFromIdToken(idToken(SUB)), SUB);
  is(subjectFromIdToken("a.b"), null);
  is(subjectFromIdToken("a.!!!.c"), null);
  is(subjectFromIdToken(undefined), null);
});

// --- Flyten mot Apple ---

Deno.test("koden byttes mot et token, og refresh-tokenet trekkes tilbake", async () => {
  const { pem, publicKey } = await testKey();
  const { calls, fetcher } = fakeFetch([
    jsonResponse({ access_token: "at", refresh_token: "rt", id_token: idToken(SUB), token_type: "Bearer" }),
    new Response(null, { status: 200 }),
  ]);
  const result = await revokeAppleToken({
    code: "kode1",
    appleSubject: SUB,
    config: config(pem),
    fetcher,
    now: () => NOW_MS,
  });
  eq(result, { outcome: "revoked" });
  is(calls.length, 2);

  is(calls[0].url, APPLE_TOKEN_URL);
  eq(Object.keys(calls[0].params).sort(), ["client_id", "client_secret", "code", "grant_type"]);
  is(calls[0].params.client_id, "com.dashdash18.app");
  is(calls[0].params.code, "kode1");
  is(calls[0].params.grant_type, "authorization_code");

  is(calls[1].url, APPLE_REVOKE_URL);
  is(calls[1].params.token, "rt");
  is(calls[1].params.token_type_hint, "refresh_token");
  is(calls[1].params.client_id, "com.dashdash18.app");

  // Samme client secret i begge kall, og den er signert med nøkkelen.
  const secret = calls[0].params.client_secret;
  is(calls[1].params.client_secret, secret);
  const [h, c, s] = secret.split(".");
  is(
    await crypto.subtle.verify(
      { name: "ECDSA", hash: "SHA-256" },
      publicKey,
      fromBase64url(s),
      new TextEncoder().encode(`${h}.${c}`),
    ),
    true,
  );
});

Deno.test("uten refresh-token trekkes access-tokenet tilbake", async () => {
  const { pem } = await testKey();
  const { calls, fetcher } = fakeFetch([
    jsonResponse({ access_token: "at", id_token: idToken(SUB) }),
    new Response(null, { status: 200 }),
  ]);
  eq(await revokeAppleToken({ code: "k", appleSubject: SUB, config: config(pem), fetcher }), { outcome: "revoked" });
  is(calls[1].params.token, "at");
  is(calls[1].params.token_type_hint, "access_token");
});

Deno.test("feil i token-kallet gir «failed» og ingen revoke", async () => {
  const { pem } = await testKey();
  const { calls, fetcher } = fakeFetch([jsonResponse({ error: "invalid_grant" }, 400)]);
  eq(await revokeAppleToken({ code: "brukt", appleSubject: SUB, config: config(pem), fetcher }), {
    outcome: "failed",
    detail: "token 400 invalid_grant",
  });
  is(calls.length, 1);
});

Deno.test("feil i revoke-kallet gir «failed»", async () => {
  const { pem } = await testKey();
  const { fetcher } = fakeFetch([
    jsonResponse({ refresh_token: "rt", id_token: idToken(SUB) }),
    new Response("Service Unavailable", { status: 503 }),
  ]);
  eq(await revokeAppleToken({ code: "k", appleSubject: SUB, config: config(pem), fetcher }), {
    outcome: "failed",
    detail: "revoke 503",
  });
});

Deno.test("nettverksfeil kastes ikke videre", async () => {
  const { pem } = await testKey();
  const { fetcher } = fakeFetch([new TypeError("dns error")]);
  eq(await revokeAppleToken({ code: "k", appleSubject: SUB, config: config(pem), fetcher }), {
    outcome: "failed",
    detail: "dns error",
  });
});

Deno.test("en ødelagt nøkkel kastes ikke videre", async () => {
  const { calls, fetcher } = fakeFetch([]);
  const result = await revokeAppleToken({ code: "k", appleSubject: SUB, config: config("søppel"), fetcher });
  is(result.outcome, "failed");
  is(calls.length, 0);
});

Deno.test("Apple som ikke svarer, gir opp etter tidsgrensen", async () => {
  const { pem } = await testKey();
  const fetcher = (_url: string, init: RequestInit) =>
    new Promise<Response>((_resolve, reject) => {
      init.signal?.addEventListener("abort", () => reject(new Error("tidsavbrudd")));
    });
  const result = await revokeAppleToken({ code: "k", appleSubject: SUB, config: config(pem), fetcher, timeoutMs: 20 });
  eq(result, { outcome: "failed", detail: "tidsavbrudd" });
});

Deno.test("en kode fra en annen Apple-ID trekkes ikke tilbake", async () => {
  const { pem } = await testKey();
  const { calls, fetcher } = fakeFetch([jsonResponse({ refresh_token: "rt", id_token: idToken("en.annen.id") })]);
  eq(await revokeAppleToken({ code: "k", appleSubject: SUB, config: config(pem), fetcher }), {
    outcome: "skipped_other_apple_id",
  });
  is(calls.length, 1);
});

Deno.test("uten Apple, uten kode eller uten secrets kalles ikke Apple", async () => {
  const { pem } = await testKey();
  const { calls, fetcher } = fakeFetch([]);
  eq(await revokeAppleToken({ code: "k", appleSubject: null, config: config(pem), fetcher }), {
    outcome: "skipped_not_apple",
  });
  eq(await revokeAppleToken({ code: null, appleSubject: SUB, config: config(pem), fetcher }), {
    outcome: "skipped_no_code",
  });
  eq(await revokeAppleToken({ code: "k", appleSubject: SUB, config: null, fetcher }), { outcome: "skipped_no_config" });
  is(calls.length, 0);
});

Deno.test("logglinja nevner manglende secrets ved navn, aldri verdier", () => {
  is(
    revokeLogLine({ outcome: "skipped_no_config" }, ["APPLE_KEY_ID", "APPLE_PRIVATE_KEY"]),
    "apple-revoke: hoppet over, mangler secrets APPLE_KEY_ID, APPLE_PRIVATE_KEY",
  );
  is(
    revokeLogLine({ outcome: "failed", detail: "token 400 invalid_grant" }),
    "apple-revoke: feilet (token 400 invalid_grant), slettingen fortsetter",
  );
  is(revokeLogLine({ outcome: "revoked" }), "apple-revoke: tokenet er trukket tilbake");
});
