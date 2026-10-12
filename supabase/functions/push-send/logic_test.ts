// Tester for push-logikken (ROADMAP fase 8: push-kategorier-test.js av/på,
// og det push-status/påminnelse trenger fra senderen). Kjøres med
//   deno test supabase/functions/push-send/
// Ingen nettverk, ingen APNs, ingen database.

import { deepStrictEqual as eq, ok, strictEqual as is } from "node:assert/strict";
import {
  activityDisplay,
  type ActivityPayload,
  apnsBody,
  attachAlreadyNotified,
  attachBlocks,
  attachCompetitionBlocks,
  classifyApnsResponse,
  clubAllows,
  dayTermThe,
  dropoutLookup,
  eveningLongText,
  eveningStartedText,
  billShareSentText,
  billShareDisputedText,
  formatMeters,
  isRecipient,
  type JobPayload,
  type MemberPayload,
  nameLookup,
  planPush,
  playerAllows,
  pushLogResults,
  pushOriginators,
  quotedPreview,
  summarize,
  tableHeadline,
  tableSpots,
  tableSubject,
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
    bet_created: ["bet", { question: "Q" }],
    bet_challenge: ["bet", { question: "Q", against: ANDERS }],
    bet_resolved: ["bet", { question: "Q", resolution: "yes" }],
    waitlist_promoted: ["signup", { member: ANDERS }],
    signup_dropped: ["signup", { member: ANDERS }],
    evening_started: ["round", {}],
    bill_share_sent: ["social", { title: "Greenfee", name: "Anders" }],
    bill_share_disputed: ["social", { title: "Greenfee", name: "Thomas" }],
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
  is(text(activity("reminder", "reminder", {})).text, "Påminnelse: neste runde nærmer seg");
  is(text(activity("nudge", "nudge", {})).text, "Hvem kommer? Svar i appen.");
  is(text(activity("round_deleted", "round", { round_no: 3, course_name: "St Andrews" }, { actor_member_id: THOMAS })).text,
    "Thomas slettet Runde 3 – St Andrews");
});

Deno.test("venteliste og avmelding (sql/045)", () => {
  is(text(activity("waitlist_promoted", "signup", { member: ANDERS, event_date: "2026-10-08" })).text,
    "Du har fått plass torsdag 8. oktober");
  is(text(activity("waitlist_promoted", "signup", { member: ANDERS, guest_name: "Ola" })).text,
    "Ola har fått plass (gjesten din)");
  is(text(activity("signup_dropped", "signup", { member: BJORN, event_date: "2026-10-08", late: false })).text,
    "Bjørn har meldt seg av torsdag 8. oktober");
  is(text(activity("signup_dropped", "signup", { member: BJORN, late: true })).text, "Bjørn har meldt seg av etter fristen");
  is(text(activity("signup_dropped", "signup", {})).text, "Ny hendelse i klubben");
});

Deno.test("opprykk går bare til den som fikk plass, avmelding til arrangørene", () => {
  const promoted = activity("waitlist_promoted", "signup", { member: BJORN, event_date: "2026-10-08" },
    { recipients: [BJORN] });
  eq(planPush(job(promoted), NOW).notifications.map((n) => n.memberId), [BJORN]);
  const dropped = activity("signup_dropped", "signup", { member: BJORN }, { actor_member_id: BJORN, recipients: [THOMAS] });
  eq(planPush(job(dropped), NOW).notifications.map((n) => n.memberId), [THOMAS]);
  // Den som meldte seg av, står bak: har mottakeren blokkert hen, blir det ingen push.
  ok(pushOriginators(job(dropped)).includes(BJORN));
});

Deno.test("forfall: ett varsel per person (appens linje og serverens signup_dropped)", () => {
  // Bjørn melder forfall. Serveren varsler arrangøren (Thomas), appens linje går til alle andre.
  const app = activity("signup", "signup", { member: BJORN, status: "no", event_date: "2026-10-08" }, { actor_member_id: BJORN });
  eq(dropoutLookup(job(app)), { eventId: "event-1", member: BJORN, createdAt: RECENT });
  eq(planPush(job(app), NOW).notifications.map((n) => n.memberId), [THOMAS, ANDERS, CATO]);
  const server = { recipients: [THOMAS], created_at: "2026-10-08T17:58:59Z" };
  const withDrop = attachAlreadyNotified(job(app), [server]);
  eq(withDrop.already_notified_ids, [THOMAS]);
  eq(planPush(withDrop, NOW).notifications.map((n) => n.memberId), [ANDERS, CATO]);
  // Serverens linje går fortsatt bare til arrangøren.
  const dropped = activity("signup_dropped", "signup", { member: BJORN }, { actor_member_id: BJORN, recipients: [THOMAS] });
  eq(planPush(job(dropped), NOW).notifications.map((n) => n.memberId), [THOMAS]);
});

Deno.test("forfall: bare forfall, og bare signup_dropped nær i tid", () => {
  const yes = activity("signup", "signup", { member: BJORN, status: "yes" }, { actor_member_id: BJORN });
  eq(dropoutLookup(job(yes)), null);
  eq(attachAlreadyNotified(job(yes), [{ recipients: [THOMAS], created_at: RECENT }]).already_notified_ids, undefined);
  const noEvent = activity("signup", "signup", { member: BJORN, status: "no" }, { event_id: null });
  eq(dropoutLookup(job(noEvent)), null);
  const app = activity("signup", "signup", { member: BJORN, status: "no" }, { actor_member_id: BJORN });
  // En gammel avmelding (mer enn ti minutter unna) gjelder ikke.
  eq(attachAlreadyNotified(job(app), [{ recipients: [THOMAS], created_at: "2026-10-08T17:40:00Z" }]).already_notified_ids, undefined);
  eq(planPush(attachAlreadyNotified(job(app), []), NOW).notifications.length, 3);
  // recipients null: alle har fått den.
  eq(planPush(attachAlreadyNotified(job(app), [{ recipients: null, created_at: RECENT }]), NOW).skipped, "ingen mottakere");
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

Deno.test("veddemål: utfordring, nytt, avgjort og annullert (samme tekst som appen)", () => {
  is(text(activity("bet_challenge", "bet", { question: "Anders slår Thomas netto på hull 7", against: ANDERS, side: "yes", points: 50 }, { actor_member_id: THOMAS })).text,
    "Thomas utfordret Anders: «Anders slår Thomas netto på hull 7» — 50 poeng på JA");
  is(text(activity("bet_created", "bet", { question: "Noen får birdie på hull 3", side: "no", points: 20 }, { actor_member_id: THOMAS })).text,
    "Thomas åpnet «Noen får birdie på hull 3» og satset 20 poeng på NEI");
  is(text(activity("bet_created", "bet", { question: "Q" }, { actor_member_id: THOMAS })).text, "Thomas åpnet «Q»");
  is(text(activity("bet_resolved", "bet", { question: "Q", resolution: "no" }, { actor_member_id: null })).text, "Veddemål avgjort: «Q» → NEI");
  is(text(activity("bet_resolved", "bet", { question: "Q", resolution: "void", auto: true })).text, "Veddemål annullert: «Q»");
  eq(text(activity("bet_challenge", "bet", { question: "Q" })), { emoji: "🔔", text: "Ny hendelse i klubben" });
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

// --- Blokkering (sql/019 user_blocks, beslutning 08.10.2026) -----------------

// Innloggingene bak medlemmene. Carl er et ledig navn uten innlogging.
const USER = { [THOMAS]: "u-thomas", [ANDERS]: "u-anders", [BJORN]: "u-bjorn", [CATO]: "u-cato" };
const LINKS = [
  ...Object.entries(USER).map(([id, user_id]) => ({ id, user_id })),
  { id: CARL, user_id: null },
];
const block = (blocker: string, blocked: string) => ({ blocker_id: USER[blocker], blocked_id: USER[blocked] });
const blocked = (p: JobPayload, ...rows: { blocker_id: string; blocked_id: string }[]) => attachBlocks(p, LINKS, rows);

Deno.test("blokkering: tråden går ikke til den som har blokkert forfatteren", () => {
  const p = thread("hei alle", ANDERS, [], { members: members({ [BJORN]: { thread_mode: "all" }, [CATO]: { thread_mode: "all" } }) });
  eq(to(p), [BJORN, CATO].sort());
  eq(to(blocked(p, block(BJORN, ANDERS))), [CATO]);
});

Deno.test("blokkering: å bli nevnt av den du har blokkert gir ikke push", () => {
  eq(to(blocked(thread("@Bjørn", ANDERS, [BJORN]), block(BJORN, ANDERS))), []);
});

Deno.test("blokkering: arrangørens trådmelding stoppes også hvis du har blokkert arrangøren", () => {
  eq(to(blocked(thread("Husk kvelden", THOMAS, []), block(CATO, THOMAS))), [ANDERS, BJORN].sort());
});

Deno.test("blokkering: bare én retning, den blokkerte får fortsatt push fra den som blokkerte", () => {
  const p = thread("hei", BJORN, [], { members: members({ [ANDERS]: { thread_mode: "all" } }) });
  eq(to(blocked(p, block(BJORN, ANDERS))), [ANDERS]);
});

Deno.test("blokkering: stor score fra en blokkert stoppes, også når en annen førte den", () => {
  // Thomas førte (actor), Anders slo eaglen (data.member).
  const eagle = { ...EAGLE, actor_member_id: THOMAS };
  // (Anders får sin egen eagle når en annen førte den, som før.)
  eq(to(blocked(job(eagle), block(BJORN, ANDERS))), [ANDERS, CATO].sort());
  // Har du blokkert føreren, stoppes den også.
  eq(to(blocked(job(eagle), block(CATO, THOMAS))), [ANDERS, BJORN].sort());
});

Deno.test("blokkering: sidepremie, påmelding, ny spiller, ledelsen og tippekongen", () => {
  const cases: ActivityPayload[] = [
    activity("side_prize", "side_prize", { kind: "drive", member: ANDERS, hole: 3, meters: 250 }, { actor_member_id: THOMAS }),
    activity("signup", "signup", { member: ANDERS, status: "yes", event_date: "2026-10-15" }),
    activity("member_joined", "club", { member: ANDERS }),
    activity("lead_changed", "lead", { after_hole: 9, leaders: [ANDERS, CATO], points: 20, outcome: "shares" }, { actor_member_id: THOMAS }),
    activity("tips_king", "tips", { members: [ANDERS], correct: 5, possible: 7 }, { actor_member_id: null }),
  ];
  for (const a of cases) {
    ok(!to(blocked(job(a), block(BJORN, ANDERS))).includes(BJORN), a.kind);
    ok(to(job(a)).includes(BJORN), a.kind);
  }
});

Deno.test("blokkering: den som bare nevnes, stopper ikke pushen", () => {
  // Bjørn har blokkert Cato. Cato blir passert på sidepremien, får scoren rettet,
  // trekkes til komiteen eller står på purrelista: Bjørn får likevel push.
  const cases: ActivityPayload[] = [
    activity("side_prize", "side_prize", { kind: "kp", member: ANDERS, hole: 3, meters: 2, passed: CATO }),
    activity("score_corrected", "score", { member: CATO, hole: 3, from: 4, to: 5 }, { actor_member_id: THOMAS }),
    activity("committee_drawn", "social", { members: [CATO] }, { actor_member_id: THOMAS }),
    activity("nudge", "nudge", {}, { actor_member_id: THOMAS, recipients: [BJORN, CATO] }),
  ];
  for (const a of cases) ok(to(blocked(job(a), block(BJORN, CATO))).includes(BJORN), a.kind);
});

Deno.test("blokkering: melding til alle og purring fra en arrangør du har blokkert stoppes", () => {
  const ann = activity("announcement", "announcement", { text: "Hei" }, { actor_member_id: THOMAS });
  eq(to(blocked(job(ann), block(BJORN, THOMAS))), [ANDERS, CATO].sort());
  const nudge = activity("nudge", "nudge", {}, { actor_member_id: THOMAS, recipients: [BJORN, CATO] });
  eq(to(blocked(job(nudge), block(BJORN, THOMAS))), [CATO]);
});

Deno.test("blokkering: påminnelsen uten avsender går til alle", () => {
  const reminder = activity("reminder", "reminder", { event_date: "2026-10-15" }, { actor_member_id: null });
  eq(pushOriginators(job(reminder)), []);
  eq(to(blocked(job(reminder), block(BJORN, ANDERS))), [THOMAS, ANDERS, BJORN, CATO].sort());
});

Deno.test("blokkering: alle blokkerte gir «ingen mottakere»", () => {
  const p = blocked(thread("@Bjørn", ANDERS, [BJORN]), block(BJORN, ANDERS));
  is(planPush(p, NOW).skipped, "ingen mottakere");
});

Deno.test("blokkering: blokkeringer utenfor klubben og uten innlogging betyr ingenting", () => {
  const p = attachBlocks(job(EAGLE), LINKS, [
    { blocker_id: "u-fremmed", blocked_id: USER[ANDERS] },
    { blocker_id: USER[BJORN], blocked_id: "u-fremmed" },
  ]);
  eq(to(p), [THOMAS, BJORN, CATO].sort());
  eq(p.members.find((m) => m.id === CARL)?.blocked_member_ids, []);
});

Deno.test("blokkering: attachBlocks endrer ikke payloaden den får", () => {
  const p = job(EAGLE);
  blocked(p, block(BJORN, ANDERS));
  is(p.members.find((m) => m.id === BJORN)?.blocked_member_ids, undefined);
});

Deno.test("pushOriginators: forfatter, aktør og spilleren det handler om", () => {
  eq(pushOriginators(thread("hei", ANDERS, [])), [ANDERS]);
  eq(pushOriginators(job({ ...EAGLE, actor_member_id: THOMAS })).sort(), [THOMAS, ANDERS].sort());
  eq(pushOriginators(job(activity("lead_changed", "lead", { leaders: [ANDERS, CATO] }, { actor_member_id: null }))).sort(), [ANDERS, CATO].sort());
});

// --- Plassbytte i tabellen (table_changed, fase 19) ---------------------------
// Samme tekster som TableChangeText i appen (HjemTabellTests i DashDash18Tests).

const COMP = "00000000-0000-0000-0000-000000000500";
const tableRow = (table: unknown[], extra: Record<string, unknown> = {}) =>
  activity("table_changed", "round", { competition: COMP, competition_name: "Jakkeracet", round_no: 3, table, ...extra },
    { actor_member_id: THOMAS });

Deno.test("plassbytte: den som klatret mest", () => {
  const a = tableRow([
    { member: ANDERS, place: 1, from: 1, points: 58 },
    { member: BJORN, place: 2, from: 3, points: 55 },
    { member: CATO, place: 3, from: 5, points: 49.5 },
  ]);
  eq(text(a), { emoji: "📊", text: "Cato klatret til 3. plass i Jakkeracet etter runde 3" });
});

Deno.test("plassbytte: ny leder går foran, og likt hopp gir best plass", () => {
  is(text(tableRow([{ member: BJORN, place: 1, from: 2 }, { member: ANDERS, place: 2, from: 1 },
    { member: CATO, place: 3, from: 6 }])).text, "Bjørn har tatt ledelsen i Jakkeracet etter runde 3");
  is(text(tableRow([{ member: ANDERS, place: 1, from: 1 }, { member: BJORN, place: 2, from: 4 },
    { member: CATO, place: 4, from: 6 }])).text, "Bjørn klatret til 2. plass i Jakkeracet etter runde 3");
});

Deno.test("plassbytte: første runde, ingen runde og ingen som klatret", () => {
  is(text(tableRow([{ member: CATO, place: 1 }, { member: ANDERS, place: 2 }], { round_no: 1 })).text,
    "Cato leder Jakkeracet etter runde 1");
  is(text(tableRow([{ member: ANDERS, place: 1, from: 1 }], { round_no: undefined })).text,
    "Tabellen i Jakkeracet er oppdatert");
  is(tableHeadline([{ member: "x", place: 2, from: 2 }], "Morrocupen", 0, nameLookup([])),
    "Tabellen i Morrocupen er oppdatert");
});

Deno.test("plassbytte: ukjent navn og ugyldige data", () => {
  is(text(tableRow([{ member: "ukjent", place: 1, from: 2 }])).text, "Noen har tatt ledelsen i Jakkeracet etter runde 3");
  eq(text(tableRow([])).text, "Ny hendelse i klubben");
  eq(text(tableRow([{ member: ANDERS, place: "1" }])).text, "Ny hendelse i klubben");
  eq(text(activity("table_changed", "round", { competition_name: "X", table: [{ member: ANDERS, place: 1 }] })).text,
    "Ny hendelse i klubben");
  is(tableSpots(null), undefined);
  eq(tableSpots([{ member: ANDERS, place: 1, from: null }]), [{ member: ANDERS, place: 1, from: undefined, points: undefined }]);
  is(tableSubject([{ member: ANDERS, place: 2, from: 1 }]), undefined);
});

Deno.test("plassbytte: går som «Rundene», til alle unntatt den som låste, og erstatter forrige for konkurransen", () => {
  const a = tableRow([{ member: BJORN, place: 1, from: 2 }, { member: ANDERS, place: 2, from: 1 }]);
  eq(to(job(a)), [ANDERS, BJORN, CATO]);
  const n = planPush(job(a), NOW).notifications[0];
  is(n.category, "round");
  is(n.collapseId, `table-${COMP}`);
  is(n.body, "📊 Bjørn har tatt ledelsen i Jakkeracet etter runde 3");
  eq(to(job(a, { members: members({ [CATO]: { disabled_categories: ["round"] } }) })), [ANDERS, BJORN]);
  is(planPush(job(a, { club: ["round"] }), NOW).skipped, "round er av for klubben");
});

Deno.test("plassbytte: den linja handler om står bak (blokkering)", () => {
  const a = tableRow([{ member: BJORN, place: 1, from: 2 }, { member: ANDERS, place: 2, from: 1 }]);
  eq(pushOriginators(job(a)).sort(), [BJORN, THOMAS].sort());
  const blocked = attachBlocks(job(a), [{ id: CATO, user_id: "u-cato" }, { id: BJORN, user_id: "u-bjorn" }],
    [{ blocker_id: "u-cato", blocked_id: "u-bjorn" }]);
  eq(planPush(blocked, NOW).notifications.map((n) => n.memberId).sort(), [ANDERS, BJORN]);
});

// --- Varsler, steg 5 (sql/046) -----------------------------------------------

const STARTED = activity("evening_started", "round",
  { event_date: "2026-10-08", round_no: 1, course_name: "Pebble Beach", hole_count: 18 }, { actor_member_id: THOMAS });

Deno.test("046: collapse fra svaret blir apns-collapse-id, ellers som før", () => {
  const p = { ...job(EAGLE), collapse: "event-event-1-game", group: "game" };
  is(planPush(p, NOW).notifications[0].collapseId, "event-event-1-game");
  const lead = activity("lead_changed", "lead", { after_hole: 9, leaders: [BJORN], points: 19, outcome: "took_lead" }, { actor_member_id: null });
  is(planPush({ ...job(lead), collapse: null }, NOW).notifications[0].collapseId, "lead-round-1");
  is(planPush({ ...job(lead), collapse: "x".repeat(80) }, NOW).notifications[0].collapseId, "x".repeat(64));
});

Deno.test("046: «kvelden er i gang» med dato, runde og bane", () => {
  is(text(STARTED).emoji, "🏁");
  is(text(STARTED).text, "Runden er i gang: torsdag 8. oktober · Runde 1 – Pebble Beach");
  is(activityDisplay(STARTED, names, "evening").text, "Kvelden er i gang: torsdag 8. oktober · Runde 1 – Pebble Beach");
  is(activityDisplay(STARTED, names, "playingDay").text,
    "Spilledagen er i gang: torsdag 8. oktober · Runde 1 – Pebble Beach");
  is(eveningStartedText({ day_term: "spilledag", round_no: 2 }), "Spilledagen er i gang: Runde 2");
  is(eveningStartedText({ event_date: "2026-10-08" }), "Runden er i gang: torsdag 8. oktober");
  is(eveningStartedText({ course_name: "Losby" }), "Runden er i gang: Losby");
  is(eveningStartedText({}), "Runden er i gang");
  is(dayTermThe("Kveld"), "Kvelden");
  is(dayTermThe("noe annet"), undefined);
  is(dayTermThe(null), undefined);
});

Deno.test("046: «kvelden er i gang» går til alle andre, med ordet fra svaret", () => {
  const plan = planPush({ ...job(STARTED), day_term: "evening" }, NOW);
  eq(plan.notifications.map((n) => n.memberId).sort(), [ANDERS, BJORN, CATO].sort());
  is(plan.notifications[0].body, "🏁 Kvelden er i gang: torsdag 8. oktober · Runde 1 – Pebble Beach");
  is(plan.notifications[0].category, "round");
});

const withUsers = (ms: MemberPayload[]) => ms.map((m) => ({ ...m, user_id: m.active ? `u-${m.display_name}` : null }));
const reasons = (p: JobPayload, results = [] as { token: string; status: number; reason?: string }[]) =>
  Object.fromEntries(pushLogResults(p, planPush(p, NOW), results).map((r) => [r.user_id, r.reason ?? r.status]));

Deno.test("046: dempet eller gruppe av gir ingen push, og grunnen logges", () => {
  const ms = withUsers(members({ [BJORN]: { muted: true, devices: [] }, [CATO]: { group_off: true, devices: [] } }));
  const p = job(EAGLE, { members: ms });
  const plan = planPush(p, NOW);
  eq(plan.notifications.map((n) => n.memberId), [THOMAS]);
  eq(pushLogResults(p, plan, [{ token: "thomas-token", status: 200 }]), [
    { user_id: "u-Anders", channel: "push", status: "skipped", reason: "actor" },
    { user_id: "u-Bjørn", channel: "push", status: "skipped", reason: "muted" },
    { user_id: "u-Cato", channel: "push", status: "skipped", reason: "group_off" },
    { user_id: "u-Thomas", channel: "push", status: "sent" },
  ]);
});

Deno.test("046: loggen gir grunn for kategori, klubb, mottakerliste, blokkering og alder", () => {
  const ms = withUsers(members({ [BJORN]: { disabled_categories: ["score"] } }));
  eq(reasons(job(EAGLE, { members: ms })),
    { "u-Anders": "actor", "u-Bjørn": "category_off", "u-Cato": "ikke sendt", "u-Thomas": "ikke sendt" });
  eq(reasons(job(EAGLE, { members: ms, club: ["score"] })),
    { "u-Anders": "actor", "u-Bjørn": "club_off", "u-Cato": "club_off", "u-Thomas": "club_off" });
  eq(reasons(job({ ...EAGLE, created_at: "2026-10-08T17:00:00Z" }, { members: ms })),
    { "u-Anders": "actor", "u-Bjørn": "too_old", "u-Cato": "too_old", "u-Thomas": "too_old" });
  eq(reasons(job({ ...EAGLE, recipients: [CATO] }, { members: ms }), [{ token: "cato-token", status: 200 }]),
    { "u-Anders": "actor", "u-Bjørn": "not_recipient", "u-Cato": "sent", "u-Thomas": "not_recipient" });
  const blocked = attachBlocks(job(EAGLE, { members: ms }),
    [{ id: ANDERS, user_id: "ua" }, { id: CATO, user_id: "uc" }], [{ blocker_id: "uc", blocked_id: "ua" }]);
  is(reasons(blocked)["u-Cato"], "blocked");
  // Kladd logges ikke, og ledige navn (uten innlogging) logges aldri.
  const draft = job({ ...EAGLE, round_status: "draft" }, { members: ms });
  eq(pushLogResults(draft, planPush(draft, NOW)), []);
  ok(!("u-Carl" in reasons(job(EAGLE, { members: ms }))));
});

Deno.test("046: sent når minst én telefon fikk den, ellers failed med APNs-grunnen", () => {
  const ms = withUsers(members({
    [THOMAS]: { devices: [
      { token: "t1", environment: "production", bundle_id: null },
      { token: "t2", environment: "sandbox", bundle_id: null },
    ] },
  }));
  const p = job(EAGLE, { members: ms });
  const plan = planPush(p, NOW);
  const results = plan.notifications.map((n) =>
    n.token === "t1" ? { token: n.token, status: 410, reason: "Unregistered" } :
    n.token === "t2" ? { token: n.token, status: 200 } :
    { token: n.token, status: 400, reason: "BadDeviceToken" }
  );
  const log = Object.fromEntries(pushLogResults(p, plan, results).map((r) => [r.user_id, r]));
  is(log["u-Thomas"].status, "sent");
  is(log["u-Bjørn"].status, "failed");
  is(log["u-Bjørn"].reason, "400 BadDeviceToken");
});

Deno.test("046: tråden logger nevnt, av, forfatter og demping", () => {
  const ms = withUsers(members({ [CATO]: { thread_mode: "off" }, [BJORN]: { muted: true, devices: [] } }));
  eq(reasons(thread("Hei @Bjørn @Thomas", ANDERS, [BJORN, THOMAS], { members: ms }), [{ token: "thomas-token", status: 200 }]),
    { "u-Anders": "actor", "u-Bjørn": "muted", "u-Cato": "category_off", "u-Thomas": "sent" });
  eq(reasons(thread("Hei", ANDERS, [], { members: ms })),
    { "u-Anders": "actor", "u-Cato": "category_off", "u-Thomas": "not_recipient", "u-Bjørn": "not_recipient" });
});

// Turnering uten klubb: medlemmene er profiler.
const P1 = "10000000-0000-0000-0000-000000000001";
const P2 = "10000000-0000-0000-0000-000000000002";
const P3 = "10000000-0000-0000-0000-000000000003";
const ACTOR_MEMBER = "20000000-0000-0000-0000-000000000001";

function competitionJob(a: ActivityPayload): JobPayload {
  return {
    job_id: 3,
    kind: "activity",
    club: { id: null, name: "Sommerserien", disabled_categories: [] },
    activity: a,
    message: null,
    members: [member(P1, "Per"), member(P2, "Pål", { is_organizer: true }), member(P3, "Espen")],
    audience: "competition",
    competition: { id: "comp-1", name: "Sommerserien" },
    group: "evening",
    collapse: null,
  };
}

Deno.test("046: turnering uten klubb får threadId competition-<id> og turneringens navn", () => {
  const plan = planPush(competitionJob(activity("announcement", "announcement", { text: "Hei" }, { actor_member_id: null })), NOW);
  eq(plan.notifications.map((n) => n.threadId), ["competition-comp-1", "competition-comp-1", "competition-comp-1"]);
  is(plan.notifications[0].title, "Sommerserien");
});

Deno.test("046: turnering uten klubb: aktøren og blokkering leses per innlogging", () => {
  const a = activity("announcement", "announcement", { text: "Hei" }, { actor_member_id: ACTOR_MEMBER });
  const p = attachCompetitionBlocks(competitionJob(a), [{ id: ACTOR_MEMBER, user_id: P2 }],
    [{ blocker_id: P3, blocked_id: P2 }, { blocker_id: "en-annen", blocked_id: P2 }]);
  is(p.actor_user_id, P2);
  eq(p.members.find((m) => m.id === P3)!.blocked_member_ids, [ACTOR_MEMBER]);
  eq(to(p), [P1]);
  eq(reasons(p, [{ token: "per-token", status: 200 }]), { [P1]: "sent", [P2]: "actor", [P3]: "blocked" });
});

Deno.test("046: turnering uten klubb: en profil som står bak, blokkeres direkte", () => {
  const a = activity("signup_dropped", "signup", { member: P1, event_date: "2026-10-08" }, { actor_member_id: null });
  const p = attachCompetitionBlocks(competitionJob(a), [], [{ blocker_id: P2, blocked_id: P1 }]);
  // Pål har blokkert Per, som linja handler om. Ingen aktør, så Per og Espen får den.
  eq(to(p), [P1, P3]);
});

Deno.test("046: uten 046-feltene er alt som før", () => {
  const plan = planPush(job(EAGLE), NOW);
  is(plan.notifications[0].threadId, "club-club-1");
  eq(pushLogResults(job(EAGLE), plan), []);
});

// ---------------------------------------------------------------------------
// Sosialt (sql/050): kommentarer, omtale og bildeoppfordring
// ---------------------------------------------------------------------------

const COMMENT_DATA = {
  target_kind: "activity", target_id: "act-0", comment_id: "c-1", preview: "Hei   der\nfolkens",
  author_name: "Anders Berg",
};

Deno.test("050: tekstene for kommentar, omtale og bildeoppfordring", () => {
  const name = nameLookup(members());
  eq(activityDisplay(activity("comment_added", "social", COMMENT_DATA), name),
    { emoji: "💬", text: "Anders Berg kommenterte: «Hei der folkens»" });
  eq(activityDisplay(activity("mentioned", "social", COMMENT_DATA), name),
    { emoji: "💬", text: "Anders Berg nevnte deg: «Hei der folkens»" });
  // Uten navn i data: aktøren. Uten tekst: uten sitat.
  eq(activityDisplay(activity("comment_added", "social", {}), name), { emoji: "💬", text: "Anders kommenterte" });
  eq(activityDisplay(activity("photo_prompt", "social", { event_date: "2026-10-08", round_no: 3 }, { actor_member_id: null }), name),
    { emoji: "📸", text: "Ta et bilde av gjengen" });
});

Deno.test("050: sitatet kuttes til 80 tegn", () => {
  const q = quotedPreview("a".repeat(120))!;
  is(Array.from(q).length, 82);
  ok(q.endsWith("…»"));
  is(quotedPreview("   "), undefined);
  is(quotedPreview(undefined), undefined);
});

Deno.test("050: kommentaren går bare til mottakerne, ikke til den som skrev", () => {
  const a = activity("comment_added", "social", COMMENT_DATA, { recipients: [THOMAS, BJORN] });
  const plan = planPush(job(a), NOW);
  eq(plan.notifications.map((n) => n.memberId).sort(), [BJORN, THOMAS].sort());
  eq(plan.notifications[0].data.target_kind, "activity");
  eq(plan.notifications[0].data.target_id, "act-0");
  // Ingen collapse fra 046 for kommentarer: hver står.
  is(plan.notifications[0].collapseId, undefined);
});

Deno.test("050: turnering uten klubb: mottakerne er profil-id-er, forfatteren er en profil", () => {
  const data = { ...COMMENT_DATA, author_profile: P1, author_name: "Per" };
  const a = activity("comment_added", "social", data, { actor_member_id: null, recipients: [P1, P3] });
  const p = competitionJob(a);
  // Per skrev: får ikke sin egen. Espen står på lista. Pål gjør ikke.
  eq(to(p), [P3]);
  eq(reasons(p, [{ token: "espen-token", status: 200 }]), { [P1]: "actor", [P2]: "not_recipient", [P3]: "sent" });
  // Forfatteren står bak: den som har blokkert Per, får ikke push.
  eq(pushOriginators(p), [P1]);
  const blocked = attachCompetitionBlocks(p, [], [{ blocker_id: P3, blocked_id: P1 }]);
  eq(to(blocked), []);
});

Deno.test("050: mottakerlista leses som innloggingen uten klubb", () => {
  const a = activity("mentioned", "social", COMMENT_DATA, { recipients: ["user-espen"] });
  const p = { ...competitionJob(a), members: [member("annen-id", "Espen", { user_id: "user-espen" })] };
  ok(isRecipient(p, a, p.members[0]));
  // I en klubb er id-ene medlemmer: innloggingen teller ikke.
  ok(!isRecipient(job(a), a, member("annen-id", "Espen", { user_id: "user-espen" })));
  ok(isRecipient(job(a), { ...a, recipients: null }, member("hvem-som-helst", "X")));
});

// --- Del regningen (sql/051) ---------------------------------------------------

Deno.test("051: «har sendt sin del» og «ikke kom» med tittel og navn", () => {
  const sent = activity("bill_share_sent", "social", { split_id: "s1", share_id: "d1", title: "Simulatorleie", name: "Anders" },
    { actor_member_id: ANDERS, recipients: [THOMAS] });
  is(text(sent).emoji, "💸");
  is(text(sent).text, "Anders har sendt sin del for Simulatorleie");
  const disputed = activity("bill_share_disputed", "social", { title: "Simulatorleie", name: "Thomas" },
    { actor_member_id: THOMAS, recipients: [ANDERS] });
  is(text(disputed).text, "Thomas sier at din del for Simulatorleie ikke kom");
  is(billShareSentText({}), "Noen har sendt sin del for regningen");
  is(billShareDisputedText({ name: " ", title: null }), "Mottakeren sier at din del for regningen ikke kom");
});

Deno.test("051: regningslinjene går bare til mottakeren på linja", () => {
  const sent = activity("bill_share_sent", "social", { title: "Greenfee", name: "Anders" },
    { actor_member_id: ANDERS, recipients: [THOMAS] });
  const plan = planPush(job(sent), NOW);
  eq(plan.notifications.map((n) => n.memberId), [THOMAS]);
  is(plan.notifications[0].body, "💸 Anders har sendt sin del for Greenfee");
});

// --- Følge (sql/054): personlige linjer, audience 'person' -------------------

function personJob(a: ActivityPayload, list: MemberPayload[] = [member(P1, "Per"), member(P3, "Espen")]): JobPayload {
  return {
    job_id: 4,
    kind: "activity",
    club: { id: null, name: "Atten", disabled_categories: [] },
    activity: a,
    message: null,
    members: list,
    audience: "person",
    competition: null,
    group: "social",
    collapse: null,
  };
}

function follow(kind: string, to: string[], extra: Partial<ActivityPayload> = {}): ActivityPayload {
  return activity(kind, "social", { actor_name: "Pål", source: "search" },
    { actor_member_id: null, actor_profile_id: P2, event_id: null, round_id: null, recipients: to, ...extra });
}

Deno.test("054: tekstene for følging", () => {
  const name = nameLookup([]);
  eq(activityDisplay(follow("follow_requested", [P1]), name), { emoji: "👋", text: "Pål vil følge deg" });
  eq(activityDisplay(follow("follow_accepted", [P1]), name), { emoji: "✅", text: "Pål godtok forespørselen din" });
  eq(activityDisplay(follow("followed", [P1]), name), { emoji: "👋", text: "Pål følger deg nå" });
  // Uten navn: «Noen».
  eq(activityDisplay(activity("followed", "social", { actor_name: " " }, { actor_member_id: null }), name),
    { emoji: "👋", text: "Noen følger deg nå" });
});

Deno.test("054: følgevarselet går bare til mottakeren, med tittelen Atten og threadId follow", () => {
  const plan = planPush(personJob(follow("follow_requested", [P1])), NOW);
  eq(plan.notifications.map((n) => n.memberId), [P1]);
  is(plan.notifications[0].title, "Atten");
  is(plan.notifications[0].body, "👋 Pål vil følge deg");
  is(plan.notifications[0].threadId, "follow");
  is(plan.notifications[0].category, "social");
  eq(reasons(personJob(follow("follow_requested", [P1])), [{ token: "per-token", status: 200 }]),
    { [P1]: "sent", [P3]: "not_recipient" });
});

Deno.test("054: aktøren er profilen, og den som har blokkert aktøren får ikke push", () => {
  const a = follow("followed", [P1, P2]);
  const withActor = personJob(a, [member(P1, "Per"), member(P2, "Pål")]);
  // Pål er aktøren og får ikke sin egen.
  eq(to(withActor), [P1]);
  eq(pushOriginators(withActor), [P2]);
  const blocked = attachCompetitionBlocks(withActor, [], [{ blocker_id: P1, blocked_id: P2 }]);
  eq(to(blocked), []);
  eq(reasons(blocked), { [P1]: "blocked", [P2]: "actor" });
});

Deno.test("054: round_finished går aldri som push", () => {
  const a = activity("round_finished", "round", { player_id: "x" },
    { actor_member_id: null, actor_profile_id: P2, recipients: null });
  const plan = planPush(personJob(a), NOW);
  eq(plan.notifications, []);
  is(plan.skipped, "round_finished går ikke som push");
});

Deno.test("054: kommentar på et kort i «Følger»", () => {
  const data = { ...COMMENT_DATA, author_profile: P2, author_name: "Pål" };
  const a = activity("comment_added", "social", data,
    { actor_member_id: null, actor_profile_id: P2, round_id: "round-9", recipients: [P1] });
  const plan = planPush(personJob(a), NOW);
  eq(plan.notifications.map((n) => n.memberId), [P1]);
  is(plan.notifications[0].body, "💬 Pål kommenterte runden: «Hei der folkens»");
  is(plan.notifications[0].threadId, "card-act-0");
  is(plan.notifications[0].data.target_id, "act-0");
  // I klubben er teksten som før.
  is(text(activity("comment_added", "social", COMMENT_DATA)).text, "Anders Berg kommenterte: «Hei der folkens»");
});

Deno.test("054: profil-id-er på mottakerlista leses som innloggingen også for person", () => {
  const a = follow("follow_accepted", ["user-espen"]);
  const p = personJob(a, [member("annen-id", "Espen", { user_id: "user-espen" })]);
  ok(isRecipient(p, a, p.members[0]));
});
