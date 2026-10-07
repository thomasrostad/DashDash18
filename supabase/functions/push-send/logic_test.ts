// Tester for push-logikken (ROADMAP fase 8: push-kategorier-test.js av/på,
// og det push-status/påminnelse trenger fra senderen). Kjøres med
//   deno test supabase/functions/push-send/
// Ingen nettverk, ingen APNs, ingen database.

import { deepStrictEqual as eq, ok, strictEqual as is } from "node:assert/strict";
import {
  activityDisplay,
  type ActivityPayload,
  apnsBody,
  classifyApnsResponse,
  clubAllows,
  eveningLongText,
  formatMeters,
  type JobPayload,
  type MemberPayload,
  nameLookup,
  planPush,
  playerAllows,
  summarize,
  threadText,
} from "./logic.ts";

const NOW = new Date("2026-10-08T18:00:00Z");
const RECENT = "2026-10-08T17:59:00Z";

const THOMAS = "00000000-0000-0000-0000-000000000009"; // arrangør
const ANDERS = "00000000-0000-0000-0000-000000000001";
const BJORN = "00000000-0000-0000-0000-000000000002";
const CATO = "00000000-0000-0000-0000-000000000003";
const CARL = "00000000-0000-0000-0000-000000000004"; // ledig navn, ingen innlogging

function member(id: string, name: string, extra: Partial<MemberPayload> = {}): MemberPayload {
  return {
    id,
    display_name: name,
    is_organizer: false,
    active: true,
    disabled_categories: [],
    thread_mode: "mentions",
    devices: [{ token: `${name.toLowerCase()}-token`, environment: "production", bundle_id: null }],
    ...extra,
  };
}

function members(overrides: Record<string, Partial<MemberPayload>> = {}): MemberPayload[] {
  return [
    member(THOMAS, "Thomas", { is_organizer: true, ...overrides[THOMAS] }),
    member(ANDERS, "Anders", overrides[ANDERS]),
    member(BJORN, "Bjørn", overrides[BJORN]),
    member(CATO, "Cato", overrides[CATO]),
    member(CARL, "Carl", { active: false, devices: [], ...overrides[CARL] }),
  ];
}

function activity(kind: string, category: string, data: Record<string, unknown>, extra: Partial<ActivityPayload> = {}): ActivityPayload {
  return {
    id: "act-1",
    kind,
    category,
    data,
    actor_member_id: ANDERS,
    event_id: "event-1",
    round_id: "round-1",
    recipients: null,
    created_at: RECENT,
    round_status: "active",
    ...extra,
  };
}

const EAGLE = activity("big_score", "score", { member: ANDERS, hole: 5, hole_index: 4, name: "eagle", strokes: 3, par: 5 });

function job(a: ActivityPayload, opts: { club?: string[]; members?: MemberPayload[] } = {}): JobPayload {
  return {
    job_id: 1,
    kind: "activity",
    club: { id: "club-1", name: "Golfgutu", disabled_categories: opts.club ?? [] },
    activity: a,
    message: null,
    members: opts.members ?? members(),
  };
}

function thread(body: string, from: string, mentions: string[], opts: { club?: string[]; members?: MemberPayload[]; image?: boolean } = {}): JobPayload {
  return {
    job_id: 2,
    kind: "thread",
    club: { id: "club-1", name: "Golfgutu", disabled_categories: opts.club ?? [] },
    activity: null,
    message: {
      id: "msg-1",
      event_id: "event-1",
      member_id: from,
      body,
      mentions,
      has_image: opts.image ?? false,
      created_at: RECENT,
      pushed_at: null,
      event_date: "2026-10-08",
    },
    members: opts.members ?? members(),
  };
}

const to = (p: JobPayload) => planPush(p, NOW).notifications.map((n) => n.memberId).sort();

// --- Kategorier av og på (push-kategorier-test.js) ---------------------------

Deno.test("alt er på fra start: eaglen går til alle andre med telefon", () => {
  eq(to(job(EAGLE)), [THOMAS, BJORN, CATO].sort());
});

Deno.test("den som gjorde det, får ikke push om seg selv", () => {
  ok(!to(job(EAGLE)).includes(ANDERS));
});

Deno.test("klubben av: ingenting sendes, og grunnen lagres", () => {
  const plan = planPush(job(EAGLE, { club: ["score"] }), NOW);
  eq(plan.notifications, []);
  is(plan.skipped, "score er av for klubben");
});

Deno.test("klubben av for én kategori stopper ikke de andre", () => {
  eq(to(job(EAGLE, { club: ["club", "setup"] })).length, 3);
});

Deno.test("spilleren av: bare den spilleren slipper", () => {
  eq(to(job(EAGLE, { members: members({ [BJORN]: { disabled_categories: ["score"] } }) })), [THOMAS, CATO].sort());
});

Deno.test("på igjen: tom liste betyr alt på", () => {
  eq(to(job(EAGLE, { members: members({ [BJORN]: { disabled_categories: [] } }) })), [THOMAS, BJORN, CATO].sort());
});

Deno.test("«Melding til alle» kan ikke slås av, verken av klubben eller spilleren", () => {
  const a = activity("announcement", "announcement", { text: "Vi starter 17:00" }, { actor_member_id: THOMAS });
  ok(clubAllows({ id: "c", name: "G", disabled_categories: ["announcement"] }, "announcement"));
  const p = job(a, { club: ["announcement"], members: members({ [BJORN]: { disabled_categories: ["announcement"] } }) });
  eq(to(p), [ANDERS, BJORN, CATO].sort());
});

Deno.test("purring: klubben kan ikke slå den av, men spilleren kan", () => {
  const a = activity("nudge", "nudge", { event_date: "2026-10-08" }, { actor_member_id: THOMAS, recipients: [BJORN, CATO] });
  eq(to(job(a, { club: ["nudge"] })), [BJORN, CATO].sort());
  eq(to(job(a, { members: members({ [CATO]: { disabled_categories: ["nudge"] } }) })), [BJORN]);
});

Deno.test("påminnelse før kvelden kan slås av for klubben og per spiller", () => {
  const a = activity("reminder", "reminder", { event_date: "2026-10-15", coming: 9, unsure: 2 }, { actor_member_id: null });
  eq(to(job(a)), [THOMAS, ANDERS, BJORN, CATO].sort());
  is(planPush(job(a, { club: ["reminder"] }), NOW).skipped, "reminder er av for klubben");
  ok(!to(job(a, { members: members({ [ANDERS]: { disabled_categories: ["reminder"] } }) })).includes(ANDERS));
});

Deno.test("playerAllows og clubAllows tåler null-lister", () => {
  ok(playerAllows(member(ANDERS, "Anders", { disabled_categories: null }), "score"));
  ok(clubAllows({ id: "c", name: "G", disabled_categories: null }, "score"));
});

// --- Mottakere -----------------------------------------------------------------

Deno.test("mottakerliste: bare dem på lista", () => {
  const a = activity("nudge", "nudge", {}, { actor_member_id: THOMAS, recipients: [BJORN] });
  eq(to(job(a)), [BJORN]);
});

Deno.test("tom mottakerliste betyr ingen, aldri alle", () => {
  const a = activity("nudge", "nudge", {}, { actor_member_id: THOMAS, recipients: [] });
  const plan = planPush(job(a), NOW);
  eq(plan.notifications, []);
  is(plan.skipped, "ingen mottakere");
});

Deno.test("ledig navn og medlemmer uten telefon får ingenting", () => {
  const ms = members({ [CATO]: { devices: [] } });
  eq(to(job(EAGLE, { members: ms })), [THOMAS, BJORN].sort());
});

Deno.test("ett varsel per telefon", () => {
  const ms = members({
    [BJORN]: {
      devices: [
        { token: "b1", environment: "production", bundle_id: null },
        { token: "b2", environment: "sandbox", bundle_id: null },
      ],
    },
  });
  const plan = planPush(job(EAGLE, { members: ms }), NOW);
  eq(plan.notifications.filter((n) => n.memberId === BJORN).map((n) => [n.token, n.environment]), [
    ["b1", "production"],
    ["b2", "sandbox"],
  ]);
});

Deno.test("kladdrunde, ukjent kategori og gamle linjer hoppes over", () => {
  is(planPush(job({ ...EAGLE, round_status: "draft" }), NOW).skipped, "kladdrunde");
  is(planPush(job({ ...EAGLE, category: "penger" }), NOW).skipped, "ukjent kategori penger");
  is(planPush(job({ ...EAGLE, created_at: "2026-10-08T17:00:00Z" }), NOW).skipped, "for gammel");
  is(planPush({ ...job(EAGLE), activity: null }, NOW).skipped, "linja finnes ikke");
});

Deno.test("ledelsen erstatter forrige varsel for samme runde (collapse-id)", () => {
  const a = activity("lead_changed", "lead", { after_hole: 9, leaders: [BJORN], points: 19, outcome: "took_lead" }, { actor_member_id: null });
  const n = planPush(job(a), NOW).notifications[0];
  is(n.collapseId, "lead-round-1");
  is(planPush(job(EAGLE), NOW).notifications[0].collapseId, undefined);
});

// --- Tråden: alle / nevnt / av ------------------------------------------------

Deno.test("tråden: standard er «når jeg nevnes»", () => {
  eq(to(thread("Hei @Bjørn", ANDERS, [BJORN])), [BJORN]);
});

Deno.test("tråden: «alle» får alt, «av» får ingenting", () => {
  const ms = members({ [CATO]: { thread_mode: "all" }, [BJORN]: { thread_mode: "off" } });
  eq(to(thread("Hei @Bjørn", ANDERS, [BJORN], { members: ms })), [CATO]);
});

Deno.test("tråden: arrangørens meldinger går til alle som ikke har slått av", () => {
  const ms = members({ [CATO]: { thread_mode: "off" } });
  eq(to(thread("Husk kølle", THOMAS, [], { members: ms })), [ANDERS, BJORN].sort());
});

Deno.test("tråden: avsenderen får ikke sin egen melding", () => {
  const ms = members({ [ANDERS]: { thread_mode: "all" } });
  ok(!to(thread("Hei", ANDERS, [ANDERS], { members: ms })).includes(ANDERS));
});

Deno.test("tråden: ukjent valg leses som «når jeg nevnes»", () => {
  const ms = members({ [CATO]: { thread_mode: null }, [BJORN]: { thread_mode: "rart" } });
  eq(to(thread("Hei @Cato", ANDERS, [CATO], { members: ms })), [CATO]);
});

Deno.test("tråden: av for klubben, pushet fra før eller for gammel", () => {
  is(planPush(thread("Hei", ANDERS, [BJORN], { club: ["thread"] }), NOW).skipped, "tråden er av for klubben");
  const pushed = thread("Hei", ANDERS, [BJORN]);
  pushed.message!.pushed_at = RECENT;
  is(planPush(pushed, NOW).skipped, "pushet fra før");
  const old = thread("Hei", ANDERS, [BJORN]);
  old.message!.created_at = "2026-10-08T17:50:00Z";
  is(planPush(old, NOW).skipped, "for gammel");
});

Deno.test("tråden: tittel med kvelden og tekst med navn", () => {
  const n = planPush(thread("Hei   @Bjørn\nkommer du?", ANDERS, [BJORN]), NOW).notifications[0];
  is(n.title, "Tråden · torsdag 8. oktober");
  is(n.body, "Anders: Hei @Bjørn kommer du?");
  is(n.threadId, "thread-event-1");
  eq(n.data, { type: "thread", message_id: "msg-1", event_id: "event-1" });
});

Deno.test("tråden: bilde og lange meldinger (PWA: meldingTekst)", () => {
  is(threadText("Anders", "", true), "Anders: 📷 Bilde");
  is(threadText("Anders", "Se her", true), "Anders: 📷 Se her");
  const long = threadText("Anders", "x".repeat(200), false);
  is(long, "Anders: " + "x".repeat(159) + "…");
});

// --- Tekstene (samme som ActivityText i appen) ---------------------------------

const names = nameLookup(members());
const text = (a: ActivityPayload) => activityDisplay(a, names);

Deno.test("store scorer", () => {
  eq(text(EAGLE), { emoji: "🦅", text: "Anders eagle på hull 5 — 3 slag på par 5" });
  eq(text(activity("big_score", "score", { member: BJORN, hole: 7, name: "hole_in_one", strokes: 1, par: 3 })),
    { emoji: "🎯", text: "Bjørn HOLE IN ONE på hull 7!" });
  eq(text(activity("big_score", "score", { member: BJORN, hole: 7, name: "albatross", strokes: 2, par: 5 })).text,
    "Bjørn albatross på hull 7 — 2 slag på par 5");
});

Deno.test("ledelsesskifte", () => {
  eq(text(activity("lead_changed", "lead", { after_hole: 9, leaders: [BJORN], points: 19, outcome: "took_lead" })),
    { emoji: "📈", text: "Bjørn har tatt ledelsen etter 9 hull · 19 poeng" });
  is(text(activity("lead_changed", "lead", { after_hole: 18, leaders: [ANDERS, BJORN, CATO], points: 36, outcome: "tied_finish" })).text,
    "Anders, Bjørn og Cato endte likt etter 18 hull · 36 poeng");
});

Deno.test("ledelsesskifte: alle utfallene (loggLedelseHvisEndret)", () => {
  const lead = (outcome: string, leaders: string[], after: number, points: number) =>
    text(activity("lead_changed", "lead", { after_hole: after, leaders, points, outcome })).text;
  is(lead("leads", [ANDERS], 3, 8), "Anders leder etter 3 hull · 8 poeng");
  is(lead("took_lead", [BJORN], 6, 13), "Bjørn har tatt ledelsen etter 6 hull · 13 poeng");
  is(lead("shares", [ANDERS, BJORN], 9, 19), "Anders og Bjørn deler ledelsen etter 9 hull · 19 poeng");
  is(lead("won", [ANDERS], 18, 38), "Anders vant runden etter 18 hull · 38 poeng");
  is(lead("snatched", [BJORN], 9, 20), "Bjørn snappet runden på siste hull etter 9 hull · 20 poeng");
  is(lead("tied_finish", [ANDERS, BJORN], 18, 36), "Anders og Bjørn endte likt etter 18 hull · 36 poeng");
  // Ukjent utfall eller ingen ledere: nøytral tekst.
  is(lead("noe_annet", [ANDERS], 3, 8), "Ny hendelse i klubben");
  is(lead("leads", [], 3, 8), "Ny hendelse i klubben");
});

Deno.test("store scorer, ledelsen og ny runde går til alle andre, og kan slås av hver for seg", () => {
  const lead = activity("lead_changed", "lead", { after_hole: 3, leaders: [BJORN], points: 8, outcome: "leads" });
  const started = activity("round_started", "round", { round_no: 1 }, { actor_member_id: THOMAS });
  eq(to(job(EAGLE)), [BJORN, CATO, THOMAS].sort());
  eq(to(job(lead)), [BJORN, CATO, THOMAS].sort());
  eq(to(job(started)), [ANDERS, BJORN, CATO].sort());
  // Spilleren slår av store scorer: får fortsatt ledelsen og ny runde.
  const m = members({ [BJORN]: { disabled_categories: ["score"] } });
  eq(to(job(EAGLE, { members: m })), [CATO, THOMAS].sort());
  eq(to(job(lead, { members: m })), [BJORN, CATO, THOMAS].sort());
  // Klubben slår av ledelsen og rundene.
  eq(planPush(job(lead, { club: ["lead"] }), NOW).skipped, "lead er av for klubben");
  eq(planPush(job(started, { club: ["round"] }), NOW).skipped, "round er av for klubben");
});

Deno.test("alle typene appen skriver har en norsk tekst (ActivityEvent.knownKinds)", () => {
  // Minste data hver type trenger, slik appen skriver den (ActivityEvent.data).
  const minimal: Record<string, [string, Record<string, unknown>]> = {
    round_started: ["round", { round_no: 1 }],
    round_locked: ["round", { round_no: 1 }],
    round_deleted: ["round", { round_no: 1 }],
    big_score: ["score", { member: ANDERS, hole: 5, hole_index: 4, name: "eagle", strokes: 3, par: 5 }],
    lead_changed: ["lead", { after_hole: 3, leaders: [ANDERS], points: 8, outcome: "leads" }],
    side_prize: ["side_prize", { kind: "kp", member: ANDERS, hole: 3, meters: 2.4 }],
    score_corrected: ["setup", { member: ANDERS, hole: 5 }],
    signup: ["signup", { member: ANDERS, status: "yes" }],
    nudge: ["nudge", {}],
    reminder: ["reminder", {}],
    announcement: ["announcement", { text: "Hei" }],
    committee_drawn: ["social", {}],
    member_joined: ["club", { member: ANDERS }],
    tips_king: ["tips", { members: [ANDERS], correct: 4, possible: 5 }],
  };
  for (const [kind, [category, data]] of Object.entries(minimal)) {
    const shown = text(activity(kind, category, data));
    ok(shown.text !== "Ny hendelse i klubben", `${kind} mangler tekst`);
    ok(shown.emoji !== "🔔", `${kind} mangler emoji`);
  }
});

Deno.test("påmelding, påminnelse og purring uten dato", () => {
  is(text(activity("signup", "signup", { member: ANDERS, status: "yes", event_date: "2026-10-08" })).text,
    "Anders meldte seg på torsdag 8. oktober");
  is(text(activity("signup", "signup", { member: ANDERS, status: "maybe" })).text, "Anders er likevel usikker");
  is(text(activity("reminder", "reminder", {})).text, "Påminnelse: neste kveld nærmer seg");
  is(text(activity("nudge", "nudge", {})).text, "Hvem kommer? Svar i appen.");
  is(text(activity("round_deleted", "round", { round_no: 3, course_name: "St Andrews" }, { actor_member_id: THOMAS })).text,
    "Thomas slettet Runde 3 – St Andrews");
});

Deno.test("ny runde", () => {
  is(text(activity("round_started", "round", { round_no: 1, course_name: "Pebble Beach", hole_count: 18, bays: 3, ld_hole: 7 })).text,
    "Ny runde: Runde 1 – Pebble Beach · 18 hull — longest drive på hull 7, 3 båser");
  is(text(activity("round_locked", "round", { round_no: 2 }, { actor_member_id: THOMAS })).text, "Thomas låste Runde 2");
});

Deno.test("påminnelse, purring og melding til alle", () => {
  is(text(activity("reminder", "reminder", { event_date: "2026-10-08", coming: 9, unsure: 2 })).text,
    "Påminnelse: torsdag 8. oktober om en uke · 9 kommer, 2 usikre");
  is(text(activity("nudge", "nudge", { event_date: "2026-10-08" }, { recipients: [BJORN, CATO] })).text,
    "Hvem kommer torsdag 8. oktober? Mangler svar fra Bjørn og Cato — svar i appen.");
  is(text(activity("announcement", "announcement", { text: "Vi starter 17:00" }, { actor_member_id: THOMAS })).text,
    "Thomas: Vi starter 17:00");
});

Deno.test("sidepremie, retting, påmelding, komité, ny spiller og tippekonge", () => {
  is(text(activity("side_prize", "side_prize", { kind: "drive", member: BJORN, hole: 7, meters: 245, passed: ANDERS, passed_meters: 231.04 })).text,
    "Bjørn leder longest drive på hull 7 med 245 m — forbi Anders (231 m)");
  is(text(activity("score_corrected", "setup", { member: ANDERS, hole: 5, from: 5, to: 4, round_no: 1 }, { actor_member_id: THOMAS })).text,
    "Thomas rettet hull 5 for Anders i Runde 1: 5 → 4");
  is(text(activity("signup", "signup", { member: ANDERS, status: "no", event_date: "2026-10-08" })).text,
    "Anders meldte forfall til torsdag 8. oktober");
  is(text(activity("committee_drawn", "social", { event_date: "2026-10-08", members: [ANDERS, BJORN] })).text,
    "Sosialkomiteen torsdag 8. oktober: Anders og Bjørn");
  is(text(activity("member_joined", "club", { member: CATO })).text, "Cato ble med i klubben");
  is(text(activity("tips_king", "tips", { members: [ANDERS], correct: 4, possible: 5, event_date: "2026-10-08" })).text,
    "Tippekongen torsdag 8. oktober: Anders med 4 av 5 riktige");
});

Deno.test("ukjent type eller manglende felt gir en nøytral tekst, og ukjent navn er «Noen»", () => {
  eq(text(activity("noe_nytt", "club", {})), { emoji: "🔔", text: "Ny hendelse i klubben" });
  eq(text(activity("big_score", "score", { member: ANDERS })), { emoji: "🔔", text: "Ny hendelse i klubben" });
  is(text(activity("member_joined", "club", { member: "ukjent-id" })).text, "Noen ble med i klubben");
});

Deno.test("varselet: klubbnavnet som tittel, emoji foran teksten", () => {
  const n = planPush(job(EAGLE), NOW).notifications[0];
  is(n.title, "Golfgutu");
  is(n.body, "🦅 Anders eagle på hull 5 — 3 slag på par 5");
  eq(n.data, { type: "activity", activity_id: "act-1", kind: "big_score", event_id: "event-1", round_id: "round-1" });
  eq(apnsBody(n), {
    aps: { alert: { title: "Golfgutu", body: n.body }, sound: "default", "thread-id": "club-club-1" },
    dd18: { ...n.data, category: "score" },
  });
});

Deno.test("datoer og meter som i appen", () => {
  is(eveningLongText("2026-10-08"), "torsdag 8. oktober");
  is(eveningLongText("2026-03-29"), "søndag 29. mars");
  is(eveningLongText("2026-02-30"), "2026-02-30");
  is(formatMeters(272.45), "272,5 m");
  is(formatMeters(3.4), "3,4 m");
  is(formatMeters(245), "245 m");
});

// --- Svar fra APNs ----------------------------------------------------------------

Deno.test("APNs-svar: 410 og BadDeviceToken fjerner tokenet", () => {
  is(classifyApnsResponse(200), "sent");
  is(classifyApnsResponse(410, "Unregistered"), "dead");
  is(classifyApnsResponse(400, "BadDeviceToken"), "dead");
  is(classifyApnsResponse(400, "BadCollapseId"), "failed");
  is(classifyApnsResponse(429, "TooManyRequests"), "retry");
  is(classifyApnsResponse(503), "retry");
  is(classifyApnsResponse(0, "network"), "retry");
  is(classifyApnsResponse(403, "InvalidProviderToken"), "config");
  is(classifyApnsResponse(400, "DeviceTokenNotForTopic"), "config");
});

Deno.test("oppsummering: døde tokens samles, jobben er ferdig når noe kom fram", () => {
  const s = summarize([
    { token: "a", status: 200 },
    { token: "b", status: 410, reason: "Unregistered" },
    { token: "c", status: 400, reason: "BadDeviceToken" },
    { token: "d", status: 503 },
  ]);
  eq(s.deadTokens, ["b", "c"]);
  is(s.sent, 1);
  is(s.failed, 3);
  is(s.ok, true);
});

Deno.test("oppsummering: prøv igjen bare når ingenting kom fram og feilen kan gå over", () => {
  is(summarize([{ token: "a", status: 503 }, { token: "b", status: 429 }]).ok, false);
  is(summarize([{ token: "a", status: 403, reason: "InvalidProviderToken" }]).ok, false);
  is(summarize([{ token: "a", status: 410 }]).ok, true);
  is(summarize([]).ok, true);
});
