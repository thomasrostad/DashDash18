// CAPTCHA ved innlogging med e-postkode, som `CaptchaFeature` i appen (#169). Appen viser Turnstile
// via siden /captcha i web/atten-lenker; her ligger widgeten rett på innloggingssiden, med samme
// skript og samme site key-regel. Ren logikk her; widgeten står i Turnstile.tsx.

export { TURNSTILE_SCRIPT } from "../../atten-lenker/src/captcha.ts";

/** Feiltekstene fra appen (CaptchaError.message), uten Apple-innlogging som web ikke har. */
export const CAPTCHA_TEXT = {
  offline: "Ingen kontakt med nettet. Sjekk nettet og prøv igjen.",
  pageUnavailable: "Sjekken kunne ikke lastes. Vent litt og prøv igjen.",
  misconfigured: "Sjekken virker ikke akkurat nå. Prøv igjen senere.",
  failed: "Vi fikk ikke bekreftet at du er et menneske. Prøv igjen.",
  timedOut: "Sjekken tok for lang tid. Prøv igjen.",
} as const;

/** Feilkodene til Turnstile: 110xxx og 400xxx er oppsettet (nøkkel, domene), 200500 er at rammen
 *  ikke lastet, `load` er at skriptet ikke kom fram. Resten er at sjekken ikke gikk. */
export function captchaErrorText(code: string): string {
  if (code === "load" || code === "200500") return CAPTCHA_TEXT.pageUnavailable;
  if (code.startsWith("110") || code.startsWith("400")) return CAPTCHA_TEXT.misconfigured;
  return CAPTCHA_TEXT.failed;
}

/** Valgene til signInWithOtp. Med CAPTCHA på må tokenet være med, og det kan bare brukes én gang.
 *  Ingen nye brukere fra web (logg inn i appen første gang). */
export function otpOptions(captchaToken: string | null): { shouldCreateUser: false; captchaToken?: string } {
  return captchaToken ? { shouldCreateUser: false, captchaToken } : { shouldCreateUser: false };
}

/** «Send kode» er klar: gyldig e-post, og tokenet når CAPTCHA er på. */
export function canSendCode(email: string, captchaOn: boolean, token: string | null): boolean {
  return email.includes("@") && (!captchaOn || !!token);
}
