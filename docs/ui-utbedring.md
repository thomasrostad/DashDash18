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

### Tavla og statistikk (agent B, `ui/tavla`)
- **V4** er gjort. Tabellen har kolonnene plass (34 pt), spiller, bevegelse og poeng (28 pt, fast kolonne). Delt plass vises som «1=». Bevegelsen regnes med samme regelmotor på rundene før siste kveld (to runder samme dato er én kveld). Den vises fra andre kveld og bare på Tavla, fordi det koster en ekstra utregning av sesongen (`comparesPrevious`). Konkurransene under `CompetitionDetailView` og `TableChangeLogger` regner den ikke. Hero-kortet vises når de øverste står likt på poeng. Teksten kommer fra regelsettet: playoff, skilletegn («skiller hulldifferanse, så stablefordsummen») eller delt seier. Golfgutu skiller på hulldifferanse, så der får de to ulik plass, men kortet vises likevel. Fremdriften er «Kveld 5 av 7 spilt · Neste: onsdag 21. oktober», med neste kveld fra `events`. Segmentet «Tabell | Alle runder | Statistikk» erstatter knappen «Alle runder». Statistikk-segmentet viser turneringens tall (beste runde, flest birdies, Longest drive) og lenker til din egen `StatsView`. Avvik: konkurransevalget ble en nedtrekkspille rett under tittelen, ikke `toolbarTitleMenu`. Den viser ingen pil ved stor tittel, så valget ble usynlig.
- **V5** er gjort uten endringer i prosjektfilen. `PushAppDelegate` (appens `UIApplicationDelegateAdaptor`) gir rollen `windowExternalDisplayNonInteractive` en egen scene (`TavlaExternalSceneDelegate`) med TV-tavla. Den viser tabellen Tavla sist viste, henter den på nytt hvert 30. sekund og holder telefonen våken mens TV-en er koblet til. TV-visningen har fått «Live»-merke (lime), sterkere kontrast og «1=». Knappen «TV» (AirPlay-ikon) gir de samme valgene som før. Den eksterne scenen er ikke prøvd på en ekte TV. Det kan bare testes i Simulator-menyen (I/O → External Displays) eller med AirPlay.
- **P3** er gjort. «Slik telles det» er et ark fra ⓘ i verktøylinja.
- **P5** er gjort. `DDStatSummary` viser ett hovedtall og resten som liste, i profilen og i statistikken (også per par-type og fairway/green). Tall uten data vises ikke (V13). «Lengste drive» heter nå «Longest drive», som i PWA-en. `DDStatTile` står igjen bare for designkatalogen.
- **V10:** appen satte allerede nb_NO på roten (`ddAppStyle`), og skjermprøvene får den også. Det engelske «May 26» kom fra før den rettingen. Datoaksen har nå språket i selve formatet (`StatsFormat.monthAxis`) og viser bare måneden. Den har luft i endene, så siste etikett ikke kuttes. Forklaringen står over grafen. Linjene bruker `ddForestInk`, fordi skog var usynlig i mørk modus.
- **V6** for disse skjermene er gjort: verdier og status ved seksjonsetikettene er sans 13 (`.ddStatus`). Mono brukes bare i etiketter og kolonneoverskrifter.
- Nye skjermprøver: `tavlastatistikk` og `stattrend`.
