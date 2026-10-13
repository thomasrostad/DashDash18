# UI-utbedring (oktober 2026)

Gjennomføring av utbedringsplanen for Atten, som bygger på en gjennomgang av 46 skjermbilder i lys og 46 i mørk modus. Gjennomgangen ble gjort uten tilgang til koden, så planen inneholder antakelser som ikke stemmer. Avvikene står under hvert punkt.

Skjermbildene tas med skjermprøvene i `DesignScreenSamples` (`-DDDesignScreen <navn>`).

## Kart: skjermbilde → kode

| Skjermbilde | Visning |
|---|---|
| `hullkort`, `losrunde` | `HullkortView` + `HullprikkerView` (`Features/Runde/`), logikk i `ForingLogic.swift` (`RoundGame.card`), modell `RundeModel` |
| `feiring` | `FeiringOverlay`, `RoundGame.celebration` |
| `hjem`, `hjemarrangor` | `HjemFeedView`, kortene i `HjemTopCards.swift` (`HjemLiveCard`, `HjemEveningCard`) |
| `tavla`, `tavlaferdig`, `tavlastableford` | `TavlaList` (`Features/Tavla/TavlaView.swift`) |
| `konktavla`, `konkcup` | `TavlaCompetitions`, `CompetitionDetailView` |
| `losspill`, `losny` | `SpillView`, `NyRundeView` |
| `statoversikt`, `profil` | `StatsView`, `PlayerProfileView` |
| `apenregning` | `BillSplitView` |
| `velkommen` | `ClubOnboardingView` + `ClubCodeEntrySection` |
| `arrangor`, `arrangorpagar` | `AdminHubView` (`AdminHubContent`) |
| `kvelden` | `KveldenView` |
| `startliste`, `pamelding` | `StartListView`, `CompetitionSignupCard` |
| `spillresultat` | `SpillSeksjon` (`GamesViews.swift`) |
| `varsler` | `VarslerContent` |

Designsystemet ligger i `DashDash18/DesignSystem/`. Farger er `DDToken` i `DDPalette.swift`, og kontrasten testes i `DesignSystemTests`. Knapper ligger i `DDButtons.swift` og fonter i `DDFonts.swift`. Den grønne topplinja var `ddNavigationChrome()`, som brukes 127 steder.

## Status per punkt

### Fase 1: designsystemet
- **1.1 Fargetokens.** Verdiene er byttet i `DDToken`, ikke flyttet til en Asset Catalog. Tokens i kode kan kontrasttestes, noe en Asset Catalog ikke kan. «Øk kontrast» er dekket med `highContrastValues` for tekst og strek. Svarte flater er fjernet: stat-kortene tegnes som hero. Valgt tilstand har fått egne tokens (`selected`, `selectedInk`), fordi skog på mørk bakgrunn ga 1,2:1.
- **1.2 Scoreskala.** Egne verdier i mørk modus. `ScoreBadge` gir form etter brutto og farge etter netto. Formen brukes foreløpig der badge-en er tatt i bruk; se fase 3 for resten.
- **1.3 Knappestiler.** `DDButtonKind` beholdes, så de rundt 200 kallene ikke måtte skrives om, men alle klasser tegnes som en av fire stiler: hoved, sekundær, tekst eller destruktiv. «Penger» tegnes som hoved og «gull» som sekundær. Deaktivert er 40 % opasitet. Valgt er skog med hake.
- **1.4 Typografi.** Brødtekst er 17, slagtall 40 og mono minst 11. Piller og status bruker sans 13 medium. Alle `Font.custom` hadde allerede `relativeTo`.
- **1.5 Komponenter.** `ScoreBadge`, `DDYouBadge` og stepper på 52 pt med `@ScaledMetric` er laget. `DDSectionLabel` fantes allerede. `DDPill` er status-pillen.

### Fase 2: kritisk
- **K1** er gjort. Lagringen sendte allerede par for urørte rader; det var kortet som krevde bekreftelse. Merk at dette fjerner PWA-ens sikring om at markøren må se på hver rad.
- **K2** var en feil i skjermprøven. Den ekte feiringen leser hull og par fra hullet som lagres. Prøven er rettet, og nye tester er lagt til.
- **K3** er gjort: systemets glass, titler og ikoner i skog, og «Lagre» i tonet glass.
- **K4** er gjort. Knappen heter nå «Har du en kode?», og «Bli med» er aktiv bare med gyldig kode. «Lim inn» er systemets `PasteButton`, som følger telefonens språk; en egen knapp ville spurt om tilgang til utklippstavla hver gang.
- **K5:** fanelinja med `Tab`-API og én `NavigationStack` per fane fantes allerede. Den manglet bare i skjermprøvene.
- **K6:** køen for føring uten nett fantes allerede (SwiftData, overlever omstart, nyeste vinner). Statuslinja er lagt til. Konfliktarket for to markører er ikke laget: serveren lagrer bare siste verdi (`updated_by`, `updated_at`), så appen ser ikke den andre markørens tall. Det krever en endring i skjemaet, og den må godkjennes først.

### Arrangør (agent C, branch `ui/arrangor`)
- **V12 og 4.4** er gjort i `AdminHubView` med nye `TonightLive.swift` (logikk), `TonightLiveModel.swift` (henting) og `TonightViews.swift`. Når kvelden er i dag, heter siden «I kveld», med dato, tid og sted som undertittel. Øverst står stegstripene, så rundekortet, påmeldingen, sidepremiene og «Før Ferdig». Kommende og tidligere kvelder står under. «Inviter spillere» er en egen knapp i verktøylinja. ⋯-menyen har «Ny kveld», «Lag serie» og «Ny turnering», og under dem oppsettet: Turneringen, Troppen, Banene, Klubben, Regler og Roller, hver bare med rettighet. «Kom i gang» er uendret.
  - Synkstatus regnes fra `hole_scores.updated_at`, ellers `recorded_at`, for den siste scoren i båsen. Kommer det ikke noe nytt på 15 minutter (`TonightLive.staleMinutes`), står linja i rust. Uten scorer regnes tiden fra starttiden. Uten noe tidspunkt står det ingen linje. Scorene hentes hvert 30. sekund mens siden vises; ingen realtime-kanal.
  - Starttid og funksjonær kommer fra startlista (sql/032) når den finnes. Ellers brukes rundens tee-tid, og ingen funksjonær vises. «Pulje 2» fra skissen vises ikke: puljen hører til runden, ikke båsen.
  - «Registrer» på sidepremiene åpner runden. Innmeldingen skjer på premiehullet i føringen, og arrangørsiden har ingen egen registreringsflyt. Status er antall innmeldte, ikke lederen, for å unngå å regne sidepremieregler i visningen.
  - «Vis live-tavla på TV» viser den eksisterende `TavlaTVView` i fullskjerm, med egen `TavlaModel` som følger scorene. Den egne AirPlay-scenen (V5) er ikke en del av dette punktet.
  - Stegrekka er segmentstriper overalt der den brukes, også på Kvelden og på kortet for neste kveld. Ferdige steg er skog med hake, nåværende er lime med «Spilles nå». Lime på krem har lav kontrast som grafikk, men teksten under bærer informasjonen.
  - Skjermprøven `arrangorpagar` har fire båser à tre: to i gang (synket og rust, den ene med funksjonær) og to som starter senere.
- **P3** er gjort. «Alle reglene i detalj» (den store forklaringen i lista) er fjernet. Det samme står nå i et ark bak ⓘ i verktøylinja, i «Turneringen» og i «Regler».
- **V13** er gjort for Kveldene (ingen kvelder: «Ny kveld»), Runder («Til kveldene») og Banene («Ny bane», pluss feiltilstand med «Prøv igjen» og lasting med tekst). Runder og Kvelden hadde allerede lasting og feil.
- **V8:** Arrangørskjermene hadde ingen flytende knapper som dekket innhold. Hurtigstarten brukte allerede `safeAreaInset`. Kvitteringen i Regler er flyttet fra overlegg til `safeAreaInset`.
- **V6:** Arrangørskjermene bruker ikke mono til status. Det gjenstående er seksjonsetikettene (`DDHeader`) og klubbkoden, der mono er valgt med vilje. Ny status bruker `.ddStatus`.
- **V3 (startliste):** sier «bås» eller «flight» etter rundens sted, og «gruppe» er borte. **P6 (Troppen):** «(deg)» er byttet med `DDYouBadge`.
