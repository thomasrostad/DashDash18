// Påmelding per kveld (steg 4, sql/045). Samme saker som appens DashDash18Tests/PameldingKveldTests.swift.
import { test } from "node:test";
import assert from "node:assert/strict";
import {
  DEADLINE_TEXT, entryDetail, fromLocalInput, isConfirmed, isMissing, logLine, settingsForm, settingsPatch, signupErrorText,
  signupText, summarize, summaryGroups, toLocalInput, waitlistText, type EveningGuest, type EveningSignup,
} from "../src/signups.ts";
import { initialParticipants } from "../src/rounds/logic.ts";

const id = (n: number) => `00000000-0000-0000-0000-${String(n).padStart(12, "0")}`;
const roster = ["Anders", "Bjørn", "Cato", "Dag", "Erik"].map((name, i) => ({ id: id(i + 1), display_name: name }));
const at = (s: number) => new Date(Date.UTC(2026, 9, 11, 12, 0, s)).toISOString();
const yes = (n: number, wait?: number): EveningSignup => ({ member_id: id(n), status: "yes", waitlisted_at: wait === undefined ? null : at(wait) });
const guest = (n: number, name: string, host: number, wait?: number): EveningGuest =>
  ({ id: id(n), event_id: id(500), name, invited_by: id(host), waitlisted_at: wait === undefined ? null : at(wait) });

test("ventelista teller ikke som kommer", () => {
  const s = summarize(roster, [yes(1), yes(2, 10), { member_id: id(3), status: "maybe" }]);
  assert.deepEqual(s.yes.map((e) => e.name), ["Anders"]);
  assert.deepEqual(s.waitlist.map((e) => e.name), ["Bjørn"]);
  assert.equal(s.coming, 1);
  assert.ok(isConfirmed(yes(1)));
  assert.ok(!isConfirmed(yes(2, 1)));
});

test("bekreftede gjester teller med, ventelista er medlemmer og gjester etter tid", () => {
  const s = summarize(roster, [yes(1), yes(2, 30), yes(3, 10)], [guest(50, "Ola", 1), guest(51, "Kari", 1, 20)]);
  assert.equal(s.coming, 2);
  assert.deepEqual(s.waitlist.map((e) => [e.name, e.place]), [["Cato", 1], ["Kari", 2], ["Bjørn", 3]]);
  assert.equal(entryDetail(s.guests[0]), "gjest av Anders");
  assert.equal(entryDetail(s.waitlist[1]), "gjest av Anders · nr. 2 på ventelista");
  assert.deepEqual(summaryGroups(s)[0].entries.map((e) => e.name), ["Anders", "Ola"]);
});

test("ikke sett og ikke svart når det er kjent", () => {
  const s = summarize(roster, [yes(1)], [], new Set([id(1), id(2)]));
  const groups = summaryGroups(s);
  assert.deepEqual(groups.map((g) => g.title), ["Kommer", "Usikker", "Kommer ikke", "Ikke svart", "Ikke sett"]);
  assert.deepEqual(groups[3].entries.map((e) => e.name), ["Bjørn"]);
  assert.deepEqual(groups[4].entries.map((e) => e.name), ["Cato", "Dag", "Erik"]);
  assert.deepEqual(summaryGroups(summarize(roster, [yes(1)])).map((g) => g.title), ["Kommer", "Usikker", "Kommer ikke", "Ikke svart"]);
});

test("teksten teller uten ventelista og med gjester (Tonight.signupText)", () => {
  const signups = [yes(1), yes(2), yes(3, 1), { member_id: id(4), status: "maybe" }];
  assert.equal(signupText(signups, [], 5), "2 av 5 kommer · 1 på venteliste · 1 usikker");
  assert.equal(signupText(signups, [guest(50, "Ola", 1), guest(51, "Kari", 2, 2)], 5), "2 av 5 kommer + 1 gjest · 2 på venteliste · 1 usikker");
  assert.equal(signupText([], [], 5), "Ingen har svart ennå · 5 i troppen");
  assert.equal(waitlistText(2), "På venteliste (nr. 2)");
});

test("runden tar ikke med ventelista (initialParticipants)", () => {
  const r = roster.map((m) => ({ id: m.id, name: m.display_name, handicap: null, seed: null }));
  assert.deepEqual(initialParticipants(r, [yes(1), yes(2, 1)]), { ids: [id(1)], source: "signups" });
  assert.equal(initialParticipants(r, [yes(2, 1)]).source, "everyone");
  // Gamle rader uten kolonnen.
  assert.deepEqual(initialParticipants(r, [{ member_id: id(1), status: "yes" }]).ids, [id(1)]);
});

test("fristen (DDB02) og manglende 045", () => {
  assert.equal(signupErrorText({ code: "DDB02", message: "x" }), DEADLINE_TEXT);
  assert.equal(signupErrorText({ code: "42501", message: "Ingen tilgang" }), "Ingen tilgang");
  assert.ok(isMissing("PGRST202"));
  assert.ok(isMissing("42703"));
  assert.ok(!isMissing("DDB02"));
});

test("innstillingene: av som standard, tak innenfor 1–500, frister rundtur", () => {
  const off = settingsForm(null);
  assert.deepEqual(settingsPatch(off), { max_players: null, signup_deadline: null, withdraw_deadline: null, allow_guests: false });
  const form = { ...off, hasMax: true, maxPlayers: 900, allowGuests: true, signupDeadline: "2026-10-14T12:00" };
  const patch = settingsPatch(form);
  assert.equal(patch.max_players, 500);
  assert.equal(patch.allow_guests, true);
  assert.equal(toLocalInput(patch.signup_deadline), "2026-10-14T12:00");
  assert.equal(fromLocalInput(""), null);
  assert.deepEqual(settingsForm({ id: id(1), ...patch }), { ...form, maxPlayers: 500 });
});

test("loggen", () => {
  const name = (m: string) => (m === id(1) ? "Anders" : undefined);
  assert.equal(logLine({ id: 1, member_id: id(1), guest_name: null, old_status: "yes", new_status: "no", changed_at: at(0), note: "late" }, name),
    "Anders: Kommer → Kommer ikke (etter fristen)");
  assert.equal(logLine({ id: 2, member_id: id(1), guest_name: "Ola", old_status: "none", new_status: "waitlist", changed_at: at(0), note: null }, name),
    "Ola (gjest av Anders): Ikke svart → Venteliste");
  assert.equal(logLine({ id: 3, member_id: null, guest_name: null, old_status: "waitlist", new_status: "yes", changed_at: at(0), note: "promoted" }, name),
    "Tidligere medlem: Venteliste → Kommer (fikk plass)");
});
