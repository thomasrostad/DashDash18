// Deltakere uten innlogging og lenken til turneringen (pakke 2, punkt 5; sql/059–061). Samme regler og tekster
// som ParticipantImport.canAdd og InviteTarget.competition i appen (DashDash18Tests/DeltakerInvitasjonTests.swift).
import { test } from "node:test";
import assert from "node:assert/strict";
import { INVITE_HELP, canAddParticipants, inviteDisplay, inviteFromRow, inviteShareText, inviteURL, participantErrorText } from "../src/participants.ts";

const base = { club_id: "k1", entry: "listed", kind: "league" as const, status: "active" as const };

test("bare klubbturneringer med påmelding som ikke er ferdige", () => {
  assert.equal(canAddParticipants(base), true);
  assert.equal(canAddParticipants({ ...base, kind: "cup" }), true);
  assert.equal(canAddParticipants({ ...base, kind: "fun" }), true);
  assert.equal(canAddParticipants({ ...base, kind: "season" }), false);
  assert.equal(canAddParticipants({ ...base, entry: "club" }), false);
  assert.equal(canAddParticipants({ ...base, status: "finished" }), false);
  assert.equal(canAddParticipants({ ...base, club_id: null }), false);
});

test("lenken, koden og teksten som deles", () => {
  assert.equal(inviteURL("ABCDEFGHJK"), "https://dashdash18.com/konkurranse/ABCDEFGHJK");
  assert.equal(inviteDisplay("ABCDEFGHJK"), "ABCDE-FGHJK");
  assert.equal(inviteShareText("Høstligaen", "Oslo Sim", "ABCDEFGHJK"),
    "Bli med i Høstligaen (Oslo Sim) i Atten. Står du på lista, tar du plassen din.\n"
    + "https://dashdash18.com/konkurranse/ABCDEFGHJK\n"
    + "Eller skriv inn koden ABCDE-FGHJK under Turneringer → «Har du en kode?».");
  assert.match(INVITE_HELP, /Koden virker i 60 dager/);
});

test("svaret fra competition_invite", () => {
  assert.deepEqual(inviteFromRow({ code: "ABCDEFGHJK", expires_at: "2026-12-22T10:00:00Z" }), { code: "ABCDEFGHJK", expiresAt: "2026-12-22T10:00:00Z" });
  assert.throws(() => inviteFromRow(null), /ugyldig kode/);
});

test("feilene", () => {
  assert.equal(participantErrorText({ code: "54000", message: "Høyst 300 om gangen" }), "Høyst 300 om gangen");
  assert.equal(participantErrorText({ code: "PGRST202", message: "x" }), "Dette kan ikke brukes før databasen er oppdatert.");
});
