// Personvern, vilkår og support på dashdash18.com (Apple krever dem for App Store).
// Tekstene kommer fra docs/personvern.md og docs/vilkar.md via `npm run juridisk` (src/juridisk-tekst.ts).
import { escapeHTML } from "./html.ts";
import { PERSONVERN_MD, VILKAR_MD } from "./juridisk-tekst.ts";

export const CONTACT_EMAIL = "personvern@dashdash18.com";

/// Lenker i teksten må peke hit: egne sider, https eller e-post. Alt annet vises som ren tekst.
function safeHref(url: string): string | null {
  return /^(https:\/\/|mailto:|\/(?!\/))/i.test(url) ? url : null;
}

/// `**fet**`, `*kursiv*`, `` `kode` `` og `[tekst](adresse)`. All tekst escapes.
export function inlineHTML(text: string): string {
  return text
    .split(/(`[^`]+`)/)
    .map((part) => {
      if (part.length > 1 && part.startsWith("`") && part.endsWith("`")) {
        return `<code>${escapeHTML(part.slice(1, -1))}</code>`;
      }
      return part
        .split(/(\[[^\]\n]*\]\([^)\s]*\))/)
        .map((piece) => {
          const link = /^\[([^\]\n]*)\]\(([^)\s]*)\)$/.exec(piece);
          if (link) {
            const href = safeHref(link[2]);
            const label = emphasis(escapeHTML(link[1]));
            return href ? `<a href="${escapeHTML(href)}">${label}</a>` : label;
          }
          return emphasis(escapeHTML(piece));
        })
        .join("");
    })
    .join("");
}

function emphasis(escaped: string): string {
  return escaped
    .replace(/\*\*(.+?)\*\*/g, "<strong>$1</strong>")
    .replace(/\*([^*\s](?:[^*]*[^*\s])?)\*/g, "<em>$1</em>");
}

function tableCells(line: string): string[] {
  return line.trim().replace(/^\|/, "").replace(/\|$/, "").split("|").map((cell) => cell.trim());
}

const TABLE_SEPARATOR = /^\|?\s*:?-+:?\s*(\|\s*:?-+:?\s*)*\|?\s*$/;

/// Den lille delen av markdown tekstene bruker: `#`/`##`, avsnitt, `-`-lister, tabeller, fet, kursiv, kode og lenker.
export function markdownToHTML(markdown: string): string {
  const lines = markdown.replace(/\r\n?/g, "\n").split("\n");
  const out: string[] = [];
  let i = 0;
  while (i < lines.length) {
    const line = lines[i];
    if (line.trim() === "") { i++; continue; }

    const heading = /^(#{1,2})\s+(.*)$/.exec(line);
    if (heading) {
      const level = heading[1].length;
      out.push(`<h${level}>${inlineHTML(heading[2].trim())}</h${level}>`);
      i++;
      continue;
    }

    if (/^\s*-\s+/.test(line)) {
      const items: string[] = [];
      while (i < lines.length && /^\s*-\s+/.test(lines[i])) {
        items.push(`<li>${inlineHTML(lines[i].replace(/^\s*-\s+/, "").trim())}</li>`);
        i++;
      }
      out.push(`<ul>\n${items.join("\n")}\n</ul>`);
      continue;
    }

    if (line.trim().startsWith("|") && i + 1 < lines.length && TABLE_SEPARATOR.test(lines[i + 1].trim())) {
      const head = tableCells(line).map((cell) => `<th scope="col">${inlineHTML(cell)}</th>`).join("");
      i += 2;
      const rows: string[] = [];
      while (i < lines.length && lines[i].trim().startsWith("|")) {
        rows.push(`<tr>${tableCells(lines[i]).map((cell) => `<td>${inlineHTML(cell)}</td>`).join("")}</tr>`);
        i++;
      }
      out.push(`<div class="tabell"><table>\n<thead><tr>${head}</tr></thead>\n<tbody>\n${rows.join("\n")}\n</tbody>\n</table></div>`);
      continue;
    }

    // Første linje tas alltid med, så en løs `|`-linje uten skillelinje blir et vanlig avsnitt.
    const paragraph: string[] = [line.trim()];
    i++;
    while (i < lines.length && lines[i].trim() !== "" && !/^(#{1,2}\s|\s*-\s+|\s*\|)/.test(lines[i])) {
      paragraph.push(lines[i].trim());
      i++;
    }
    out.push(`<p>${inlineHTML(paragraph.join(" "))}</p>`);
  }
  return out.join("\n");
}

/// Teksten i første `#`-overskrift, uten markdown.
function firstHeading(markdown: string): string {
  return /^#\s+(.*)$/m.exec(markdown)?.[1].replace(/[*`]/g, "").trim() ?? "Atten";
}

const SUPPORT_HTML = `
<h1>Support for Atten</h1>
<p>Atten er en app for å føre golfrunder, spille med venner og kjøre turneringer med gjengen.</p>
<h2>Kontakt</h2>
<p>Spørsmål om appen eller personvern: <a href="mailto:${CONTACT_EMAIL}">${CONTACT_EMAIL}</a>.</p>
<h2>Slette kontoen</h2>
<p>Åpne <strong>Deg → Slett konto</strong> i appen. Les i <a href="/personvern">personvernerklæringen</a> hva som slettes.</p>
<h2>Rapportere eller blokkere</h2>
<p>Hold inne på en melding i tråden, og velg å rapportere meldingen eller blokkere den som skrev den. En spiller kan du også rapportere eller blokkere fra profilen. Vi ser på rapporter innen 24 timer.</p>
<h2>Personvern og vilkår</h2>
<ul>
<li><a href="/personvern">Personvernerklæring</a></li>
<li><a href="/vilkar">Vilkår for bruk</a></li>
</ul>`;

/// `path`: den kanoniske adressen (uten / til slutt). `description`: teksten i søkeresultatet og del-kortet.
export type LegalPage = { path: string; title: string; description: string; content: string };

function fromMarkdown(path: string, markdown: string, description: string): LegalPage {
  return { path, title: firstHeading(markdown), description,
           content: markdownToHTML(markdown) + `\n<p class="liten"><a href="/">Til forsiden</a></p>` };
}

let pages: Record<string, LegalPage> | null = null;

/// `/personvern`, `/vilkar` og `/support`, med eller uten / til slutt. null: ikke en av dem.
export function legalPage(pathname: string): LegalPage | null {
  const match = /^\/(personvern|vilkar|support)\/?$/.exec(pathname);
  if (!match) return null;
  pages ??= {
    personvern: fromMarkdown("/personvern", PERSONVERN_MD,
      "Hvilke opplysninger golfappen Atten lagrer, hvorfor, hvor de ligger og hvordan du sletter kontoen. Ingen reklame og ingen sporing."),
    vilkar: fromMarkdown("/vilkar", VILKAR_MD,
      "Vilkårene for å bruke golfappen Atten: kontoen din, regler for innhold, poeng uten penger, ansvar og kontakt."),
    support: {
      path: "/support", title: "Support – Atten",
      description: "Kontakt Atten, slett kontoen din, eller rapporter og blokker innhold i golfappen.",
      content: SUPPORT_HTML + `\n<p class="liten"><a href="/">Til forsiden</a></p>`,
    },
  };
  return pages[match[1]];
}
