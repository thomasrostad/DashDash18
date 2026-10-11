// Navnet på klubben fra Enhetsregisteret (Brønnøysundregistrene). Åpent API uten nøkkel, med CORS.
// Samme regler som Enhetsregisteret.swift i appen.

export type BrregResult = { ok: true; name: string } | { ok: false; error: string };

export const BRREG_ERRORS = {
  invalid: "Organisasjonsnummeret må ha 9 siffer.",
  notFound: "Fant ingen enhet med det nummeret.",
  deleted: "Enheten er slettet i Enhetsregisteret.",
  offline: "Ingen kontakt med Enhetsregisteret. Sjekk nettet.",
  failed: "Fikk ikke svar fra Enhetsregisteret. Prøv igjen.",
};

/** Nummeret uten mellomrom, eller null når det ikke er 9 siffer. */
export function normalizeOrgNumber(raw: string): string | null {
  const digits = raw.replace(/\s/g, "");
  return /^[0-9]{9}$/.test(digits) ? digits : null;
}

export function brregURL(orgNumber: string): string {
  return `https://data.brreg.no/enhetsregisteret/api/enheter/${orgNumber}`;
}

/** Navnet fra svaret. 400: ugyldig nummer, 404: finnes ikke, 410: slettet. */
export function parseBrreg(status: number, body: unknown): BrregResult {
  if (status === 200) {
    const name = (body as { navn?: unknown } | null)?.navn;
    return typeof name === "string" && name.trim() ? { ok: true, name: name.trim() } : { ok: false, error: BRREG_ERRORS.failed };
  }
  if (status === 400) return { ok: false, error: BRREG_ERRORS.invalid };
  if (status === 404) return { ok: false, error: BRREG_ERRORS.notFound };
  if (status === 410) return { ok: false, error: BRREG_ERRORS.deleted };
  return { ok: false, error: BRREG_ERRORS.failed };
}

export async function lookUpName(raw: string, fetcher: typeof fetch = fetch): Promise<BrregResult> {
  const number = normalizeOrgNumber(raw);
  if (!number) return { ok: false, error: BRREG_ERRORS.invalid };
  let res: Response;
  try {
    res = await fetcher(brregURL(number), { headers: { Accept: "application/json" } });
  } catch {
    return { ok: false, error: BRREG_ERRORS.offline };
  }
  const body = res.status === 200 ? await res.json().catch(() => null) : null;
  return parseBrreg(res.status, body);
}
