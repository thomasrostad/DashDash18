import { test } from "node:test";
import assert from "node:assert/strict";
import { canGrant, legacyRights, roleNameError, roleRights, rightsOf, rightsParam, sortRoles, visibleTabs, type ClubRole } from "../src/roles.ts";
import { brregURL, lookUpName, normalizeOrgNumber, parseBrreg, BRREG_ERRORS } from "../src/brreg.ts";

let n = 0;
function role(name: string, rights: string[] = [], o: Partial<ClubRole> = {}): ClubRole {
  return { id: `r${++n}`, club_id: "c", name, rights, is_owner: false, template_key: null, sort_order: n, ...o };
}
const owner = role("Eier", [], { is_owner: true, template_key: "owner", sort_order: 0 });
const organizer = role("Arrangør", ["tournaments", "rounds", "members", "money"], { template_key: "organizer" });
const treasurer = role("Kasserer", ["money"], { template_key: "treasurer" });
const committee = role("Sosialkomité", [], { template_key: "committee" });
const banemester = role("Banemester", ["rounds"]);
const porter = role("Dørvakt", ["members"]);
const all = [owner, organizer, treasurer, committee, banemester, porter];

test("eier har alt, uansett hva raden sier", () => {
  assert.deepEqual([...roleRights(owner)].sort(), ["members", "money", "rounds", "tournaments"]);
  const r = rightsOf(all, [owner.id]);
  assert.equal(r.isOwner, true);
  assert.equal(r.rights.size, 4);
});

test("rettighetene legges sammen, ukjente hoppes over", () => {
  const r = rightsOf([...all, role("Rar", ["money", "noe_nytt"])], [treasurer.id, banemester.id]);
  assert.deepEqual([...r.rights].sort(), ["money", "rounds"]);
  assert.equal(r.isOwner, false);
});

test("bare roller med rettigheter du har, og bare eier gir Eier", () => {
  const p = rightsOf(all, [porter.id]);
  assert.equal(canGrant(p, committee), true);
  assert.equal(canGrant(p, porter), true);
  assert.equal(canGrant(p, treasurer), false);
  assert.equal(canGrant(p, owner), false);
  assert.equal(canGrant(rightsOf(all, [treasurer.id]), committee), false);
  assert.equal(canGrant(rightsOf(all, [organizer.id]), treasurer), true);
  assert.equal(canGrant(rightsOf(all, [organizer.id]), owner), false);
  assert.equal(canGrant(rightsOf(all, [owner.id]), owner), true);
});

test("eier først, så malene, så egne", () => {
  const sorted = sortRoles([porter, committee, owner, banemester, treasurer, organizer]).map((r) => r.name);
  assert.deepEqual(sorted, ["Eier", "Arrangør", "Kasserer", "Sosialkomité", "Banemester", "Dørvakt"]);
});

test("fanene følger rettighetene", () => {
  assert.deepEqual(visibleTabs(rightsOf(all, [treasurer.id]), true), ["tabeller", "klubb"]);
  assert.deepEqual(visibleTabs(rightsOf(all, [banemester.id]), true), ["terminliste", "baner", "tabeller", "klubb"]);
  assert.deepEqual(visibleTabs(rightsOf(all, [porter.id]), true), ["tropp", "tabeller", "klubb"]);
  assert.deepEqual(visibleTabs(rightsOf(all, [committee.id]), true), []);
  assert.deepEqual(visibleTabs(rightsOf(all, [owner.id]), true), ["turneringer", "terminliste", "baner", "tropp", "tabeller", "klubb", "roller"]);
  // Uten 044: dagens arrangør ser det samme som før, pluss Klubb, men ikke Roller.
  assert.deepEqual(visibleTabs(legacyRights(true, false), false), ["turneringer", "terminliste", "baner", "tropp", "tabeller", "klubb"]);
  assert.deepEqual(visibleTabs(rightsOf(all, [owner.id]), false), ["turneringer", "terminliste", "baner", "tropp", "tabeller", "klubb"]);
});

test("navn og rettigheter til club_role_save", () => {
  assert.equal(roleNameError("  Banemester2 ", all, null), null);
  assert.equal(roleNameError("arrangør", all, null), "Klubben har alt en rolle som heter «arrangør».");
  assert.equal(roleNameError("Arrangør", all, organizer.id), null);
  assert.equal(roleNameError(" ", all, null), "Rollen må ha et navn (1–40 tegn).");
  assert.deepEqual(rightsParam(["money", "tournaments", "x"]), ["tournaments", "money"]);
});

test("organisasjonsnummer og svaret fra Enhetsregisteret", async () => {
  assert.equal(normalizeOrgNumber("923 609 016"), "923609016");
  assert.equal(normalizeOrgNumber("12345"), null);
  assert.equal(normalizeOrgNumber("92360901A"), null);
  assert.equal(brregURL("923609016"), "https://data.brreg.no/enhetsregisteret/api/enheter/923609016");
  assert.deepEqual(parseBrreg(200, { organisasjonsnummer: "923609016", navn: "EQUINOR ASA" }), { ok: true, name: "EQUINOR ASA" });
  assert.deepEqual(parseBrreg(200, {}), { ok: false, error: BRREG_ERRORS.failed });
  assert.deepEqual(parseBrreg(404, null), { ok: false, error: BRREG_ERRORS.notFound });
  assert.deepEqual(parseBrreg(400, null), { ok: false, error: BRREG_ERRORS.invalid });
  assert.deepEqual(parseBrreg(410, null), { ok: false, error: BRREG_ERRORS.deleted });

  const fake = (async () => new Response(JSON.stringify({ navn: "GOLFGUTU" }), { status: 200 })) as typeof fetch;
  assert.deepEqual(await lookUpName("923609016", fake), { ok: true, name: "GOLFGUTU" });
  const offline = (async () => { throw new TypeError("Failed to fetch"); }) as typeof fetch;
  assert.deepEqual(await lookUpName("923609016", offline), { ok: false, error: BRREG_ERRORS.offline });
  assert.deepEqual(await lookUpName("12", fake), { ok: false, error: BRREG_ERRORS.invalid });
});
