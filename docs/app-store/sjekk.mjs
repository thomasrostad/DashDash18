// Sjekker App Store-metadataene i docs/app-store/metadata/ mot Apples grenser og våre egne regler.
// Kjør: `node docs/app-store/sjekk.mjs`. Avslutter med kode 1 og en liste over brudd hvis noe er galt.
// Uten avhengigheter. Tegn telles som Unicode-tegn, ikke bytes. Avsluttende linjeskift trimmes bort.
import { existsSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, "metadata");

const languages = ["nb", "en-GB"];
const limits = {
  "name.txt": 30,
  "subtitle.txt": 30,
  "keywords.txt": 100,
  "promotional_text.txt": 170,
  "description.txt": 4000,
};
// Beskrivelsen finnes bare på norsk.
const required = {
  nb: Object.keys(limits),
  "en-GB": ["name.txt", "subtitle.txt", "keywords.txt", "promotional_text.txt"],
};
// Ord som ikke skal stå i noen fil (helt ord, uavhengig av store og små bokstaver).
const forbidden = ["tipping", "veddemål", "betting", "wager", "bet"];

const errors = [];
const lines = [];
const length = (s) => [...s].length;
const read = (lang, file) => readFileSync(join(root, lang, file), "utf8").replace(/\s+$/u, "");
/// Hele ord i små bokstaver: splitt på alt som ikke er bokstav eller tall.
const words = (s) => s.toLowerCase().split(/[^\p{L}\p{N}]+/u).filter(Boolean);

const keywordsByLang = {};
for (const lang of languages) {
  const text = {};
  for (const file of required[lang]) {
    const path = join(root, lang, file);
    if (!existsSync(path)) {
      errors.push(`${lang}/${file}: fila mangler`);
      continue;
    }
    text[file] = read(lang, file);
    const n = length(text[file]);
    const ok = n <= limits[file];
    lines.push(`${ok ? "OK  " : "FEIL"} ${lang}/${file}: ${n}/${limits[file]} tegn`);
    if (!ok) errors.push(`${lang}/${file}: ${n} tegn, grensen er ${limits[file]}`);
    if (n === 0) errors.push(`${lang}/${file}: fila er tom`);

    for (const word of forbidden) {
      const re = new RegExp(`(?<![\\p{L}\\p{N}])${word}(?![\\p{L}\\p{N}])`, "iu");
      if (re.test(text[file])) errors.push(`${lang}/${file}: inneholder det forbudte ordet «${word}»`);
    }
  }

  const raw = text["keywords.txt"];
  if (raw === undefined) continue;
  if (/\s,|,\s/u.test(raw)) errors.push(`${lang}/keywords.txt: mellomrom ved komma (bruker tegn Apple ikke trenger)`);
  const keywords = raw.split(",").map((k) => k.trim().toLowerCase()).filter(Boolean);
  keywordsByLang[lang] = keywords;

  const seen = new Set();
  for (const k of keywords) {
    if (seen.has(k)) errors.push(`${lang}/keywords.txt: «${k}» står to ganger`);
    seen.add(k);
  }

  const nameWords = new Set([...words(text["name.txt"] ?? ""), ...words(text["subtitle.txt"] ?? "")]);
  for (const k of keywords) {
    for (const w of words(k)) {
      if (nameWords.has(w)) errors.push(`${lang}/keywords.txt: «${w}» står også i navn eller undertittel (Apple teller det allerede)`);
    }
  }
}

if (keywordsByLang.nb && keywordsByLang["en-GB"]) {
  const nb = new Set(keywordsByLang.nb.flatMap(words));
  for (const w of new Set(keywordsByLang["en-GB"].flatMap(words))) {
    if (nb.has(w)) errors.push(`keywords.txt: «${w}» står både i nb og en-GB (Apple slår språkene sammen i Norge)`);
  }
}

console.log(lines.join("\n"));
if (errors.length > 0) {
  console.error(`\n${errors.length} brudd:`);
  for (const e of errors) console.error(`- ${e}`);
  process.exit(1);
}
console.log("\nIngen brudd.");
