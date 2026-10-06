# DashDash18

Native iOS-klient (SwiftUI, iOS 26+, Swift Testing) for GolfGutu Invitational.

## Fasit

- `referanse/golfgutu-pwa/` er fasit for funksjonalitet og regler. `referanse/golfgutu-pwa/README.md` er i praksis spesifikasjonen.
- Regelmotoren ligger i `referanse/golfgutu-pwa/db-nytt.js`. UI-flyt ligger i `app-nytt.js`. Skjema og RLS ligger i `sql/`.
- Der README og kode er uenige, vinner koden som faktisk kjører (`db-nytt.js`). Si fra om avviket.
- `SPEC.md` er en tidlig kartlegging. Når den avviker fra denne filen, gjelder denne filen.

## Backend

- Eksisterende Supabase-database. Bruk `supabase-swift`.
- **Test-prosjektet først.** Prod rører vi ikke før brukeren eksplisitt sier det.
- iOS-appen og PWA-en brukes samtidig mot samme database. Appen må derfor følge PWA-ens kontrakt: samme tabeller, kolonner, verdier og skrivemønster.
- RLS er eneste tilgangskontroll. Anta at en skrivning kan feile stille (PostgREST skiller ikke «RLS stoppet deg» fra «ingen rader»). Sjekk rader tilbake.
- Ingen hemmeligheter i repoet. Kun publishable key i klienten. Service-role-nøkkel skal aldri inn i appen.

## Paritet med PWA-en (viktigst)

All spillogikk må gi **nøyaktig samme resultat** som `db-nytt.js`. Gjelder blant annet:

- poeng og stableford, slagfordeling per hull (stroke index, 9 vs 18 hull)
- WHS banehandicap, andeler, seedingsgrupper, lagshandicap, avrunding
- konkurranseformer og matchspill, trekant, avkorting
- jakketabell og tiebreak
- veddemålsoppgjør, poster/saldo og oppgjør, nettoing, avrunding av beløp

Arbeidsmåte:

- Les den aktuelle funksjonen i `db-nytt.js` før du implementerer den. Gjenskap oppførselen, ikke koden. Skriv idiomatisk Swift.
- Skriv testen først, med forventede verdier utledet fra `db-nytt.js` (eller fra PWA-ens egne tester i `referanse/golfgutu-pwa/tests/`). Ikke gjett tall.
- Kantfall teller: avrunding, 9-hullsrunder, `hcp_extern`, seedede spillere, lag, uavgjort.
- Hold spillogikk i rene Swift-typer uten SwiftUI- og nettverksavhengighet, slik at den kan testes isolert og senere deles med Watch/widgets.
- Ikke lagre avledede verdier annerledes enn PWA-en. Skriver appen `round_points`, `poster` e.l., må formatet være identisk med det PWA-en skriver.

## Regler

- **Aldri rediger `.xcodeproj` direkte** (heller ikke `project.pbxproj`). Legg til og flytt filer via Xcode-verktøyene (MCP), eller be brukeren gjøre det i Xcode.
- **Aldri endre noe i `referanse/`.**
- **Ingen endringer i databasen uten at brukeren har godkjent SQL-en.** Det gjelder skjema, policies, funksjoner, triggere og data. Vis SQL-en, vent på godkjenning, kjør først mot test. Les-spørringer er greit.
- **Bygg etter hver endring.** Bruk `BuildProject` (Xcode MCP). Fiks feil og advarsler før du går videre.
- **Små steg.** Én avgrenset endring om gangen.

## Arbeidsregler (ROADMAP)

- Les `ROADMAP.md` ved starten av hver økt og si hvilken fase og oppgave vi er på.
- Jobb på én oppgave om gangen. Bygg og kjør testene før du sier at noe er ferdig.
- Kryss av oppgaven og oppdater STATUS i `ROADMAP.md` etter hver fullført oppgave, og commit med en melding som peker på fasen (f.eks. «Fase 2: stableford per hull»).
- Hvis noe viser seg å være større eller annerledes enn planlagt: oppdater planen og si fra, i stedet for å improvisere.
- Ingen endringer i Supabase uten at brukeren har godkjent SQL-en.

## Kode og stil

- Swift Concurrency (`async`/`await`, actors), `@Observable`. Apple-rammeverk først. Nye avhengigheter utover `supabase-swift` krever godkjenning.
- Hold views små. Logikk i modeller og tjenester.
- Følg stilen i omkringliggende kode.

## Tester

- Swift Testing (`import Testing`, `@Test`, `#expect`), ikke XCTest.
- Enhetstester i `DashDash18Tests/`, UI-tester i `DashDash18UITests/`.
- Kjør testene etter endringer i spillogikk.

## Språk

- Kommuniser og skriv UI-tekst på norsk (bokmål). Terminologi følger PWA-en (Kveld, Tavla, Jakkeracet, Arrangør, Markør, Bås).
- Kodeidentifikatorer på engelsk.

## Struktur

- `DashDash18/` – appkode
- `DashDash18Tests/`, `DashDash18UITests/`
- `DashDash18.xcodeproj`
- `referanse/` – skrivebeskyttet
- `SPEC.md` – kartlegging av PWA-en (utkast)
- `ROADMAP.md` – faser, status og beslutninger
