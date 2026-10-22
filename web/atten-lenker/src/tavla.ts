// Tavla i nettleseren for tilskuere (sql/056): dashdash18.com/tavla/KODE, lenken arrangøren deler i
// WhatsApp-gruppa med «Del tavla» i appen. Tabellen, «Alle runder» og scorekortene, oppdatert live,
// uten app og uten konto. Samme lesevei og regelmotor som TV-siden (tv_board_data, web/golfgutu-core).

import {
  LeagueStandings, snapshotHandicap, snapshotHasInward, snapshotScorecard, snapshotTotal, tavlaToJSON,
  type RoundsGrid, type RoundSnapshot, type ScoreName,
} from "../../golfgutu-core/src/index.ts";
import { buildTVPayload, leagueStandings, seasonStandings, type TVEnv, type TVPayload } from "./tv.ts";
import { ICON_LINKS, shareMeta } from "./html.ts";

/**
 * App Store-lenken i «Få Atten-appen». null til appen er publisert: da står det «Kommer snart i App Store»
 * uten lenke. Bytt til f.eks. "https://apps.apple.com/no/app/atten/id1234567890".
 */
export const APP_STORE_URL: string | null = "https://apps.apple.com/no/app/atten/id6820031728";

/** Hvor ofte siden henter på nytt (sekunder). Workeren holder svaret like lenge i hurtigbufferen. */
export const REFRESH_SECONDS = 20;

/** Én rute på scorekortet: hullnummer, par, slag, poeng og scorenavnet (fargen). */
export interface ShareHole {
  n: number;
  par: number;
  s: number | null;
  p: number | null;
  k: ScoreName | null;
}

export interface ShareCard {
  /** Spillehandicapet i runden. */
  hcp: number;
  /** Stablefordsummen i runden. */
  total: number;
  holes: ShareHole[];
}

export interface ShareRoundsRow {
  id: string;
  name: string;
  place: string;
  points: (number | null)[];
  strokes: (number | null)[];
  toPar: (number | null)[];
  counted: boolean[] | null;
  pointsTotal: number;
  strokesTotal: number;
  toParTotal: number;
}

export interface ShareRounds {
  columns: { id: string; label: string; date: string | null; title: string; ongoing: boolean }[];
  rows: ShareRoundsRow[];
  bestPoints: (number | null)[];
  bestStrokes: (number | null)[];
}

/** Det tilskuersiden viser. Tabellen og panelene er de samme som på TV-en. */
export interface SharePayload extends Omit<TVPayload, "rows" | "latest"> {
  kind: "season" | "league" | "cup";
  /** Tabellen. `id` er spilleren bak raden (for scorekortene), null i cupen. */
  rows: { id: string | null; place: string; name: string; total: string; detail: string }[];
  /** «Alle runder». null i cupen og før første runde. */
  rounds: ShareRounds | null;
  /** Scorekortene: runde-id → spiller-id → kortet. */
  cards: Record<string, Record<string, ShareCard>>;
}

function roundsJSON(grid: RoundsGrid): ShareRounds | null {
  if (grid.columns.length === 0) return null;
  return {
    columns: grid.columns.map((c) => ({ id: c.roundID, label: c.label, date: c.date, title: c.title, ongoing: c.isOngoing })),
    rows: grid.rows.map((r) => ({
      id: r.playerID, name: r.name, place: r.place, points: r.points, strokes: r.strokes, toPar: r.toPar, counted: r.counted,
      pointsTotal: r.pointsTotal, strokesTotal: r.strokesTotal, toParTotal: r.toParTotal,
    })),
    bestPoints: grid.bestPoints,
    bestStrokes: grid.bestStrokes,
  };
}

/** Scorekortet til hver spiller i hver runde, Ut og Inn i ett, regnet som i appen (`RoundGame.scorecard`). */
export function scorecards(snapshots: readonly RoundSnapshot[]): SharePayload["cards"] {
  const cards: SharePayload["cards"] = {};
  for (const s of snapshots) {
    const sides = snapshotHasInward(s) ? [false, true] : [false];
    const byPlayer: Record<string, ShareCard> = {};
    for (const p of s.players) {
      if (byPlayer[p.memberID]) continue;
      const holes = sides.flatMap((inward) => snapshotScorecard(s, p.memberID, inward).lines)
        .map((l) => ({ n: l.number, par: l.par, s: l.strokes, p: l.points, k: l.scoreName }));
      byPlayer[p.memberID] = { hcp: snapshotHandicap(s, p.memberID), total: snapshotTotal(s, p.memberID), holes };
    }
    cards[s.round.id] = byPlayer;
  }
  return cards;
}

/** Svaret fra tv_board_data → det tilskuersiden viser. Rent, uten nett. */
export function buildSharePayload(board: Record<string, unknown>): SharePayload {
  const tv = buildTVPayload(board);
  const { rows: _rows, latest: _latest, ...head } = tv;
  const comp = board.competition as { season_id?: string | null; kind?: string };
  if (comp.season_id != null) {
    const t = seasonStandings(board);
    const json = tavlaToJSON(t);
    return {
      ...head, kind: "season",
      rows: json.rows.map((r, i) => ({ ...tv.rows[i], id: r.memberID })),
      rounds: roundsJSON(json.rounds),
      cards: scorecards(t.snapshots),
    };
  }
  if (comp.kind === "cup") {
    return { ...head, kind: "cup", rows: tv.rows.map((r) => ({ ...r, id: null })), rounds: null, cards: {} };
  }
  const { league } = leagueStandings(board);
  return {
    ...head, kind: "league",
    rows: league.rows.map((r) => ({
      id: r.entrant.id, place: league.placeText(r), name: r.name, total: LeagueStandings.points(r.total), detail: league.detail(r),
    })),
    rounds: roundsJSON(league.roundGrid()),
    cards: scorecards(league.snapshots),
  };
}

/** Henter med koden. null: ugyldig, utløpt eller tilbaketrukket kode (delingen er slått av). */
export async function fetchSharePayload(code: string, env: TVEnv): Promise<SharePayload | null> {
  if (!env.SUPABASE_URL || !env.SUPABASE_KEY) throw new Error("Workeren mangler SUPABASE_URL eller SUPABASE_KEY.");
  const res = await fetch(`${env.SUPABASE_URL}/rest/v1/rpc/tv_board_data`, {
    method: "POST",
    headers: { apikey: env.SUPABASE_KEY, "Content-Type": "application/json" },
    body: JSON.stringify({ p_code: code }),
  });
  if (!res.ok) {
    const body = (await res.json().catch(() => ({}))) as { code?: string };
    if (body.code === "P0002") return null;
    throw new Error(`tv_board_data svarte ${res.status}`);
  }
  return buildSharePayload((await res.json()) as Record<string, unknown>);
}

// MARK: Siden

// Fargene er appens (DashDash18/DesignSystem/DDPalette.swift), lys og mørk. Skriftene er appens
// (Figtree og Sometype Mono), kuttet til latinske tegn og servert fra /fonts (public/).
const STYLE = `
@font-face { font-family:"Figtree"; src:url("/fonts/Figtree.woff2") format("woff2"); font-weight:300 900; font-display:swap; }
@font-face { font-family:"Sometype Mono"; src:url("/fonts/SometypeMono.woff2") format("woff2"); font-weight:400 700; font-display:swap; }
:root { color-scheme: light dark;
  --bg:#FFF9DF; --card:#FFFFFF; --forest:#1C483A; --ink:#21292B; --ink2:#5F5D53; --ondark:#FFF9DF; --hero2:#CFE0D5;
  --rule:#F0EADB; --border:#ECE4C8; --chip:#F3EDD6; --sel:#1C483A; --selink:#FFF9DF; --you:#FBF1C9; --gold:#E4C767;
  --yellow:#F5C842; --yellowink:#21292B; --yellowtext:#7A5C00; --rust:#A84A10; --forestink:#1C483A;
  --eagle-bg:#EFE3B0; --eagle:#5A4A0E; --birdie-bg:#D9EBD0; --birdie:#21451F; --par-bg:#F3E9DD; --par:#4A4438;
  --bogey-bg:#FCE5DB; --bogey:#8A2F0E; --dobbel-bg:#F7D4C6; --dobbel:#7A2408; --blowup-bg:#EEEBE3; --blowup:#5F5D53;
  --sans:"Figtree",-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;
  --mono:"Sometype Mono",ui-monospace,"SF Mono",Menlo,monospace; }
@media (prefers-color-scheme: dark) { :root {
  --bg:#0C1F18; --card:#17332A; --forest:#123026; --ink:#E8EFE7; --ink2:#A3B5AB; --ondark:#F3F0E2; --hero2:#BFD3C7;
  --rule:#1F3B31; --border:rgba(255,255,255,.08); --chip:#1F3B33; --sel:#A8D8B4; --selink:#0C1F18; --you:rgba(228,199,103,.14);
  --yellowtext:#F5C842; --rust:#F08A4B; --forestink:#A8D8B4;
  --eagle-bg:#4E431A; --eagle:#F2E3A6; --birdie-bg:#284E2A; --birdie:#CFEAC4; --par-bg:#22382F; --par:#D9DCD2;
  --bogey-bg:#4D2A1F; --bogey:#F6C9B5; --dobbel-bg:#5E2618; --dobbel:#FBD3C2; --blowup-bg:#2A2F2C; --blowup:#C9CEC9; } }
* { box-sizing:border-box; }
html { -webkit-text-size-adjust:100%; }
body { margin:0; background:var(--bg); color:var(--ink); font:16px/1.4 var(--sans); }
main { max-width:720px; margin:0 auto; padding:0 16px 40px; }
button { font:inherit; color:inherit; }
.top { display:flex; align-items:center; gap:8px; padding:14px 0 10px; }
.brand { font:700 13px/1 var(--mono); letter-spacing:.12em; text-transform:uppercase; color:var(--forestink); }
.live { margin-left:auto; display:flex; align-items:center; gap:6px; font-size:13px; color:var(--ink2); }
.live i { width:8px; height:8px; border-radius:50%; background:#6BE07A; box-shadow:0 0 0 3px rgba(107,224,122,.25); }
.live.stale i { background:var(--ink2); box-shadow:none; }
.hero { background:var(--forest); color:var(--ondark); border-radius:22px; padding:20px; }
.hero .club { font:600 12px/1.2 var(--mono); letter-spacing:.08em; text-transform:uppercase; color:var(--gold); margin:0 0 6px; overflow-wrap:anywhere; }
.hero h1 { margin:0; font-size:26px; line-height:1.15; font-weight:600; overflow-wrap:anywhere; }
.hero p { margin:6px 0 0; color:var(--hero2); font-size:14px; }
.app { display:flex; align-items:center; gap:12px; margin:12px 0 0; padding:12px 14px; background:var(--card); border:1px solid var(--border); border-radius:18px; }
.app > div { min-width:0; } .app b { display:block; font-weight:600; } .app span { font-size:13px; color:var(--ink2); }
.app a, .app em { margin-left:auto; flex:none; padding:9px 14px; border-radius:999px; background:var(--yellow); color:var(--yellowink);
  font-weight:600; font-size:14px; text-decoration:none; font-style:normal; }
.app em { background:var(--chip); color:var(--ink2); font-weight:500; }
.seg { display:flex; gap:6px; margin:18px 0 10px; padding:4px; background:var(--chip); border-radius:999px; }
.seg button { flex:1; border:0; background:none; padding:9px 0; border-radius:999px; font-weight:500; cursor:pointer; }
.seg button[aria-pressed="true"] { background:var(--sel); color:var(--selink); font-weight:600; }
.card { background:var(--card); border:1px solid var(--border); border-radius:18px; overflow:hidden; }
.row { display:flex; align-items:center; gap:12px; width:100%; padding:12px 14px; border:0; border-top:1px solid var(--rule); background:none; text-align:left; }
.row:first-child { border-top:0; } button.row { cursor:pointer; } button.row:active { background:var(--chip); }
.place { width:28px; flex:none; text-align:right; color:var(--ink2); font-variant-numeric:tabular-nums; }
.who { flex:1; min-width:0; } .who b { display:block; font-weight:600; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }
.who small { display:block; color:var(--ink2); font-size:13px; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }
.total { font-size:20px; font-weight:600; font-variant-numeric:tabular-nums; }
.first .total { color:var(--yellowtext); }
.chev { color:var(--ink2); flex:none; }
.note { margin:10px 2px 0; font-size:13px; color:var(--ink2); }
.label { margin:22px 2px 8px; overflow-wrap:anywhere; font:600 12px/1.2 var(--mono); letter-spacing:.08em; text-transform:uppercase; color:var(--ink2); }
.panel .row { padding:9px 14px; } .panel .total { font-size:16px; }
.modes { display:flex; gap:6px; margin:0 0 10px; }
.modes button { border:0; padding:6px 12px; border-radius:999px; background:var(--chip); font-size:14px; cursor:pointer; }
.modes button[aria-pressed="true"] { background:var(--sel); color:var(--selink); font-weight:600; }
.grid { overflow-x:auto; -webkit-overflow-scrolling:touch; }
table { border-collapse:separate; border-spacing:0; font-variant-numeric:tabular-nums; }
.grid table { min-width:100%; }
.grid th, .grid td { padding:10px 8px; text-align:center; border-top:1px solid var(--rule); white-space:nowrap; font-size:15px; }
.grid thead th { border-top:0; font-size:12px; color:var(--ink2); font-weight:500; line-height:1.2; }
.grid thead th b { display:block; color:var(--ink); font-size:14px; font-weight:600; }
.grid .nm { position:sticky; left:0; background:var(--card); text-align:left; max-width:132px; overflow:hidden; text-overflow:ellipsis;
  font-weight:600; padding-left:14px; box-shadow:1px 0 0 var(--rule); }
.grid .sum { font-weight:700; position:sticky; right:0; background:var(--card); box-shadow:-1px 0 0 var(--rule); }
.grid td.c { cursor:pointer; } .grid td.best { background:var(--you); color:var(--yellowtext); font-weight:700; }
.grid td.out { color:var(--ink2); opacity:.55; text-decoration:line-through; }
.dot { display:inline-block; width:6px; height:6px; border-radius:50%; background:var(--rust); margin-left:3px; vertical-align:middle; }
.msg { text-align:center; padding:60px 8px; } .msg h1 { font-size:24px; margin:0 0 8px; overflow-wrap:break-word; } .msg p { color:var(--ink2); margin:0 0 8px; }
footer { margin:28px 2px 0; font-size:13px; color:var(--ink2); text-align:center; }
footer a { color:var(--forestink); }
dialog { border:0; padding:0; overflow:auto; overscroll-behavior:contain; width:100%; max-width:560px; max-height:88vh; margin:auto auto 0; border-radius:22px 22px 0 0;
  background:var(--bg); color:var(--ink); }
@media (min-width:600px) { dialog { margin:auto; border-radius:22px; } }
dialog::backdrop { background:rgba(12,31,24,.55); }
.sheet { padding:18px 16px 28px; }
.sheet header { display:flex; align-items:flex-start; gap:12px; margin-bottom:12px; } .sheet header > div { min-width:0; }
.sheet h2 { margin:0; font-size:22px; font-weight:600; overflow-wrap:anywhere; } .sheet header p { margin:2px 0 0; color:var(--ink2); font-size:14px; }
.close { margin-left:auto; border:0; background:var(--chip); width:34px; height:34px; border-radius:50%; font-size:18px; cursor:pointer; flex:none; }
.back { border:0; background:none; color:var(--forestink); padding:0 0 10px; font-weight:600; cursor:pointer; }
.sc { width:100%; table-layout:fixed; margin-bottom:12px; }
.sc th, .sc td { padding:6px 0; text-align:center; font-size:14px; }
.sc th { text-align:left; font:600 11px/1 var(--mono); letter-spacing:.06em; text-transform:uppercase; color:var(--ink2); width:46px; }
.sc .hn td { color:var(--ink2); font-size:12px; } .sc .sm { font-weight:700; width:40px; }
.chip { display:inline-block; min-width:26px; padding:3px 0; border-radius:8px; font-weight:600; }
.k-eagle { background:var(--eagle-bg); color:var(--eagle); } .k-birdie { background:var(--birdie-bg); color:var(--birdie); }
.k-par { background:var(--par-bg); color:var(--par); } .k-bogey { background:var(--bogey-bg); color:var(--bogey); }
.k-dobbel { background:var(--dobbel-bg); color:var(--dobbel); } .k-blowup { background:var(--blowup-bg); color:var(--blowup); }
.stats { display:flex; gap:8px; margin:0 0 14px; } .stats div { flex:1; background:var(--card); border:1px solid var(--border); border-radius:14px; padding:10px 12px; }
.stats small { display:block; font:600 11px/1.2 var(--mono); letter-spacing:.06em; text-transform:uppercase; color:var(--ink2); }
.stats b { font-size:22px; font-weight:600; font-variant-numeric:tabular-nums; }
.legend { display:flex; flex-wrap:wrap; gap:6px; font-size:12px; color:var(--ink2); } .legend .chip { font-weight:500; padding:2px 8px; min-width:0; }
`;

function appBanner(): string {
  const action = APP_STORE_URL
    ? `<a href="${APP_STORE_URL}" rel="noopener">Last ned</a>`
    : `<em>Kommer snart</em>`;
  return `<div class="app"><div><b>Få Atten-appen</b><span>Scorekort, tabeller og varsler for gjengen, rett på telefonen.</span></div>${action}</div>`;
}

/** /tavla/KODE: henter /tavla/KODE.json hvert 20. sekund (og når fanen kommer fram igjen). */
export function sharePage(code: string, nonce: string): string {
  const script = `
const url = "/tavla/${code}.json"; let data = null, tab = "tabell", mode = "points", last = 0, gone = false;
const $ = id => document.getElementById(id);
const esc = s => String(s ?? "").replace(/[&<>"']/g, c => ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
const minus = x => x < 0 ? "\\u2212" + (-x) : String(x);
const toPar = x => x === 0 ? "E" : x > 0 ? "+" + x : minus(x);
const time = d => d.toLocaleTimeString("nb-NO", {hour:"2-digit", minute:"2-digit"});
function setLive(){ const el = $("live"); if (!last) return; const old = Date.now() - last > ${REFRESH_SECONDS * 3}000;
  el.className = "live" + (old ? " stale" : ""); el.innerHTML = "<i></i>" + (old ? "Sist oppdatert " : "Live · ") + time(new Date(last)); }
function render(){
  if (!data) return;
  document.title = data.name + " – Atten";
  $("club").textContent = data.club || ""; $("club").hidden = !data.club;
  $("name").textContent = data.name; $("played").textContent = data.played;
  const hasRounds = !!(data.rounds && data.rounds.columns.length);
  $("seg").hidden = !hasRounds; if (!hasRounds) tab = "tabell";
  for (const b of $("seg").children) b.setAttribute("aria-pressed", b.dataset.tab === tab);
  $("tabell").hidden = tab !== "tabell"; $("runder").hidden = tab !== "runder";
  $("rows").innerHTML = data.rows.length ? data.rows.map((r, i) => {
    const can = r.id && hasRounds;
    const tag = can ? 'button type="button" data-player="' + esc(r.id) + '"' : "div";
    return '<' + tag + ' class="row' + (r.place === "1." ? " first" : "") + '"><span class="place">' + esc(r.place) + '</span>'
      + '<span class="who"><b>' + esc(r.name) + '</b>' + (r.detail ? '<small>' + esc(r.detail) + '</small>' : "") + '</span>'
      + '<span class="total">' + esc(r.total) + '</span>' + (can ? '<span class="chev" aria-hidden="true">›</span>' : "") + '</' + (can ? "button" : "div") + '>';
  }).join("") : '<div class="row"><span class="who"><small>Ingen resultater ennå.</small></span></div>';
  $("note").textContent = data.note || ""; $("note").hidden = !data.note;
  const panels = (data.teams ? [data.teams] : []).concat(data.extras || []);
  $("panels").innerHTML = panels.map(p => '<h2 class="label">' + esc(p.title) + '</h2><div class="card panel">'
    + p.lines.map(x => '<div class="row"><span class="who"><b>' + esc(x.name) + '</b></span><span class="total">' + esc(x.score) + '</span></div>').join("") + '</div>').join("");
  if (hasRounds) renderRounds();
  const open = $("sheet").dataset; if ($("sheet").open && open.player) showPlayer(open.player, open.round || null, true);
}
function cell(r, n){
  const v = mode === "points" ? r.points[n] : mode === "strokes" ? r.strokes[n] : r.toPar[n];
  if (v === null || v === undefined) return '<td>–</td>';
  const best = mode === "points" ? data.rounds.bestPoints[n] === v : mode === "strokes" ? data.rounds.bestStrokes[n] === v : false;
  const out = r.counted && !r.counted[n];
  return '<td class="c' + (best ? " best" : "") + (out ? " out" : "") + '" data-player="' + esc(r.id) + '" data-round="' + esc(data.rounds.columns[n].id) + '">'
    + (mode === "topar" ? toPar(v) : v) + '</td>';
}
function renderRounds(){
  const g = data.rounds;
  for (const b of $("modes").children) b.setAttribute("aria-pressed", b.dataset.mode === mode);
  const head = '<tr><th class="nm">Spiller</th>' + g.columns.map(c => '<th><b>' + esc(c.label) + (c.ongoing ? '<span class="dot" title="Pågår"></span>' : "") + '</b>' + esc(c.date || "") + '</th>').join("") + '<th class="sum"><b>Sum</b></th></tr>';
  const body = g.rows.map(r => '<tr><td class="nm">' + esc(r.name) + '</td>' + g.columns.map((_, n) => cell(r, n)).join("")
    + '<td class="sum">' + (mode === "points" ? r.pointsTotal : mode === "strokes" ? r.strokesTotal : toPar(r.toParTotal)) + '</td></tr>').join("");
  $("grid").innerHTML = '<table><thead>' + head + '</thead><tbody>' + body + '</tbody></table>';
  $("gridnote").textContent = g.rows.some(r => r.counted) ? "Gjennomstreket: runden teller ikke (beste runder teller)." : "Gult: beste i runden. Trykk på en rute for scorekortet.";
}
function scorecard(card){
  const rows = [];
  for (let i = 0; i < card.holes.length; i += 9) {
    const h = card.holes.slice(i, i + 9); const side = card.holes.length > 9 ? (i === 0 ? "Ut" : "Inn") : "Sum";
    const sum = f => h.reduce((t, x) => t + (x[f] ?? 0), 0);
    rows.push('<table class="sc"><tr class="hn"><th>Hull</th>' + h.map(x => '<td>' + x.n + '</td>').join("") + '<td class="sm">' + side + '</td></tr>'
      + '<tr><th>Par</th>' + h.map(x => '<td>' + x.par + '</td>').join("") + '<td class="sm">' + sum("par") + '</td></tr>'
      + '<tr><th>Slag</th>' + h.map(x => '<td>' + (x.s === null ? "·" : '<span class="chip k-' + esc(x.k) + '">' + x.s + '</span>') + '</td>').join("") + '<td class="sm">' + sum("s") + '</td></tr>'
      + '<tr><th>Poeng</th>' + h.map(x => '<td>' + (x.p === null ? "" : x.p) + '</td>').join("") + '<td class="sm">' + sum("p") + '</td></tr></table>');
  }
  return rows.join("");
}
const LEGEND = '<div class="legend"><span class="chip k-eagle">Eagle</span><span class="chip k-birdie">Birdie</span><span class="chip k-par">Par</span><span class="chip k-bogey">Bogey</span><span class="chip k-dobbel">Dobbel</span><span class="chip k-blowup">0 poeng</span></div>';
function showPlayer(player, round, keep){
  const g = data.rounds; const r = g && g.rows.find(x => x.id === player);
  const s = $("sheet"); s.dataset.player = player; s.dataset.round = round || "";
  let html;
  if (!r) { html = '<header><div><h2>Fant ikke spilleren</h2></div><button class="close" data-close aria-label="Lukk">×</button></header>'; }
  else if (round) {
    const n = g.columns.findIndex(c => c.id === round); const c = g.columns[n];
    const card = (data.cards[round] || {})[player];
    html = '<button type="button" class="back" data-player="' + esc(player) + '">‹ Alle runder for ' + esc(r.name) + '</button>'
      + '<header><div><h2>' + esc(r.name) + '</h2><p>' + esc(c ? c.title : "") + (c && c.ongoing ? " · pågår" : "") + '</p></div><button class="close" data-close aria-label="Lukk">×</button></header>'
      + (card ? '<div class="stats"><div><small>Poeng</small><b>' + card.total + '</b></div><div><small>Slag</small><b>' + (r.strokes[n] ?? "–") + '</b></div><div><small>Mot par</small><b>' + (r.toPar[n] === null ? "–" : toPar(r.toPar[n])) + '</b></div><div><small>Hcp</small><b>' + card.hcp + '</b></div></div>'
        + scorecard(card) + LEGEND : '<p class="note">Ikke med i denne runden.</p>')
      + (data.note && c && c.ongoing ? '<p class="note">' + esc(data.note) + '</p>' : "");
  } else {
    const t = data.rows.find(x => x.id === player);
    html = '<header><div><h2>' + esc(r.name) + '</h2><p>' + esc(t ? t.place + " · " + t.total + (t.detail ? " · " + t.detail : "") : "") + '</p></div><button class="close" data-close aria-label="Lukk">×</button></header>'
      + '<div class="card">' + g.columns.map((c, n) => r.points[n] === null ? "" : '<button type="button" class="row" data-player="' + esc(player) + '" data-round="' + esc(c.id) + '">'
        + '<span class="who"><b>' + esc(c.title) + (c.ongoing ? '<span class="dot"></span>' : "") + '</b><small>' + (r.strokes[n] ?? "–") + ' slag · ' + (r.toPar[n] === null ? "–" : toPar(r.toPar[n])) + (r.counted && !r.counted[n] ? " · teller ikke" : "") + '</small></span>'
        + '<span class="total">' + r.points[n] + '</span><span class="chev" aria-hidden="true">›</span></button>').reverse().join("") + '</div>';
  }
  $("sheetbody").innerHTML = html;
  if (!s.open) { s.showModal(); if (!keep) history.pushState({sheet:1}, ""); }
}
function closeSheet(){ const s = $("sheet"); if (s.open) { s.close(); s.dataset.player = ""; } }
document.addEventListener("click", e => {
  const t = e.target.closest("[data-tab],[data-mode],[data-player],[data-close]"); if (!t) { if (e.target === $("sheet")) history.back(); return; }
  if (t.dataset.tab) { tab = t.dataset.tab; render(); }
  else if (t.dataset.mode) { mode = t.dataset.mode; renderRounds(); }
  else if (t.dataset.close !== undefined) { history.back(); }
  else if (t.dataset.player) { showPlayer(t.dataset.player, t.dataset.round || null, $("sheet").open); }
});
window.addEventListener("popstate", closeSheet);
$("sheet").addEventListener("cancel", e => { e.preventDefault(); history.back(); });
async function load(){
  if (gone) return;
  try { const r = await fetch(url, {cache:"no-store"});
    if (r.status === 404) { gone = true; closeSheet(); $("main").innerHTML = '<div class="msg"><h1>Lenken virker ikke lenger</h1><p>Arrangøren har slått av delingen av Tavla, eller laget en ny lenke.</p><p>Be om den nye lenken i gruppa.</p></div>'; return; }
    if (!r.ok) throw new Error(r.status);
    data = await r.json(); last = Date.now(); render(); setLive();
  } catch (e) { setLive(); }
}
load(); setInterval(() => { if (!document.hidden) load(); }, ${REFRESH_SECONDS}000); setInterval(setLive, 15000);
document.addEventListener("visibilitychange", () => { if (!document.hidden && Date.now() - last > 5000) load(); });`;

  const body = `<main id="main">
<div class="top"><span class="brand">Atten</span><span class="live" id="live">Henter …</span></div>
<section class="hero"><p class="club" id="club" hidden></p><h1 id="name">Tavla</h1><p id="played">Henter tabellen …</p></section>
${appBanner()}
<div class="seg" id="seg" role="group" aria-label="Visning" hidden><button type="button" data-tab="tabell" aria-pressed="true">Tabell</button><button type="button" data-tab="runder" aria-pressed="false">Alle runder</button></div>
<section id="tabell"><div class="card" id="rows" style="margin-top:12px"></div><p class="note" id="note" hidden></p><div id="panels"></div></section>
<section id="runder" hidden><div class="modes" id="modes" role="group" aria-label="Vis"><button type="button" data-mode="points" aria-pressed="true">Poeng</button><button type="button" data-mode="strokes" aria-pressed="false">Slag</button><button type="button" data-mode="topar" aria-pressed="false">Mot par</button></div>
<div class="card grid" id="grid"></div><p class="note" id="gridnote"></p></section>
<footer>Oppdateres av seg selv mens det føres. Ingen innlogging, e-post eller bilder vises.<br>Laget med <a href="/">Atten</a>.</footer>
</main>
<dialog id="sheet" aria-label="Scorekort"><div class="sheet" id="sheetbody"></div></dialog>`;

  return `<!doctype html><html lang="nb"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<meta name="robots" content="noindex"><meta name="theme-color" content="#1C483A" media="(prefers-color-scheme: light)"><meta name="theme-color" content="#0C1F18" media="(prefers-color-scheme: dark)">
${shareMeta("Tavla i Atten", "Tabellen og scorekortene, live.", `/tavla/${code}`)}
<title>Tavla – Atten</title>${ICON_LINKS}<link rel="preload" href="/fonts/Figtree.woff2" as="font" type="font/woff2" crossorigin><style>${STYLE}</style></head><body>${body}
<script nonce="${nonce}">${script}</script></body></html>`;
}

/** Ugyldig kode i adressen. */
export function shareInvalidPage(): string {
  return `<!doctype html><html lang="nb"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="robots" content="noindex"><title>Tavla – Atten</title>${ICON_LINKS}<style>${STYLE}</style></head><body><main>
<div class="top"><span class="brand">Atten</span></div><div class="msg"><h1>Lenken virker ikke</h1><p>Lenken er ufullstendig eller feil. Be om lenken på nytt i gruppa.</p></div>
${appBanner()}</main></body></html>`;
}
