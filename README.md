# Atten (DashDash18)

Native iOS-app for golfturneringer blant venner. Den erstatter GolfGutu-PWA-en som Golfgutu Invitational bruker i dag. Brukerne ser navnet **Atten**. Repo, Xcode-prosjekt, bundle-id (`com.dashdash18.app`), domenet dashdash18.com og URL-skjemaet `dashdash://` heter fortsatt DashDash18.

- SwiftUI, iOS 26+, Swift 6, Swift Testing
- Backend: egen Supabase via `supabase-swift` (foreløpig bare test, prod kommer)
- iPhone først, Android senere

## Hva appen gjør nå

Status 09.10.2026. Alt kjører mot test-Supabase; prod er ikke satt opp. Detaljer per fase står i [`ROADMAP.md`](ROADMAP.md).

**Fanene.** Hjem · Spill · Tavla · Arrangør · Deg. «Arrangør» vises bare for arrangører i klubben. Uten klubb har appen Spill og Deg.

| Område | Hva |
|---|---|
| Innlogging og start | Apple eller engangskode på e-post. Ny bruker kan spille med venner med en gang, eller bli med i/lage en klubb. Google er av til OAuth er satt opp |
| Invitasjon | Klubblenke `https://dashdash18.com/klubb/KODE` (universell lenke, åpner appen) og QR-kode. Siden på dashdash18.com er Workeren i `web/atten-lenker/` |
| Hjem | Feed med aktivitet, «Pågår nå», neste kveld/spilledag med svar, tråd og tippekupong, og arrangørens knapp for neste steg |
| Spill | Løse runder på slope.no-baner, bli med med kode, spill i runden, «Del regningen» (Vipps), «Turneringer» for å se og lage turneringer (også uten klubb: private liga, cup og morro), og «Finn turneringer» med åpne turneringer å melde seg på |
| Turneringer | Fire oppsett: Stableford-serie, Matchspill-serie (Golfgutu), Cup og Morro. Påmelding med tak og venteliste, startliste, stab. Liga og morro kan være «Spill når det passer» (periode, de beste N teller, runder i perioden teller av seg selv). Liga, cup og morro i en klubb kan ha egne spilledager med runder («Spilledager og runder» på arrangørsiden). Lages fra «+» på Arrangør-fanen eller fra Spill. Kan slettes av arrangøren (navnet må skrives) |
| Ordet for en dag | «Kveld» for Golfgutu, «Spilledag» for nye turneringer (valg i «Ny turnering» og i reglene) |
| Arrangør på web | https://admin.dashdash18.com: samme innlogging og tilganger som appen. Del 1 viser turneringer, terminliste og tropp; resten kommer i delene i `web/admin/README.md` |
| Arrangør | Oppsett øverst (turneringen, troppen, banene), så dagen som står for tur med stegrekka Påmelding → Oppsett → Spilles → Ferdig, kommende og tidligere dager, varsler, rapporter og arkiv |
| Tavla | Tabellen regnes på telefonen av regelmotoren (paritet med PWA-en), med data fra én RPC (`tavla_data`). «Alle runder» (også i liga og morro) viser alle spillernes poeng, slag eller mot par runde for runde (som et PGA-leaderboard), og hver rute og hver runde på spillerprofilen åpner scorekortet. «TV-visning» viser tabellen i fullskjerm for skjermen i lokalet (side for side, siste runde, oppdateres mens det føres, skjermen slukker ikke) |
| Vedd og tips | Veddemål med poeng i hovedturneringen (ikke i andre turneringer ennå), tippekupong per kveld med «Tips» og «Forrige kupong» rett på Hjem-kortet |
| Ytelse | Mengdebaserte RPC-er for venner, løse runder, turneringslista og Hjem (sql/036–037) |

**Funksjonsflagg.** Nye deler ligger bak et flagg i koden til SQL-en er kjørt og prøvd. Av nå: `PurchaseFeature` (kjøp, venter på App Store Connect) og `GoogleLoginFeature` (venter på Google Cloud). Resten er på. Søk etter `Feature {` for å finne dem.

**Venter på Thomas.** App Store Connect, Google OAuth, personvern og vilkår publisert, egen SMTP, eksport fra PWA-en og ja til prod. Lista står i [`docs/gjoremal.md`](docs/gjoremal.md).

## Dokumenter

| Fil | Hva |
|---|---|
| [`ROADMAP.md`](ROADMAP.md) | Faser, status og beslutninger. Start her for å se hvor prosjektet står |
| [`SPEC.md`](SPEC.md) | Kartlegging av PWA-en (funksjoner og regler) |
| [`CLAUDE.md`](CLAUDE.md) | Arbeidsregler for Claude Code. Gjelder også for mennesker |
| [`docs/gjoremal.md`](docs/gjoremal.md) | Det som må gjøres manuelt (App Store Connect, Supabase-konsoll, Google) |
| [`sql/README.md`](sql/README.md) | Databasemigreringer og status per fil (test og prod) |
| [`docs/fase-26-tv-tidsvindu-web.md`](docs/fase-26-tv-tidsvindu-web.md) | Plan: TV med kode, turneringer med tidsvindu, regelmotoren i TypeScript og web-admin |
| [`docs/golfapper.md`](docs/golfapper.md) | Analyse av flyten i andre golfapper (Squabbit, 18Birdies, Golf Genius, GolfBox, Trackman m.fl.) og 12 anbefalinger for Atten |
| [`docs/vedd-per-turnering.md`](docs/vedd-per-turnering.md) | Forslag: veddemål per turnering, poengbank og oppgjør (venter på valg) |
| [`docs/`](docs/) | Datamodell, sikkerhet, push, widgets, Xcode Cloud, App Store, personvern og vilkår |

Ved konflikt gjelder `CLAUDE.md`, så `ROADMAP.md`, så `SPEC.md`.

## Mappestruktur

```
DashDash18/            Appen (App, Auth, Club, Data, Features, Outbox, Push, LiveActivity …)
DashDash18Widgets/     Widgets og Live Activity
DashDash18Tests/       Enhetstester for appen
DashDash18UITests/     UI-tester
Packages/GolfgutuCore/ Regelmotoren: ren Swift, egne tester og JSON-fixtures
Packages/DashImport/   Import fra PWA-en (fase 9)
sql/                   Migreringer for appens Supabase (nummerert, én fil = én transaksjon)
sql/lokal/             Prøveskript og sjekker (lokalt, eller i en transaksjon som rulles tilbake)
supabase/functions/    Edge Functions: push-send, delete-account, slope-sync, verify-purchase
web/atten-lenker/      Cloudflare Worker på dashdash18.com: AASA-fil og invitasjonssider
web/admin/             Web-admin på admin.dashdash18.com (Vite, React, supabase-js)
web/golfgutu-core/     Regelmotoren i TypeScript (paritet med GolfgutuCore, for TV-siden og web-admin)
StoreKit/              StoreKit-konfig for kjøp i simulatoren
ci_scripts/            Xcode Cloud (skriver Supabase-konfig fra miljøvariabler)
docs/                  Bakgrunn og oppsett
```

Ikke i git: `referanse/` (PWA-en, inneholder nøkler), `DashDash18/Config/Supabase-*.plist`, `import-snapshot/` og `import-out/` (navn fra gjengen).

## Kom i gang

1. Åpne `DashDash18.xcodeproj` i Xcode 26.6. Samme versjon brukes i Xcode Cloud, se [`docs/xcode-cloud.md`](docs/xcode-cloud.md).
2. Legg inn `DashDash18/Config/Supabase-Test.plist` med prosjekt-URL og **publishable key** for test-prosjektet. Service-role-nøkkelen skal aldri inn i appen.
3. Bygg og kjør skjemaet `DashDash18` på en simulator.

Ikke legg byggemapper under `Documents`. iCloud legger metadata på filene, og da feiler kodesigneringen.

## Tester

Regelmotoren:

```sh
cd Packages/GolfgutuCore && swift test
```

Appen:

```sh
xcodebuild test -project DashDash18.xcodeproj -scheme DashDash18 \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath ~/Library/Developer/Xcode/DerivedData/DashDash18-cli
```

Regelmotoren i TypeScript (`web/golfgutu-core`, for server og nett), mot de samme fixturene og goldenfilene fra Swift:

```sh
node --test 'web/golfgutu-core/test/*.test.ts'
```

Endres regelmotoren med vilje, skrives goldenfilene på nytt med `GOLDEN_WRITE=1 swift test --filter GoldenTests` i `Packages/GolfgutuCore` (se `web/golfgutu-core/README.md`).

Edge Functions har Deno-tester ved siden av koden, for eksempel `deno test supabase/functions/push-send/`.

Med Golfgutu-oppsettet skal regelmotoren gi nøyaktig samme svar som PWA-ens `db-nytt.js`. Testtallene kommer fra PWA-ens tester eller er utledet fra koden, aldri gjettet.

## Arbeidsflyt: branch og PR

`main` er alltid det som er i TestFlight. Ingen pusher rett til `main`.

1. Lag en branch fra oppdatert `main`, én per oppgave:
   `fase-18/ny-turnering`, `fiks/tavla-sortering`, `docs/readme`.
2. Commit i små steg. Meldingen peker på fasen: «Fase 18: stableford-serie i Tavla».
3. Bygg og kjør testene før PR.
4. Åpne PR mot `main` (`gh pr create`). Beskriv hva som er endret, hvordan det er testet, og om det trengs SQL eller oppsett.
5. Claude merger (squash) når bygg og tester er grønne, og sier fra med lenke. Krever PR-en noe av Thomas (SQL som ikke er godkjent, oppsett i App Store Connect eller Google), venter den på ham. Branchen slettes etter merge.

Når `main` endres, sender Xcode Cloud et nytt bygg til TestFlight (15–30 min). Gjelder PR-en bare dokumentasjon eller SQL, skriv `[ci skip]` i tittelen på squash-commiten, så startes ingen bygg.

## Database (Supabase)

Foreløpig ett prosjekt: **test** (`tsekialrxuhrugscosgi`). Prod opprettes før byttet for gjengen (fase 9). PWA-ens database er bare kilde for import og skrives aldri til.

Endringer går slik (detaljer i [`sql/README.md`](sql/README.md)):

1. Ny nummerert fil i `sql/`, med kontrollspørringer nederst.
2. Thomas leser og godkjenner SQL-en. Uten godkjenning kjøres ingenting.
3. Kjøres på test, deretter kontrollspørringene.
4. Prøves i appen mot test.
5. Prod (når det finnes) først etter ny godkjenning.

Filen legges i en PR som andre endringer. Status i `sql/README.md` oppdateres når den er kjørt.

## Distribusjon

Xcode Cloud-workflowen «TestFlight fra main» arkiverer og sender til TestFlight ved hver endring på `main`. Oppsett og miljøvariabler står i [`docs/xcode-cloud.md`](docs/xcode-cloud.md), App Store-oppsettet i [`docs/app-store.md`](docs/app-store.md).
