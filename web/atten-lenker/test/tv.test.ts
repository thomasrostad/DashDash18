import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { buildTVPayload, normalizeTVCode, tvBoardPage, tvCodePage } from "../src/tv.ts";
import { handle } from "../src/index.ts";
import { decodeSeasonRow, decodeTavlaData, tavlaInput, TavlaStandings } from "../../golfgutu-core/src/index.ts";

const fixture = JSON.parse(readFileSync(new URL("../../golfgutu-core/test/fixtures/tavla.json", import.meta.url), "utf8"));
const expected = JSON.parse(readFileSync(new URL("../../golfgutu-core/test/fixtures/tavla.forventet.json", import.meta.url), "utf8"));

test("koden normaliseres", () => {
  assert.equal(normalizeTVCode("abcde fghjk"), "ABCDEFGHJK");
  assert.equal(normalizeTVCode("ABCDE-FGHJK"), "ABCDEFGHJK");
  assert.equal(normalizeTVCode("ABCDEFGHJ1"), null); // 1 er ikke i alfabetet
  assert.equal(normalizeTVCode("kort"), null);
});

test("TV-tabellen er appens tabell (samme regelmotor og tekster)", () => {
  const season = fixture.sesonger[0];
  const board = { ...fixture.tavlaData, competition: { name: season.name, season_id: season.id, club_id: season.club_id,
    status: season.status, rules: season.rules, club_name: "Golfgutu Invitational" } };
  const tv = buildTVPayload(board);
  // Fasiten er laget av appens Swift-kode (tools/swift-tavla i golfgutu-core).
  const app = expected.tavla[0] as { rows: { placeText: string; name: string; totalText: string; detail: string }[] };
  assert.ok(tv.rows.length > 0);
  assert.match(tv.played, /av \d+ (kveld|kvelder|spilledag|spilledager) spilt/);
  assert.deepEqual(tv.rows.map((r) => [r.place, r.name, r.total, r.detail]),
                   app.rows.map((r) => [r.placeText, r.name, r.totalText, r.detail]));
  assert.ok(tv.latest === null || tv.latest.lines.every((l, i, a) => i === 0 || a[i - 1].points >= l.points));
});

test("TV med tabellreglene: delt plass, playoff og uten plass som i appen (steg 6)", () => {
  fixture.sesonger.forEach((season: { id: string; club_id: string; name: string; status: string; rules: unknown }, i: number) => {
    const board = { ...fixture.tavlaData, competition: { name: season.name, season_id: season.id, club_id: season.club_id,
      status: season.status, rules: season.rules, club_name: null } };
    const tv = buildTVPayload(board);
    const app = expected.tavla[i] as { rows: { placeText: string; name: string; totalText: string; detail: string }[] };
    assert.deepEqual(tv.rows.map((r) => [r.place, r.name, r.total, r.detail]),
                     app.rows.map((r) => [r.placeText, r.name, r.totalText, r.detail]), season.name);
  });
  const playoff = fixture.sesonger.findIndex((s: { name: string }) => s.name === "Playoff 2026");
  const s = fixture.sesonger[playoff];
  const tv = buildTVPayload({ ...fixture.tavlaData, competition: { name: s.name, season_id: s.id, club_id: s.club_id, status: s.status, rules: s.rules } });
  assert.deepEqual(tv.rows.slice(0, 3).map((r) => r.place), ["1.", "1.", "1."]);
  assert.ok(tv.rows[0].detail.startsWith("Playoff · "));
  assert.equal(tv.rows.at(-1)?.place, "–");
});

test("TV med playoff-runde (sql/047): vinneren først, og playoffen er ikke siste runde", () => {
  const s = fixture.sesonger.find((x: { name: string }) => x.name === "Playoff 2026");
  const t = new TavlaStandings(tavlaInput(decodeTavlaData(fixture.tavlaData), decodeSeasonRow(s)));
  const tied = t.rows.filter((r) => r.playoffPending).map((r) => r.memberID);
  assert.ok(tied.length >= 2);
  const template = fixture.tavlaData.rounds.find((r: { status: string; course_id: string | null }) => r.status === "locked" && r.course_id !== null);
  const pid = "99999999-0000-0000-0000-000000000001";
  const playoff = { ...template, id: pid, round_no: 9, name: "Playoff", status: "active", handicap_allowance: 0, counts: false,
    kind: "playoff", playoff_for: s.id, playoff_holes: [17, 0, 17] };
  const board = {
    ...fixture.tavlaData,
    rounds: [...fixture.tavlaData.rounds, playoff],
    players: [...fixture.tavlaData.players, ...tied.map((m) => ({ round_id: pid, member_id: m, club_id: template.club_id, playing_handicap: 0 }))],
    scores: [...fixture.tavlaData.scores, ...tied.map((m, i) => ({ round_id: pid, member_id: m, hole_index: 0, strokes: i === 1 ? 3 : 4 }))],
    competition: { name: s.name, season_id: s.id, club_id: s.club_id, status: s.status, rules: s.rules },
  };
  const before = buildTVPayload({ ...fixture.tavlaData, competition: board.competition });
  const tv = buildTVPayload(board);
  const winner = t.rows.find((r) => r.memberID === tied[1])!.name;
  assert.equal(tv.rows[0].name, winner);
  assert.equal(tv.rows[0].place, "1.");
  assert.ok(tv.rows.slice(1, tied.length).every((r) => r.place === "2."));
  assert.ok(!tv.rows[0].detail.startsWith("Playoff"));
  assert.deepEqual(tv.latest, before.latest, "playoffen er ikke siste runde");
  assert.equal(tv.note, null, "playoffen skjuler ingen hull");
});

test("TV med skjulte hull (sql/047): notis mens runden går, ingen når den er låst", () => {
  const s = fixture.sesonger[0];
  const competition = { name: s.name, season_id: s.id, club_id: s.club_id, status: s.status, rules: s.rules };
  const last = fixture.tavlaData.rounds.at(-1);
  const rounds = (status: string, hide: number) => fixture.tavlaData.rounds.map((r: { id: string }) =>
    r.id === last.id ? { ...r, status, hide_last_holes: hide } : r);
  // Serveren sender ikke scorene på de skjulte hullene: de mangler bare, og TV-en regner med det den får.
  const hiddenScores = fixture.tavlaData.scores.filter((x: { round_id: string; hole_index: number }) => x.round_id !== last.id || x.hole_index < last.hole_count - 3);
  const tv = buildTVPayload({ ...fixture.tavlaData, rounds: rounds("active", 3), scores: hiddenScores, competition });
  assert.equal(tv.note, "De siste hullene vises når runden er låst");
  assert.ok(tv.rows.length > 0);
  assert.equal(buildTVPayload({ ...fixture.tavlaData, rounds: rounds("locked", 3), competition }).note, null);
  assert.equal(buildTVPayload({ ...fixture.tavlaData, competition }).note, null);
  assert.ok(tvBoardPage("ABCDEFGHJK", "n").includes('id="note"'));
});

test("TV for liga er appens ligatabell (sql/043)", () => {
  const d = fixture.tavlaData;
  const club = d.members[0].club_id;
  const id = "00000000-0000-0000-0000-000000009100";
  const dates = new Map(d.events.map((e: { id: string; event_date: string }) => [e.id, e.event_date]));
  const names = new Map(d.members.map((m: { id: string; display_name: string }) => [m.id, m.display_name]));
  // Slik tv_competition_data leverer det: datoen på runden, navnene fra round_roster.
  const board = {
    ...d,
    events: undefined,
    competition: { id, name: "Onsdagsligaen", kind: "league", status: "active", season_id: null, club_id: club, owner_id: null,
      entry: "club", rules: { version: 2, competition: { league: { bestRounds: 3 } } }, starts_on: null, ends_on: null, is_main: false,
      club_name: "Golfgutu Invitational" },
    participants: [],
    links: d.rounds.map((r: { id: string }) => ({ competition_id: id, round_id: r.id })),
    rounds: d.rounds.map((r: { event_id: string }) => ({ ...r, event_date: dates.get(r.event_id) ?? null })),
    roster: d.players.map((p: { round_id: string; member_id: string }) => ({ round_id: p.round_id, player_id: p.member_id, display_name: names.get(p.member_id) ?? null })),
    round_participants: [],
    profiles: [],
    cup_matches: [],
  };
  const tv = buildTVPayload(board);
  const app = expected.konkurranser[0];
  assert.equal(app.kind, "league");
  const want = app.standings as { rows: { placeText: string; name: string; totalText: string; detail: string }[]; rounds: { columns: { title: string }[] } };
  assert.ok(tv.rows.length > 0);
  assert.deepEqual(tv.rows.map((r) => [r.place, r.name, r.total, r.detail]),
                   want.rows.map((r) => [r.placeText, r.name, r.totalText, r.detail]));
  assert.equal(tv.latest?.title, want.rounds.columns.at(-1)?.title);
  assert.equal(tv.name, "Onsdagsligaen");
  // Utseendet: tittel, regel og hvor langt den har kommet er de samme tekstene som før, og rutene følger tabellen.
  assert.equal(tv.kind, "league");
  assert.equal(tv.heading.title, "Onsdagsligaen");
  assert.equal(tv.played, `${tv.heading.progress} · ${tv.heading.rule}`);
  assert.equal(tv.rounds?.rows.length, tv.rows.length);
  assert.deepEqual(tv.rounds?.labels, want.rounds.columns.map((_, i) => `${i + 1}`));
});

test("TV for cup viser runden som pågår", () => {
  const d = fixture.tavlaData;
  const id = "00000000-0000-0000-0000-000000009200";
  const pid = (i: number) => `00000000-0000-0000-0000-${String(500 + i).padStart(12, "0")}`;
  const match = (no: number, slot: number, a: string, b: string | null, winner: string | null, result: string | null) =>
    ({ id: `${no}-${slot}`, competition_id: id, round_no: no, slot, player_a: a, player_b: b, winner, walkover: false, result, round_id: null });
  const board = {
    competition: { id, name: "Klubbcupen", kind: "cup", status: "active", season_id: null, club_id: d.members[0].club_id, owner_id: null,
      entry: "listed", rules: { version: 2 }, starts_on: null, ends_on: null, is_main: false, club_name: null },
    participants: [0, 1, 2, 3].map((i) => ({ id: pid(i), competition_id: id, member_id: d.members[i].id, profile_id: null, status: "active" })),
    members: d.members,
    cup_matches: [match(1, 0, pid(0), pid(3), pid(0), "3&2"), match(1, 1, pid(1), pid(2), null, null)],
  };
  const tv = buildTVPayload(board);
  assert.equal(tv.played, "Semifinale");
  assert.equal(tv.rows.length, 2);
  assert.equal(tv.rows[0].detail, "3&2");
  assert.equal(tv.rows[0].total, d.members[0].display_name);
  assert.equal(tv.kind, "cup");
  assert.deepEqual(tv.heading, { title: "Klubbcupen", rule: null, progress: "Semifinale" });
  assert.equal(tv.rounds, null);
});

test("TV med flere konkurranser og lag mot lag (sql/048): små paneler ved siden av hovedtabellen", () => {
  const season = fixture.sesonger[0];
  const competition = { name: season.name, season_id: season.id, club_id: season.club_id, status: season.status, rules: season.rules, club_name: null };
  const plain = buildTVPayload({ ...fixture.tavlaData, competition });
  // Uten 048-feltene: som før.
  assert.deepEqual(plain.extras, []);
  assert.equal(plain.teams, null);

  const round = "00000000-0000-0000-0000-000000000105"; // runden som går
  const players = fixture.tavlaData.players.map((p: { round_id: string }, i: number) => (p.round_id === round ? { ...p, side: i % 2 === 0 ? 1 : 2 } : p));
  const comp = (n: number, name: string, isMain: boolean, form: string) =>
    ({ id: `66666666-6666-6666-6666-66666666666${n}`, round_id: round, name, is_main: isMain, format_version: 1, config: { form }, sort_order: n });
  const board = {
    ...fixture.tavlaData, competition, players,
    round_competitions: [comp(0, "Stableford", true, "stableford"), comp(1, "Skins", false, "skins"), comp(2, "Foursome", false, "foursome")],
  };
  const tv = buildTVPayload(board);
  // Hovedtabellen er den samme.
  assert.deepEqual(tv.rows, plain.rows);
  assert.deepEqual(tv.extras.map((e) => e.title), ["Skins", "Foursome"]);
  assert.ok(tv.extras[0].lines.length > 0 && tv.extras[0].lines.length <= 5);
  // Bare navn som alt er i svaret.
  const names = new Set(fixture.tavlaData.members.map((m: { display_name: string }) => m.display_name));
  for (const l of tv.extras[0].lines) {
    assert.match(l.name, /^\d+\. /);
    for (const n of l.name.replace(/^\d+\. /, "").split(" og ")) assert.ok(names.has(n), n);
  }
  assert.deepEqual(tv.extras[1].lines, [{ name: "Ikke støttet ennå", score: "" }]);
  assert.equal(tv.teams?.title, "Lag mot lag");
  assert.deepEqual(tv.teams?.lines.map((l) => l.name).sort(), ["Side 1", "Side 2"]);
  assert.match(tvBoardPage("ABCDEFGHJK", "n"), /id="extras"/);
});

test("TV med maksimumscore og match som konkurranser: slag og stillingen, side 1 mot side 2 fra lag mot lag", () => {
  const season = fixture.sesonger[0];
  const competition = { name: season.name, season_id: season.id, club_id: season.club_id, status: season.status, rules: season.rules, club_name: null };
  const round = "00000000-0000-0000-0000-000000000105";
  const players = fixture.tavlaData.players.map((p: { round_id: string }, i: number) => (p.round_id === round ? { ...p, side: i % 2 === 0 ? 1 : 2 } : p));
  const comp = (n: number, name: string, isMain: boolean, config: Record<string, unknown>) =>
    ({ id: `77777777-7777-7777-7777-77777777777${n}`, round_id: round, name, is_main: isMain, format_version: 1, config, sort_order: n });
  const board = {
    ...fixture.tavlaData, competition, players,
    round_competitions: [
      comp(0, "Stableford", true, { form: "stableford" }),
      comp(1, "Maks", false, { form: "maks-score" }),
      comp(2, "Lagmatch", false, { teamForm: { type: "individual" }, scoring: { type: "matchPlay" } }),
    ],
  };
  const tv = buildTVPayload(board);
  assert.deepEqual(tv.extras.map((e) => e.title), ["Maks", "Lagmatch"]);
  assert.ok(tv.extras[0].lines.length > 0);
  for (const l of tv.extras[0].lines) assert.match(l.score, /^\d+$/);
  // To rader, én per side, med stillingen som tekst.
  assert.equal(tv.extras[1].lines.length, 2);
  for (const l of tv.extras[1].lines) assert.match(l.score, /opp|ned|Delt|Vunnet|Tapt|Ikke startet/);
});

test("TV med match med én ball per lag: foursome-runden, rundens to lag", () => {
  const season = fixture.sesonger[0];
  const competition = { name: season.name, season_id: season.id, club_id: season.club_id, status: season.status, rules: season.rules, club_name: null };
  const round = "00000000-0000-0000-0000-000000000105";
  const rounds = fixture.tavlaData.rounds.map((r: { id: string }) => (r.id === round ? { ...r, format: "foursome" } : r));
  let n = 0;
  const players = fixture.tavlaData.players.map((p: { round_id: string }) => {
    if (p.round_id !== round || n >= 4) return p;
    n += 1;
    return { ...p, team_no: n <= 2 ? 1 : 2 };
  });
  const comp = (i: number, name: string, isMain: boolean, config: Record<string, unknown>) =>
    ({ id: `77777777-7777-7777-7777-77777777778${i}`, round_id: round, name, is_main: isMain, format_version: 1, config, sort_order: i });
  const board = {
    ...fixture.tavlaData, competition, rounds, players,
    round_competitions: [
      comp(0, "Foursome", true, { form: "foursome" }),
      comp(1, "Foursome-match", false, { teamForm: { type: "pairs", pairs: "foursome" }, scoring: { type: "matchPlay" } }),
    ],
  };
  const tv = buildTVPayload(board);
  assert.deepEqual(tv.extras.map((e) => e.title), ["Foursome-match"]);
  // To rader, ett per lag (to navn), med stillingen som tekst.
  assert.equal(tv.extras[0].lines.length, 2);
  for (const l of tv.extras[0].lines) {
    assert.match(l.name, / og /);
    assert.match(l.score, /opp|ned|Delt|Vunnet|Tapt|Ikke startet/);
  }
});

test("TV-sidene", async () => {
  const home = await handle(new Request("https://dashdash18.com/tv"));
  assert.equal(home.status, 200);
  const page = await handle(new Request("https://dashdash18.com/tv/ABCDEFGHJK"));
  assert.equal(page.status, 200);
  assert.match(page.headers.get("Content-Security-Policy") ?? "", /connect-src 'self'/);
  const lower = await handle(new Request("https://dashdash18.com/tv/abcdefghjk"));
  assert.equal(lower.status, 302);
  const bad = await handle(new Request("https://dashdash18.com/tv/xx.json"));
  assert.equal(bad.status, 404);
  assert.ok(tvBoardPage("ABCDEFGHJK", "n").includes('/tv/ABCDEFGHJK.json'));
});

// ---------- utseendet (02.11.2026): samme uttrykk som tavla på TV-en på forsiden ----------

const seasonBoard = (i: number) => {
  const s = fixture.sesonger[i];
  return { ...fixture.tavlaData, competition: { name: s.name, season_id: s.id, club_id: s.club_id, status: s.status, rules: s.rules, club_name: "Golfgutu Invitational" } };
};

test("TV: tittelen delt i navn og regel, med samme tekst som name og played", () => {
  fixture.sesonger.forEach((_: unknown, i: number) => {
    const tv = buildTVPayload(seasonBoard(i));
    assert.equal(tv.kind, "season");
    assert.equal(tv.heading.progress, tv.played);
    assert.equal(tv.name, tv.heading.rule ? `${tv.heading.rule} · ${tv.heading.title}` : tv.heading.title);
  });
  assert.equal(buildTVPayload(seasonBoard(0)).heading.rule, "Jakkeracet");
});

test("TV: poengene per runde er rutenettet i «Alle runder», i tabellens rekkefølge", () => {
  fixture.sesonger.forEach((_: unknown, i: number) => {
    const board = seasonBoard(i);
    const tv = buildTVPayload(board);
    const grid = new TavlaStandings(tavlaInput(decodeTavlaData(board), decodeSeasonRow({ ...fixture.sesonger[i] }))).roundGrid();
    assert.ok(tv.rounds);
    assert.equal(tv.rounds.labels.length, grid.columns.length);
    assert.equal(tv.rounds.rows.length, tv.rows.length);
    const byName = new Map(grid.rows.map((r) => [r.name, r.points]));
    tv.rows.forEach((r, k) => assert.deepEqual(tv.rounds!.rows[k]?.points, byName.get(r.name), r.name));
    // Siste runde i kortet ved siden av er siste kolonne i rutene.
    const n = tv.rounds.labels.length - 1;
    for (const l of tv.latest!.lines) assert.equal(tv.rounds.rows[tv.rows.findIndex((r) => r.name === l.name)]?.points[n], l.points);
  });
});

test("TV-sidene har uttrykket fra forsiden: skrifter, høydekurver, .tv-stilen og ingen eksterne ressurser", async () => {
  const board = tvBoardPage("ABCDEFGHJK", "n");
  assert.match(board, /<div class="landing tvflate"><svg class="kurver"/);
  assert.match(board, /<div class="tv vegg">/);
  assert.match(board, /<h1 class="ttl"><span class="loud" id="tittel">/);
  assert.match(board, /<span class="soft" id="regel" hidden>/);
  assert.match(board, /<b id="live" hidden>Live<\/b>/);
  assert.match(board, /\.landing \.tv \.bar b::before/, "stilen er den samme som demoTavla på forsiden");
  assert.match(board, /archivo-latin\.woff2/);
  assert.match(board, /newsreader-latin\.woff2/);
  assert.doesNotMatch(board, /<canvas|startTopo/, "høydekurvene står stille");
  const code = tvCodePage("n");
  assert.match(code, /<h1><span class="loud">Atten<\/span> <span class="soft">på TV<\/span><\/h1>/);
  for (const html of [board, code]) assert.doesNotMatch(html, /(src|href)="https?:/);
  const res = await handle(new Request("https://dashdash18.com/tv/ABCDEFGHJK"));
  assert.match(res.headers.get("Content-Security-Policy") ?? "", /script-src 'nonce-/);
});

/** Kjører skriptet på TV-siden med en liten falsk DOM og svaret `payload`. Gir elementene og sidebyttet. */
async function runBoard(payload: unknown, height = 1080) {
  const els = new Map<string, Record<string, unknown>>();
  const el = (id: string) => {
    if (!els.has(id)) els.set(id, { innerHTML: "", textContent: "", hidden: false, clientHeight: height * 0.7, offsetHeight: 30, clientWidth: 1200,
      rows: [], children: [], getBoundingClientRect: () => ({ bottom: height, height: 0 }) });
    return els.get(id)!;
  };
  const timers: (() => void)[] = [];
  const script = /<script nonce="n">([\s\S]*)<\/script>/.exec(tvBoardPage("ABCDEFGHJK", "n"))![1];
  let loaded!: () => void;
  const done = new Promise<void>((r) => { loaded = r; });
  const run = new Function("document", "window", "fetch", "setInterval", "getComputedStyle", script);
  run({ getElementById: el }, { innerHeight: height, addEventListener() {} },
    async () => { setTimeout(loaded, 0); return { status: 200, json: async () => payload }; },
    (f: () => void, ms: number) => { if (ms === 10000) timers.push(f); }, () => ({ fontSize: "36px" }));
  await done;
  return { el, nextPage: () => timers.forEach((f) => f()) };
}

test("TV-siden viser alle radene over sidene, tittelen, regelen og Live når runden går", async () => {
  const tv = buildTVPayload(seasonBoard(0));
  const many = { ...tv, rows: Array.from({ length: 31 }, (_, i) => ({ place: `${i + 1}.`, name: `Spiller ${i + 1}`, total: `${40 - i}`, detail: "3 kvelder" })),
    rounds: null, latest: tv.latest && { ...tv.latest, ongoing: true } };
  const { el, nextPage } = await runBoard(many);
  assert.equal(el("tittel").textContent, "Vår 2026");
  assert.equal(el("regel").textContent, "Jakkeracet");
  assert.equal(el("regel").hidden, false);
  assert.equal(el("live").hidden, false);
  assert.equal(el("played").textContent, "Golfgutu Invitational · 5 av 7 kvelder spilt");
  const pages = (String(el("dots").innerHTML).match(/<i/g) ?? []).length;
  assert.ok(pages > 1);
  const seen = new Set<string>();
  for (let p = 0; p < pages; p++) {
    for (const m of String(el("rows").innerHTML).matchAll(/<span class="n">([^<]*)<\/span>/g)) seen.add(m[1]);
    nextPage();
  }
  assert.deepEqual([...seen].sort(), many.rows.map((r) => r.name).sort());
  assert.match(String(el("latest").innerHTML), /<b>Pågår nå<\/b>/);
});

test("TV-siden: lederen i gull, playoff-merket, ruter per runde og Siste runde uten Live; cup uten ruter og kort", async () => {
  const playoff = fixture.sesonger.findIndex((s: { name: string }) => s.name === "Playoff 2026");
  const tv = buildTVPayload(seasonBoard(playoff));
  const { el } = await runBoard(tv);
  const rows = String(el("rows").innerHTML);
  assert.match(rows, /^<tr class="lead"/);
  assert.match(rows, /<span class="dt"><b>Playoff<\/b> · /);
  assert.match(rows, /<span class="rd"><i>/);
  assert.match(String(el("thead").innerHTML), /<th>Spiller<\/th><th class="rdc">/);
  assert.equal(el("live").hidden, true);
  assert.match(String(el("latest").innerHTML), /<span>Siste runde<\/span>/);
  const cup = await runBoard({ ...tv, kind: "cup", heading: { title: "Klubbcupen", rule: null, progress: "Semifinale" }, rounds: null, latest: null, extras: [], teams: null });
  assert.match(String(cup.el("thead").innerHTML), /<th>Kamp<\/th><th class="r">Vinner<\/th>/);
  assert.equal(cup.el("regel").hidden, true);
  assert.equal(cup.el("siden").hidden, true);
});
