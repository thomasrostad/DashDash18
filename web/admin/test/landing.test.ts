import { test } from "node:test";
import assert from "node:assert/strict";
import { contourLevels, contourSegments, noise3 } from "../src/landing/topo.ts";
import { applyDemoEvent, DEMO_EVENTS, DEMO_PLAYERS } from "../src/landing/demo.ts";
import { ARRANGOR_CARDS, card, demoTavla, readingLine, rulesArt } from "../src/landing/markup.ts";
import { startLanding } from "../src/landing/live.ts";

test("høydekurvene: en kul gir én lukket ring rundt toppen", () => {
  // 5 × 5 punkter, høyest i midten.
  const f = [
    0, 0, 0, 0, 0,
    0, 1, 1, 1, 0,
    0, 1, 2, 1, 0,
    0, 1, 1, 1, 0,
    0, 0, 0, 0, 0,
  ];
  const segs = contourSegments(f, 5, 5, 10, 1.5);
  assert.equal(segs.length, 4); // én liten ruter rundt midtpunktet
  for (const [x1, y1, x2, y2] of segs) {
    for (const [x, y] of [[x1, y1], [x2, y2]]) {
      assert.ok(x >= 10 && x <= 30 && y >= 10 && y <= 30, `punktet (${x}, ${y}) ligger rundt toppen`);
    }
  }
  // Endepunktene møtes: ringen er lukket.
  const key = (x: number, y: number) => `${x.toFixed(3)},${y.toFixed(3)}`;
  const count = new Map<string, number>();
  for (const [x1, y1, x2, y2] of segs) for (const k of [key(x1, y1), key(x2, y2)]) count.set(k, (count.get(k) ?? 0) + 1);
  assert.ok([...count.values()].every((n) => n === 2));
});

test("høydekurvene: flatt felt gir ingen kurver og ingen nivåer", () => {
  const f = new Array(16).fill(0.5);
  assert.deepEqual(contourSegments(f, 4, 4, 10, 0.5), []);
  assert.deepEqual(contourLevels(f, 10), []);
});

test("høydekurvene: hvert fjerde nivå er en indekskurve", () => {
  const levels = contourLevels([0, 1, 2, 3], 8);
  assert.equal(levels.length, 7);
  assert.deepEqual(levels.map((l) => l.index), [false, false, false, true, false, false, false]);
  assert.ok(Math.abs(levels[0].iso - 3 / 8) < 1e-9);
});

test("støyen er stabil og holder seg innenfor ±1", () => {
  assert.equal(noise3(1.3, 2.7, 0.4), noise3(1.3, 2.7, 0.4));
  for (let i = 0; i < 500; i++) {
    const v = noise3(i * 0.37, i * 0.11, i * 0.05);
    assert.ok(v >= -1.01 && v <= 1.01);
  }
});

test("eksempeltavla: en birdie flytter spilleren opp, og rekkefølgen ellers står", () => {
  const after = applyDemoEvent(DEMO_PLAYERS, DEMO_EVENTS[0]); // Marte L. +4 = 195
  assert.deepEqual(after.slice(0, 4).map((p) => p.name), ["Kari Moen", "Henrik A.", "Marte L.", "Jon B."]);
  const twice = applyDemoEvent(applyDemoEvent(after, DEMO_EVENTS[0]), DEMO_EVENTS[0]); // 203
  assert.deepEqual(twice.slice(0, 3).map((p) => p.name), ["Kari Moen", "Marte L.", "Henrik A."]);
  assert.equal(twice.find((p) => p.name === "Marte L.")?.points, 203);
  assert.equal(DEMO_PLAYERS[2].points, 191, "originalen endres ikke");
});

// Delene i markup.ts brukes både her og på dashdash18.com (web/atten-lenker/src/salgsside.ts).
test("markeringen: tavla har alle eksempelradene og hendelsene, kortene og setningen er escapet", () => {
  const tavla = demoTavla();
  assert.deepEqual([...tavla.matchAll(/data-navn="([^"]+)"/g)].map((m) => m[1]), DEMO_PLAYERS.map((p) => p.name));
  assert.match(tavla, /<tr class="lead" data-navn="Kari Moen"/);
  const events = JSON.parse(/data-hendelser="([^"]+)"/.exec(tavla)![1].replace(/&quot;/g, '"'));
  assert.deepEqual(events, DEMO_EVENTS);
  assert.equal(ARRANGOR_CARDS.length, 5);
  assert.ok(ARRANGOR_CARDS.every((c) => c.startsWith('<article class="kcard')));
  const line = readingLine([{ text: "Før <b> og " }, { text: "tavla", soft: true }]);
  assert.equal(line, '<p class="read"><span class="w">Før</span> <span class="w">&lt;b&gt;</span> <span class="w">og</span> <span class="soft"><span class="w">tavla</span></span></p>');
  assert.match(card({ eyebrow: "A&B", title: "T", em: "E", art: rulesArt([["x", "y"]]) }), /<p class="eb">A&amp;B<\/p><h3>T <em>E<\/em><\/h3><div class="art rules">/);
});

test("bevegelsen er selvstendig, så dashdash18.com kan legge den inn som tekst", () => {
  const fn = new Function(`return (${startLanding.toString()});`)();
  assert.equal(typeof fn, "function");
  assert.doesNotMatch(startLanding.toString(), /import\(|require\(/);
});
