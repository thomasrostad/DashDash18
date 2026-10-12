import { test } from "node:test";
import assert from "node:assert/strict";
import { buildICS, escapeText, eventSummary, foldLine, normalizeCalendarToken, utcStamp, type CalendarEvent } from "../src/kalender.ts";
import { handle } from "../src/index.ts";

const TOKEN = "abcdefghijklmnopqrstuvwxyz234567";
const env = { SUPABASE_URL: "https://eksempel.supabase.co", SUPABASE_KEY: "publiserbar" };
const bytes = (s: string) => new TextEncoder().encode(s).length;
const unfold = (s: string) => s.replace(/\r\n /g, "");

const kveld: CalendarEvent = {
  id: "EEEEEEEE-0000-0000-0000-000000005101",
  club_name: "Golfgutu",
  competition_name: "Sesong 2026",
  competition_kind: "season",
  date: "2026-10-15",
  start_time: "18:00:00",
  venue: "Simsenteret, bås 3",
  note: "Ta med sko; og godt humør\nHusk Vipps",
  updated_at: "2026-10-12T11:21:13.769177+02:00",
};
const liga: CalendarEvent = {
  id: "eeeeeeee-0000-0000-0000-000000005102",
  club_name: "Golfgutu",
  competition_name: "Torsdagsligaen",
  competition_kind: "league",
  date: "2026-12-31",
  start_time: null,
  venue: null,
  note: null,
  updated_at: null,
};

test("tokenet: bare 32 tegn base32 med små bokstaver", () => {
  assert.equal(normalizeCalendarToken(TOKEN), TOKEN);
  assert.equal(normalizeCalendarToken(TOKEN.toUpperCase()), null);
  assert.equal(normalizeCalendarToken(TOKEN.slice(1)), null);
  assert.equal(normalizeCalendarToken(TOKEN.slice(1) + "1"), null); // 1 er ikke base32
});

test("TEXT escapes: backslash, semikolon, komma og linjeskift", () => {
  assert.equal(escapeText("a\\b;c,d\ne\r\nf"), "a\\\\b\\;c\\,d\\ne\\nf");
  assert.equal(escapeText("Bærum: «kveld» – ø å"), "Bærum: «kveld» – ø å");
});

test("linjene brettes ved 75 oktetter uten å dele norske tegn", () => {
  const ascii = "DESCRIPTION:" + "x".repeat(200);
  const folded = foldLine(ascii);
  assert.ok(folded.split("\r\n").every((l) => bytes(l) <= 75));
  assert.ok(folded.split("\r\n").slice(1).every((l) => l.startsWith(" ")));
  assert.equal(unfold(folded), ascii);

  const norsk = "LOCATION:" + "æøå".repeat(40) + "🏌️";
  const f2 = foldLine(norsk);
  const linjer = f2.split("\r\n");
  assert.ok(linjer.length > 1);
  assert.ok(linjer.every((l) => bytes(l) <= 75));
  assert.ok(linjer.every((l) => !l.includes("�")));
  assert.equal(unfold(f2), norsk);
  assert.equal(foldLine("SUMMARY:kort"), "SUMMARY:kort");
});

test("tidsstempel i UTC", () => {
  assert.equal(utcStamp("2026-10-12T11:21:13.769177+02:00"), "20261012T092113Z");
  assert.equal(utcStamp(new Date(Date.UTC(2026, 0, 2, 3, 4, 5))), "20260102T030405Z");
  assert.equal(utcStamp("tull"), null);
});

test("tittelen: klubb · Kveld for sesongen, klubb · turnering ellers", () => {
  assert.equal(eventSummary(kveld), "Golfgutu · Kveld");
  assert.equal(eventSummary(liga), "Golfgutu · Torsdagsligaen");
  assert.equal(eventSummary({ ...liga, competition_name: null }), "Golfgutu · Kveld");
});

test("iCalendar: kalenderen, tidssonen og kveldene", () => {
  const ics = buildICS({ events: [kveld, liga] }, new Date(Date.UTC(2026, 9, 12, 8, 0, 0)));
  assert.ok(ics.endsWith("\r\n"));
  assert.ok(!/[^\r]\n/.test(ics), "bare CRLF");
  const raw = ics.split("\r\n");
  assert.ok(raw.every((l) => bytes(l) <= 75), "ingen linje over 75 oktetter");
  const lines = unfold(ics).split("\r\n");
  assert.equal(lines[0], "BEGIN:VCALENDAR");
  assert.equal(lines.at(-2), "END:VCALENDAR");
  for (const want of ["VERSION:2.0", "PRODID:-//DashDash18//Atten//NB", "METHOD:PUBLISH", "X-WR-CALNAME:Atten",
    "REFRESH-INTERVAL;VALUE=DURATION:PT1H", "X-PUBLISHED-TTL:PT1H", "BEGIN:VTIMEZONE", "TZID:Europe/Oslo",
    "RRULE:FREQ=YEARLY;BYMONTH=3;BYDAY=-1SU", "RRULE:FREQ=YEARLY;BYMONTH=10;BYDAY=-1SU"]) {
    assert.ok(lines.includes(want), want);
  }
  assert.equal(lines.filter((l) => l === "BEGIN:VEVENT").length, 2);
  assert.equal(lines.filter((l) => l === "END:VEVENT").length, 2);
  assert.equal(lines.filter((l) => l.startsWith("DTSTAMP:")).every((l) => l === "DTSTAMP:20261012T080000Z"), true);

  // Kvelden med tid: lokal tid i Oslo, tre timer.
  assert.ok(lines.includes("UID:eeeeeeee-0000-0000-0000-000000005101@dashdash18.com"));
  assert.ok(lines.includes("DTSTART;TZID=Europe/Oslo:20261015T180000"));
  assert.ok(lines.includes("DURATION:PT3H"));
  assert.ok(lines.includes("SUMMARY:Golfgutu · Kveld"));
  assert.ok(lines.includes("LOCATION:Simsenteret\\, bås 3"));
  assert.ok(lines.includes("DESCRIPTION:Sesong 2026\\nTa med sko\\; og godt humør\\nHusk Vipps\\nDu er påmeldt i Atten."));
  assert.ok(lines.includes("LAST-MODIFIED:20261012T092113Z"));

  // Uten tid: heldag, også over nyttår.
  assert.ok(lines.includes("DTSTART;VALUE=DATE:20261231"));
  assert.ok(lines.includes("DTEND;VALUE=DATE:20270101"));
  assert.ok(lines.includes("SUMMARY:Golfgutu · Torsdagsligaen"));
  assert.ok(lines.includes("DESCRIPTION:Du er påmeldt i Atten."));
  assert.equal(lines.filter((l) => l.startsWith("LOCATION:")).length, 1);
  assert.equal(lines.filter((l) => l.startsWith("LAST-MODIFIED:")).length, 1);
});

test("iCalendar: tom kalender og rader med feil form hoppes over", () => {
  const tom = unfold(buildICS({ events: [] })).split("\r\n");
  assert.ok(tom.includes("BEGIN:VTIMEZONE"));
  assert.ok(!tom.includes("BEGIN:VEVENT"));
  const feil = unfold(buildICS({ events: [{ ...kveld, id: "x" }, { ...kveld, date: "15.10.2026" }] })).split("\r\n");
  assert.ok(!feil.includes("BEGIN:VEVENT"));
});

test("iCalendar: lang tekst med norske tegn brettes riktig", () => {
  const lang = { ...kveld, note: "Påmelding før fredag. ".repeat(10), venue: "Ålesund Golfklubb, Blindheim – bås 12; spør i resepsjonen" };
  const ics = buildICS({ events: [lang] });
  assert.ok(ics.split("\r\n").every((l) => bytes(l) <= 75));
  const lines = unfold(ics).split("\r\n");
  assert.ok(lines.includes("LOCATION:Ålesund Golfklubb\\, Blindheim – bås 12\\; spør i resepsjonen"));
});

type Kall = { url: string; init: RequestInit };
async function medFetch(svar: () => Response, f: (kall: Kall[]) => Promise<void>) {
  const original = globalThis.fetch;
  const kall: Kall[] = [];
  globalThis.fetch = (async (url: string | URL | Request, init?: RequestInit) => {
    kall.push({ url: String(url), init: init ?? {} });
    return svar();
  }) as typeof fetch;
  try {
    await f(kall);
  } finally {
    globalThis.fetch = original;
  }
}

test("/kalender/<token>.ics: henter calendar_feed med anon-nøkkelen og svarer med iCalendar", async () => {
  await medFetch(() => Response.json({ generated_at: "2026-10-12T08:00:00Z", time_zone: "Europe/Oslo", events: [kveld] }), async (kall) => {
    const res = await handle(new Request(`https://dashdash18.com/kalender/${TOKEN}.ics`), env);
    assert.equal(res.status, 200);
    assert.equal(res.headers.get("Content-Type"), "text/calendar; charset=utf-8");
    assert.equal(res.headers.get("Cache-Control"), "private, max-age=300");
    assert.equal(res.headers.get("X-Robots-Tag"), "noindex");
    const body = await res.text();
    assert.ok(body.startsWith("BEGIN:VCALENDAR\r\n"));
    assert.ok(body.includes("UID:eeeeeeee-0000-0000-0000-000000005101@dashdash18.com"));
    assert.equal(kall.length, 1);
    assert.equal(kall[0].url, "https://eksempel.supabase.co/rest/v1/rpc/calendar_feed");
    assert.equal(kall[0].init.method, "POST");
    assert.equal((kall[0].init.headers as Record<string, string>).apikey, "publiserbar");
    assert.deepEqual(JSON.parse(String(kall[0].init.body)), { p_token: TOKEN });

    const head = await handle(new Request(`https://dashdash18.com/kalender/${TOKEN}.ics`, { method: "HEAD" }), env);
    assert.equal(head.status, 200);
    assert.equal(await head.text(), "");
  });
});

test("/kalender: ukjent eller tilbaketrukket token gir 404, feil form spør ikke serveren", async () => {
  await medFetch(() => Response.json({ code: "P0002", message: "Fant ingen kalender for lenken" }, { status: 404 }), async (kall) => {
    const res = await handle(new Request(`https://dashdash18.com/kalender/${TOKEN}.ics`), env);
    assert.equal(res.status, 404);
    assert.equal(res.headers.get("Cache-Control"), "no-store");
    assert.equal(kall.length, 1);
    for (const bad of ["kort.ics", `${TOKEN.toUpperCase()}.ics`, `${TOKEN}1.ics`]) {
      const r = await handle(new Request(`https://dashdash18.com/kalender/${bad}`), env);
      assert.equal(r.status, 404, bad);
    }
    assert.equal(kall.length, 1);
    const utenIcs = await handle(new Request(`https://dashdash18.com/kalender/${TOKEN}`), env);
    assert.equal(utenIcs.status, 404);
  });
});

test("/kalender: feil hos Supabase eller manglende oppsett gir 502", async () => {
  await medFetch(() => Response.json({ code: "XX000" }, { status: 500 }), async () => {
    const res = await handle(new Request(`https://dashdash18.com/kalender/${TOKEN}.ics`), env);
    assert.equal(res.status, 502);
    assert.equal(res.headers.get("Cache-Control"), "no-store");
  });
  const uten = await handle(new Request(`https://dashdash18.com/kalender/${TOKEN}.ics`), {});
  assert.equal(uten.status, 502);
});
