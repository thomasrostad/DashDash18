# DashDash18

Native iOS-app (SwiftUI, iOS 26+, Swift 6, Swift Testing) for GolfGutu Invitational. Erstatter GolfGutu-PWA-en. iPhone først, Android senere.

Appen heter **Atten** for brukerne (besluttet 08.10.2026). Repo, prosjekt, target, kodeidentifikatorer, bundle-id `com.dashdash18.app`, App Group, domenet dashdash18.com og URL-skjemaet `dashdash://` beholder DashDash-navnet. «Golfgutu Invitational» er klubben til gjengen, ikke appen.

## Fasit

- `referanse/golfgutu-pwa/` er fasit for funksjonalitet og regler. `referanse/golfgutu-pwa/README.md` er i praksis spesifikasjonen.
- Regelmotoren ligger i `referanse/golfgutu-pwa/db-nytt.js`. UI-flyt ligger i `app-nytt.js`. Skjema og RLS ligger i `sql/`.
- Der README og kode er uenige, vinner koden som faktisk kjører (`db-nytt.js`). Si fra om avviket.
- `SPEC.md` er en kartlegging av PWA-en. `ROADMAP.md` har beslutningene. Ved konflikt gjelder denne filen, så `ROADMAP.md`, så `SPEC.md`.

## Backend

- **Egen, ny Supabase** for appen. Bruk `supabase-swift`. To prosjekter: test og prod. **Test først.** Prod rører vi ikke før brukeren eksplisitt sier det.
- **PWA-ens database deles ikke.** Den brukes bare som kilde for import, og bare med lesing. Aldri skriv til den.
- Skjemaet er vårt eget og skal tåle dynamiske turneringer (se «Regelsett»). Lagre rådata (scorer, oppsett). Regn ut avledede verdier i stedet for å lagre dem, med mindre det er et bevisst valg.
- RLS er tilgangskontrollen. Sjekk rader tilbake ved skriving. Bruk RPC (én transaksjon) når en handling skriver flere rader.
- Ingen hemmeligheter i repoet. Kun publishable key i klienten. Service-role-nøkkel skal aldri inn i appen.

## Regelsett og paritet (viktigst)

- Turneringen styres av et **regelsett** som arrangøren setter i admin-panelet: antall spillere, antall kvelder, hva som teller, poengmodell, sidepremier, handicapmodell, former og så videre. **Ingenting skal være låst** til 12 spillere, 7 kvelder eller én måte å spille på.
- **Golfgutu-oppsettet** er regelsettet som gjengir PWA-ens regler. Med det oppsettet må all spillogikk gi **nøyaktig samme resultat** som `db-nytt.js`: stableford, slagfordeling, WHS, andeler, seeding, lagshandicap, avrunding, former, match, trekant, avkorting, jakketabell, tiebreak og tips.
- Andre regelsett er utvidelser. De skal ikke endre svaret for Golfgutu-oppsettet.
- **Ingen regelverdier i koden.** Poeng (seier, uavgjort, tap, sidepremier, trekant, stableford), hva som teller (kvelder eller matcher, alle eller beste N), handicap (modell, andel, seeding), former, grenser og tiebreak leses fra regelsettet. Faste tall finnes bare i Golfgutu-malen (`Ruleset.golfgutu`). Ny logikk som trenger en regelverdi, legger den til i regelsettet med Golfgutu-verdien som standard.

Arbeidsmåte:

- Les den aktuelle funksjonen i `db-nytt.js` før du implementerer den. Gjenskap oppførselen, ikke koden. Skriv idiomatisk Swift.
- Skriv testen først, med forventede verdier utledet fra `db-nytt.js` eller fra PWA-ens tester i `referanse/golfgutu-pwa/tests/`. Ikke gjett tall.
- Legg testtallene som språknøytrale fixtures (JSON), slik at de kan gjenbrukes av en Android- eller server-implementasjon senere.
- Kantfall teller: avrunding (`Math.round` = `floor(x + 0.5)`), 9-hullsrunder, ekstern handicap, seedede spillere, lag, uavgjort, norsk sortering.
- Hold spillogikken i rene Swift-typer uten SwiftUI- og nettverksavhengighet, slik at den kan testes isolert og deles med Watch, widgets og Live Activity.

## Regler

- **Aldri rediger `.xcodeproj` direkte** (heller ikke `project.pbxproj`). Legg til og flytt filer via Xcode-verktøyene (MCP), eller be brukeren gjøre det i Xcode.
- **Aldri endre noe i `referanse/`.**
- **Ingen endringer i Supabase uten at brukeren har godkjent det.** Det gjelder skjema, policies, funksjoner, triggere, data og konfig (for eksempel innloggingsmåter). Vis SQL-en, vent på godkjenning, kjør først mot test. Les-spørringer er greit.
- **Bygg etter hver endring.** Bruk `BuildProject` (Xcode MCP). Fiks feil og advarsler før du går videre. Henger Xcode-koblingen (har skjedd ved testkjøring), bruk `xcodebuild test -project DashDash18.xcodeproj -scheme DashDash18 -destination 'platform=iOS Simulator,name=iPhone 17 Pro'` med `-derivedDataPath ~/Library/Developer/Xcode/DerivedData/DashDash18-cli`. Aldri en byggemappe under `Documents` (iCloud legger metadata på filene, og kodesigneringen feiler).
- **Små steg.** Én avgrenset endring om gangen.

## Arbeidsregler (ROADMAP)

- Les `ROADMAP.md` ved starten av hver økt og si hvilken fase og oppgave vi er på.
- Jobb på én oppgave om gangen. Bygg og kjør testene før du sier at noe er ferdig.
- Kryss av oppgaven og oppdater STATUS i `ROADMAP.md` etter hver fullført oppgave, og commit med en melding som peker på fasen (f.eks. «Fase 2: stableford per hull»).
- Hvis noe viser seg å være større eller annerledes enn planlagt: oppdater planen og si fra, i stedet for å improvisere.
- Ingen endringer i Supabase uten at brukeren har godkjent SQL-en.
- Push til GitHub (`origin main`) etter hver commit.

## Kode og stil

- Swift Concurrency (`async`/`await`, actors), `@Observable`, SwiftData for lokal lagring. Apple-rammeverk først. Nye avhengigheter utover `supabase-swift` krever godkjenning.
- Hold views små. Logikk i modeller og tjenester.
- Følg stilen i omkringliggende kode.
- Appmålet er MainActor som standard. Rene typer som brukes fra tester eller bakgrunn merkes `nonisolated`, og extensions av dem må også være `nonisolated extension` (ellers krasjer de på kjøretid uten kompileringsfeil).

## Tester

- Swift Testing (`import Testing`, `@Test`, `#expect`), ikke XCTest.
- Regelmotor-tester i `Packages/GolfgutuCore/Tests/` (kjøres med `swift test`). App-tester i `DashDash18Tests/`, UI-tester i `DashDash18UITests/`.
- Kjør testene etter endringer i spillogikk.

## Språk

- Kommuniser og skriv UI-tekst på norsk (bokmål). Terminologi følger PWA-en (Kveld, Tavla, Jakkeracet, Arrangør, Markør, Bås).
- Kodeidentifikatorer på engelsk.

## Struktur

- `DashDash18/` – appkode
- `DashDash18Tests/`, `DashDash18UITests/`
- `DashDash18.xcodeproj`
- `Packages/GolfgutuCore/` – regelmotoren som lokal Swift-pakke (ren Swift, Swift Testing, JSON-fixtures). Testes med `swift test`
- `DashDash18/Config/Supabase-*.plist` – miljøkonfig, ikke i git
- `sql/` – migreringer for den nye Supabase-en, med status per fil i `sql/README.md`
- `referanse/` – skrivebeskyttet, ikke i git (inneholder nøkler)
- `SPEC.md` – kartlegging av PWA-en
- `ROADMAP.md` – faser, status og beslutninger
