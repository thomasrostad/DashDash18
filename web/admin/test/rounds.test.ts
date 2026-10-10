// Runde-oppsettet. Sakene og tallene er de samme som i appens DashDash18Tests/RundeTests.swift
// (som igjen er fra PWA-ens markor-test.js, paamelding-test.js og slett-runde-test.js).
import { test } from "node:test";
import assert from "node:assert/strict";
import { formById, golfgutuRules, type CourseHoleRecord, type CourseRow } from "../../golfgutu-core/src/index.ts";
import {
  addSeat, allowsNewRound, applySidePrize, bayCounts, baysWithoutMarker, canKeepMatches, canStartAtTen, defaultBayCount,
  deleteButtonTitle, deleteLines, deleteMessage, deletedMessage, draftParticipants, drawIndividual, initialParticipants,
  issueMessage, makeMarker, markerIn, matchProblems, moveSeat, newDraft, nextRoundNo, playerMatch, redrawMatches,
  roundStatusText, roundTitle, roundWrite, saveErrorText, seatFor, setForm, setStart, setupIssues, setupParams,
  sidePrizeChoice, startErrorText, startOptions, suggestedBays, suggestedTeams, teamMatch, teamMatches, teamProblem,
  BAY_TERM, previousRound, applySuggestion, type RosterMember, type RoundDraft,
} from "../src/rounds/logic.ts";
import { coreCourseOf, coreCourseWithTee, courseItemReady, filterSlope, makeCourseItem, suggestedTee, type CourseTee } from "../src/rounds/courses.ts";

const id = (n: number) => `00000000-0000-0000-0000-${String(n).padStart(12, "0")}`;
const eventID = id(500);
const roster: RosterMember[] = ["Anders", "Bjørn", "Cato", "Dag", "Erik", "Frode", "Gunnar", "Halvor"]
  .map((name, i) => ({ id: id(i + 1), name, handicap: null, seed: null }));
const [a, b, c, d, e, f, g, h] = roster.map((m) => m.id);
const G = golfgutuRules();

function course(holes = 18, par: number | null = 4, rating: number | null = 72, slope: number | null = 113) {
  const row: CourseRow = { id: id(700), clubID: id(999), name: "Testbanen", externalName: null, courseRating: rating, slopeRating: slope, inUse: true };
  const records: CourseHoleRecord[] = par === null ? [] : Array.from({ length: holes }, (_, i) => ({ courseID: id(700), holeNumber: i + 1, par, strokeIndex: i + 1, lengthM: null }));
  return makeCourseItem(row, records, null);
}
const ready = (item = course()) => ({ name: item.course.name, isReady: courseItemReady(item) });

// MARK: Båser

test("åtte mann på tre båser med én markør hver", () => {
  const plan = suggestedBays([a, b, c, d, e, f, g, h], [], 3);
  assert.deepEqual(Object.fromEntries(bayCounts(plan)), { 1: 3, 2: 3, 3: 2 });
  for (const bay of [1, 2, 3]) assert.equal(plan.filter((s) => s.bay === bay && s.isMarker).length, 1);
  assert.deepEqual([markerIn(plan, 1), markerIn(plan, 2), markerIn(plan, 3)], [a, b, c]);
});

test("tolv blir fire, fire, fire", () => {
  const twelve = Array.from({ length: 12 }, (_, i) => id(i + 1));
  const count = defaultBayCount(12, G.formats.maxPerBay);
  assert.equal(count, 3);
  const plan = suggestedBays(twelve, [], count);
  assert.deepEqual(Object.fromEntries(bayCounts(plan)), { 1: 4, 2: 4, 3: 4 });
  assert.deepEqual(baysWithoutMarker(plan), []);
  assert.equal(plan.filter((s) => s.isMarker).length, 3);
});

test("antall båser følger regelsettet", () => {
  assert.equal(defaultBayCount(0, 4), 1);
  assert.equal(defaultBayCount(4, 4), 1);
  assert.equal(defaultBayCount(5, 4), 2);
  assert.equal(defaultBayCount(12, 6), 2);
});

test("duellpartnere sitter i samme bås", () => {
  const plan = suggestedBays([a, b, c, e, f, h], [[a, h], [c, f], [e, b]], 2);
  assert.equal(seatFor(plan, d), undefined);
  assert.equal(seatFor(plan, a)?.bay, seatFor(plan, h)?.bay);
  assert.equal(seatFor(plan, c)?.bay, seatFor(plan, f)?.bay);
  assert.equal(seatFor(plan, e)?.bay, seatFor(plan, b)?.bay);
  assert.deepEqual(baysWithoutMarker(plan), []);
});

test("spillere utenfor runden i en match hoppes over", () => {
  assert.deepEqual(suggestedBays([a, b], [[a, d], [b, a]], 1).map((s) => s.memberID), [a, b]);
});

test("markør som flyttes lar ingen bås stå uten", () => {
  let plan = suggestedBays(Array.from({ length: 12 }, (_, i) => id(i + 1)), [], 3);
  const m1 = markerIn(plan, 1)!;
  const m2 = markerIn(plan, 2)!;
  plan = moveSeat(plan, m1, 2);
  assert.equal(markerIn(plan, 2), m2);
  assert.ok(markerIn(plan, 1) !== undefined && markerIn(plan, 1) !== m1);
  assert.equal(seatFor(plan, m1)?.isMarker, false);
  plan = makeMarker(plan, m1);
  assert.equal(markerIn(plan, 2), m1);
  assert.equal(plan.filter((s) => s.bay === 2 && s.isMarker).length, 1);
});

test("markør til tom bås tar rollen med", () => {
  const plan = moveSeat(suggestedBays([a, b, c], [], 1), a, 2);
  assert.equal(markerIn(plan, 2), a);
  assert.equal(markerIn(plan, 1), b);
});

test("ut av båsene og inn igjen", () => {
  let plan = moveSeat(suggestedBays([a, b, c, d, e], [], 2), a, null);
  assert.equal(seatFor(plan, a), undefined);
  assert.equal(markerIn(plan, 1), c);
  plan = addSeat(plan, a);
  assert.deepEqual(seatFor(plan, a), { memberID: a, bay: 1, isMarker: false });
  assert.deepEqual(addSeat([], a), [{ memberID: a, bay: 1, isMarker: true }]);
});

// MARK: Deltakere

const signup = (m: string, status: string) => ({ member_id: m, status });

test("de påmeldte i troppens rekkefølge", () => {
  const r = initialParticipants(roster, [signup(e, "yes"), signup(a, "yes"), signup(b, "maybe"), signup(c, "no"), signup(h, "yes")]);
  assert.deepEqual(r, { ids: [a, e, h], source: "signups" });
});

test("ingen «Kommer» gir alle", () => {
  assert.deepEqual(initialParticipants(roster, [signup(b, "maybe")]), { ids: roster.map((m) => m.id), source: "everyone" });
});

test("kladden bruker de som er satt opp", () => {
  const saved = [b, f, a].map((memberID) => ({ memberID }));
  assert.deepEqual(draftParticipants(roster, saved, [signup(c, "yes")]), { ids: [a, b, f], source: "saved" });
  assert.deepEqual(draftParticipants(roster, [], [signup(c, "yes")]), { ids: [c], source: "signups" });
});

// MARK: Lag og matcher

test("elleve i toerscramble blir 3+3+3+2", () => {
  const eleven = Array.from({ length: 11 }, (_, i) => id(i + 1));
  const teams = suggestedTeams(eleven, formById("scramble-2"), 4);
  const sizes: Record<number, number> = {};
  for (const t of Object.values(teams)) sizes[t] = (sizes[t] ?? 0) + 1;
  assert.deepEqual(sizes, { 1: 3, 2: 3, 3: 3, 4: 2 });
  assert.equal(teamProblem(teams, eleven, formById("scramble-2"), 4), null);
  assert.deepEqual(suggestedTeams(eleven, formById("foursome"), 4), {});
});

test("lag som ikke går opp", () => {
  const foursome = formById("foursome");
  const four = [a, b, c, d];
  assert.equal(teamProblem({}, four, foursome, 4), "Sett opp lagene før du starter runden.");
  assert.equal(teamProblem({ [a]: 1, [b]: 1, [c]: 1, [d]: 1 }, four, foursome, 4), "Det må være minst to lag.");
  assert.equal(teamProblem({ [a]: 1, [b]: 1, [c]: 1, [d]: 2 }, four, foursome, 4), "Lag 1 og 2 har ikke 2 spillere.");
  assert.equal(teamProblem({ [a]: 1, [b]: 1, [c]: 2 }, four, foursome, 4), "Én av deltakerne har ikke lag.");
  assert.equal(teamProblem({ [a]: 1, [b]: 1, [c]: 1, [d]: 1, [e]: 1, [f]: 2 }, [a, b, c, d, e, f], formById("scramble-2"), 4),
    "Lag 1 har flere enn 4. Et lag får ikke plass i en bås da.");
});

test("lag mot lag: 1 mot 2, 3 mot 4", () => {
  assert.deepEqual(teamMatches({ [a]: 1, [b]: 1, [c]: 2, [d]: 2, [e]: 3, [f]: 3, [g]: 4, [h]: 4 }), [teamMatch(1, 2), teamMatch(3, 4)]);
});

test("trekningen gir dueller og en trekant ved oddetall", () => {
  assert.deepEqual(drawIndividual(roster.slice(0, 5)), [playerMatch(a, b), playerMatch(c, d, e)]);
  assert.deepEqual(drawIndividual([roster[0]]), []);
});

test("lagrede matcher står når de samme er med", () => {
  const m = [playerMatch(a, b), playerMatch(c, d)];
  assert.ok(canKeepMatches(m, [a, b, c, d], {}, false));
  assert.ok(!canKeepMatches(m, [a, b, c, d, e], {}, false));
  assert.ok(!canKeepMatches([], [a, b], {}, false));
  assert.ok(canKeepMatches([teamMatch(1, 2)], [a, b], { [a]: 1, [b]: 2 }, true));
  assert.ok(!canKeepMatches([teamMatch(1, 3)], [a, b], { [a]: 1, [b]: 2 }, true));
});

test("feil i matchene", () => {
  const names = new Map(roster.map((m) => [m.id, m.name]));
  assert.deepEqual(matchProblems([playerMatch(a, b), playerMatch(b, g), playerMatch(c, null)], [a, b, c], {}, names),
    ["Bjørn står i både match 1 og 2.", "Gunnar i match 2 er ikke med i runden.", "Match 3 mangler to forskjellige spillere."]);
});

// MARK: Sjekk før start

function draft(participants: string[], rules = G): RoundDraft {
  const dd = newDraft({ roundID: id(600), eventID, roundNo: 1, teeTime: "17:00:00", participants, source: "signups", rules });
  return redrawMatches({ ...dd, courseID: id(700) }, roster);
}

test("gyldig runde har ingen hindringer", () => {
  assert.deepEqual(setupIssues(draft([a, b, c, d]), ready(), G, roster, true), []);
});

test("banen må være klar", () => {
  assert.deepEqual(setupIssues(draft([a, b]), null, G, roster, false), [{ kind: "noCourse" }]);
  assert.deepEqual(setupIssues(draft([a, b]), ready(course(18, null)), G, roster, false), [{ kind: "courseNotReady", name: "Testbanen" }]);
});

test("start krever to spillere og markør i hver bås", () => {
  assert.ok(setupIssues(draft([a]), ready(), G, roster, true).some((i) => i.kind === "tooFewPlayers"));
  assert.deepEqual(setupIssues(draft([a]), ready(), G, roster, false), []);
  const setup = {
    ...draft([a, b, c, d, e, f]),
    bays: [
      { memberID: a, bay: 1, isMarker: true }, { memberID: b, bay: 1, isMarker: false },
      { memberID: c, bay: 2, isMarker: false }, { memberID: d, bay: 2, isMarker: false },
      { memberID: e, bay: 3, isMarker: false }, { memberID: f, bay: 3, isMarker: false },
    ],
  };
  assert.deepEqual(setupIssues(setup, ready(), G, roster, true), [{ kind: "bayWithoutMarker", bays: [2, 3] }]);
  assert.equal(issueMessage({ kind: "bayWithoutMarker", bays: [2, 3] }, BAY_TERM), "Bås 2 og 3 har ingen markør.");
});

test("formen må være tillatt i regelsettet", () => {
  const rules = golfgutuRules();
  rules.formats.allowedFormIDs = ["stableford"];
  const m = setForm(draft([a, b]), "match", rules, roster);
  assert.deepEqual(setupIssues(m, ready(), rules, roster, false), [{ kind: "formNotAllowed", name: "Matchspill (individuelt)" }]);
  const s = setForm(draft([a, b]), "skins", G, roster);
  assert.deepEqual(setupIssues(s, ready(), G, roster, false), [{ kind: "formNotSupported", name: "Skins" }]);
});

test("lagform krever lag som går opp", () => {
  const setup = setForm(draft([a, b, c, d]), "foursome", G, roster);
  assert.deepEqual(setup.teams, { [a]: 1, [b]: 1, [c]: 2, [d]: 2 });
  assert.deepEqual(setup.matches, [teamMatch(1, 2)]);
  assert.deepEqual(setupIssues(setup, ready(), G, roster, true), []);
  const wrong = { ...setup, teams: { ...setup.teams, [d]: 1 } };
  assert.ok(setupIssues(wrong, ready(), G, roster, true).some((i) => i.kind === "teams" && i.text === "Lag 1 og 2 har ikke 2 spillere."));
});

test("ny runde får regelsettets standarder", () => {
  const rules = golfgutuRules();
  rules.formats.defaultFormID = "match";
  rules.handicap.externalHandicap = true;
  rules.sidePrizes.closestToPin.enabled = false;
  const dd = newDraft({ roundID: id(600), eventID, roundNo: 2, teeTime: null, participants: [a, b], source: "signups", rules });
  assert.equal(dd.formID, "match");
  assert.equal(dd.allowance, 1.0);
  assert.ok(dd.externalHandicap && dd.ldEnabled && !dd.kpEnabled);
  const gg = newDraft({ roundID: id(600), eventID, roundNo: 1, teeTime: null, participants: [a, b], source: "signups", rules: G });
  assert.ok(gg.formID === "stableford" && gg.allowance === 0.95 && !gg.externalHandicap);
});

test("siste ni bare for 9 hull på en 18-hullsbane", () => {
  assert.ok(canStartAtTen(9, 18));
  assert.ok(!canStartAtTen(18, 18));
  assert.ok(!canStartAtTen(9, 9));
  assert.deepEqual(startOptions(18).map((s) => `${s.firstHole}/${s.holeCount}`), ["1/18", "1/9", "10/9"]);
  assert.deepEqual(startOptions(9).length, 2);
  const s = setStart({ ...draft([a, b]), ldHoleIndex: 15, kpHoleIndex: 4 }, { firstHole: 10, holeCount: 9 }, 18);
  assert.deepEqual([s.holeCount, s.firstHole, s.ldHoleIndex, s.kpHoleIndex], [9, 10, null, 4]);
});

// MARK: set_round_setup og raden

const players: RosterMember[] = [
  { id: id(1), name: "Anders", handicap: 10, seed: null }, { id: id(2), name: "Bjørn", handicap: 20.4, seed: null },
  { id: id(3), name: "Cato", handicap: 30, seed: 2 }, { id: id(4), name: "Dag", handicap: null, seed: null },
];
function setupDraft(): RoundDraft {
  const dd = newDraft({ roundID: id(600), eventID, roundNo: 1, teeTime: null, participants: players.map((p) => p.id), source: "signups", rules: G });
  return redrawMatches({ ...dd, courseID: id(700) }, players);
}

test("kladd sender oppsettet uten spillehandicap", () => {
  const p = setupParams(id(600), setupDraft(), players, coreCourseOf(course()), G, false);
  assert.equal(p.p_round_id, id(600));
  assert.equal(p.p_players.length, 4);
  assert.deepEqual(p.p_players[0], { member_id: id(1), bay_no: 1, is_marker: true, team_no: null, playing_handicap: null });
  assert.equal(p.p_players[1].is_marker, false);
  assert.deepEqual(p.p_matches, [
    { match_no: 1, player_a: id(1), player_b: id(2), player_c: null, team_a: null, team_b: null, result: null },
    { match_no: 2, player_a: id(3), player_b: id(4), player_c: null, team_a: null, team_b: null, result: null },
  ]);
});

test("start regner spillehandicap med effectiveHandicap", () => {
  // 10 · 0,95 = 9,5 → 10. 20,4 → 20 · 0,95 = 19. Seedet gruppe 2 → 5. Uten indeks → 0.
  const p = setupParams(id(600), setupDraft(), players, coreCourseOf(course()), G, true);
  assert.deepEqual(p.p_players.map((x) => x.playing_handicap), [10, 19, 5, 0]);
});

test("Trackman fordeler gir null", () => {
  const p = setupParams(id(600), { ...setupDraft(), externalHandicap: true }, players, coreCourseOf(course()), G, true);
  assert.deepEqual(p.p_players.map((x) => x.playing_handicap), [0, 0, 0, 0]);
});

test("lagform sender lag og lagmatcher", () => {
  const dd = setForm(setupDraft(), "fourball", G, players);
  const p = setupParams(id(600), dd, players, coreCourseOf(course()), G, true);
  assert.deepEqual(p.p_players.map((x) => x.team_no), [1, 1, 2, 2]);
  assert.deepEqual(p.p_matches, [{ match_no: 1, player_a: null, player_b: null, player_c: null, team_a: 1, team_b: 2, result: null }]);
  assert.deepEqual(p.p_players.map((x) => x.playing_handicap), [15, 15, 3, 3]);
});

test("spillere utenfor troppen og båsene tas ut", () => {
  const dd = setupDraft();
  const changed = { ...dd, participants: [...dd.participants, id(77)], bays: moveSeat(dd.bays, id(1), null) };
  const p = setupParams(id(600), changed, players, null, G, false);
  assert.deepEqual(p.p_players.map((x) => x.member_id), players.map((x) => x.id));
  assert.equal(p.p_players[0].bay_no, null);
  assert.equal(p.p_players[0].is_marker, false);
});

test("raden", () => {
  const dd = { ...setupDraft(), holeCount: 9, firstHole: 10, ldEnabled: false };
  const row = roundWrite(dd, id(999), coreCourseOf(course()));
  assert.equal(row.hole_count, 9);
  assert.equal(row.first_hole, 10);
  assert.equal(row.format, "stableford");
  assert.equal(row.handicap_allowance, 0.95);
  assert.equal(row.ld_enabled, false);
  // Forslaget lagres også når premien er av. Alle par 4: første par 4 (hull 1) for LD, KP hull 3.
  assert.equal(row.ld_hole_index, 0);
  assert.equal(row.kp_hole_index, 2);
  assert.equal(row.tee_time, null);
  assert.equal("status" in row, false);
  assert.equal(roundWrite({ ...dd, holeCount: 18 }, id(999), null).first_hole, 1);
});

// MARK: Liste og sletting

test("tittel og status", () => {
  assert.equal(roundTitle(2, "Pebble Beach"), "Runde 2 – Pebble Beach");
  assert.equal(roundTitle(1, null), "Runde 1");
  assert.deepEqual((["draft", "active", "locked"] as const).map(roundStatusText), ["Kladd", "Pågår", "Låst"]);
  assert.equal(nextRoundNo([]), 1);
  assert.equal(nextRoundNo([{ roundNo: 1 }, { roundNo: 3 }]), 4);
  assert.ok(allowsNewRound("2026-10-10", "2026-10-10"));
  assert.ok(!allowsNewRound("2026-10-09", "2026-10-10"));
});

test("slettingen teller førte hull", () => {
  const s = { holeScores: 6, playersWithScores: 2, sideClaims: 2, isDraft: false };
  assert.deepEqual(deleteLines(s), ["6 førte hull, fra 2 spillere", "2 innmeldte sidepremier"]);
  assert.equal(deleteButtonTitle(s), "Slett runden og 6 førte hull");
  assert.ok(deleteMessage(s).startsWith("Dette følger med ut, og kan ikke angres:"));
  const empty = { holeScores: 0, playersWithScores: 0, sideClaims: 0, isDraft: false };
  assert.ok(deleteMessage(empty).includes("Runden er tom"));
  assert.equal(deleteButtonTitle(empty), "Slett runden");
  assert.equal(deleteButtonTitle({ ...empty, isDraft: true }), "Slett kladden");
  assert.deepEqual(deleteLines({ holeScores: 1, playersWithScores: 1, sideClaims: 1, isDraft: false }), ["1 ført hull, fra 1 spiller", "1 innmeldt sidepremie"]);
  assert.equal(deletedMessage({ round_no: 3, hole_scores: 6, side_claims: 0 }), "Runde 3 er slettet, med 6 førte hull.");
});

test("feilene på norsk", () => {
  assert.equal(startErrorText({ code: "23505", message: "x" }), "En runde går allerede. Lås den før du starter en ny.");
  assert.equal(startErrorText({ code: "42501", message: "x" }), "Du har ikke tilgang til dette.");
  assert.equal(startErrorText({ code: "55000", message: "x" }), "Bare en kladd kan startes. Last inn på nytt og sjekk.");
  assert.equal(saveErrorText({ code: "23505", message: "x" }), "Kvelden har alt en runde med samme nummer. Last inn på nytt og prøv igjen.");
  assert.equal(saveErrorText({ code: "55000", message: "Runden er låst" }), "Runden er låst");
});

// MARK: Forslag fra forrige runde, sidepremier og baner

test("forrige startede runde i turneringen gir forslaget", () => {
  const events = [{ id: id(1), event_date: "2026-10-01" }, { id: id(2), event_date: "2026-10-08" }, { id: id(3), event_date: "2026-10-15" }];
  const base = { courseID: id(700), teeID: null, holeCount: 9, firstHole: 10, ldHoleIndex: 7, kpHoleIndex: 2, weight: 2, venue: "course" };
  const rounds = [
    { ...base, id: id(10), status: "locked" as const, eventID: id(1), roundNo: 2 },
    { ...base, id: id(11), status: "locked" as const, eventID: id(2), roundNo: 1 },
    { ...base, id: id(12), status: "draft" as const, eventID: id(2), roundNo: 2 },
    { ...base, id: id(13), status: "active" as const, eventID: id(3), roundNo: 1 },
  ];
  assert.equal(previousRound(rounds, events, "2026-10-08")?.id, id(11));
  const prev = previousRound(rounds, events, "2026-10-08");
  const item = course();
  const out = applySuggestion(draft([a, b]), prev, [{ id: item.course.id, isReady: true, holeCount: 18, teeIDs: [] }], G);
  assert.deepEqual([out.venue, out.weight, out.holeCount, out.firstHole, out.ldHoleIndex, out.kpHoleIndex, out.externalHandicap], ["course", 2, 9, 10, 7, 2, false]);
});

test("sidepremie som én rad", () => {
  assert.equal(sidePrizeChoice(false, 3, 5), null);
  assert.equal(sidePrizeChoice(true, null, 5), 5);
  assert.deepEqual(applySidePrize(null, 3, 5), { enabled: false, holeIndex: 3 });
  assert.deepEqual(applySidePrize(5, 3, 5), { enabled: true, holeIndex: null });
  assert.deepEqual(applySidePrize(7, null, 5), { enabled: true, holeIndex: 7 });
});

test("teen gir CR, slope og egne hull", () => {
  const tee = (n: number, gender: CourseTee["gender"], order: number, holes: CourseHoleRecord[] = []): CourseTee =>
    ({ id: id(n), courseID: id(700), name: `Tee ${n}`, gender, courseRating: 70.1, slopeRating: 125, par: null, sortOrder: order, holes });
  const own = Array.from({ length: 9 }, (_, i) => ({ courseID: id(700), holeNumber: i + 1, par: 3, strokeIndex: i + 1, lengthM: 120 }));
  const item = { ...course(), tees: [tee(31, "women", 0), tee(32, "men", 1, own)] };
  assert.equal(suggestedTee(item.tees, null)?.id, id(32));
  assert.equal(suggestedTee(item.tees, id(31))?.id, id(31));
  const plain = coreCourseWithTee(item, null);
  assert.deepEqual([plain.courseRating, plain.slopeRating, plain.par, plain.holes?.length], [72, 113, 72, 18]);
  const women = coreCourseWithTee(item, id(31));
  assert.deepEqual([women.courseRating, women.slopeRating, women.par, women.holes?.length], [70.1, 125, 72, 18]);
  const men = coreCourseWithTee(item, id(32));
  assert.deepEqual([men.par, men.holes?.length], [27, 9]);
});

test("søket i slope.no: norske først, alle ordene", () => {
  const list = [
    { id: "1", name: "Bærum Golfklubb", city: "Bærum", country: "NO", hasHoles: true },
    { id: "2", name: "Abc Golf", city: "Malmö", country: "SE", hasHoles: true },
    { id: "3", name: "Oslo Golfklubb", city: "Oslo", country: "NO", hasHoles: false },
    { id: "4", name: "Asker Golfklubb", city: "Asker", country: "NO", hasHoles: true },
  ];
  assert.deepEqual(filterSlope(list, "").map((x) => x.id), ["4", "1", "2"]);
  assert.deepEqual(filterSlope(list, "baerum golf").map((x) => x.id), []);
  assert.deepEqual(filterSlope(list, "bærum golf").map((x) => x.id), ["1"]);
  assert.deepEqual(filterSlope(list, "sverige").map((x) => x.id), ["2"]);
});
