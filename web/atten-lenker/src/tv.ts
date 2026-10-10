// TV-visning med kode (fase 26, sql/041): dashdash18.com/tv/KODE på en skjerm uten appen.
// Workeren henter rådataene med tv_board_data(kode) og regner tabellen med regelmotoren i
// TypeScript (web/golfgutu-core), med samme tall og tekster som Tavla i appen.

import {
  CompetitionScope, CupStandings, decodeCompetitionMatch, decodeCompetitionParticipant, decodeCompetitionRound,
  decodeCompetitionRow, decodeProfile, decodeRoundParticipant, decodeTavlaData, LeagueStandings, makeSnapshot,
  PersonDirectory, standingsFromTavlaData, type RoundsGrid, type UUID,
} from "../../golfgutu-core/src/index.ts";

export interface TVEnv {
  SUPABASE_URL?: string;
  SUPABASE_KEY?: string;
}

/** Det TV-siden viser: navn, tabell og siste runde. */
export interface TVPayload {
  name: string;
  club: string | null;
  played: string;
  rows: { place: string; name: string; total: string; detail: string }[];
  latest: { title: string; ongoing: boolean; lines: { name: string; points: number }[] } | null;
}

/** Koden slik serveren lagrer den: 10 tegn, store bokstaver, uten mellomrom. */
export function normalizeTVCode(raw: string): string | null {
  const code = decodeURIComponent(raw).replace(/[\s-]/g, "").toUpperCase();
  return /^[A-HJ-NP-Z2-9]{10}$/.test(code) ? code : null;
}

/** Svaret fra tv_board_data → det TV-en viser. Rent, uten nett (testes med fixturen fra golfgutu-core). */
export function buildTVPayload(board: Record<string, unknown>): TVPayload {
  if ((board.competition as { season_id?: string | null }).season_id == null) return competitionPayload(board);
  const comp = board.competition as {
    name: string; season_id: string; club_id: string; status: string; rules: Record<string, unknown>; club_name?: string | null;
  };
  const season = { id: comp.season_id, club_id: comp.club_id, name: comp.name, status: comp.status, rules: comp.rules };
  const t = standingsFromTavlaData(board, season);
  const playingDay = (comp.rules as { dayTerm?: string })?.dayTerm === "playingDay";
  const total = t.eveningsTotal;
  const unit = playingDay ? (total === 1 ? "spilledag" : "spilledager") : (total === 1 ? "kveld" : "kvelder");
  return {
    name: t.countsStableford ? t.seasonName : `Jakkeracet · ${t.seasonName}`,
    club: comp.club_name ?? null,
    played: `${t.eveningsPlayed} av ${total} ${unit} spilt`,
    rows: t.rows.map((r) => ({ place: r.placeText, name: r.name, total: r.totalText, detail: r.detail })),
    latest: latestRound(t.rounds),
  };
}

/** Siste kolonne i rundeoversikten: de åtte beste i runden. */
function latestRound(grid: RoundsGrid): TVPayload["latest"] {
  const n = grid.columns.length - 1;
  if (n < 0) return null;
  return {
    title: grid.columns[n].title,
    ongoing: grid.columns[n].isOngoing,
    lines: grid.rows
      .filter((r) => r.points[n] !== null)
      .map((r) => ({ name: r.name, points: r.points[n] as number }))
      .sort((a, b) => b.points - a.points || a.name.localeCompare(b.name, "no"))
      .slice(0, 8),
  };
}

const list = (board: Record<string, unknown>, key: string): unknown[] => (Array.isArray(board[key]) ? (board[key] as unknown[]) : []);

/** Liga, morro og cup (sql/043, tv_competition_data): samme mapping som turneringssiden i appen. */
function competitionPayload(board: Record<string, unknown>): TVPayload {
  const raw = board.competition as Record<string, unknown> & { club_name?: string | null };
  const comp = decodeCompetitionRow(raw);
  const club = raw.club_name ?? null;
  const participants = list(board, "participants").map((x) => decodeCompetitionParticipant(x));
  const profiles = list(board, "profiles").map((x) => decodeProfile(x));
  const roundParticipants = list(board, "round_participants").map((x) => decodeRoundParticipant(x));
  const data = decodeTavlaData({ ...board, events: [] });
  const directory = new PersonDirectory(data.members, roundParticipants, profiles);

  if (comp.kind === "cup") {
    const names = new Map<UUID, string>();
    for (const p of participants) {
      const n = p.memberID !== null ? directory.members.get(p.memberID)?.displayName : p.profileID !== null ? directory.profiles.get(p.profileID)?.displayName : null;
      names.set(p.id, n ?? "Ukjent");
    }
    const cup = new CupStandings(list(board, "cup_matches").map((x) => decodeCompetitionMatch(x)), names);
    const i = cup.rounds.findIndex((r) => r.some((g) => g.winner === null && !g.isBye));
    const at = i < 0 ? cup.rounds.length - 1 : i;
    const games = at < 0 ? [] : cup.rounds[at].filter((g) => !g.isBye);
    return {
      name: comp.name,
      club,
      played: cup.champion !== null ? `Vinner: ${cup.champion.name}` : at < 0 ? "Ikke trukket ennå" : cup.roundTitles[at],
      rows: games.map((g) => ({
        place: "",
        name: `${g.a?.name ?? "?"} – ${g.b?.name ?? "?"}`,
        total: g.winner === null ? "" : (g.winner === g.a?.participantID ? g.a?.name : g.b?.name) ?? "",
        detail: g.walkover ? "W.O." : g.result ?? "",
      })),
      latest: null,
    };
  }

  // Navn fra troppen i runden (klubbrunde) eller deltakerne (løs runde), dato fra kvelden/spilledagen.
  const names = new Map<UUID, Map<UUID, string>>();
  for (const x of list(board, "roster")) {
    const r = x as { round_id: string; player_id: string; display_name: string | null };
    const m = names.get(r.round_id.toLowerCase()) ?? new Map<UUID, string>();
    if (r.display_name !== null) m.set(r.player_id.toLowerCase(), r.display_name);
    names.set(r.round_id.toLowerCase(), m);
  }
  const dates = new Map<UUID, string | null>();
  for (const x of list(board, "rounds")) {
    const r = x as { id: string; event_date?: string | null };
    dates.set(r.id.toLowerCase(), r.event_date ?? null);
  }
  const snapshots = data.rounds.map((round) => makeSnapshot(round, {
    roundHoles: data.roundHoles.filter((h) => h.roundID === round.id),
    players: data.players.filter((p) => p.roundID === round.id),
    matches: data.matches.filter((m) => m.roundID === round.id),
    scores: data.scores.filter((s) => s.roundID === round.id),
    sideClaims: data.claims.filter((c) => c.roundID === round.id),
    course: data.courses.find((c) => c.id === round.courseID) ?? null,
    courseHoles: data.courseHoles.filter((h) => h.courseID === round.courseID),
    eventDate: dates.get(round.id) ?? null,
    rules: comp.rules,
    names: names.get(round.id) ?? new Map(),
  }));
  const links = list(board, "links").map((x) => decodeCompetitionRound(x));
  const input = new CompetitionScope(comp, links, participants).input(snapshots, directory);
  const l = new LeagueStandings(input);
  return {
    name: comp.name,
    club,
    played: `${l.roundCount} ${l.roundCount === 1 ? "runde" : "runder"} spilt · ${l.rulesSummary}`,
    rows: l.rows.map((r) => ({ place: l.placeText(r), name: r.name, total: LeagueStandings.points(r.total), detail: l.detail(r) })),
    latest: latestRound(l.roundGrid()),
  };
}

/** Henter med koden. null: ugyldig, utløpt eller tilbaketrukket kode (P0002). */
export async function fetchTVPayload(code: string, env: TVEnv): Promise<TVPayload | null> {
  if (!env.SUPABASE_URL || !env.SUPABASE_KEY) throw new Error("Workeren mangler SUPABASE_URL eller SUPABASE_KEY.");
  const res = await fetch(`${env.SUPABASE_URL}/rest/v1/rpc/tv_board_data`, {
    method: "POST",
    headers: { apikey: env.SUPABASE_KEY, "Content-Type": "application/json" },
    body: JSON.stringify({ p_code: code }),
  });
  if (!res.ok) {
    // PostgREST svarer 500 (eller 400/404) med koden P0002 når koden er ukjent, utløpt eller trukket tilbake.
    const body = (await res.json().catch(() => ({}))) as { code?: string };
    if (body.code === "P0002") return null;
    throw new Error(`tv_board_data svarte ${res.status}`);
  }
  return buildTVPayload((await res.json()) as Record<string, unknown>);
}

const STYLE = `
  :root { color-scheme: dark; --bg:#0B1F18; --ink:#FFF9DF; --dim:rgba(255,249,223,.6); --gold:#E4C767; --panel:rgba(255,249,223,.06); }
  * { box-sizing: border-box; } html, body { margin:0; height:100%; background:var(--bg); color:var(--ink);
    font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif; overflow:hidden; }
  main { height:100%; padding:3vh 4vw; display:flex; flex-direction:column; gap:2vh; font-size:clamp(14px,1.6vw,40px); }
  header { display:flex; align-items:baseline; gap:2vw; } h1 { margin:0; font-size:2.2em; font-weight:600; }
  .dim { color:var(--dim); } .clock { margin-left:auto; font-size:1.9em; font-weight:300; font-variant-numeric:tabular-nums; }
  .body { flex:1; display:flex; gap:3vw; min-height:0; } .table { flex:1; display:flex; flex-direction:column; min-height:0; }
  .row { display:flex; align-items:center; gap:1.2em; padding:.45em 0; border-bottom:1px solid rgba(255,249,223,.08); }
  .place { width:2.6em; text-align:right; color:var(--dim); font-variant-numeric:tabular-nums; }
  .name { font-size:1.35em; flex:1; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
  .top .name { font-weight:600; } .detail { color:var(--dim); font-size:.8em; white-space:nowrap; }
  .total { font-size:1.45em; font-weight:600; min-width:3em; text-align:right; font-variant-numeric:tabular-nums; }
  .first .total { color:var(--gold); } .dots { text-align:center; margin-top:1vh; } .dots span { opacity:.25; } .dots span.on { opacity:.9; }
  aside { width:30vw; background:var(--panel); border-radius:1.2em; padding:1.4em; align-self:flex-start; }
  aside h2 { margin:0 0 .3em; font-size:.9em; text-transform:uppercase; letter-spacing:.08em; color:var(--dim); }
  aside h2.live { color:var(--gold); } aside .line { display:flex; gap:.6em; padding:.25em 0; font-size:1.1em; }
  aside .line b { margin-left:auto; } .msg { margin:auto; text-align:center; max-width:40em; }
  form { display:flex; gap:1em; justify-content:center; margin-top:2em; } input { font:inherit; font-size:1.6em; padding:.4em .6em; width:9em;
    text-transform:uppercase; letter-spacing:.15em; border-radius:.4em; border:0; } button { font:inherit; font-size:1.3em; padding:.4em 1em;
    border-radius:999px; border:0; background:var(--gold); color:#21292B; font-weight:600; }
  @media (orientation: portrait) { .body { flex-direction:column; } aside { width:100%; } .detail { display:none; } }
`;

function shell(title: string, body: string, nonce: string, script: string): string {
  return `<!doctype html><html lang="nb"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="robots" content="noindex"><title>${title}</title><style>${STYLE}</style></head><body>${body}
<script nonce="${nonce}">${script}</script></body></html>`;
}

/** /tv: skriv inn koden (for en TV-nettleser uten tastatur er QR-lenken raskest). */
export function tvCodePage(nonce: string): string {
  return shell("Atten · TV", `<main><div class="msg"><h1>Atten på TV</h1>
<p class="dim">Skriv koden fra appen (Tavla → TV-visning → TV-kode).</p>
<form id="f"><input id="k" maxlength="11" autocomplete="off" autofocus placeholder="ABCDE FGHJK"><button>Vis</button></form></div></main>`,
    nonce, `document.getElementById("f").addEventListener("submit",e=>{e.preventDefault();
const k=document.getElementById("k").value.replace(/[\\s-]/g,"").toUpperCase(); if(k) location.href="/tv/"+encodeURIComponent(k);});`);
}

/** /tv/KODE: henter /tv/KODE.json hvert 15. sekund, bytter side hvert 10. sekund. */
export function tvBoardPage(code: string, nonce: string): string {
  const script = `
const url = "/tv/${code}.json"; let data = null, page = 0, fails = 0;
const esc = s => String(s).replace(/[&<>"]/g, c => ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;"}[c]));
const $ = id => document.getElementById(id);
function clock(){ $("clock").textContent = new Date().toLocaleTimeString("nb-NO",{hour:"2-digit",minute:"2-digit"}); }
function render(){
  if(!data) return;
  $("name").textContent = data.name; $("played").textContent = (data.club ? data.club + " · " : "") + data.played;
  const rowH = window.innerHeight * 0.075, avail = window.innerHeight * 0.72;
  const per = Math.max(3, Math.floor(avail / rowH)); const pages = Math.max(1, Math.ceil(data.rows.length / per));
  page = page % pages; const rows = data.rows.slice(page*per, page*per+per);
  $("rows").innerHTML = rows.map((r,i) => '<div class="row'+(r.place.startsWith("1.")?" first":"")+(page===0&&i<3?" top":"")+'">'
    + '<span class="place">'+esc(r.place)+'</span><span class="name">'+esc(r.name)+'</span><span class="detail">'+esc(r.detail)+'</span><span class="total">'+esc(r.total)+'</span></div>').join("");
  $("dots").innerHTML = pages > 1 ? Array.from({length:pages},(_,i)=>'<span class="'+(i===page?"on":"")+'">●</span>').join(" ") : "";
  const l = data.latest;
  $("latest").innerHTML = l ? '<h2 class="'+(l.ongoing?"live":"")+'">'+(l.ongoing?"Pågår nå":"Siste runde")+'</h2><div class="dim">'+esc(l.title)+'</div>'
    + l.lines.map((x,i)=>'<div class="line"><span class="dim">'+(i+1)+'.</span><span>'+esc(x.name)+'</span><b>'+x.points+'</b></div>').join("") : "";
  $("latest").style.display = l ? "" : "none";
}
async function load(){
  try { const r = await fetch(url, {cache:"no-store"});
    if (r.status === 404) { $("main").innerHTML = '<div class="msg"><h1>Fant ingen TV-visning</h1><p class="dim">Koden er feil, utløpt eller trukket tilbake. Lag en ny kode i appen.</p></div>'; return; }
    data = await r.json(); fails = 0; render();
  } catch(e) { fails++; }
}
clock(); setInterval(clock, 15000); load(); setInterval(load, 15000); setInterval(()=>{ page++; render(); }, 10000);
window.addEventListener("resize", render);`;
  return shell("Atten · TV", `<main id="main"><header><div><h1 id="name">Atten</h1><div class="dim" id="played">Henter tabellen …</div></div>
<div class="clock" id="clock"></div></header><div class="body"><div class="table"><div id="rows"></div><div class="dots" id="dots"></div></div>
<aside id="latest" style="display:none"></aside></div></main>`, nonce, script);
}
