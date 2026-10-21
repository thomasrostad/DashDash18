# atten-lenker

Cloudflare Worker for https://dashdash18.com. Den gjør to ting:

- **Universelle lenker.** Serverer `apple-app-site-association` (på `/.well-known/apple-app-site-association` og `/apple-app-site-association`), slik at iOS åpner `https://dashdash18.com/klubb/KODE`, `/runde/KODE`, `/konkurranse/KODE` og `/folg/KODE` i Atten.
- **Invitasjonssider.** Har man ikke appen, åpnes de samme adressene i nettleseren. Siden viser koden, en knapp som åpner `dashdash://<type>/KODE`, og hvordan man får appen.

- **Følgekoden** (steg 13, `sql/054`). `/folg/KODE` (8 tegn uten I, O, 0 og 1) står i AASA-filen, så QR-koden i «Min kode» åpner appen. Uten appen viser siden «Åpne Atten for å følge» med koden og en knapp til `dashdash://folg/KODE`. Ugyldig kode gir 404.

- **Kalenderabonnement** (steg 10, `sql/051`). `/kalender/<token>.ics` henter `calendar_feed(token)` med den publiserbare nøkkelen (`SUPABASE_URL`, `SUPABASE_KEY`, som TV-siden) og svarer med iCalendar: kveldene medlemmet er bekreftet påmeldt på, med tid i Europe/Oslo (VTIMEZONE), tre timer per kveld, heldag når kvelden ikke har tid, og `REFRESH-INTERVAL`/`X-PUBLISHED-TTL` på én time. Lenken er personlig: `Cache-Control: private, max-age=300`, ukjent eller avskrudd lenke gir 404. Appen åpner `webcal://dashdash18.com/kalender/<token>.ics`.

- **Tavla for tilskuere** (`sql/056`). `/tavla/KODE` er lenken fra «Del tavla» i appen: tabellen, «Alle runder» og scorekortene, mobilvennlig, lys og mørk, med appens farger og skrifter. Siden henter `/tavla/KODE.json` hvert 20. sekund (og når fanen kommer fram igjen). Workeren henter `tv_board_data(kode)` som TV-siden og regner med `web/golfgutu-core` (`src/tavla.ts`). JSON-svaret holdes 10 sekunder i Cloudflares hurtigbuffer per kode, så mange tilskuere ikke gir mange kall til Supabase. Avslått eller ukjent kode gir 404, og siden sier «Lenken virker ikke lenger». Skriftene (Figtree og Sometype Mono, kuttet til latinske tegn, OFL) ligger i `public/fonts` og serveres som statiske filer (`[assets]` i `wrangler.toml`).

- **Personvern, vilkår og support** (App Store). `/personvern` og `/vilkar` viser `docs/personvern.md` og `docs/vilkar.md`, `/support` er en kort side med kontakt (personvern@dashdash18.com), sletting av konto og rapportering. Alle tre godtar også / til slutt og caches én time. Markdown-filene er kilden: `npm run juridisk` skriver dem til `src/juridisk-tekst.ts` (generert, sjekkes inn), og `src/juridisk.ts` gjør dem om til HTML (overskrifter, avsnitt, lister, tabeller, fet, kursiv, kode, lenker; all tekst escapes). En test feiler hvis den genererte filen ikke stemmer med `docs/`.

- **CAPTCHA ved innlogging** (1.0.1, `CaptchaFeature` i appen). `/captcha?sitekey=…` viser Cloudflare Turnstile (`appearance: interaction-only`, så ruta bare vises når Turnstile vil ha et trykk) og sender svaret til appen med `window.webkit.messageHandlers.atten.postMessage`: `{type: "token", token}`, `{type: "error", code}`, `expired`, `timeout` og `interactive`. Site key-en kommer fra appen i adressen (den er offentlig), så samme side virker for test og prod. Ugyldig eller manglende nøkkel gir 400. CSP slipper bare inn `https://challenges.cloudflare.com` (skript og ramme), `Cache-Control: no-store`, og `Referrer-Policy: strict-origin` så Turnstile ser domenet. Domenet `dashdash18.com` må stå på widgeten i Cloudflare. Siden må være deployet før appen får en site key.

`/` er en kort side om Atten med lenker til personvern, vilkår og support. Alt annet gir 404. Sidene har ingen sporing, ingen cookies og ingen eksterne skript, med unntak av Turnstile på `/captcha`.

## Endre tekst

Øverst i `src/index.ts`:

- `GET_THE_APP_HTML`: teksten til den som ikke har appen. Bytt til App Store-lenken når appen er ute.
- `APP_STORE_URL` (i `src/tavla.ts`): App Store-lenken i «Få Atten-appen» på Tavla-siden. `null` gir «Kommer snart».
- Personvern og vilkår: endre `docs/personvern.md` eller `docs/vilkar.md` og kjør `npm run juridisk`. Skriptet advarer om uutfylte hakeparenteser (f.eks. `[Oslo tingrett]`). **Før publisering:** `npm run juridisk -- --strict`, som avslutter med kode 1 så lenge noen står igjen. Adressene (`https://dashdash18.com/personvern` og `/vilkar`) settes i `LegalLinks` i appen.

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
