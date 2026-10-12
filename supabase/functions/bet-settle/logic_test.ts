// Tester for bet-settle. Kjøres med
//   deno test supabase/functions/bet-settle/
// eller uten Deno med Node og shimmen i docs/push-oppsett.md:
//   node --import /tmp/deno-shim.mjs --test supabase/functions/bet-settle/logic_test.ts
// Ingen nettverk, ingen database: RPC-ene er falske og skriver ned kallene.

import { deepStrictEqual as eq, ok, rejects, strictEqual as is } from "node:assert/strict";
import { runOnce, safeEqual, type Rpc } from "./logic.ts";

const R = "aaaaaaaa-0000-0000-0000-000000000001";
const C = "cccccccc-0000-0000-0000-000000000001";
const A = "11111111-0000-0000-0000-00000000000a";
const B = "11111111-0000-0000-0000-00000000000b";
const D = "11111111-0000-0000-0000-00000000000d";
const E = "11111111-0000-0000-0000-00000000000e";
const PARS = [4, 4, 3, 5, 4, 4, 3, 5, 4, 4, 4, 3, 5, 4, 4, 3, 5, 4];
const bet = (n: number) => `b0000000-0000-0000-0000-00000000000${n}`;

/** En låst 18-hullsrunde på bane, slik bet_settle_jobs leverer den. */
function job(roundId = R) {
  const scores = (m: string, f: (h: number) => number, holes = 18) =>
    PARS.slice(0, holes).map((p, h) => ({ round_id: roundId, member_id: m, hole_index: h, strokes: f(h) }));
  return {
    round_id: roundId,
    attempts: 0,
    data: {
      events: [],
      members: [],
      rounds: [{
        id: roundId, club_id: null, event_id: null, course_id: C, round_no: 1, name: null, status: "locked",
        hole_count: 18, first_hole: 1, tee_time: null, format: "stableford", handicap_allowance: 1,
        external_handicap: false, weight: 1, ld_enabled: true, ld_hole_index: 3, kp_enabled: true, kp_hole_index: 2,
        cut_rule: null, cut_after: null, venue: "course", tee_id: null, tee_name: null, course_rating: 72,
        slope_rating: 113, tee_par: 72, counts: true, points_table: null, hide_last_holes: 0, kind: "normal",
        playoff_for: null, playoff_holes: null,
      }],
      round_holes: [],
      // A, D og E har handicap 0, B 18 (ett slag på hvert hull).
      players: [[A, 0], [B, 18], [D, 0], [E, 0]].map(([m, h]) => ({
        round_id: roundId, member_id: m, club_id: null, handicap_index: h, seed_group: null, playing_handicap: h,
        bay_no: 1, is_marker: false, team_no: null,
      })),
      matches: [{ round_id: roundId, match_no: 1, player_a: A, player_b: D, player_c: null, team_a: null, team_b: null, result: null }],
      claims: [
        { id: "dddddddd-0000-0000-0000-000000000001", round_id: roundId, member_id: B, kind: "drive", meters: 251, hole_index: 3, created_at: "2026-10-12T18:00:00Z" },
        { id: "dddddddd-0000-0000-0000-000000000002", round_id: roundId, member_id: A, kind: "drive", meters: 240, hole_index: 3, created_at: "2026-10-12T18:01:00Z" },
      ],
      courses: [{ id: C, club_id: null, name: "Testbanen", external_name: null, course_rating: 72, slope_rating: 113, in_use: true }],
      course_holes: PARS.map((p, i) => ({ course_id: C, hole_number: i + 1, par: p, stroke_index: i + 1, length_m: null })),
      scores: [
        ...scores(A, (h) => PARS[h] - (h === 0 ? 1 : 0)), // birdie på hull 1, ellers par
        ...scores(B, (h) => PARS[h] + 1), // bogey overalt = netto par
        ...scores(D, (h) => PARS[h] + (h === 1 ? 1 : 0)), // bogey på hull 2
        ...scores(E, (h) => PARS[h], 9), // bare de ni første hullene
      ],
    },
    bets: [
      { id: bet(1), condition: { kind: "hole", hole: 4, a: A, b: B }, closed_at: null, rules: null },
      { id: bet(2), condition: { kind: "birdie", hole: 0, player: A }, closed_at: null, rules: { version: 2 } },
      { id: bet(3), condition: { kind: "par", hole: 1, player: D }, closed_at: "2026-10-12T18:30:00Z", rules: null },
      { id: bet(4), condition: { kind: "beats", a: A, b: E }, closed_at: null, rules: null },
      { id: bet(5), condition: { kind: "match", player: A }, closed_at: null, rules: null },
      { id: bet(6), condition: { kind: "drive", player: B }, closed_at: null, rules: null },
      { id: bet(7), condition: { kind: "kp", player: A }, closed_at: null, rules: null },
      { id: bet(8), condition: { kind: "par", hole: 12, player: E }, closed_at: null, rules: null },
      { id: bet(9), condition: { kind: "hole", hole: 4, a: A, b: B }, closed_at: null, rules: { version: 2, bets: { voidTies: false } } },
    ],
  };
}

interface Call { name: string; params: Record<string, unknown> }

function fakeRpc(jobs: unknown[], fail: Partial<Record<string, string>> = {}): { rpc: Rpc; calls: Call[] } {
  const calls: Call[] = [];
  const rpc: Rpc = <T>(name: string, params: Record<string, unknown>) => {
    calls.push({ name, params });
    if (fail[name]) return Promise.reject(new Error(fail[name]));
    if (name === "bet_settle_jobs") return Promise.resolve(jobs as T);
    if (name === "settle_round_bets") {
      return Promise.resolve({ settled: (params.p_results as unknown[]).length, done: true } as T);
    }
    return Promise.resolve(null as T);
  };
  return { rpc, calls };
}

Deno.test("en låst runde: utfallene skrives med settle_round_bets", async () => {
  const { rpc, calls } = fakeRpc([job()]);
  const s = await runOnce(rpc, 7);
  eq(calls.map((c) => c.name), ["bet_settle_jobs", "settle_round_bets"]);
  eq(calls[0].params, { p_limit: 7 });
  is(calls[1].params.p_round_id, R);
  eq(calls[1].params.p_results, [
    { bet_id: bet(1), verdict: "void" }, // delt hull, Golfgutu annullerer
    { bet_id: bet(2), verdict: "yes" }, // birdie
    { bet_id: bet(3), verdict: "no" }, // bogey: ikke par
    { bet_id: bet(4), verdict: "yes" }, // A slår E (E har ni hull)
    { bet_id: bet(5), verdict: "yes" }, // A to opp mot D
    { bet_id: bet(6), verdict: "yes" }, // B lengst
  ]);
  // KP uten innmelding, E uten hull 13, delt hull uten voidTies: står igjen til arrangøren.
  eq(s, {
    jobs: 1, settled: 6, unknown: 3, failed: 0,
    rounds: [{ round_id: R, settled: 6, unknown: 3, response: { settled: 6, done: true } }],
  });
});

Deno.test("tom kø: bare hentingen", async () => {
  const { rpc, calls } = fakeRpc([]);
  const s = await runOnce(rpc);
  eq(calls, [{ name: "bet_settle_jobs", params: { p_limit: 10 } }]);
  eq(s, { jobs: 0, settled: 0, unknown: 0, failed: 0, rounds: [] });
});

Deno.test("en jobb som ikke kan leses, meldes som feilet; de andre går videre", async () => {
  const broken = job("aaaaaaaa-0000-0000-0000-000000000002");
  broken.data.rounds = [];
  const { rpc, calls } = fakeRpc([broken, job()]);
  const s = await runOnce(rpc);
  eq(calls.map((c) => c.name), ["bet_settle_jobs", "bet_settle_failed", "settle_round_bets"]);
  is(calls[1].params.p_round_id, "aaaaaaaa-0000-0000-0000-000000000002");
  ok(String(calls[1].params.p_error).includes("mangler"));
  is(s.failed, 1);
  is(s.settled, 6);
});

Deno.test("settle_round_bets feiler: meldes med bet_settle_failed", async () => {
  const { rpc, calls } = fakeRpc([job()], { settle_round_bets: "settle_round_bets: 400 Veddemålet er alt avgjort" });
  const s = await runOnce(rpc);
  eq(calls.map((c) => c.name), ["bet_settle_jobs", "settle_round_bets", "bet_settle_failed"]);
  ok(String(calls[2].params.p_error).includes("alt avgjort"));
  is(s.failed, 1);
  is(s.settled, 0);
});

Deno.test("også bet_settle_failed feiler: ingen unntak, jobben står i køen", async () => {
  const { rpc } = fakeRpc([job()], { settle_round_bets: "nede", bet_settle_failed: "nede" });
  const s = await runOnce(rpc);
  is(s.failed, 1);
});

Deno.test("hentingen feiler: kaster (index.ts svarer 502)", async () => {
  const { rpc } = fakeRpc([], { bet_settle_jobs: "bet_settle_jobs: 403 permission denied" });
  await rejects(() => runOnce(rpc), /permission denied/);
});

Deno.test("jobb uten round_id", async () => {
  const { rpc, calls } = fakeRpc([{ bets: [] }]);
  const s = await runOnce(rpc);
  eq(calls.map((c) => c.name), ["bet_settle_jobs"]);
  is(s.failed, 1);
});

Deno.test("hemmeligheten sammenliknes helt", () => {
  ok(safeEqual("abc", "abc"));
  ok(!safeEqual("abc", "abd"));
  ok(!safeEqual("abc", "abcd"));
  ok(!safeEqual("", "x"));
});
