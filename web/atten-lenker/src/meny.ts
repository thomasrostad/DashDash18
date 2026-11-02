// Toppmenyen på dashdash18.com (src/nettsted.ts) og forsiden på admin.dashdash18.com (web/admin/src/landing/):
// samme lenker og samme stil, ett sted. Filen holdes liten og uten import av sidene, så web-admin kan bruke den.

export const ADMIN_URL = "https://admin.dashdash18.com";

export const GUIDES: readonly { path: string; text: string }[] = [
  { path: "/guide/golfturnering", text: "Arrangere en golfturnering" },
  { path: "/guide/golfliga", text: "Golfliga og cup" },
  { path: "/guide/spillformer", text: "Spillformer i golf" },
];

export interface MenuOptions {
  /** Adressen til siden, for å markere den i menyen. */
  current?: string;
  /** Foran lenkene til nettstedet: tom på dashdash18.com, `SITE` fra web-admin. */
  base?: string;
  /** «Logg inn»: web-admin som standard, eller et anker når innloggingen står på siden. */
  login?: string;
}

function link(href: string, text: string, o: Required<MenuOptions>, cls = "n"): string {
  return `<a class="${cls}" href="${o.base}${href}"${href === o.current ? ' aria-current="page"' : ""}>${text}</a>`;
}

/** `<nav>` med merket, Kalkulator, Guider (en `<details>`, virker uten skript), For klubber og Logg inn. */
export function siteMenu(options: MenuOptions = {}): string {
  const o: Required<MenuOptions> = { current: "", base: "", login: ADMIN_URL, ...options };
  const inGuide = GUIDES.some((g) => g.path === o.current);
  return `<nav class="meny wrap" aria-label="Hovedmeny">
<a class="wordmark" href="${o.base}/"${o.current === "/" ? ' aria-current="page"' : ""}>Atten<i>.</i></a>
${link("/stableford", "Kalkulator", o)}
<details class="guider"><summary class="n${inGuide ? " aktiv" : ""}">Guider</summary>
<div class="panel">${GUIDES.map((g) => link(g.path, g.text, o, "")).join("")}</div>
</details>
${link("/for-klubber", "For klubber", o)}
<a class="n logginn" href="${o.login}"${o.login.startsWith("#") ? "" : ' rel="noopener"'}>Logg inn</a>
</nav>`;
}

// Fargene har reserveverdier, så stilen virker også der --rule og --flate ikke er satt (web-admin).
export const MENU_STYLE = `
  /* toppmenyen: én linje på PC, to på mobil. «Guider» er en <details>, så den virker uten skript. */
  .meny { display: flex; align-items: center; gap: 6px 26px; min-height: 68px; flex-wrap: wrap; padding-top: 10px; padding-bottom: 10px; }
  .meny .wordmark { margin-right: auto; text-decoration: none; color: var(--on-dark); }
  .meny .n { font-size: 15px; color: var(--on-dark-2); text-decoration: none; padding: 8px 0; cursor: pointer; }
  .meny .n:hover, .meny .n[aria-current], .meny .n.aktiv { color: var(--on-dark); }
  .meny .n[aria-current], .meny .n.aktiv { box-shadow: inset 0 -1px 0 var(--gold); }
  .meny .logginn { order: 5; color: var(--on-dark); border: 1px solid rgba(244, 241, 230, .3); border-radius: 999px; padding: 7px 16px; }
  .meny .logginn:hover { border-color: var(--gold); color: var(--on-dark); }
  .guider { position: relative; }
  .guider summary { list-style: none; display: inline-flex; align-items: center; gap: 6px; }
  .guider summary::-webkit-details-marker { display: none; }
  .guider summary::after { content: ""; width: 6px; height: 6px; border: solid currentColor; border-width: 0 1.5px 1.5px 0; transform: translateY(-2px) rotate(45deg); }
  .guider[open] summary::after { transform: translateY(1px) rotate(-135deg); }
  .guider .panel { position: absolute; top: calc(100% + 8px); left: -16px; z-index: 5; min-width: 250px; display: grid; padding: 8px;
    background: #10231B; border: 1px solid var(--rule, rgba(244, 241, 230, .12)); border-radius: 16px; box-shadow: 0 30px 60px -20px rgba(0, 0, 0, .7); }
  .guider .panel a { padding: 10px 12px; border-radius: 10px; text-decoration: none; font-size: 15px; color: var(--on-dark); }
  .guider .panel a:hover, .guider .panel a[aria-current] { background: var(--flate, rgba(244, 241, 230, .035)); color: var(--gold); }
  @media (max-width: 640px) {
    .meny { column-gap: 22px; }
    .meny .wordmark { order: -3; }
    .meny .logginn { order: -2; }
    .meny::before { content: ""; order: -1; flex-basis: 100%; height: 0; }
    .guider .panel { left: -60px; }
  }
`;
