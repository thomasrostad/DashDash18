// Tilbaketrekking av Logg inn med Apple når kontoen slettes (App Review 5.1.1(v) og 4.8).
//
// Appen ber om en fersk Apple-innlogging rett før slettingen og sender `authorizationCode`
// med i forespørselen. Her byttes koden mot et token hos Apple (/auth/token), og tokenet
// trekkes tilbake (/auth/revoke). Da forsvinner Atten fra «Logg inn med Apple» i
// innstillingene til brukeren. Ingen Apple-token lagres noe sted.
//
// Secrets (Supabase → Edge Functions → Secrets), aldri i repoet:
//   APPLE_TEAM_ID      10 tegn, Team ID
//   APPLE_KEY_ID       10 tegn, nøkkelen fra Apple Developer → Keys (Sign in with Apple)
//   APPLE_PRIVATE_KEY  innholdet i AuthKey_XXXXXXXXXX.p8 (PEM, linjeskift eller \n)
//   APPLE_CLIENT_ID    com.dashdash18.app (bundle-id, samme som Client ID i Supabase Auth)
//
// Feil hos Apple stopper aldri slettingen: alt her ender i et utfall som logges.
// Bare WebCrypto og fetch, så modulen kan testes uten nettverk (apple_test.ts).

export const APPLE_TOKEN_URL = "https://appleid.apple.com/auth/token";
export const APPLE_REVOKE_URL = "https://appleid.apple.com/auth/revoke";
export const APPLE_AUDIENCE = "https://appleid.apple.com";

/** Client secret-en lever kort: den lages for hvert kall (Apple tillater opptil seks måneder). */
export const CLIENT_SECRET_TTL_SECONDS = 5 * 60;

/** Så lenge vi venter på Apple før vi gir opp og lar slettingen bli ferdig. */
export const APPLE_TIMEOUT_MS = 10_000;

/** Lengste kode vi godtar fra appen (Apple sine er rundt 100 tegn). */
export const MAX_CODE_LENGTH = 1024;

export const APPLE_SECRET_NAMES = ["APPLE_TEAM_ID", "APPLE_KEY_ID", "APPLE_PRIVATE_KEY", "APPLE_CLIENT_ID"] as const;

export interface AppleConfig {
  teamId: string;
  keyId: string;
  privateKeyPem: string;
  clientId: string;
}

/** Konfigurasjonen fra secrets, eller hvilke som mangler. */
export function appleConfigFrom(
  env: (name: string) => string | undefined,
): { config: AppleConfig; missing: [] } | { config: null; missing: string[] } {
  const value = (name: string) => (env(name) ?? "").trim();
  const missing = APPLE_SECRET_NAMES.filter((name) => !value(name));
  if (missing.length > 0) return { config: null, missing };
  return {
    config: {
      teamId: value("APPLE_TEAM_ID"),
      keyId: value("APPLE_KEY_ID"),
      privateKeyPem: value("APPLE_PRIVATE_KEY"),
      clientId: value("APPLE_CLIENT_ID"),
    },
    missing: [],
  };
}

/** Koden fra forespørselen, eller null når den mangler eller ser feil ut. */
export function appleCodeFrom(body: unknown): string | null {
  if (!body || typeof body !== "object") return null;
  const value = (body as Record<string, unknown>).appleAuthorizationCode;
  if (typeof value !== "string") return null;
  const code = value.trim();
  if (!code || code.length > MAX_CODE_LENGTH || /\s/.test(code)) return null;
  return code;
}

/** Apple-ID-en (`sub`) til brukeren, fra identitetene i GET /auth/v1/user. Null uten Apple. */
export function appleSubjectOf(user: unknown): string | null {
  const identities = (user as { identities?: unknown })?.identities;
  if (!Array.isArray(identities)) return null;
  for (const identity of identities) {
    if (!identity || typeof identity !== "object") continue;
    const i = identity as Record<string, unknown>;
    if (String(i.provider ?? "").toLowerCase() !== "apple") continue;
    const data = (i.identity_data ?? {}) as Record<string, unknown>;
    for (const candidate of [data.sub, data.provider_id, i.provider_id, i.id]) {
      if (typeof candidate === "string" && candidate) return candidate;
    }
  }
  return null;
}

export function base64url(bytes: Uint8Array): string {
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function base64urlJson(value: unknown): string {
  return base64url(new TextEncoder().encode(JSON.stringify(value)));
}

function base64urlDecode(text: string): string {
  const padded = text.replace(/-/g, "+").replace(/_/g, "/") + "===".slice((text.length + 3) % 4);
  return atob(padded);
}

/** PKCS#8-bytene fra .p8-fila. Godtar ekte linjeskift og «\n» slik secrets ofte lagres. */
export function pemToPkcs8(pem: string): Uint8Array {
  const body = pem
    .replace(/\\n/g, "\n")
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s+/g, "");
  if (!body || !/^[A-Za-z0-9+/=]+$/.test(body)) throw new Error("APPLE_PRIVATE_KEY er ikke en PEM-nøkkel");
  const bin = atob(body);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

export function importAppleKey(pem: string): Promise<CryptoKey> {
  // `.buffer` er hele nøkkelen (nytt array), og typen godtas av både gamle og nye TypeScript-versjoner.
  const der = pemToPkcs8(pem).buffer as ArrayBuffer;
  return crypto.subtle.importKey("pkcs8", der, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
}

/**
 * Client secret-en Apple vil ha: en JWT signert med ES256.
 * Header {alg: ES256, kid}, claims {iss: team, iat, exp, aud: appleid.apple.com, sub: client id}.
 * WebCrypto gir signaturen som r||s (64 byte), som er formatet JWS bruker.
 */
export async function makeClientSecret(key: CryptoKey, config: AppleConfig, issuedAtSeconds: number): Promise<string> {
  const header = { alg: "ES256", kid: config.keyId };
  const claims = {
    iss: config.teamId,
    iat: issuedAtSeconds,
    exp: issuedAtSeconds + CLIENT_SECRET_TTL_SECONDS,
    aud: APPLE_AUDIENCE,
    sub: config.clientId,
  };
  const signingInput = `${base64urlJson(header)}.${base64urlJson(claims)}`;
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    new TextEncoder().encode(signingInput),
  );
  return `${signingInput}.${base64url(new Uint8Array(signature))}`;
}

/**
 * `sub` fra ID-tokenet i svaret fra /auth/token. Signaturen sjekkes ikke: tokenet kommer rett
 * fra Apple over TLS som svar på vårt eget kall, og brukes bare til å sammenligne Apple-ID-er.
 */
export function subjectFromIdToken(idToken: unknown): string | null {
  if (typeof idToken !== "string") return null;
  const parts = idToken.split(".");
  if (parts.length !== 3) return null;
  try {
    const payload = JSON.parse(base64urlDecode(parts[1])) as { sub?: unknown };
    return typeof payload.sub === "string" && payload.sub ? payload.sub : null;
  } catch {
    return null;
  }
}

export type RevokeOutcome =
  | "revoked"
  | "skipped_no_code"
  | "skipped_not_apple"
  | "skipped_no_config"
  | "skipped_other_apple_id"
  | "failed";

export interface RevokeResult {
  outcome: RevokeOutcome;
  /** Kort forklaring til loggen. Aldri tokens eller nøkler. */
  detail?: string;
}

type FetchLike = (input: string, init: RequestInit) => Promise<Response>;

export interface RevokeInput {
  /** Fersk `authorizationCode` fra appen, eller null. */
  code: string | null;
  /** Apple-ID-en kontoen er koblet til (`appleSubjectOf`), eller null. */
  appleSubject: string | null;
  config: AppleConfig | null;
  fetcher?: FetchLike;
  now?: () => number;
  timeoutMs?: number;
}

function form(values: Record<string, string>): string {
  return new URLSearchParams(values).toString();
}

async function errorText(response: Response): Promise<string> {
  let reason = "";
  try {
    const body = await response.json() as { error?: unknown };
    reason = typeof body?.error === "string" ? body.error : "";
  } catch {
    // ikke JSON
  }
  return `${response.status}${reason ? ` ${reason}` : ""}`;
}

/**
 * Bytter koden mot et token og trekker det tilbake. Kaster aldri: alle feil blir et utfall.
 * Brukere uten Apple-innlogging, kall uten kode og manglende secrets hoppes over.
 */
export async function revokeAppleToken(input: RevokeInput): Promise<RevokeResult> {
  if (!input.appleSubject) return { outcome: "skipped_not_apple" };
  if (!input.code) return { outcome: "skipped_no_code" };
  if (!input.config) return { outcome: "skipped_no_config" };
  const config = input.config;
  const fetcher = input.fetcher ?? fetch;
  const now = input.now ?? Date.now;
  const timeoutMs = input.timeoutMs ?? APPLE_TIMEOUT_MS;
  const post = (url: string, values: Record<string, string>) =>
    fetcher(url, {
      method: "POST",
      headers: { "content-type": "application/x-www-form-urlencoded", accept: "application/json" },
      body: form(values),
      signal: AbortSignal.timeout(timeoutMs),
    });

  try {
    const key = await importAppleKey(config.privateKeyPem);
    const clientSecret = await makeClientSecret(key, config, Math.floor(now() / 1000));

    // 1. Koden mot token.
    const tokenResponse = await post(APPLE_TOKEN_URL, {
      client_id: config.clientId,
      client_secret: clientSecret,
      code: input.code,
      grant_type: "authorization_code",
    });
    if (!tokenResponse.ok) return { outcome: "failed", detail: `token ${await errorText(tokenResponse)}` };
    const tokens = await tokenResponse.json() as {
      refresh_token?: unknown;
      access_token?: unknown;
      id_token?: unknown;
    };

    // Koden må høre til samme Apple-ID som kontoen. Ellers rører vi ikke tokenet.
    const subject = subjectFromIdToken(tokens.id_token);
    if (subject !== input.appleSubject) return { outcome: "skipped_other_apple_id" };

    const [token, hint] = typeof tokens.refresh_token === "string" && tokens.refresh_token
      ? [tokens.refresh_token, "refresh_token"]
      : typeof tokens.access_token === "string" && tokens.access_token
      ? [tokens.access_token, "access_token"]
      : [null, null];
    if (!token || !hint) return { outcome: "failed", detail: "token uten refresh_token og access_token" };

    // 2. Trekk tilbake. Apple svarer 200 med tomt innhold.
    const revokeResponse = await post(APPLE_REVOKE_URL, {
      client_id: config.clientId,
      client_secret: clientSecret,
      token,
      token_type_hint: hint,
    });
    if (!revokeResponse.ok) return { outcome: "failed", detail: `revoke ${await errorText(revokeResponse)}` };
    await revokeResponse.body?.cancel();
    return { outcome: "revoked" };
  } catch (error) {
    return { outcome: "failed", detail: String((error as Error)?.message ?? error).slice(0, 200) };
  }
}

/** Logglinja for utfallet. `missing` er secrets som mangler (bare navnene). */
export function revokeLogLine(result: RevokeResult, missing: string[] = []): string {
  switch (result.outcome) {
    case "revoked":
      return "apple-revoke: tokenet er trukket tilbake";
    case "skipped_not_apple":
      return "apple-revoke: hoppet over, kontoen har ikke Apple-innlogging";
    case "skipped_no_code":
      return "apple-revoke: hoppet over, appen sendte ingen Apple-kode";
    case "skipped_no_config":
      return `apple-revoke: hoppet over, mangler secrets ${missing.join(", ")}`;
    case "skipped_other_apple_id":
      return "apple-revoke: hoppet over, koden hører til en annen Apple-ID enn kontoen";
    case "failed":
      return `apple-revoke: feilet (${result.detail ?? "ukjent"}), slettingen fortsetter`;
  }
}
