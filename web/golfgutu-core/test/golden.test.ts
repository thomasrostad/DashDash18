// Paritet med Swift-motoren byte for byte: GoldenTests.swift skriver hele sesongtabeller (fem regelsett per
// sak) og alt motoren regner per runde til Fixtures/golden/*.json. Her regnes det samme i TypeScript og
// skrives med sorterte nøkler, og teksten må være helt lik.

import assert from "node:assert/strict";
import { test } from "node:test";
import { courseHoles, numberOfHoles } from "../src/course.ts";
import { courseHandicap, effectiveHandicap, teamBasis } from "../src/handicap.ts";
import { stableStringify } from "../src/jsmath.ts";
import { holeDiff, holeWinner, matchShortText, matchSides, matchStanding, matchText, outcomeForA, allInMatch, strokeOffset } from "../src/match.ts";
import { decodePlayer, decodeRound, decodeSideClaim, type Player, type Round } from "../src/models.ts";
import { decodeRuleset, encodeRuleset, GOLFGUTU, type Ruleset } from "../src/ruleset.ts";
import { roundNetTotal, roundPoints } from "../src/scoring.ts";
import { eveningDates, formatPoints, Season } from "../src/season.ts";
import { closestToPinHole, longestDriveHole, suggestedClosestToPinHole, suggestedLongestDriveHole } from "../src/sideprize.ts";
import { trianglePoints } from "../src/triangle.ts";
import { countingHoles, lowestCommonHole } from "../src/truncation.ts";
import { fixture, golden, map, obj, stablefordRounds } from "./helpers.ts";
import { readFileSync } from "node:fs";

const goldenText = (name: string) =>
  readFileSync(new URL(`../../../Packages/GolfgutuCore/Tests/GolfgutuCoreTests/Fixtures/golden/${name}.json`, import.meta.url), "utf8");

const opt = <T>(x: T | null): T | undefined => (x === null ? undefined : x);

function seasonDump(name: string, variant: string, s: Season) {
  const m = (r: any) => ({ roundIndex: r.roundIndex, roundID: opt(r.roundID), matchNo: opt(r.matchNo), points: r.points, holes: r.holes, isTriangle: r.isTriangle });
  const sd = (r: any) => ({ roundIndex: r.roundIndex, roundID: opt(r.roundID), kind: r.kind, shared: r.shared, points: r.points });
  const rs = (r: any) => ({ roundIndex: r.roundIndex, roundID: opt(r.roundID), points: r.points });
  const sel = <A>(x: { counting: A[]; dropped: A[] }, f: (a: A) => unknown) => ({ counting: x.counting.map(f), dropped: x.dropped.map(f) });
  return {
    name,
    variant,
    rules: encodeRuleset(s.ruleset),
    roundPoints: s.rounds.map((_, i) => obj(s.roundPoints(i))),
    players: s.players.map((p) => {
      const t = s.tableSelection(p.id);
      return {
        id: p.id,
        tableMatches: sel(t.matches, m),
        tableSidePrizes: sel(t.sidePrizes, sd),
        tableRounds: sel(t.rounds, rs),
        matchTotals: s.matchTotals(p.id),
        sidePrizePoints: s.sidePrizePoints(p.id),
        weightedRoundPoints: s.rounds.map((_, i) => s.weightedRoundPoints(i, p.id)),
        countingRounds: sel(s.countingRounds(p.id), rs),
        stablefordTotal: s.stablefordTotal(p.id),
      };
    }),
    jacketBoard: s.jacketBoard().map((r) => ({
      id: r.player.id, name: r.player.name, total: r.total, duel: r.duel, side: r.side, matches: r.matches, holes: r.holes,
      played: r.played, stableford: r.stableford, roundPoints: r.roundPoints, totalText: formatPoints(r.total, s.ruleset),
    })),
    stablefordBoard: s.stablefordBoard().map((r) => ({ id: r.player.id, total: r.total, played: r.played, counting: r.counting, dropped: r.dropped })),
    eveningDates: eveningDates(s.rounds),
    roundNumbers: s.rounds.map((r) => s.roundNumber(r.date)),
    draw: s.drawMatches(s.players, 1),
  };
}

function roundDump(name: string, round: Round, roster: readonly Player[], rules: Ruleset = GOLFGUTU) {
  const perPlayer = <T>(f: (p: Player) => T) => Object.fromEntries(roster.map((p) => [p.id, f(p)]));
  return {
    name,
    courseHoles: courseHoles(round).map((h) => ({ par: h.par, cardIndex: h.cardIndex, meters: opt(h.meters), strokeIndex: h.strokeIndex })),
    countingHoles: countingHoles(round),
    lowestCommonHole: lowestCommonHole(round),
    effective: perPlayer((p) => effectiveHandicap(p, round, roster, rules)),
    courseHandicap: perPlayer((p) => courseHandicap(p, round, rules)),
    teamBasis: perPlayer((p) => teamBasis(p, round, rules)),
    netTotal: perPlayer((p) => roundNetTotal(round, p, roster, rules)),
    roundPoints: obj(roundPoints(round, roster, rules)),
    matches: round.matches.map((m) => {
      const s = matchSides(m, round);
      const d = holeDiff(m, round, roster, rules);
      const standings: Record<string, unknown> = {};
      for (const pid of allInMatch(s)) {
        const st = matchStanding(m, pid, round, roster, rules);
        if (st === null) continue;
        standings[pid] = { ...st, text: matchText(st), shortText: matchShortText(st) };
      }
      return {
        a: s.a, b: s.b, c: opt(s.c),
        strokeOffset: strokeOffset(m, round, roster, rules),
        holeWinners: Array.from({ length: numberOfHoles(round) }, (_, h) => holeWinner(m, h, round, roster, rules)),
        holeDiff: opt(d),
        outcomeForA: opt(outcomeForA(m, round, roster, rules)),
        standings,
        triangle: opt(obj(trianglePoints(m, round, roster, rules))),
      };
    }),
    ldHole: opt(longestDriveHole(round)),
    kpHole: opt(closestToPinHole(round)),
    suggestedLD: suggestedLongestDriveHole(round),
    suggestedKP: suggestedClosestToPinHole(round),
  };
}

/** Sammenligner først strukturen (lesbar diff), så teksten byte for byte. */
function same(name: string, actual: unknown[]) {
  const want = golden(name) as unknown[];
  assert.equal(actual.length, want.length, `${name}: antall`);
  actual.forEach((a, i) => assert.deepEqual(JSON.parse(stableStringify(a)), want[i], `${name}[${i}]`));
  assert.equal(stableStringify(actual), goldenText(name), `${name}: byte for byte`);
}

const sesong = fixture("sesong");
const saker = [...sesong.saker, ...sesong.annetRegelsett.map((a: any) => a.sak)].map((s: any) => ({
  navn: s.navn as string,
  spillere: (s.spillere as any[]).map((p) => decodePlayer(p)),
  runder: (s.runder as any[]).map((r) => decodeRound(r)),
  claims: (s.claims as any[]).map((c) => decodeSideClaim(c)),
}));

test("sesongtabeller: samme som Swift, byte for byte", () => {
  const want = golden("sesonger") as any[];
  // Regelsettene står i goldenfila, i samme rekkefølge per sak.
  const variants: [string, Ruleset][] = [];
  for (const g of want.slice(0, 5)) variants.push([g.variant, decodeRuleset(g.rules)]);
  const out: unknown[] = [];
  for (const sak of saker) {
    for (const [variant, rules] of variants) out.push(seasonDump(sak.navn, variant, new Season(sak.spillere, sak.runder, sak.claims, rules)));
  }
  const sf = fixture("sesong-stableford");
  const sfPlayers = (sf.spillere as any[]).map((p) => decodePlayer(p));
  const sfClaims = (sf.claims as any[]).map((c) => decodeSideClaim(c));
  const sfRounds = stablefordRounds(sf);
  for (const sak of sf.saker) {
    out.push(seasonDump(`sesong-stableford: ${sak.navn}`, "fixture", new Season(sfPlayers, sfRounds, sfClaims, decodeRuleset(sak.regelsett))));
  }
  for (const [variant, rules] of variants) out.push(seasonDump("sesong-stableford", variant, new Season(sfPlayers, sfRounds, sfClaims, rules)));
  const fh = fixture("frosset-handicap");
  const fhPlayers = (fh.spillere as any[]).map((p) => decodePlayer(p));
  const fhRounds = (fh.runder as any[]).map((r) => decodeRound(r));
  const frozen = new Map(Object.entries(fh.spillehandicap as Record<string, Record<string, number>>).map(([k, v]) => [k, map(v)]));
  out.push(seasonDump("frosset-handicap", "troppen", new Season(fhPlayers, fhRounds)));
  out.push(seasonDump("frosset-handicap", "frosset", new Season(fhPlayers, fhRounds, [], GOLFGUTU, frozen)));
  same("sesonger", out);
});

test("runder: samme som Swift, byte for byte", () => {
  const out: unknown[] = [];
  for (const sak of saker) sak.runder.forEach((r, i) => out.push(roundDump(`sesong: ${sak.navn} #${i}`, r, sak.spillere)));
  const players = (x: any[]) => x.map((p) => decodePlayer(p));
  for (const sak of fixture("match").saker) out.push(roundDump(`match: ${sak.navn}`, decodeRound(sak.runde), players(sak.spillere)));
  const avk = fixture("avkorting");
  for (const sak of avk.saker) out.push(roundDump(`avkorting: ${sak.navn}`, decodeRound(sak.runde), players(avk.spillere)));
  out.push(roundDump("avkorting: koster", decodeRound(avk.avkortingenKoster.runde), players(avk.avkortingenKoster.spillere)));
  for (const sak of fixture("handicap").saker) out.push(roundDump(`handicap: ${sak.navn}`, decodeRound(sak.runde), players(sak.spillere)));
  for (const t of fixture("trekant").trekanter) out.push(roundDump(`trekant: ${t.navn}`, decodeRound(t.runde), players(t.spillere)));
  const fh = fixture("frosset-handicap");
  (fh.runder as any[]).forEach((r, i) => out.push(roundDump(`frosset: #${i}`, decodeRound(r), players(fh.spillere))));
  same("runder", out);
});
