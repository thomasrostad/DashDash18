// Tester for APNs-klienten uten nettverk: JWT-en, adressen, hodene og
// fornying av tokenet. Nøkkelen lages i testen, aldri en ekte .p8.
//   deno test supabase/functions/push-send/

import { deepStrictEqual as eq, ok, strictEqual as is } from "node:assert/strict";
import { ApnsClient, base64url, makeProviderToken, pemToPkcs8, sendAll } from "./apns.ts";
import type { PushNotification } from "./logic.ts";

async function testKey() {
  const pair = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
  const pkcs8 = new Uint8Array(await crypto.subtle.exportKey("pkcs8", pair.privateKey));
  const b64 = btoa(String.fromCharCode(...pkcs8));
  const pem = `-----BEGIN PRIVATE KEY-----\n${b64.match(/.{1,64}/g)!.join("\n")}\n-----END PRIVATE KEY-----`;
  return { pem, publicKey: pair.publicKey };
}

function decodePart(part: string): unknown {
  const b64 = part.replace(/-/g, "+").replace(/_/g, "/");
  return JSON.parse(atob(b64 + "=".repeat((4 - b64.length % 4) % 4)));
}

function fromBase64url(s: string): Uint8Array {
  const b64 = s.replace(/-/g, "+").replace(/_/g, "/");
  const bin = atob(b64 + "=".repeat((4 - b64.length % 4) % 4));
  return Uint8Array.from(bin, (c) => c.charCodeAt(0));
}

const NOTE: PushNotification = {
  memberId: "m1",
  token: "ab".repeat(32),
  environment: "sandbox",
  title: "Golfgutu",
  body: "🦅 Anders eagle på hull 5",
  category: "score",
  threadId: "club-1",
  collapseId: "lead-r1",
  data: { type: "activity", activity_id: "a1" },
};

Deno.test("base64url uten fyll og med URL-tegn", () => {
  is(base64url(new Uint8Array([251, 255, 191])), "-_-_");
  is(base64url(new Uint8Array([1])), "AQ");
});

Deno.test("PEM med «\\n» som tekst (slik secrets ofte lagres) gir samme bytes", async () => {
  const { pem } = await testKey();
  eq(pemToPkcs8(pem.replace(/\n/g, "\\n")), pemToPkcs8(pem));
});

Deno.test("PEM som ikke er en nøkkel gir en tydelig feil", () => {
  let message = "";
  try {
    pemToPkcs8("ikke en nøkkel!");
  } catch (e) {
    message = (e as Error).message;
  }
  is(message, "APNS_PRIVATE_KEY er ikke en PEM-nøkkel");
});

Deno.test("provider-tokenet er en ES256-JWT med kid, iss og iat, og signaturen holder", async () => {
  const { pem, publicKey } = await testKey();
  const key = await crypto.subtle.importKey("pkcs8", pemToPkcs8(pem), { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const jwt = await makeProviderToken(key, "ABC123DEFG", "TEAM123456", 1_760_000_000);
  const [h, c, s] = jwt.split(".");
  eq(decodePart(h), { alg: "ES256", kid: "ABC123DEFG" });
  eq(decodePart(c), { iss: "TEAM123456", iat: 1_760_000_000 });
  const signature = fromBase64url(s);
  is(signature.length, 64);
  ok(await crypto.subtle.verify({ name: "ECDSA", hash: "SHA-256" }, publicKey, signature, new TextEncoder().encode(`${h}.${c}`)));
});

Deno.test("sender til riktig vert med riktige hoder, og gjenbruker tokenet", async () => {
  const { pem } = await testKey();
  const calls: { url: string; init: RequestInit }[] = [];
  const fakeFetch = (url: string, init: RequestInit) => {
    calls.push({ url, init });
    return Promise.resolve(new Response(null, { status: 200 }));
  };
  const now = 1_760_000_000_000;
  const client = new ApnsClient({ keyId: "KEY", teamId: "TEAM", privateKeyPem: pem, bundleId: "no.dashdash18.app" }, fakeFetch, () => now);
  eq(await client.send(NOTE), { token: NOTE.token, status: 200, reason: null });
  await client.send({ ...NOTE, environment: "production", collapseId: undefined });

  is(calls[0].url, `https://api.sandbox.push.apple.com/3/device/${NOTE.token}`);
  is(calls[1].url, `https://api.push.apple.com/3/device/${NOTE.token}`);
  const headers = calls[0].init.headers as Record<string, string>;
  is(headers["apns-topic"], "no.dashdash18.app");
  is(headers["apns-push-type"], "alert");
  is(headers["apns-priority"], "10");
  is(headers["apns-collapse-id"], "lead-r1");
  is(headers["apns-expiration"], String(now / 1000 + 3600));
  ok(headers.authorization.startsWith("bearer "));
  is((calls[1].init.headers as Record<string, string>)["apns-collapse-id"], undefined);
  is((calls[1].init.headers as Record<string, string>).authorization, headers.authorization);
  eq(JSON.parse(calls[0].init.body as string).aps.alert, { title: "Golfgutu", body: "🦅 Anders eagle på hull 5" });
});

Deno.test("nytt token etter 50 minutter og etter ExpiredProviderToken", async () => {
  const { pem } = await testKey();
  let now = 1_760_000_000_000;
  const auths: string[] = [];
  let expireNext = false;
  const fakeFetch = (_url: string, init: RequestInit) => {
    auths.push((init.headers as Record<string, string>).authorization);
    if (expireNext) {
      expireNext = false;
      return Promise.resolve(new Response(JSON.stringify({ reason: "ExpiredProviderToken" }), { status: 403 }));
    }
    return Promise.resolve(new Response(null, { status: 200 }));
  };
  const client = new ApnsClient({ keyId: "KEY", teamId: "TEAM", privateKeyPem: pem, bundleId: "b" }, fakeFetch, () => now);
  await client.send(NOTE);
  now += 49 * 60 * 1000;
  await client.send(NOTE);
  is(auths[1], auths[0]);
  now += 2 * 60 * 1000;
  await client.send(NOTE);
  ok(auths[2] !== auths[1]);

  now += 1000;
  expireNext = true;
  const result = await client.send(NOTE);
  is(result.status, 200);
  is(auths.length, 5);
  ok(auths[4] !== auths[3]);
});

Deno.test("grunnen fra APNs leses, og nettverksfeil blir status 0", async () => {
  const { pem } = await testKey();
  const gone = new ApnsClient({ keyId: "K", teamId: "T", privateKeyPem: pem, bundleId: "b" },
    () => Promise.resolve(new Response(JSON.stringify({ reason: "Unregistered" }), { status: 410 })));
  eq(await gone.send(NOTE), { token: NOTE.token, status: 410, reason: "Unregistered" });
  const down = new ApnsClient({ keyId: "K", teamId: "T", privateKeyPem: pem, bundleId: "b" },
    () => Promise.reject(new Error("dns")));
  eq(await down.send(NOTE), { token: NOTE.token, status: 0, reason: "dns" });
});

Deno.test("sendAll beholder rekkefølgen", async () => {
  const client = { send: (n: PushNotification) => Promise.resolve({ token: n.token, status: 200 }) };
  const notes = ["a", "b", "c", "d", "e"].map((t) => ({ ...NOTE, token: t }));
  eq((await sendAll(client, notes, 2)).map((r) => r.token), ["a", "b", "c", "d", "e"]);
  eq(await sendAll(client, []), []);
});
