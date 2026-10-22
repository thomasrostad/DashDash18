# ASO-plan: Atten synlig i App Store og Google

Vedtatt 21.10.2026. Bakgrunn og ferdig tekst: [Atten – App Store-optimalisering](https://claude.ai/artifact/Y4GMftpFqocWSeznZvYKeP).

**Mål:** Atten skal dukke opp når noen i Norge søker på golfturnering, scorekort, golfgjeng, liga eller stableford, i App Store og på Google. I dag heter appen bare «Atten», har ingen undertittel, ingen vurderinger, og nettsiden var skjult for Google.

**Tidslinje** (følger `docs/utgivelser.md`):

| Dato | Hva |
|---|---|
| Tor 22.10 | Agentene kjører A1–A5 parallelt. Thomas gjør T1 og T2. |
| Fre 23.10 | PR-ene er merget, bygget ligger i TestFlight (Gjengen). |
| Man 26.10 | Prod-bygg og innsending med ny metadata og skjermbilder (T3). |
| Tir–tor 27.–29.10 | Utgivelse med phased release. |
| Man 9.11 og 23.11 | Måling og justering (A6). |

## Slik starter du i morgen

Åpne Claude Code i repoet og lim inn:

> Les `docs/aso-plan.md`. Kjør oppgavene A1–A5 som egne agenter, hver i sin worktree og på sin branch fra oppdatert `main`, parallelt. Hver agent følger CLAUDE.md (bygg, tester, PR, ingen endring i `.xcodeproj`), og leverer én PR. Når alle er ferdige: gi meg én liste med PR-lenke, status (bygg og tester) og hva som gjenstår for meg. Merge selv det som er grønt og ikke krever noe av meg.

## Oppgaver for agentene

Alle fem er uavhengige og kan kjøres samtidig. Ingen av dem rører Supabase.

### A1. Merge og deploy av nettsiden

- **Branch:** finnes allerede, `fiks/seo-nettside` ([PR #186](https://github.com/thomasrostad/DashDash18/pull/186)).
- **Gjør:** les PR-en, kjør `npm test` i `web/atten-lenker`, merge med squash når testene er grønne.
- **Deploy** (`npm run deploy`) krever Cloudflare-innlogging og gjøres av Thomas (T1).
- **Ferdig når:** PR #186 er merget.

### A2. Be om vurdering etter en god runde

- **Branch:** `fiks/vurdering`
- **Prompt:**
  > Legg til en forespørsel om vurdering med `@Environment(\.requestReview)`. Vis den bare når brukeren har fullført minst to runder, rett etter at en runde er levert (`RundeModel.finish()`) og feiringen er lukket (`FeiringOverlay.onDismiss`), og høyst én gang per app-versjon. Aldri ved oppstart, midt i føringen, for gjester eller i UI-tester. Legg beslutningen i en ren, `nonisolated` type (for eksempel `ReviewPrompt`) som tar antall fullførte runder, siste versjon det ble spurt i og gjeldende versjon, og lagre tilstanden i `UserDefaults`. Skriv testene først (Swift Testing).
- **Ferdig når:** bygget er grønt, testene for `ReviewPrompt` dekker: under to runder, to runder, samme versjon, ny versjon, gjest.

### A3. Del-kort som peker hjem

- **Branch:** `fiks/delekort-adresse`
- **Prompt:**
  > I `Features/Deling/ResultShareCard.swift` står bare «Atten» nederst på bildet. Endre bunnteksten til «Atten · dashdash18.com», i samme stil. Sjekk at kortet fortsatt ser riktig ut i `RenderMatrixTests` og med lange navn.
- **Ferdig når:** bygget og testene er grønne.

### A4. Metadata som filer, med kontroll av lengder

- **Branch:** `docs/aso-metadata` (tittel med `[ci skip]`)
- **Prompt:**
  > Lag `docs/app-store/metadata/nb/` og `docs/app-store/metadata/en-GB/` med én fil per felt: `name.txt`, `subtitle.txt`, `keywords.txt`, `promotional_text.txt` og (bare nb) `description.txt`. Teksten står i tabellen under. Lag `docs/app-store/sjekk.mjs` (Node, uten avhengigheter) som feiler hvis navn eller undertittel er over 30 tegn, nøkkelord over 100, reklametekst over 170, beskrivelse over 4000, hvis nøkkelordene har mellomrom etter komma, hvis et ord i nøkkelordene også står i navn eller undertittel for samme språk, eller hvis et ord går igjen mellom nb og en-GB. Kjør den og vis resultatet i PR-en.
- **Tekst:**

  | Felt | nb | en-GB |
  |---|---|---|
  | Navn | Atten – golf med gjengen | Atten: Golf League Tracker |
  | Undertittel | Turnering, score og tavle | Scorecard and leaderboard |
  | Nøkkelord | golfturnering,scorekort,liga,stableford,slagspill,matchspill,handicap,poeng,venner,klubb,resultater | tournament,society,matchplay,friends,buddies,group,season,standings,net,gross,outing,scoring,app |
  | Reklametekst | Påmelding, båser, scorekort hull for hull og en tavle som oppdateres mens dere spiller. Liga, cup og oppgjør for golfgjengen, samlet i én app. | (samme som nb) |

  Beskrivelsen (nb) står i dokumentet over, under «Ferdig metadata, norsk». Ingen ord som tipping, veddemål eller betting i noen fil.
- **Ferdig når:** `node docs/app-store/sjekk.mjs` gir null feil.

### A5. Skjermbilder med søkeord i teksten

- **Branch:** `fiks/appstore-skjermbilder`
- **Prompt:**
  > Lag en UI-test, `DashDash18UITests/AppStoreScreenshotTests.swift`, som åpner skjermene under med `-DDDesignScreen <navn>` på iPhone 17 Pro Max-simulatoren, tar skjermbilde og legger det ved som `XCTAttachment` med navnet `01-…` til `06-…`. Lag så et skript i `docs/app-store/` som henter bildene ut av `.xcresult` og setter overskriften øverst i Attens farger og skrift, i App Stores 6,9-tommersformat (1320 × 2868). Overskriften skal være stor og lett å lese maskinelt; Apple bruker teksten i søket. Ny fil i UI-test-målet legges til med Xcode-verktøyene, ikke ved å redigere prosjektfila.

  | # | Skjerm (`-DDDesignScreen`) | Overskrift |
  |---|---|---|
  | 1 | `kvelden` | Golfkvelden med gjengen, samlet |
  | 2 | `hullkort` | Scorekort hull for hull |
  | 3 | `tavla` | Tavla oppdateres mens dere spiller |
  | 4 | `sesong` | Liga og cup hele sesongen |
  | 5 | `nyturnering` | Stableford, slagspill og matchspill |
  | 6 | `feiring` | Hvem tar jakka i år? |

- **Ferdig når:** seks PNG-er i riktig størrelse ligger som vedlegg i PR-en (ikke sjekket inn i git), og testen er grønn.

## Oppgaver for Thomas

Disse krever innlogging som agentene ikke har.

- [ ] **T1 (tor, 10 min):** når A1 er merget: `cd web/atten-lenker && npm run deploy`. Sjekk at `https://dashdash18.com/robots.txt` svarer. Legg domenet inn i [Google Search Console](https://search.google.com/search-console) og send inn `https://dashdash18.com/sitemap.xml`.
- [ ] **T2 (tor, 5 min):** App Store Connect → Atten → reklametekst for nb. Den kan endres uten ny versjon, så den går ut med en gang.
- [ ] **T3 (man 26.10, 30 min):** ny versjon i App Store Connect. Lim inn fra `docs/app-store/metadata/nb/` (A4). Legg til språket English (U.K.) og lim inn fra `en-GB/`. Last opp de seks bildene fra A5 under 6,9-tommer. Send inn sammen med prod-bygget, som vanlig etter `docs/utgivelser.md`.

## A6. Måling (9.11 og 23.11)

- **Prompt (kan settes opp som planlagt oppgave):**
  > Les `docs/aso-plan.md`. Lag en kort status: hvilke av A1–A5 og T1–T3 er gjort (sjekk PR-er og `main`), om `dashdash18.com` er indeksert (søk «site:dashdash18.com»), og om Atten vises i App Store-søk på golfturnering, scorekort, golfgjeng, golf liga og stableford. Foreslå hvilke nøkkelord som bør byttes ut ved neste versjon.
- Thomas legger til tallene fra App Store Connect → Analyse → Visninger og Kilde (App Store-søk), som agenten ikke har tilgang til.
- **Regel:** bytt bare nøkkelord som ikke har gitt visninger etter to uker. Ett sett endringer per versjon, så det er mulig å se hva som virket.

## Status

- [ ] A1 nettside merget
- [x] A2 vurdering
- [ ] A3 del-kort
- [ ] A4 metadata
- [ ] A5 skjermbilder
- [ ] T1 deploy og Search Console
- [ ] T2 reklametekst
- [ ] T3 innsending med ny metadata
- [ ] A6 første måling 9.11
