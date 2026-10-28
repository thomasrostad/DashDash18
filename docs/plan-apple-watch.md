# Apple Watch: plan

28.10.2026. Grunnlag: ønske fra Thomas om en egen klokkeapp. Kartlagt mot appen (`DashDash18/`, ca. 80 000 linjer Swift), regelmotoren (`Packages/GolfgutuCore`, ca. 9 000 linjer), widgetene og Live Activity (`DashDash18Widgets/`) og utboksen (`DashDash18/Outbox/`).

**Status:** plan, ingen kode skrevet. Står i ROADMAP som «etter v1». Android-planen står i [`plan-android.md`](plan-android.md) og deler steg 0 med denne.

## Mål

Spilleren og markøren skal kunne føre slag på klokka uten å ta opp telefonen, og se hvordan det står. Telefonen er fortsatt der alt annet skjer: oppsett, påmelding, Tavla i detalj, admin og det sosiale.

## Hva finnes i dag

- **Live Activity** under runden vises i Smart Stack på klokka (siden 17.10.2026): hull, egen score og stillingen i båsen. Fra 1.0.4 viser den «15 slag» i slagspill.
- **Ingen klokkeapp.** Live Activity-en kan ikke føre slag.
- **Regelmotoren** (GolfgutuCore) er ren Swift uten SwiftUI og nettverk, og kan brukes på klokka som den er.
- **Rundelogikken** (`ForingLogic`, `RoundSnapshot`, `MarkerConflicts`, `MatchLogic`, `SidePrizeLogic`, deler av `GamesLogic`) ligger i appmålet, ikke i pakken. Den er ren Swift, men klokka kan ikke bruke den før den flyttes.
- **Utboksen** lagrer hvert hull før det sendes, og sender når nettet er tilbake. Den gjelder telefonen.

## Hva klokkeappen gjør (første versjon)

| Skjerm | Innhold |
|---|---|
| **Runden nå** | Starter av seg selv når du har en aktiv runde på telefonen. Viser hull, par, indeks og slag mottatt. |
| **Føre hullet** | Én rad per spiller du fører for (deg selv, eller hele båsen som markør). Digital Crown og +/− setter slag. Resultatet vises etter formen («2 p · netto par», «brutto bogey», «tak 6 slag»), med samme tekst som hullkortet på telefonen. Taket i maksimumscore gjelder også her. |
| **Neste hull** | Sveip eller dobbelttrykk med fingrene («double tap») sender hullet og går videre. Vibrasjon bekrefter. |
| **Bayen nå** | Stillingen i båsen etter formen, med samme rekkefølge og tekst som på telefonen. Match: «2 opp etter 11». |
| **Ikke sendt** | Viser «3 hull venter på telefonen» når hull ikke er kommet fram, og konflikt når markøren og spilleren har ført ulikt. Konflikten løses på telefonen. |
| **Tavla** | Topp 3 og din plass, bare til å se på. |
| **Komplikasjoner** | På urskiven: neste kveld, og score og hull under runden. |

Ikke med i første versjon: oppsett av runder, påmelding, admin, veddemål og tips, feed, kommentarer og GPS.

## Hvordan klokka får og sender data

**Anbefaling: klokka snakker med telefonen (WatchConnectivity), og telefonen sender til Supabase gjennom utboksen som i dag.**

- Telefonen sender runden (`RoundSnapshot`: spillere, hull, handicap, form og ført score) til klokka når runden starter og når noe endres.
- Klokka sender hvert ført hull til telefonen. Telefonen legger det i utboksen, og da gjelder alt utboksen allerede gjør: lagring før sending, nye forsøk uten nett, avvisning og markørkonflikter.
- Når klokka sender et hull, vekker iOS appen på telefonen i bakgrunnen, også når den ikke er åpen.
- Når telefonen ikke er i nærheten, legger klokka hullene i sin egen kø og sender dem når telefonen er tilbake. Klokka viser «venter på telefonen».

Hvorfor ikke la klokka snakke med Supabase selv: da trenger klokka egen innlogging, egen utboks og egen konfliktløsning. Det gir to steder hvor samme hull kan sendes, og telefonen er nesten alltid i bagen. Klokka kan få direkte nett senere hvis det trengs for runder uten telefon (se «Senere»).

## Steg

### Steg 0 – Flytt rundelogikken ut av appen *(felles med Android)*

Flytt den rene rundelogikken fra appmålet til en egen pakke ved siden av GolfgutuCore, for eksempel `Packages/AttenRound`: hullkortet (`HoleCard`), `RoundGame`, `RoundSnapshot`, scorekortet, «Bayen nå», markørkonflikter, match og sidepremier. Visningene blir igjen i appen.

- **Hvorfor:** klokka (og Android, se den planen) trenger nøyaktig samme svar som telefonen. Kopier ville drive fra hverandre.
- **Ferdig når:** appen bygger, alle app-testene er grønne, og testene for den flyttede logikken kjører med `swift test` i pakken.
- **Risiko:** noen typer er merket `@MainActor` eller bruker app-ting (`Observable`, SwiftData). De må deles i en ren del og en app-del. Ingen endring i oppførsel.
- **Omfang:** 2–4 økter.

### Steg 1 – Klokkemålet

- Nytt watchOS-mål i Xcode med Xcode MCP (`XcodeNewTarget`) eller av Thomas i Xcode. `project.pbxproj` redigeres ikke for hånd.
- Bundle-id `com.dashdash18.app.watchkitapp`. Følger med iOS-appen, i samme App Store-post.
- watchOS 26 som minimum, i takt med iOS 26.
- Kobler GolfgutuCore og AttenRound til målet. Fargene og typografien fra `DesignSystem` deles der det går (farger og navn), ellers egne klokkevarianter.
- Xcode Cloud: begge workflowene må arkivere med klokkemålet. Sjekk at bygget går gjennom «Prepare Build for App Store Connect».
- **Ferdig når:** en tom klokkeapp installeres med appen fra TestFlight.
- **Omfang:** 1 økt.

### Steg 2 – Synk med telefonen

- `WatchSession` på begge sider (WatchConnectivity). Telefonen sender gjeldende runde som «application context» (siste tilstand vinner) og svarer på hull fra klokka.
- Hull fra klokka går inn i utboksen på telefonen med samme `HoleSubmission` som hullkortet bruker. Ingen ny vei til serveren.
- Klokka har en liten kø for hull telefonen ikke har bekreftet.
- Tester: kø og bekreftelse testes som ren logikk (Swift Testing), med en falsk forbindelse.
- **Ferdig når:** et hull ført på klokka står på telefonen og i Supabase test, også når telefonappen er lukket, og når telefonen var utenfor rekkevidde mens hullet ble ført.
- **Omfang:** 2–3 økter.

### Steg 3 – Føring og stilling

- Skjermene i tabellen over: Runden nå, Føre hullet, Neste hull, Bayen nå, Ikke sendt.
- Tekst og tall kommer fra AttenRound, de samme som hullkortet på telefonen: `formText`, `maxStrokes`, slag mottatt og `resultText`.
- Digital Crown, dobbelttrykk med fingrene for «send og neste», og vibrasjon ved sendt og feil.
- Alltid-på-skjerm: dempet visning som viser hull og score uten animasjon.
- Tilgjengelighet: VoiceOver-tekst som på telefonen (`StrokeAccessibility`), og store tekststørrelser.
- **Ferdig når:** en hel runde i simulatoren (iPhone 18 Pro og Watch-simulator) kan føres fra klokka i stableford, slagspill netto og maksimumscore, og «Bayen nå» er lik på klokka og telefonen.
- **Omfang:** 3–4 økter.

### Steg 4 – Tavla og komplikasjoner

- Tavla: topp 3 og din plass, fra telefonen.
- Komplikasjoner (WidgetKit på klokka): neste kveld, og hull og score under runden. Live Activity-en i Smart Stack beholdes. Trykk på den åpner klokkeappen.
- **Ferdig når:** komplikasjonene oppdateres når runden endres, og viser riktig tekst når du ikke har noen runde.
- **Omfang:** 1–2 økter.

### Steg 5 – Ut i App Store

- Skjermbilder for klokka i App Store Connect (kreves når appen har klokkemål).
- Teksten i App Store nevner klokka.
- Personvern: ingen nye datatyper. Klokka samler ikke inn noe telefonen ikke allerede gjør.
- TestFlight med gjengen én kveld før innsending.
- **Omfang:** 1 økt.

**Totalt: 10–15 økter, inkludert steg 0.**

## Det du må gjøre

- Teste på din egen klokke i TestFlight. Simulatoren viser ikke hvordan Digital Crown og dobbelttrykk kjennes ute.
- Trykke «Add for Review» når klokkeversjonen er klar.

Ingen endringer i Supabase. Ingen nye avhengigheter (WatchConnectivity og WidgetKit er Apples egne).

## Risiko

- **Steg 0 tar lengre tid enn anslått** hvis rundelogikken henger tettere sammen med visningene enn den ser ut til. Da sier jeg fra før jeg fortsetter.
- **Klokka mister forbindelsen** midt i en runde. Køen på klokka tar seg av det, og «venter på telefonen» sier hva som skjer.
- **Små skjermer.** Markøren fører for opptil fire spillere. Det må testes på 41 mm, ikke bare på den største klokka.

## Senere

- Direkte nett fra klokka for runder uten telefon (egen innlogging overført fra telefonen, og egen utboks).
- Treningsøkt «Golf» som holder appen fremme og teller kalorier (krever HealthKit-tillatelse).
- GPS og avstand til green, når appen får banegeometri (B11).
