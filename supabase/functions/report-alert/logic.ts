// Logikken i report-alert (sql/063): sjekk av hemmeligheten, mottakerne, teksten og selve
// kjøringen. Ingen Deno-, nett- eller databaseavhengighet her, så alt kan testes i logic_test.ts.
// SMTP-klienten er push-send sin (../push-send/email.ts), ikke en kopi.

import type { EmailMessage, EmailSender, SmtpConfig } from "../push-send/email.ts";

/** Det report_alert_payload(rapport) gir (sql/063, target_id fra 066). Navn, aldri e-post. */
export interface ReportPayload {
  id: string;
  kind: string;
  /** Innholdets id (sql/066). Mangler før 066 er kjørt. */
  target_id?: string | null;
  reason: string;
  note: string | null;
  excerpt: string | null;
  status: string;
  created_at: string;
  reporter_name: string | null;
  target_name: string | null;
  club_name: string | null;
  competition_name: string | null;
}

/** Typene, som i appen (Moderation.swift, ReportKind.label). */
export const KIND_LABELS: Record<string, string> = {
  message: "melding",
  image: "bilde",
  member: "navn i troppen",
  profile: "profil",
  comment: "kommentar",
  course: "bane i banebiblioteket",
  competition: "turnering i «Finn turneringer»",
};

/** Typene uten arrangør over seg (sql/066): ingen kan avgjøre dem i appen, vi tar dem i databasen. */
export const UNMODERATED_KINDS = new Set(["course", "competition"]);

/** Grunnene, som i appen (Moderation.swift, ReportReason.title). */
export const REASON_LABELS: Record<string, string> = {
  offensive: "Støtende eller hatefullt",
  harassment: "Trakassering eller mobbing",
  spam: "Spam eller reklame",
  inappropriate_image: "Upassende bilde",
  impersonation: "Utgir seg for å være en annen",
  other: "Noe annet",
};

export const EXCERPT_MAX = 300;

/** Sammenlikner uten å lekke lengden av felles prefiks via tid (som i push-send). */
export function safeEqual(a: string, b: string): boolean {
  const x = new TextEncoder().encode(a);
  const y = new TextEncoder().encode(b);
  let diff = x.length ^ y.length;
  for (let i = 0; i < Math.max(x.length, y.length); i++) diff |= (x[i] ?? 0) ^ (y[i] ?? 0);
  return diff === 0;
}

/** REPORT_ALERT_TO, kommaseparert. Bare det som ser ut som adresser, uten duplikater. */
export function parseRecipients(value: string | undefined): string[] {
  const out: string[] = [];
  for (const part of (value ?? "").split(",")) {
    const a = part.trim();
    if (a && /^[^\s@<>]+@[^\s@<>]+$/.test(a) && !out.includes(a)) out.push(a);
  }
  return out;
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** report_id fra body {"report_id": "<uuid>"}, eller null. */
export function parseReportId(body: unknown): string | null {
  if (!body || typeof body !== "object") return null;
  const id = (body as Record<string, unknown>).report_id;
  return typeof id === "string" && UUID.test(id) ? id.toLowerCase() : null;
}

export function kindLabel(kind: string): string {
  return KIND_LABELS[kind] ?? kind;
}

/** Én linje, uten linjeskift og med høyst max tegn. */
function oneLine(value: string | null | undefined, max: number): string {
  const s = (value ?? "").replace(/\s+/g, " ").trim();
  return s.length > max ? s.slice(0, max - 1) + "…" : s;
}

/** Tidspunktet i norsk tid, f.eks. «20.10.2026 kl. 18:05». */
export function formatTime(iso: string): string {
  const d = new Date(iso);
  if (!Number.isFinite(d.getTime())) return iso;
  const parts = Object.fromEntries(
    new Intl.DateTimeFormat("nb-NO", {
      timeZone: "Europe/Oslo",
      day: "2-digit",
      month: "2-digit",
      year: "numeric",
      hour: "2-digit",
      minute: "2-digit",
      hourCycle: "h23",
    }).formatToParts(d).map((p) => [p.type, p.value]),
  );
  return `${parts.day}.${parts.month}.${parts.year} kl. ${parts.hour}:${parts.minute}`;
}

/** Emne og tekst. Kort, på norsk, uten e-postadresser til brukerne. */
export function alertMessage(p: ReportPayload, to: string): EmailMessage {
  const kind = kindLabel(p.kind);
  const where = p.kind === "course"
    ? "Det felles banebiblioteket (alle innloggede ser banen)"
    : p.kind === "competition"
    ? `Turnering: ${oneLine(p.competition_name, 60) || "(ukjent navn)"}` +
      (p.club_name ? ` (klubb: ${oneLine(p.club_name, 60)})` : "") + ", i «Finn turneringer» for alle"
    : p.club_name
    ? `Klubb: ${oneLine(p.club_name, 60)}`
    : p.competition_name
    ? `Turnering: ${oneLine(p.competition_name, 60)}`
    : "Utenfor klubb og turnering (løse runder eller profil)";
  const unmoderated = UNMODERATED_KINDS.has(p.kind);
  const excerpt = oneLine(p.excerpt, EXCERPT_MAX);
  const note = oneLine(p.note, EXCERPT_MAX);
  const lines = [
    `Ny rapport i Atten: ${kind}.`,
    "",
    `Grunn: ${REASON_LABELS[p.reason] ?? p.reason}`,
    `Rapportert av: ${oneLine(p.reporter_name, 60) || "(ukjent navn)"}`,
    `Innholdet er fra: ${oneLine(p.target_name, 60) || "(ukjent navn)"}`,
    where,
    `Tidspunkt: ${formatTime(p.created_at)}`,
    "",
    p.kind === "image" ? `Bildet (sti i Storage): ${excerpt || "(mangler)"}` : `Utdrag: ${excerpt || "(tomt)"}`,
  ];
  if (note) lines.push(`Kommentar fra den som rapporterte: ${note}`);
  lines.push("");
  if (unmoderated) {
    lines.push(
      "Rapporten må følges opp innen 24 timer (App Store 1.2). Ingen arrangør kan avgjøre den i",
      "Atten: ta den i databasen (se OPPFØLGING i sql/066_rapporter_baner_turneringer.sql).",
    );
  } else {
    lines.push(
      "Rapporten må følges opp innen 24 timer (App Store 1.2): fjern innholdet eller avvis",
      "rapporten i Atten, eller ta det i databasen.",
    );
  }
  lines.push("");
  if (p.target_id) lines.push(`Innholdets id: ${p.target_id}`);
  lines.push(`Rapport-id: ${p.id}`);
  return { to, subject: `Atten: ny rapport (${kind})`, text: lines.join("\r\n") };
}

// ---------------------------------------------------------------------------
// Én kjøring
// ---------------------------------------------------------------------------

export type Rpc = <T>(name: string, params: Record<string, unknown>) => Promise<T>;

export interface AlertDeps {
  /** REPORT_ALERT_SECRET. Tom: funksjonen er ikke satt opp. */
  secret: string;
  /** x-report-secret fra forespørselen. */
  header: string;
  /** Den tolkede bodyen (eller undefined når den ikke var JSON). */
  body: unknown;
  recipients: string[];
  smtp: SmtpConfig | null;
  rpc: Rpc | null;
  makeSender: (config: SmtpConfig) => EmailSender;
  log: (message: string) => void;
}

export interface AlertResult {
  status: number;
  body: Record<string, unknown>;
}

/**
 * Hele kjøringen. Svarer med korte koder, aldri en feilmelding eller stack til klienten;
 * detaljene går til loggen.
 */
export async function runAlert(d: AlertDeps): Promise<AlertResult> {
  if (!d.secret || !d.rpc) {
    d.log("report-alert: mangler REPORT_ALERT_SECRET eller Supabase-konfigurasjon");
    return { status: 500, body: { error: "config" } };
  }
  if (!safeEqual(d.header, d.secret)) return { status: 401, body: { error: "unauthorized" } };

  const id = parseReportId(d.body);
  if (!id) return { status: 400, body: { error: "bad_request" } };

  if (!d.smtp) {
    d.log("report-alert: SMTP er ikke satt opp, ingen e-post");
    return { status: 200, body: { skipped: "no_smtp" } };
  }
  if (d.recipients.length === 0) {
    d.log("report-alert: REPORT_ALERT_TO er tom, ingen e-post");
    return { status: 200, body: { skipped: "no_recipients" } };
  }

  let payload: ReportPayload | null;
  try {
    payload = await d.rpc<ReportPayload | null>("report_alert_payload", { p_report_id: id });
  } catch (error) {
    d.log(`report-alert: report_alert_payload feilet: ${String((error as Error)?.message ?? error).slice(0, 300)}`);
    return { status: 502, body: { error: "lookup_failed" } };
  }
  if (!payload) return { status: 200, body: { skipped: "not_found" } };

  const sender = d.makeSender(d.smtp);
  let sent = 0;
  let failed = 0;
  for (const to of d.recipients) {
    try {
      await sender.send(alertMessage(payload, to));
      sent++;
    } catch (error) {
      failed++;
      d.log(`report-alert: e-post feilet: ${String((error as Error)?.message ?? error).slice(0, 300)}`);
    }
  }
  if (sent === 0) return { status: 502, body: { error: "send_failed", failed } };
  return { status: 200, body: { sent, failed } };
}
