# Golfapper: flyter Atten kan lære av

Research 10.10.2026. Kildene er stort sett App Store-tekster, hjelpesider og presse. Det finnes få uavhengige UX-tester, så detaljer om konkrete skjermbilder er markert (usikkert) der vi ikke har sett dem selv.

## Appene

**Squabbit (turnering/tur blant venner)**
- Invitasjon: arrangøren lager eventet én gang og deler én lenke eller QR i gruppechatten. Man kan bli med via lenke, kode eller QR, og i nettleser uten å installere appen.
- Føring: bare én person per flight trenger å føre. Resten følger med live. Scorer lagres lokalt og synkes når nettet er tilbake.
- Tavle: hver konkurranse (slagspill, skins, lagmatch, nærmest hull) har sin egen tavle inni samme event. Push ved ledelsesskifte (og ved birdie ifølge Golfbreaks).
- Sosialt: gruppechat ved siden av tavla. Scoringsøyeblikk postes automatisk, og man kan legge ved bilder. Morsom "sanntidsstatistikk": lengste par-rekke, beste på par 3, største sprekk.
- Gratis kjerne, "Host Pro" for arrangørfunksjoner.

**Golf GameBook**
- Live tavle for alt fra søndags-skins til egne Ryder Cup-oppsett ("Reds vs Blues"), og turneringer over én eller flere runder med opptil 72 spillere.
- WHS: spillehandicap justeres automatisk per bane og format.
- "Friends on course" viser hvem som spiller akkurat nå. Feed med likes og kommentarer på scorekort, merker (40+), egne utfordringer (flest birdies, flest runder).
- Delbar tavlelenke for tilskuere. Svakhet i anmeldelser: ikke-brukere må laste ned appen for å følge, og varslingskontrollen er dårlig.
- Apple Watch for føring og tavle.

**18Birdies**
- Opptil tre sidespill samtidig (skins, Nassau, Vegas, Wolf, match). Verdien per skin kan justeres. Appen gjør innsatsregnestykket.
- Føring på tre trykk fra GPS-skjermen (anmeldelse).
- Offentlige turneringer og ligaer: Community > Events > Create. Turneringen har et tidsvindu (1 dag til 1 uke), og man spiller når man vil i vinduet. Ligaen samler flere turneringer til én poengtavle for sesongen.
- Tavla viser plassering, avstand til toppen og hvem som klatrer. Spillerkortet har hull-for-hull, så du ser *hvordan* noen gikk forbi deg.
- Feed: når en venn blir med på eller fullfører et event, vises resultatet med lenke til tavla. Kan ha maks antall deltakere.

**Golf Genius (klubb- og ligaadministrasjon)**
- Arrangøren slår på mobilføring. Tavla går live når runden settes "In Progress". Arrangøren skrur av føringen etter hvert som kortene leveres, og "finaliserer" runden til slutt. Det tilsvarer Attens "lås runde".
- To tavlevisninger: TV-modus med autoscroll for klubbhuset, og en interaktiv visning for mobil. Begge har sammendrag og hull-for-hull. Alle formater i ett event (brutto, skins, netto bestball) kan følges side om side.
- Arrangøren kan føre for en hel flight fra appen.

**GolfBox / Gimmie / Mitt Golf (Norge)**
- GolfBox-appen: før score hull for hull, også for medspillere. Lever direkte, og handicapet justeres hvis klubben tillater det og markøren godkjenner. Følg live-resultater i egen og andre klubber.
- GolfBox live scoring krever ingen app: spilleren får SMS eller e-post med lenke og scorekode og fører i nettleseren.
- Gimmie (GLFR, GolfBox og NGF) beskrives som Golf-Norges offisielle app. Mitt Golf (GolfBox A/S) kom 10.11.2025. (Usikkert hvilken av dem som er hovedkanalen for score i dag.)
- Lærdom: norske golfere er vant til markør-godkjenning og at handicap er "ekte" bare via GolfBox.

**Trackman Golf-appen (simulator)**
- Arrangøren sender en invitasjonslenke til ligaen, og spillerne blir med i appen. Lag opprettes i appen, og vikarer er tillatt.
- Ligaer går over flere uker og kan ha flere spilltyper (banespill, nærmest hull, lengste drive) med egne poeng for hver.
- Turneringer opprettes av senteret i Trackman Portal: format (slagspill, stableford, netto), bane, oppsett, offentlig/privat, startavgift.
- Vennematch på tvers av steder: velg bane, tee, fasthet og vind.
- NEXT Golf Tour: tavleoppføringer kan spilles av som delt skjerm med sving og ballbane.

**GSPro / SGT (simulator)**
- Hvert event har brutto og netto, så alle nivåer kan delta. Tourene er delt etter slaglengde (WEB-tour under 250 yards, TIPS fra bakerste tee). Det er sesongpoeng på tvers av event.
- Klubbvert setter bane, greenhastighet, lengde, vind og gimme-sirkel. Erfaringen fra ligaer: sim-score blir ofte høyere, og det er lurt å sette tak på hullscore.

**PGA TOUR-appen (tavle-UX)**
- Favorittspillerens score oppdateres idet ballen går i hull. Trykk på en rad åpner "player shelf" med scorekort, profil og video. Man kan abonnere på varsler per favorittspiller.
- Scorekortet viser "play-by-play" og slagspor. TOURPulse lar deg følge en runde på nytt i etterkant.

**Golf Pad (kort)**
- Når du åpner appen på eventdagen, spør den om du vil starte føring for dagens event. Valgfri bekreftelse før scoren postes til tavla, og rettinger oppdaterer tavla automatisk.

## Hva Atten bør ta etter (prioritert)

1. **Invitasjon:** Én lenke og QR per kveld/turnering som kan deles i gruppechat, med en nettleservisning som viser Tavla uten app. Det er den viktigste vekstmotoren hos Squabbit og GameBook, og anmeldere klager når tilskuere må installere.
2. **Runde/føring:** "Én fører per flight/bås", der de andre i gruppen bare følger med. Det passer simulatorbåser der én telefon ligger ved skjermen (Squabbit, Golf Genius).
3. **Runde/føring:** Offline først, med lokal lagring og synk når nettet er tilbake, og en tydelig "ikke synket"-indikator. Kjelleranlegg og baner har ofte dårlig dekning.
4. **Hjem:** Spør "Start føring for kveldens spilledag?" når appen åpnes på en dag brukeren har en planlagt runde (Golf Pad). Det fjerner navigering akkurat når man står på tee.
5. **Tavla:** Trykk på en rad åpner et ark med hull-for-hull-kort, så man ser hvor noen tok deg igjen. Vis "thru" og to-par/poeng ved siden av navnet (18Birdies, PGA TOUR).
6. **Tavla:** Separate faner per konkurranse i samme kveld (hovedspill, sidespill, nærmest hull, lag), i stedet for én blandet liste (Squabbit, Golf Genius).
7. **Hjem/feed:** Automatiske feed-hendelser for birdie, ledelsesskifte og fullført runde, med lenke til tavla, og push som brukeren kan styre per type. GameBook får kritikk for dårlige varslingsvalg.
8. **Arrangør:** Tydelig livssyklus for runden: Utkast > Åpen for føring > Live > Låst/Finalisert, med "lås flight" etter hvert som kortene er godkjent (Golf Genius).
9. **Arrangør/Tavla:** En TV-modus med autoscroll som senteret kan vise på skjermen i lobbyen eller båsen (Golf Genius). Det gjør Atten synlig for alle som er innom senteret.
10. **Turneringer:** Turneringer med tidsvindu (spill når du vil i uke X), med sesongpoeng i ligaen på tvers av kvelder. Det passer simulatorgjenger som ikke kan møtes samtidig (18Birdies, SGT).
11. **Spill/Turneringer:** Brutto og netto side om side som standard, og et valgfritt maks-tak per hull for simulator (SGT, Golf League Tracker).
12. **Spill:** Morsom kveldsstatistikk etter runden, som lengste par-rekke, største sprekk og beste på par 3. Det er billig å lage og gir mye prat (Squabbit).

## Hva vi gjør bedre allerede
- Atten er laget for "serie over mange kvelder" i en gjeng. Konkurrentene er enten enkeltrunde-apper (18Birdies, Hole19) eller tunge klubbverktøy (Golf Genius, GolfBox Tournament).
- Simulator og bane i samme modell, med grupper og båser. Trackman og SGT låser deg til egen plattform.
- Norsk språk og norske golfvaner (stableford, WHS) uten abonnement på kjernen. GameBook og Hole19 legger mye bak betalingsmur (usikkert hvor Attens prismodell ender).
- Påmelding med venteliste. Squabbit og 18Birdies har maks antall deltakere, men vi fant ingen venteliste hos dem (usikkert).

## Kilder
- Squabbit, App Store: https://apps.apple.com/us/app/-/id1556538444
- Golfbreaks om Squabbit: https://www.golfbreaks.com/en-us/inspiration/articles/every-golf-trip-scorekeeper/
- Squabbit, Capterra: https://www.capterra.com/p/10045332/Squabbit/
- Golf GameBook, App Store: https://apps.apple.com/app/id409307935
- GameBook, tavlelenker: https://www.prnewswire.co.uk/news-releases/grow-golf-gamebook-introduces-live-leaderboard-links-for-every-golfer-144541285.html
- 18Birdies, offentlige turneringer og ligaer: https://18birdies.com/clubhouse/play/introducing-public-tournaments-and-leagues
- 18Birdies Tournament+: https://18birdies.com/clubhouse/18birdies-news/tournament-18birdies-brings-innovation-golf-tournaments
- 18Birdies-anmeldelse: https://pluggedingolf.com/?p=37423
- Golf Genius, manager-app: https://intercom.help/tournament-management/en/articles/10777399-using-the-mobile-and-ipad-apps-managers
- GolfBox App: https://apps.apple.com/app/id606152821
- GolfBox live scoring: https://golfbusinessnews.com/news/new-products/golfbox-announces-bonus-live-scoring-module/
- Gimmie: https://apps.apple.com/no/app/gimmie/id6444337000?l=nb
- Trackman Tournaments: https://support.trackmangolf.com/hc/en-us/articles/37391282658331-Tournaments-What-are-Trackman-Tournaments
- Trackman Leagues: https://support.trackmangolf.com/hc/en-us/articles/43687786100507-Tournaments-Trackman-Leagues
- Trackman online play: https://shopindoorgolf.com/blogs/helpful-articles-videos/trackman-tournaments-and-online-play
- SGT/GSPro: https://shop.carlofet.com/simulator-golf-tour og https://carlofet.com/blog/how-to-start-an-indoor-golf-league
- Golf League Tracker, sim: https://www.golfleaguetracker.com/glthome/cms/blog/simulator-standard
- PGA TOUR-appen: https://www.golfdigest.com/story/new-pga-tour-app-website-redesign og https://www.thememorialtournament.com/media/pga-tour-app
- Golf Pad, live posting: https://support.golfpadgps.com/support/solutions/articles/6000246311-posting-real-time-scores-using-the-golf-pad-app

Ikke dekket: Arccos, TheGrint, Golfshot og Hole19. Vi fant ingen konkrete UX-kilder om flytene deres.
