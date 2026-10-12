// E-post til dem uten push (sql/046, punkt 6). AV til SMTP er satt opp.
//
// Egen del, adskilt fra pushen: index.ts kaller runEmail() for activity-jobber bare når
// alle fire secrets finnes. Mangler én, gjør denne fila ingenting (ingen oppslag, ingen logg).
//
// Secrets (Supabase → Edge Functions → Secrets), aldri i repoet:
//   SMTP_HOST   for eksempel smtp.resend.com, smtp.sendgrid.net, smtp.office365.com
//   SMTP_USER   brukernavnet hos e-posttjenesten
//   SMTP_PASS   passordet eller API-nøkkelen
//   SMTP_FROM   avsenderen, for eksempel «Atten <varsler@dashdash18.com>» (domenet må være
//               godkjent hos tjenesten, med SPF og DKIM)
//   SMTP_PORT   valgfri, standard 465. Edge Functions stenger 25 og 587, så bruk 465 (TLS
//               fra start).
//
// Ingen nye avhengigheter: en liten SMTP-klient over Deno.connectTls (AUTH LOGIN), med
// transporten byttbar så den kan testes uten nett (email_test.ts). EmailSender er grensesnittet,
// så en HTTP-tjeneste (fetch mot et API) kan settes inn i stedet senere.

import { activityDisplay, type JobPayload, MAX_AGE_MS, nameLookup } from "./logic.ts";

/** Linjene som kan gå som e-post. Samme liste som push_email_kinds() i 046. */
export const EMAIL_KINDS = ["announcement", "nudge", "reminder", "waitlist_promoted", "signup_dropped"] as const;

export interface SmtpConfig {
  host: string;
  port: number;
  user: string;
  pass: string;
  from: string;
}

/** Konfigurasjonen når alle fire er satt, ellers null (e-post er av). */
export function smtpConfig(get: (name: string) => string | undefined): SmtpConfig | null {
  const host = get("SMTP_HOST")?.trim(), user = get("SMTP_USER")?.trim();
  const pass = get("SMTP_PASS"), from = get("SMTP_FROM")?.trim();
  if (!host || !user || !pass || !from) return null;
  const port = Number(get("SMTP_PORT") ?? "465");
  return { host, user, pass, from, port: Number.isInteger(port) && port > 0 ? port : 465 };
}

/** En rad fra push_email_recipients(jobb). */
export interface EmailRecipient {
  user_id: string;
  member_id: string | null;
  display_name: string | null;
  email: string;
}

export interface EmailMessage {
  to: string;
  subject: string;
  text: string;
}

/**
 * Skal jobben vurderes for e-post? Bare activity-jobber med en av EMAIL_KINDS, ikke kladd og
 * ikke for gamle (samme grense som push). Hvem som får, avgjør push_email_recipients.
 */
export function emailEligible(payload: JobPayload, now: Date): boolean {
  const a = payload.activity;
  if (payload.kind !== "activity" || !a) return false;
  if (!(EMAIL_KINDS as readonly string[]).includes(a.kind)) return false;
  if (a.round_status === "draft") return false;
  const t = Date.parse(a.created_at);
  return Number.isFinite(t) && now.getTime() - t <= MAX_AGE_MS.activity;
}

/** Emne og tekst. Samme tekst som pushen, uten emoji i emnet. Kort, på norsk. */
export function emailMessage(payload: JobPayload, to: string): EmailMessage {
  const display = activityDisplay(payload.activity!, nameLookup(payload.members), payload.day_term);
  const title = payload.club.name;
  const subject = `${title}: ${display.text}`.replace(/\s+/g, " ").slice(0, 150);
  const text = [
    `${display.emoji} ${display.text}`,
    "",
    "Åpne Atten for å se mer.",
    "",
    "Du får denne e-posten fordi du ikke har varsler på telefonen.",
    "Slå den av i Atten under Deg → Varsler.",
  ].join("\r\n");
  return { to, subject, text };
}

// ---------------------------------------------------------------------------
// Avsenderen
// ---------------------------------------------------------------------------

export interface EmailSender {
  send(message: EmailMessage): Promise<void>;
}

/** En linjebasert forbindelse. Deno.connectTls i drift, en falsk i testene. */
export interface LineTransport {
  readLine(): Promise<string | null>;
  write(text: string): Promise<void>;
  close(): void;
}

function b64(text: string): string {
  const bytes = new TextEncoder().encode(text);
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin);
}

/** «=?UTF-8?B?…?=» når emnet har tegn utenfor ASCII. */
export function encodeHeader(value: string): string {
  // deno-lint-ignore no-control-regex
  return /^[\x20-\x7e]*$/.test(value) ? value : `=?UTF-8?B?${b64(value)}?=`;
}

/** Adressen i «Navn <adresse>», eller hele teksten. */
export function addressOf(value: string): string {
  const m = /<([^>]+)>/.exec(value);
  return (m ? m[1] : value).trim();
}

/** Hele meldingen (RFC 5322), med teksten i base64 så æøå og emoji går trygt. */
export function buildMime(from: string, message: EmailMessage, date: Date, messageId: string): string {
  const body = b64(message.text).replace(/.{1,76}/g, "$&\r\n");
  return [
    `From: ${from}`,
    `To: ${message.to}`,
    `Subject: ${encodeHeader(message.subject)}`,
    `Date: ${date.toUTCString()}`,
    `Message-ID: <${messageId}>`,
    "MIME-Version: 1.0",
    "Content-Type: text/plain; charset=utf-8",
    "Content-Transfer-Encoding: base64",
    "",
    body,
  ].join("\r\n");
}

/** Leser ett svar (også flerlinjers «250-…»). Kaster når koden ikke er den ventede. */
async function expect(t: LineTransport, code: number): Promise<string> {
  let line: string | null;
  let all = "";
  do {
    line = await t.readLine();
    if (line === null) throw new Error(`SMTP: forbindelsen ble brutt (ventet ${code})`);
    all += line + "\n";
  } while (/^\d{3}-/.test(line));
  if (!line.startsWith(String(code))) throw new Error(`SMTP: ${line.slice(0, 200)}`);
  return all;
}

/** SMTP over TLS (465) med AUTH LOGIN. Én forbindelse per melding: e-postene er få. */
export class SmtpSender implements EmailSender {
  private readonly config: SmtpConfig;
  private readonly connect: (host: string, port: number) => Promise<LineTransport>;
  private readonly now: () => Date;

  constructor(
    config: SmtpConfig,
    connect: (host: string, port: number) => Promise<LineTransport> = denoTlsTransport,
    now: () => Date = () => new Date(),
  ) {
    this.config = config;
    this.connect = connect;
    this.now = now;
  }

  async send(message: EmailMessage): Promise<void> {
    const t = await this.connect(this.config.host, this.config.port);
    try {
      await expect(t, 220);
      await t.write(`EHLO dashdash18.com\r\n`);
      await expect(t, 250);
      await t.write("AUTH LOGIN\r\n");
      await expect(t, 334);
      await t.write(b64(this.config.user) + "\r\n");
      await expect(t, 334);
      await t.write(b64(this.config.pass) + "\r\n");
      await expect(t, 235);
      await t.write(`MAIL FROM:<${addressOf(this.config.from)}>\r\n`);
      await expect(t, 250);
      await t.write(`RCPT TO:<${addressOf(message.to)}>\r\n`);
      await expect(t, 250);
      await t.write("DATA\r\n");
      await expect(t, 354);
      const id = `${crypto.randomUUID()}@dashdash18.com`;
      await t.write(buildMime(this.config.from, message, this.now(), id) + "\r\n.\r\n");
      await expect(t, 250);
      await t.write("QUIT\r\n");
    } finally {
      t.close();
    }
  }
}

/** Deno.connectTls som linjer. Bare i drift (Edge Functions). */
async function denoTlsTransport(host: string, port: number): Promise<LineTransport> {
  // deno-lint-ignore no-explicit-any
  const DenoNs = (globalThis as any).Deno;
  const conn = await DenoNs.connectTls({ hostname: host, port });
  const decoder = new TextDecoder();
  const encoder = new TextEncoder();
  let buffer = "";
  const chunk = new Uint8Array(4096);
  return {
    async readLine() {
      while (!buffer.includes("\n")) {
        const n = await conn.read(chunk);
        if (n === null) {
          const rest = buffer;
          buffer = "";
          return rest || null;
        }
        buffer += decoder.decode(chunk.subarray(0, n));
      }
      const i = buffer.indexOf("\n");
      const line = buffer.slice(0, i).replace(/\r$/, "");
      buffer = buffer.slice(i + 1);
      return line;
    },
    async write(text: string) {
      const bytes = encoder.encode(text);
      let off = 0;
      while (off < bytes.length) off += await conn.write(bytes.subarray(off));
    },
    close() {
      try {
        conn.close();
      } catch {
        // Lukket fra før.
      }
    },
  };
}

// ---------------------------------------------------------------------------
// Én jobb
// ---------------------------------------------------------------------------

export interface EmailLog {
  user_id: string;
  channel: "email";
  status: "sent" | "failed";
  reason?: string;
}

/**
 * Sender e-post til mottakerne og gir loggen (channel = 'email') til push_log_result.
 * En feil for én mottaker stopper ikke de andre.
 */
export async function sendEmails(
  sender: EmailSender,
  payload: JobPayload,
  recipients: EmailRecipient[],
): Promise<EmailLog[]> {
  const out: EmailLog[] = [];
  for (const r of recipients) {
    if (!r.email || !r.email.includes("@")) continue;
    try {
      await sender.send(emailMessage(payload, r.email));
      out.push({ user_id: r.user_id, channel: "email", status: "sent" });
    } catch (error) {
      const reason = String((error as Error)?.message ?? error).slice(0, 200);
      out.push({ user_id: r.user_id, channel: "email", status: "failed", reason });
    }
  }
  return out;
}
