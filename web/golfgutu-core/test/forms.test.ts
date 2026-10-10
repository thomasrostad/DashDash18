// FormTests.swift: konkurranseformer. Tall og tekster: Fixtures/former.json.

import assert from "node:assert/strict";
import { test } from "node:test";
import { ALL_FORMS, DEFAULT_FORM_ID, formById, isTeamForm, roundForm } from "../src/forms.ts";
import { formSuggestions, golfgutuMaxPerBay, setupFor, setupIsOK, setupIsTriangle, setupIsUneven, setupReason, setupText, teamSplit } from "../src/formsetup.ts";
import { makeRound } from "../src/models.ts";
import { fixture } from "./helpers.ts";

const fil = fixture("former");

test("registeret er likt PWA-en", () => {
  assert.equal(DEFAULT_FORM_ID, fil.formStandard);
  assert.equal(golfgutuMaxPerBay(), fil.spillerePerBaas);
  assert.equal(ALL_FORMS.length, fil.former.length);
  ALL_FORMS.forEach((f, i) => {
    const js = fil.former[i];
    assert.equal(f.id, js.id);
    assert.equal(f.name, js.navn);
    assert.equal(f.teamSize, js.lag);
    assert.equal(f.card, js.kort);
    assert.equal(f.scoring, js.regning);
    assert.equal(f.allowance, js.hcpAndel);
    assert.equal(f.support, js.stotte);
    assert.equal(f.allowsUnevenTeams, js.taalerSkjevtLag);
    assert.equal(f.help, js.hjelp);
  });
});

test("konkurranseform", () => {
  assert.equal(formById("scramble-4").teamSize, 4);
  assert.equal(formById("tull").id, "stableford");
  assert.equal(formById(null).id, "stableford");
});

test("formForRunde og erLagform", () => {
  for (const sak of fil.formForRunde) {
    const r = makeRound({ gameType: sak.gameType ?? null });
    assert.equal(roundForm(r).id, sak.id);
    assert.equal(isTeamForm(roundForm(r)), sak.erLagform);
  }
});

test("lagdeling", () => {
  assert.equal(fil.lagdeling.length, 180);
  for (const sak of fil.lagdeling) {
    const svar = teamSplit(sak.antall, sak.k, sak.taalerSkjevt);
    const f = sak.svar;
    assert.deepEqual(svar, f ? { sides: f.sider, sizes: f.storrelser, matches: f.matcher } : null, `lagdeling(${sak.antall}, ${sak.k}, ${sak.taalerSkjevt})`);
  }
});

test("oppsett for antall", () => {
  for (const sak of fil.oppsettForAntall) {
    const s = setupFor(sak.formId, sak.antall);
    const f = sak.svar;
    const navn = `oppsettForAntall('${sak.formId}', ${sak.antall})`;
    assert.equal(setupIsOK(s), f.ok, navn);
    assert.equal(setupReason(s), f.hvorfor ?? null, navn);
    assert.equal(setupText(s), f.form ?? null, navn);
    if (s.kind === "individual") {
      assert.ok(s.duels === f.dueller && s.triangle === f.trekant, navn);
    } else if (s.kind === "teams") {
      assert.ok(s.split.sides === f.sider && s.split.matches === f.matcher, navn);
      assert.deepEqual(s.split.sizes, f.storrelser, navn);
      assert.equal(s.uneven, f.skjevt, navn);
    }
  }
});

test("påmelding: sakene", () => {
  assert.equal(setupText(setupFor("stableford", 11)), "4 dueller og én trekant");
  assert.ok(setupIsTriangle(setupFor("stableford", 11)));
  assert.equal(setupText(setupFor("stableford", 12)), "6 dueller");
  assert.ok(!setupIsTriangle(setupFor("stableford", 12)));
  assert.equal(setupText(setupFor("stableford", 3)), "én trekant");
  assert.ok(!setupIsOK(setupFor("stableford", 1)));
  assert.equal(setupText(setupFor("scramble-2", 11)), "4 lag (3+3+3+2) · 2 matcher");
  assert.ok(setupIsUneven(setupFor("scramble-2", 11)));
  assert.ok(!setupIsUneven(setupFor("scramble-2", 12)));
  assert.ok(!setupIsOK(setupFor("foursome", 11)));
  assert.ok(setupIsOK(setupFor("foursome", 12)));
  assert.ok(!setupIsOK(setupFor("scramble-4", 9)));
  assert.ok(setupIsOK(setupFor("scramble-4", 16)));
  assert.ok(setupReason(setupFor("scramble-4", 3))!.includes("går ikke opp i et likt antall lag på 4"));
  const elleve = formSuggestions(11).map((s) => s.id);
  assert.ok(elleve.includes("stableford") && elleve.includes("scramble-2") && !elleve.includes("foursome"));
  const sju = formSuggestions(7);
  assert.ok(sju.length > 0 && sju.every((s) => formById(s.id).teamSize === 1));
  assert.ok(formSuggestions(12).every((s) => formById(s.id).support === "full"));
});

test("skjeve lag", () => {
  assert.ok(formById("fourball").allowsUnevenTeams);
  assert.ok(!formById("foursome").allowsUnevenTeams && !formById("greensome").allowsUnevenTeams);
  assert.deepEqual(teamSplit(5, 2, true), { sides: 2, sizes: [3, 2], matches: 1 });
  assert.equal(teamSplit(5, 2, false), null);
  assert.equal(teamSplit(9, 4, true), null);
});

test("former som passer", () => {
  for (const sak of fil.formerSomPasser) {
    const svar = formSuggestions(sak.antall);
    assert.deepEqual(svar.map((s) => s.id), sak.svar.map((f: any) => f.id));
    svar.forEach((s, i) => {
      const f = sak.svar[i];
      assert.ok(s.name === f.navn && s.text === f.form && s.uneven === f.skjevt && s.triangle === f.trekant, `${sak.antall}: ${f.id}`);
    });
  }
});

test("maks per bås fra regelsettet", () => {
  assert.ok(!setupIsOK(setupFor("scramble-4", 16, 3)));
  assert.equal(teamSplit(5, 2, true, 2), null);
  assert.deepEqual(teamSplit(9, 4, true, 5), { sides: 2, sizes: [5, 4], matches: 1 });
});
