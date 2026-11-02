// Rammen rundt sidene på nettstedet (forsiden, innholdssidene, personvern, vilkår, support og 404): toppmeny,
// topp med høydekurver, innhold i luftige blokker og bunn med lenkene. Samme uttrykk som forsiden på
// admin.dashdash18.com (web/admin/src/landing/): natt-grønn flate, Archivo smal og fet i versaler, Newsreader
// kursiv i gull. Invitasjonene, Tavla, TV, kalenderen og /captcha bruker ikke rammen.
//
// Alt er server-rendret HTML og CSS. Høydekurvene regnes med den samme koden som tegner dem på web-admin
// (topo.ts, marching squares) og legges inn som SVG, så utseendet trenger ingen skript.

import { contourLevels, contourSegments, fillTopoField, type Segment } from "../../admin/src/landing/topo.ts";
import { APP_STORE_URL, escapeHTML } from "./html.ts";
import { CONTENT_PAGES } from "./innhold.ts";
import { ADMIN_URL, MENU_STYLE, siteMenu } from "./meny.ts";
import { landingBody, type Landing } from "./salgsside.ts";

/** Overskriften i toppen: en stor del i versaler og en gull kursiv del. Sammen er de samme tekst som h1. */
export interface Heading {
  loud: string;
  soft?: string;
}

export interface SiteFrame {
  /** Adressen til siden, for å markere den i menyen. */
  path: string;
  /** Toppen med h1, ingress og knapper hentes fra starten av innholdet. Uten: innholdet vises som ett ark. */
  hero?: boolean;
  /** Den lille linja over overskriften. Det som står før « · », vises i gull. */
  eyebrow?: string;
  heading?: Heading;
  /** Knapper til App Store og arrangør når innholdet ikke har egne knapper i toppen. */
  cta?: boolean;
  /** Salgsside (forsiden og /for-klubber): samme deler som forsiden på admin, se src/salgsside.ts. */
  landing?: Landing;
}

/** Skriftene (public/fonts, kopier fra web/admin/public/fonts). Lastes tidlig, de brukes i overskriften. */
export const SITE_FONTS = [
  '<link rel="preload" href="/fonts/archivo-latin.woff2" as="font" type="font/woff2" crossorigin>',
  '<link rel="preload" href="/fonts/newsreader-latin.woff2" as="font" type="font/woff2" crossorigin>',
].join("\n");

// ---------- høydekurvene ----------

/** Flaten kurvene regnes på (piksler) og greenens topp, som HERO_TOPO på web-admin. */
const TOPO = { W: 1440, H: 760, step: 24, levels: 14, t: 3.1, cx: 0.72, cy: 0.45, r: 0.42 };

/** Setter linjestykkene sammen til lengre linjer, så SVG-en blir kort. */
export function joinSegments(segments: readonly Segment[]): number[][] {
  const key = (x: number, y: number) => `${Math.round(x * 100)},${Math.round(y * 100)}`;
  const at = new Map<string, number[]>();
  segments.forEach(([x1, y1, x2, y2], i) => {
    for (const k of [key(x1, y1), key(x2, y2)]) at.set(k, [...(at.get(k) ?? []), i]);
  });
  const used = new Uint8Array(segments.length);
  const next = (x: number, y: number): [number, number] | null => {
    for (const i of at.get(key(x, y)) ?? []) {
      if (used[i]) continue;
      used[i] = 1;
      const [x1, y1, x2, y2] = segments[i];
      return key(x1, y1) === key(x, y) ? [x2, y2] : [x1, y1];
    }
    return null;
  };
  const lines: number[][] = [];
  segments.forEach(([x1, y1, x2, y2], i) => {
    if (used[i]) return;
    used[i] = 1;
    const line = [x1, y1, x2, y2];
    for (let p = next(x2, y2); p; p = next(p[0], p[1])) line.push(p[0], p[1]);
    for (let p = next(x1, y1); p; p = next(p[0], p[1])) line.unshift(p[0], p[1]);
    lines.push(line);
  });
  return lines;
}

function pathData(lines: number[][]): string {
  return lines.map((l) => {
    const pts: string[] = [];
    for (let i = 0; i < l.length; i += 2) {
      const p = `${Math.round(l[i])} ${Math.round(l[i + 1])}`;
      if (pts[pts.length - 1] !== p) pts.push(p);
    }
    return pts.length > 1 ? `M${pts[0]}L${pts.slice(1).join(" ")}` : "";
  }).join("");
}

let topoCache: string | null = null;

/** Høydekurvene som SVG: tynne gull linjer, hver fjerde sterkere (indekskurver, som på kart). Regnes én gang. */
export function topoSVG(): string {
  if (topoCache) return topoCache;
  const { W, H, step } = TOPO;
  const cols = Math.ceil(W / step) + 1, rows = Math.ceil(H / step) + 1;
  const field = new Float32Array(cols * rows);
  fillTopoField(field, cols, rows, step, W, H, TOPO.t, TOPO);
  const weak: Segment[] = [], strong: Segment[] = [];
  for (const { iso, index } of contourLevels(field, TOPO.levels)) {
    (index ? strong : weak).push(...contourSegments(field, cols, rows, step, iso));
  }
  const path = (segs: Segment[], cls: string) =>
    `<path class="${cls}" d="${pathData(joinSegments(segs))}" vector-effect="non-scaling-stroke"/>`;
  topoCache = `<svg class="kurver" viewBox="0 0 ${W} ${H}" preserveAspectRatio="xMidYMin slice" aria-hidden="true" focusable="false">` +
    path(weak, "svak") + path(strong, "sterk") + "</svg>";
  return topoCache;
}

// ---------- innholdet ----------

/** Toppen av innholdet: `<h1>`, første avsnitt (ingressen) og knappene rett etter. */
export const HERO = /^\s*<h1>([\s\S]*?)<\/h1>\s*(?:<p>([\s\S]*?)<\/p>)?((?:\s*<a class="knapp"[^>]*>[\s\S]*?<\/a>)*)/;

/** Teksten i `heading`, slik den står i h1 (escapet). */
export function headingText(heading: Heading): string {
  return heading.soft ? `${escapeHTML(heading.loud)} ${escapeHTML(heading.soft)}` : escapeHTML(heading.loud);
}

/** Den lille linja over overskriften: det før « · » i gull (`<b>`), resten grått. */
export function eyebrowHTML(text: string): string {
  const [first, ...rest] = text.split(" · ");
  return `<b>${escapeHTML(first)}</b>${rest.length ? ` · ${escapeHTML(rest.join(" · "))}` : ""}`;
}

function hero(content: string, frame: SiteFrame): { hero: string; rest: string } {
  const match = HERO.exec(content);
  if (!match) return { hero: "", rest: content };
  const [all, h1, lead, buttons] = match;
  // Overskriften deles bare når delene gir nøyaktig samme tekst som h1 (samme tekst for Google).
  const heading = frame.heading && headingText(frame.heading) === h1
    ? (frame.heading.soft ? `${escapeHTML(frame.heading.loud)} <span class="soft">${escapeHTML(frame.heading.soft)}</span>` : h1)
    : h1;
  const eyebrow = frame.eyebrow ? `<p class="eyebrow">${eyebrowHTML(frame.eyebrow)}</p>\n` : "";
  const knapper = buttons.trim() ||
    (frame.cta
      ? `<a class="knapp" href="${APP_STORE_URL}" rel="noopener">Last ned Atten fra App Store</a>\n` +
        `<a class="knapp" href="${ADMIN_URL}" rel="noopener">Logg inn som arrangør</a>`
      : "");
  return {
    hero: `<div class="hero">
${eyebrow}<h1>${heading}</h1>
${lead !== undefined ? `<p class="ingress">${lead}</p>\n` : ""}${knapper ? `<div class="knapper">\n${knapper}\n</div>\n` : ""}</div>`,
    rest: content.slice(all.length),
  };
}

/** Deler innholdet ved hver `<h2>` på øverste nivå (ikke inne i skjemaet, tabeller eller lister). */
export function splitSections(html: string): { lead: string; sections: { heading: string; body: string }[] } {
  const tags = /<(\/?)(form|section|details|div|table|ul|ol|aside)\b[^>]*>|<h2\b[^>]*>[\s\S]*?<\/h2>/g;
  const cuts: { start: number; end: number }[] = [];
  let depth = 0;
  for (let m = tags.exec(html); m; m = tags.exec(html)) {
    if (m[2]) depth += m[1] ? -1 : 1;
    else if (depth === 0) cuts.push({ start: m.index, end: m.index + m[0].length });
  }
  const lead = html.slice(0, cuts.length ? cuts[0].start : html.length);
  const sections = cuts.map((c, i) => ({
    heading: html.slice(c.start, c.end),
    body: html.slice(c.end, i + 1 < cuts.length ? cuts[i + 1].start : html.length),
  }));
  return { lead, sections };
}

function blocks(html: string): string {
  const { lead, sections } = splitSections(html);
  return (lead.trim() ? `<div class="blokk enkel">\n${lead.trim()}\n</div>\n` : "") +
    sections.map((s) => `<section class="blokk">\n${s.heading}\n<div class="tekst">\n${s.body.trim()}\n</div>\n</section>\n`).join("");
}

// ---------- meny og bunn ----------

/** Bunnen med lenkene. `credit`: f.eks. hvem som har tatt bildene på siden. */
export const siteFooter = (credit?: string) => `<footer class="bunn">
<div class="wrap kolonner">
<div class="om"><a class="wordmark" href="/">Atten<i>.</i></a>
<p>Golfappen for turnering, liga og golfgjengen. Ingen sporing og ingen cookies.</p>
<a class="knapp" href="${APP_STORE_URL}" rel="noopener">Last ned fra App Store</a></div>
<nav aria-label="Sider"><p class="tittel">Sider</p><ul>${CONTENT_PAGES.map((p) => `<li><a href="${p.path}">${escapeHTML(p.linkText)}</a></li>`).join("")}</ul></nav>
<nav aria-label="Om Atten"><p class="tittel">Om Atten</p><ul><li><a href="/personvern">Personvern</a></li><li><a href="/vilkar">Vilkår</a></li><li><a href="/support">Support</a></li><li><a href="${ADMIN_URL}" rel="noopener">Logg inn som arrangør</a></li></ul></nav>
</div>
<div class="wrap linje"><span>Atten er laget av DashDash18 i Oslo.</span><span>${credit ? `${escapeHTML(credit)} · ` : ""}dashdash18.com</span></div>
</footer>`;

/** Alt inne i `<body>` for en side på nettstedet. `content` er HTML-en som før (med h1 først). */
export function siteBody(content: string, mainClass: string, frame: SiteFrame): string {
  if (frame.landing) return landingBody(content, frame, frame.landing);
  const top = frame.hero ? hero(content, frame) : { hero: "", rest: content };
  const inner = frame.hero
    ? `${top.hero}\n<div class="blokker">\n${blocks(top.rest)}</div>`
    : `<article class="ark">\n${content}\n</article>`;
  return `<div class="side${frame.hero ? "" : " lav"}">
${topoSVG()}
<header class="topp">${siteMenu({ current: frame.path })}</header>
<main class="${mainClass}">
${inner}
</main>
${siteFooter()}
</div>`;
}

// Fargene og typografien er fra web/admin/src/styles.css og landing/style.ts (--night, --gold, --on-dark,
// .loud, .soft, .wordmark). Gull (#E4C767) på natt (#0A1712) har kontrast over 10:1, grågrønn (#9DB0A5) over 7:1.
export const SITE_STYLE = `
  @font-face { font-family: "Archivo"; font-style: normal; font-weight: 400 900; font-stretch: 62% 125%; font-display: swap; src: url("/fonts/archivo-latin.woff2") format("woff2"); }
  @font-face { font-family: "Newsreader"; font-style: italic; font-weight: 400 600; font-display: swap; src: url("/fonts/newsreader-latin.woff2") format("woff2"); }
  :root { color-scheme: dark; --night: #0A1712; --forest: #1C483A; --gold: #E4C767; --gold-hi: #EED486; --on-dark: #F4F1E6;
    --on-dark-2: #9DB0A5; --rule: rgba(244, 241, 230, .12); --flate: rgba(244, 241, 230, .035);
    --sans: "Archivo", -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
    --serif: "Newsreader", Georgia, "Times New Roman", serif; --num: ui-monospace, "SF Mono", Menlo, Consolas, monospace; }
  * { box-sizing: border-box; }
  html { -webkit-text-size-adjust: 100%; }
  body { margin: 0; background: var(--night); color: var(--on-dark); font: 17px/1.6 var(--sans); -webkit-font-smoothing: antialiased; overflow-x: hidden; }
  .side { position: relative; isolation: isolate; min-height: 100vh; display: flex; flex-direction: column; }
  .wrap { width: 100%; max-width: 1180px; margin: 0 auto; padding-left: max(20px, env(safe-area-inset-left, 0px)); padding-right: max(20px, env(safe-area-inset-right, 0px)); }
  .kurver { position: absolute; top: 0; left: 0; width: 100%; height: clamp(600px, 100svh, 900px); z-index: -1; pointer-events: none;
    -webkit-mask-image: linear-gradient(#000 45%, transparent); mask-image: linear-gradient(#000 45%, transparent); }
  .kurver .svak { fill: none; stroke: rgba(228, 199, 103, .19); stroke-width: .8; }
  .kurver .sterk { fill: none; stroke: rgba(228, 199, 103, .42); stroke-width: 1.2; }
  .side::before { content: ""; position: absolute; inset: 0 0 auto; height: clamp(600px, 100svh, 900px); z-index: -1; pointer-events: none;
    background: radial-gradient(120% 90% at 25% 35%, transparent 35%, rgba(10, 23, 18, .8) 100%); }
  .lav .kurver, .lav::before { height: 360px; }
  .lav .kurver { opacity: .6; }
  :focus-visible { outline: 2px solid var(--gold); outline-offset: 3px; border-radius: 4px; }
  a { color: inherit; text-decoration-color: var(--gold); text-decoration-thickness: 1px; text-underline-offset: 3px; }
  a:hover { color: var(--gold-hi); }
  p { margin: 0 0 16px; }
  .soft { font-family: var(--serif); font-style: italic; font-weight: 400; letter-spacing: -.02em; text-transform: none; }
  .wordmark { font-family: var(--sans); font-stretch: 75%; font-weight: 800; font-size: 24px; text-transform: uppercase;
    letter-spacing: -.01em; text-decoration: none; color: var(--on-dark); }
  .wordmark i { font-style: normal; color: var(--gold); }

${MENU_STYLE}
  /* toppen: som forsiden på admin.dashdash18.com */
  .side .hero { padding-block: clamp(36px, 8vw, 104px) clamp(48px, 7vw, 96px); max-width: 1180px; }
  .eyebrow { font-size: 14px; color: var(--on-dark-2); letter-spacing: .02em; margin: 0 0 18px; }
  .eyebrow b { color: var(--gold); font-weight: 600; }
  .side .hero h1 { font-family: var(--sans); font-stretch: 62%; font-weight: 800; text-transform: uppercase; line-height: .9; letter-spacing: 0;
    font-size: clamp(38px, 10.4vw, 108px); margin: 0; max-width: 11em; text-wrap: balance; overflow-wrap: break-word; }
  .side .hero h1 .soft { display: block; color: var(--gold); font-size: .62em; line-height: 1.04; margin-top: .14em; }
  .ingress { font-size: clamp(17px, 1.5vw, 20px); color: var(--on-dark-2); max-width: 36em; margin: 26px 0 0; }
  .knapper { display: flex; flex-wrap: wrap; gap: 12px; margin-top: 30px; }
  .knapp { display: inline-flex; align-items: center; justify-content: center; min-height: 48px; padding: 12px 24px; border-radius: 999px;
    background: var(--gold); color: #16201C; font-weight: 600; font-size: 16px; line-height: 1.2; text-decoration: none; transition: background .2s; }
  .knapp:hover { background: var(--gold-hi); color: #16201C; }
  .knapper .knapp + .knapp, .ark .knapp + .knapp { background: transparent; color: var(--on-dark); box-shadow: inset 0 0 0 1px rgba(244, 241, 230, .35); }
  .knapper .knapp + .knapp:hover { box-shadow: inset 0 0 0 1px var(--gold); color: var(--on-dark); }

  /* innholdet: hver h2 er en blokk med tynn kant, overskriften til venstre på PC */
  main { flex: 1; }
  .blokker { display: grid; gap: 20px; padding-bottom: clamp(48px, 8vw, 96px); }
  .blokker, .side .hero { width: 100%; margin: 0 auto; padding-left: max(20px, env(safe-area-inset-left, 0px)); padding-right: max(20px, env(safe-area-inset-right, 0px)); }
  .blokker { max-width: 1180px; }
  .blokk { background: var(--flate); border: 1px solid var(--rule); border-radius: 22px; padding: clamp(22px, 4vw, 44px); min-width: 0; }
  .blokk:not(.enkel) { display: grid; grid-template-columns: minmax(0, 1fr); gap: 4px 56px; }
  @media (min-width: 900px) {
    .blokk:not(.enkel) { grid-template-columns: minmax(0, 4fr) minmax(0, 8fr); }
    .blokk:not(.enkel) > h2 { position: sticky; top: 24px; align-self: start; }
    /* brede tabeller får hele bredden, med overskriften over */
    .blokk:not(.enkel):has(> .tekst > .tabell) { grid-template-columns: minmax(0, 1fr); }
    .blokk:has(> .tekst > .tabell) > h2 { position: static; }
  }
  .dok h2 { font-family: var(--sans); font-stretch: 75%; font-weight: 700; font-size: clamp(25px, 2.6vw, 32px); line-height: 1.06;
    letter-spacing: -.01em; margin: 0 0 14px; text-wrap: balance; }
  .dok h3 { font-size: 18px; margin: 24px 0 8px; }
  .tekst { min-width: 0; }
  .tekst > :last-child, .blokk > :last-child { margin-bottom: 0; }
  .dok ul, .dok ol { margin: 0 0 16px; padding-left: 22px; }
  .dok li { margin: 0 0 8px; }
  .dok li::marker { color: var(--gold); }
  .dok strong { font-weight: 650; }
  .dok code { font: .9em var(--num); }
  ol.steg { list-style: none; padding: 0; counter-reset: steg; }
  ol.steg li { counter-increment: steg; position: relative; padding-left: 46px; min-height: 32px; margin-bottom: 14px; }
  ol.steg li::before { content: counter(steg); position: absolute; left: 0; top: -2px; width: 32px; height: 32px; border-radius: 50%;
    display: grid; place-items: center; font-weight: 700; font-size: 15px; color: var(--gold); box-shadow: inset 0 0 0 1px rgba(228, 199, 103, .55); }
  .liten { font-size: 15px; color: var(--on-dark-2); }
  .tekst .knapp, .enkel > .knapp, .ark .knapp { margin: 8px 12px 16px 0; }
  .tabell { overflow-x: auto; -webkit-overflow-scrolling: touch; margin: 0 0 16px; border: 1px solid var(--rule); border-radius: 14px; }
  .tabell table { border-collapse: collapse; min-width: 560px; width: 100%; font-size: 15px; line-height: 1.45; }
  .tabell th, .tabell td { text-align: left; vertical-align: top; padding: 10px 14px; border-bottom: 1px solid var(--rule); }
  .tabell tr:last-child td { border-bottom: 0; }
  .tabell th { color: var(--gold); font-weight: 600; font-size: 13px; text-transform: uppercase; letter-spacing: .05em; background: var(--flate); }

  /* personvern, vilkår, support og 404: ett ark med lang tekst */
  .ark { max-width: 760px; margin: clamp(24px, 6vw, 72px) auto clamp(48px, 8vw, 96px); padding: clamp(24px, 5vw, 52px);
    width: calc(100% - 40px); background: var(--flate); border: 1px solid var(--rule); border-radius: 22px; }
  .ark h1 { font-family: var(--sans); font-stretch: 62%; font-weight: 800; text-transform: uppercase; line-height: .95;
    font-size: clamp(30px, 7.6vw, 60px); margin: 0 0 20px; overflow-wrap: break-word; hyphens: auto; text-wrap: balance; }
  .ark h2 { margin-top: 36px; }

  /* bunnen */
  .bunn { border-top: 1px solid var(--rule); color: var(--on-dark-2); font-size: 15px; }
  .bunn .kolonner { display: grid; grid-template-columns: minmax(0, 1.4fr) minmax(0, 1fr) minmax(0, 1fr); gap: 32px; padding-top: 48px; padding-bottom: 32px; }
  .bunn .om p { margin: 12px 0 18px; max-width: 26em; }
  .bunn .tittel { color: var(--on-dark); font-weight: 600; margin: 4px 0 12px; }
  .bunn ul { list-style: none; margin: 0; padding: 0; }
  .bunn li { margin: 0 0 8px; }
  .bunn nav a { text-decoration: none; }
  .bunn nav a:hover { color: var(--on-dark); }
  .bunn .linje { display: flex; justify-content: space-between; gap: 16px; flex-wrap: wrap; font-size: 12px; padding-top: 18px; padding-bottom: 32px;
    border-top: 1px solid rgba(244, 241, 230, .08); }
  @media (max-width: 760px) { .bunn .kolonner { grid-template-columns: 1fr 1fr; } .bunn .om { grid-column: 1 / -1; } }
`;
