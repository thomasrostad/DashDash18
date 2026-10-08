# Atten (DashDash18)

Native iOS-app for golfturneringer blant venner. Den erstatter GolfGutu-PWA-en som Golfgutu Invitational bruker i dag. Brukerne ser navnet **Atten**. Repo, Xcode-prosjekt, bundle-id (`com.dashdash18.app`), domenet dashdash18.com og URL-skjemaet `dashdash://` heter fortsatt DashDash18.

- SwiftUI, iOS 26+, Swift 6, Swift Testing
- Backend: egen Supabase via `supabase-swift` (foreløpig bare test, prod kommer)
- iPhone først, Android senere

## Dokumenter

| Fil | Hva |
|---|---|
| [`ROADMAP.md`](ROADMAP.md) | Faser, status og beslutninger. Start her for å se hvor prosjektet står |
| [`SPEC.md`](SPEC.md) | Kartlegging av PWA-en (funksjoner og regler) |
| [`CLAUDE.md`](CLAUDE.md) | Arbeidsregler for Claude Code. Gjelder også for mennesker |
| [`docs/gjoremal.md`](docs/gjoremal.md) | Det som må gjøres manuelt (App Store Connect, Supabase-konsoll, Google) |
| [`sql/README.md`](sql/README.md) | Databasemigreringer og status per fil (test og prod) |
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
sql/lokal/             Prøveskript for lokal kjøring av migreringene
supabase/functions/    Edge Functions: push-send, delete-account, verify-purchase
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

Edge Functions har Deno-tester ved siden av koden, for eksempel `deno test supabase/functions/push-send/`.

Med Golfgutu-oppsettet skal regelmotoren gi nøyaktig samme svar som PWA-ens `db-nytt.js`. Testtallene kommer fra PWA-ens tester eller er utledet fra koden, aldri gjettet.

## Arbeidsflyt: branch og PR

`main` er alltid det som er i TestFlight. Ingen pusher rett til `main`.

1. Lag en branch fra oppdatert `main`, én per oppgave:
   `fase-18/ny-turnering`, `fiks/tavla-sortering`, `docs/readme`.
2. Commit i små steg. Meldingen peker på fasen: «Fase 18: stableford-serie i Tavla».
3. Bygg og kjør testene før PR.
4. Åpne PR mot `main` (`gh pr create`). Beskriv hva som er endret, hvordan det er testet, og om det trengs SQL eller oppsett.
5. Thomas ser gjennom og merger (squash). Branchen slettes etter merge.

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
