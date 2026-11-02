// Stableford-kalkulator (/stableford): banehandicap, spillehandicap, slag per hull og stablefordpoeng.
// Regnes på serveren: skjemaet sendes med GET til samme adresse, og svaret står i HTML-en. Ingen skript.
// Handicapregningen er appens WHS-kode (web/golfgutu-core/src/whs.ts, samme som WHS.swift), ikke en kopi.
// Golfreglene er fasit: banehandicap etter regel 6.1 (9 hull: indeksen halveres), slag etter regel 6.2
// (plusshandicap gir slag tilbake på de letteste hullene) og stableford etter golfreglene 21.1b.

import { roundTenth, roundWhole, strokesReceived, whsCourseHandicap } from "../../../golfgutu-core/src/whs.ts";
import { APP_STORE_URL, escapeHTML, SITE } from "../html.ts";
import type { ContentPage } from "../innhold.ts";

/** Stableford (golfreglene 21.1b): netto par gir 2 poeng, ett poeng per slag bedre eller dårligere, aldri under 0. */
export const NET_PAR_POINTS = 2;
/** WHS-anbefalingen for individuelt slagspill og stableford (Appendix C). */
export const DEFAULT_ALLOWANCE = 95;

export interface StablefordInput {
  /** Handicapindeks. Plusshandicap er negativt (+2,1 → −2.1). */
  index: number;
  slope: number;
  courseRating: number;
  par: number;
  /** Handicapandel i prosent (0–100). */
  allowance: number;
  holes: 9 | 18;
}

export interface HoleInput {
  hole: number;
  par: number;
  strokeIndex: number;
  /** Slag på hullet, eller `null` når det ikke er ført. */
  gross: number | null;
}

export interface HoleResult extends HoleInput {
  /** Slag fått på hullet (negativt: gitt tilbake). */
  strokes: number;
  /** Stablefordpoeng, eller `null` uten slag. */
  points: number | null;
}

/** Banehandicap (regel 6.1). På 9 hull: indeksen / 2 × slope / 113 + (CR − par), med 9-hulls CR og par. */
export function courseHandicap(input: StablefordInput): number {
  const index = input.holes === 9 ? input.index / 2 : input.index;
  return whsCourseHandicap(index, input.slope, input.courseRating, input.par);
}

/** Spillehandicap: banehandicap × handicapandel, avrundet til nærmeste hele tall (,5 bort fra null, som WHS-koden). */
export function playingHandicap(courseHcp: number, allowance: number): number {
  return roundWhole((courseHcp * allowance) / 100);
}

/** Stablefordpoeng på ett hull: 2 + par + slag fått − slag, aldri under 0. */
export function stablefordPoints(par: number, strokes: number, gross: number): number {
  return Math.max(0, NET_PAR_POINTS + par + strokes - gross);
}

/** Slag fått på hullet med denne rangeringen (1 = vanskeligst av hullene som spilles). */
export function strokesForRank(playingHcp: number, rank: number, holes: 9 | 18): number {
  return strokesReceived(playingHcp, rank, holes);
}

/**
 * Rangeringen av hullene etter indeks. På 18 hull er rangeringen indeksen. På 9 hull med indekser fra et
 * 18-hullskort (f.eks. 1, 3, 5 …) rangeres de ni hullene, så det vanskeligste blir 1.
 */
export function ranks(holes: readonly HoleInput[], count: 9 | 18): Map<number, number> {
  const out = new Map<number, number>();
  const sorted = [...holes].sort((a, b) => a.strokeIndex - b.strokeIndex);
  const useIndex = count === 18 || holes.every((h) => h.strokeIndex <= 9);
  sorted.forEach((h, i) => out.set(h.hole, useIndex ? h.strokeIndex : i + 1));
  return out;
}

/** Poeng og slag hull for hull. */
export function holeResults(holes: readonly HoleInput[], playingHcp: number, count: 9 | 18): HoleResult[] {
  const rank = ranks(holes, count);
  return holes.map((h) => {
    const strokes = strokesForRank(playingHcp, rank.get(h.hole)!, count);
    return { ...h, strokes, points: h.gross === null ? null : stablefordPoints(h.par, strokes, h.gross) };
  });
}

// MARK: Lesing av skjemaet

interface FieldError {
  field: string;
  message: string;
}

export interface Parsed {
  /** Det som ble skrevet inn, for å fylle skjemaet igjen. */
  raw: Record<string, string>;
  holes: 9 | 18;
  input: StablefordInput | null;
  holeInputs: HoleInput[];
  errors: FieldError[];
  /** Har spørringen noe fra skjemaet? */
  submitted: boolean;
}

/** Tall med komma eller punktum, med eller uten fortegn. */
function decimal(raw: string): number | null {
  const s = raw.replace(/\s/g, "").replace(",", ".");
  if (!/^[+-]?\d+(\.\d+)?$/.test(s)) return null;
  return Number(s);
}

function integer(raw: string): number | null {
  const s = raw.replace(/\s/g, "");
  return /^\d+$/.test(s) ? Number(s) : null;
}

const STEP1_FIELDS = ["indeks", "slope", "cr", "par", "andel"] as const;

export function parseQuery(query: URLSearchParams): Parsed {
  const raw: Record<string, string> = {};
  for (const [k, v] of query) raw[k] = v.slice(0, 20);
  const holes: 9 | 18 = raw.hull === "9" ? 9 : 18;
  const errors: FieldError[] = [];
  const submitted = STEP1_FIELDS.some((f) => f in raw);
  if (!submitted) return { raw, holes, input: null, holeInputs: [], errors, submitted };

  const need = (field: string, name: string): string | null => {
    const v = (raw[field] ?? "").trim();
    if (v === "") errors.push({ field, message: `Fyll inn ${name}.` });
    return v === "" ? null : v;
  };

  let index: number | null = null;
  const indexRaw = need("indeks", "handicapindeks");
  if (indexRaw !== null) {
    const n = decimal(indexRaw);
    // Plusshandicap skrives «+2,1» (og noen skriver «-2,1»); begge betyr −2,1 i regningen.
    const value = n === null ? null : /^\s*[+-]/.test(indexRaw) ? -Math.abs(n) : n;
    if (value === null || value < -10 || value > 54) {
      errors.push({ field: "indeks", message: "Handicapindeks må være et tall fra +10 til 54, for eksempel 18,4. Plusshandicap skrives med +, for eksempel +1,2." });
    } else index = value;
  }

  let slope: number | null = null;
  const slopeRaw = need("slope", "slope");
  if (slopeRaw !== null) {
    const n = integer(slopeRaw);
    if (n === null || n < 55 || n > 155) errors.push({ field: "slope", message: "Slope må være et helt tall fra 55 til 155. Det står på scorekortet for teen du spiller fra." });
    else slope = n;
  }

  let par: number | null = null;
  const parRaw = need("par", "par for banen");
  if (parRaw !== null) {
    const n = integer(parRaw);
    if (n === null || n < 3 * holes || n > 6 * holes) errors.push({ field: "par", message: `Par for ${holes} hull må være et helt tall fra ${3 * holes} til ${6 * holes}.` });
    else par = n;
  }

  let cr: number | null = null;
  const crRaw = need("cr", "course rating");
  if (crRaw !== null) {
    const n = decimal(crRaw);
    if (n === null || n <= 0 || /^\s*[+-]/.test(crRaw)) errors.push({ field: "cr", message: "Course rating må være et tall, for eksempel 71,2." });
    else if (par !== null && Math.abs(n - par) > 20) errors.push({ field: "cr", message: `Course rating ${escapeHTML(crRaw)} er langt fra par ${par}. Er det ${holes === 9 ? "9-hullsverdien" : "verdien for 18 hull"}?` });
    else cr = n;
  }

  let allowance: number | null = DEFAULT_ALLOWANCE;
  const andelRaw = (raw.andel ?? "").replace("%", "").trim();
  if (andelRaw !== "") {
    const n = integer(andelRaw);
    if (n === null || n > 100) {
      errors.push({ field: "andel", message: "Handicapandel må være et helt tall fra 0 til 100 (prosent)." });
      allowance = null;
    } else allowance = n;
  }

  const input = index !== null && slope !== null && cr !== null && par !== null && allowance !== null
    ? { index, slope, courseRating: cr, par, allowance, holes }
    : null;

  // Steg 2: par, indeks og slag per hull. Tomme hull hoppes over.
  const holeInputs: HoleInput[] = [];
  for (let h = 1; h <= holes; h++) {
    const p = (raw[`par${h}`] ?? "").trim();
    const si = (raw[`si${h}`] ?? "").trim();
    const g = (raw[`slag${h}`] ?? "").trim();
    if (p === "" && si === "" && g === "") continue;
    const pn = integer(p), sin = integer(si), gn = integer(g);
    let ok = true;
    if (p === "" || si === "") {
      errors.push({ field: p === "" ? `par${h}` : `si${h}`, message: `Hull ${h}: fyll inn både par og indeks.` });
      ok = false;
    }
    if (p !== "" && (pn === null || pn < 3 || pn > 6)) {
      errors.push({ field: `par${h}`, message: `Hull ${h}: par må være 3, 4, 5 eller 6.` });
      ok = false;
    }
    if (si !== "" && (sin === null || sin < 1 || sin > 18)) {
      errors.push({ field: `si${h}`, message: `Hull ${h}: indeks må være et helt tall fra 1 til 18.` });
      ok = false;
    }
    if (g !== "" && (gn === null || gn < 1 || gn > 20)) {
      errors.push({ field: `slag${h}`, message: `Hull ${h}: slag må være et helt tall fra 1 til 20.` });
      ok = false;
    }
    if (ok) holeInputs.push({ hole: h, par: pn!, strokeIndex: sin!, gross: g === "" ? null : gn });
  }
  const seen = new Map<number, number>();
  for (const h of holeInputs) {
    const other = seen.get(h.strokeIndex);
    if (other !== undefined) errors.push({ field: `si${h.hole}`, message: `Indeks ${h.strokeIndex} står på både hull ${other} og hull ${h.hole}. Hvert hull har sin egen indeks.` });
    else seen.set(h.strokeIndex, h.hole);
  }
  if (holes === 9 && holeInputs.some((h) => h.strokeIndex > 9) && holeInputs.length < 9) {
    errors.push({ field: "si1", message: "På 9 hull med indekser fra et 18-hullskort (over 9) må alle ni hullene ha indeks, så kalkulatoren kan rangere dem." });
  }

  return { raw, holes, input, holeInputs, errors, submitted };
}

// MARK: HTML

/** Tall med norsk desimalkomma og ekte minustegn. */
function num(x: number): string {
  const s = String(x).replace(".", ",");
  return x < 0 ? `−${s.slice(1)}` : s;
}

/** Handicap slik golfere skriver det: plusshandicap med +. */
function hcp(x: number): string {
  return x < 0 ? `+${String(-x).replace(".", ",")}` : String(x).replace(".", ",");
}

function plural(n: number, one: string, many: string): string {
  return `${n} ${Math.abs(n) === 1 ? one : many}`;
}

/** «1–12» eller «7» for et sammenhengende spenn. */
function span(a: number, b: number): string {
  return a === b ? `${a}` : `${a}–${b}`;
}

/** Setningene om hvor mange slag man får, gruppert på sammenhengende indekser. */
export function strokeSummary(playingHcp: number, holes: 9 | 18): string[] {
  if (playingHcp === 0) return ["Du får ingen slag. Netto er det samme som brutto på alle hullene."];
  const groups: { from: number; to: number; strokes: number }[] = [];
  for (let r = 1; r <= holes; r++) {
    const s = strokesForRank(playingHcp, r, holes);
    const last = groups[groups.length - 1];
    if (last && last.strokes === s) last.to = r;
    else groups.push({ from: r, to: r, strokes: s });
  }
  return groups.map((g) => {
    const where = g.from === g.to ? `hullet med indeks ${g.from}` : `hullene med indeks ${span(g.from, g.to)}`;
    if (g.strokes > 0) return `Du får ${plural(g.strokes, "slag", "slag")} på ${where}.`;
    if (g.strokes < 0) return `Du gir ${plural(-g.strokes, "slag", "slag")} tilbake på ${where}.`;
    return `Ingen slag på ${where}.`;
  });
}

function attrs(p: Parsed, field: string): string {
  const value = p.raw[field];
  const invalid = p.errors.some((e) => e.field === field);
  return (value ? ` value="${escapeHTML(value)}"` : "") + (invalid ? ' aria-invalid="true"' : "");
}

function field(p: Parsed, name: string, label: string, hint: string, example: string, mode: "decimal" | "numeric", value?: string): string {
  const v = p.raw[name] === undefined && value !== undefined ? ` value="${value}"` : attrs(p, name);
  return `<div class="felt">
<label for="${name}">${label}</label>
<input id="${name}" name="${name}" type="text" inputmode="${mode}" autocomplete="off" placeholder="${example}" aria-describedby="${name}-hjelp"${v}>
<small id="${name}-hjelp">${hint}</small>
</div>`;
}

function step1Result(input: StablefordInput): string {
  const ch = courseHandicap(input);
  const ph = playingHandicap(ch, input.allowance);
  const idx = input.holes === 9 ? `${num(input.index)} / 2` : num(input.index);
  const raw = (input.holes === 9 ? input.index / 2 : input.index) * (input.slope / 113) + (input.courseRating - input.par);
  const phRaw = (ch * input.allowance) / 100;
  const cells = Array.from({ length: input.holes }, (_, i) => {
    const s = strokesForRank(ph, i + 1, input.holes);
    return `<li><span>Indeks ${i + 1}</span> <strong>${s > 0 ? "+" : s < 0 ? "−" : ""}${Math.abs(s)}</strong></li>`;
  }).join("");
  return `<section class="svar" id="resultat" aria-labelledby="resultat-tittel">
<h2 id="resultat-tittel">Ditt handicap på banen</h2>
<div class="tall">
<p><span>Banehandicap</span> <strong>${hcp(ch)}</strong></p>
<p><span>Spillehandicap (${input.allowance} %)</span> <strong>${hcp(ph)}</strong></p>
</div>
<p class="liten">Banehandicap: ${idx} × ${input.slope} / 113 + (${num(input.courseRating)} − ${input.par}) = ${num(roundTenth(raw))} → ${num(ch)}.<br>
Spillehandicap: ${num(ch)} × ${input.allowance} % = ${num(Math.round(phRaw * 100) / 100)} → ${num(ph)}.</p>
<h3>Slag per hull</h3>
${strokeSummary(ph, input.holes).map((s) => `<p>${s}</p>`).join("\n")}
<ul class="rutenett" aria-label="Slag per hull etter indeks">${cells}</ul>
<p class="liten">Indeksen (SI, hcp) står på scorekortet for hvert hull. 1 er det vanskeligste hullet.${input.holes === 9 ? " På 9 hull er 1 det vanskeligste av de ni hullene du spiller." : ""} Spiller du netto par på alle hullene, får du ${NET_PAR_POINTS * input.holes} poeng.</p>
</section>`;
}

function holeTable(p: Parsed, results: HoleResult[] | null): string {
  const byHole = new Map((results ?? []).map((r) => [r.hole, r]));
  const rows = Array.from({ length: p.holes }, (_, i) => {
    const h = i + 1;
    const r = byHole.get(h);
    const strokes = r ? (r.strokes > 0 ? `+${r.strokes}` : r.strokes < 0 ? `−${-r.strokes}` : "0") : "";
    return `<tr><th scope="row">${h}</th>` +
      `<td><input name="par${h}" type="text" inputmode="numeric" autocomplete="off" aria-label="Par hull ${h}"${attrs(p, `par${h}`)}></td>` +
      `<td><input name="si${h}" type="text" inputmode="numeric" autocomplete="off" aria-label="Indeks hull ${h}"${attrs(p, `si${h}`)}></td>` +
      `<td><input name="slag${h}" type="text" inputmode="numeric" autocomplete="off" aria-label="Slag hull ${h}"${attrs(p, `slag${h}`)}></td>` +
      (results ? `<td>${strokes}</td><td><strong>${r?.points ?? ""}</strong></td>` : "") + `</tr>`;
  }).join("\n");
  let foot = "";
  if (results) {
    const played = results.filter((r) => r.points !== null);
    const total = played.reduce((s, r) => s + r.points!, 0);
    const gross = played.reduce((s, r) => s + r.gross!, 0);
    const par = played.reduce((s, r) => s + r.par, 0);
    foot = `<tfoot><tr><th scope="row">Sum</th><td>${par || ""}</td><td></td><td>${gross || ""}</td><td></td><td><strong>${total}</strong></td></tr></tfoot>`;
  }
  return `<div class="hulltabell"><table>
<thead><tr><th scope="col">Hull</th><th scope="col">Par</th><th scope="col">Indeks</th><th scope="col">Slag</th>${results ? '<th scope="col">Får</th><th scope="col">Poeng</th>' : ""}</tr></thead>
<tbody>
${rows}
</tbody>${foot}
</table></div>`;
}

function pointsResult(results: HoleResult[], holes: 9 | 18): string {
  const played = results.filter((r) => r.points !== null);
  if (played.length === 0) return "";
  const total = played.reduce((s, r) => s + r.points!, 0);
  const vsPar = total - NET_PAR_POINTS * played.length;
  const after = played.length === holes ? `etter ${holes} hull` : `etter ${plural(played.length, "hull", "hull")}`;
  const rel = vsPar === 0 ? "netto par" : vsPar > 0 ? `${vsPar} over netto par` : `${-vsPar} under netto par`;
  return `<p class="sum" id="poeng" role="status"><strong>${plural(total, "poeng", "poeng")}</strong> ${after} (${rel}).</p>`;
}

export function stablefordContent(query: URLSearchParams): string {
  const p = parseQuery(query);
  const results = p.input && p.holeInputs.length > 0 && p.errors.length === 0
    ? holeResults(p.holeInputs, playingHandicap(courseHandicap(p.input), p.input.allowance), p.holes)
    : null;
  const errorBox = p.errors.length
    ? `<div class="feil" role="alert" id="feil"><p><strong>Sjekk dette:</strong></p><ul>${p.errors.map((e) => `<li>${e.field ? `<a href="#${e.field.replace(/\d+$/, "") === e.field ? e.field : "hull"}">${e.message}</a>` : e.message}</li>`).join("")}</ul></div>`
    : "";
  const holeOpen = p.holeInputs.length > 0 || p.errors.some((e) => /\d$/.test(e.field));
  const nine = p.holes === 9;

  return `
<h1>Stableford-kalkulator</h1>
<p>Regn ut spillehandicap, hvor mange slag du får på hvert hull og hvor mange stablefordpoeng runden gir. Etter golfreglene og World Handicap System (WHS). Gratis, uten innlogging.</p>
${errorBox}
<form method="get" action="/stableford#resultat" class="skjema" novalidate>
<h2>Steg 1: spillehandicap og slag per hull</h2>
<fieldset class="hull-valg">
<legend>Antall hull</legend>
<label><input type="radio" name="hull" value="18"${nine ? "" : " checked"}> 18 hull</label>
<label><input type="radio" name="hull" value="9"${nine ? " checked" : ""}> 9 hull</label>
</fieldset>
<div class="felter">
${field(p, "indeks", "Handicapindeks", "Plusshandicap med +, f.eks. +1,2.", "18,4", "decimal")}
${field(p, "slope", "Slope", "Fra scorekortet, for teen din.", "125", "numeric")}
${field(p, "cr", "Course rating (CR)", nine ? "9-hullsverdien." : "Fra scorekortet, for teen din.", nine ? "35,6" : "71,2", "decimal")}
${field(p, "par", "Par for banen", nine ? "For de ni hullene." : "For 18 hull.", nine ? "36" : "72", "numeric")}
${field(p, "andel", "Handicapandel (%)", `${DEFAULT_ALLOWANCE} % er vanlig i stableford.`, String(DEFAULT_ALLOWANCE), "numeric", String(DEFAULT_ALLOWANCE))}
</div>
<button class="knapp" type="submit">Regn ut</button>
${p.input && !p.errors.some((e) => STEP1_FIELDS.includes(e.field as never)) ? step1Result(p.input) : ""}
<details id="hull"${holeOpen ? " open" : ""}>
<summary>Steg 2 (valgfritt): poeng hull for hull</summary>
<p class="liten">Fyll inn par, indeks og slag for hullene du har spilt. Tomme hull hoppes over. Uten slag ser du bare hvor mange slag du får.${nine ? " Står indeksene fra 18-hullskortet (f.eks. 1, 3, 5), rangeres de ni hullene for deg." : ""}</p>
${results ? pointsResult(results, p.holes) : ""}
${holeTable(p, results)}
<button class="knapp" type="submit">Regn ut poeng</button>
</details>
</form>

<a class="knapp" href="${APP_STORE_URL}" rel="noopener">Før scorekortet i Atten</a>
<p class="liten">Atten er gratis for iPhone. Appen regner stablefordpoeng og slag per hull for alle i runden mens dere fører scorekortet hull for hull.</p>

<h2>Slik regnes stablefordpoeng</h2>
<p>I stableford får du poeng på hvert hull etter hvor mange slag du brukte, sammenlignet med par pluss slagene handicapet gir deg på hullet (netto). Netto par gir 2 poeng. Hvert slag bedre gir ett poeng mer, og hvert slag dårligere ett poeng mindre, men aldri under 0.</p>
<ul>
<li>Netto dobbel bogey eller verre, eller hullet ikke fullført: 0 poeng</li>
<li>Netto bogey: 1 poeng</li>
<li>Netto par: 2 poeng</li>
<li>Netto birdie: 3 poeng</li>
<li>Netto eagle: 4 poeng</li>
<li>Netto albatross: 5 poeng</li>
</ul>
<p>Formelen per hull er <strong>poeng = 2 + par + slag du får − slag du brukte</strong>, og aldri mindre enn 0. Den som har flest poeng til sammen, vinner. Fordi et dårlig hull aldri gir minuspoeng, kan du plukke opp ballen når du ikke lenger kan få poeng. Det gjør stableford raskere enn vanlig slagspill. Les mer om stableford og andre spillformer i <a href="/guide/spillformer">guiden til spillformer</a>.</p>

<h2>Banehandicap</h2>
<p>Handicapindeksen din gjelder på en bane av normal vanskelighet. Banehandicapet er hvor mange slag du får på akkurat den banen og teen du spiller fra:</p>
<p><strong>banehandicap = handicapindeks × slope / 113 + (course rating − par)</strong>, avrundet til nærmeste hele tall.</p>
<p>Slope og course rating står på scorekortet for hver tee. Slope 113 er en bane av normal vanskelighet. På 9 hull deles indeksen på to, og du bruker course rating og par for de ni hullene.</p>

<h2>Spillehandicap og handicapandel</h2>
<p>Spillehandicapet er slagene du faktisk får i konkurransen: banehandicapet ganget med handicapandelen, avrundet. I individuell stableford og slagspill anbefaler WHS 95 %. Arrangøren av turneringen bestemmer andelen, så sjekk konkurranseinnbydelsen. Andre spillformer, som bestball og lagspill, har andre anbefalte andeler.</p>

<h2>Hvor mange slag får jeg på hvert hull?</h2>
<p>Slagene fordeles etter hullenes indeks. Med spillehandicap 12 på 18 hull får du ett slag på hullene med indeks 1 til 12. Med 20 får du ett slag på alle hull, og to slag på indeks 1 og 2. Har du plusshandicap, gir du slag tilbake, først på hullet med indeks 18 (det letteste), så 17 og videre.</p>

<h2>Regneeksempel</h2>
<p>Du har handicapindeks 12,4 og spiller fra en tee med slope 125, course rating 71,2 og par 72.</p>
<ul>
<li>Banehandicap: 12,4 × 125 / 113 + (71,2 − 72) = 12,9, avrundet 13.</li>
<li>Spillehandicap med 95 %: 13 × 0,95 = 12,35, avrundet 12.</li>
<li>Du får ett slag på hullene med indeks 1–12, og ingen slag på indeks 13–18.</li>
<li>Et par 4 med indeks 7 der du bruker 5 slag: netto 4, altså netto par og 2 poeng.</li>
<li>Et par 3 med indeks 15 der du bruker 4 slag: ingen slag fått, netto bogey og 1 poeng.</li>
</ul>
<p><a href="/stableford?hull=18&amp;indeks=12%2C4&amp;slope=125&amp;cr=71%2C2&amp;par=72&amp;andel=95#resultat">Se eksempelet i kalkulatoren</a>.</p>

<h2>Stableford i turnering og liga</h2>
<p>Stableford er den vanligste spillformen i klubbturneringer og golfgjenger, fordi alle kan konkurrere uansett handicap. Skal du arrangere, se <a href="/guide/golfturnering">guiden til å arrangere en golfturnering</a>. I Atten fører hver spiller scorekortet på telefonen, appen regner poengene, og tavla oppdateres mens dere spiller.</p>`;
}

export const STABLEFORD_TITLE = "Stableford-kalkulator: poeng og slag per hull – Atten";
export const STABLEFORD_DESCRIPTION =
  "Regn ut spillehandicap, hvor mange slag du får på hvert hull og stablefordpoeng for runden. Etter golfreglene (WHS). Gratis, uten innlogging.";

// Fargene og skriftene er nettstedets (SITE_STYLE i src/nettsted.ts): gull aksent og store tall som tavla på admin.
const STYLE = `
  .dok .skjema h2 { margin: 0 0 18px; }
  .hull-valg { border: 0; padding: 0; margin: 0 0 18px; display: flex; gap: 8px 24px; flex-wrap: wrap; }
  .hull-valg legend { padding: 0; margin: 0 0 6px; font-weight: 600; font-size: 15px; color: var(--on-dark-2); }
  .hull-valg label { display: inline-flex; align-items: center; gap: 10px; min-height: 44px; cursor: pointer; }
  .hull-valg input { width: 20px; height: 20px; margin: 0; accent-color: var(--gold); }
  .felter { display: grid; grid-template-columns: repeat(auto-fit, minmax(160px, 1fr)); gap: 16px; margin: 0 0 22px; }
  .felt label { display: block; font-weight: 600; font-size: 15px; margin: 0 0 6px; }
  .felt small { display: block; font-size: 13px; color: var(--on-dark-2); margin-top: 6px; line-height: 1.4; }
  .skjema input[type="text"] { width: 100%; font: inherit; font-size: 17px; padding: 12px 14px; border-radius: 14px;
    border: 1px solid rgba(244, 241, 230, .18); background: rgba(244, 241, 230, .06); color: var(--on-dark);
    font-variant-numeric: tabular-nums; transition: border-color .2s, background .2s; }
  .skjema input[type="text"]::placeholder { color: rgba(244, 241, 230, .35); }
  .skjema input[type="text"]:focus { border-color: var(--gold); background: rgba(244, 241, 230, .09); outline: 0; }
  .skjema input[type="text"]:focus-visible, .skjema input[type="radio"]:focus-visible, .skjema summary:focus-visible,
    button.knapp:focus-visible { outline: 2px solid var(--gold); outline-offset: 3px; }
  .skjema input[aria-invalid="true"] { border-color: #F2A65A; }
  button.knapp { border: 0; font-family: inherit; cursor: pointer; }
  .feil { border: 1px solid #F2A65A; border-radius: 16px; padding: 14px 18px; margin: 0 0 20px; background: rgba(242, 166, 90, .08); }
  .feil ul { margin: 0; }
  .feil a { color: var(--on-dark); }
  .svar { border: 1px solid rgba(228, 199, 103, .4); border-radius: 18px; padding: clamp(18px, 3vw, 28px); margin: 24px 0;
    background: rgba(228, 199, 103, .05); }
  .dok .svar h2 { margin: 0 0 18px; }
  .svar h3 { font-size: 18px; margin: 20px 0 8px; }
  .tall { display: grid; grid-template-columns: 1fr 1fr; gap: 16px; }
  .tall p { margin: 0 0 12px; }
  .tall span { display: block; font-size: 14px; color: var(--on-dark-2); }
  .tall strong { display: block; font-stretch: 62%; font-weight: 800; font-size: clamp(56px, 9vw, 88px); line-height: .95;
    color: var(--gold); font-variant-numeric: tabular-nums; }
  .dok .rutenett { list-style: none; padding: 0; margin: 8px 0 16px; display: grid; grid-template-columns: repeat(auto-fill, minmax(78px, 1fr)); gap: 6px; }
  .dok .rutenett li { margin: 0; padding: 8px; border-radius: 10px; background: rgba(244, 241, 230, .06); text-align: center; }
  .rutenett span { display: block; font-size: 12px; color: var(--on-dark-2); }
  .rutenett strong { font-size: 19px; color: var(--gold); }
  .skjema details { margin: 8px 0 0; border-top: 1px solid var(--rule); }
  .skjema summary { cursor: pointer; font-weight: 600; font-size: 18px; padding: 18px 0; min-height: 44px; }
  .skjema summary::marker { color: var(--gold); }
  .hulltabell { overflow-x: auto; margin: 0 0 18px; }
  .hulltabell table { width: 100%; border-collapse: collapse; font-size: 15px; font-variant-numeric: tabular-nums; }
  .hulltabell th, .hulltabell td { padding: 4px 3px; text-align: center; border-bottom: 1px solid var(--rule); }
  .hulltabell thead th { color: var(--gold); font-size: 12px; font-weight: 600; text-transform: uppercase; letter-spacing: .05em; }
  .hulltabell tfoot strong, .hulltabell td strong { color: var(--gold); }
  .hulltabell input[type="text"] { min-width: 2.6em; max-width: 4.5em; padding: 8px 4px; text-align: center; border-radius: 10px; }
  .sum { font-size: 19px; margin: 4px 0 18px; }
  .sum strong { display: block; font-stretch: 62%; font-weight: 800; font-size: clamp(56px, 9vw, 88px); line-height: .95; color: var(--gold); }
`;

export const STABLEFORD: ContentPage = {
  path: "/stableford",
  title: STABLEFORD_TITLE,
  description: STABLEFORD_DESCRIPTION,
  lastmod: "2026-11-02",
  linkText: "Stableford-kalkulator",
  eyebrow: "Kalkulator · etter golfreglene og WHS",
  heading: { loud: "Stableford-kalkulator" },
  content: stablefordContent(new URLSearchParams()),
  render: stablefordContent,
  style: STYLE,
  jsonLd: {
    "@context": "https://schema.org",
    "@type": "WebApplication",
    name: "Stableford-kalkulator",
    url: `${SITE}/stableford`,
    description: STABLEFORD_DESCRIPTION,
    applicationCategory: "SportsApplication",
    operatingSystem: "Alle",
    inLanguage: "nb",
    isAccessibleForFree: true,
    offers: { "@type": "Offer", price: "0", priceCurrency: "NOK" },
    publisher: { "@type": "Organization", name: "Atten", url: `${SITE}/` },
  },
};
