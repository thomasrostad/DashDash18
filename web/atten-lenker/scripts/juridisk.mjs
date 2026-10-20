// Lager src/juridisk-tekst.ts fra docs/personvern.md og docs/vilkar.md (kilden).
// `npm run juridisk` genererer alltid. `npm run juridisk -- --strict` avslutter med kode 1
// hvis teksten fortsatt har uutfylte hakeparenteser (f.eks. «[Oslo tingrett]»). Kjør med --strict før publisering.
import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const docs = join(here, "..", "..", "..", "docs");
// `--out <fil>` skriver et annet sted (brukes av testen).
const outFlag = process.argv.indexOf("--out");
const out = outFlag > 0 ? process.argv[outFlag + 1] : join(here, "..", "src", "juridisk-tekst.ts");
const strict = process.argv.includes("--strict");

const sources = [
  { name: "PERSONVERN_MD", file: "personvern.md" },
  { name: "VILKAR_MD", file: "vilkar.md" },
];

/// Hakeparenteser som ikke er en lenke (`[tekst](adresse)`): plassholdere som må fylles inn.
export function unfilledPlaceholders(text) {
  return [...text.matchAll(/\[[^\]\n]*\](?!\()/g)].map((m) => m[0]);
}

let body =
  "// GENERERT av scripts/juridisk.mjs fra docs/personvern.md og docs/vilkar.md. Ikke rediger her:\n" +
  "// endre .md-filene og kjør `npm run juridisk`.\n";
const warnings = [];
for (const { name, file } of sources) {
  const text = readFileSync(join(docs, file), "utf8");
  for (const placeholder of unfilledPlaceholders(text)) warnings.push(`docs/${file}: ${placeholder}`);
  body += `\nexport const ${name} = ${JSON.stringify(text)};\n`;
}
writeFileSync(out, body);
console.log(`Skrev ${out}`);

if (warnings.length > 0) {
  console.warn(`\nADVARSEL: ${warnings.length} uutfylte hakeparenteser. Fyll dem inn før sidene publiseres:`);
  for (const warning of warnings) console.warn(`  ${warning}`);
  if (strict) process.exit(1);
}
