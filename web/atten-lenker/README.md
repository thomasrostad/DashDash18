# atten-lenker

Cloudflare Worker for https://dashdash18.com. Den gjør to ting:

- **Universelle lenker.** Serverer `apple-app-site-association` (på `/.well-known/apple-app-site-association` og `/apple-app-site-association`), slik at iOS åpner `https://dashdash18.com/klubb/KODE`, `/runde/KODE` og `/konkurranse/KODE` i Atten.
- **Invitasjonssider.** Har man ikke appen, åpnes de samme adressene i nettleseren. Siden viser koden, en knapp som åpner `dashdash://<type>/KODE`, og hvordan man får appen.

`/` er en kort side om Atten. Alt annet gir 404. Siden har ingen sporing, ingen cookies og ingen eksterne skript.

## Endre tekst

Øverst i `src/index.ts`:

- `GET_THE_APP_HTML`: teksten til den som ikke har appen. Bytt til App Store-lenken når appen er ute.
- `PRIVACY_URL`: adressen til personvernerklæringen. Lenken vises på forsiden når den er satt (samme adresse som `LegalLinks.privacy` i appen).

## Test

Node 24 eller nyere, uten Cloudflare:

```sh
npm test
```

## Deploy

Wrangler må være logget inn på Cloudflare-kontoen som eier dashdash18.com (`npx wrangler login`).

```sh
cd web/atten-lenker
npm install
npm test
npx wrangler deploy
```

`routes` i `wrangler.toml` gjør dashdash18.com til et eget domene for workeren (Custom Domain). Cloudflare lager DNS-posten og sertifikatet selv. Finnes det allerede en DNS-post for `dashdash18.com` (A, AAAA eller CNAME), må den slettes først, ellers feiler deployen. `www.dashdash18.com` dekkes ikke. Skal den også virke, må den legges til som egen rute, og appen må få `applinks:www.dashdash18.com`.

`npx wrangler deploy --dry-run --outdir dist` bygger uten å laste opp, og krever ikke innlogging.

### Sjekk etter deploy

```sh
curl -sI https://dashdash18.com/.well-known/apple-app-site-association   # 200, application/json, ingen Location
curl -s https://dashdash18.com/.well-known/apple-app-site-association
```

Apple henter filen gjennom sitt eget CDN, så det kan ta litt tid før endringer slår inn. Hva Apple har lagret, ser du på `https://app-site-association.cdn-apple.com/a/v1/dashdash18.com`.

Deretter slås flagget `UniversalLinksFeature.isEnabled` på i appen, og «Associated Domains» med `applinks:dashdash18.com` legges til i Xcode.
