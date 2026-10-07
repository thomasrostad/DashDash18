// App Store Server API: hent én transaksjon (Get Transaction Info).
// Nøkkelen og id-ene leses fra Supabase-secrets i index.ts, aldri fra repoet:
//   APPSTORE_ISSUER_ID    App Store Connect → Users and Access → Integrations → In-App Purchase
//   APPSTORE_KEY_ID       id-en til nøkkelen (10 tegn)
//   APPSTORE_PRIVATE_KEY  innholdet i SubscriptionKey_XXXXXXXXXX.p8 (PEM, linjeskift eller \n)
//   APPSTORE_BUNDLE_ID    appens bundle-id
//
// Bare WebCrypto og fetch. Testes med en falsk fetch (logic_test.ts).

export const HOSTS = {
  production: "https://api.storekit.itunes.apple.com",
  sandbox: "https://api.storekit-sandbox.itunes.apple.com",
} as const;

export interface AppStoreConfig {
  issuerId: string;
  keyId: string;
  privateKeyPem: string;
  bundleId: string;
}

export function base64url(bytes: Uint8Array): string {
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

const base64urlJson = (value: unknown) => base64url(new TextEncoder().encode(JSON.stringify(value)));

export function pemToPkcs8(pem: string): Uint8Array {
  const body = pem
    .replace(/\\n/g, "\n")
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s+/g, "");
  if (!body || !/^[A-Za-z0-9+/=]+$/.test(body)) throw new Error("APPSTORE_PRIVATE_KEY er ikke en PEM-nøkkel");
  const bin = atob(body);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

/** JWT for App Store Server API: ES256, aud appstoreconnect-v1, bid = bundle-id, høyst en time. */
export async function makeApiToken(config: AppStoreConfig, nowSeconds: number): Promise<string> {
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToPkcs8(config.privateKeyPem),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  const header = { alg: "ES256", kid: config.keyId, typ: "JWT" };
  const claims = { iss: config.issuerId, iat: nowSeconds, exp: nowSeconds + 20 * 60, aud: "appstoreconnect-v1", bid: config.bundleId };
  const input = `${base64urlJson(header)}.${base64urlJson(claims)}`;
  const signature = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(input));
  return `${input}.${base64url(new Uint8Array(signature))}`;
}

type FetchLike = (input: string, init: RequestInit) => Promise<Response>;

/**
 * signedTransactionInfo for transaksjonen. Prøver produksjon først og sandkassen ved
 * «finnes ikke» (TestFlight og Xcode bruker sandkassen), som Apple anbefaler.
 */
export async function fetchSignedTransaction(
  transactionId: string,
  token: string,
  fetcher: FetchLike = fetch,
): Promise<{ signedTransactionInfo: string; environment: "production" | "sandbox" }> {
  for (const environment of ["production", "sandbox"] as const) {
    const response = await fetcher(`${HOSTS[environment]}/inApps/v1/transactions/${transactionId}`, {
      method: "GET",
      headers: { authorization: `Bearer ${token}` },
    });
    if (response.status === 404) {
      await response.body?.cancel();
      continue;
    }
    const text = await response.text();
    if (!response.ok) throw new Error(`App Store ${response.status}: ${text.slice(0, 200)}`);
    const body = JSON.parse(text) as { signedTransactionInfo?: string };
    if (!body.signedTransactionInfo) throw new Error("App Store svarte uten transaksjon");
    return { signedTransactionInfo: body.signedTransactionInfo, environment };
  }
  throw new Error("Fant ikke transaksjonen hos App Store");
}
