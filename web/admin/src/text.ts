// Norske tekster, samme ord som appen (CompetitionText, EveningDates).

const months = ["januar", "februar", "mars", "april", "mai", "juni", "juli", "august", "september", "oktober", "november", "desember"];
const weekdays = ["søndag", "mandag", "tirsdag", "onsdag", "torsdag", "fredag", "lørdag"];

/** «torsdag 8. oktober» (år med når det er et annet enn i år). */
export function longDate(iso: string, today = new Date()): string {
  const [y, m, d] = iso.split("-").map(Number);
  if (!y || !m || !d) return iso;
  const date = new Date(Date.UTC(y, m - 1, d));
  const text = `${weekdays[date.getUTCDay()]} ${d}. ${months[m - 1]}`;
  return y === today.getFullYear() ? text : `${text} ${y}`;
}

export function kindText(kind: string): string {
  return ({ season: "Serie", league: "Liga", cup: "Cup", fun: "Morroturnering", game: "Spill" } as Record<string, string>)[kind] ?? kind;
}

export function statusText(status: string): string {
  return ({ planned: "Planlagt", active: "I gang", finished: "Ferdig" } as Record<string, string>)[status] ?? status;
}

export function memberStatusText(status: string): string {
  return ({ active: "Aktiv", pending: "Venter på godkjenning", archived: "Arkivert" } as Record<string, string>)[status] ?? status;
}

/** «Kl. 18:00» av «18:00:00». */
export function timeText(t: string | null): string | null {
  return t ? `Kl. ${t.slice(0, 5)}` : null;
}

/** Dagens dato i Oslo som «YYYY-MM-DD». */
export function todayISO(now = new Date()): string {
  return new Intl.DateTimeFormat("sv-SE", { timeZone: "Europe/Oslo" }).format(now);
}

// MARK: - Feiltekst

/** Feilkodene databasen bruker med egen norsk tekst (`raise ... using errcode` i sql/; P0001 er raise uten kode). */
const OWN_ERROR_CODES = new Set(["P0001", "P0002", "P0099", "22023", "23503", "23505", "23514", "42501", "54000", "55000", "DDB01", "DDB02", "DDOK1", "DDT47", "ZZ035"]);
/** Engelsk tekst fra Postgres, PostgREST og nettleseren, også når koden er en av de over. */
const TECHNICAL_TEXT = /permission denied|duplicate key|violates|relation "|column "|does not exist|JWT|syntax error|invalid input|schema cache|Could not find|Cannot read prop|is not a function/i;

export const GENERIC_ERROR = "Noe gikk galt. Prøv igjen, eller last inn siden på nytt.";

/** Teksten i feilen når den er skrevet for folk (norsk fra databasen eller fra oss). Ellers en kort norsk tekst, og detaljen logges. */
export function plainErrorText(e: unknown): string {
  const err = e as { name?: unknown; code?: unknown; message?: unknown } | null;
  const message = typeof err?.message === "string" ? err.message : "";
  const code = typeof err?.code === "string" ? err.code : null;
  const technical = !message || (code !== null && !OWN_ERROR_CODES.has(code)) || TECHNICAL_TEXT.test(message)
    || /^(TypeError|ReferenceError|SyntaxError|RangeError)$/.test(String(err?.name ?? ""));
  if (!technical) return message;
  console.error(e);
  return GENERIC_ERROR;
}
