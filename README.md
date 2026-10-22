# Atten (DashDash18)

Native iOS-app for golfturneringer blant venner. Den erstatter GolfGutu-PWA-en som Golfgutu Invitational bruker i dag. Brukerne ser navnet **Atten**. Repo, Xcode-prosjekt, bundle-id (`com.dashdash18.app`), domenet dashdash18.com og URL-skjemaet `dashdash://` heter fortsatt DashDash18.

- SwiftUI, iOS 26+, Swift 6, Swift Testing
- Backend: egen Supabase via `supabase-swift`, to prosjekter: test og Atten Prod
- iPhone først, Android senere

## Hva appen gjør nå

Status 20.10.2026. **Atten 1.0 er sendt til App Review** (build 181, gratis, bare iPhone, bare Norge). Prod-bygg går mot Atten Prod (`wxabhadvuzyrmndxpuza`) via Xcode Cloud-workflowen «App Store (prod)» med `ATTEN_ENVIRONMENT=prod`; bygg fra «TestFlight fra main» går fortsatt mot test. Gjengen er fortsatt på test. Sjekklisten står i [`docs/prod-sjekkliste.md`](docs/prod-sjekkliste.md). Detaljer per fase står i [`ROADMAP.md`](ROADMAP.md).

**Fanene.** Hjem · Spill · Tavla · Arrangør · Deg. «Arrangør» vises bare for arrangører i klubben (med sql/044: dem med minst én rettighet). Uten klubb har appen Spill og Deg.

| Område | Hva |
|---|---|
| Innlogging og start | Apple eller engangskode på e-post (med hint om å sjekke søppelpost når koden er sendt, og norske feilmeldinger, f.eks. «For mange forsøk – vent litt og prøv igjen»). Ny bruker kan spille med venner med en gang, eller bli med i/lage en klubb. Google er av til OAuth er satt opp |
| Invitasjon | Klubblenke `https://dashdash18.com/klubb/KODE` (universell lenke, åpner appen) og QR-kode. Lenker til klubb, løs runde, konkurranse og følging huskes på telefonen gjennom innloggingen (også om iOS lukker appen mens koden hentes i Mail) til de er brukt, eller i et døgn. Siden på dashdash18.com er Workeren i `web/atten-lenker/` |
| Hjem | Feed med aktivitet, «Pågår nå» (ett kort per runde du spiller i eller arrangerer, også når flere går samtidig), neste kveld/spilledag med svar, tråd og tippekupong, og arrangørens knapp for neste steg |
| Spill | Løse runder på slope.no-baner, bli med med kode, spill i runden, «Del regningen» (Vipps), «Turneringer» for å se og lage turneringer (også uten klubb: private liga, cup og morro), og «Finn turneringer» med åpne turneringer å melde seg på |
| Turneringer | Sju oppsett: Stableford-serie, Matchspill-serie (Golfgutu), Cup, Morro, og i en klubb Amerikaner og Københavner (formens poeng går i tabellen) og Lag mot lag (fourball side mot side). Skins er skjult i «Ny turnering» til formen kan føres i appen (turneringer som alt bruker den, kjennes igjen som før). Påmelding med tak og venteliste, startliste, stab. Med gunstart åpner føringen på gruppas starthull fra startlista, og «Lagre hull 18 og gå videre» går til hull 1. Liga og morro kan være «Spill når det passer» (periode, de beste N teller, runder i perioden teller av seg selv). Liga, cup og morro i en klubb kan ha egne spilledager med runder («Spilledager og runder» på arrangørsiden). Lages fra «+» på Arrangør-fanen eller fra Spill. Kan slettes av arrangøren (navnet må skrives) |
| Ordet for en dag | «Kveld» for Golfgutu, «Spilledag» for nye turneringer (valg i «Ny turnering» og i reglene) |
| Arrangør på web | https://admin.dashdash18.com: samme innlogging og tilganger som appen. Del 1 viser turneringer, terminliste og tropp; resten kommer i delene i `web/admin/README.md` |
| Arrangør | Oppsett øverst (turneringen, troppen, banene; i Troppen kan mange navn legges inn på én gang ved å lime inn en liste med navn og handicap), så dagen som står for tur med stegrekka Påmelding → Oppsett → Spilles → Ferdig, kommende og tidligere dager, varsler, rapporter og arkiv. Med sql/034: flere runder kan gå samtidig (én per spilledag og pulje), opptil 99 båser, og en serie som aktiveres mens hovedturneringen går, kan erstatte den eller kjøre ved siden av. Tavla, Vedd og arrangørsiden viser hovedturneringen. «Tilpass reglene» har minste antall kvelder, sum eller snitt, poengtabeller, playoff og trekning av matcher (etter tabellen, tilfeldig uten gjentakelser, manuelt). Ny runde trekker etter valget, og lag kan trekkes tilfeldig og byttes to og to. I scramble og andre former med ett kort per lag går lagene opp for alle antall (lag som ikke blir fulle, får én færre, f.eks. 3+3+3 i scramble-4 med ni); går det ikke opp, sier oppsettet hvorfor i stedet for å tømme lagene |
| Roller (steg 2, krever sql/044) | Klubben har roller med fire rettigheter (turneringer, runder, medlemmer, penger). Eieren styrer «Roller» på Arrangør-fanen og gir bort eierskapet fra spillersiden i Troppen; den som har «Medlemmer og invitasjon» gir roller med rettigheter den selv har. Arrangør-fanen viser bare delene du har rettighet til. Uten 044 er alt som før (bryterne for arrangør og kasserer). Det samme på web (fanene Roller og Tropp) |
| Påmelding per kveld (steg 4, krever sql/045) | Svaret går gjennom `evening_signup`. Arrangøren kan slå på maks antall, påmeldingsfrist, avmeldingsfrist og gjester per kveld (Endre kvelden, og «Endre» i terminlista på web); alt er av som standard. Full kveld gir «På venteliste (nr. N)» og automatisk opprykk med varsel. «Kommer» teller bare dem med plass, pluss bekreftede gjester (Kveld, Hjem-kortet, arrangørsiden, runde-oppsettet, tipsen og web-admin). Medlemmer melder på gjester med navn. Arrangøren ser «ikke sett» og «ikke svart» i purringen, endrer svar og ser loggen («Endre påmeldingen» på Kvelden, «Påmelding» i terminlista på web). Uten 045 er alt som før |
| Varsler (steg 5, krever sql/046) | **Første oppstart (1.0.1):** iOS spør om varsler med en gang appen åpnes, før innlogging, fordi påmeldingen hviler på dem. Telefonen kobles til kontoen når du logger inn. Sier du nei, spør iOS ikke igjen; da slås det på under Deg → Varsler. Deg → Varsler har fire grupper som kan slås av: Spillet, Sosialt, Kvelden og Arrangør (bare for dem med en rettighet), med kategoriene under hver gruppe og tråden under Sosialt, og «E-post når du ikke har varsler på». Kveld-skjermen har «Demp denne kvelden» (ingen push om kvelden, utenom melding til alle). Når den første runden starter, kommer ett «Kvelden er i gang» (runde 2 og 3 gir ingen push). `push-send` erstatter forrige varsel i samme gruppe samme kveld, sender push i turneringer uten klubb og logger hver mottaker i `notifications`. E-post til dem uten push er av til SMTP er satt opp (`docs/push-oppsett.md`). Uten 046 er alt som før. **Trykk på et varsel** åpner skjermen det handler om, også når appen var lukket (etter innloggingen): runden (føringen), Kveld-skjermen (påmelding, purring, påminnelse, komiteen, tipsen), tråden (bildeoppfordringen med kameraet), Tavla (låst runde, tabellendring), Vedd, Mine oppgjør eller Varsler (melding til alle, kommentarer, omtale og følging). Ukjente varsler åpner bare appen |
| Klubben | Navn og valgfritt organisasjonsnummer (Arrangør → Klubben, og «Klubb» på web). «Hent navn» henter navnet fra Enhetsregisteret, og du bekrefter før det brukes. Nummeret lagres når 044 er kjørt |
| Tavla | Tabellen regnes på telefonen av regelmotoren (paritet med PWA-en), med data fra én RPC (`tavla_data`). «Alle runder» (også i liga og morro) viser alle spillernes poeng, slag eller mot par runde for runde (som et PGA-leaderboard), og hver rute og hver runde på spillerprofilen åpner scorekortet. «TV-visning» viser tabellen i fullskjerm for skjermen i lokalet (side for side, siste runde, oppdateres mens det føres, skjermen slukker ikke). Arrangøren kan lage en TV-kode, så en skjerm uten appen viser tabellen på dashdash18.com/tv/KODE (regnet på serveren). Det samme gjelder liga, cup og morro (TV-kode på turneringssiden). Tabellreglene (steg 6): delt plass (1, 1, 3), de med for få kvelder nederst uten plass, og «Playoff» ved likt på første plass, også i web-admin og på TV. Spilles alle rundene i scramble eller en annen form med ett kort per lag, med de samme lagene, står tabellen (og TV-visningen i appen) med ett lag per rad («Anne, Berit, Cecilie og Dina») og plass blant lagene; «Alle runder», TV-koden og delt tavle er fortsatt per spiller |
| Del tavla (16.10.2026; sql/056 på test, Workeren deployet) | «Del tavla» på Tavla, på turneringssiden (liga, cup, morro) og under «I kveld» på arrangørsiden gir en lenke, dashdash18.com/tavla/KODE, som kan legges i WhatsApp-gruppa. Tilskuere ser tabellen, «Alle runder» (poeng, slag eller mot par) og scorekortet til hver spiller i hver runde i nettleseren, oppdatert hvert 20. sekund, uten app og uten konto, med appens farger og skrifter, lys og mørk modus, og «Få Atten-appen». Arrangøren slår delingen av og på (lenken slutter å virke med en gang) og kan lage en ny lenke; spillerne kan dele lenken videre når den er på. Egen kode, så TV-koden påvirkes ikke. Skjulte hull vises først når runden er låst |
| Tilleggspoeng (1.0.2, krever sql/072, ikke kjørt) | Arrangøren gir en spiller poeng for hånd, med en grunn, under Arrangør → Turneringen → Tilleggspoeng: velg spiller, poeng (halve går, minus trekker fra), grunn og eventuelt kvelden; sveip for å slette. Poengene legges på totalen i tabellen ved siden av sidepremiene (uvektet, strykes aldri av «beste N»), og står i linja under navnet («1 fra tilleggspoeng»). Spillerprofilen på Tavla viser hvert tillegg med grunnen og kvelden. TV-koden og «Del tavla» regner det samme. Første bruk: CP knockout challenge 22.10. Uten 072 er alt som før |
| Runde-regler og playoff (steg 6, krever sql/047) | Runde-oppsettet (appen og web-admin) har «Teller ikke i tabellen», poengtabell («Vanlig» eller en fra reglene) og «Skjul de tre siste hullene». Mens runden går, ser bare båsen din og de med rettigheten Runder de skjulte hullene; andre ser «De siste hullene vises når runden er låst» (også på TV). Ved delt førsteplass med playoff i reglene viser Tavla og Tabeller «Start playoff»: velg hullene (forslag siste, første, siste) og spillerne, så føres playoffen hull for hull, og vinneren går inn i tabellen (også på TV). «Legg til hull» når det fortsatt står likt. En playoff teller aldri og står utenfor Tavla, statistikk, tips, spill og «Pågår nå»; i «Mine runder» heter den «Playoff». Uten 047 er alt som før. Forfall gir ett varsel per person: arrangørene får serverens, de andre appens |
| Regelvern (15.10.2026) | «Føring og visning» i reglene: **maks slag per hull** (av, netto dobbel bogey eller fast antall; stepperen stopper, og tabellen regner med grensen), **lås kortet når det er levert** («Lever kortet» i føringen, bare arrangøren åpner det igjen; sql/057, kjørt på test 16.10) og **antall hull** «Skjul de siste hullene» skjuler (runde-oppsettet har antallet, standard 3). Alt er av eller som før i Golfgutu-oppsettet |
| Gjenbruk (steg 8, krever sql/049) | «Lag serie» på arrangørsiden og i terminlista på web: første dato, ukedag, hvor ofte, antall, tid og sted, med datoene før du lagrer og «Hoppet over» for datoer turneringen alt har. En dag i en serie viser «Hver torsdag kl. 18:00», og endring spør «Bare denne» eller «Denne og fremtidige» (passerte og startede står). Runde-oppsettet fyller inn «Samme som sist» fra serveren (bane, tee, hull, form, andel, sidepremier, vekt og tabellreglene) med «Samme spillere og båser» eller «Ny trekning»; uten 049 brukes forslaget appen finner selv. Maler: «Lagre som mal» og «Bruk mal» i runde-oppsettet (rettigheten Runder) og i Ny turnering (regler og fast spilledag; etter «Lag» tilbys «Lag serie» med planen), med «Maler» for nytt navn og sletting. Klubbens maler for arrangøren, egne maler uten klubb i appen. Uten 049 er alt dette skjult |
| Kalender og oppgjør (steg 10, krever sql/051) | Deg → Kalender: «Legg til i kalenderen» abonnerer på kveldene du er bekreftet påmeldt på (`webcal://dashdash18.com/kalender/<token>.ics`, oppdateres av seg selv), «Kopier lenke», «Ny lenke» (den gamle slutter å virke) og «Skru av». «Del regningen» i en løs runde kan lagres («Lagre og følg opp»): delene fra den like delingen, deg som mottaker, og Vipps-nummeret ditt på regningen til alle har betalt. Deg → Mine oppgjør: den som skal betale, trykker «Betal med Vipps», og delen merkes sendt når appen blir aktiv igjen; mottakeren svarer «Fikk den» eller «Kom ikke». Regningen kan slettes til noe er bekreftet. Varsel i bjella og push: «Anders har sendt sin del for Greenfee» og «Thomas sier at din del for Greenfee ikke kom». Uten 051 er kalenderen skjult, og regningen deles som før uten lagring |
| Sosialt (steg 9, krever sql/050) | Reaksjoner på alt (hendelser i Hjem, meldinger i tråden og kommentarer): de fem faste først og «Annen emoji …» for resten, «Hvem har reagert» uten blokkerte. Kommentarer under hendelser og meldinger med @-omtale, endre og slette egne (Penger-rettigheten kan slette andres), rapport og «Følg tråden». Hjem hentes i sider med «Vis eldre» nederst. Når en runde låses, får spillerne «Ta et bilde av gjengen» med kameraet rett i tråden. Varsel og push for nye kommentarer og omtale. Uten 050 er alt som før |
| Formater (steg 7, krever sql/048) | Runde-oppsettet (appen og web-admin) har «Konkurranser i runden»: formen er hovedkonkurransen, og «Legg til konkurranse» gir Bestball i par, Skins, Første ni, Siste ni, Amerikaner og Københavner, alle regnet fra de samme scorene. Hver kan gjelde alle eller valgte spillere, alle hull, 1–9 eller 10–18, og handicapandel og par ligger under «Avansert». «Lag mot lag» gir hver spiller side 1 eller 2 (laget følger med) og trekker matchene side mot side. Runden (føringen og arrangørens rundetabell) viser «Konkurranser» med stillingen i hver, regnet fra øyeblikksbildet ved start (regelsett, hull og spillehandicap), og lag mot lag med poeng til sidene; Tavla viser lagtabellen over rundene. Par/bogey (match mot banen per hull, +1/0/−1 etter regel 21.3) er en oppskrift i «Legg til konkurranse» og en ferdig form; stillingen viser summen med fortegn («+3»). Foursome, greensome, chapman og scramble regnes som konkurranser når runden spilles i den lagformen: laget fører én score per hull (som før), med lagets handicap. «Lagshandicap» i reglene har «Bruk WHS-anbefalingen» (foursome 50 %, greensome og chapman 60/40, scramble 35/15 og 25/20/15/10); Golfgutu beholder PWA-ens tall. Maksimumscore (regel 21.2) og Match er oppskrifter i «Legg til konkurranse»: maksimumscore er slagspill der hvert hull kappes til taket (netto dobbel bogey som standard fra regelsettet, eller fast 3–20 slag), netto eller brutto, og stillingen viser slag («73 slag»); match er to valgte spillere, eller side 1 mot side 2 når runden er lag mot lag, hull for hull med handicapslagene fra rundens matcher, og stillingen viser «2 opp etter 6», «Delt etter 5» eller «Vunnet 3&2» (matchen stopper når den er avgjort). Spilles runden med én ball per lag (foursome, greensome, chapman, scramble), er «Match» lag mot lag i den lagformen: rundens to lag, eller to valgte lag når runden har flere, med lagets ene score per hull, lagshandicapet fra reglene (med WHS-anbefalingen er foursome 50 % av lagets samlede banehandicap) og slagene som i matchene (laget med høyest lagshandicap får forskjellen), og samme stilling («Vunnet 3&2»). Det motoren ikke regner ennå (én ball i en annen lagform enn runden, og sammenlagt match), står som «Ikke støttet ennå». Arrangøren har «Oppdater øyeblikksbildet» i en runde som går, og får spørsmålet etter å ha rettet hullene på en bane som er i bruk. «Samme som sist» tar med konkurransene og sidene. TV-en viser de ekstra konkurransene og lag mot lag som små paneler. Uten 048 er alt som før |
| Vedd og tips | Veddemål med poeng, tippekupong per kveld med «Tips» og «Forrige kupong» rett på Hjem-kortet. **Ikke i App Store-bygget (prod):** veddemål er av, og tippekupongen er alltid for æra, uten innsats og pott (`BetsFeature`). Apple avviste 1.0 for «simulert gambling» (2.3.6), som krever at en organisasjon sender inn appen. Test-bygget har alt som før |
| Veddemål overalt (steg 11, krever sql/052) | Veddemål i hovedturneringen, liga, cup, morro, private turneringer og løse runder, med egen poengbank per turnering eller runde (`bet_bank`). Innsatsene telles per person (medlem eller profil). **Av som standard:** arrangøren slår det på med bryteren «Veddemål» på Arrangør-fanen (under turneringen, ved Påmelding og Stab), på turneringssiden, på Kveld-kortet («Av. Trykk for å slå på.»), i Vedd selv, i «Ny turnering» og på web (turneringens side). Løse runder: «Veddemål» i «Ny runde», eller eieren slår det på i runden. Vedd vises bare der det er slått på; hører runden til flere turneringer med veddemål, velges banken i Vedd-menyen. Serveren gjør opp når runden låses (`bet-settle`), og det står «Avgjort av scorene» i Hjem. Hjem feier ikke lenger på arrangørens telefon; telefonen tar bare runder serveren ikke har gjort opp etter 30 minutter, og «Avgjør» for hånd står for det scorene ikke svarer på (for eksempel nærmest pinnen uten innmelding). På test er ingen turnering slått på ennå: Golfgutu-sesongen må slås på av arrangøren. Uten 052 er alt som før (hovedturneringen, `create_bet`) |
| Følge (steg 13, krever sql/054) | Deg → Følger: forespørsler øverst med «Godta» og «Avslå», «Du følger» og «Følger deg» (sveip for å slutte å følge eller fjerne), «Godkjenn nye følgere» og «Kan finnes i søk», og antallet. «Finn spillere» søker på navn (minst tre tegn) med Følg / Venter / Følger og «Følger deg». «Min kode» viser QR-koden (`https://dashdash18.com/folg/KODE`) og «Ny kode»; «Skann kode» leser den med kameraet (eller skriv koden) og følger med en gang. Lenken åpner appen, og uten appen viser dashdash18.com «Åpne Atten for å følge». Profilen har Følg-knappen, «Blokker» og «Rapporter profil». Etter en ferdig runde: «Følg medspillerne». Hjem har «Klubben» og «Følger»: ferdige runder fra dem du følger og dine egne (slag, til par, bane, dato og hull) med reaksjoner og kommentarer; uten klubb ligger rundene under Deg → Følger. **Legg til venner:** øverst i «Følger» på Hjem står kortet «Legg til venner» med inntil tre du kjenner (klubb, runder, turneringer) og Følg-knappen, og knappen til «Legg til venner»: «Søk på navn», «Skann QR-kode», «Vis min kode og del lenken», «Folk du kjenner» (de som følger deg står først) og forespørslene. Samme side ligger øverst i Deg → Følger. En venn er en dere følger begge veier; det finnes ingen egen vennemodell. Bjella viser «X vil følge deg» (med Godta og Avslå), «X godtok forespørselen din», «X følger deg nå» og kommentarer på kortene, og push-send sender dem (aldri ferdige runder). Dem du følger står øverst i «Ny runde» og «Ny turnering». Uten 054 er alt dette skjult |
| Apple Watch (17.10.2026) | Live Activity for runden vises i Smart Stack på klokka (watchOS 11+): hull, poeng og slag, og matchen eller plassen i båsen. Trykk åpner appen på telefonen. Ingen egen klokkeapp ennå |
| Ytelse | Mengdebaserte RPC-er for venner, løse runder, turneringslista og Hjem (sql/036–037) |
| Utseende (UI-utbedring, oktober 2026) | Systemets navigasjonslinje med glass og store titler i stedet for den grønne stripen. Nytt designsystem: fire knappestiler, scoreskala med form, mørk modus med dybde og «Øk kontrast». **Føringen:** par er forvalgt («Lagre hull N og gå videre» er alltid aktiv), hullet stort øverst, hullbrikker på 44 pt, «Føring | Stilling | Spill», synkstatus i bunnlinja. **Hjem:** «Neste kveld» øverst med svar i segmenter, runden som pågår som bar over fanelinja. **Tavla:** «Tabell | Alle runder | Statistikk», ▲/▼, «1=», kort ved delt ledelse, TV på ekstern skjerm (AirPlay). **Arrangør:** «I kveld» med båsene live og synkstatus, påmelding med «Purr dem», «Før Ferdig». Del regningen i kroner per person, cup-treet én runde om gangen, tomtilstander med én handling. Status, avvik og det som gjenstår i [`docs/ui-utbedring.md`](docs/ui-utbedring.md) |
| Avviste hull (20.10.2026) | Sier serveren nei til et hull som lå i kø (for eksempel fordi runden ble låst før dekningen kom tilbake), viser føringen en stripe: «Hull 7 ble ikke lagret: … Tallene står ikke på kortet. Før dem på nytt, eller si fra til arrangøren.» «OK» skjuler den. Ingen ny SQL |
| Avslutt runden (16.10.2026) | Når kortet er ført ferdig (eller siste hull er ført), viser bunnlinja i føringen «Ferdig? Avslutt runden» for den som kan avslutte: eieren av en løs runde (`finish_loose_round`) og arrangøren med rettigheten Runder i en klubbrunde (låses som «Lås runden», med «Runde låst» i Hjem). Bekreftelsen sier hva som skjer (runden låses, resultatet står, ingen kan føre mer). Er ikke alle ferdige, står det hvor mange flighter/båser eller spillere som mangler, og det kommer en ekstra bekreftelse. Arrangøren som ikke spiller, får knappen når minst én er ferdig, og «Avslutt runden …» ligger også i ⋯-menyen. Andre spillere ser «Kortet ditt er ferdig» (eller «Lever kortet» med låst kort). En klubbrunde lukker føringen etterpå, og Hjem henter på nytt uten å åpne den igjen; en løs runde blir stående med resultatet. Ingen ny SQL |
| Deltaker i turnering (20.10.2026, sql/059) | Den som er påmeldt en klubbturnering uten å være medlem (en deltakerrad i klubben), ser turneringen under «Turneringer» i Spill med «Meld meg av», og seg selv som «deg» i tabellen og cuptreet. Turneringssiden har «Før runden» for hver runde som går og der du spiller (også for medlemmer: da åpnes føringen på Hjem). Føringen for deltakeren er den vanlige (eget kort, par-bekreftelsen, utboksen), uten klubbens tråd, tips, veddemål, aktivitet og avslutning, og en låst runde vises med resultatet. Uten klubb står rundene som går under «Turneringsrunder» i Spill og i baren over fanelinja, og en push om runden åpner føringen. Et medlem i én klubb som er deltaker i en annen, ser begge. Ingen ny SQL |
| Deltakerinvitasjon (20.10.2026, sql/060) | Arrangøren av en klubbturnering med påmelding har «Legg til deltakere (lim inn liste)» og «Del lenken til turneringen» på arrangørsiden (under turneringen, ved Påmelding og Stab). Lista limes inn fra e-post, GolfBox eller et regneark: ett navn per linje, handicap etter navnet eller i egen kolonne, og NGF-nummer i en tredje kolonne (`navn; handicap; NGF`). Navn som står to ganger eller er påmeldt fra før, er merket og hoppes over; samme navn som et medlem er greit. Alt legges inn i én omgang (høyst 300) og gir «N lagt til». Arrangøren deler lenken (`https://dashdash18.com/konkurranse/KODE`, QR, ny kode og «Trekk tilbake», virker i 60 dager) også med «Inviter» på turneringssiden; deltakerne får ikke «Inviter». Den som åpner lenken, ser klubben og «Er du en av disse?» med de ledige navnene (søk når lista er lang) og «Jeg står ikke på lista», og at hen blir deltaker i turneringen, ikke medlem i klubben. Etterpå: «Åpne turneringen», Turneringer henter på nytt, og en ny bruker uten klubb får vennemodus i stedet for valgskjermen (også når appen ser at du har deltakerrader). Innloggingen viser «Logg inn for å ta plassen din i turneringen» når lenken venter |
| Profil uten klubb (20.10.2026) | Deg uten klubb har «Navn og handicap» med «Endre»: navn, handicapindeks og NGF-medlemsnummer (valgfritt, sifre med én bindestrek som i databasen) lagres på profilen og brukes i løse runder, i søk og når du blir deltaker i en turnering. Et NGF-nummer som står på en annen bruker, gir «Det NGF-nummeret er registrert på en annen bruker.» Med klubb står navn og handicap i medlemskapet som før, og Deg har «NGF-medlemsnummer» for profilen. Mangler profilen navn, viser Deg og Spill (uten klubb) «Legg inn navnet ditt, så ser de andre hvem du er», som åpner skjemaet. Navnet Apple gir ved første innlogging, blir profilnavnet når profilen ikke har navn fra før (et navn du har satt, står). Ingen ny SQL |
| Markørkonflikt (K6/6.3, krever sql/055) | Fører to markører ulikt for samme spiller og hull, får føringen en stripe og et merke på raden. Arket viser begge tallene, hvem som førte og når, og markøren eller arrangøren velger hvilket som gjelder. Arrangøren ser det også i rundekortet på «I kveld». Bare klubbrunder. Uten 055 er alt som før |
| CAPTCHA ved innlogging med e-post (1.0.1, av til site key er satt) | Før koden sendes, viser appen et lite ark med Cloudflare Turnstile («Et øyeblikk»). Oftest lukker det seg selv; vil Turnstile at du trykker, vises ruta. Arket er en WKWebView med `https://dashdash18.com/captcha?sitekey=…` fra workeren (`web/atten-lenker/src/captcha.ts`), og tokenet sendes med `signInWithOTP` som `captchaToken`. Supabase sjekker ikke CAPTCHA når koden skrives inn (`/verify`) eller ved Apple-innlogging (`id_token`), så der sendes ikke noe token. Feil vises på norsk med «Prøv igjen». Site key-en leses fra `TurnstileSiteKey` i `Supabase-<Miljø>.plist` (Xcode Cloud: `TURNSTILE_SITE_KEY`); uten den er `CaptchaFeature` av. Stegene står i `docs/prod-sjekkliste.md` 2.6 |
| Slett konto og Apple (1.0.1, 21.10.2026) | Deg → «Slett konto …», bekreftes med SLETT. Har kontoen Logg inn med Apple, ber appen om en ny Apple-innlogging til slutt (teksten under knappen sier det), og `delete-account` trekker tilbake Apple-tokenet (`appleid.apple.com/auth/revoke`), så Atten forsvinner fra «Logg inn med Apple» i innstillingene. Lukker du Apple-arket, slettes ingenting. Gir Apple ingen kode, eller feiler Apple, slettes kontoen likevel. Kontoer med e-postkode merker ingen forskjell. Krever secrets `APPLE_*` og ny deploy av `delete-account` (`docs/prod-sjekkliste.md` punkt 4.5). Ingen ny SQL |
| Feilsporing (20.10.2026, krever sql/064) | MetricKit melder krasj, heng, høy CPU, mye skriving til disk og treg oppstart fra ekte brukere (dagen etter, ikke i simulatoren). Appen legger dem i en kø på telefonen (høyst 50, eldste kastes) og sender dem med `submit_diagnostics` når du er innlogget, ved oppstart og når appen blir aktiv. Ingen persondata utover bruker-id-en. Uten 064 blir de liggende i køen, og appen virker som før. Flagg: `DiagnosticsFeature` |
| Oppdatering og nødbrytere (1.0.2, krever sql/068) | Appen leser `app_config` etter innlogging og når den blir aktiv. Under `min_ios_build` (fra 1.0): «Oppdater Atten», ingen vei forbi. Under `recommended_ios_build`: «Ny versjon av Atten» én gang per anbefalt bygg, med «Oppdater» og «Senere». `ios_flags` slår av Del tavla, TV-kode, Finn turneringer, Del regningen, Sosialt eller Live Activity uten nytt bygg (`KillSwitch`), bare av, aldri på. Bryterne huskes til neste oppstart. Feiler lesingen, sperres ingenting. Regler i [`docs/utgivelser.md`](docs/utgivelser.md) |
| Rapporter baner og turneringer (1.0.1, sql/066 kjørt 21.10.2026) | I det felles banebiblioteket og i «Velg bane» har en bane som en annen har lagt inn (også «Ikke klar»), «Rapporter banen» når du sveiper eller holder på raden. I «Finn turneringer» har turneringen «Rapporter turneringen» på raden og i ⋯-menyen på turneringssiden. Samme rapportark som ellers (grunn og kommentar). Rapporten går bare til oss (e-post fra `report-alert`), ikke til klubbens arrangør, og det du har rapportert, skjules for deg til rapporten er avvist. Egne baner og baner fra slope.no kan ikke rapporteres. Flagg: `PublicContentReportFeature` (på) |
| Varsel om ventende medlem (1.0.1, sql/067 kjørt 21.10.2026) | Når noen skriver klubbkoden og et nytt navn og venter på godkjenning, får de med Medlemmer og invitasjon (og eieren) push og en linje i bjella: «Ola Nordmann vil bli med i Golfgutu Invitational». Trykk på pushen åpner Arrangør → Troppen i riktig klubb (andre får bare appen åpnet); linja i bjella har «Åpne Troppen». Arrangør-fanen har et merke med antall ventende, arrangørsiden har raden «Ola Nordmann vil bli med» / «N vil bli med i klubben» øverst, og ⋯-menyen sier «Troppen (N venter)». Varselet forsvinner når en arrangør godkjenner eller avviser. Hører til gruppen Arrangør i Deg → Varsler («Nye som vil bli med i klubben»), og de uten push får e-post når SMTP er på. Import og SQL gir ingen varsel. Flagg: `PendingMembersFeature` (av) |
| Stillingen i runden (21.10.2026) | Heter «Bayen nå» i simulatoren og «Flighten nå» på ekte bane. Mens runden går, rangeres individuell stableford på poeng mot par (poengene minus netto par-poengene for hullene som er ført), så den som har spilt flest hull, ikke leder bare av den grunn. Under navnet står «etter 9 hull · 2 p over par». De som ikke har ført noe, står nederst. Låst eller avkortet runde, lag, match og par/bogey rangeres som før (summen). Live Activity og plassen i feiringen følger samme rekkefølge |

**Funksjonsflagg.** Nye deler ligger bak et flagg i koden til SQL-en er kjørt og prøvd. Av nå: `PurchaseFeature` (kjøp, venter på App Store Connect) og `GoogleLoginFeature` (venter på Google Cloud). `CaptchaFeature` er på bare når konfigen har en Turnstile site key. Resten er på. Søk etter `Feature {` for å finne dem.

**Venter på Thomas.** App Store Connect, Google OAuth, personvern og vilkår publisert, egen SMTP, eksport fra PWA-en og ja til prod. Lista står i [`docs/gjoremal.md`](docs/gjoremal.md).

## Dokumenter

| Fil | Hva |
|---|---|
| [`ROADMAP.md`](ROADMAP.md) | Faser, status og beslutninger. Start her for å se hvor prosjektet står |
| [`SPEC.md`](SPEC.md) | Kartlegging av PWA-en (funksjoner og regler) |
| [`CLAUDE.md`](CLAUDE.md) | Arbeidsregler for Claude Code. Gjelder også for mennesker |
| [`docs/ui-utbedring.md`](docs/ui-utbedring.md) | UI-utbedringen etter skjermgjennomgangen i oktober 2026: kart fra skjerm til kode, status per punkt og avvik fra planen |
| [`docs/lanseringssjekk.md`](docs/lanseringssjekk.md) | Gjennomgang 17.10.2026 mot en sjekkliste for lansering, og hvordan appen skal ta betalt |
| [`docs/utgivelser.md`](docs/utgivelser.md) | Regler for utgivelser: fast rytme, hasteretting, brytere, bakoverkompatibel database, støttevindu og iOS-minimum |
| [`docs/gjoremal.md`](docs/gjoremal.md) | Det som må gjøres manuelt (App Store Connect, Supabase-konsoll, Google) |
| [`sql/README.md`](sql/README.md) | Databasemigreringer og status per fil (test og prod) |
| [`docs/folge.md`](docs/folge.md) | Følge andre spillere (steg 13): hva Strava og andre gjør, Thomas sine valg, personvern og datamodell |
| [`docs/gjennomforingsplan.md`](docs/gjennomforingsplan.md) | Arbeidsrekkefølgen for alt som ble besluttet 11.10: tolv steg med SQL-nummer, avhengigheter og status |
| [`docs/plan-konkurranser-og-sosialt.md`](docs/plan-konkurranser-og-sosialt.md) | Gap-analyse og plan (fase 27–34): konkurranser, påmelding, medlemmer og sosialt lag, mot researchen i `docs/research/golfapper-research.md`. Venter på godkjenning |
| [`docs/fase-26-tv-tidsvindu-web.md`](docs/fase-26-tv-tidsvindu-web.md) | Plan: TV med kode, turneringer med tidsvindu, regelmotoren i TypeScript og web-admin |
| [`docs/golfapper.md`](docs/golfapper.md) | Analyse av flyten i andre golfapper (Squabbit, 18Birdies, Golf Genius, GolfBox, Trackman m.fl.) og 12 anbefalinger for Atten |
| [`docs/vedd-per-turnering.md`](docs/vedd-per-turnering.md) | Veddemål per turnering og runde, poengbank og oppgjør på serveren (bygget, steg 11) |
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
2. Legg inn `DashDash18/Config/Supabase-Test.plist` med prosjekt-URL og **publishable key** for test-prosjektet. Service-role-nøkkelen skal aldri inn i appen. Valgfritt: `TurnstileSiteKey` (site key for Cloudflare Turnstile) slår på CAPTCHA ved innlogging med e-post. Bare site key, aldri secret key.
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

To prosjekter: **test** (`tsekialrxuhrugscosgi`) og **Atten Prod** (`wxabhadvuzyrmndxpuza`, satt opp 20.10.2026 med alle migreringene, se `docs/prod-sjekkliste.md`). Nye migreringer kjøres på test først og så på prod. PWA-ens database er bare kilde for import og skrives aldri til.

Endringer går slik (detaljer i [`sql/README.md`](sql/README.md)):

1. Ny nummerert fil i `sql/`, med kontrollspørringer nederst.
2. Thomas leser og godkjenner SQL-en. Uten godkjenning kjøres ingenting.
3. Kjøres på test, deretter kontrollspørringene.
4. Prøves i appen mot test.
5. Prod (når det finnes) først etter ny godkjenning.

Filen legges i en PR som andre endringer. Status i `sql/README.md` oppdateres når den er kjørt.

### Feilrapporter (MetricKit)

Krasj og heng fra appen havner i `public.app_diagnostics` i samme prosjekt som bygget snakker med (test eller prod, også i kolonnen `environment`), når `sql/064_feilrapporter.sql` er kjørt. Tabellen har ingen policyer, så den leses bare i SQL Editor (eller med service_role). `signature` er unntaket eller signalet og øverste ramme i appen (`DashDash18+0x…`, ikke symbolisert; bruk dSYM-en i Xcode Organizer for linjen), og `payload` er Apples JSON for diagnosen.

```sql
-- Oftest siste 7 dager
select kind, signature, count(*) as antall, count(distinct user_id) as brukere,
       max(app_version || ' (' || build || ')') as siste_bygg, max(created_at) as sist
  from public.app_diagnostics
 where created_at > now() - interval '7 days'
 group by kind, signature
 order by antall desc
 limit 20;
```

## Distribusjon

Xcode Cloud-workflowen «TestFlight fra main» arkiverer og sender til TestFlight ved hver endring på `main`. Oppsett og miljøvariabler står i [`docs/xcode-cloud.md`](docs/xcode-cloud.md), App Store-oppsettet i [`docs/app-store.md`](docs/app-store.md).
