// Tester for verify-purchase. Kjøres med
//   deno test supabase/functions/verify-purchase/
// Ingen nettverk (App Store etterlignes med en falsk fetch), ingen database.

import { deepStrictEqual as eq, ok, rejects, strictEqual as is, throws } from "node:assert/strict";
import { base64url, fetchSignedTransaction, makeApiToken } from "./appstore.ts";
import {
  decodeJwsPayload,
  parseRequest,
  PurchaseError,
  recordFromTransaction,
  statusForError,
  type TransactionPayload,
} from "./logic.ts";

const USER = "0a000000-0000-0000-0000-00000000000a";
const CUP = "c0000000-0000-0000-0000-000000000001";
const NOW = new Date("2026-10-08T12:00:00Z");
const BUNDLE = "com.dashdash18.app";

const tx = (over: Partial<TransactionPayload> = {}): TransactionPayload => ({
  transactionId: "2000000001",
  originalTransactionId: "2000000001",
  bundleId: BUNDLE,
  productId: "no.dashdash.turnering.sesong",
  type: "Consumable",
  purchaseDate: Date.parse("2026-10-08T11:59:00Z"),
  appAccountToken: USER.toUpperCase(),
  environment: "Sandbox",
  ...over,
});

const options = (body: unknown = { transactionId: "2000000001", competitionId: CUP }) => ({
  userId: USER,
  bundleId: BUNDLE,
  request: parseRequest(body),
  now: NOW,
});

Deno.test("forespørselen: transaksjons-id er tall, turnering og klubb er uuid", () => {
  eq(parseRequest({ transactionId: "123", competitionId: CUP.toUpperCase() }), {
    transactionId: "123",
    competitionId: CUP,
    clubId: null,
  });
  eq(parseRequest({ transactionId: 456 }).transactionId, "456");
  throws(() => parseRequest({ transactionId: "abc" }), PurchaseError);
  throws(() => parseRequest({ transactionId: "1", competitionId: "drop table" }), PurchaseError);
  throws(() => parseRequest(null), PurchaseError);
});

Deno.test("et forbrukbart kjøp kobles til turneringen", () => {
  const record = recordFromTransaction(tx(), options());
  is(record.status, "active");
  is(record.product_kind, "consumable");
  is(record.competition_id, CUP);
  is(record.club_id, null);
  is(record.environment, "sandbox");
  is(record.app_account_token, USER);
  is(record.purchased_at, "2026-10-08T11:59:00.000Z");
});

Deno.test("feil app, ukjent produkt og annen konto avvises", () => {
  throws(() => recordFromTransaction(tx({ bundleId: "com.annen.app" }), options()), (e) => (e as PurchaseError).code === "wrong_app");
  throws(() => recordFromTransaction(tx({ productId: "no.annet" }), options()), (e) => (e as PurchaseError).code === "unknown_product");
  throws(
    () => recordFromTransaction(tx({ appAccountToken: "0b000000-0000-0000-0000-00000000000b" }), options()),
    (e) => (e as PurchaseError).code === "wrong_account",
  );
  is(statusForError(new PurchaseError("wrong_account", "x")), 422);
  is(statusForError(new PurchaseError("bad_request", "x")), 400);
  is(statusForError(new Error("nett")), 502);
});

Deno.test("refusjon og utløpt abonnement", () => {
  is(recordFromTransaction(tx({ revocationDate: Date.parse("2026-10-08T11:00:00Z") }), options()).status, "refunded");
  const sub = (expires: string) =>
    recordFromTransaction(
      tx({ productId: "no.dashdash.turnering.ar", type: "Auto-Renewable Subscription", expiresDate: Date.parse(expires) }),
      options({ transactionId: "1", clubId: CUP }),
    );
  is(sub("2026-10-01T00:00:00Z").status, "expired");
  const active = sub("2027-10-01T00:00:00Z");
  is(active.status, "active");
  is(active.product_kind, "subscription");
  is(active.competition_id, null);
  is(active.club_id, CUP);
});

Deno.test("JWS-payload leses", () => {
  const payload = base64url(new TextEncoder().encode(JSON.stringify({ productId: "ø", n: 1 })));
  eq(decodeJwsPayload(`x.${payload}.y`), { productId: "ø", n: 1 });
  throws(() => decodeJwsPayload("bare.to"));
});

Deno.test("App Store: produksjon først, sandkassen ved 404", async () => {
  const calls: string[] = [];
  const fake = (url: string) => {
    calls.push(url);
    if (url.includes("sandbox")) return Promise.resolve(new Response(JSON.stringify({ signedTransactionInfo: "a.b.c" })));
    return Promise.resolve(new Response("{}", { status: 404 }));
  };
  const result = await fetchSignedTransaction("42", "token", fake);
  eq(result, { signedTransactionInfo: "a.b.c", environment: "sandbox" });
  is(calls.length, 2);
  ok(calls[0].startsWith("https://api.storekit.itunes.apple.com/inApps/v1/transactions/42"));
  await rejects(fetchSignedTransaction("42", "t", () => Promise.resolve(new Response("{}", { status: 404 }))));
  await rejects(fetchSignedTransaction("42", "t", () => Promise.resolve(new Response("nei", { status: 401 }))));
});

Deno.test("JWT til App Store Server API er ES256 med riktige claims", async () => {
  const pair = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
  const pkcs8 = new Uint8Array(await crypto.subtle.exportKey("pkcs8", pair.privateKey));
  let bin = "";
  for (const b of pkcs8) bin += String.fromCharCode(b);
  const pem = `-----BEGIN PRIVATE KEY-----\n${btoa(bin)}\n-----END PRIVATE KEY-----`;
  const token = await makeApiToken({ issuerId: "iss", keyId: "KEY1234567", privateKeyPem: pem, bundleId: BUNDLE }, 1000);
  const [h, c, s] = token.split(".");
  eq(decodeJwsPayload(`x.${h}.y`), { alg: "ES256", kid: "KEY1234567", typ: "JWT" });
  eq(decodeJwsPayload(`x.${c}.y`), { iss: "iss", iat: 1000, exp: 2200, aud: "appstoreconnect-v1", bid: BUNDLE });
  const sig = Uint8Array.from(atob(s.replace(/-/g, "+").replace(/_/g, "/") + "==".slice(0, (4 - (s.length % 4)) % 4)), (ch) => ch.charCodeAt(0));
  ok(await crypto.subtle.verify({ name: "ECDSA", hash: "SHA-256" }, pair.publicKey, sig, new TextEncoder().encode(`${h}.${c}`)));
});
