import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { buildTVPayload } from "../src/tv.ts";
import { nameList } from "../src/hoydepunkter.ts";

const fixture = JSON.parse(readFileSync(new URL("../../golfgutu-core/test/fixtures/tavla.json", import.meta.url), "utf8"));
const d = fixture.tavlaData;

// En liten sesong: kveld 1 er låst, kveld 2 pågår. Spillehandicap 0, så poengene er par − slag + 2 per hull.
// Par på banen i fixturen: 4 4 3 5 4 4 3 4 5 | 4 3 4 5 4 4 3 4 5.
const PARS: number[] = d.course_holes.filter((h: { course_id: string }) => h.course_id === "00000000-0000-0000-0000-000000009001")
  .sort((a: { hole_number: number }, b: { hole_number: number }) => a.hole_number - b.hole_number).map((h: { par: number }) => h.par);
const id = (n: number) => `00000000-0000-0000-0000-${String(n).padStart(12, "0")}`;
const [BJORN, LARS, KARE, KNUT] = [1, 2, 3, 4].map(id);
const R1 = id(181), R2 = id(182), E1 = id(281), E2 = id(282);
const SEASON = id(9002);
const STABLEFORD = { version: 2, table: { pointsSource: "stableford", counting: { unit: "round", best: null }, roundingStep: null },
  sidePrizes: { longestDrive: { enabled: false, points: 1 }, closestToPin: { enabled: false, points: 1 } } };

/** Slag mot par per hull: 0 par, −1 birdie, +1 bogey. Kortere enn 18: resten er ikke spilt. */
type Card = number[];
const par = (n: number, change: Record<number, number> = {}): Card => Array.from({ length: n }, (_, i) => change[i] ?? 0);

interface Live {
  rules?: unknown; venue?: string | null; hide?: number; ld?: boolean; status?: string; claims?: unknown[];
  tonight?: Record<string, { bay: number; card: Card; strokes?: Record<number, number> }>;
}

/** Kveld 1: Bjørn 40, Lars 36, Knut 34, Kåre 30. Kveld 2 (pågår): Bjørn ferdig med 36, Lars eagle på hull 4 og ti hull,
 *  Kåre hole in one på hull 7 og birdie på 1–3 etter tolv hull, Knut par på tolv hull. */
function board(o: Live = {}) {
  const template = d.rounds.find((r: { id: string }) => r.id === id(105));
  const round = (rid: string, eid: string, status: string) => ({ ...template, id: rid, event_id: eid, status, name: null, ld_enabled: o.ld ?? false,
    kp_enabled: false, hide_last_holes: status === "active" ? (o.hide ?? 0) : 0, venue: o.venue === undefined ? "course" : o.venue });
  const first: Record<string, Card> = { [BJORN]: par(18, { 0: -1, 1: -1, 4: -1, 5: -1 }), [LARS]: par(18), [KNUT]: par(18, { 0: 1, 1: 1 }),
    [KARE]: par(18, { 0: 1, 1: 1, 2: 1, 4: 1, 5: 1, 7: 1 }) };
  const tonight = o.tonight ?? {
    [BJORN]: { bay: 1, card: par(18) },
    [LARS]: { bay: 2, card: par(10, { 3: -2 }) },
    [KARE]: { bay: 3, card: par(12, { 0: -1, 1: -1, 2: -1 }), strokes: { 6: 1 } },
    [KNUT]: { bay: 3, card: par(12) },
  };
  const scores = (rid: string, m: string, card: Card, strokes: Record<number, number> = {}) =>
    card.map((x, i) => ({ round_id: rid, member_id: m, hole_index: i, strokes: strokes[i] ?? PARS[i] + x }));
  const player = (rid: string, m: string, bay: number | null) => ({ round_id: rid, member_id: m, club_id: id(9000), handicap_index: 10,
    seed_group: null, playing_handicap: 0, bay_no: bay, is_marker: false, team_no: null });
  return {
    ...d,
    events: [{ ...d.events[0], id: E1, event_date: "2026-09-01" }, { ...d.events[0], id: E2, event_date: "2026-09-08" }],
    rounds: [round(R1, E1, "locked"), round(R2, E2, o.status ?? "active")],
    round_holes: [],
    players: [...[BJORN, LARS, KARE, KNUT].map((m) => player(R1, m, 1)), ...Object.entries(tonight).map(([m, t]) => player(R2, m, t.bay))],
    matches: [],
    claims: o.claims ?? [],
    scores: [...Object.entries(first).flatMap(([m, c]) => scores(R1, m, c)), ...Object.entries(tonight).flatMap(([m, t]) => scores(R2, m, t.card, t.strokes))],
    competition: { name: "Høst", season_id: SEASON, club_id: id(9000), status: "active", rules: o.rules ?? STABLEFORD, club_name: null },
  };
}

const texts = (b: unknown, kind?: string) => buildTVPayload(b as Record<string, unknown>).highlights
  .filter((h) => kind === undefined || h.kind === kind).map((h) => `${h.label}: ${h.text}`);
const total = (b: unknown, name: string) => Number(buildTVPayload(b as Record<string, unknown>).rows.find((r) => r.name === name)!.total.replace(",", "."));

test("høydepunkter: bragdene er brutto, nyeste først (færrest hull siden), høyst seks", () => {
  assert.deepEqual(texts(board()).filter((t) => !t.includes("så langt") && !t.startsWith("Jakten") && !t.startsWith("Ute") && !t.startsWith("Best")), [
    "Kåre · hull 7: hole in one!",
    "Lars · hull 4: eagle",
    "Kåre · hull 3: birdie",
    "Kåre · hull 2: birdie",
    "Kåre · hull 1: birdie",
  ]);
  const p = buildTVPayload(board());
  assert.equal(p.highlights.find((h) => h.kind === "holeInOne")?.label, "Kåre · hull 7");
  // Netto birdie (slag fått) er ikke en bragd: med handicap 36 er par netto birdie, men brutto par.
  const many = board({ tonight: { [LARS]: { bay: 1, card: par(18, { 0: -1, 1: -1, 2: -1, 3: -1, 4: -1, 5: -1, 6: -1, 7: -1 }) } } });
  assert.equal(texts(many).filter((t) => t.endsWith("birdie")).length, 6);
  assert.deepEqual(texts(many, "birdie").slice(0, 2), ["Lars · hull 8: birdie", "Lars · hull 7: birdie"]);
});

test("høydepunkter: de beste så langt, med flest birdier (brutto birdie eller bedre) og de ni siste", () => {
  assert.deepEqual(texts(board(), "best"), ["Best så langt: Bjørn · 36 poeng"]);
  assert.deepEqual(texts(board(), "birdies"), ["Flest birdier så langt: Kåre · 4 birdier"]);
  assert.deepEqual(texts(board(), "backNine"), ["Best på de ni siste: Bjørn · 18 poeng"], "bare de som har spilt alle de ni siste");
  // Likt: begge navnene.
  const tie = board({ tonight: { [BJORN]: { bay: 1, card: par(5, { 0: -1 }) }, [LARS]: { bay: 1, card: par(5, { 1: -1 }) } } });
  assert.deepEqual(texts(tie, "best"), ["Best så langt: Bjørn og Lars · 11 poeng"]);
  assert.deepEqual(texts(tie, "birdies"), ["Flest birdier så langt: Bjørn og Lars · 1 birdie"]);
  assert.deepEqual(texts(tie, "backNine"), []);
});

test("høydepunkter: hvor flightene er (båsene i simulatoren), og skjulte hull røper ikke hullet", () => {
  assert.deepEqual(texts(board(), "groups"), ["Ute på banen: Flight 1 er ferdig · flight 2 på hull 11 · flight 3 på hull 13"]);
  assert.deepEqual(texts(board({ venue: null }), "groups"), ["I båsene: Bås 1 er ferdig · bås 2 på hull 11 · bås 3 på hull 13"]);
  // Tre skjulte hull: scorene på 16–18 kommer ikke til TV-en. Bjørn har ført 15 hull, de andre er ikke der ennå.
  const hidden = board({ hide: 3, tonight: { [BJORN]: { bay: 1, card: par(15) }, [LARS]: { bay: 2, card: par(10) } } });
  assert.deepEqual(texts(hidden, "groups"), ["Ute på banen: Flight 1 er på de siste hullene · flight 2 på hull 11"]);
  // Flere enn tre flighter: flere innslag.
  const five = board({ tonight: Object.fromEntries([1, 2, 3, 4].map((n) => [id(n), { bay: n, card: par(n) }])) });
  assert.equal(texts(five, "groups").length, 2);
});

test("høydepunkter: jakten, med «trenger N poeng» som regelmotoren bekrefter", () => {
  // Lars og Knut deler 3. plass med 58; navnene står i tabellens rekkefølge.
  assert.deepEqual(buildTVPayload(board()).rows.slice(0, 4).map((r) => [r.place, r.name, r.total]),
    [["1.", "Bjørn", "76"], ["2.", "Kåre", "59"], ["3.", "Knut", "58"], ["3.", "Lars", "58"]]);
  assert.deepEqual(texts(board(), "chase"), [
    "Jakten: Kåre har gått forbi Knut og Lars",
    "Jakten: Kåre trenger 18 poeng for å gå forbi Bjørn",
    "Jakten: Knut trenger 19 poeng for å gå forbi Bjørn",
  ]);
  // Fasit med regelmotoren: Kåre spiller ferdig med 17 poeng til (fem birdier og en par) → likt; 18 (seks birdier) → forbi.
  const finish = (birdies: number) => board({ tonight: {
    [BJORN]: { bay: 1, card: par(18) },
    [KARE]: { bay: 3, card: par(18, { 0: -1, 1: -1, 2: -1, ...Object.fromEntries(Array.from({ length: birdies }, (_, k) => [12 + k, -1])) }), strokes: { 6: 1 } },
  } });
  assert.equal(total(finish(5), "Kåre"), total(finish(5), "Bjørn"));
  assert.ok(total(finish(6), "Kåre") > total(finish(6), "Bjørn"));
  assert.equal(buildTVPayload(finish(6)).rows[0].name, "Kåre");
  // Tatt ledelsen.
  assert.deepEqual(texts(finish(6), "chase"), ["Jakten: Kåre har tatt ledelsen"]);
});

test("høydepunkter: «trenger N poeng» bare når det er sikkert", () => {
  const need = (b: unknown) => texts(b, "chase").filter((t) => t.includes("trenger"));
  // Lederen spiller fortsatt.
  assert.deepEqual(need(board({ tonight: { [BJORN]: { bay: 1, card: par(17) }, [LARS]: { bay: 2, card: par(10) } } })), []);
  // Skjulte hull, sidepremie i runden.
  assert.deepEqual(need(board({ hide: 3 })), []);
  assert.deepEqual(need(board({ ld: true, rules: { ...STABLEFORD, sidePrizes: { longestDrive: { enabled: true, points: 1 }, closestToPin: { enabled: false, points: 1 } } } })), []);
  // Matchpoeng, beste N, snitt, plassering og formens poeng: tabellen vokser ikke med stablefordpoengene.
  const table = (t: Record<string, unknown>) => ({ ...STABLEFORD, table: { ...STABLEFORD.table, ...t } });
  for (const t of [{ pointsSource: "matches" }, { counting: { unit: "round", best: 1 } }, { aggregation: "average" }, { pointsSource: "placement" },
    { formPoints: true }, { roundingStep: 2 }]) {
    assert.deepEqual(need(board({ rules: table(t) })), [], JSON.stringify(t));
  }
  // Avrunding til halve poeng flytter ikke hele poeng: fortsatt med.
  assert.equal(need(board({ rules: table({ roundingStep: 0.5 }) })).length, 2);
  // «Gått forbi» gjelder alle tabelltyper (samme sammenligning som bevegelsen).
  assert.ok(texts(board({ rules: table({ pointsSource: "matches" }) }), "chase").every((t) => !t.includes("trenger")));
});

test("høydepunkter: sidepremiene i runden fra innmeldingene", () => {
  const claim = (m: string, kind: string, meters: number, at: string) => ({ id: id(Math.round(meters * 10)), round_id: R2, member_id: m, kind, meters, hole_index: 3, created_at: at });
  const b = board({ ld: true, claims: [claim(LARS, "drive", 251.5, "2026-09-08T18:00:00Z"), claim(KNUT, "drive", 262, "2026-09-08T18:10:00Z")] });
  assert.deepEqual(texts(b, "drive"), ["Lengste drive så langt: Knut · 262 m"]);
  assert.deepEqual(texts(board({ ld: false, claims: [claim(LARS, "drive", 250, "2026-09-08T18:00:00Z")] }), "drive"), [], "premien er av i runden");
});

test("høydepunkter: ingen når ingen runde pågår, i cupen og for fixturens låste sesong", () => {
  assert.deepEqual(buildTVPayload(board({ status: "locked" })).highlights, []);
  const s = fixture.sesonger[0];
  const tv = buildTVPayload({ ...d, competition: { name: s.name, season_id: s.id, club_id: s.club_id, status: s.status, rules: s.rules } });
  assert.equal(tv.latest?.ongoing, false);
  assert.deepEqual(tv.highlights, []);
});

test("høydepunkter: fixturen med siste runde som pågår gir bare navn som står i tabellen", () => {
  const s = fixture.sesonger[0];
  const last = d.rounds.at(-1);
  const tv = buildTVPayload({ ...d, rounds: d.rounds.map((r: { id: string }) => (r.id === last.id ? { ...r, status: "active" } : r)),
    competition: { name: s.name, season_id: s.id, club_id: s.club_id, status: s.status, rules: s.rules } });
  assert.ok(tv.highlights.length > 0);
  const names = tv.rows.map((r) => r.name);
  for (const h of tv.highlights) {
    assert.doesNotMatch(JSON.stringify(h), /[0-9a-f]{8}-[0-9a-f]{4}-/, "ingen id-er");
    const who = h.kind === "chase" || h.kind === "groups" ? h.text : h.label.includes(" · hull ") ? h.label : h.text;
    assert.ok(names.some((n) => who.includes(n)) || h.kind === "groups", `${h.label}: ${h.text}`);
  }
});

test("høydepunkter i ligaen: «trenger» med stablefordpoeng og alle runder, ikke med plassering", () => {
  const b = board();
  const comp = id(9100);
  const names = new Map(d.members.map((m: { id: string; display_name: string }) => [m.id, m.display_name]));
  const league = (rules: unknown) => ({
    ...b, events: undefined,
    competition: { id: comp, name: "Ligaen", kind: "league", status: "active", season_id: null, club_id: id(9000), owner_id: null, entry: "club",
      rules, starts_on: null, ends_on: null, is_main: false, club_name: null },
    participants: [], links: b.rounds.map((r: { id: string }) => ({ competition_id: comp, round_id: r.id })),
    rounds: b.rounds.map((r: { event_id: string }) => ({ ...r, event_date: r.event_id === E1 ? "2026-09-01" : "2026-09-08" })),
    roster: b.players.map((p: { round_id: string; member_id: string }) => ({ round_id: p.round_id, player_id: p.member_id, display_name: names.get(p.member_id) ?? null })),
    round_participants: [], profiles: [], cup_matches: [],
  });
  const stableford = texts(league({ version: 2, competition: { league: { scoring: "stableford", bestRounds: null } } }), "chase");
  assert.ok(stableford.includes("Jakten: Kåre trenger 18 poeng for å gå forbi Bjørn"), stableford.join(" | "));
  assert.ok(texts(league({ version: 2, competition: { league: { scoring: "placement", bestRounds: null } } }), "chase").every((t) => !t.includes("trenger")));
  assert.ok(texts(league({ version: 2, competition: { league: { scoring: "stableford", bestRounds: 1 } } }), "chase").every((t) => !t.includes("trenger")));
  assert.ok(texts(league({ version: 2, competition: { league: { scoring: "stableford", bestRounds: null } } }), "eagle").length === 1);
});

test("navnelista: ett, to og tre navn, ellers ingen", () => {
  assert.equal(nameList(["Bjørn"]), "Bjørn");
  assert.equal(nameList(["Bjørn", "Ola"]), "Bjørn og Ola");
  assert.equal(nameList(["Bjørn", "Ola", "Kåre"]), "Bjørn, Ola og Kåre");
  assert.equal(nameList(["a", "b", "c", "d"]), null);
  assert.equal(nameList([]), null);
});
