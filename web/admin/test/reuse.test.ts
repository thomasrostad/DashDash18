import { test } from "node:test";
import assert from "node:assert/strict";
import { GOLFGUTU, newDraft, type RoundDraft } from "../src/rounds/logic.ts";
import {
  applyPreviousPlayers, applyRoundTemplate, decodePreviousSetup, decodeRoundTemplate, decodeTournamentTemplate, encodeRoundTemplate,
  encodeTournamentTemplate, isoWeekday, seriesDates, seriesText, templateNameError, type TournamentTemplate,
} from "../src/reuse.ts";

// MARK: Serie (create_event_series)

test("serie: start på riktig ukedag gir startdatoen først", () => {
  // 2026-10-15 er en torsdag.
  assert.equal(isoWeekday("2026-10-15"), 4);
  assert.deepEqual(seriesDates("2026-10-15", 4, 3), ["2026-10-15", "2026-10-22", "2026-10-29"]);
});

test("serie: start etter ukedagen går til neste uke", () => {
  // Fredag 16. oktober, ukedag torsdag: første er 22. oktober.
  assert.deepEqual(seriesDates("2026-10-16", 4, 2), ["2026-10-22", "2026-10-29"]);
  // Søndag (7) og mandag (1).
  assert.deepEqual(seriesDates("2026-10-18", 1, 1), ["2026-10-19"]);
  assert.deepEqual(seriesDates("2026-10-19", 7, 1), ["2026-10-25"]);
});

test("serie: annenhver uke og over nyttår", () => {
  assert.deepEqual(seriesDates("2026-12-20", 2, 3, 2), ["2026-12-22", "2027-01-05", "2027-01-19"]);
  assert.deepEqual(seriesDates("2026-12-28", 5, 2), ["2027-01-01", "2027-01-08"]);
});

test("serie: ugyldig gir ingen datoer, og høyst 52", () => {
  assert.deepEqual(seriesDates("", 4, 3), []);
  assert.deepEqual(seriesDates("2026-10-15", 0, 3), []);
  assert.deepEqual(seriesDates("2026-10-15", 4, 0), []);
  assert.equal(seriesDates("2026-10-15", 4, 60).length, 52);
});

test("serie: tekst", () => {
  assert.equal(seriesText({ weekday: 4, every_weeks: 1, start_time: "18:00:00" }), "Hver torsdag kl. 18");
  assert.equal(seriesText({ weekday: 2, every_weeks: 2, start_time: "18:30:00" }), "Annenhver tirsdag kl. 18.30");
  assert.equal(seriesText({ weekday: 1, every_weeks: 3, start_time: null }), "Hver 3. uke på mandag");
});

// MARK: Maler

function draft(): RoundDraft {
  return newDraft({ roundID: "r1", eventID: "e1", roundNo: 1, teeTime: null, participants: ["a", "b"], source: "signups", rules: GOLFGUTU });
}

test("rundemal: lagre og lese gir det samme, uten spillere", () => {
  const d: RoundDraft = {
    ...draft(), courseID: "c1", teeID: "t1", holeCount: 9, firstHole: 10, formID: GOLFGUTU.formats.allowedFormIDs[0],
    allowance: 0.95, externalHandicap: true, venue: "simulator", ldEnabled: true, ldHoleIndex: 3, kpEnabled: false, kpHoleIndex: null,
    weight: 2, counts: false, pointsTable: "finale", hideLastHoles: 3,
  };
  const payload = encodeRoundTemplate(d, [{ kind: "skins", settings: { stake: 10 } }]);
  assert.equal(payload.version, 1);
  assert.equal("participants" in payload || "players" in payload, false);
  const json = JSON.parse(JSON.stringify(payload));
  const t = decodeRoundTemplate(json);
  assert.deepEqual(t, {
    courseID: "c1", teeID: "t1", holeCount: 9, firstHole: 10, format: d.formID, allowance: 0.95, externalHandicap: true,
    venue: "simulator", ldEnabled: true, ldHoleIndex: 3, kpEnabled: false, kpHoleIndex: null, weight: 2, counts: false,
    pointsTable: "finale", hideLastHoles: 3, games: [{ kind: "skins", settings: { stake: 10 } }],
  });
  assert.deepEqual(Object.keys(payload).sort(), [
    "counts", "course_id", "external_handicap", "first_hole", "format", "games", "handicap_allowance", "hide_last_holes",
    "hole_count", "kp_enabled", "kp_hole_index", "ld_enabled", "ld_hole_index", "points_table", "tee_id", "venue", "version", "weight",
  ]);
});

test("rundemal: tåler manglende og ukjente nøkler", () => {
  const t = decodeRoundTemplate({ format: "x", unknown: true, games: [{ settings: {} }, "nei"] });
  assert.equal(t.holeCount, 18);
  assert.equal(t.firstHole, 1);
  assert.equal(t.weight, 1);
  assert.equal(t.counts, true);
  assert.equal(t.venue, null);
  assert.deepEqual(t.games, []);
  assert.deepEqual(decodeRoundTemplate(null).courseID, null);
});

test("rundemal: bruk fyller bane bare når den er klar, og form bare når den er tillatt", () => {
  const t = decodeRoundTemplate({ course_id: "c1", tee_id: "t9", hole_count: 9, first_hole: 10, format: "ukjent", weight: 2, ld_hole_index: 12 });
  const courses = [{ id: "c1", isReady: true, holeCount: 18, teeIDs: ["t1"] }];
  const d = applyRoundTemplate(draft(), t, courses, GOLFGUTU.formats.allowedFormIDs);
  assert.equal(d.courseID, "c1");
  assert.equal(d.teeID, null); // teen finnes ikke på banen
  assert.equal(d.firstHole, 10);
  assert.equal(d.ldHoleIndex, null); // utenfor 9 hull
  assert.equal(d.formID, draft().formID);
  assert.equal(d.weight, 2);
  const none = applyRoundTemplate(draft(), t, [{ ...courses[0], isReady: false }], GOLFGUTU.formats.allowedFormIDs);
  assert.equal(none.courseID, null);
});

test("turneringsmal: lagre og lese gir det samme, og tåler manglende nøkler", () => {
  const t: TournamentTemplate = {
    template: "matchSeries", kind: "season", rules: { version: 2, evenings: 7 },
    schedule: { weekday: 4, everyWeeks: 2, count: 10, startTime: "18:00", venue: "Bergen" },
    venue: "Bergen", entry: "club", signupOpen: false, maxEntrants: 24,
  };
  const payload = JSON.parse(JSON.stringify(encodeTournamentTemplate(t)));
  assert.deepEqual(payload.schedule, { weekday: 4, every_weeks: 2, count: 10, start_time: "18:00", venue: "Bergen" });
  assert.deepEqual(decodeTournamentTemplate(payload), t);
  const empty = decodeTournamentTemplate({ kind: "cup", schedule: { weekday: 9 }, other: 1 });
  assert.equal(empty.kind, "cup");
  assert.equal(empty.template, null);
  assert.equal(empty.schedule, null);
  assert.equal(empty.rules, null);
  assert.equal(decodeTournamentTemplate({ schedule: { weekday: 3, start_time: "17:30:00" } }).schedule?.startTime, "17:30");
});

test("malnavn", () => {
  const list = [{ id: "1", club_id: "k", owner_id: null, kind: "round" as const, name: "Torsdag", payload: {} }];
  assert.equal(templateNameError("  ", list, "round"), "Gi malen et navn.");
  assert.match(templateNameError("torsdag ", list, "round")!, /finnes alt/);
  assert.equal(templateNameError("torsdag", list, "tournament"), null);
  assert.equal(templateNameError("Torsdag", list, "round", "1"), null);
});

// MARK: «Samme som sist»

const previousJSON = {
  round_id: "r0", event_id: "e0", event_date: "2026-10-08", round_no: 2, status: "locked",
  course_id: "c1", tee_id: null, hole_count: 18, first_hole: 1, format: GOLFGUTU.formats.allowedFormIDs[0],
  handicap_allowance: 0.85, external_handicap: false, venue: "course", ld_enabled: true, ld_hole_index: 4,
  kp_enabled: true, kp_hole_index: 6, weight: 1, counts: true, points_table: null, hide_last_holes: 0, wave_no: 1,
  players: [
    { member_id: "a", bay_no: 1, is_marker: true, team_no: null, seed_group: 1 },
    { member_id: "b", bay_no: 1, is_marker: false, team_no: null, seed_group: null },
    { member_id: "gone", bay_no: 2, is_marker: true, team_no: null, seed_group: null },
    { member_id: "c", bay_no: 2, is_marker: false, team_no: null, seed_group: null },
  ],
  matches: [
    { match_no: 2, player_a: "c", player_b: "gone", player_c: null, team_a: null, team_b: null },
    { match_no: 1, player_a: "a", player_b: "b", player_c: null, team_a: null, team_b: null },
  ],
  games: [],
};

test("samme som sist: rundedelen fylles inn", () => {
  const prev = decodePreviousSetup(previousJSON)!;
  assert.equal(prev.roundNo, 2);
  assert.equal(prev.eventDate, "2026-10-08");
  const d = applyRoundTemplate(draft(), prev.round, [{ id: "c1", isReady: true, holeCount: 18, teeIDs: [] }], GOLFGUTU.formats.allowedFormIDs);
  assert.equal(d.courseID, "c1");
  assert.equal(d.venue, "course");
  assert.equal(d.allowance, 0.85);
  assert.equal(d.ldHoleIndex, 4);
  assert.equal(d.kpHoleIndex, 6);
  assert.equal(decodePreviousSetup(null), null);
  assert.equal(decodePreviousSetup({}), null);
});

test("samme som sist: spillerne som forslag, uten dem som er borte", () => {
  const prev = decodePreviousSetup(previousJSON)!;
  const roster = ["a", "b", "c", "d"].map((id) => ({ id, name: id.toUpperCase(), handicap: 10, seed: null }));
  const d = applyPreviousPlayers(draft(), prev, roster);
  assert.deepEqual(d.participants, ["a", "b", "c"]);
  assert.equal(d.participantSource, "saved");
  assert.deepEqual(d.bays.map((s) => [s.memberID, s.bay, s.isMarker]).sort(), [["a", 1, true], ["b", 1, false], ["c", 2, true]]);
  assert.equal(d.matches.length, 1);
  assert.deepEqual([d.matches[0].playerA, d.matches[0].playerB], ["a", "b"]);
});
