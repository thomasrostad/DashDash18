// APNs med token-basert autentisering (ES256 JWT fra en .p8-nøkkel).
// Nøkkelen og id-ene leses fra Supabase-secrets i index.ts, aldri fra repoet:
//   APNS_KEY_ID       10 tegn, fra Apple Developer → Keys
//   APNS_TEAM_ID      10 tegn, Team ID
//   APNS_PRIVATE_KEY  innholdet i AuthKey_XXXXXXXXXX.p8 (PEM, linjeskift eller \n)
//   APNS_BUNDLE_ID    appens bundle-id (apns-topic)
//
// Bare WebCrypto og fetch, så modulen kjører i Deno (Edge Functions) og kan
// testes uten nettverk (apns_test.ts sender med en falsk fetch).

import { apnsBody, type PushNotification, type SendResult } from "./logic.ts";

export interface ApnsConfig {
  keyId: string;
  teamId: string;
  privateKeyPem: string;
  bundleId: string;
}

export const APNS_HOSTS = {
  sandbox: "https://api.sandbox.push.apple.com",
  production: "https://api.push.apple.com",
} as const;

/** Apple: lag nytt token høyst hvert 20. minutt, og det varer i en time. */
export const PROVIDER_TOKEN_TTL_SECONDS = 50 * 60;

export function base64url(bytes: Uint8Array): string {
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function base64urlJson(value: unknown): string {
  return base64url(new TextEncoder().encode(JSON.stringify(value)));
}

/** PKCS#8-bytene fra .p8-fila. Godtar ekte linjeskift og «\n» slik secrets ofte lagres. */
export function pemToPkcs8(pem: string): Uint8Array {
  const body = pem
    .replace(/\\n/g, "\n")
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s+/g, "");
  if (!body || !/^[A-Za-z0-9+/=]+$/.test(body)) throw new Error("APNS_PRIVATE_KEY er ikke en PEM-nøkkel");
  const bin = atob(body);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

export function importApnsKey(pem: string): Promise<CryptoKey> {
  return crypto.subtle.importKey(
    "pkcs8",
    pemToPkcs8(pem),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
}

/** Provider-tokenet: header {alg: ES256, kid}, claims {iss: team, iat}. WebCrypto gir r||s (64 byte), som JWS vil ha. */
export async function makeProviderToken(
  key: CryptoKey,
  keyId: string,
  teamId: string,
  issuedAtSeconds: number,
): Promise<string> {
  const signingInput = `${base64urlJson({ alg: "ES256", kid: keyId })}.${base64urlJson({ iss: teamId, iat: issuedAtSeconds })}`;
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    new TextEncoder().encode(signingInput),
  );
  return `${signingInput}.${base64url(new Uint8Array(signature))}`;
}

type FetchLike = (input: string, init: RequestInit) => Promise<Response>;

/** Sender til APNs over HTTP/2 (Deno sin fetch forhandler h2 med Apple). */
export class ApnsClient {
  private readonly config: ApnsConfig;
  private readonly fetcher: FetchLike;
  private readonly now: () => number;
  private key?: Promise<CryptoKey>;
  private cached?: { token: string; issuedAt: number };

  constructor(config: ApnsConfig, fetcher: FetchLike = fetch, now: () => number = Date.now) {
    this.config = config;
    this.fetcher = fetcher;
    this.now = now;
  }

  /** Gjenbrukes i 50 minutter. forceNew etter 403 ExpiredProviderToken. */
  async providerToken(forceNew = false): Promise<string> {
    const nowSeconds = Math.floor(this.now() / 1000);
    if (!forceNew && this.cached && nowSeconds - this.cached.issuedAt < PROVIDER_TOKEN_TTL_SECONDS) {
      return this.cached.token;
    }
    this.key ??= importApnsKey(this.config.privateKeyPem);
    const token = await makeProviderToken(await this.key, this.config.keyId, this.config.teamId, nowSeconds);
    this.cached = { token, issuedAt: nowSeconds };
    return token;
  }

  async send(n: PushNotification): Promise<SendResult> {
    try {
      let result = await this.post(n, await this.providerToken());
      if (result.status === 403 && result.reason === "ExpiredProviderToken") {
        result = await this.post(n, await this.providerToken(true));
      }
      return result;
    } catch (error) {
      // Nettverk eller DNS: midlertidig (status 0 = retry i classifyApnsResponse).
      return { token: n.token, status: 0, reason: String((error as Error)?.message ?? error).slice(0, 100) };
    }
  }

  private async post(n: PushNotification, jwt: string): Promise<SendResult> {
    const headers: Record<string, string> = {
      authorization: `bearer ${jwt}`,
      "apns-topic": this.config.bundleId,
      "apns-push-type": "alert",
      "apns-priority": "10",
      // Et varsel som ikke kom fram innen en time, er ikke verdt å levere.
      "apns-expiration": String(Math.floor(this.now() / 1000) + 3600),
      "content-type": "application/json",
    };
    if (n.collapseId) headers["apns-collapse-id"] = n.collapseId;
    const response = await this.fetcher(`${APNS_HOSTS[n.environment]}/3/device/${n.token}`, {
      method: "POST",
      headers,
      body: JSON.stringify(apnsBody(n)),
    });
    let reason: string | null = null;
    if (response.status !== 200) {
      try {
        reason = (await response.json())?.reason ?? null;
      } catch {
        reason = null;
      }
    } else {
      await response.body?.cancel();
    }
    return { token: n.token, status: response.status, reason };
  }
}

/** Sender alle, høyst `concurrency` om gangen. */
export async function sendAll(
  client: Pick<ApnsClient, "send">,
  notifications: PushNotification[],
  concurrency = 8,
): Promise<SendResult[]> {
  const results: SendResult[] = new Array(notifications.length);
  let next = 0;
  async function worker() {
    while (next < notifications.length) {
      const i = next++;
      results[i] = await client.send(notifications[i]);
    }
  }
  await Promise.all(Array.from({ length: Math.min(concurrency, notifications.length) }, worker));
  return results;
}
