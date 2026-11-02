// Salgssidene på dashdash18.com: forsiden (/) og /for-klubber. Samme deler og samme uttrykk som forsiden på
// admin.dashdash18.com, fra samme kilde: markeringen fra web/admin/src/landing/markup.ts, stilen fra style.ts og
// bevegelsen fra live.ts (inline-skript med nonce). Teksten for Google (h1, ingress, knappene og h2-blokkene) står i
// innholdet som før og plasseres i delene her, så søkeordene og overskriftene er de samme.
//
// Uten skript står alt ferdig: tavla, kortene og setningen er server-rendret. Høydekurvene er SVG-en fra nettsted.ts.

import { startLanding } from "../../admin/src/landing/live.ts";
import { demoTavla, PHOTO_CREDIT, photoBand, rail, readingLine, type ReadingPart } from "../../admin/src/landing/markup.ts";
import { LANDING_STYLE } from "../../admin/src/landing/style.ts";
import { escapeHTML } from "./html.ts";
import { siteMenu } from "./meny.ts";
import { eyebrowHTML, headingText, HERO, siteFooter, splitSections, topoSVG, type SiteFrame } from "./nettsted.ts";

export interface Landing {
  /** Til høyre i toppen: tavla på TV-en (som på admin) eller telefonen med scorekortet (HTML fra markup.ts). */
  art: string;
  /** Den store delen av h1 fordelt på linjer. Sammen (med mellomrom) er de `heading.loud`. */
  lines: readonly string[];
  /** Setningen som tones inn ord for ord, og linja under. */
  reading: readonly ReadingPart[];
  by: string;
  /** «Bli kjent med …»: overskriften og kortene (HTML fra `card` i markup.ts). */
  know: { loud: string; soft: string; cards: readonly string[] };
  /** Hvor mange h2-blokker fra innholdet som står før fotobåndet. Resten kommer etter. */
  photoAfter: number;
  /** Avslutningen på natt-grønt: overskrift, tekst (HTML) og knapper (HTML). */
  close: { loud: string; soft: string; text: string; buttons: string };
}

/**
 * Det som ikke står i style.ts: paletten og grunnstilen fra web/admin/src/styles.css (der satt på :root, her avgrenset
 * til .landing, så menyen og bunnen beholder nettstedets farger), og delene bare dashdash18.com har: knappene i toppen,
 * telefonen i toppen og h2-blokkene med teksten for Google.
 */
export const LANDING_SITE_STYLE = `
  .landing { --bg: #F6F3EA; --card: #FFFFFF; --ink: #16201C; --ink2: #5E655F; --rule: #E7E2D4; --lime: #E3EFDD; --accent: #1C483A; }
  @media (prefers-color-scheme: dark) {
    .landing { --bg: #0E1C17; --card: #15271F; --ink: #EEF1EA; --ink2: #A3B2A9; --rule: #27392F; --lime: rgba(159, 212, 180, .16); --accent: #9FD4B4; }
  }
  .landing .loud { font-family: var(--sans); font-stretch: 62%; font-weight: 800; text-transform: uppercase; line-height: .88; letter-spacing: 0; }
  .landing h2 { font-size: 22px; letter-spacing: -.01em; }
  .landing table { border-collapse: collapse; }
  .landing th, .landing td { text-align: left; vertical-align: top; }
  .landing .kurver { height: 100%; -webkit-mask-image: none; mask-image: none; }
  .landing .close .kurver { opacity: .55; }
  /* på lys flate er gull for svakt: fokus, lenker og punkter i --accent (skoggrønt, lys grønn i mørk modus) */
  .landing .morning, .landing .know, .landing .tekster { --mark: var(--accent); }
  .landing .morning :focus-visible, .landing .know :focus-visible, .landing .tekster :focus-visible { outline-color: var(--mark); }

  /* toppen: knappene der web-admin har innloggingen, og en lengre overskrift */
  .landing .pitch .knapper { margin-top: 30px; }
  /* lange ord (GOLFTURNERINGEN) skal få plass i kolonnen: hver bokstav er under en halv skriftstørrelse bred.
     --tegn er den lengste linja, satt på .pitch. Ellers samme størrelse som på admin. */
  .landing .pitch.tilpass { container-type: inline-size; }
  .landing .pitch.tilpass h1 .loud { font-size: min(clamp(60px, 8.4vw, 128px), 100cqi / (var(--tegn) * .5)); }
  .landing .first .phone { margin: 0 auto; width: min(272px, 64vw); }
  .landing .pscr .mini { margin-top: auto; background: #fff; border-radius: 14px; padding: 10px 12px 4px; }
  .landing .pscr .mini p { font-size: 11px; font-weight: 600; color: #6E6C62; margin-bottom: 4px; }
  .landing .pscr .mini div { display: flex; gap: 8px; padding: 6px 0; border-top: 1px solid #EEE9D6; font-size: 13px; }
  .landing .pscr .mini span { width: 1.2em; color: #6E6C62; }
  .landing .pscr .mini b { flex: 1; font-weight: 600; }
  .landing .pscr .mini em { font-style: normal; font-weight: 700; font-variant-numeric: tabular-nums; }

  /* teksten for Google: hver h2 en rad, overskriften til venstre på PC */
  .landing .tekster { background: var(--bg); color: var(--ink); padding-block: clamp(8px, 2vw, 24px) clamp(56px, 8vw, 104px); }
  .landing .del { display: grid; grid-template-columns: minmax(0, 1fr); gap: 12px 56px; padding-block: clamp(28px, 4vw, 48px); border-top: 1px solid var(--rule); }
  @media (min-width: 900px) { .landing .del { grid-template-columns: minmax(0, 5fr) minmax(0, 7fr); } }
  .landing .del h2 { font-stretch: 75%; font-weight: 700; font-size: clamp(28px, 3vw, 42px); line-height: 1.02; letter-spacing: -.01em; }
  .landing .del .tekst { max-width: 40em; }
  .landing .del p, .landing .del ul, .landing .del ol { margin: 0 0 14px; }
  .landing .del ul { padding-left: 20px; }
  .landing .del li { margin: 0 0 10px; }
  .landing .del li::marker { color: var(--mark); }
  .landing .del strong { font-weight: 650; }
  .landing .del a:not(.knapp) { color: var(--mark); text-decoration-color: currentColor; }
  .landing .del a:not(.knapp):hover { color: var(--ink); }
  .landing ol.steg li::before { color: var(--mark); box-shadow: inset 0 0 0 1px var(--mark); }
  .landing .del .knapp { margin: 8px 12px 0 0; }
  .landing .del .knapp + .knapp { background: transparent; color: var(--ink); box-shadow: inset 0 0 0 1px var(--ink2); }
  .landing .del .knapp + .knapp:hover { box-shadow: inset 0 0 0 1px var(--ink); }
  .landing .del ul.lenker { list-style: none; padding: 0; display: grid; gap: 10px; }
  .landing .del ul.lenker a { display: block; padding: 16px 18px; border-radius: 16px; background: var(--card); color: var(--ink); text-decoration: none; font-weight: 600; }
  .landing .del ul.lenker a:hover { box-shadow: inset 0 0 0 2px var(--gold); color: var(--ink); }
  .landing .del ul.lenker span { display: block; font-weight: 400; font-size: 15px; color: var(--ink2); margin-top: 2px; }

  /* bunnen etter en salgsside: samme bredde som delene over */
  .landing + .bunn .wrap { max-width: 1240px; padding-left: max(22px, env(safe-area-inset-left, 0px)); padding-right: max(22px, env(safe-area-inset-right, 0px)); }

  /* avslutningen: knapper i stedet for e-postraden */
  .landing .close .knapper { margin: 0; }
  .landing .close p a { color: var(--on-dark); }
`;

/** Inline-skriptet: live.ts som tekst, kjørt på `.landing` (siden er server-rendret, skriptet bare setter i gang). */
export const LANDING_SCRIPT = `{ const root = document.querySelector(".landing"); if (root) (${startLanding.toString()})(root); }`;

/** h1 med den store delen på linjer (som på admin) og den gule kursive delen. Teksten er den samme som før. */
function heading(h1: string, frame: SiteFrame, landing: Landing): string {
  if (!frame.heading || headingText(frame.heading) !== h1) return h1;
  const lines = landing.lines.join(" ") === frame.heading.loud ? landing.lines : [frame.heading.loud];
  const loud = lines.map((l) => `<span class="ln"><span>${escapeHTML(l)}</span></span>`).join(" ");
  return `<span class="loud">${loud}</span>${frame.heading.soft ? ` <span class="soft in-2">${escapeHTML(frame.heading.soft)}</span>` : ""}`;
}

function del(s: { heading: string; body: string }): string {
  return `<section class="del">\n${s.heading}\n<div class="tekst">\n${s.body.trim()}\n</div>\n</section>\n`;
}

const tekster = (sections: { heading: string; body: string }[]) =>
  sections.length ? `<div class="tekster"><div class="wrap">\n${sections.map(del).join("")}</div></div>\n` : "";

/** Alt inne i `<body>` for en salgsside. `content` er HTML-en som før: h1, ingress, knapper, så h2-blokkene. */
export function landingBody(content: string, frame: SiteFrame, landing: Landing): string {
  const match = HERO.exec(content);
  const [all, h1, lead, buttons] = match ?? ["", "", undefined, ""];
  const { lead: note, sections } = splitSections(content.slice(all.length));
  const longest = Math.max(...landing.lines.map((l) => l.length));
  return `<div class="landing">
<main class="salg">
<header class="hero">
${topoSVG()}
<div class="pin" aria-hidden="true"><i></i><span>Green 7 · fall 2,1 %</span></div>
<div class="lnav">${siteMenu({ current: frame.path })}</div>
<div class="wrap"><div class="first">
<div class="pitch tilpass" style="--tegn: ${longest}">
${frame.eyebrow ? `<p class="name in-1">${eyebrowHTML(frame.eyebrow)}</p>\n` : ""}<h1>${heading(h1, frame, landing)}</h1>
${lead !== undefined ? `<p class="sub in-3">${lead}</p>\n` : ""}${buttons.trim() ? `<div class="in-4"><div class="knapper">\n${buttons.trim()}\n</div></div>\n` : ""}${note.trim() ? `<div class="new in-4">${note.trim()}</div>\n` : ""}</div>
<div class="in-3">${landing.art}</div>
</div></div>
</header>
<section class="morning"><div class="wrap">
${readingLine(landing.reading)}
<p class="by">${escapeHTML(landing.by)}</p>
</div></section>
<section class="know" id="bli-kjent">
<div class="wrap"><h2><span class="loud">${escapeHTML(landing.know.loud)}</span><span class="soft">${escapeHTML(landing.know.soft)}</span></h2></div>
${rail(landing.know.cards, `${landing.know.loud} ${landing.know.soft}`.replace(/\.$/, ""))}
</section>
${tekster(sections.slice(0, landing.photoAfter))}${photoBand()}
${tekster(sections.slice(landing.photoAfter))}<section class="close" id="ny">
${topoSVG()}
<div class="wrap">
<div><h2><span class="loud">${escapeHTML(landing.close.loud)}</span><span class="soft">${escapeHTML(landing.close.soft)}</span></h2>
<p>${landing.close.text}</p></div>
<div class="knapper">\n${landing.close.buttons}\n</div>
</div>
</section>
</main>
</div>
${siteFooter(PHOTO_CREDIT)}`;
}

/** Stilen i `<head>` for en salgsside: den delte fra web-admin og tillegget over. */
export const LANDING_HEAD_STYLE = LANDING_STYLE + LANDING_SITE_STYLE;
