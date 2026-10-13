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

### Runden, spill og regningen (agent D, `ui/runde`)
- **4.2 Føringen** er gjort i `RundeView`. Verktøylinja har «Lukk føringen» (pil ned), tittelen («Losby · runde 4», eller bare banen i en løs runde) og en undertittel som «Du fører for bås 2». ⋯-menyen har scorekortet ditt, reglene i runden (`RulesetSummarySection` i et ark), del og hent på nytt. Bytte markør og avbryt finnes ikke som handlinger i appen, så de er ikke med. Fanelinja skjules mens føringen står åpen, og systemets tilbakeknapp er byttet med pil ned. Segmentene er «Føring | Stilling | Spill · N». «Spill i runden · N» fikk ikke plass i tre like segmenter på 375 pt, så teksten er forkortet. N teller matcher, konkurranser og spill på runden. Stilling viser «Bayen nå». Når runden avgjøres hull for hull, vises matchene der. Inviter, Del regningen, Avslutt og «Følg medspillerne» ligger nederst under Stilling. Hero-kortet viser hullnummeret i 60 pt, par og meter, indeksen, en gull-pille for nærmest pinnen eller longest drive, og ‹ › på 44 pt. Lagringen er flyttet fra kortet til bunnlinja i glass, med synkstatus og «Lagre hull 7 og gå videre →». Det som sendes, er uendret. Spillene hentes nå i `RundeView`, så segmentet vet hvor mange de er. Wolf-valget står i «Spill» med knapper på 48 pt. Hullkort-prøven er nå den ekte `RundeView` med skissens data (`SpillSamples.foeringModel`).
- **V15** er gjort. Hullbrikkene (`DDHoleChip`) er 44 × 44 pt i en rullbar rad som ruller til hullet du står på. `DDHoleTick` er beholdt fordi `DesignCatalogView` bruker den. Hull med delvis føring har chip-bakgrunn og en skog-kant. Båsens hull har en strek under brikken.
- **V7** er gjort i føringen. Radene stables ved tilgjengelighetsstørrelser. Stepperen er ett element med label «Kåre, 4 slag», value «2 poeng» og adjustable action, og dobbelttrykk bekrefter tallet. Bunnlinja, segmentene og hero-kortet vokser bare til xxxL, og brikkene stopper på 64 pt, ellers tok de halve skjermen i AX3.
- **V8:** «Ny runde» lå allerede i `safeAreaInset`. Problemet var at det flytende glasskortet lot radene under synes halvveis. Nå er det en tett bunnlinje med hel bredde (`BottomActionBar`). «Del regningen» bruker den samme for «Åpne Vipps». Andre skjermer i Spill og Apen hadde ingen flytende knapper.
- **V14** er gjort, med ett avvik: knappen heter fortsatt «Åpne Vipps». Den åpner Vipps-appen, men sender ingen forespørsel, fordi private betalingsforespørsler krever bedriftsavtale. Kategori-chipsene brukte allerede `DDChoiceButtonStyle`. «Lagre og følg opp» er gjort sekundær, så gult bare står på hovedknappen.
- **P6:** «(deg)» i «Bayen nå», i sidepremien og i velgeren er byttet med `DDYouBadge`. I systemmenyen, der et merke ikke kan vises, er det et person-ikon. Kortet med bare deg heter «Ditt kort», ikke «DEG». I skjermbilde 15 fant jeg ikke «Thomas (deg)» i dagens kode.
- **V6:** spillpoengene er flyttet fra mono til sans, og statuspillen på spillkortene står under teksten så den ikke kuttes. Mono brukes fortsatt i invitasjonskodene og i seksjonsetikettene.
