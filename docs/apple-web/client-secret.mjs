// Lager client secret-en (ES256-JWT) som Supabase Auth trenger for Logg inn med Apple på web og
// Android. Apple godtar høyst seks måneder, så den må lages på nytt før den går ut (docs/apple-web.md).
//
// Kjør (Node 22.18 eller nyere, uten avhengigheter):
//   node docs/apple-web/client-secret.mjs --team <Team ID> --key-id <Key ID> \
//     --client com.dashdash18.app.web --p8 ~/Downloads/AuthKey_XXXXXXXXXX.p8 | pbcopy
//
// Samme signering som delete-account (supabase/functions/delete-account/apple.ts).
// Nøkkelen leses bare inn i minnet: den skrives aldri til disk, logg eller skjerm.
// Bare JWT-en går til stdout. Utløpsdatoen og advarsler går til stderr.
import { readFileSync } from "node:fs";
import { CLIENT_SECRET_MAX_TTL_SECONDS, importAppleKey, makeClientSecret } from "../../supabase/functions/delete-account/apple.ts";

const BUNDLE_ID = "com.dashdash18.app";

function arg(name) {
  const i = process.argv.indexOf(`--${name}`);
  return i > 0 ? (process.argv[i + 1] ?? "").trim() : "";
}

function fail(message) {
  console.error(`Feil: ${message}`);
  console.error("Bruk: node docs/apple-web/client-secret.mjs --team <Team ID> --key-id <Key ID> --client <Services ID> --p8 <AuthKey_….p8>");
  process.exit(1);
}

const teamId = arg("team");
const keyId = arg("key-id");
const clientId = arg("client");
const p8 = arg("p8");
// Valgfritt: antall dager (standard og høyst 180, litt under Apples grense).
const days = arg("days") ? Number(arg("days")) : 180;

if (!/^[A-Z0-9]{10}$/.test(teamId)) fail("--team må være Team ID-en, 10 tegn (A–Z og 0–9).");
if (!/^[A-Z0-9]{10}$/.test(keyId)) fail("--key-id må være Key ID-en, 10 tegn (A–Z og 0–9).");
if (!clientId) fail("--client mangler (Services ID-en, f.eks. com.dashdash18.app.web).");
if (clientId === BUNDLE_ID) fail(`--client skal være Services ID-en, ikke bundle-id-en ${BUNDLE_ID}.`);
if (!p8) fail("--p8 mangler (stien til AuthKey_….p8).");
const ttl = Math.floor(days * 24 * 60 * 60);
if (!Number.isInteger(days) || ttl <= 0 || ttl > CLIENT_SECRET_MAX_TTL_SECONDS) fail("--days må være et heltall fra 1 til 180.");

let pem;
try {
  pem = readFileSync(p8, "utf8");
} catch {
  fail(`fant ikke fila ${p8}.`);
}

let jwt;
try {
  const key = await importAppleKey(pem);
  jwt = await makeClientSecret(key, { teamId, keyId, clientId, privateKeyPem: "" }, Math.floor(Date.now() / 1000), ttl);
} catch {
  // Feilmeldingen fra WebCrypto skrives ikke ut, i tilfelle den viser deler av nøkkelen.
  fail("klarte ikke å lese nøkkelen. Er det .p8-fila fra Apple (Sign in with Apple)?");
}

const expires = new Date(Date.now() + ttl * 1000);
process.stdout.write(`${jwt}\n`);
console.error(`Client secret for ${clientId} laget. Går ut ${expires.toISOString().slice(0, 10)}: lag en ny før det.`);
