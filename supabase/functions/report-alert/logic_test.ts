// Tester for report-alert (sql/063). Kjøres med
//   deno test supabase/functions/report-alert/
// eller uten Deno med Node og shimmen i docs/push-oppsett.md:
//   node --import /tmp/deno-shim.mjs --test supabase/functions/report-alert/logic_test.ts
// Ingen nettverk, ingen database: RPC-en og avsenderen er falske og skriver ned kallene.

import { deepStrictEqual as eq, ok, strictEqual as is } from "node:assert/strict";
import type { EmailMessage, EmailSender, SmtpConfig } from "../push-send/email.ts";
import {
  alertMessage,
  type AlertDeps,
  formatTime,
  parseRecipients,
  parseReportId,
  type ReportPayload,
  type Rpc,
  runAlert,
  safeEqual,
} from "./logic.ts";

const ID = "6f0c1a52-1111-4222-8333-944455556666";
const SMTP: SmtpConfig = { host: "smtp.x.no", port: 465, user: "u", pass: "p", from: "Atten <varsler@dashdash18.com>" };

const PAYLOAD: ReportPayload = {
  id: ID,
  kind: "message",
  reason: "harassment",
  note: "Dette er ikke greit",
  excerpt: "Du er  dårlig\npå golf",
  status: "open",
  created_at: "2026-10-20T16:05:00Z",
  reporter_name: "Thomas",
  target_name: "Ola",
  club_name: "Golfgutu",
  competition_name: null,
};

function deps(over: Partial<AlertDeps> = {}) {
  const calls: { name: string; params: Record<string, unknown> }[] = [];
  const sent: EmailMessage[] = [];
  const logs: string[] = [];
  const rpc: Rpc = <T>(name: string, params: Record<string, unknown>) => {
    calls.push({ name, params });
    return Promise.resolve(PAYLOAD as unknown as T);
  };
  const sender: EmailSender = {
    send: (m) => {
      sent.push(m);
      return Promise.resolve();
    },
  };
  const d: AlertDeps = {
    secret: "hemmelig",
    header: "hemmelig",
    body: { report_id: ID },
    recipients: ["personvern@dashdash18.com"],
    smtp: SMTP,
    rpc,
    makeSender: () => sender,
    log: (m) => logs.push(m),
    ...over,
  };
  return { d, calls, sent, logs };
}

Deno.test("safeEqual: lik, ulik og ulik lengde", () => {
  ok(safeEqual("abc", "abc"));
  ok(!safeEqual("abc", "abd"));
  ok(!safeEqual("abc", "abcd"));
  ok(!safeEqual("", "x"));
  ok(safeEqual("æøå", "æøå"));
});

Deno.test("mottakerne: kommaseparert, trimmet, uten tomme, ugyldige og duplikater", () => {
  eq(parseRecipients(undefined), []);
  eq(parseRecipients(" , "), []);
  eq(parseRecipients("a@b.no, c@d.no ,a@b.no,tull, Navn <x@y.no>"), ["a@b.no", "c@d.no"]);
});

Deno.test("report_id må være en uuid", () => {
  is(parseReportId({ report_id: ID.toUpperCase() }), ID);
  is(parseReportId({ report_id: "1; drop table" }), null);
  is(parseReportId({ report_id: 7 }), null);
  is(parseReportId(null), null);
  is(parseReportId(undefined), null);
});

Deno.test("tidspunktet i norsk tid, også om vinteren", () => {
  is(formatTime("2026-10-20T16:05:00Z"), "20.10.2026 kl. 18:05");
  is(formatTime("2026-12-01T23:30:00Z"), "02.12.2026 kl. 00:30");
  is(formatTime("tull"), "tull");
});

Deno.test("e-posten: emne, type, grunn, navn, klubb, utdrag og 24 timer", () => {
  const m = alertMessage(PAYLOAD, "personvern@dashdash18.com");
  is(m.to, "personvern@dashdash18.com");
  is(m.subject, "Atten: ny rapport (melding)");
  ok(m.text.includes("Grunn: Trakassering eller mobbing"));
  ok(m.text.includes("Rapportert av: Thomas"));
  ok(m.text.includes("Innholdet er fra: Ola"));
  ok(m.text.includes("Klubb: Golfgutu"));
  ok(m.text.includes("Tidspunkt: 20.10.2026 kl. 18:05"));
  ok(m.text.includes("Utdrag: Du er dårlig på golf"));
  ok(m.text.includes("Kommentar fra den som rapporterte: Dette er ikke greit"));
  ok(m.text.includes("innen 24 timer"));
  ok(m.text.includes(ID));
  ok(!m.text.includes("@"), "ingen e-postadresser i teksten");
});

Deno.test("e-posten: turnering, bilde, ukjente navn og utdrag på høyst 300 tegn", () => {
  const m = alertMessage({
    ...PAYLOAD,
    kind: "comment",
    club_name: null,
    competition_name: "Høstcupen",
    reporter_name: null,
    target_name: null,
    note: null,
    excerpt: "x".repeat(600),
  }, "a@b.no");
  is(m.subject, "Atten: ny rapport (kommentar)");
  ok(m.text.includes("Turnering: Høstcupen"));
  ok(m.text.includes("Rapportert av: (ukjent navn)"));
  ok(!m.text.includes("Kommentar fra"));
  const line = m.text.split("\r\n").find((l) => l.startsWith("Utdrag: "))!;
  is(line.length - "Utdrag: ".length, 300);

  const img = alertMessage({ ...PAYLOAD, kind: "image", excerpt: "club/abc.jpg" }, "a@b.no");
  is(img.subject, "Atten: ny rapport (bilde)");
  ok(img.text.includes("Bildet (sti i Storage): club/abc.jpg"));

  const prof = alertMessage({ ...PAYLOAD, kind: "profile", club_name: null }, "a@b.no");
  ok(prof.text.includes("Utenfor klubb og turnering"));
});

Deno.test("kjøring: feil hemmelighet gir 401 uten oppslag", async () => {
  const { d, calls, sent } = deps({ header: "feil" });
  eq(await runAlert(d), { status: 401, body: { error: "unauthorized" } });
  is(calls.length, 0);
  is(sent.length, 0);
});

Deno.test("kjøring: mangler hemmelighet eller Supabase gir 500 config", async () => {
  eq((await runAlert(deps({ secret: "" }).d)).body, { error: "config" });
  eq((await runAlert(deps({ rpc: null }).d)).status, 500);
});

Deno.test("kjøring: ugyldig body gir 400", async () => {
  const { d, calls } = deps({ body: { report_id: "x" } });
  eq(await runAlert(d), { status: 400, body: { error: "bad_request" } });
  is(calls.length, 0);
});

Deno.test("kjøring: uten SMTP eller mottakere: 200 skipped og en logglinje", async () => {
  const a = deps({ smtp: null });
  eq(await runAlert(a.d), { status: 200, body: { skipped: "no_smtp" } });
  is(a.calls.length, 0);
  is(a.logs.length, 1);
  const b = deps({ recipients: [] });
  eq(await runAlert(b.d), { status: 200, body: { skipped: "no_recipients" } });
  is(b.logs.length, 1);
});

Deno.test("kjøring: sender én e-post per mottaker med payload fra RPC-en", async () => {
  const { d, calls, sent } = deps({ recipients: ["a@b.no", "c@d.no"] });
  eq(await runAlert(d), { status: 200, body: { sent: 2, failed: 0 } });
  eq(calls, [{ name: "report_alert_payload", params: { p_report_id: ID } }]);
  eq(sent.map((m) => m.to), ["a@b.no", "c@d.no"]);
  is(sent[0].subject, "Atten: ny rapport (melding)");
});

Deno.test("kjøring: fant ikke rapporten gir 200 skipped", async () => {
  const rpc: Rpc = <T>() => Promise.resolve(null as T);
  eq(await runAlert(deps({ rpc }).d), { status: 200, body: { skipped: "not_found" } });
});

Deno.test("kjøring: feil i oppslag eller sending gir korte koder, detaljene bare i loggen", async () => {
  const rpc: Rpc = () => Promise.reject(new Error("report_alert_payload: 500 hemmelig detalj"));
  const a = deps({ rpc });
  const ra = await runAlert(a.d);
  eq(ra, { status: 502, body: { error: "lookup_failed" } });
  ok(!JSON.stringify(ra).includes("hemmelig detalj"));
  ok(a.logs.some((l) => l.includes("hemmelig detalj")));

  let n = 0;
  const flaky: EmailSender = {
    send: () => (n++ === 0 ? Promise.reject(new Error("SMTP: 535 auth")) : Promise.resolve()),
  };
  const b = deps({ recipients: ["a@b.no", "c@d.no"], makeSender: () => flaky });
  eq(await runAlert(b.d), { status: 200, body: { sent: 1, failed: 1 } });

  const dead: EmailSender = { send: () => Promise.reject(new Error("SMTP: 535 auth")) };
  const c = deps({ makeSender: () => dead });
  const rc = await runAlert(c.d);
  eq(rc, { status: 502, body: { error: "send_failed", failed: 1 } });
  ok(!JSON.stringify(rc).includes("535"));
});
