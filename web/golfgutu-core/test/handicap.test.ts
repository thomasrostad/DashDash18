// HandicapTests.swift. Tall: Fixtures/handicap.json.

import assert from "node:assert/strict";
import { test } from "node:test";
import { allowance, courseHandicap, courseHandicapFor, effectiveHandicap, groupHandicap, isSeeded, seedingGroup, teamBasis, teamHandicapByIDs } from "../src/handicap.ts";
import { jsRound } from "../src/jsmath.ts";
import { decodePlayer, decodeRound, makePlayer, makeRound } from "../src/models.ts";
import { GOLFGUTU, golfgutuRules } from "../src/ruleset.ts";
import { fixture } from "./helpers.ts";

const fil = fixture("handicap");
const saker = (fil.saker as any[]).map((s) => ({
  navn: s.navn as string,
  spillere: (s.spillere as any[]).map((p) => decodePlayer(p)),
  runde: decodeRound(s.runde),
  sjekker: s.sjekker as any[],
}));

test("seeding-gruppene er Golfgutu", () => {
  const g = GOLFGUTU.handicap.seedingGroups;
  assert.deepEqual(g.map((x) => x.number), fil.seedingGrupper.map((x: any) => x.nr));
  assert.deepEqual(g.map((x) => x.handicap), fil.seedingGrupper.map((x: any) => x.hcp));
  assert.deepEqual(g.map((x) => x.name), fil.seedingGrupper.map((x: any) => x.navn));
});

test("gruppehandicap null er ikke 0", () => {
  assert.equal(seedingGroup(7), null);
  assert.equal(isSeeded(makePlayer("y", "", 3)), false);
  assert.equal(groupHandicap(makePlayer("a", "", null, 1)), 0);
  assert.equal(groupHandicap(makePlayer("d")), null);
  assert.equal(groupHandicap(null), null);
});

test("courseHandicap (WHS)", () => {
  for (const c of fil.courseHandicap) {
    assert.equal(courseHandicapFor(c.inn[0], c.inn[1], c.inn[2], c.inn[3]), c.forventet, `courseHandicap${JSON.stringify(c.inn)}`);
  }
});

test("sakene i fixturen", () => {
  assert.ok(saker.length > 40);
  for (const sak of saker) {
    const spiller = (id: string | null) => sak.spillere.find((p) => p.id === id) ?? null;
    for (const s of sak.sjekker) {
      let svar: number;
      switch (s.fn) {
        case "effectiveHandicap": svar = effectiveHandicap(spiller(s.spiller), sak.runde, sak.spillere); break;
        case "banehandicap": svar = courseHandicap(spiller(s.spiller), sak.runde); break;
        case "lagGrunnlag": svar = teamBasis(spiller(s.spiller), sak.runde); break;
        case "lagHandicap": svar = teamHandicapByIDs(sak.runde, s.spillere ?? [], sak.spillere); break;
        case "rundeAndel": svar = allowance(sak.runde); break;
        default: assert.fail(`ukjent funksjon ${s.fn}`);
      }
      assert.equal(svar, s.forventet, `${sak.navn}: ${s.fn}(${s.spiller ?? (s.spillere ?? []).join(",")})`);
    }
  }
});

test("banebytte: relasjonene", () => {
  const sak = (prefix: string) => saker.find((s) => s.navn.startsWith(prefix))!;
  const uten = sak("banebytte: uten bane"), elise = sak("banebytte: Elisefarm"), flat = sak("banebytte: flat");
  const hcp = (s: typeof uten, id: string) => effectiveHandicap(s.spillere.find((p) => p.id === id) ?? null, s.runde, s.spillere);
  for (const id of ["p1", "p2", "p3"]) {
    assert.ok(hcp(elise, id) >= hcp(uten, id));
    assert.equal(hcp(flat, id), hcp(uten, id));
  }
  assert.ok(hcp(elise, "p2") > hcp(uten, "p2") && hcp(elise, "p3") > hcp(uten, "p3"));
  assert.ok(hcp(elise, "p3") - hcp(uten, "p3") > hcp(elise, "p1") - hcp(uten, "p1"));
});

test("egne seeding-grupper fra regelsettet", () => {
  const r = golfgutuRules();
  r.handicap.seedingGroups = [{ number: 1, handicap: 2, name: "A" }, { number: 2, handicap: 8, name: "B" }];
  const p = makePlayer("x", "", 20, 2);
  const runde = makeRound({ gameType: "stableford", holeCount: 9, hcpAllowance: 0.95 });
  assert.equal(effectiveHandicap(p, runde, [p], r), 8);
  assert.equal(effectiveHandicap(makePlayer("z", "", 20, 3), runde, [], r), jsRound(20 * 0.95 * 0.5));
});
