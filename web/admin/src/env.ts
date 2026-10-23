// Miljøet bygget snakker med: test eller prod. Samme regler som AppConfig i appen.
// Miljøet er Vite-modusen (`--mode test` / `--mode prod`), og verdiene leses bare fra
// `env/<miljø>/.env` (utenfor git), så test og prod aldri blandes. Ren logikk; brukes både av
// vite.config.ts (bygget stopper) og supabase.ts (siden viser feilen).

import { normalizeSiteKey } from "../../atten-lenker/src/captcha.ts";

export type AttenEnv = "test" | "prod";

/** Atten Prod. Test er `tsekialrxuhrugscosgi`. */
export const PROD_REF = "wxabhadvuzyrmndxpuza";

/** Modusen som miljø, eller null når den er ukjent (f.eks. `development`). */
export function envFromMode(mode: string): AttenEnv | null {
  return mode === "test" || mode === "prod" ? mode : null;
}

/** Prosjekt-ref-en fra adressen, f.eks. `tsekialrxuhrugscosgi`. */
export function projectRef(url: string): string {
  try {
    return new URL(url).host.split(".")[0] ?? "";
  } catch {
    return "";
  }
}

/** Ny hemmelig nøkkel (`sb_secret_…`) eller gammel JWT-nøkkel med rollen `service_role`. Går forbi RLS. */
export function isSecretKey(key: string): boolean {
  if (key.startsWith("sb_secret_")) return true;
  const parts = key.split(".");
  if (!key.startsWith("eyJ") || parts.length !== 3) return false;
  try {
    const payload = parts[1].replace(/-/g, "+").replace(/_/g, "/");
    const claims = JSON.parse(atob(payload + "=".repeat((4 - (payload.length % 4)) % 4)));
    return claims?.role === "service_role";
  } catch {
    return false;
  }
}

export interface EnvValues {
  VITE_SUPABASE_URL?: string;
  VITE_SUPABASE_KEY?: string;
  VITE_TURNSTILE_SITE_KEY?: string;
}

export interface WebConfig {
  env: AttenEnv;
  url: string;
  key: string;
  /** Site key for Turnstile. Uten den er CAPTCHA av, som `CaptchaFeature` i appen. */
  turnstileSiteKey: string | null;
}

/** Konfigen for modusen, eller en norsk feiltekst. */
export function readConfig(mode: string, values: EnvValues): WebConfig | { error: string } {
  const env = envFromMode(mode);
  if (!env) return { error: `Ukjent miljø «${mode}». Bygg med --mode test eller --mode prod.` };
  const file = `env/${env}/.env`;
  const url = values.VITE_SUPABASE_URL?.trim() ?? "";
  const key = values.VITE_SUPABASE_KEY?.trim() ?? "";
  if (!url || !key) return { error: `Mangler VITE_SUPABASE_URL eller VITE_SUPABASE_KEY i ${file} (se .env.example).` };
  if (!url.startsWith("https://")) return { error: `VITE_SUPABASE_URL i ${file} må starte med https://.` };
  // Hindrer at prod havner bak test-navnet, eller omvendt.
  const isProd = projectRef(url) === PROD_REF;
  if (env === "prod" && !isProd) return { error: `${file} peker ikke på prod (${PROD_REF}).` };
  if (env === "test" && isProd) return { error: `${file} peker på prod. Bruk --mode prod.` };
  if (isSecretKey(key)) return { error: `VITE_SUPABASE_KEY i ${file} er den hemmelige nøkkelen. Bruk publishable key.` };
  // Tom: ingen CAPTCHA. Feilskrevet: stopp, så siden ikke går ut med en sjekk som aldri lykkes.
  const rawSiteKey = values.VITE_TURNSTILE_SITE_KEY?.trim() ?? "";
  const turnstileSiteKey = rawSiteKey ? normalizeSiteKey(rawSiteKey) : null;
  if (rawSiteKey && !turnstileSiteKey) return { error: `VITE_TURNSTILE_SITE_KEY i ${file} er ikke en gyldig site key.` };
  return { env, url, key, turnstileSiteKey };
}

/** Veddemål vises bare i test. Appen har dem av i prod etter App Review 2.3.6 (`BetsFeature`). */
export function betsVisible(env: AttenEnv): boolean {
  return env !== "prod";
}
