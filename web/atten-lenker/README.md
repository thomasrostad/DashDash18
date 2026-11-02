# atten-lenker

Cloudflare Worker for https://dashdash18.com. Den gjør to ting:

- **Universelle lenker.** Serverer `apple-app-site-association` (på `/.well-known/apple-app-site-association` og `/apple-app-site-association`), slik at iOS åpner `https://dashdash18.com/klubb/KODE`, `/runde/KODE`, `/konkurranse/KODE` og `/folg/KODE` i Atten.
- **Invitasjonssider.** Har man ikke appen, åpnes de samme adressene i nettleseren. Siden viser koden, en knapp som åpner `dashdash://<type>/KODE`, og hvordan man får appen.

- **Følgekoden** (steg 13, `sql/054`). `/folg/KODE` (8 tegn uten I, O, 0 og 1) står i AASA-filen, så QR-koden i «Min kode» åpner appen. Uten appen viser siden «Åpne Atten for å følge» med koden og en knapp til `dashdash://folg/KODE`. Ugyldig kode gir 404.

- **Kalenderabonnement** (steg 10, `sql/051`). `/kalender/<token>.ics` henter `calendar_feed(token)` med den publiserbare nøkkelen (`SUPABASE_URL`, `SUPABASE_KEY`, som TV-siden) og svarer med iCalendar: kveldene medlemmet er bekreftet påmeldt på, med tid i Europe/Oslo (VTIMEZONE), tre timer per kveld, heldag når kvelden ikke har tid, og `REFRESH-INTERVAL`/`X-PUBLISHED-TTL` på én time. Lenken er personlig: `Cache-Control: private, max-age=300`, ukjent eller avskrudd lenke gir 404. Appen åpner `webcal://dashdash18.com/kalender/<token>.ics`.

- **Tavla for tilskuere** (`sql/056`). `/tavla/KODE` er lenken fra «Del tavla» i appen: tabellen, «Alle runder» og scorekortene, mobilvennlig, lys og mørk, med appens farger og skrifter. Siden henter `/tavla/KODE.json` hvert 20. sekund (og når fanen kommer fram igjen). Workeren henter `tv_board_data(kode)` som TV-siden og regner med `web/golfgutu-core` (`src/tavla.ts`). JSON-svaret holdes 10 sekunder i Cloudflares hurtigbuffer per kode, så mange tilskuere ikke gir mange kall til Supabase. Avslått eller ukjent kode gir 404, og siden sier «Lenken virker ikke lenger». Skriftene (Figtree og Sometype Mono, kuttet til latinske tegn, OFL) ligger i `public/fonts` og serveres som statiske filer (`[assets]` i `wrangler.toml`).

- **Personvern, vilkår og support** (App Store). `/personvern` og `/vilkar` viser `docs/personvern.md` og `docs/vilkar.md`, `/support` er en kort side med kontakt (personvern@dashdash18.com), sletting av konto og rapportering. Alle tre godtar også / til slutt og caches én time. Markdown-filene er kilden: `npm run juridisk` skriver dem til `src/juridisk-tekst.ts` (generert, sjekkes inn), og `src/juridisk.ts` gjør dem om til HTML (overskrifter, avsnitt, lister, tabeller, fet, kursiv, kode, lenker; all tekst escapes). En test feiler hvis den genererte filen ikke stemmer med `docs/`.

- **CAPTCHA ved innlogging** (1.0.1, `CaptchaFeature` i appen). `/captcha?sitekey=…` viser Cloudflare Turnstile (`appearance: interaction-only`, så ruta bare vises når Turnstile vil ha et trykk) og sender svaret til appen med `window.webkit.messageHandlers.atten.postMessage`: `{type: "token", token}`, `{type: "error", code}`, `expired`, `timeout` og `interactive`. Site key-en kommer fra appen i adressen (den er offentlig), så samme side virker for test og prod. Ugyldig eller manglende nøkkel gir 400. CSP slipper bare inn `https://challenges.cloudflare.com` (skript og ramme), `Cache-Control: no-store`, og `Referrer-Policy: strict-origin` så Turnstile ser domenet. Domenet `dashdash18.com` må stå på widgeten i Cloudflare. Siden må være deployet før appen får en site key.

`/` er salgssiden for spillerne og golfgjengen (se «Salgssidene» under), med lenker til personvern, vilkår og support i bunnen. Alt annet gir en 404-side i samme stil, med lenke til forsiden og App Store. Sidene har ingen sporing, ingen cookies og ingen eksterne skript, med unntak av Turnstile på `/captcha`. Salgssidene har ett inline-skript med nonce (bevegelsen).

- **Innholdssider for Google** (`src/innhold.ts`, 02.11.2026): kalkulator, klubbside og guider. Hver side er én fil i `src/innhold/` og én linje i `CONTENT_PAGES`; ruting, `/sitemap.xml`, JSON-LD og lenkene i bunnen av forsiden og innholdssidene kommer derfra. Testene sjekker tittel, beskrivelse, kanonisk adresse og lenkene for hver side.
  - **Stableford-kalkulator** (`/stableford`, `src/innhold/stableford.ts`): banehandicap, spillehandicap, slag per hull og poeng hull for hull. Skjemaet sendes med GET til samme adresse og regnes på serveren med WHS-koden i `web/golfgutu-core/src/whs.ts` (ingen skript). En side med `render` i `ContentPage` får `form-action 'self'` i CSP-en; kanonisk adresse er `/stableford` også med spørring.
- **Søk og deling.** `/`, `/personvern`, `/vilkar` `/support` og innholdssidene indekseres: egen tittel og beskrivelse, kanonisk adresse og del-kort (Open Graph og `twitter:card`). Bare de står i `/sitemap.xml`. Alt annet er `noindex`, og invitasjonene, følgekoden og Tavla har del-kort uten kanonisk adresse. Invitasjonene, følgekoden, Tavla og TV bruker Figtree fra `public/fonts`.
- **Utseende på nettstedet** (`src/nettsted.ts`, 02.11.2026): forsiden, innholdssidene, personvern, vilkår, support og 404-siden har samme uttrykk som forsiden på admin.dashdash18.com (`web/admin/src/landing/`): natt-grønn flate, høydekurver i gull, Archivo smal og fet i versaler og Newsreader kursiv i gull. Rammen er én mekanisme (`site` i `page()`): toppmeny (Kalkulator, Guider, For klubber, Logg inn; «Guider» er en `<details>`, så den virker uten skript), toppen med h1, ingress og knapper hentet fra starten av innholdet, hver `<h2>` som en blokk med tynn kant, og bunnen med lenkene. `eyebrow` og `heading` (`loud` og `soft`) i `ContentPage` gir den lille linja og den todelte overskriften; sammen må delene være nøyaktig teksten i `<h1>` (testes), så teksten Google ser er uendret. Personvern, vilkår, support og 404 får menyen og bunnen, men ingen topp. Høydekurvene regnes på serveren med `fillTopoField`, `contourLevels` og `contourSegments` fra `web/admin/src/landing/topo.ts` (samme kode som på web-admin) og legges inn som SVG, regnet én gang per isolat. Ingen skript, ingen eksterne kall. Skriftene `archivo-latin.woff2` og `newsreader-latin.woff2` i `public/fonts` er **kopier** fra `web/admin/public/fonts` (SIL Open Font License, `OFL-Archivo.txt` og `OFL-Newsreader.txt`); statiske filer kan ikke deles mellom workerne, så endres de der, kopier dem på nytt. `test/nettsted.test.ts` sjekker menyen, én h1, toppen, blokkene og at invitasjonene er uendret.
- **Salgssidene** (`src/salgsside.ts`, 02.11.2026): `/` og `/for-klubber` har de samme delene som forsiden på admin.dashdash18.com, fra samme kilde i `web/admin/src/landing/`: markeringen (`markup.ts`: tavla på TV-en, telefonen med scorekortet, kortene i «Bli kjent»-raden, setningen som tones inn og fotobåndet), stilen (`style.ts`, `LANDING_STYLE`) og bevegelsen (`live.ts`, `startLanding`). Workeren server-rendrer delene og legger `startLanding` inn som tekst i et inline-skript med nonce; uten skript står alt ferdig (starttilstandene gjelder bare under `.live`). Derfor `keep_names = false` i `wrangler.toml`: ellers setter esbuild inn `__name(...)` i funksjonen, og den finnes ikke i nettleseren. Teksten for Google står i innholdet som før (h1, ingress, knapper og h2-ene med søkeordene) og plasseres i delene: h1 i toppen, hver h2 som en del med overskriften til venstre (`photoAfter` styrer hvor fotobåndet kommer). En side blir salgsside med `landing` i `ContentPage` (eller `HOME_LANDING` i `src/index.ts`). Paletten fra `web/admin/src/styles.css` står i `LANDING_SITE_STYLE`, avgrenset til `.landing`, så sidene er lyse i lys modus og mørke i mørk, som admin. Bildene i `public/landing` (`fairway.jpg`, `kveld.jpg`) er **kopier** fra `web/admin/public/landing` (Unsplash-lisensen, kreditert i bunnen); navn, poeng og koder i eksemplene er oppdiktet. `test/salgsside.test.ts` sjekker delene, h1-teksten, søkeordene i h2, at alt er synlig uten skript, skriptet og bildene.
- **TV-visningen** (`src/tv.ts`, 02.11.2026): `/tv` og `/tv/KODE` har samme uttrykk som tavla på TV-en på forsiden (`demoTavla` i `web/admin/src/landing/markup.ts`). Stilen er den samme som salgssidene bruker (`SITE_STYLE` og `LANDING_HEAD_STYLE`, med `.tv`, `.bar`, `.ttl`, rutene og `.field`); `TV_STYLE` gjør den bare stor nok til en hel skjerm og legger til kortene ved siden av. Navnet står i store versaler med en kort forklaring av hvordan tabellen regnes i gull kursiv (`tableHeading`, fra `table` i regelsettet; ligaen bruker `rulesSummary`), kolonnen sier hva tallet er («Matchpoeng», «Stableford», «Snitt»), lederen i gull, bevegelse siden forrige kveld (▲/▼/–) i stedet for detaljlinja, poengene per runde som små ruter (så mange som får plass i bredden), «Live» med prikk når siste runde pågår, og «Siste runde», lag mot lag og de andre konkurransene som kort. Høydekurvene er den faste SVG-en fra `nettsted.ts` (ingen bevegelse). Hvor mange rader som får plass, måles på skjermen, og sidene byttes hvert 10. sekund. Utseendet bruker fire felt i `/tv/KODE.json` i tillegg til de gamle (som er uendret, også `detail`): `heading` (navn, forklaring, framdrift og kolonneoverskriftene), `kind`, `rounds` (rutenettet fra «Alle runder», i tabellens rekkefølge) og `moves` (plass før minus plass nå: samme TavlaStandings/LeagueStandings regnet på rådataene uten siste kveld eller runde; null for første kveld, ny spiller og uten plass, og for hele tabellen i cupen og når sesongen har en playoff-runde). Størrelsene regnes fra skjermhøyden (`--u`), og en smal nettleser får kortene under tabellen.
- **Ikoner og del-bilde** i `public/`: `favicon.svg` (app-ikonet fra `DashDash18/AppIcon.icon` med avrundede hjørner), `favicon.ico` (16, 32 og 48 px fra SVG-en), `apple-touch-icon.png` (180 px fra `AppIcon.png`) og `og.png` (1200 × 630, Figtree og appens farger). Endres app-ikonet, må de lages på nytt.

## Endre tekst

Øverst i `src/index.ts`:

- `GET_THE_APP_HTML`: teksten til den som ikke har appen, med App Store-lenken.
- `HOME_TITLE` og `HOME_DESCRIPTION`: tittel og beskrivelse for forsiden i søk og del-kort. Beskrivelsene til personvern, vilkår og support står i `src/juridisk.ts`.
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
