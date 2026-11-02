// Delene av forsiden som også står på dashdash18.com (web/atten-lenker/src/salgsside.ts): tavla på TV-en,
// telefonen med scorekortet, kortene i «Bli kjent»-raden, setningen som tones inn og fotobåndet. Ren HTML som
// tekst, uten React og DOM, så Landing.tsx og workeren bruker samme kilde. Bevegelsen står i live.ts, stilen i
// style.ts. Navn, poeng og koder er oppdiktet (demo.ts), og tavla er merket som eksempel. Uten skript står alt
// ferdig; live.ts setter det i gang.

import { escapeHTML as esc } from "../../../atten-lenker/src/html.ts";
import { DEMO_EVENTS, DEMO_PLAYERS } from "./demo.ts";

/** Et bilde i public/landing. Bredde og høyde er filens, så nettleseren holder av plass. */
export interface Picture { src: string; alt: string; width: number; height: number }

export const FAIRWAY: Picture = { src: "/landing/fairway.jpg", alt: "Klippet fairway med dugg om morgenen", width: 1500, height: 1001 };
export const KVELD: Picture = { src: "/landing/kveld.jpg", alt: "Tre golfere skåler på banen etter runden", width: 1400, height: 934 };
/** Bildene er fra Unsplash (Unsplash-lisensen) og krediteres i bunnen av siden. */
export const PHOTO_CREDIT = "Foto: Sugar Golf og FilterGrade på Unsplash";

const image = (p: Picture) =>
  `<img src="${p.src}" alt="${esc(p.alt)}" width="${p.width}" height="${p.height}" loading="lazy" decoding="async">`;

// ---------- tavla på TV-en ----------

/** Tavla på TV-en med eksempeltabellen. live.ts lar scorene komme inn og tabellen sortere seg på nytt. */
export function demoTavla(): string {
  const rows = DEMO_PLAYERS.map((p, i) =>
    `<tr${i === 0 ? ' class="lead"' : ""} data-navn="${esc(p.name)}" style="animation-delay: ${300 + i * 90}ms">` +
    `<td class="pl">${i + 1}</td>` +
    `<td class="nm">${esc(p.name)}<span class="rd">${p.rounds.map((r, j) => `<i${j === 6 ? ' class="x"' : ""}>${r}</i>`).join("")}</span></td>` +
    `<td class="r pts">${p.points}</td></tr>`).join("");
  return `<div class="screen">
<div class="tv" aria-label="Eksempel på tavla på TV-en" data-hendelser="${esc(JSON.stringify(DEMO_EVENTS))}">
<div class="scr">
<div class="bar"><span>Runde 7 av 10 · eksempel</span><b>Live <span data-klokke>20.14</span></b></div>
<div class="ttl"><span class="loud">Høstserien</span><span class="soft">beste 6 av 10, Stableford</span></div>
<table>
<thead><tr><th></th><th>Spiller</th><th class="r">Poeng</th></tr></thead>
<tbody>${rows}</tbody>
</table>
<div class="toast" aria-live="polite"></div>
</div>
</div>
<div class="stand"></div>
<p class="cap"><em>Tavla på TV-en i klubbhuset.</em> Åpnes med en kode på fire tegn.</p>
</div>`;
}

// ---------- kortene ----------

export interface Phone {
  /** Øverst på skjermen: bane og tee til venstre, hullet til høyre. */
  top: [string, string];
  /** Par, lengde og indeks, og spilleren som føres. */
  hole: string;
  player: string;
  /** Scoren som står; live.ts trykker − og viser én mindre. */
  score: number;
  /** Mer på skjermen under knappene (HTML). */
  extra?: string;
}

/** Telefonen med scorekortet. */
export function phone(p: Phone): string {
  return `<div class="phone" data-telefon><div class="pscr">` +
    `<div class="top"><span>${esc(p.top[0])}</span><span>${esc(p.top[1])}</span></div>` +
    `<div class="hole">${esc(p.hole)}<b>${esc(p.player)}</b></div>` +
    `<div class="score">${p.score}</div>` +
    `<div class="pm"><span>−</span><span class="on">+</span></div>${p.extra ?? ""}</div></div>`;
}

export interface Card {
  /** Den lille linja øverst, overskriften og den kursive fortsettelsen. */
  eyebrow: string;
  title: string;
  em: string;
  /** Det som står nederst i kortet (HTML fra en av `…Art`-funksjonene). */
  art: string;
  look?: "dark" | "img";
  /** Bildet bak et `img`-kort. */
  picture?: Picture;
}

/** Ett kort i raden. Får klassen `in` av live.ts når det er synlig. */
export function card(c: Card): string {
  return `<article class="${["kcard", c.look].filter(Boolean).join(" ")}" data-inview>` +
    (c.picture ? image(c.picture) : "") +
    `<p class="eb">${esc(c.eyebrow)}</p><h3>${esc(c.title)} <em>${esc(c.em)}</em></h3>${c.art}</article>`;
}

export const phoneArt = (p: Phone) => `<div class="art">${phone(p)}</div>`;

/** Lista med navn, handicap og et merke. `wait`: det gule merket (venter), ellers det grønne. */
export function rosterArt(note: string, rows: readonly { name: string; hcp: string; label: string; wait?: boolean }[]): string {
  return `<div class="art"><p class="paste">${esc(note)}</p><div class="plist">` +
    rows.map((r, i) => `<div style="transition-delay: ${250 + i * 220}ms"><span>${esc(r.name)}</span><span class="h">${esc(r.hcp)}</span>` +
      `<em${r.wait ? ' class="inv"' : ""}>${esc(r.label)}</em></div>`).join("") +
    `</div></div>`;
}

/** Banen med par per hull (de ni første). */
export function courseArt(name: string, info: string, par: readonly number[]): string {
  return `<div class="art"><div class="course"><div class="h"><b>${esc(name)}</b><span>${esc(info)}</span></div><div class="holes">` +
    par.map((p, i) => `<i${p === 3 ? ' class="p3"' : p === 5 ? ' class="p5"' : ""} style="transition-delay: ${i * 50}ms">${p}</i>`).join("") +
    `</div></div></div>`;
}

/** Koden på skjermen i lokalet og båsene (de første `busy` er i gang). */
export function simArt(code: string, text: string, busy: number, bays = 6): string {
  return `<div class="art simart"><div class="code">` +
    [...code].map((c, i) => `<span style="transition-delay: ${i * 70}ms">${esc(c)}</span>`).join("") +
    `</div><p>${esc(text)}</p><div class="bays">` +
    Array.from({ length: bays }, (_, i) => (i < busy ? '<i class="on"></i>' : "<i></i>")).join("") +
    `</div></div>`;
}

/** Rader med en fet tekst til venstre og en grå til høyre. */
export function rulesArt(rows: readonly [string, string][]): string {
  return `<div class="art rules">${rows.map(([b, s]) => `<div><b>${esc(b)}</b><span>${esc(s)}</span></div>`).join("")}</div>`;
}

/** Raden med kort og pilene under (pilene vises bare med skript, se `.live` i style.ts). */
export function rail(cards: readonly string[], label: string): string {
  const arrow = (d: string) =>
    `<svg viewBox="0 0 14 14" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="${d}"/></svg>`;
  return `<div class="rail" role="region" aria-label="${esc(label)}" tabindex="0">${cards.join("")}</div>
<div class="wrap paddles">
<button type="button" data-dir="-1" aria-label="Forrige" disabled>${arrow("M9 2 4 7l5 5")}</button>
<button type="button" data-dir="1" aria-label="Neste">${arrow("m5 2 5 5-5 5")}</button>
</div>`;
}

// ---------- setningen og fotoet ----------

export interface ReadingPart { text: string; soft?: boolean }

/** Setningen som leses fram ord for ord mens man scroller. Hvert ord er et `.w`. */
export function readingLine(parts: readonly ReadingPart[]): string {
  const words = (text: string) => text.split(/(\s+)/).map((w) => (!w || /^\s+$/.test(w) ? w : `<span class="w">${esc(w)}</span>`)).join("");
  return `<p class="read">${parts.map((p) => (p.soft ? `<span class="soft">${words(p.text)}</span>` : words(p.text))).join("")}</p>`;
}

/** Fotobåndet: kvelden etter runden, med teksten nederst. Glir litt når man scroller (live.ts). */
export function photoBand(): string {
  return `<div class="photo" data-parallax>${image(KVELD)}
<div class="wrap">
<p class="t">Onsdag, <b>21.47</b>. Siste flight er inne.</p>
<p class="s">Kari vant kvelden med 38 poeng, og alle visste det før de hadde tatt av seg skoene.</p>
</div>
</div>`;
}

// ---------- innholdet for arrangører (admin-forsiden og dashdash18.com/for-klubber) ----------

/** Toppen: samme tekst på admin-forsiden og /for-klubber (Thomas 02.11.2026). `loud` er linjene i versaler. */
export const ARRANGOR_HERO = {
  eyebrow: "Atten Arrangør",
  eyebrowRest: "for klubber og simulatorsentre",
  loud: ["Tabellen", "er ferdig"],
  soft: "før dere er i baren.",
  ingress: "Atten er appen og turneringssystemet for den som arrangerer golf: klubbkvelden, simulatorligaen eller firmaturneringen. Spillerne melder seg på og fører scoren hull for hull på telefonen, regelmotoren regner, og tavla på skjermen oppdaterer seg mens de spiller.",
} as const;

export const ARRANGOR_READING: readonly ReadingPart[] = [
  { text: "Klubbkvelden fortjener bedre enn et regneark som blir ferdig klokka ett om natta. Med Atten fører spillerne selv, regelmotoren regner, og " },
  { text: "tavla står på skjermen", soft: true },
  { text: " før siste putt er holet." },
];
export const ARRANGOR_BY = "Atten Arrangør. Laget for de som sitter igjen med lista.";

export const ARRANGOR_CARDS: readonly string[] = [
  card({
    eyebrow: "Appen", title: "Spillerne fører selv.", em: "Poengene er regnet før neste tee.",
    art: phoneArt({ top: ["Losby · gul", "Hull 7 av 18"], hole: "Par 4 · 352 m · idx 3", player: "Kari", score: 4 }),
  }),
  card({
    eyebrow: "Troppen", title: "Lim inn lista fra regnearket.", em: "Resten ordner seg.",
    art: rosterArt("Har de appen, kobles de. Ellers får de en lenke.", [
      { name: "Kari Moen", hcp: "12,4", label: "Koblet" },
      { name: "Jonas Lie", hcp: "22,7", label: "Lenke sendt", wait: true },
      { name: "Marte Lunde", hcp: "18,0", label: "Koblet" },
      { name: "Jon Berg", hcp: "6,3", label: "Koblet" },
    ]),
  }),
  card({
    eyebrow: "Baner", title: "Fra slope.no,", em: "eller egne baner i simulatoren.", look: "img", picture: FAIRWAY,
    art: courseArt("Losby, gul tee", "Par 72 · slope 128", [4, 5, 3, 4, 4, 3, 5, 4, 4]),
  }),
  card({
    eyebrow: "Simulatorsentre", title: "Ligaen i båsen", em: "får sin egen tavle.", look: "dark",
    art: simArt("K7HQ", "Koden på skjermen i lokalet. Trackman fordeler slagene.", 4),
  }),
  card({
    eyebrow: "Reglene", title: "Regnet likt", em: "i appen, på web og på TV.",
    art: rulesArt([["Spillform", "Stableford"], ["Teller", "Beste 6 av 10"], ["Handicapandel", "95 %"], ["Sidepremier", "Lengste drive, nærmest"]]),
  }),
];
