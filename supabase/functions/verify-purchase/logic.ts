// Ren logikk for verify-purchase (fase 17, StoreKit 2). Ingen nettverk, så den kan testes med
//   deno test supabase/functions/verify-purchase/
//
// Transaksjonen hentes av serveren selv fra App Store Server API (appstore.ts) over TLS, med
// vår egen nøkkel. Svaret (signedTransactionInfo) kommer da rett fra Apple, og vi leser
// innholdet uten å stole på noe appen har sendt utover transaksjons-id-en.

/** Produktene appen selger (samme som PurchaseCatalog i Swift og DashDash.storekit). */
export const PRODUCTS: Record<string, "consumable" | "non_consumable" | "subscription"> = {
  "no.dashdash.turnering.sesong": "consumable",
  "no.dashdash.turnering.ar": "subscription",
};

/** Innholdet i signedTransactionInfo (JWSTransactionDecodedPayload), feltene vi bruker. */
export interface TransactionPayload {
  transactionId: string;
  originalTransactionId: string;
  bundleId: string;
  productId: string;
  type?: string;
  purchaseDate?: number;
  expiresDate?: number;
  revocationDate?: number;
  appAccountToken?: string;
  environment?: string;
}

/** Det record_purchase (sql/023) tar imot. */
export interface PurchaseRecord {
  profile_id: string;
  product_id: string;
  product_kind: string;
  original_transaction_id: string;
  transaction_id: string;
  environment: "sandbox" | "production";
  status: "active" | "expired" | "revoked" | "refunded";
  purchased_at: string | null;
  expires_at: string | null;
  revoked_at: string | null;
  app_account_token: string | null;
  competition_id: string | null;
  club_id: string | null;
}

export type PurchaseErrorCode = "bad_request" | "wrong_app" | "unknown_product" | "wrong_account" | "sandbox_not_allowed";

export class PurchaseError extends Error {
  readonly code: PurchaseErrorCode;
  constructor(code: PurchaseErrorCode, message: string) {
    super(message);
    this.code = code;
  }
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** Forespørselen fra appen: { transactionId, competitionId?, clubId? }. */
export interface VerifyRequest {
  transactionId: string;
  competitionId: string | null;
  clubId: string | null;
}

export function parseRequest(body: unknown): VerifyRequest {
  if (!body || typeof body !== "object") throw new PurchaseError("bad_request", "Mangler innhold");
  const b = body as Record<string, unknown>;
  const tx = typeof b.transactionId === "string" ? b.transactionId.trim() : String(b.transactionId ?? "");
  if (!/^[0-9]{1,30}$/.test(tx)) throw new PurchaseError("bad_request", "Ugyldig transaksjons-id");
  const optionalUuid = (v: unknown, name: string): string | null => {
    if (v === undefined || v === null || v === "") return null;
    if (typeof v !== "string" || !UUID.test(v)) throw new PurchaseError("bad_request", `Ugyldig ${name}`);
    return v.toLowerCase();
  };
  return {
    transactionId: tx,
    competitionId: optionalUuid(b.competitionId, "turnering"),
    clubId: optionalUuid(b.clubId, "klubb"),
  };
}

/** Leser payload-delen av en JWS uten å sjekke signaturen (bare for svar som kom rett fra Apple). */
export function decodeJwsPayload<T>(jws: string): T {
  const parts = jws.split(".");
  if (parts.length !== 3) throw new Error("Ugyldig JWS");
  const b64 = parts[1].replace(/-/g, "+").replace(/_/g, "/");
  const padded = b64 + "=".repeat((4 - (b64.length % 4)) % 4);
  const bin = atob(padded);
  const bytes = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  return JSON.parse(new TextDecoder().decode(bytes)) as T;
}

const iso = (ms?: number) => (typeof ms === "number" && ms > 0 ? new Date(ms).toISOString() : null);

/** Miljøet til transaksjonen. Bare «Production» er produksjon; alt annet regnes som sandkasse. */
export function environmentOf(tx: TransactionPayload): "sandbox" | "production" {
  return tx.environment === "Production" ? "production" : "sandbox";
}

/** Gjør Apples transaksjon om til en rad for entitlements, eller avviser den.
 *
 * Sikkerhetsrevisjonen 07.10.2026:
 *  - H3: et sandkassekjøp (TestFlight, Xcode) låser ikke opp i produksjon. Det godtas bare når
 *    `allowSandbox` er satt (secret APPSTORE_ALLOW_SANDBOX=true, bare på test-prosjektet).
 *  - M4: appAccountToken MÅ finnes og være den innloggede brukerens id (appen setter den ved
 *    kjøpet). Ellers kunne første konto som sendte en transaksjons-id, ta kjøpet. */
export function recordFromTransaction(
  tx: TransactionPayload,
  options: { userId: string; bundleId: string; request: VerifyRequest; now: Date; allowSandbox: boolean },
): PurchaseRecord {
  if (tx.bundleId !== options.bundleId) throw new PurchaseError("wrong_app", "Kjøpet er fra en annen app");
  const kind = PRODUCTS[tx.productId];
  if (!kind) throw new PurchaseError("unknown_product", `Ukjent produkt ${tx.productId}`);
  const environment = environmentOf(tx);
  if (environment === "sandbox" && !options.allowSandbox) {
    throw new PurchaseError("sandbox_not_allowed", "Testkjøp (sandkasse) låser ikke opp i produksjon");
  }
  if (!tx.appAccountToken || tx.appAccountToken.toLowerCase() !== options.userId.toLowerCase()) {
    throw new PurchaseError("wrong_account", "Kjøpet er ikke gjort av denne kontoen");
  }
  let status: PurchaseRecord["status"] = "active";
  if (tx.revocationDate) status = "refunded";
  else if (kind === "subscription" && tx.expiresDate && tx.expiresDate <= options.now.getTime()) status = "expired";

  return {
    profile_id: options.userId,
    product_id: tx.productId,
    product_kind: kind,
    original_transaction_id: tx.originalTransactionId,
    transaction_id: tx.transactionId,
    environment,
    status,
    purchased_at: iso(tx.purchaseDate),
    expires_at: iso(tx.expiresDate),
    revoked_at: iso(tx.revocationDate),
    app_account_token: tx.appAccountToken.toLowerCase(),
    competition_id: kind === "consumable" ? options.request.competitionId : null,
    club_id: kind === "subscription" ? options.request.clubId : null,
  };
}

/** HTTP-status for en avvisning. */
export function statusForError(error: unknown): number {
  if (error instanceof PurchaseError) return error.code === "bad_request" ? 400 : 422;
  return 502;
}
