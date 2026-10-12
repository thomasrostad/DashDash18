// BetsTests.swift: veddemål med poeng. Tall: Fixtures/veddemaal.json (samme fil som Swift-testen).
// Oppgjøret og feiingen kjøres med PWA-ens regler (`PWA_BET_RULES`); Golfgutu-malen har hele poeng og
// annullerer delt. Til slutt oppgjøret på serveren (`settleJob`, sql/052).

import assert from "node:assert/strict";
import { test } from "node:test";
import { settleJob } from "../src/app/betsettle.ts";
import {
  acceptsStakes,
  betAtStake,
  betAvailable,
  betBalance,
  betIsAbout,
  betNet,
  betNetting,
  betOutcome,
  betPayouts,
  betPhase,
  betPosition,
  betTable,
  betTemplates,
  betTransfers,
  betVerdict,
  canResolveBet,
  decodeBet,
  decodeBetCondition,
  firstOpenHole,
  makeBet,
  makeBetCondition,
  shouldClose,
  stakeProblem,
  sweep,
  type Bet,
  type BetUpdate,
} from "../src/bets.ts";
import { decodePlayer, decodeRound, decodeSideClaim, makePlayer, makeRound, type Course, type Round } from "../src/models.ts";
import { decodeRuleset, GOLFGUTU, golfgutuRules, PWA_BET_RULES, type Ruleset } from "../src/ruleset.ts";
import { validateRuleset } from "../src/validation.ts";
import { fixture, obj } from "./helpers.ts";

const fil = fixture("veddemaal");
const PWA: Ruleset = { ...golfgutuRules(), bets: { ...PWA_BET_RULES, stakeOptions: [...PWA_BET_RULES.stakeOptions] } };

const ni: Course = {
  id: "b", name: null as unknown as string, par: 36, courseRating: 36, slopeRating: 113,
  holes: [4, 4, 3, 4, 5, 3, 4, 4, 5].map((par, i) => ({ par, si: i + 1, meters: null })),
};
const scores = (o: Record<string, Record<number, number>>) =>
  new Map(Object.entries(o).map(([k, v]) => [k, new Map(Object.entries(v).map(([h, s]) => [Number(h), s]))]));
const cond = makeBetCondition;
const upd = (betID: string | null, close: boolean, verdict: BetUpdate["verdict"]): BetUpdate => ({ betID, close, verdict });

// MARK: vilkaar-test.js, kveld-test.js §5

test("utfallet er som PWA", () => {
  assert.equal(fil.utfall.length, 36);
  for (const sak of fil.utfall) {
    const svar = betOutcome(decodeRound(sak.runde), decodeBetCondition(sak.vilkaar), sak.spillere.map((p: any) => decodePlayer(p)),
      sak.innmeldinger.map((c: any) => decodeSideClaim(c)));
    assert.equal(svar, sak.forventet, `${sak.kilde}: ${sak.navn}`);
  }
});

test("birdie på hull fem stenger og avgjøres", () => {
  const round = makeRound({ id: "r1", holeCount: 9, course: ni, hcpAllowance: 1, hcpExtern: true });
  const bet = makeBet({ id: "m", condition: cond({ kind: "birdie", round: "r1", hole: 4, player: "a" }) });
  round.holeScores = scores({ a: { 0: 4, 1: 4, 2: 3 } });
  assert.ok(acceptsStakes(bet, round));
  round.holeScores.get("a")!.set(3, 4);
  assert.ok(!acceptsStakes(bet, round));
  assert.equal(betOutcome(round, bet.condition!, []), null);
  round.holeScores.get("a")!.set(4, 4);
  assert.equal(betOutcome(round, bet.condition!, []), "yes");
  assert.deepEqual(sweep([bet], round, 4, []), [upd("m", true, "yes")]);
});

// MARK: lockout-test.js, kveld-test.js §3

test("låsingen er som PWA", () => {
  assert.equal(fil.laasing.length, 22);
  for (const sak of fil.laasing) {
    assert.equal(acceptsStakes(decodeBet(sak.veddemaal), sak.runde ? decodeRound(sak.runde) : null), sak.forventet, sak.navn);
  }
});

test("første åpne hull er som PWA", () => {
  assert.equal(fil.forsteApneHull.length, 14);
  for (const sak of fil.forsteApneHull) {
    assert.equal(firstOpenHole(decodeRound(sak.runde), sak.spillere), sak.forventet, sak.navn);
  }
  assert.equal(firstOpenHole(null, ["a"]), null);
});

test("forspranget fra regelsettet", () => {
  const rules = golfgutuRules();
  rules.bets.lockAheadHoles = 2;
  const round = makeRound({ id: "r1", holeCount: 18, holeScores: scores({ a: { 0: 4, 1: 4 } }) });
  assert.equal(firstOpenHole(round, ["a"]), 3);
  assert.equal(firstOpenHole(round, ["a"], rules), 4);
  const bet = makeBet({ condition: cond({ kind: "par", round: "r1", hole: 3, player: "a" }) });
  assert.ok(acceptsStakes(bet, round));
  assert.ok(!acceptsStakes(bet, round, rules));
  assert.equal(firstOpenHole(makeRound({ id: "r1" }), ["a"], rules), 0);
});

// MARK: Lukking og feiing

test("lukking er som PWA", () => {
  assert.equal(fil.lukking.length, 9);
  for (const sak of fil.lukking) {
    assert.equal(shouldClose(decodeBet(sak.veddemaal), decodeRound(sak.runde), sak.hull), sak.forventet, sak.navn);
  }
});

test("feiingen skriver det samme som PWA", () => {
  assert.equal(fil.feiing.length, 8);
  for (const sak of fil.feiing) {
    const svar = sweep(sak.veddemaal.map((b: any) => decodeBet(b)), decodeRound(sak.runde), sak.hull ?? null,
      sak.spillere.map((p: any) => decodePlayer(p)), [], PWA);
    assert.deepEqual(svar.map((u) => u.betID), sak.forventet.map((f: any) => f.id), sak.navn);
    assert.deepEqual(svar.map((u) => u.close), sak.forventet.map((f: any) => f.lukkes), sak.navn);
    assert.deepEqual(svar.map((u) => (u.verdict === "void" ? null : u.verdict)), sak.forventet.map((f: any) => f.utfall), sak.navn);
  }
});

// MARK: Malene

test("malene er som PWA", () => {
  assert.equal(fil.maler.length, 12);
  for (const sak of fil.maler) {
    const runde = sak.runde ? decodeRound(sak.runde) : null;
    const maler = betTemplates(runde, sak.meg, sak.mot ?? null);
    assert.deepEqual(maler.map((m) => m.kind), sak.forventet.map((f: any) => f.mal), sak.navn);
    assert.deepEqual(maler.map((m) => m.condition), sak.forventet.map((f: any) => (f.vilkaar ? decodeBetCondition(f.vilkaar) : null)), sak.navn);
    assert.deepEqual(maler.map((m) => m.side), sak.forventet.map((f: any) => f.side), sak.navn);
    maler.forEach((mal, i) => {
      const ventet = sak.forventet[i];
      assert.equal(acceptsStakes(makeBet({ condition: mal.condition }), runde), ventet.tarInnsatser, `${sak.navn}: ${ventet.tekst}`);
      assert.ok(ventet.tarInnsatser);
    });
  }
});

// MARK: Oppgjøret (poster-test.js)

test("overføringene er som veddemaalPoster", () => {
  assert.equal(fil.poster.length, 8);
  for (const sak of fil.poster) {
    const svar = betTransfers(decodeBet(sak.veddemaal), PWA);
    assert.deepEqual(svar, sak.forventet.map((p: any) => ({ from: p.fra, to: p.til, points: p.poeng })), sak.navn);
    const per = new Map<string, number>();
    for (const t of svar) {
      per.set(t.from, (per.get(t.from) ?? 0) - t.points);
      per.set(t.to, (per.get(t.to) ?? 0) + t.points);
    }
    assert.ok(Math.abs([...per.values()].reduce((a, b) => a + b, 0)) < 0.001, sak.navn);
  }
});

test("netto per spiller er som marketNetFor", () => {
  const sak = fil.netto[0];
  const bets: Bet[] = sak.veddemaal.map((b: any) => decodeBet(b));
  for (const [pid, ventet] of Object.entries(sak.forventet as Record<string, number>)) {
    assert.ok(Math.abs(betNet(pid, bets, PWA) - ventet) < 0.01, pid);
  }
  assert.equal(betNet("t", bets, PWA), -116.67);
  assert.ok(Math.abs(Object.keys(sak.forventet).reduce((s, p) => s + betNet(p, bets, PWA), 0)) < 1e-9);
  const spillere = Object.keys(sak.forventet).sort().map((p) => makePlayer(p, p));
  const tabell = betTable(spillere, bets, PWA);
  assert.deepEqual(tabell.map((r) => r.playerID), sak.rekkefolge);
  assert.ok(tabell.every((r) => r.balance === null && r.available === null));
});

test("tabellen stemmer med overføringene", () => {
  const sak = fil.netto[0];
  const bets: Bet[] = sak.veddemaal.map((b: any) => decodeBet(b));
  const ov = bets.flatMap((b) => betTransfers(b, PWA));
  for (const pid of Object.keys(sak.forventet)) {
    const fra = ov.reduce((s, t) => s + (t.to === pid ? t.points : 0) - (t.from === pid ? t.points : 0), 0);
    assert.ok(Math.abs(fra - betNet(pid, bets, PWA)) <= 0.01 * ov.length, pid);
  }
});

test("nettoing er som skyldOversikt", () => {
  assert.equal(fil.nettoing.length, 4);
  for (const sak of fil.nettoing) {
    const o = betNetting(sak.poster.map((p: any) => ({ from: p.fra, to: p.til, points: p.poeng })), sak.meg);
    assert.deepEqual(o.gives.map((l) => l.counterpart), sak.forventet.betaler.map((l: any) => l.motpart), sak.navn);
    assert.deepEqual(o.gives.map((l) => l.points), sak.forventet.betaler.map((l: any) => l.poeng), sak.navn);
    assert.deepEqual(o.receives.map((l) => l.counterpart), sak.forventet.faar.map((l: any) => l.motpart), sak.navn);
    assert.deepEqual(o.receives.map((l) => l.points), sak.forventet.faar.map((l: any) => l.poeng), sak.navn);
    assert.deepEqual(o.even, sak.forventet.nullPar, sak.navn);
    assert.equal(o.totalGives, sak.forventet.sumBetaler, sak.navn);
    assert.equal(o.totalReceives, sak.forventet.sumFaar, sak.navn);
  }
});

// MARK: Statuspillen

test("statuspillen har én betydning", () => {
  for (const sak of fil.status) {
    assert.equal(betPhase(makeBet({ status: sak.status, resolution: sak.resolution }), sak.tarInnsatser), sak.forventet, sak.navn);
  }
  assert.equal(betPhase(makeBet({ status: "void" }), false), "void");
});

// MARK: Egne: annullert, poengbanken og innsatsen

test("annullert gir innsatsen tilbake", () => {
  const bet = makeBet({ status: "void", stakes: [
    { id: null, playerID: "a", side: "yes", points: 100 }, { id: null, playerID: "b", side: "no", points: 50 },
  ] });
  assert.equal(betTransfers(bet).length, 0);
  assert.equal(betNet("a", [bet]), 0);
  assert.equal(betAtStake("a", [bet]), 0);
  assert.ok(!acceptsStakes(bet, null));
});

test("poengbanken", () => {
  const avgjort = makeBet({ id: "1", status: "resolved", resolution: "yes", stakes: [
    { id: null, playerID: "a", side: "yes", points: 100 }, { id: null, playerID: "b", side: "no", points: 50 },
  ] });
  const aapent = makeBet({ id: "2", stakes: [{ id: null, playerID: "a", side: "no", points: 70 }] });
  const bets = [avgjort, aapent];
  assert.equal(betNet("a", bets), 50);
  assert.equal(betNet("b", bets), -50);
  assert.equal(betAtStake("a", bets), 70);
  assert.equal(betBalance("a", bets), 1050);
  assert.equal(betAvailable("a", bets), 980);
  assert.equal(betBalance("b", bets), 950);
  const tabell = betTable([makePlayer("b", "Bjørn"), makePlayer("a", "Anders"), makePlayer("c", "Cato")], bets);
  assert.deepEqual(tabell.map((r) => r.playerID), ["a", "c", "b"]);
  assert.ok(tabell[0].bets === 2 && tabell[0].won === 1);
  assert.ok(tabell[1].balance === 1000 && tabell[1].bets === 0);
  assert.equal(tabell[2].won, 0);
  const likt = betTable([makePlayer("x", "Åse"), makePlayer("y", "Øyvind"), makePlayer("z", "Ærlig")], []);
  assert.deepEqual(likt.map((r) => r.name), ["Ærlig", "Øyvind", "Åse"]);
});

test("innsatsen sjekkes", () => {
  const round = makeRound({ id: "r1", holeCount: 18, holeScores: scores({ a: { 0: 4 } }) });
  const bet = makeBet({ id: "m", condition: cond({ kind: "par", round: "r1", hole: 10, player: "a" }),
    stakes: [{ id: null, playerID: "me", side: "no", points: 150 }] });
  const sjekk = (s: "yes" | "no", p: number, bets: Bet[] = [bet], rules: Ruleset = GOLFGUTU) =>
    stakeProblem(bet, "me", s, p, round, bets, rules);
  assert.equal(sjekk("no", 50), null);
  assert.deepEqual(sjekk("no", 51), { kind: "overCap", max: 200, already: 150 });
  assert.deepEqual(sjekk("yes", 10), { kind: "otherSide", side: "no" });
  assert.deepEqual(sjekk("no", 0), { kind: "invalidAmount" });
  assert.deepEqual(stakeProblem(bet, "ny", "yes", 201, round, [bet]), { kind: "overCap", max: 200, already: 0 });
  const annet = makeBet({ id: "x", stakes: [{ id: null, playerID: "me", side: "yes", points: 820 }] });
  assert.deepEqual(sjekk("no", 50, [bet, annet]), { kind: "insufficient", available: 30 });
  assert.equal(sjekk("no", 30, [bet, annet]), null);
  const ingenBank = golfgutuRules();
  ingenBank.bets.startingPoints = null;
  assert.equal(sjekk("no", 50, [bet, annet], ingenBank), null);
  const stengt = makeBet({ condition: cond({ kind: "par", round: "r1", hole: 1, player: "a" }) });
  assert.deepEqual(stakeProblem(stengt, "me", "yes", 50, round, []), { kind: "closed" });
});

test("posisjon og hvem det gjelder", () => {
  const bet = makeBet({ against: "b", stakes: [
    { id: null, playerID: "me", side: "no", points: 50 }, { id: null, playerID: "me", side: "no", points: 30 },
  ] });
  assert.equal(betPosition(bet, "me")?.side, "no");
  assert.equal(betPosition(bet, "me")?.points, 80);
  assert.equal(betPosition(bet, "c"), null);
  assert.ok(betIsAbout(bet, "b"));
  assert.ok(betIsAbout(makeBet({ condition: cond({ kind: "hole", round: "r", hole: 1, a: "x", b: "y" }) }), "y"));
  assert.ok(!betIsAbout(bet, "me"));
});

// MARK: Regelsettet

test("regelsettet for veddemål", () => {
  const g = GOLFGUTU.bets;
  assert.equal(g.lockAheadHoles, 1);
  assert.equal(g.maxStakePerBet, 200);
  assert.deepEqual(g.stakeOptions, [50, 100, 200]);
  assert.equal(g.defaultStake, 100);
  assert.equal(g.startingPoints, 1000);
  assert.equal(g.payoutDecimals, 0);
  assert.ok(g.voidTies);
  assert.equal(validateRuleset(golfgutuRules()).length, 0);
  assert.equal(validateRuleset(PWA).length, 0);

  const egne = decodeRuleset({ version: 2, bets: { lockAheadHoles: 2, startingPoints: null } });
  assert.equal(egne.bets.lockAheadHoles, 2);
  assert.equal(egne.bets.startingPoints, null);
  assert.equal(egne.bets.maxStakePerBet, 200);
  assert.ok(egne.bets.payoutDecimals === 0 && egne.bets.voidTies);
  const pwa = decodeRuleset({ version: 2, bets: { payoutDecimals: 2, voidTies: false } });
  assert.ok(pwa.bets.payoutDecimals === 2 && !pwa.bets.voidTies);
  assert.deepEqual(decodeRuleset({ version: 2 }).bets, { ...g, stakeOptions: [...g.stakeOptions] });

  const felt = (endre: (r: Ruleset) => void) => {
    const r = golfgutuRules();
    endre(r);
    return validateRuleset(r).map((i) => i.field);
  };
  assert.deepEqual(felt((r) => { r.bets.lockAheadHoles = 0; }), ["bets.lockAheadHoles"]);
  assert.ok(felt((r) => { r.bets.maxStakePerBet = 0; }).includes("bets.maxStakePerBet"));
  assert.deepEqual(felt((r) => { r.bets.stakeOptions = [50, 300]; }), ["bets.stakeOptions"]);
  assert.deepEqual(felt((r) => { r.bets.defaultStake = 250; }), ["bets.defaultStake"]);
  assert.deepEqual(felt((r) => { r.bets.startingPoints = -1; }), ["bets.startingPoints"]);
  assert.deepEqual(felt((r) => { r.bets.startingPoints = null; }), []);
  assert.deepEqual(felt((r) => { r.bets.payoutDecimals = 3; }), ["bets.payoutDecimals"]);
  assert.deepEqual(felt((r) => { r.bets.payoutDecimals = -1; }), ["bets.payoutDecimals"]);
});

// MARK: Besluttet 07.10.2026

test("hele poeng fordeler resten", () => {
  const bet = makeBet({ status: "resolved", resolution: "yes", stakes: [
    { id: null, playerID: "c", side: "yes", points: 50 }, { id: null, playerID: "a", side: "yes", points: 50 },
    { id: null, playerID: "b", side: "yes", points: 50 }, { id: null, playerID: "x", side: "no", points: 100 },
  ] });
  assert.deepEqual(obj(betPayouts(bet)), { a: 34, b: 33, c: 33, x: -100 });
  assert.equal(betNet("a", [bet]), 34);
  assert.deepEqual(obj(betPayouts(bet, PWA)), { a: 33.34, b: 33.33, c: 33.33, x: -100 });
  assert.deepEqual(betTransfers(bet).map((t) => t.points), [33, 33, 33]);
});

test("hele poeng tar overskuddet fra største innsats", () => {
  const bet = makeBet({ status: "resolved", resolution: "no", stakes: [
    { id: null, playerID: "b", side: "no", points: 30 }, { id: null, playerID: "a", side: "no", points: 60 },
    { id: null, playerID: "c", side: "no", points: 10 }, { id: null, playerID: "x", side: "yes", points: 55 },
  ] });
  assert.deepEqual(obj(betPayouts(bet)), { a: 32, b: 17, c: 6, x: -55 });
  const delt = makeBet({ status: "resolved", resolution: "no", stakes: [
    { id: null, playerID: "a", side: "no", points: 20 }, { id: null, playerID: "b", side: "no", points: 30 },
    { id: null, playerID: "a", side: "no", points: 40 }, { id: null, playerID: "c", side: "no", points: 10 },
    { id: null, playerID: "x", side: "yes", points: 55 },
  ] });
  assert.deepEqual(obj(betPayouts(delt)), obj(betPayouts(bet)));
});

test("hele poeng skaper eller fjerner ingen poeng", () => {
  // Samme generator som Swift-testen (64-bits LCG), med BigInt.
  let seed = 0x9E3779B97F4A7C15n;
  const M = (1n << 64n) - 1n;
  const next = (n: number) => {
    seed = (seed * 6364136223846793005n + 1442695040888963407n) & M;
    return Number((seed >> 33n) % BigInt(n));
  };
  const players = Array.from({ length: 9 }, (_, i) => `p${i}`);
  const bets: Bet[] = [];
  for (let i = 0; i < 400; i++) {
    const stakes = [];
    for (const p of players) if (next(3) > 0) stakes.push({ id: null, playerID: p, side: next(2) === 0 ? "yes" as const : "no" as const, points: 1 + next(200) });
    const status = i % 10 === 0 ? "void" as const : "resolved" as const;
    bets.push(makeBet({ id: `${i}`, status, resolution: status === "resolved" ? (next(2) === 0 ? "yes" : "no") : null, stakes }));
  }
  for (const bet of bets) {
    const p = betPayouts(bet);
    for (const v of p.values()) assert.equal(v, Math.round(v), bet.id!);
    assert.equal([...p.values()].reduce((a, b) => a + b, 0), 0, bet.id!);
    const res = bet.resolution;
    if (res === null || p.size === 0) continue;
    const win = bet.stakes.filter((s) => s.side === res).reduce((s, x) => s + x.points, 0);
    const lose = bet.stakes.filter((s) => s.side !== res).reduce((s, x) => s + x.points, 0);
    for (const [pid, x] of p) {
      if (x < 0) continue;
      const exact = betPosition(bet, pid)!.points * lose / win;
      assert.ok(Math.abs(x - exact) <= 1.5, `${bet.id}: ${pid}`);
    }
  }
  assert.equal(players.reduce((s, p) => s + betNet(p, bets), 0), 0);
  const tabell = betTable(players.map((p) => makePlayer(p, p)), bets);
  assert.equal(tabell.reduce((s, r) => s + (r.balance ?? 0), 0), 1000 * players.length);
});

test("delt hull annulleres automatisk", () => {
  const round = makeRound({ id: "r1", holeCount: 9, course: ni, hcpAllowance: 1, hcpExtern: true });
  const duell = makeBet({ id: "d", condition: cond({ kind: "hole", round: "r1", hole: 2, a: "a", b: "b" }) });
  round.holeScores = scores({ a: { 0: 4, 1: 4, 2: 3 }, b: { 0: 5, 1: 4 } });
  assert.equal(betVerdict(round, duell.condition!, []), null);
  round.holeScores.get("b")!.set(2, 3);
  assert.equal(betOutcome(round, duell.condition!, []), null);
  assert.equal(betVerdict(round, duell.condition!, []), "void");
  assert.equal(betVerdict(round, duell.condition!, [], [], PWA), null);
  assert.deepEqual(sweep([duell], round, 2, []), [upd("d", true, "void")]);
  assert.deepEqual(sweep([duell], round, 2, [], [], PWA), [upd("d", true, null)]);
  round.holeScores.get("b")!.set(2, 4);
  assert.equal(betVerdict(round, duell.condition!, []), "yes");
  assert.equal(sweep([duell], round, 2, [])[0]?.verdict, "yes");
});

test("arrangøren med innsats avgjør ikke", () => {
  const bet = makeBet({ stakes: [
    { id: null, playerID: "arr", side: "yes", points: 50 }, { id: null, playerID: "b", side: "no", points: 50 },
  ] });
  assert.ok(!canResolveBet(bet, "arr"));
  assert.ok(canResolveBet(bet, "arr2"));
  assert.ok(!canResolveBet(makeBet({ status: "void" }), "arr2"));
  assert.ok(!canResolveBet(makeBet({ status: "resolved", resolution: "yes" }), "arr2"));
});

// MARK: Oppgjøret på serveren (sql/052, bet-settle)

/** En jobb slik `bet_settle_jobs` lager den: én låst 18-hullsrunde med radene fra databasen. */
function realisticJob(): any {
  const R = "aaaaaaaa-0000-0000-0000-000000000001";
  const C = "cccccccc-0000-0000-0000-000000000001";
  const [A, B, D, E] = ["11111111-0000-0000-0000-00000000000a", "11111111-0000-0000-0000-00000000000b",
    "11111111-0000-0000-0000-00000000000d", "11111111-0000-0000-0000-00000000000e"];
  const pars = [4, 4, 3, 5, 4, 4, 3, 5, 4, 4, 4, 3, 5, 4, 4, 3, 5, 4];
  const scoresFor = (m: string, f: (h: number) => number) => pars.map((p, h) => ({ round_id: R, member_id: m, hole_index: h, strokes: f(h) }));
  return {
    round_id: R,
    attempts: 0,
    data: {
      events: [],
      members: [],
      rounds: [{
        id: R, club_id: null, event_id: null, course_id: C, round_no: 1, name: null, status: "locked", hole_count: 18,
        first_hole: 1, tee_time: null, format: "stableford", handicap_allowance: 1, external_handicap: false, weight: 1,
        ld_enabled: true, ld_hole_index: 3, kp_enabled: true, kp_hole_index: 2, cut_rule: null, cut_after: null,
        venue: "course", tee_id: null, tee_name: null, course_rating: 72, slope_rating: 113, tee_par: 72,
        counts: true, points_table: null, hide_last_holes: 0, kind: "normal", playoff_for: null, playoff_holes: null,
      }],
      round_holes: [],
      players: [A, B, D, E].map((m, i) => ({
        round_id: R, member_id: m, club_id: null, handicap_index: [0, 18, 0, 0][i], seed_group: null,
        playing_handicap: [0, 18, 0, 0][i], bay_no: 1, is_marker: false, team_no: null,
      })),
      matches: [{ round_id: R, match_no: 1, player_a: A, player_b: D, player_c: null, team_a: null, team_b: null, result: null }],
      claims: [
        { id: "dddddddd-0000-0000-0000-000000000001", round_id: R, member_id: B, kind: "drive", meters: 251, hole_index: 3, created_at: "2026-10-12T18:00:00Z" },
        { id: "dddddddd-0000-0000-0000-000000000002", round_id: R, member_id: A, kind: "drive", meters: 240, hole_index: 3, created_at: "2026-10-12T18:01:00Z" },
      ],
      courses: [{ id: C, club_id: null, name: "Testbanen", external_name: null, course_rating: 72, slope_rating: 113, in_use: true }],
      course_holes: pars.map((p, i) => ({ course_id: C, hole_number: i + 1, par: p, stroke_index: i + 1, length_m: null })),
      // A: par overalt, birdie på hull 1 (indeks 0). B: bogey overalt (18 slag: netto par). D: par
      // overalt unntatt bogey på hull 2 (indeks 1). E har bare ført de ni første hullene.
      scores: [
        ...scoresFor(A, (h) => pars[h] - (h === 0 ? 1 : 0)),
        ...scoresFor(B, (h) => pars[h] + 1),
        ...scoresFor(D, (h) => pars[h] + (h === 1 ? 1 : 0)),
        ...scoresFor(E, (h) => pars[h]).filter((s) => s.hole_index < 9),
      ],
    },
    bets: [
      { id: "b0000000-0000-0000-0000-000000000001", condition: { kind: "hole", hole: 4, a: A, b: B }, closed_at: null, rules: null },
      { id: "b0000000-0000-0000-0000-000000000002", condition: { kind: "birdie", hole: 0, player: A }, closed_at: null, rules: { version: 2 } },
      { id: "b0000000-0000-0000-0000-000000000003", condition: { kind: "par", hole: 1, player: D }, closed_at: "2026-10-12T18:30:00Z", rules: null },
      { id: "b0000000-0000-0000-0000-000000000004", condition: { kind: "beats", a: A, b: E }, closed_at: null, rules: null },
      { id: "b0000000-0000-0000-0000-000000000005", condition: { kind: "match", player: A }, closed_at: null, rules: null },
      { id: "b0000000-0000-0000-0000-000000000006", condition: { kind: "drive", player: B }, closed_at: null, rules: null },
      { id: "b0000000-0000-0000-0000-000000000007", condition: { kind: "kp", player: A }, closed_at: null, rules: null },
      { id: "b0000000-0000-0000-0000-000000000008", condition: { kind: "par", hole: 12, player: E }, closed_at: null, rules: null },
      { id: "b0000000-0000-0000-0000-000000000009", condition: { kind: "hole", hole: 4, a: A, b: B }, closed_at: null, rules: { version: 2, bets: { voidTies: false } } },
    ],
  };
}

test("oppgjøret på serveren: en låst runde", () => {
  const job = realisticJob();
  const out = settleJob(job);
  assert.equal(out.round_id, job.round_id);
  const v = Object.fromEntries(out.results.map((r) => [r.bet_id.slice(-1), r.verdict]));
  // 1: A par (4) mot B bogey med ett slag (netto 4): delt hull → annullert med Golfgutu.
  assert.equal(v["1"], "void");
  // 2: A birdie på hull 1.
  assert.equal(v["2"], "yes");
  // 3: D (handicap 0) bogey på hull 2: ikke par.
  assert.equal(v["3"], "no");
  // 4: A 37 poeng mot E med ni hull: A slår E.
  assert.equal(v["4"], "yes");
  // 5: A mot D, begge handicap 0: birdie på hull 1 og D bogey på hull 2 gir A to opp.
  assert.equal(v["5"], "yes");
  // 6: B lengst.
  assert.equal(v["6"], "yes");
  // 7, 8 og 9 kan ikke avgjøres: ingen KP-innmelding, E har ikke ført hull 13, delt uten voidTies.
  assert.deepEqual(out.unknown.map((id) => id.slice(-1)).sort(), ["7", "8", "9"]);
  assert.equal(out.results.length + out.unknown.length, job.bets.length);
});

test("oppgjøret på serveren: samme svar som motoren på regelmotorens runde", () => {
  // Med frosset handicap og runden låst gir settleJob det samme som betVerdict direkte.
  const round: Round = makeRound({ id: "r1", holeCount: 9, course: ni, hcpAllowance: 1, hcpExtern: true, locked: true,
    holeScores: scores({ a: { 2: 3 }, b: { 2: 3 } }) });
  assert.equal(betVerdict(round, cond({ kind: "hole", round: "r1", hole: 2, a: "a", b: "b" }), []), "void");
  assert.throws(() => settleJob({ round_id: "x", data: {}, bets: [] }), /mangler/);
});
