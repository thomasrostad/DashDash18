// Tester for e-posten til dem uten push (email.ts, sql/046 punkt 6). Kjøres med
//   deno test supabase/functions/push-send/
// Ingen nettverk: SMTP-samtalen går mot en falsk server.

import { deepStrictEqual as eq, ok, rejects, strictEqual as is } from "node:assert/strict";
import {
  addressOf,
  buildMime,
  type EmailMessage,
  emailEligible,
  emailMessage,
  encodeHeader,
  type LineTransport,
  sendEmails,
  smtpConfig,
  SmtpSender,
} from "./email.ts";
import type { ActivityPayload, JobPayload } from "./logic.ts";

const NOW = new Date("2026-10-08T18:00:00Z");
const THOMAS = "00000000-0000-0000-0000-000000000009";

function payload(kind: string, category: string, data: Record<string, unknown>, extra: Partial<ActivityPayload> = {}): JobPayload {
  return {
    job_id: 7,
    kind: "activity",
    club: { id: "club-1", name: "Golfgutu", disabled_categories: [] },
    activity: {
      id: "act-1", kind, category, data, actor_member_id: THOMAS, event_id: "event-1", round_id: null,
      recipients: null, created_at: "2026-10-08T17:59:00Z", round_status: null, ...extra,
    },
    message: null,
    members: [{
      id: THOMAS, display_name: "Thomas", is_organizer: true, active: true, disabled_categories: [],
      thread_mode: "mentions", devices: [],
    }],
  };
}

const ANNOUNCEMENT = payload("announcement", "announcement", { text: "Vi starter 17:00" });

Deno.test("e-post er av til alle fire SMTP-secrets er satt", () => {
  const env = (o: Record<string, string>) => (k: string) => o[k];
  is(smtpConfig(env({})), null);
  is(smtpConfig(env({ SMTP_HOST: "smtp.x.no", SMTP_USER: "u", SMTP_PASS: "p" })), null);
  is(smtpConfig(env({ SMTP_HOST: " ", SMTP_USER: "u", SMTP_PASS: "p", SMTP_FROM: "a@b.no" })), null);
  eq(smtpConfig(env({ SMTP_HOST: "smtp.x.no", SMTP_USER: "u", SMTP_PASS: "p", SMTP_FROM: "Atten <a@b.no>" })),
    { host: "smtp.x.no", user: "u", pass: "p", from: "Atten <a@b.no>", port: 465 });
  is(smtpConfig(env({ SMTP_HOST: "h", SMTP_USER: "u", SMTP_PASS: "p", SMTP_FROM: "f", SMTP_PORT: "2465" }))!.port, 2465);
  is(smtpConfig(env({ SMTP_HOST: "h", SMTP_USER: "u", SMTP_PASS: "p", SMTP_FROM: "f", SMTP_PORT: "tull" }))!.port, 465);
});

Deno.test("bare melding til alle, purring, påminnelse, opprykk og avmelding, og ikke gamle", () => {
  ok(emailEligible(ANNOUNCEMENT, NOW));
  ok(emailEligible(payload("nudge", "nudge", {}), NOW));
  ok(emailEligible(payload("signup_dropped", "signup", { member: THOMAS }), NOW));
  ok(!emailEligible(payload("big_score", "score", {}), NOW));
  ok(!emailEligible(payload("evening_started", "round", {}), NOW));
  ok(!emailEligible(payload("announcement", "announcement", { text: "x" }, { created_at: "2026-10-08T17:00:00Z" }), NOW));
  ok(!emailEligible({ ...ANNOUNCEMENT, kind: "thread" }, NOW));
});

Deno.test("emnet og teksten: samme tekst som pushen, kort og på norsk", () => {
  const m = emailMessage(ANNOUNCEMENT, "per@example.no");
  is(m.to, "per@example.no");
  is(m.subject, "Golfgutu: Thomas: Vi starter 17:00");
  ok(m.text.startsWith("📣 Thomas: Vi starter 17:00\r\n"));
  ok(m.text.includes("Deg → Varsler"));
  ok(!m.text.includes("—"), "ingen tankestrek");
});

Deno.test("MIME: UTF-8 i emnet og base64 i teksten", () => {
  is(encodeHeader("Hei"), "Hei");
  is(encodeHeader("Påmelding"), "=?UTF-8?B?UMOlbWVsZGluZw==?=");
  is(addressOf("Atten <varsler@dashdash18.com>"), "varsler@dashdash18.com");
  is(addressOf("a@b.no"), "a@b.no");
  const mime = buildMime("Atten <a@b.no>", { to: "c@d.no", subject: "Hei", text: "Hei på deg" },
    new Date("2026-10-08T18:00:00Z"), "id@x");
  ok(mime.includes("Subject: Hei\r\n"));
  ok(mime.includes("Content-Transfer-Encoding: base64"));
  ok(mime.endsWith("SGVpIHDDpSBkZWc=\r\n"));
});

/** En falsk SMTP-server: svarer på hver kommando etter tur. */
function fakeServer(replies: string[]) {
  const written: string[] = [];
  const queue = [...replies];
  let closed = false;
  const transport: LineTransport = {
    readLine: () => Promise.resolve(queue.length ? queue.shift()! : null),
    write: (t) => {
      written.push(t);
      return Promise.resolve();
    },
    close: () => {
      closed = true;
    },
  };
  return { transport, written, isClosed: () => closed };
}

const OK_DIALOG = [
  "220 smtp.x.no ESMTP",
  "250-smtp.x.no", "250-AUTH LOGIN PLAIN", "250 OK",
  "334 VXNlcm5hbWU6", "334 UGFzc3dvcmQ6", "235 ok",
  "250 ok", "250 ok", "354 go", "250 queued",
];
const CONFIG = { host: "smtp.x.no", port: 465, user: "bruker", pass: "hemmelig", from: "Atten <varsler@dashdash18.com>" };
const MESSAGE: EmailMessage = { to: "per@example.no", subject: "Hei", text: "Hei" };

Deno.test("SMTP: logger inn, sender og lukker", async () => {
  const server = fakeServer(OK_DIALOG);
  let target = "";
  const sender = new SmtpSender(CONFIG, (h, p) => {
    target = `${h}:${p}`;
    return Promise.resolve(server.transport);
  }, () => NOW);
  await sender.send(MESSAGE);
  is(target, "smtp.x.no:465");
  eq(server.written.slice(0, 4), ["EHLO dashdash18.com\r\n", "AUTH LOGIN\r\n", "YnJ1a2Vy\r\n", "aGVtbWVsaWc=\r\n"]);
  is(server.written[4], "MAIL FROM:<varsler@dashdash18.com>\r\n");
  is(server.written[5], "RCPT TO:<per@example.no>\r\n");
  ok(server.written[7].endsWith("\r\n.\r\n"));
  is(server.written[8], "QUIT\r\n");
  ok(server.isClosed());
});

Deno.test("SMTP: feil passord gir en tydelig feil, og forbindelsen lukkes", async () => {
  const server = fakeServer(["220 hei", "250 OK", "334 a", "334 b", "535 Authentication failed"]);
  const sender = new SmtpSender(CONFIG, () => Promise.resolve(server.transport));
  await rejects(sender.send(MESSAGE), /SMTP: 535 Authentication failed/);
  ok(server.isClosed());
});

Deno.test("sendEmails: én feil stopper ikke de andre, og loggen har kanal email", async () => {
  const sent: string[] = [];
  const sender = {
    send: (m: EmailMessage) => {
      if (m.to === "feil@example.no") return Promise.reject(new Error("SMTP: 550 nei"));
      sent.push(m.to);
      return Promise.resolve();
    },
  };
  const log = await sendEmails(sender, ANNOUNCEMENT, [
    { user_id: "u1", member_id: "m1", display_name: "Per", email: "per@example.no" },
    { user_id: "u2", member_id: null, display_name: "Pål", email: "feil@example.no" },
    { user_id: "u3", member_id: null, display_name: "Espen", email: "ingen-adresse" },
  ]);
  eq(sent, ["per@example.no"]);
  eq(log, [
    { user_id: "u1", channel: "email", status: "sent" },
    { user_id: "u2", channel: "email", status: "failed", reason: "SMTP: 550 nei" },
  ]);
});
