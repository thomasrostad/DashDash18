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

## Utrulling

- **Appen:** merget til `main` 14.10.2026 (PR #108). Xcode Cloud bygger «TestFlight fra main» og sender bygget til TestFlight. Delene (#102–#107) er lukket, fordi de er med i #108.
- **Lenkesiden** (`web/atten-lenker`, dashdash18.com): rullet ut med `wrangler deploy` 14.10.2026 (versjon `ad59b807`). Den viser «Har du en kode?» i stedet for «Bli med med kode».
- Ingen SQL eller endringer i Supabase.

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
- **K6:** køen for føring uten nett fantes allerede (SwiftData, overlever omstart, nyeste vinner). Statuslinja er lagt til. Konfliktarket for to markører er ikke laget: serveren lagrer bare siste verdi (`updated_by`, `updated_at`), så appen ser ikke den andre markørens tall. Forslaget til skjemaendring ligger i `sql/055_markorkonflikt.sql` og venter på godkjenning; arket i appen lages etterpå.

### Arrangør (V12, 4.4, P3, V13, V8, V6)
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

### Hjem og Varsler (V1, V2, 4.1, P2, P4, P6, V13)
- **V1** er gjort. Runden som pågår er `DDLiveRoundBar` i `tabViewBottomAccessory` i `RootView` og `FriendsRootView`, med `.tabBarMinimizeBehavior(.onScrollDown)`. Trykk åpner føringen på Hjem (klubbrunde via `HjemRouter.showRound`, løs runde via `showLooseRound`). Flere runder: den første, og «+1» (VoiceOver: «+1 runde til») åpner en meny. Arrangøren som ikke spiller får «Følg» og «Bjørn leder med 23 p». Uten klubb henter `LiveRoundsModel` de løse rundene hvert minutt, og baren åpner runden i Spill-fanen. Avvik: `tabViewBottomAccessory(isEnabled:)` finnes først i iOS 26.1, og på 26.0 kan tilbehøret ikke skrus av. Der står baren øverst i feeden i stedet. Føringen (`RundeView`, `LooseRoundScreen`) skjuler fanelinja og baren, som i 4.2. «Siden sist»-heroen, flisene og hele oppsummeringsmodellen (`HomeSummaryBuilder`, `summaryPhrase`) er fjernet.
- **V2** er gjort. «Neste kveld» er hero øverst med svaret som segmenter på 44 pt: «Kommer · Usikker · Kommer ikke». Usikker er beholdt som tredje segment, siden domenet har det. Valgt er krem med skogtekst, fordi skog på hero ikke synes (nytt kontrastpar «Valgt svar på hero»). «Angre» er erstattet av fristen fra `events`-innstillingene (sql/045): avmeldingsfristen når du kommer, ellers påmeldingsfristen. Uten frist står «Du kan endre svaret når som helst.» Angre-vinduet på 8 sekunder i `KveldModel` virker fortsatt. Ventelisteplassen vises i stedet for fristen når du står der. Arrangøren har en egen rad under kortet. Tråd og tips står under kortet, ikke i det.
- **4.1:** klubbvalget er en meny i verktøylinja på Hjem når du er aktiv i flere klubber (samme `ClubModel.select` som «Bytt klubb» på Deg). Kildepillene er nøytrale chips. Tabellkortet har ▲/▼ (skog/rust) og «Deg»-merket. Bragden viser `ScoreBadge` med form og «Anders Berg slo eagle». Reaksjonene dine er valgt-tilstand (skog), ikke lime. Avvik: seksjonene heter fortsatt «I dag · I går · Tidligere», ikke «Siden sist».
- **P2:** rust-prikken er fjernet fra tidsstemplene på Hjem-kortene og fra «Runden pågår» (kortet finnes ikke lenger). I Varsler står den bare for ulest. Live er lime.
- **P4:** «Legg til reaksjon» er 44 × 44 pt. Brikkene er 36 pt med 44 pt trykkflate. Langt trykk på feed-kortene ga allerede reaksjonsvalget.
- **P6:** «(deg)» i kommentarene er byttet til `DDYouBadge`.
- **V13:** den tomme feeden er `ContentUnavailableView` med «Start en runde» (Spill-fanen). Feiltilstanden bruker også `ContentUnavailableView` med «Prøv igjen». Varsler hadde allerede lasting, feil og tom tilstand. Avvik: «Har du en kode?» er ikke med, fordi Hjem bare finnes med klubb.
- Skjermprøve: `hjemflere` (to runder samtidig). Alle Hjem-prøvene står nå i fanelinja med baren over.

### Tavla og statistikk (V4, V5, 4.3, P3, P5, V10, V6)
- **V4** er gjort. Tabellen har kolonnene plass (34 pt), spiller, bevegelse og poeng (28 pt, fast kolonne). Delt plass vises som «1=». Bevegelsen regnes med samme regelmotor på rundene før siste kveld (to runder samme dato er én kveld). Den vises fra andre kveld på Tavla og (fra 15.10) i seriene, ligaene og morroturneringene under Turneringer. Ligaene regner tabellen uten siste runde (`LeagueStandings.previousPlaces`). `TableChangeLogger` regner den ikke. Hero-kortet vises når de øverste står likt på poeng. Teksten kommer fra regelsettet: playoff, skilletegn («skiller hulldifferanse, så stablefordsummen») eller delt seier. Golfgutu skiller på hulldifferanse, så der får de to ulik plass, men kortet vises likevel. Fremdriften er «Kveld 5 av 7 spilt · Neste: onsdag 21. oktober», med neste kveld fra `events`. Segmentet «Tabell | Alle runder | Statistikk» erstatter knappen «Alle runder». Statistikk-segmentet viser turneringens tall (beste runde, flest birdies, Longest drive) og lenker til din egen `StatsView`. Avvik: konkurransevalget ble en nedtrekkspille rett under tittelen, ikke `toolbarTitleMenu`. Den viser ingen pil ved stor tittel, så valget ble usynlig.
- **V5** er gjort uten endringer i prosjektfilen. `PushAppDelegate` (appens `UIApplicationDelegateAdaptor`) gir rollen `windowExternalDisplayNonInteractive` en egen scene (`TavlaExternalSceneDelegate`) med TV-tavla. Den viser tabellen Tavla sist viste, henter den på nytt hvert 30. sekund og holder telefonen våken mens TV-en er koblet til. TV-visningen har fått «Live»-merke (lime), sterkere kontrast og «1=». Knappen «TV» (AirPlay-ikon) gir de samme valgene som før. Den eksterne scenen er ikke prøvd på en ekte TV. Det kan bare testes i Simulator-menyen (I/O → External Displays) eller med AirPlay.
- **P3** er gjort. «Slik telles det» er et ark fra ⓘ i verktøylinja.
- **P5** er gjort. `DDStatSummary` viser ett hovedtall og resten som liste, i profilen og i statistikken (også per par-type og fairway/green). Tall uten data vises ikke (V13). «Lengste drive» heter nå «Longest drive», som i PWA-en. `DDStatTile` står igjen bare for designkatalogen.
- **V10:** appen satte allerede nb_NO på roten (`ddAppStyle`), og skjermprøvene får den også. Det engelske «May 26» kom fra før den rettingen. Datoaksen har nå språket i selve formatet (`StatsFormat.monthAxis`) og viser bare måneden. Den har luft i endene, så siste etikett ikke kuttes. Forklaringen står over grafen. Linjene bruker `ddForestInk`, fordi skog var usynlig i mørk modus.
- **V6** for disse skjermene er gjort: verdier og status ved seksjonsetikettene er sans 13 (`.ddStatus`). Mono brukes bare i etiketter og kolonneoverskrifter.
- Nye skjermprøver: `tavlastatistikk` og `stattrend`.

### Runden, spill og regningen (4.2, V15, V7, V8, V14, P6, V6)
- **4.2 Føringen** er gjort i `RundeView`. Verktøylinja har «Lukk føringen» (pil ned), tittelen («Losby · runde 4», eller bare banen i en løs runde) og en undertittel som «Du fører for bås 2». ⋯-menyen har scorekortet ditt, reglene i runden (`RulesetSummarySection` i et ark), del og hent på nytt. Bytte markør og avbryt finnes ikke som handlinger i appen, så de er ikke med. Fanelinja skjules mens føringen står åpen, og systemets tilbakeknapp er byttet med pil ned. Segmentene er «Føring | Stilling | Spill · N». «Spill i runden · N» fikk ikke plass i tre like segmenter på 375 pt, så teksten er forkortet. N teller matcher, konkurranser og spill på runden. Stilling viser «Bayen nå». Når runden avgjøres hull for hull, vises matchene der. Inviter, Del regningen, Avslutt og «Følg medspillerne» ligger nederst under Stilling. Hero-kortet viser hullnummeret i 60 pt, par og meter, indeksen, en gull-pille for nærmest pinnen eller longest drive, og ‹ › på 44 pt. Lagringen er flyttet fra kortet til bunnlinja i glass, med synkstatus og «Lagre hull 7 og gå videre →». Det som sendes, er uendret. Spillene hentes nå i `RundeView`, så segmentet vet hvor mange de er. Wolf-valget står i «Spill» med knapper på 48 pt. Hullkort-prøven er nå den ekte `RundeView` med skissens data (`SpillSamples.foeringModel`).
- **V15** er gjort. Hullbrikkene (`DDHoleChip`) er 44 × 44 pt i en rullbar rad som ruller til hullet du står på. `DDHoleTick` er beholdt fordi `DesignCatalogView` bruker den. Hull med delvis føring har chip-bakgrunn og en skog-kant. Båsens hull har en strek under brikken.
- **V7** er gjort i føringen. Radene stables ved tilgjengelighetsstørrelser. Stepperen er ett element med label «Kåre, 4 slag», value «2 poeng» og adjustable action, og dobbelttrykk bekrefter tallet. Bunnlinja, segmentene og hero-kortet vokser bare til xxxL, og brikkene stopper på 64 pt, ellers tok de halve skjermen i AX3.
- **V8:** «Ny runde» lå allerede i `safeAreaInset`. Problemet var at det flytende glasskortet lot radene under synes halvveis. Nå er det en tett bunnlinje med hel bredde (`BottomActionBar`). «Del regningen» bruker den samme for «Åpne Vipps». Andre skjermer i Spill og Apen hadde ingen flytende knapper.
- **V14** er gjort, med ett avvik: knappen heter fortsatt «Åpne Vipps». Den åpner Vipps-appen, men sender ingen forespørsel, fordi private betalingsforespørsler krever bedriftsavtale. Kategori-chipsene brukte allerede `DDChoiceButtonStyle`. «Lagre og følg opp» er gjort sekundær, så gult bare står på hovedknappen.
- **P6:** «(deg)» i «Bayen nå», i sidepremien og i velgeren er byttet med `DDYouBadge`. I systemmenyen, der et merke ikke kan vises, er det et person-ikon. Kortet med bare deg heter «Ditt kort», ikke «DEG». I skjermbilde 15 fant jeg ikke «Thomas (deg)» i dagens kode.
- **V6:** spillpoengene er flyttet fra mono til sans, og statuspillen på spillkortene står under teksten så den ikke kuttes. Mono brukes fortsatt i invitasjonskodene og i seksjonsetikettene.

### Resten (V9, V13, 0.3, 6, 7)
- **V9:** cup-treet viser én runde om gangen. Velgeren står over treet, og treet åpner på runden med din neste kamp.
- **V13:** `DDCardStyle.empty` har ikke lenger stiplet ramme; det gjelder 16 tomtilstander. Turneringer har tilstander for lasting og feil.
- **V3:**
  - «Har du en kode?» brukes overalt.
  - Startlista sier «bås» eller «flight», aldri begge.
  - «Longest drive» beholdes i stedet for planens «Lengste drive», fordi PWA-en bruker det og CLAUDE.md sier at terminologien følger PWA-en. Statistikken er rettet til «Longest drive».
  - «E-postkode» betyr innlogging med kode og beholdes.
  - «Tirsdagsligaen» og «Torsdagsligaen» finnes bare i skjermprøvene.
  - `Localizable.xcstrings` er ikke laget. Tekstene ligger inline og trekkes ut av Xcode (`SWIFT_EMIT_LOC_STRINGS`); en katalog bør lages i Xcode.
- **0.3:**
  - `RenderMatrixTests` dekker lys og mørk, L, xxxL og AX3, og 375, 402 og 440 pt.
  - Uten et bibliotek for snapshot-tester (nye avhengigheter krever godkjenning) sammenligner den ikke bilder.
  - Den visuelle kontrollen gjøres med skjermprøvene og `xcrun simctl`.
- **6.1:** Live Activity fantes allerede. Widgetfargene følger de nye tokenene.
- **6.3:** konfliktløsning mellom markører: SQL-forslaget `055_markorkonflikt.sql` venter på godkjenning (se K6).
- **7.1–7.3:** `UIDesignRequiresCompatibility` finnes ikke. Ingen egne materialer, og ingen ugjennomsiktige flater bak systemlinjene.
- **7.7:** iOS 27 SDK er ikke installert (Xcode 26.6, iOS 26.5).
- **Seksjonsetiketter** (`ddEyebrow`) vokser til xxxL, men ikke videre, så de ikke tar over skjermen i AX3.

### Kjente ting
- `SignupUndoTimerTests/nyttSvarOgAngreStopperVentingen` feilet av og til under tung last (fast pause på 200 ms). Rettet 15.10: den venter nå på hendelsene i stedet for på klokka.
- TV på ekstern skjerm (V5) er ikke prøvd med en ekte skjerm. Prøv med Simulator → I/O → External Displays, eller AirPlay mens Tavla er åpen.
