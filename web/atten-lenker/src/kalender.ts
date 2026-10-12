// Kalenderabonnement (steg 10, sql/051): dashdash18.com/kalender/<token>.ics.
// Telefonen henter lenken jevnlig (webcal://). Workeren henter kveldene med calendar_feed(token)
// (anon, som TV-siden) og lager iCalendar (RFC 5545). Svaret har ingen personopplysninger:
// bare kveldene (klubb, turnering, dato, tid, sted og notat).
//
// Tid: DTSTART med TZID=Europe/Oslo og en VTIMEZONE for Europe/Oslo (sommertid siste søndag i mars
// og vintertid siste søndag i oktober), så kvelden står kl. 18 norsk tid også om telefonen er i en
// annen tidssone. Kvelder uten starttid blir heldagshendelser. Varighet tre timer (DURATION:PT3H).

import type { TVEnv } from "./tv.ts";

export type CalendarEnv = TVEnv;

/** En kveld slik calendar_feed sender den. */
export interface CalendarEvent {
  id: string;
  club_name: string | null;
  competition_name: string | null;
  competition_kind: string | null;
  date: string; // YYYY-MM-DD
  start_time: string | null; // HH:MM:SS
  venue: string | null;
  note: string | null;
  updated_at: string | null; // ISO 8601 med sone
}

export interface CalendarFeed {
  generated_at?: string;
  time_zone?: string;
  events: CalendarEvent[];
}

export const CALENDAR_NAME = "Atten";
export const TIME_ZONE = "Europe/Oslo";
export const EVENT_DURATION = "PT3H";
export const REFRESH = "PT1H";
const UID_DOMAIN = "dashdash18.com";

/** Tokenet slik serveren lager det: 32 tegn base32 med små bokstaver. Ellers null (gir 404 uten oppslag). */
export function normalizeCalendarToken(raw: string): string | null {
  return /^[a-z2-7]{32}$/.test(raw) ? raw : null;
}

/** TEXT-verdi etter RFC 5545 3.3.11: \ ; , og linjeskift escapes. */
export function escapeText(value: string): string {
  return value
    .replace(/\\/g, "\\\\")
    .replace(/;/g, "\\;")
    .replace(/,/g, "\\,")
    .replace(/\r\n|\r|\n/g, "\\n");
}

const encoder = new TextEncoder();

/**
 * Bretter en innholdslinje etter RFC 5545 3.1: høyst 75 oktetter per linje (uten CRLF), fortsettelsen
 * starter med ett mellomrom. Deler aldri et tegn (æ, ø, å og emoji er flere oktetter i UTF-8).
 */
export function foldLine(line: string): string {
  if (encoder.encode(line).length <= 75) return line;
  const parts: string[] = [];
  let current = "";
  let size = 0;
  let limit = 75;
  for (const char of line) {
    const bytes = encoder.encode(char).length;
    if (size + bytes > limit) {
      parts.push(current);
      current = "";
      size = 0;
      limit = 74; // mellomrommet først på linja teller med
    }
    current += char;
    size += bytes;
  }
  parts.push(current);
  return parts.join("\r\n ");
}

/** 2026-10-12T09:21:13.769177+00:00 → 20261012T092113Z. null når datoen ikke kan leses. */
export function utcStamp(iso: string | Date): string | null {
  const date = iso instanceof Date ? iso : new Date(String(iso).replace(/(\.\d{3})\d+/, "$1"));
  if (Number.isNaN(date.getTime())) return null;
  return date.toISOString().replace(/[-:]/g, "").replace(/\.\d{3}/, "");
}

/** «Golfgutu · Kveld» for sesongen (eller uten turnering), «Golfgutu · Torsdagsligaen» ellers. */
export function eventSummary(event: CalendarEvent): string {
  const club = event.club_name?.trim() || CALENDAR_NAME;
  const comp = event.competition_name?.trim();
  if (!comp || event.competition_kind === "season") return `${club} · Kveld`;
  return `${club} · ${comp}`;
}

function nextDay(date: string): string {
  const [y, m, d] = date.split("-").map(Number);
  const next = new Date(Date.UTC(y, m - 1, d + 1));
  return next.toISOString().slice(0, 10).replace(/-/g, "");
}

const VTIMEZONE = [
  "BEGIN:VTIMEZONE",
  `TZID:${TIME_ZONE}`,
  `X-LIC-LOCATION:${TIME_ZONE}`,
  "BEGIN:DAYLIGHT",
  "TZOFFSETFROM:+0100",
  "TZOFFSETTO:+0200",
  "TZNAME:CEST",
  "DTSTART:19700329T020000",
  "RRULE:FREQ=YEARLY;BYMONTH=3;BYDAY=-1SU",
  "END:DAYLIGHT",
  "BEGIN:STANDARD",
  "TZOFFSETFROM:+0200",
  "TZOFFSETTO:+0100",
  "TZNAME:CET",
  "DTSTART:19701025T030000",
  "RRULE:FREQ=YEARLY;BYMONTH=10;BYDAY=-1SU",
  "END:STANDARD",
  "END:VTIMEZONE",
];

function eventLines(event: CalendarEvent, stamp: string): string[] {
  if (!/^[0-9a-f-]{36}$/i.test(event.id) || !/^\d{4}-\d{2}-\d{2}$/.test(event.date)) return [];
  const day = event.date.replace(/-/g, "");
  const lines = ["BEGIN:VEVENT", `UID:${event.id.toLowerCase()}@${UID_DOMAIN}`, `DTSTAMP:${stamp}`];
  const time = event.start_time && /^(\d{2}):(\d{2})(?::(\d{2}))?/.exec(event.start_time);
  if (time) {
    lines.push(`DTSTART;TZID=${TIME_ZONE}:${day}T${time[1]}${time[2]}${time[3] ?? "00"}`, `DURATION:${EVENT_DURATION}`);
  } else {
    lines.push(`DTSTART;VALUE=DATE:${day}`, `DTEND;VALUE=DATE:${nextDay(event.date)}`);
  }
  lines.push(`SUMMARY:${escapeText(eventSummary(event))}`);
  if (event.venue?.trim()) lines.push(`LOCATION:${escapeText(event.venue.trim())}`);
  const description = [
    event.competition_name?.trim() && event.competition_kind !== "season" ? null : event.competition_name?.trim(),
    event.note?.trim(),
    "Du er påmeldt i Atten.",
  ].filter((x): x is string => Boolean(x));
  lines.push(`DESCRIPTION:${escapeText(description.join("\n"))}`);
  const modified = event.updated_at ? utcStamp(event.updated_at) : null;
  if (modified) lines.push(`LAST-MODIFIED:${modified}`);
  lines.push("STATUS:CONFIRMED", "TRANSP:OPAQUE", "END:VEVENT");
  return lines;
}

/** Hele kalenderen som tekst med CRLF og brettede linjer. Ren funksjon (testes uten nett). */
export function buildICS(feed: CalendarFeed, now: Date = new Date()): string {
  const stamp = utcStamp(now) as string;
  const lines = [
    "BEGIN:VCALENDAR",
    "VERSION:2.0",
    "PRODID:-//DashDash18//Atten//NB",
    "CALSCALE:GREGORIAN",
    "METHOD:PUBLISH",
    `NAME:${CALENDAR_NAME}`,
    `X-WR-CALNAME:${CALENDAR_NAME}`,
    `X-WR-CALDESC:${escapeText("Kveldene du er påmeldt i Atten")}`,
    `X-WR-TIMEZONE:${TIME_ZONE}`,
    `REFRESH-INTERVAL;VALUE=DURATION:${REFRESH}`,
    `X-PUBLISHED-TTL:${REFRESH}`,
    ...VTIMEZONE,
    ...(Array.isArray(feed.events) ? feed.events : []).flatMap((e) => eventLines(e, stamp)),
    "END:VCALENDAR",
  ];
  return lines.map(foldLine).join("\r\n") + "\r\n";
}

/** Kveldene for tokenet, eller null når tokenet er ukjent eller skrudd av (P0002). Kaster ved andre feil. */
export async function fetchCalendarFeed(token: string, env: CalendarEnv): Promise<CalendarFeed | null> {
  if (!env.SUPABASE_URL || !env.SUPABASE_KEY) throw new Error("Workeren mangler SUPABASE_URL eller SUPABASE_KEY.");
  const res = await fetch(`${env.SUPABASE_URL}/rest/v1/rpc/calendar_feed`, {
    method: "POST",
    headers: { apikey: env.SUPABASE_KEY, "Content-Type": "application/json" },
    body: JSON.stringify({ p_token: token }),
  });
  if (!res.ok) {
    const body = (await res.json().catch(() => ({}))) as { code?: string };
    if (body.code === "P0002") return null;
    throw new Error(`calendar_feed svarte ${res.status}`);
  }
  return (await res.json()) as CalendarFeed;
}

const HEADERS: Record<string, string> = {
  "X-Content-Type-Options": "nosniff",
  "Referrer-Policy": "no-referrer",
  "X-Robots-Tag": "noindex",
};

/** Svaret på /kalender/<token>.ics. Lenken er personlig: kort, privat cache. */
export async function calendarResponse(rawToken: string, env: CalendarEnv, isHead: boolean): Promise<Response> {
  const token = normalizeCalendarToken(rawToken);
  const notFound = () => new Response(isHead ? null : "Fant ikke kalenderen. Lag en ny lenke i Atten (Deg → Kalender).\n", {
    status: 404, headers: { ...HEADERS, "Content-Type": "text/plain; charset=utf-8", "Cache-Control": "no-store" } });
  if (!token) return notFound();
  let feed: CalendarFeed | null;
  try {
    feed = await fetchCalendarFeed(token, env);
  } catch {
    return new Response(isHead ? null : "Fikk ikke hentet kalenderen. Prøv igjen senere.\n", {
      status: 502, headers: { ...HEADERS, "Content-Type": "text/plain; charset=utf-8", "Cache-Control": "no-store" } });
  }
  if (!feed) return notFound();
  return new Response(isHead ? null : buildICS(feed), {
    status: 200,
    headers: {
      ...HEADERS,
      "Content-Type": "text/calendar; charset=utf-8",
      "Content-Disposition": 'inline; filename="atten.ics"',
      "Cache-Control": "private, max-age=300",
    },
  });
}
