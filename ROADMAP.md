# ROADMAP: DashDash18

Plan fra dagens tomme Xcode-prosjekt til en iOS-app som erstatter GolfGutu-PWA-en for hele gjengen. Grunnlag: `SPEC.md`, `CLAUDE.md`, `referanse/golfgutu-pwa/` (særlig `README.md` og `db-nytt.js`).

Henvisninger som «SPEC 4.9» peker til seksjoner i `SPEC.md`.

---

## STATUS

| | |
|---|---|
| **Nåværende fase** | Fase 1 – Innlogging og Kveld i lesemodus (ikke startet) |
| **Sist gjort** | Beslutninger tatt (seksjon 3). `.gitignore` holder `referanse/` utenfor git. Ingen Swift-kode ennå. Prosjektet er fortsatt Xcode-malen. |
| **Neste oppgave** | Fase 1, oppgave 1: sette deployment target til iOS 26.0 og Swift 6-språkmodus i Xcode (B7). |
| **Venter på deg** | Godkjenning av Supabase-oppsett for Apple- og Google-innlogging (B9) før fase 1 oppgave 8. |

---

## 1. MÅLBILDE

«Ferdig» betyr:

1. **Gjengen spiller en hel kveld uten PWA-en.** Påmelding, kladd, start, par-bekreftelse, føring per bås, LD/KP, tippekupong, tråd, avkorting og «Avslutt kvelden» gjøres i iOS-appen, av spillere, markører og arrangør.
2. **All spillogikk gir samme svar som PWA-en.** Hver regel i `db-nytt.js` som påvirker poeng, stableford, WHS, match, jakketabell og tips har en Swift-test med tall hentet fra PWA-ens tester eller utledet fra koden (SPEC 4).
3. **Appen er distribuert til alle** i gjengen via TestFlight og kjører mot **prod**-databasen.
4. **Ingen data går tapt eller må flyttes.** Appen bruker samme database som PWA-en, så sesongen fortsetter der den slapp.
5. Føring virker med dårlig dekning: ingen hull går tapt når nettet faller ut.
6. Veddemål er avgjort på nytt (B10): enten med poeng i stedet for penger, eller utelatt. Penger flyttes ikke.

PWA-en lever side om side med appen til appen er god nok til å overta (B3).

---

## 2. FASER

Hver fase gir noe som kan prøves på en ekte kveld. Fram til appen får skrive mot prod (B4) betyr «ekte kveld» en kveld simulert i **test**-prosjektet, med PWA-ens test-bygg (`golfgutu-test.pages.dev`) og iOS-appen side om side.

Tester i parentes er filer i `referanse/golfgutu-pwa/tests/`. Hver av dem skal ha en Swift-test (Swift Testing) som gir samme svar. Fullstendig oversikt står i vedlegg A.

---

### Fase 1 – Innlogging og Kveld i lesemodus

**Mål:** Logge inn mot test-databasen med Apple, Google eller e-postkode, og se kvelden og en runde som pågår (ført fra PWA-en) live på telefonen.

- [ ] Sette deployment target til iOS 26.0 og Swift 6-språkmodus i Xcode (B7). Ikke via `project.pbxproj`.
- [ ] Miljøkonfig for **test** (URL og publishable key) i en fil som ikke sjekkes inn, og som ikke kan peke på prod ved et uhell.
- [ ] Legge til `supabase-swift` via Swift Package Manager i Xcode.
- [ ] Rydde malkoden (`Item.swift`, mal-`ContentView`) og opprette mappestrukturen.
- [ ] Datamodeller (rene `Codable`-typer) for `players`, `schedule`, `signups`, `rounds`, `round_bays`, `round_teams`, `round_matches`, `round_holes`, `hole_scores`, `round_points`, `courses`, `course_holes`, `settings` (SPEC 3.1).
- [ ] Paginert henting (1000 rader, eksplisitt sortering) som i PWA-en (SPEC 3.3).
- [ ] Innlogging med e-postkode (ikke anta kodelengde) og kobling av `auth.uid()` til spillerrad: «velg navnet ditt» (ta ledig rad, sjekk at én rad kom tilbake), «Bli med» som ny spiller, logg ut.
- [ ] **Logg inn med Apple** (native, `AuthenticationServices` + `signInWithIdToken`) og **Google** (OAuth via `supabase-swift`, uten ekstra SDK). Krever godkjent Supabase-oppsett (B9).
- [ ] **Koble til Apple/Google** fra en innlogget konto (`linkIdentity`), slik at eksisterende spillere beholder samme `user_id` og PWA-innloggingen fortsatt virker.
- [ ] «Vi kjenner deg ikke igjen»: tydelig vei hvis noen logger inn med en ny identitet som ikke er koblet (for eksempel Apples «Skjul e-post»).
- [ ] Hent på nytt når appen blir aktiv igjen (SPEC 5.1 nr. 4).
- [ ] Realtime på `hole_scores`, `rounds`, `round_bays` med målrettet refetch.
- [ ] Kveld-skjerm, rolig: neste kveld, påmeldte, topp av tabellen (foreløpig fra `round_points`).
- [ ] Kveld-skjerm, spill: aktiv runde, min bås, hvem som fører, brutto per hull for båsen, scorekort (bare tall som ligger i basen).

**Ferdig når:**
- Jeg logger inn på telefonen mot test med e-postkoden min og ser riktig navn.
- Jeg kobler Apple til kontoen, logger ut og inn igjen med Apple, og er fortsatt samme spiller. E-postkoden virker fortsatt i PWA-test.
- Jeg logger inn med Google på samme måte.
- Jeg ser neste kveld og hvem som er påmeldt, likt PWA-test.
- Når noen fører et hull i PWA-test, dukker tallet opp i appen innen få sekunder, også etter at appen har ligget i bakgrunnen.
- Appen kan ikke nå prod (sjekket i konfig).

**Tester:** Ingen regneregler ennå. Swift-tester for radmapping (standardverdier som `holeCount` 9/18, `ldAktiv !== false`, `prat_push`-fallback), `banehullFraRader` (`banepar-test.js`), `paameldteForDato` (`paamelding-test.js`, `kvelder-test.js`). Oppførselen fra `innlogging-test.js`, `innmelding-test.js` og `uinnloeste-rader-test.js` (ta ledig rad, ikke ta andres).

**Avhengigheter og risiko:**
- Apple- og Google-innlogging krever oppsett i Supabase (providers, manuell kobling), i Apple Developer (Sign in with Apple, tjeneste-ID og nøkkel) og i Google Cloud (OAuth-klient). Supabase-delen godkjennes av deg (B9).
- Supabase kobler automatisk identiteter med samme verifiserte e-post. Apples «Skjul e-post» gir en annen adresse, og da må kontoen kobles manuelt fra en innlogget økt.
- Engangskoden sendes via Resend. Hvis e-post fra test ikke er satt opp, trengs en testbruker (finnes bare i test).
- RLS gir tomt svar til anon: hent aldri før innlogging (SPEC 3.2).

**Anslag:** 7–10 økter.

---

### Fase 2 – Spillogikk og føring som markør

**Mål:** Føre score for båsen fra iPhone med nøyaktig samme poeng som PWA-en regner.

- [ ] Spillogikk i rene Swift-typer (ingen UI/nett): `courseForRound` med rang-strokeindex og `holeStart`, `courseHandicap`, `rundeAndel`, seeding, `banehandicap`, `lagGrunnlag`, `lagHandicap`, `effectiveHandicap`, `handicapStrokesForHole`, `pointsForHole`, `scoreNameForHole`, `poengFraHull`, `tellendeHull`, `poengForTomtHull`, `lavesteFellesHull`, `KONKURRANSEFORMER`, `formForRunde` (SPEC 4.1–4.5).
- [ ] Avrunding som JS: én felles hjelper for `Math.round` (`floor(x + 0.5)`) og `rund2` (SPEC 4.0).
- [ ] `kanFore` og båsoppslag (SPEC 4.10).
- [ ] Hullkort for hele båsen: stepper, «N slag fått», regnestykket, score-merke, bekreft hver spiller, «Lagre hull» låst til alle er ført.
- [ ] Seer-modus for ikke-markør med linjen «… fører · du ser det live».
- [ ] `saveHoleScore` som i PWA-en: upsert `hole_scores`, les tilbake, regn, upsert `round_points`. Lagsform skriver hele laget og `skrivLagpoeng` (SPEC 4.9).
- [ ] Sjekk rader tilbake og vis klar feil hvis RLS stopper skrivingen.
- [ ] Følg båsens hull (`baasensHull`), sol-stripe når jeg ser på et annet hull.
- [ ] Scorekort Ut/Inn med poeng regnet lokalt.
- [ ] Paritetssjekk: en hel runde ført i iOS gir samme `round_points` som `regnOmRundePoeng` i PWA-en for samme data.

**Ferdig når:**
- Jeg er markør i en bås på test, fører 9 hull for fire spillere i appen, og PWA-test viser samme brutto, netto og poeng per spiller.
- En spiller som ikke er markør kan ikke føre (stepperen vises ikke), og ser tallene live.
- Seedet spiller, 9-hullsrunde med `holeStart` 9, `hcp_extern` (Trackman) og en scramble-runde gir samme poeng i begge apper.

**Tester:** `brutto-test.js`, `seeding-test.js`, `parspill-test.js`, `baneoppsett-test.js`, `banepar-test.js`, `banehull-test.js`, `banebytte-test.js`, `trackman-test.js`, `avkorting-test.js` (poeng-delen), `markor-test.js` (`kanFore`), `tropp-test.js` (`kanFore`, handicap). Pluss egne tester for det som mangler test i PWA-en: `scoreNameForHole`, `rundeAndel`, `lagGrunnlag`, `poengForTomtHull`, `holeStart: 9` mot 18-hulls bane, `skrivLagpoeng`.

**Avhengigheter og risiko:**
- Krever fase 1.
- **Største risiko i hele prosjektet:** små avvik (avrunding, JS-sannhet, rekkefølge) gir feil poeng i en delt database. Mot: test først, paritetssjekk mot PWA-test på samme runde.
- `saveHoleScore` er to skriv (ikke atomisk), som i PWA-en. Vi kopierer mønsteret, vi forbedrer det ikke.

**Anslag:** 8–12 økter.

---

### Fase 3 – Robust føring og første kveld i bruk

**Mål:** Markørene kan bruke appen på en ekte torsdag uten å miste et eneste hull, selv uten dekning.

- [ ] Lokal lagring med SwiftData (B6): cache av kveldens data og en utboks for score.
- [ ] Utboks: hull lagres lokalt først, sendes i rekkefølge med nye forsøk, idempotent upsert. Tydelig «ikke lagret ennå» per hull.
- [ ] Gjenoppta etter at appen er drept: utboksen sendes ved neste oppstart.
- [ ] Konflikt: siste skriving vinner, som i PWA-en. Vis hvis noen andre har endret et hull jeg har i kø.
- [ ] Feiring (birdie/eagle/albatross/hole in one) med redusert-bevegelse-støtte.
- [ ] Aktivitetslogg ved store scorer og ledelsesskifte (hull 3/6/9/12/15/18), likt tekstformat som PWA-en, uten dobbel logging når PWA-en fører samme kveld.
- [ ] TestFlight-oppsett (B1), første bygg til markørene.
- [ ] Prod-konfig ved siden av test, med tydelig skille i appen (B4).
- [ ] Prøvekveld på test: alle markører på iOS, resten på PWA.
- [ ] Første prod-kveld (etter din godkjenning): markørene fører i appen, PWA-en er reserve.

**Ferdig når:**
- Jeg slår på flymodus, fører tre hull, slår av flymodus: alle tre hull ligger i PWA-en med riktige poeng.
- Jeg dreper appen med hull i kø, åpner igjen: hullene sendes.
- Markørene har fått appen via TestFlight og ført en hel kveld uten tap, først på test og så på prod.

**Tester:** Ingen nye regneregler. Swift-tester for utboksen (rekkefølge, idempotens, nye forsøk). Verdien fra `hent-paa-nytt-test.js` og `skjema-realtime-test.js` er oppførsel (hent ved aktivering, tastet tekst overlever oppdatering), ikke tall.

**Avhengigheter og risiko:**
- Krever fase 2.
- Første skriving mot prod krever din eksplisitte godkjenning (B4).
- Ekstern TestFlight går gjennom Apples beta-gjennomgang. Uten penger i appen er risikoen lav (B1).

**Anslag:** 6–9 økter.

---

### Fase 4 – Match, trekant og Tavla

**Mål:** Se riktig matchstilling på kvelden og riktig jakketabell for sesongen.

- [ ] Match: `matchSider`, `matchSlag`, `sideNettoPaaHull`, `matchHullVinner`, `matchHullDiff`, `matchUtfallForA`, `matchStilling`, `matchTekst`, `matchStillingKort`, `avgjoresHullForHull`.
- [ ] Trekant: `trekantPoeng`.
- [ ] Sesong: `matchResultaterFor`, `matchSum`, `sidepremieVinnere`, `sidepremieResultaterFor`, `jakketavle`, `fmtPoeng`, `tellendeRunderFor` og `seasonTotalNytt` som skilletegn.
- [ ] Kveld: matchkort, «Bayen nå» sortert på netto eller matchstilling, «1 opp / Delt / —».
- [ ] LD/KP: vis hull, meld egen lengde (`side_claims`, slett + sett inn), stilling.
- [ ] Tavla: Jakkeracet, «Slik telles det», spillerprofil (snitt, beste, birdies, innbyrdes).
- [ ] Sesongoppsummering når `settings.finished` (uten pengepremier og bøtestatistikk i første omgang).

**Ferdig når:**
- Tavla i appen og i PWA-en viser samme rekkefølge, poeng og hulldifferanse for alle spillere.
- En fourball-match og en trekant gir samme stilling og tekst i begge apper, hull for hull.
- Jeg melder longest drive i appen og den vises i PWA-en.

**Tester:** `match-test.js`, `matchrunde-test.js`, `matcher-test.js`, `trekant-test.js`, `seier-test.js`, `sesong-test.js`, `skjevt-lag-test.js`, `sidepremie-valgfritt-test.js`, `kvelder-test.js`, `neste-kveld-test.js`. Pluss egne tester for det PWA-en ikke tester: alle grener i `matchTekst`, delt sidepremie (0,5), `matchSum`, `sideNettoPaaHull`.

**Avhengigheter og risiko:**
- Krever fase 2.
- `localeCompare('no')` påvirker rekkefølge ved likt. Test med æ, ø, å.
- Sesongteksten «tre beste» er uavklart (SPEC 4.6.2).

**Anslag:** 6–8 økter.

---

### Fase 5 – Påmelding, varsler og Deg

**Mål:** Spillerne trenger ikke PWA-en mellom kveldene.

- [ ] Svar på kvelden: Kommer / Usikker / Kommer ikke + kommentar (`svarPaaDato`), angre i 8 s, loggtekster som PWA-en.
- [ ] Terminliste (les), sosialkomité, kveld rykker opp når ferdig (`kveldErFerdig`).
- [ ] Varsler: aktivitetslogg «I dag / Tidligere», ulest per enhet, reaksjoner (`activity_reaksjoner`).
- [ ] Deg: handicapindeks (komma tillatt, `parseHcp`), portrett (`klubbilder`), koblede innloggingsmåter (Apple/Google/e-post), logg ut.
- [ ] Kalender: lenke til eksisterende abonnement (`/api/kalender/<token>.ics`) via `webcal://`.

**Ferdig når:**
- Jeg svarer «Usikker» med kommentar i appen, og PWA-en viser det. Angre virker.
- Aktivitet fra PWA-en dukker opp i Varsler, og en reaksjon i appen vises i PWA-en.
- Jeg endrer handicap til «18,4» og PWA-en viser 18,4.

**Tester:** `paamelding-svar-test.js`, `paamelding-test.js`, `terminliste-test.js`, `reaksjoner-test.js`, `kvelder-test.js`, `neste-kveld-test.js`. Oppførsel fra `kalender-del-test.js`, `klubbilder-test.js`.

**Avhengigheter og risiko:**
- Krever fase 1. Kan gjøres parallelt med fase 4.
- Aktivitetsloggen er HTML-tekst med emoji-prefiks. Ikonvalg må parses som i PWA-en (`AKTIVITET_IKON`).

**Anslag:** 4–6 økter.

---

### Fase 6 – Arrangørsiden

**Mål:** Arrangøren kan sette opp, kjøre og avslutte en kveld helt i appen, uten å ødelegge noe PWA-en fortsatt gjør med penger.

- [ ] Start runde-veiviser i tre steg, lagre som kladd, rediger kladd, start (blokkert hvis en runde går).
- [ ] Båser og markører (`foreslaatteBaaser`, `saveBaaser`), matcher for hånd (`saveMatcher`), lag (`saveLag`), forslag om form (`oppsettForAntall`, `formerSomPasser`), `trekkMatcher`.
- [ ] Par-bekreftelse og banebekreftelse (`bekreftBaneoppsett` med 23505-håndtering), forslag til LD/KP-hull.
- [ ] Innstillinger for runden: bytt bane (regn om), `hcp_extern`, LD/KP av/på, vekt.
- [ ] Rett en score, Rundene (tabell, retting i låst runde, logges).
- [ ] Avkort runden med effekt-forhåndsvisning (`avkortingenKoster`, `saveAvkorting`).
- [ ] **Avslutt kvelden:** lås runden og kjør de samme etterarbeidene som PWA-en gjør i dag, uten egen UI for penger: `oppdaterMarkeder` (`vilkaarUtfall`, `skalLukkes`), `avregnKvelden` (`veddemaalPoster`, `kupongPoster`, idempotent) og `kunngjorTippekongen`. Ellers blir veddemålene og skyldlisten i PWA-en feil (B10).
- [ ] Slett runde via RPC `slett_runde(rid)` med oppsummering.
- [ ] Klubb-oppsett: tropp (legg til, seed, frigjør innlogging), baner, terminliste og sosialkomité, arrangører, push-kategorier (`push_av`).
- [ ] Purring og melding til alle (`activity_log` med `til`).

**Ferdig når:**
- Jeg setter opp to kladder for en kveld i appen, starter dem etter tur, og PWA-en viser samme båser, matcher og lag.
- Jeg avkorter en runde etter 14 hull, og effekten per spiller er lik den PWA-en viser.
- «Avslutt kvelden» i appen gir samme avgjorte veddemål og samme poster i PWA-en som om arrangøren hadde brukt PWA-en. Kjørt to ganger gir den ingen nye.

**Tester:** `kladd-test.js`, `rediger-kladd-test.js`, `markor-test.js` (`foreslaatteBaaser`), `paamelding-test.js` (`oppsettForAntall`), `skjevt-lag-test.js`, `trekant-test.js` (`trekkMatcher`), `banebekreftelse-test.js`, `baneskjema-test.js`, `banevalg-test.js`, `slett-runde-test.js`, `rundene-test.js`, `avkorting-test.js`, `seeding-test.js`, `tropp-test.js`, `kunngjoring-test.js`, `push-kategorier-test.js`, `vilkaar-test.js`, `kveld-test.js`, `poster-test.js` (bare `veddemaalPoster` og `avregnKvelden`). Pluss egne for `trekkSosialkomite` (injisert tilfeldighet), forslag til LD/KP-hull, `lagdeling`.

**Avhengigheter og risiko:**
- Krever fase 2 og 4 (veddemål på `match`, `drive` og `kp` bruker matchstilling og sidepremier).
- **Uavklart (SPEC 3.5):** om par-bekreftelse virker for en markør som ikke er arrangør. Avklares mot test først i fasen.
- Delete-then-insert for båser, lag og matcher er ikke atomisk. Kopieres som i PWA-en.
- Avregningen er ekte penger i PWA-en så lenge den lever. Ingen snarveier på avrunding (`rund2`).

**Anslag:** 11–16 økter.

---

### Fase 7 – Tippekupong og kveldens tråd

**Mål:** Det siste av kvelden som i dag bare finnes i PWA-en.

- [ ] Tippekupong: fem spørsmål, frist i Oslo-tid (`tipsFrist`, `tipsAapen`), lagre/trekk, andres tips etter låsing, `tips_levert()`.
- [ ] Fasit og resultat: `tipsFasit`, `tipsRiktig`, `tipsResultat`, «Tippekongen». Oppgjøret i kroner vises ikke i appen (B10), men `kupongPoster` kjøres ved avslutning (fase 6) så PWA-en stemmer.
- [ ] Kveldens tråd: tekst, @navn, slett, uleste, push-valg (`prat_push`). Bilde fra bildebiblioteket (kamera i fase 8).
- [ ] Varsle `/api/prat-push` etter sendt melding, som PWA-en.

**Ferdig når:**
- Jeg leverer kupong i appen før kl 17, og den låses når første slag føres i PWA-en.
- Etter kvelden gir appen og PWA-en samme fasit og samme vinnere.
- En melding fra appen vises i PWA-ens tråd, og omvendt.

**Tester:** `tippekupong-test.js`, `kveldens-traad-test.js`, `traad-bilder-test.js`. Pluss egne for `tipsRiktig`, `tipsBeste`, `tipsKomplett`, `osloTidspunkt` rundt sommertid.

**Avhengigheter og risiko:**
- Krever fase 2.
- `meldinger` krever `created_at` innen ±1 min av serverens klokke. Utelat feltet.
- Bildesti må være `<spiller>/<melding>.jpg`: generer id før opplasting.

**Anslag:** 6–8 økter.

---

### Fase 8 – Native løft

**Mål:** Det PWA-en aldri kunne: push for alle, Live Activity, widgets, kamera og kalender.

- [ ] **APNs-push** (B5): tabell for enhetstokens (SQL til godkjenning), sender på serversiden (worker eller Edge Function), samme kategorier og `push_av` som i dag. Testes på test før prod.
- [ ] Varselvalg i appen som speiler `push_av` og `prat_push`.
- [ ] **Live Activity** under runde: hull, egen score, stilling i bås/match. Oppdatert lokalt først, push-oppdatering når APNs finnes.
- [ ] **Widgets:** neste kveld og jakketabell.
- [ ] **Kamera** i tråden, komprimert til 1600 px JPEG som PWA-en.
- [ ] **Kalender:** «Legg i kalender» via EventKit, i tillegg til abonnement.
- [ ] Deling av tavla og resultater via delingsark.

**Ferdig når:**
- Jeg får push på telefonen når noen gjør birdie, uten at PWA-en er installert.
- Live Activity viser hull og stilling på låseskjermen under hele runden.
- Widgeten viser neste kveld og topp 3.

**Tester:** `push-kategorier-test.js` (kategori av/på). `push-paaminnelse-test.js`, `push-status-test.js` og `push-worker-test.mjs` gjelder serversiden og får tilsvarende tester der senderen bygges, ikke i appen.

**Avhengigheter og risiko:**
- APNs krever en databaseendring og en server-komponent (B5). Ikke uten godkjent SQL.
- Web push og APNs må gå parallelt så lenge noen bruker PWA-en, uten doble varsler.

**Anslag:** 10–15 økter.

---

### Fase 9 – Hele gjengen på appen

**Mål:** Alle bruker iOS-appen mot prod for alt som er bygget, med PWA-en som reserve og for penger.

- [ ] TestFlight-invitasjon til alle i gjengen.
- [ ] Innlogging for alle: hver spiller kobler Apple eller Google, eller fortsetter med e-postkode.
- [ ] Generalprøve på test: en hel kveld med bare iOS, også arrangøren.
- [ ] En hel prod-kveld der ingen åpner PWA-en for noe annet enn penger.
- [ ] Liste over det som fortsatt mangler før PWA-en kan pensjoneres.

**Ferdig når:**
- Alle i gjengen har appen og har logget inn.
- En hel prod-kveld er gjennomført i appen, og tallene stemmer med det PWA-en viser.

**Tester:** Hele Swift-testsuiten grønn. Paritetssjekk mot PWA-en på en kopi av en ekte kveld fra prod (leses, ikke skrives).

**Avhengigheter og risiko:**
- Krever fase 1–7. Fase 8 er ønsket, men ikke et krav.
- Hvis noen ikke har iPhone, kan PWA-en ikke pensjoneres helt (B3).

**Anslag:** 3–5 økter (pluss kveldene).

---

### Fase 10 – Veddemål på nytt og pensjonering av PWA-en

**Mål:** Bestemme og bygge veddemål for appen, og ta PWA-en ut av bruk.

- [ ] Beslutning om modell (B10): poeng i stedet for penger, penger som i dag, eller ingen veddemål.
- [ ] Hvis poeng: egen poengmodell (ikke `poster` i kroner), krever sannsynligvis databaseendring (SQL til godkjenning) og en regel for hva som skjer med åpne pengeveddemål og gammel gjeld i PWA-en.
- [ ] Bygge vedd-ark, liste og avgjøring i appen etter valgt modell (`forsteApneHull`, `markedTarInnsatser`, `vilkaarUtfall` er allerede portert i fase 6).
- [ ] Gjøre opp eller fryse gjenværende gjeld i PWA-en før den pensjoneres.
- [ ] Pensjonering: PWA-en viser «bruk appen», eller blir stående som nødløsning ut sesongen (B3).

**Ferdig når:**
- Gjengen har vedet (eller bevisst valgt bort veddemål) en hel kveld i appen.
- Ingen åpen gjeld er igjen bare i PWA-en.
- PWA-en er ikke nødvendig for noe.

**Tester:** `lockout-test.js`, `status-del-test.js`, og de delene av `vilkaar-test.js` og `poster-test.js` som gjelder valgt modell. `utlegg-test.js` hvis utlegg beholdes.

**Avhengigheter og risiko:**
- Krever fase 9 og B10.
- En poengmodell i samme database som PWA-ens pengemodell kan forvirre så lenge begge lever. Byggestart først når PWA-en snart skal pensjoneres.

**Anslag:** 5–10 økter, avhengig av modell.

---

**Totalt:** ca. 66–99 økter. Usikkerheten er størst i fase 2 (paritet), 6 (arrangør og avregning) og 8 (server-del).

---

## 3. BESLUTNINGER

Status: **Tatt** (av deg eller meg etter fullmakt), eller **Åpen**.

### B1 – Distribusjon · Tatt (meg)
**Ekstern TestFlight med e-postinvitasjon.** Uten ekte penger i appen (B10) er Apples beta-gjennomgang lite risikabelt, og eksterne testere slipper å bli brukere i App Store Connect. Bygg utløper etter 90 dager og må fornyes. Krever betalt Apple Developer-medlemskap. Offentlig App Store er ikke et mål for v1.
*Konsekvens:* hvis veddemål med penger kommer tilbake (B10), må dette vurderes på nytt (Apples regler for pengespill, retningslinje 5.3). Jeg har ikke verifisert gjeldende ordlyd.

### B2 – Spillogikk · Tatt (meg)
**Portere `db-nytt.js` til Swift med like tester.** Ingen databaseendring, virker offline, PWA-en er urørt.
*Konsekvens:* to implementasjoner må holdes like så lenge PWA-en lever. Flytting til Postgres kan vurderes etter pensjonering, når det bare finnes én klient.

### B3 – Sameksistens og pensjonering · Tatt (deg)
**PWA-en lever til appen er god nok til å overta.** Begge bruker samme database, så sesongen fortsetter der den slapp uten flytting av data.
- iOS skriver nøyaktig som PWA-en (SPEC 4.9). Ingen nye kolonner eller tolkninger.
- Avregning ved «Avslutt kvelden» gjøres likt i begge apper (fase 6), så PWA-ens skyldliste stemmer selv om appen ikke viser penger.
- Aktivitetslogg og varsler skal ikke dobles når begge apper brukes samme kveld.
- Pensjonering skjer i fase 10.

**Åpent spørsmål:** har alle 12 iPhone? README siterer «Vi har bare iPhone», men det bør bekreftes.

### B4 – Prod · Tatt (meg)
**Test fram til og med prøvekvelden i fase 3. Deretter prod for markørene, med din godkjenning før første prod-skriving.** Konfig for test og prod skilles tydelig i appen.

### B5 – Databaseendringer · Tatt (meg), hver endring godkjennes av deg
Endringer planen kan trenge:
- **Tabell for APNs-enhetstokens** og en sender (fase 8).
- **Realtime-publikasjon** for tabeller appen abonnerer på, hvis de mangler (SPEC 3.5).
- **`round_holes.meters`** finnes kanskje ikke (SPEC 3.5). Sjekkes først.
- **Poengmodell for veddemål** (fase 10), hvis B10 lander på poeng.

Prosess:
1. SQL skrives som fil i dette repoet (`sql/`), aldri i `referanse/`.
2. Du godkjenner SQL-en.
3. Kjøres på **test**, med kontrollspørringer og rullebakke i fila (som PWA-ens migreringer).
4. PWA-test og iOS testes mot test.
5. Prod først etter ny godkjenning.
6. Husk anon-fella: `revoke execute … from anon` etter hver `create or replace`, og sjekk returnerte rader (SPEC 3.2).

### B6 – Lokal lagring · Tatt (meg)
**SwiftData** for cache og utboks. Domenelogikken ligger i rene Swift-typer utenfor, så den kan testes og deles med widgets og Live Activity.

### B7 – Deployment target og Swift · Tatt (meg)
**iOS 26.0 og Swift 6-språkmodus.** Prosjektet står i dag på 26.5 og Swift 5, som stenger ute telefoner på 26.0–26.4. Endres i Xcode.

### B8 – `referanse/` i git · Tatt (deg)
**Holdes utenfor git** (`.gitignore`), fordi mappa inneholder nøkler.

### B9 – Innlogging · Tatt (deg), oppsett må godkjennes
**Apple, Google og eksisterende e-postkode.**
- Apple: native, via `AuthenticationServices` og `signInWithIdToken`.
- Google: OAuth via `supabase-swift` i nettleserark, uten ekstra SDK.
- Eksisterende spillere kobler Apple/Google til kontoen sin (`linkIdentity`), slik at `players.user_id` og PWA-innloggingen er uendret.
- Nye spillere kan logge inn rett med Apple/Google og velge navn.

**Krever din godkjenning før det gjøres:** i Supabase (test først) må Apple og Google aktiveres som providers og manuell identitetskobling slås på. Det er konfig, ikke SQL, men det er en endring i Supabase. Apple Developer- og Google Cloud-oppsett gjør du (eller vi sammen).

### B10 – Veddemål og penger · Utsatt (deg)
**Appen viser ikke penger eller veddemål i første omgang.** Avregningen ved «Avslutt kvelden» porteres likevel (fase 6), så PWA-ens penger stemmer så lenge den lever. Modellen bestemmes i fase 10.

| Alternativ | Konsekvens |
|---|---|
| **Poeng i stedet for penger** (min anbefaling) | Ingen pengespill-risiko hos Apple. Gjengen kan fortsatt vedde. Krever egen poengmodell og sannsynligvis en databaseendring. Gammel gjeld i kroner må gjøres opp i PWA-en først. |
| Penger som i dag | Bare porting, men risiko ved Apples gjennomgang (B1). |
| Ingen veddemål | Minst arbeid, men tar bort en del av kvelden gjengen bruker. |

### B11 – Lukket for nå
- **GPS/avstand til green:** utenfor v1 (seksjon 4).
- **Tellende runder:** alle 7 kvelder teller, som PWA-en. Teksten «tre beste» på Sesongsiden er utdatert og følges ikke.

---

## 4. UTENFOR OMFANG (første ferdige versjon)

- **Penger og veddemål med kroner i appen** (B10). Avregningen kjører i bakgrunnen for PWA-ens skyld.
- **Bøter, utlegg og bøtekasse.** Henger sammen med penger og avgjøres sammen med B10.
- **GPS og avstand til green.** PWA-en har det ikke, og databasen har ingen banegeometri.
- **Apple Watch.**
- **Ekte bane** (ikke simulator) som eget bruksmønster.
- **Android.** Hvis noen trenger det, blir PWA-en stående (B3).
- **iPad-tilpasset bred modus** for arrangør. Appen kjører på iPad som iPhone-layout.
- **Plakaten for kvelden** (canvas til Instagram). PWA-en kan brukes til den så lenge den lever.
- **Regelendringer:** skins, halve slag, to runder samtidig, påmelding per runde, flere sesonger eller klubber. Appen gjør det PWA-en gjør.
- **Flytting av logikk til Postgres** (B2) og retting av RLS-hull. Etter pensjonering.
- **E-postreserve og kalender-endepunkt.** Blir i `_worker.js` som i dag.
- **Den gamle banken** (`bank_bevegelser`, saldo, innskudd).

---

## Vedlegg A – PWA-tester og hvor de dekkes

| Test | Fase | Merknad |
|---|---|---|
| `brutto-test.js`, `seeding-test.js`, `parspill-test.js`, `baneoppsett-test.js`, `banepar-test.js`, `banehull-test.js`, `banebytte-test.js`, `trackman-test.js` | 2 | Regneregler |
| `avkorting-test.js` | 2, 6 | Poeng (2), avkort-flyt og hengende veddemål (6) |
| `markor-test.js` | 2, 6 | `kanFore` (2), `foreslaatteBaaser` (6) |
| `tropp-test.js` | 2, 6 | |
| `match-test.js`, `matchrunde-test.js`, `matcher-test.js`, `trekant-test.js`, `seier-test.js`, `sesong-test.js`, `skjevt-lag-test.js`, `sidepremie-valgfritt-test.js` | 4 | |
| `kvelder-test.js`, `neste-kveld-test.js` | 1, 4, 5 | |
| `paamelding-test.js` | 1, 5, 6 | |
| `innlogging-test.js`, `innmelding-test.js`, `uinnloeste-rader-test.js` | 1 | Oppførsel ved innlogging og å ta navn |
| `paamelding-svar-test.js`, `terminliste-test.js`, `reaksjoner-test.js` | 5 | |
| `kladd-test.js`, `rediger-kladd-test.js`, `banebekreftelse-test.js`, `baneskjema-test.js`, `banevalg-test.js`, `slett-runde-test.js`, `rundene-test.js`, `kunngjoring-test.js` | 6 | |
| `vilkaar-test.js`, `kveld-test.js` | 6, 10 | Avgjøring ved avslutning (6), vedd-UI (10) |
| `poster-test.js` | 6, 10 | `veddemaalPoster` og `avregnKvelden` (6), skyldliste (10) |
| `lockout-test.js`, `status-del-test.js` | 10 | Innsats-låsing i vedd-UI |
| `utlegg-test.js` | 10 | Hvis utlegg beholdes |
| `tippekupong-test.js`, `kveldens-traad-test.js`, `traad-bilder-test.js` | 7 | |
| `push-kategorier-test.js` | 6, 8 | |
| `push-paaminnelse-test.js`, `push-status-test.js`, `push-worker-test.mjs`, `kalender-worker-test.mjs` | 8 | Serverside, ikke i appen |
| `hent-paa-nytt-test.js`, `skjema-realtime-test.js` | 1, 3 | Oppførsel, ikke tall |
| `kalender-del-test.js`, `klubbilder-test.js` | 5 | Oppførsel |
| `knapper-test.js`, `toast-test.js` | – | UI-regler (dobbelttrykk, toast-kø). Hensikten videreføres, ikke testene |
| `porten-test.js`, `bred-test.js`, `globalnavn-test.js`, `plakat-test.js` | – | PWA-spesifikke eller utenfor omfang |
