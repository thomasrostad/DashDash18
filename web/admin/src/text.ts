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
