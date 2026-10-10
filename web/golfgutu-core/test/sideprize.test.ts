// SidePrizeTests.swift: longest drive og nærmest pinnen. Tall: Fixtures/sidepremier.json.

import assert from "node:assert/strict";
import { test } from "node:test";
import { decodeRound, decodeSideClaim, makeRound, sideClaimLabel, type SideClaim } from "../src/models.ts";
import {
  bestClaimPerPlayer,
  claimsFor,
  closestToPinClaims,
  closestToPinHole,
  formatMeters,
  hasClosestToPin,
  hasLongestDrive,
  longestDriveClaims,
  longestDriveHole,
  seasonClosestToPin,
  seasonLongestDrive,
  sidePrizeWinners,
  suggestedClosestToPinHole,
  suggestedLongestDriveHole,
} from "../src/sideprize.ts";
import { fixture } from "./helpers.ts";

const fil = fixture("sidepremier");
const claims = (fil.claims as any[]).map((c) => decodeSideClaim(c));

test("hullene", () => {
  for (const h of fil.hull) {
    const r = decodeRound(h.runde);
    assert.equal(hasLongestDrive(r), h.harLongestDrive, h.navn);
    assert.equal(hasClosestToPin(r), h.harKp, h.navn);
    assert.equal(longestDriveHole(r) ?? -1, h.longestDriveHullFor, `${h.navn}: LD-hull`);
    assert.equal(closestToPinHole(r) ?? -1, h.kpHullFor, `${h.navn}: KP-hull`);
    assert.equal(suggestedLongestDriveHole(r), h.foreslaattLongestDriveHull, `${h.navn}: LD-forslag`);
    assert.equal(suggestedClosestToPinHole(r), h.foreslaattKpHull, `${h.navn}: KP-forslag`);
  }
});

test("valgfritt som PWA-en", () => {
  assert.ok(hasLongestDrive(makeRound()) && hasClosestToPin(makeRound()));
  const ldAv = makeRound({ ldEnabled: false, ldHoleIndex: 4, kpHoleIndex: 2 });
  assert.ok(longestDriveHole(ldAv) === null && closestToPinHole(ldAv) === 2);
  const kpAv = makeRound({ kpEnabled: false, ldHoleIndex: 4, kpHoleIndex: 2 });
  assert.ok(closestToPinHole(kpAv) === null && longestDriveHole(kpAv) === 4);
  const c: SideClaim[] = [
    { id: "c1", kind: "drive", playerId: "a", roundId: "r1", meters: 260, holeIndex: null, ts: "1" },
    { id: "c2", kind: "kp", playerId: "b", roundId: "r1", meters: 3.4, holeIndex: null, ts: "2" },
  ];
  const av = makeRound({ id: "r1", ldEnabled: false, kpEnabled: false });
  assert.equal(longestDriveClaims(av, c).length, 0);
  assert.equal(closestToPinClaims(av, c).length, 0);
  const paa = makeRound({ id: "r1" });
  assert.deepEqual(sidePrizeWinners(longestDriveClaims(paa, c)), ["a"]);
  assert.deepEqual(sidePrizeWinners(closestToPinClaims(paa, c)), ["b"]);
});

test("innmeldinger og vinnere", () => {
  for (const rc of fil.runder) {
    const r = decodeRound(rc.runde);
    const ld = longestDriveClaims(r, claims);
    const kp = closestToPinClaims(r, claims);
    assert.deepEqual(ld.map((x) => x.id ?? ""), rc.longestDrive, `${r.id}: LD`);
    assert.deepEqual(kp.map((x) => x.id ?? ""), rc.kp, `${r.id}: KP`);
    assert.deepEqual(sidePrizeWinners(ld), rc.vinnereLongestDrive);
    assert.deepEqual(sidePrizeWinners(kp), rc.vinnereKp);
    assert.deepEqual(claimsFor("drive", r, claims), ld);
  }
  assert.deepEqual(fil.runder[0].vinnereLongestDrive, ["c", "b"]);
  assert.deepEqual(fil.runder[1].vinnereKp, ["a", "d"]);
});

test("sesonglister", () => {
  assert.deepEqual(seasonLongestDrive(claims).map((c) => c.id ?? ""), fil.sesong.longestDrive);
  assert.deepEqual(seasonClosestToPin(claims).map((c) => c.id ?? ""), fil.sesong.kp);
  const beste = bestClaimPerPlayer(claims.filter((c) => c.kind === "drive"), (a, b) => a > b);
  assert.deepEqual(beste.map((c) => c.playerId), ["a", "b", "c", "d"]);
  assert.deepEqual(beste.map((c) => c.meters), [280, 300, 272.5, 240]);
});

test("fmtMeter", () => {
  for (const [m, tekst] of fil.fmtMeter) assert.equal(formatMeters(m), tekst, String(m));
  assert.equal(sideClaimLabel("drive"), "Longest drive");
  assert.equal(sideClaimLabel("kp"), "Nærmest pinnen");
});
