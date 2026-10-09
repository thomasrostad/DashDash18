# ROADMAP: DashDash18

Plan fra dagens tomme Xcode-prosjekt til en iOS-app som erstatter GolfGutu-PWA-en for hele gjengen. Grunnlag: `SPEC.md`, `CLAUDE.md`, `referanse/golfgutu-pwa/` (særlig `README.md` og `db-nytt.js`).

Henvisninger som «SPEC 4.9» peker til seksjoner i `SPEC.md`.

---

## STATUS

| | |
|---|---|
| **Nåværende fase** | Fase 12–17 bygget. På test er 011–024 kjørt (08.10). Slått på: alt unntatt Google-innlogging og kjøp (onboarding uten klubb på 09.10), som venter på oppsett i App Store Connect og Google og på publisert personvern (`docs/gjoremal.md`). |
| **Sist gjort** | 08.10: arrangørsiden gjennomgått mot beste praksis og omstrukturert (fase 11, `docs/arrangorsiden-vurdering.md`): Kveldene/Kvelden, én rundeliste, én oppsettsflyt, «Kom i gang», sesong lander på aktiv. Hjem-feed vurdert i `docs/hjem-feed.md`. Før det, 07.10: total gjennomgang av oppførselen i fem områder (Kveld/admin-runde, Runde/utboks/Live Activity, Tavla/deling/widgets/veddemål, Tråd/varsler/push/tips/Deg, innlogging/klubb/app-skall/admin). Rundt 45 feil rettet, bl.a. hull i kø som forsvant etter omstart, oppstart uten nett, live-oppdatering av Kveld og Tavla, push mens appen er åpen. 680 enhetstester grønne. |
| **Neste oppgave** | Fase 12–17 er bygget, og 019–027 og 029–032 er kjørt på test. `delete-account` er deployet. Gjenstår: oppsett i App Store Connect og Google (`docs/gjoremal.md` C), så `verify-purchase` med IAP-nøkkelen og flaggene for kjøp og Google (onboarding er på). Prøve arrangørflyten på telefon. Deretter byttet for gjengen (fase 9) og prod. |
| **Venter på deg** | Beta App Review for første eksterne bygg. «Allow manual linking» i Supabase Auth (Apple-kobling). Prøve LD/KP, avkorting og avslutt kvelden på telefon. B15: slope.no dekker CR/slope for nordiske baner (fase 20); GolfAPI.io trengs bare for par og indeks per hull. Google-innlogging. |

---

## 1. MÅLBILDE

«Ferdig» betyr:

1. **Gjengen spiller en hel kveld i appen, uten PWA-en.** Påmelding, oppsett, start, føring per bås, LD/KP, tippekupong, tråd, avkorting og avslutning gjøres i appen, av spillere, markører og arrangør.
2. **Turneringen er ikke låst.** Antall spillere, antall kvelder, hva som teller, poengmodell, former og sidepremier settes av arrangøren i admin-panelet.
3. **Golfgutu-oppsettet gir samme svar som PWA-en.** Med regelsettet som gjengir PWA-ens regler, gir appen samme stableford, slag, match, jakketabell og tips som `db-nytt.js`. Hver regel har en Swift-test med tall fra PWA-ens tester eller utledet fra koden (SPEC 4).
4. **Appen har sin egen Supabase.** Historikken fra PWA-en er importert, så sesongen fortsetter der den slapp.
5. **Appen er distribuert til alle** i gjengen med iPhone via TestFlight.
6. Føring virker med dårlig dekning: ingen hull går tapt når nettet faller ut.

---

## 2. FASER

Hver fase gir noe som kan prøves. Fram til byttet (fase 9) foregår alt mot appens **test**-prosjekt, mens gjengen fortsetter å bruke PWA-en på torsdager. «Ekte kveld» betyr derfor en kveld spilt i appen ved siden av PWA-en, eller en prøvekveld med noen av gutta.

Tester i parentes er filer i `referanse/golfgutu-pwa/tests/`. Hver av dem skal ha en Swift-test som gir samme svar med Golfgutu-oppsettet. Fullstendig oversikt står i vedlegg A.

---

### Fase 1 – Grunnmur, ny Supabase og innlogging

**Mål:** Logge inn i appen mot en ny, egen test-database med Apple, Google eller e-postkode.

- [x] Sette deployment target til iOS 26.0 og Swift 6-språkmodus i Xcode (B7). Ikke via `project.pbxproj`.
- [x] Rydde malkoden (`Item.swift`, mal-`ContentView`) og opprette mappestrukturen. *(App-skall med fanene Kveld, Tavla, Deg.)*
- [x] Legge til `supabase-swift` via Swift Package Manager i Xcode (2.55.3, koblet til target DashDash18).
- [x] Miljøkonfig for test og prod i filer som ikke sjekkes inn, med tydelig visning av miljø i appen. *(`Config/Supabase-<Miljø>.plist` utenfor git, `AppConfig` avviser feil miljø og hemmelig nøkkel, TEST-merke i verktøylinjen og miljø i Deg.)*
- [x] **Skjema v1** for kjernen (SQL i `sql/`, til godkjenning): klubb/tropp, medlemmer og roller, sesong med regelsett (B12), kveld, påmelding, bane og hull, runde, deltakere, bås og markør, lag, match, score. Med RLS og grants, også anon-revoke. *(`sql/001_skjema_v1.sql`, godkjent 06.10.)*
- [x] Kjøre skjemaet på test etter godkjenning, med kontrollspørringer. *(10/10 ok, anon får 42501.)*
- [ ] Innlogging: Logg inn med Apple (native), Google (OAuth) og e-postkode (B9). Supabase-konfig godkjennes først. *(06.10: e-postkode prøvd på telefon via Resend fra `noreply@dashdash18.com`. Logg inn med Apple bygget og slått på i Supabase. Google gjenstår.)*
- [x] Første innlogging: velg navn i troppen eller bli med som ny. Arrangør kan godkjenne og frigjøre. *(06.10: lag klubb, bli med med kode, ta ledig navn eller vent på godkjenning, Deg viser klubb/rolle/kode. Godkjenning i admin kommer i fase 3. «Lag en ny klubb» prøvd på telefon mot test 06.10.)*
- [x] Rolig Kveld-skjerm som viser «Ingen kveld satt opp» og hvem som er logget inn. *(Erstattet av Kveld-fanen med neste kveld og påmelding.)*

**Ferdig når:**
- Jeg logger inn på telefonen med Apple, logger ut, logger inn med Google og med e-postkode. Hver gang er jeg samme spiller (eller kan koble kontoene).
- Appen viser at den kjører mot test, og kan ikke nå prod ved et uhell.
- En annen bruker uten rolle kan ikke lese eller endre andres data utover det RLS tillater (sjekket med to kontoer).

**Tester:** Swift-tester for radmapping og konfig. Oppførselen fra `innlogging-test.js`, `innmelding-test.js` og `uinnloeste-rader-test.js` (ta ledig navn, ikke ta andres).

**Avhengigheter og risiko:**
- Du oppretter Supabase-prosjektene (B4).
- Apple-innlogging trenger Sign in with Apple i Apple Developer (tjeneste-ID og nøkkel). Google trenger en OAuth-klient i Google Cloud.
- Skjemaet bestemmer mye av resten. Det må være generelt nok for B12, men ikke større enn kjernen trenger. Resten kommer i senere migreringer.

**Anslag:** 7–10 økter.

---

### Fase 2 – Regelmotor med Golfgutu-oppsettet

**Mål:** Hele poeng- og handicaplogikken i Swift, styrt av regelsettet, med samme svar som PWA-en for Golfgutu-oppsettet.

- [x] Regelsett-modell (B12) med Golfgutu-oppsettet som ferdig mal. *(Minimal. Har også `stablefordCountingEvenings = 5` for tiebreak-paritet.)*
- [x] Bane og hull: `courseForRound` med rang-strokeindex og start på hull 10, standard-par, lengdesjekk, `baneErKlar` (SPEC 4.1).
- [x] Handicap: `courseHandicap`, andel, seeding med valgfrie grupper, `banehandicap`, `lagGrunnlag`, `lagHandicap`, `effectiveHandicap`, ekstern handicap (Trackman), brutto (SPEC 4.2).
- [x] Slag og poeng: `handicapStrokesForHole`, `pointsForHole`, `scoreNameForHole`, `poengFraHull` (SPEC 4.3).
- [x] Former: `KONKURRANSEFORMER` som data, `formForRunde`, lagdeling og forslag (SPEC 4.4).
- [x] Avkorting: tre regler, `tellendeHull`, `lavesteFellesHull` (SPEC 4.5).
- [x] Avrunding som JS i én hjelper (`floor(x + 0.5)`, `rund2`) og norsk sortering (SPEC 4.0).
- [x] Testtall som JSON-fixtures (CLAUDE.md). *(Generert fra `db-nytt.js` i Node; bokstavelige tall fra PWA-testene kontrollert.)*
- [x] Pakken lagt til i Xcode-prosjektet (bruker: *Add Local…*), og appen bygger med den.

*Status 06.10: 49 tester i 7 suiter grønne med `swift test`. Avvik: par er `Int?` (JS godtar desimal/tekst; testen for par som tekst er hoppet over). Andel og `hcp_extern` for nye runder kommer fra `app-nytt.js`.*

**Ferdig når:**
- Alle Swift-tester for fasen er grønne, og hver PWA-test listet under har en tilsvarende test med samme tall.
- Jeg kan lese en kort rapport som viser at de samme fem eksempelrundene gir samme poeng i Swift som PWA-ens tester.

**Tester:** `brutto-test.js`, `seeding-test.js`, `parspill-test.js`, `baneoppsett-test.js`, `banepar-test.js`, `banehull-test.js`, `banebytte-test.js`, `trackman-test.js`, `avkorting-test.js` (poeng), `paamelding-test.js` og `skjevt-lag-test.js` (lagdeling). Pluss egne tester der PWA-en mangler: `scoreNameForHole`, `rundeAndel`, `lagGrunnlag`, `poengForTomtHull`, start på hull 10 mot 18-hulls bane, `lagdeling`.

**Avhengigheter og risiko:**
- Kan startes parallelt med fase 1 (ingen nettverk).
- Risiko: små avvik i avrunding, JS-sannhet og rekkefølge (SPEC 4.0). Mot: tester først, tall fra PWA-en.
- Regelsettet kan friste til å bygge for mye. Bare det PWA-en gjør pluss det som trengs for at antall og telling ikke er låst. Mer kommer senere.

**Anslag:** 8–12 økter.

---

### Fase 3 – Admin-panel: tropp, baner, sesong og terminliste

**Mål:** Arrangøren kan sette opp en sesong i appen, med egne regler, egne spillere og egne baner.

- [x] Regelsett-revisjon: alle regelverdier i regelmotoren leses fra `Ruleset` (CLAUDE.md «Ingen regelverdier i koden»), inkludert «beste N» som kvelder eller matcher. Golfgutu-oppsettet gir fortsatt samme svar som PWA-en. *(06.10: Ruleset v2, se `Packages/GolfgutuCore/REGELSETT.md`. 80 tester grønne.)*
- [x] Admin-panel (kun arrangør): Sesong og regelsett (start fra Golfgutu-oppsettet, endre antall kvelder, hva som teller, poengmodell, sidepremier, handicapmodell, tillatte former, maks per bås). *(06.10: hele Ruleset v2, live validering, «Slik telles det». Ikke prøvd mot database.)*
- [x] Tropp: legg til og fjern spillere uten tak på antall, handicapindeks, seeding, roller (arrangør, kasserer), frigjør innlogging. *(06.10: også godkjenn/avvis, arkiver. Ikke prøvd mot database.)*
- [x] Baner: liste, rediger par, indeks, lengde, CR og slope, bekreftet-status. Import av PWA-ens 18 baner fra referansens SQL-filer eller fra PWA-basen (lesing). *(06.10: 18 Golfgutu-baner som JSON-import. CR-spørsmål åpent. Søk etter ekte baner: B15.)*
- [x] Terminliste: kvelder med dato, tid, sted, sosialkomité. *(06.10: også trekning av sosialkomité.)*
- [ ] Skjema-tillegg ved behov (SQL til godkjenning). *(002, 004, 005 godkjent og kjørt på test 06.10; appen bruker RPC-ene.)*

**Ferdig når:**
- Jeg setter opp en sesong med 5 kvelder og «beste 3 teller» for 9 spillere, og en med Golfgutu-oppsettet for 12. Begge lagres og vises riktig.
- Alle 18 baner fra PWA-en ligger i appen med samme par og indeks.
- En spiller uten arrangør-rolle ser ikke admin-panelet og kan ikke endre noe via API.

**Tester:** `banebekreftelse-test.js`, `baneskjema-test.js`, `banevalg-test.js`, `banepar-test.js`, `terminliste-test.js`, `tropp-test.js`, `seeding-test.js` (rolle-delen), `trekant-test.js` (`trekkSosialkomite` har ingen PWA-test, egen test med fast tilfeldighet).

**Avhengigheter og risiko:**
- Krever fase 1 og regelsett-modellen fra fase 2.
- Regelsettet må ha gyldighetssjekk (for eksempel «beste N» der N > antall kvelder).

**Anslag:** 7–10 økter.

---

### Fase 4 – Påmelding og oppsett av kvelden

**Mål:** Spillerne melder seg på i appen, og arrangøren setter opp kvelden (kladd, båser, markører, form, lag, matcher) og starter den.

- [x] Påmelding: Kommer / Usikker / Kommer ikke + kommentar, angre, purring av de som ikke har svart. *(06.10: svar og kommentar. Purring bygget senere. 08.10: angre som i PWA-en: svaret vises med en gang, sendes etter 8 s eller når appen legges bort, og først da får de andre hendelsen. Ikke prøvd på telefon.)*
- [x] Kveld-skjerm, rolig: neste kveld, påmeldte, sosialkomité. *(06.10.)*
- [x] Start runde-veiviser i tre steg: bane og tid, hvem og båser, oppsett. Lagre som kladd, rediger kladd, start (blokkert hvis en runde går). *(06.10. Ikke prøvd mot database. 08.10: veiviseren er erstattet av hurtigstarten, fase 11.)*
- [x] Båser og markør (`foreslaatteBaaser`), matcher for hånd, lag, forslag om form (`oppsettForAntall`, `formerSomPasser`), `trekkMatcher`. *(06.10: trekning på navn til tabellen finnes, fase 6.)*
- [x] Forslag til LD- og KP-hull. Par-bekreftelse før føring. *(06.10: markør bekrefter med confirm_round_par, sql/007.)*
- [x] Flere runder samme kveld. *(06.10.)*

**Ferdig når:**
- Fem test-spillere melder seg på fra egne telefoner (eller simulator), og jeg ser svarene.
- Jeg lager to kladder for samme kveld, starter den første, og den andre nektes til den første er avsluttet.
- Båser, markører, lag og matcher blir som jeg satte dem.

**Tester:** `paamelding-svar-test.js`, `paamelding-test.js`, `kvelder-test.js`, `neste-kveld-test.js`, `kladd-test.js`, `rediger-kladd-test.js`, `markor-test.js` (`foreslaatteBaaser`), `matcher-test.js`, `trekant-test.js` (`trekkMatcher`), `skjevt-lag-test.js`, `sidepremie-valgfritt-test.js`.

**Avhengigheter og risiko:**
- Krever fase 2 og 3.
- Lagring av båser, lag og matcher gjøres som én RPC (atomisk), ikke slett-så-sett-inn som i PWA-en.

**Anslag:** 7–10 økter.

---

### Fase 5 – Føring per bås, offline og første prøvekveld

**Mål:** Markøren fører en hel runde for båsen sin på iPhone, også uten dekning, og alle ser det live.

- [x] Kveld-skjerm, spill: hullprikker, hullkort for hele båsen, «Bayen nå». *(06.10.)*
- [x] Hullkort: stepper, «N slag fått», regnestykket, score-merke, bekreft hver spiller, «Lagre hull» låst til alle er ført. *(06.10.)*
- [x] Skriverett (`kanFore`) i appen og i RLS: arrangør, markør for egen bås, ellers seg selv. *(06.10: følger can_score.)*
- [x] Lagring av et hull for hele båsen i én RPC (atomisk, idempotent). *(save_hole via utboksen.)*
- [x] Seer-modus for ikke-markør. Følg båsens hull, sol-stripe. *(06.10.)*
- [x] Lokal lagring med SwiftData (B6): cache og utboks. Hull i kø sendes i rekkefølge med nye forsøk, også etter at appen er drept. *(06.10: utboks med kø, komprimering, backoff. Ikke prøvd i flymodus.)*
- [x] Realtime og henting på nytt når appen blir aktiv. *(06.10.)*
- [x] Scorekort Ut/Inn. Feiring (birdie, eagle, albatross, hole in one) med redusert-bevegelse-støtte. *(06.10.)*
- [ ] TestFlight-oppsett og første bygg til noen i gjengen (B1).
- [ ] Prøvekveld: en kveld der minst én bås fører i appen ved siden av PWA-en.

**Ferdig når:**
- Jeg fører 9 hull for fire spillere, og poengene i appen er de samme som PWA-en ville gitt for samme slag.
- En spiller som ikke er markør kan ikke føre, og ser tallene live på sin telefon.
- Flymodus på, tre hull ført, flymodus av: alle tre hull er lagret på serveren.
- Appen drept med hull i kø, åpnet igjen: hullene sendes.

**Tester:** `markor-test.js` (`kanFore`), `tropp-test.js` (`kanFore`), `brutto-test.js` (regnestykket), `banebytte-test.js` (poeng etter retting). Swift-tester for utboksen (rekkefølge, idempotens, nye forsøk). Oppførsel fra `hent-paa-nytt-test.js` og `skjema-realtime-test.js`.

**Avhengigheter og risiko:**
- Krever fase 4.
- Hvis vi lagrer poeng i stedet for å regne dem, må de alltid regnes fra serverens scorer (PWA-ens 41 → 3-feil, SPEC 4.9).
- Gjengen bruker fortsatt PWA-en på ekte kvelder. Dobbel føring på prøvekvelden er bevisst og må være frivillig for dem som er med.

**Anslag:** 10–14 økter.

---

### Fase 6 – Match, trekant og Tavla

**Mål:** Riktig matchstilling på kvelden og riktig tabell for sesongen, etter regelsettet.

- [x] Match: `matchSider`, `matchSlag`, `sideNettoPaaHull`, `matchHullVinner`, `matchHullDiff`, `matchUtfallForA`, `matchStilling`, `matchTekst`, `matchStillingKort`. *(Logikk i GolfgutuCore, 06.10.)*
- [x] Trekant: `trekantPoeng`. *(Også `trekkMatcher`.)*
- [x] Tabell etter regelsettet: duellpoeng, sidepremier, vekt, hva som teller (alle eller beste N), tiebreak. Golfgutu-oppsettet = `jakketavle`. *(Logikk ferdig. Åpent: «beste N» teller matcher/runder, ikke kvelder, som PWA-en.)*
- [x] LD og KP: meld egen lengde, stilling, delt ved likt. *(06.10.)*
- [x] Kveld: matchkort, «1 opp / Delt / —», stilling i «Bayen nå». *(06.10.)*
- [x] Tavla: tabell, «Slik telles det» generert fra regelsettet, spillerprofil, sesongoppsummering. *(06.10: prøvd på telefon mot test, runden vises i tabellen.)*

**Ferdig når:**
- For en importert kopi av en PWA-kveld (fase 9-importen kjørt mot test) viser Tavla samme rekkefølge, poeng og hulldifferanse som PWA-en.
- Endrer jeg regelsettet til «beste 3 teller», endrer tabellen seg som forventet.
- En fourball-match og en trekant gir samme stilling og tekst som PWA-en, hull for hull.

**Tester:** `match-test.js`, `matchrunde-test.js`, `matcher-test.js`, `trekant-test.js`, `seier-test.js`, `sesong-test.js`, `skjevt-lag-test.js`, `sidepremie-valgfritt-test.js`. Pluss egne for alle grener i `matchTekst`, delt sidepremie (0,5), `matchSum`, `sideNettoPaaHull`, og regelsett ulike Golfgutu-oppsettet.

**Avhengigheter og risiko:**
- Krever fase 5. Importen fra fase 9 kan gjøres tidlig mot test for å få ekte data å sammenligne med.
- `localeCompare('no')` påvirker rekkefølge ved likt. Test med æ, ø, å.

**Anslag:** 7–10 økter.

---

### Fase 7 – Avslutning, varsler, tråd og tippekupong

**Mål:** Resten av kvelden: avslutte, rette, snakke og tippe.

- [x] Avkort runden med effekt-forhåndsvisning (`avkortingenKoster`). *(06.10.)*
- [x] Avslutt kvelden: lås, kveld ferdig, neste kveld rykker opp. *(06.10: låser pågående runder.)*
- [x] Rett en score, Rundene (tabell, retting i låst runde, logges). Slett runde (én RPC). *(06.10.)*
- [x] Aktivitet og varsler i appen: strukturert (type + data), ikke HTML. Reaksjoner. *(06.10. Ikke prøvd mot database.)*
- [x] Deg: handicap (komma), portrett, koblede innloggingsmåter, logg ut. *(07.10. Apple-kobling bak `AccountLinkingFeature.appleEnabled = false` til «Allow manual linking» er godkjent. Ikke prøvd på telefon.)*
- [x] Kveldens tråd: tekst, @navn, bilde fra bildebiblioteket, uleste. *(06.10. Ikke prøvd mot database.)*
- [x] Tippekupong: fem spørsmål, frist i Oslo-tid, andres tips etter låsing, fasit og resultat. Innsats i poeng eller «for æra» (B10). *(06.10. Ikke prøvd mot database.)*

**Ferdig når:**
- Jeg avkorter en runde etter 14 hull og ser samme effekt per spiller som PWA-en viser for samme data.
- Kvelden avsluttes, og neste kveld vises øverst.
- En melding med bilde i tråden vises hos en annen spiller.
- Tippekupongen låses ved første slag, og fasiten er lik PWA-ens for samme kveld.

**Tester:** `avkorting-test.js`, `rundene-test.js`, `slett-runde-test.js`, `kunngjoring-test.js`, `reaksjoner-test.js`, `kveldens-traad-test.js`, `traad-bilder-test.js`, `tippekupong-test.js` (fasit og resultat; oppgjør i kroner utgår). Pluss egne for `tipsRiktig`, `tipsBeste`, `tipsKomplett`, `osloTidspunkt` rundt sommertid.

**Avhengigheter og risiko:**
- Krever fase 5 og 6.
- Tippekupongen uten penger må avklares sammen med B10.

**Anslag:** 9–13 økter.

---

### Fase 8 – Native løft

**Mål:** Det PWA-en aldri kunne: push for alle, Live Activity, widgets, kamera og kalender.

- [x] **APNs-push:** tabell for enhetstokens (SQL til godkjenning) og en sender (Supabase Edge Function), med kategorier som kan slås av og på per spiller og av arrangør. *(07.10: 010 godkjent og kjørt på test (12/12), `push-send` deployet, secrets, webhook `dd18_push_queue` og pg_cron-påminnelse satt opp, Push-capability lagt til, flagget på. Ikke prøvd på telefon. Ikke prod.)*
- [x] Varsler for store scorer, ledelsesskifte, ny runde, påminnelse før kveld, purring, tråd (nevnt/alle/av). *(07.10: hull i kø logges, ledelsen regnes på ferske data, ingen duplikater fra samme telefon. Mellom telefoner: forslag 011. Arrangørskjermene «Hva blir push» og «Hvem har push». Ikke prøvd på telefon.)*
- [x] **Live Activity** under runde: hull, egen score, stilling i bås og match. *(07.10: target DashDash18WidgetsExtension, slått på. Oppdateres bare fra appen; push-oppdatering kommer med APNs. Prøvd på telefon.)*
- [x] **Widgets:** neste kveld og tabell-topp. *(07.10: App Group `group.com.dashdash18.app`, slått på. Prøvd på telefon.)*
- [x] **Kamera** i tråden. *(07.10. Prøvd på telefon.)*
- [x] **Kalender:** «Legg i kalender» via EventKit. *(07.10: på Kveld, uten kalendertilgang. Prøvd på telefon.)*
- [x] Deling av tabell og resultater via delingsark. *(07.10: Tavla og Runde, bilde + tekst. Prøvd på telefon.)*

**Ferdig når:**
- Jeg får push når noen i gjengen gjør birdie, og kan skru av den kategorien.
- Live Activity viser hull og stilling på låseskjermen under hele runden.
- Widgeten viser neste kveld og topp 3.

**Tester:** `push-kategorier-test.js` (av/på). `push-paaminnelse-test.js` og `push-status-test.js` får tilsvarende tester for Edge Function-en.

**Avhengigheter og risiko:**
- Krever fase 5. Kan delvis gjøres parallelt med fase 6 og 7.
- APNs-nøkkel fra Apple Developer må lagres som hemmelighet i Supabase, aldri i appen.

**Anslag:** 10–15 økter.

---

### Fase 9 – Import og bytte

**Mål:** Historikken fra PWA-en ligger i appens database, og gjengen spiller neste kveld i appen.

- [x] Importverktøy (lesing fra PWA-ens prod, skriving til appens database): spillere, baner, terminliste, påmeldinger, runder med oppsett, scorer, sidepremier, tips. Idempotent, kan kjøres flere ganger. *(07.10: `Packages/DashImport`, 28 tester. Ikke kjørt på ekte data.)*
- [x] Hvordan dataene hentes ut (SQL-eksport, eller lesing med innlogget bruker) avgjøres i fasen. Ingenting skrives til PWA-basen. *(07.10: én lesende eksport-SQL, `sql/import/export_pwa.sql`. Se `docs/import-plan.md`.)*
- [ ] Kontroll: etter import viser appens Tavla det samme som PWA-ens for hele sesongen.
- [ ] Prod-oppsett av appens Supabase (skjema, innlogging, APNs) etter godkjenning.
- [ ] TestFlight-invitasjon til alle med iPhone. Hver spiller logger inn og velger navnet sitt (importert).
- [ ] Generalprøve på test med hele gjengen.
- [ ] Byttedag: siste import etter siste PWA-kveld, så neste kveld i appen.
- [ ] PWA-en fryses: viser «Vi har flyttet til appen» og lar seg ikke føre i.

**Ferdig når:**
- Tavla i appen er identisk med PWA-ens etter siste import.
- Alle med iPhone har logget inn og funnet navnet sitt.
- En hel kveld er spilt i appen på prod uten at PWA-en ble åpnet.

**Tester:** Hele Swift-testsuiten grønn. Paritetssjekk på importerte data for hele sesongen.

**Avhengigheter og risiko:**
- Krever fase 1–7. Fase 8 er ønsket, men ikke et krav.
- **Android-brukere** kan ikke bruke appen før Android finnes, og PWA-en er fryst (B13).
- Penger og veddemål i PWA-en må være gjort opp eller eksportert før frysing (B10).

**Anslag:** 5–8 økter (pluss kveldene).

---

### Fase 10 – Veddemål med poeng

**Mål:** Gjengen kan vedde på kvelden igjen, med poeng i stedet for penger.

- [x] Endelig modell (B10): poengbank per sesong, innsats, tak, oppgjør. *(07.10: besluttet, se `docs/veddemaal-poeng.md`: 1000 poeng per sesong, hele poeng, auto-annullering ved delt, den som avgjør kan ikke ha innsats.)*
- [x] Skjema-tillegg (SQL til godkjenning). *(07.10: `sql/012_veddemaal.sql` godkjent og kjørt på test, 12/12. Veddemål slått på i appen.)*
- [x] Vedd-ark med malene fra PWA-en (hull-duell, par, slår, fritekst), låsing (`forsteApneHull`, `markedTarInnsatser`) og automatisk avgjøring (`vilkaarUtfall`). *(07.10: regelmotor med 18 tester fra PWA-ens fasit, UI bak flagg.)*
- [x] Poengtabell for veddemål, separat fra jakketabellen. *(07.10: bak flagg.)*

**Ferdig når:**
- Et veddemål på «birdie på hull 5» stenger når hull 4 er ført, og avgjøres riktig når hull 5 føres.
- Poengene i veddemålstabellen stemmer med regnestykket.

**Tester:** `vilkaar-test.js`, `lockout-test.js`, `kveld-test.js`, `status-del-test.js`, `poster-test.js` (`veddemaalPoster` som poeng, og nettoing).

**Avhengigheter og risiko:**
- Krever fase 5 og 6 (match-, drive- og kp-vilkår).
- Kan bygges før fase 9 hvis gjengen savner veddemål ved byttet.

**Anslag:** 6–9 økter.

---

### Fase 11 – Enklere arrangøroppsett

**Mål:** En arrangør setter opp kvelden på under ett minutt uten å lure på noe. Tilbakemelding 07.10: start, bane og simulator/ekte bane er ikke intuitivt.

Besluttet 07.10.2026 (deg):
- **Hurtigstart** for «Ny runde»: én skjerm med *Hvor spiller dere?* (Simulator / Ekte bane), bane, start (hull og antall), tid og spillere. Alt annet tar standard fra regelsettet. «Flere valg» åpner matcher, LD/KP, vekt, lag og handicap ved behov.
- **Simulator / ekte bane** er et eget valg. På ekte bane heter gruppene **flight** i stedet for **bås**. Ellers samme regler.
- Alle fire delene skal gjennomgås: Ny runde/oppsett, Banene, Sesong og regler, og Arrangørsiden som helhet.

- [x] Arrangørsiden: ny struktur med «I kveld» øverst (neste kveld, påmeldte, start runden) og sjeldnere ting under.
- [x] Hurtigstart for ny runde med forslag ferdig utfylt (bane og oppsett fra forrige kveld, båser fra påmeldte).
- [x] Simulator / ekte bane som valg på runden (lagres), med bås ↔ flight i hele appen. Krever trolig SQL (til godkjenning). *(07.10: 015 kjørt, slått på. Hurtigstarten viser banene som passer stedet.)**
- [x] Banene: enklere å legge inn og forstå «klar», tydelig skille mellom simulatorbane og ekte bane. *(07.10: 016 kjørt, banetype slått på.)**
- [x] Sesong og regler: Golfgutu-oppsettet som standard, endringer i klart språk, avanserte valg skjult.

Gjennomgang 08.10.2026 mot beste praksis (`docs/arrangorsiden-vurdering.md`), i prioritert rekkefølge:

- [x] Rundelistene slått sammen: «Alle runder» → «Runder» → «Rundene» er én liste «Runder», gruppert per kveld, nyeste først. Rader navigerer (kladd åpner oppsettet, startet/låst åpner rundens skjerm). Avkort, lås, slett og rett hull ligger på rundens skjerm. Slett kladd med sveip. *(08.10.)*
- [x] Huben: «Neste kveld» (bare «I kveld» når kvelden er i dag), og «Kom i gang»-sjekkliste (sesong, baner, tropp, kveldene) når noe mangler. *(08.10.)*
- [x] Kvelden som ett objekt: «Kveldene» erstatter Terminliste og Runder. «Kvelden» har tid og sted, påmelding og purring, runder, avslutt kvelden og melding til alle. «Alle runder» er arkiv nederst i Kveldene. *(08.10.)*
- [x] Sesong og regler lander på den aktive sesongen, med «Alle sesonger» og «Ny sesong» nederst. *(08.10.)*
- [x] Én oppsettsflyt: hurtigstarten beholdes, veiviseren er fjernet, flyten pushes i stedet for ark, med vakt mot å miste ulagrede endringer. *(08.10.)*
- [x] «Varsler til troppen» samler melding til alle og push-skjermene. Invitasjonskoden er flyttet til Troppen, Rapporter til arrangørsiden. *(08.10.)*
- [x] Inngang for arrangører: knapp i Kveld-fanens verktøylinje i stedet for egen fane, fordi Hjem-forslaget (`docs/hjem-feed.md`) kan endre fanene. *(08.10.)*
- [ ] Prøve hele arrangørflyten på telefon mot test: ny runde, lagre kladd, start, lås og slett fra rundens skjerm, avslutt kvelden, purring og melding til alle fra Kvelden.

**Ferdig når:**
- Du setter opp en vanlig kveld med tre trykk etter at påmeldingen er klar.
- En ny arrangør klarer det uten hjelp.

**Anslag:** 4–6 økter.

### Fase 18 – Turnering i stedet for sesong og konkurranse

**Besluttet 08.10.2026 (Thomas):** «Det å arrangere en turnering og runde er ganske komplisert, og den følger Golfgutu-oppsettet som ikke nødvendigvis er riktig for den som arrangerer.» Fire oppsett i stedet for Golfgutu som fasit, og sesong og konkurranse slås sammen til ett begrep: **turnering**.

- **Fire oppsett** i «Ny turnering»: *Stableford-serie* (enkel: stableford-poeng per kveld, beste kvelder teller, ingen matcher eller seeding), *Matchspill-serie* (dagens Golfgutu-oppsett), *Cup* (utslag) og *Morroturnering*. Golfgutu er ett av oppsettene, ikke målestokken. Detaljreglene ligger bak «Tilpass reglene».
- **Ett begrep.** I en klubb er en serie en sesong (gratis, kvelder og Tavla). Uten klubb er en serie en liga (kjøp som i dag). Cup og morro er konkurranser som før. Datamodellen er allerede slik (`competitions.kind = season` speiler sesongen, sql/017), så ingen SQL trengs.
- **Ny regel:** `TableRules` får hva tabellpoengene kommer fra: matcher (standard, Golfgutu uendret) eller stableford.
- **Ny runde blir én bekreftelse:** bane, hvem og starttid, resten fra turneringen. Matcher og lag bare når formen krever det.
- **Mindre tekst:** høyst én hjelpelinje per seksjon.

- [x] Regelmotoren: tabell fra stableford, de fire oppsettene, gjenkjenning av oppsett. Paritet uendret. *(08.10: 191 kjernetester grønne, Golfgutu-JSON byte-lik.)*
- [x] Ny runde: én bekreftelsesskjerm, færre valg og tekster. Matcher verken vises eller trekkes når tabellen teller stableford. *(08.10: 23 → 16 synlige valg, 12 → 1 hjelpetekst.)*
- [x] Turnering i appen: «Ny turnering» med oppsettene, én liste over turneringer, arrangørsiden lander på hovedturneringen, Tavla for stableford-serie. *(08.10. Ikke prøvd mot database.)*
- [ ] Prøve på telefon: sett opp en stableford-serie og en kveld fra null.
- [x] Rester: «sesong» er «turnering» i appens tekster og regelmotorens meldinger; privat stableford-serie (liga) kjennes igjen som oppsettet; arket «Ny turnering» lager modellen først når det åpnes. *(08.10.)*
- [x] Fem feilmeldinger i SQL sier «turnering» (026, kjørt på test 08.10, kontrollen 5 av 5).

### Fase 19 – Hjem-fanen med aktivitetsfeed

**Besluttet 08.10.2026 (Thomas):** bygg Hjem-feeden etter forslagene i `docs/hjem-feed.md`.
- **Fanene:** Hjem erstatter Kveld: **Hjem · Spill · Tavla · Deg**. «Pågår nå» og «Neste kveld» (med svarknappene og arrangørens hovedknapp) står øverst på Hjem.
- **Varsler-bjella** blir bare det som angår deg direkte (nevnt, utfordret, purret på, melding til alle, din runde). Resten står i feeden.
- **Retning:** 1a (kronologisk feed i I dag · I går · Tidligere, filterpiller per turnering) med 1b-oppsummeringen øverst bare når noe har skjedd siden sist.
- **Innhold:** bragder (brutto eagle og bedre), tabellendringer (plassbytte), egne runder, sidepremier, tippekonge, melding til alle, påmeldinger. Ikke alle andres runder. Reaksjoner på alt. Push som i dag («Hva blir push»).
- **Data:** alle klubbene du er med i, dine turneringer og løse runder. SQL (til godkjenning) bare der det trengs.

- [x] Data og logikk: samlet feed på tvers av klubber, turneringer og løse runder; plassbytte som hendelse; «sist sett» på tvers; ren feedmodell med tester. *(08.10: PR #7. 027 kjørt på test, push-send v4 deployet, plassbytte slått på.)*
- [x] Hjem-fanen i appen: kortene fra designet, filterpiller, oppsummering, Pågår nå og Neste kveld; Kveld-fanen erstattes; bjella viser bare det som angår deg. *(08.10. Kveld-skjermen er ett trykk unna fra Neste kveld. Ikke prøvd mot ekte data.)*
- [ ] Prøve på telefon mot test.

### Fase 20 – Baner fra slope.no

**08.10.2026 (Thomas):** slope.no har et åpent, gratis API for nordiske baner (`/wp-json/golfhs/v1/meta` og `/export`). Eieren ber bare om kreditering og lenke til slope.no i appen. Dataene sjekkes hver natt mot ~2 500 kilder og kontrolleres ukentlig. 1 306 baner (161 i Norge) med tees: navn, kjønn, course rating, slope og par. Ingen data per hull: par og indeks per hull legges fortsatt inn fra scorekortet.

- [x] Skjema for tees per bane, CR/slope på runden og synk-status (SQL 029, kjørt på test 08.10, kontrollen 12 av 12).
- [x] Synk som Edge Function `slope-sync`: meta først, eksport bare ved ny `data_version`, én gang i døgnet. Lokale rettelser overlever. *(08.10: deployet på test, secret og Vault satt, cron `dd18-slope-sync` kl. 03:17 UTC. Første kjøring: 1306 baner, 9343 tees.)*
- [x] Appen: søk i slope.no-banene for ekte bane, tee-valg i runde-oppsett og løse runder, CR/slope fra teen i handicap. *(08.10: `SlopeNoFeature` slått på. Ikke prøvd på telefon.)*
- [x] Kreditering: «Slope og course rating fra slope.no» med lenke der tee-data vises, og i Om appen. *(08.10.)*
- [x] Hull per tee fra slope.no (par, indeks, lengde): SQL 030 kjørt på test, slope-sync v2, 937 baner og 6146 tees med hull (160 av 161 norske). Hentede baner spilles direkte, teens hull og par fryses på runden. `SlopeNoFeature.usesHoles` på. *(08.10. Ikke prøvd på telefon.)*

### Fase 21 – Arrangørsiden som tidslinje

**08.10.2026 (Thomas):** «Liker fortsatt ikke oppsettet i arrangørsiden, det er veldig kronglete og ikke alt ligger i kronologisk rekkefølge.»

- [x] Arrangørsiden i datorekkefølge: tidligere kvelder, så kortet for kvelden som står for tur med stegrekka Påmelding → Oppsett → Spilles → Ferdig og én knapp for neste steg, så kommende kvelder. Før sesongen er klar: «Kom i gang» med 1 Turneringen → 2 Troppen → 3 Banene → 4 Kveldene. Oppsett nederst og sammenfoldet. Kveldene-skjermen er slått inn i arrangørsiden. *(08.10.)*
- [x] Kvelden i tre seksjoner: Før, Under og Etter kvelden, med samme stegrekke. *(08.10.)*
- [x] Hjem-knappen heter det samme som neste steg og går rett dit: to trykk fra Hjem til «Start runden» (før: fire). *(08.10.)*
- [x] Bygget rundt én valgt turnering (hovedturneringen som standard), så en turneringsvelger kan legges til i fase 23. *(08.10.)*
- [x] Egen fane «Arrangør» (bare for arrangører) mellom Tavla og Deg, i stedet for ikonet på Hjem og raden i Deg. Oppsettet øverst og alltid åpent, så kvelden som står for tur, kommende og tidligere kvelder. *(09.10, Thomas: siden var for gjemt.)*
- [x] «Spilledag» for nye turneringer (`DayTerm` i regelsettet, `dayTerm`; uten feltet: «kveld», som Golfgutu). Valget i «Ny turnering» og i reglene. Arrangørsiden, Kvelden, «Kom i gang», stegrekka, avslutningen og Hjem-knappen følger ordet. *(09.10, Thomas.)*
- [x] «Spilledag» på spillersidene: ordet for klubbens hovedturnering hentes i `RootView` (`DayTermQueries`). Kveld-skjermen, tråden, Hjem-kortet og feeden, runden, Tavla og sesongoppsummeringen, tips, vedd, deling, Deg og regelteksten følger ordet. *(09.10.)*
- [x] Resten: varselinnstillingene (spiller og arrangør), Live Activity, kalendernavnet, og nøytrale tekster der ordet ikke er kjent (påminnelsen uten dato «neste runde nærmer seg» i push-send v6 og i appen, feilmeldingene i terminlista). *(09.10; push-send v6 deployet på test.)* Kodenavnene (`Kveld…`) står.
- [ ] Prøve på telefon mot ekte data.

### Fase 22–25 – Turneringen som kjerne (klubber og simulatorsentre)

**08.10.2026 (Thomas):** golfklubber og simulatorsentre skal kunne kjøre mange turneringer i uka, noen over lang tid, ofte overlappende. Åpen påmelding for ikke-medlemmer (valg per turnering). Golfgutu forblir en klubb med hovedturnering. Lasttest gratis først (lokalt), Pro senere. Design: `docs/fase-22-turnering-som-kjerne.md`.

- [x] Fase 22, design: målbilde, datamodell før → etter, migreringstrinn 031–035, paritetskontroll, lokal lasttest (1 000 brukere, 22 000 runder, 3 mill. hull). *(09.10.)*
- [x] 031 (additivt, trygt for dagens app): kjørt på test 09.10, kontrollen 12 av 12, paritet identisk. Beslutningene 2–9 står nederst i designdokumentet.
- [x] 032: stab, påmelding med tak og venteliste (tilbud gjelder 48 timer), startliste, mengdebaserte RLS-hjelpere. Kjørt på test 09.10, kontrollen 10 av 10, paritet identisk, cron for utløpte tilbud.
- [ ] 033–035: speilingen snus, gamle regler fjernes (krever `min_ios_build`), `seasons` som view.
- [x] Fase 23: arrangør per turnering (velger, åpen påmelding, venteliste, startliste, stab), `min_ios_build` i appen. `TournamentCoreFeature` på 09.10. *(Ikke prøvd på telefon.)*
- [ ] Fase 24: skala (Tavla-data i én RPC, tabellen på serveren, sanntid).
  - [x] Tavla-data i én RPC (`sql/036_tavla_data.sql`, `TavlaRPCFeature`): Tavla, Vedd og jakkeracet henter sesongen i ett kall. Kjørt på test 09.10, svaret likt med RLS-spørringene, 13 ms. Ikke-medlemmer henter som før.
  - [x] Mengdebaserte RPC-er (`sql/037_mengde_rpc.sql`, `SetQueriesFeature`): «folk du kjenner», dine løse runder, turneringslista og Hjem-feeden. Kjørt på test 09.10, likt med RLS for alle brukerne. Gjenstår: policyene med `(select auth.uid())` (mål i lasttesten først).
  - [x] Lasttest på SQL-nivå av 036–038 (`sql/lokal/lasttest_fase24.sql`, 09.10): Tavla 53 ms i ett kall, folk du kjenner 1,3 ms, turneringslista 2,6 ms. Funn: `my_loose_rounds` 296 ms, rettet i 039 (5,7 ms, kjørt på test 09.10). Lasttest gjennom PostgREST krever Docker (ikke installert).
- [ ] Fase 25: spillersiden (finn og meld deg på turneringer nær deg).
  - [x] «Finn turneringer» i Spill (også uten klubb): åpne turneringer fra `public_competitions` (032), søk på navn, klubb og sted, og påmelding med samme kort som turneringssiden. *(09.10.)* Gjenstår: «nær deg» (sted/avstand), push når en ny åpen turnering legges ut.

### Tilbakemeldinger 09.10.2026 (Thomas)

- [x] Slette turneringer: `delete_tournament` (sql/038, kjørt på test), «Slett turneringen …» med navnet som bekreftelse (#36).
- [x] Del regningen: tastaturet lukkes («Ferdig», dra i lista), «Åpne Vipps» med reserve via vipps.no (#31). Må prøves på telefon med Vipps.
- [x] Invitasjon: kortere tekst og QR-kode (#34).
- [x] Tippekupongen: «Tråden» og «Tips» rett på Hjem-kortet (#32).
- [x] Vedd i en runde bruker runden du står i; i andre turneringer står det at veddemål bare gjelder hovedturneringen ennå (#35).
- [x] Ny turnering synlig: «+»-meny på Arrangør, i liga/cup/morro, «Lag turneringen» i «Kom i gang», «Turneringer» i Spill (#33).
- [x] «Forrige kupong · dato» på Hjem-kortet og på Kveld-skjermen, så resultatet og tippekongen kan åpnes når neste kveld har tatt over. *(09.10.)*
- [x] Spillere uten klubb ser og lager private turneringer (liga, cup, morro) fra «Turneringer» i Spill (`CompetitionsModel(client:userID:)`). *(09.10.)*
- [x] Veddemålene gjøres opp fra Hjem på arrangørens telefon (høyst hvert femte minutt), ikke bare når veddemålene åpnes. *(09.10.)*
- [ ] Veddemål per turnering med egen poengbank, private turneringer og oppgjør uten arrangør: forslag og valg i `docs/vedd-per-turnering.md`. Venter på Thomas.

### Kodegjennomgang 08.10.2026: åpne funn

Hele appen er gjennomgått (død kode fjernet, kommentarer rettet, småfeil rettet med test). Dette står igjen:

- [x] **Kjøp (før `PurchaseFeature` slås på):** turneringsmålet festes bare til transaksjonen fra kjøpsarket, ikke til fornyelser eller «Gjenopprett». Må prøves i sandkassen før kjøp slås på. *(08.10.)*
- [x] **Kjøp:** «Ny turnering» sier fra når koblingen av en ledig kreditt feiler. *(08.10.)*
- [x] **Google (før `GoogleLoginFeature` slås på):** utloggingsteksten nevner Google når kontoen har det. *(08.10.)*
- [x] **Veddemål i Varsler:** egne tekster i appen og i `push-send` (PWA-ens ordlyd, poeng for kroner). *(08.10. push-send versjon 3 deployet på test.)*
- [ ] **Flagg som står permanent på** (fjernes når skjemaet er i prod): Foundation, Push, LiveActivity, Widget, Venue, CourseKind, Stats, Bets, Games, Competitions, LooseRounds, AccountDeletion, Moderation, BillSplit.
- [x] **Små ting:** kolonnelistene samlet, konkurransesiden henter bare sine egne påmeldinger, og utboksen kan ikke få to retry-løkker. `EveningDates` ligger også i widget-targetet (08.10), og kopiene i widgeten er fjernet. *(08.10.)*

---

### Fase 12–17 – Åpen app med flere bruksområder

**Besluttet 07.10.2026 (deg):** appen skal være åpen for alle og dekke løse runder med venner, spill på runden, flere konkurranser samtidig og egen statistikk. Hele planen står i `docs/visjon-apen-app.md`. Kort fortalt:

- **Fase 12 – Fundament** *(07.10: 017 kjørt på test, kontrollen 14/14, slått på; jakkeracet likt via konkurranser)*: runden er kjernen, og klubb er valgfritt. Planen har profiler, gjester og konkurranser som eget lag. Jakkeracet blir én konkurranse, og pariteten står.
- **Fase 13 – Løs runde med venner** *(07.10: 018 kjørt på test, URL-skjemaet `dashdash` lagt inn, slått på – Spill-fanen)*: ny runde på sekunder, invitasjon med lenke eller QR, felles banebibliotek.
- **Fase 14 – Spill på runden** *(07.10: 020 kjørt på test, slått på; motor med 20 håndregnede scenarier)*: skins, Nassau, Wolf, bingo-bango-bongo og 2 mot 2, i poeng.
- **Fase 15 – Flere konkurranser** *(07.10: bygget bak `CompetitionsFeature` – liga, cup, morroturnering, «Teller også i …»; venter på 022. Betalingsstubben kobles til `PurchaseService` fra fase 17 når kjøp slås på)*: liga, cup og morroturneringer samtidig (erstatter tidligere fase 12-utkast), med «Teller også i …».
- **Fase 16 – Statistikk** *(07.10: ferdig, 021 kjørt, slått på)*: historikk, snitt, rekorder og handicaputvikling.
- **Fase 17 – Åpent for alle (App Store)** *(07.10: bygget bak flagg; venter på 019, 023, Edge Functions og oppsett i App Store Connect/Google, se `docs/app-store.md`)*: onboarding uten klubb, sletting av konto, personvern, rapporter og blokker, Google-innlogging og prod.

**Besluttet 07.10.2026:** fase 12 før byttet (fase 9). Brukerne legger inn baner nå, og skjemaet gjøres klart for en ekstern kilde. Navnet er **DashDash**. Appen er gratis, med kjøp i appen for å kjøre turnering. Veddemål er bare poeng, og Vipps brukes til å dele felles utgifter. Se `docs/visjon-apen-app.md`.

---

**Totalt:** ca. 76–111 økter. Usikkerheten er størst i fase 2 (paritet), 5 (offline) og 9 (import).

Etter v1: Android (B13), Apple Watch, GPS.

---

## 3. BESLUTNINGER

Status: **Tatt** (av deg, eller av meg etter fullmakt), **Utsatt** eller **Åpen**.

### B1 – Distribusjon · Tatt
**Ekstern TestFlight med e-postinvitasjon.** Du har Apple Developer-konto. Uten ekte penger i appen er Apples beta-gjennomgang lite risikabelt. Bygg utløper etter 90 dager og må fornyes. Offentlig App Store er ikke et mål for v1.

### B2 – Spillogikk · Tatt (meg)
**Regelmotor i Swift**, med testtall som JSON-fixtures. Virker offline og under føring.
*Konsekvens for Android:* motoren må skrives på nytt for Android, men fixturene gjør det mekanisk å sjekke at svarene er like. Alternativet er å flytte utregningene til Postgres-funksjoner nå. Det gir én sannhet for begge plattformer, men føring og stilling offline blir vanskeligere. Jeg anbefaler Swift nå, og å vurdere server på nytt når Android planlegges.

### B3 – PWA-en · Tatt (deg)
**PWA-en og PWA-basen er urørt til byttet.** Gjengen spiller på PWA-en til appen er god nok. Ved byttet (fase 9) importeres historikken, og PWA-en fryses. Ingen sameksistens mot samme database.

### B4 – Supabase · Tatt (deg)
**Ny Supabase for appen.** Jeg anbefaler to prosjekter: **test** og **prod**, som PWA-en har i dag.
*Konsekvens:* eget skjema som tåler dynamiske turneringer, atomiske RPC-er, strammere RLS, APNs-tabell uten å røre PWA-en. Koster en importjobb (fase 9).

### B5 – Databaseendringer · Tatt (meg), hver endring godkjennes av deg
1. SQL skrives som fil i `sql/` i dette repoet, nummerert.
2. Du godkjenner SQL-en.
3. Kjøres på **test**, med kontrollspørringer og rullebakke i fila.
4. Appen testes mot test.
5. Prod først etter ny godkjenning.
6. Anon-fella fra PWA-en: `revoke execute … from anon` etter hver `create or replace`, og sjekk returnerte rader (SPEC 3.2).

### B14 – Regelmotoren som lokal Swift-pakke · Tatt (meg)
Spillogikken bygges i `Packages/GolfgutuCore`, en lokal Swift-pakke uten SwiftUI og nettverk, med Swift Testing og JSON-fixtures. Den testes med `swift test` uten Xcode, kan bygges parallelt med appen, og deles senere med widgets, Live Activity og Watch. Pakken legges til i Xcode-prosjektet av brukeren (*Add Local…*).

### B15 – Banedata: søk etter ekte baner og Trackman-scorekort · Åpen (deg)
**08.10.2026:** slope.no gir CR/slope per tee for 1 306 nordiske baner, gratis med kreditering (fase 20). Det som gjenstår fra en betalt kilde, er par og indeks per hull.
Kartlagt 06.10.2026. Ingen åpen, komplett kilde for norske scorekort med CR/slope, og ingen offentlig kilde for Trackman-scorekort.
- **Anbefalt hovedvei:** GolfAPI.io for søk (par/SI/lengde per tee, CR/slope per kjønn, green-koordinater; caching i egen database er tillatt, videredeling ikke). Pris må hentes inn (contact@golfapi.io), nordisk dekning må testes på 10–20 norske klubber. Reserve: GolfCourseAPI Pro (ca. 10 USD/mnd).
- **Alltid:** «Bekreft mot scorekortet/skjermen» før banen brukes, med kilde (api/ocr/manuell) lagret på banen. Foto av scorekort lest på telefonen (Vision `RecognizeDocumentsRequest`, iOS 26) som reserve.
- **Trackman:** match Trackman-navnet mot den ekte banen i API-et, merk «Trackman-versjon», bekreft mot simulatorskjermen, og del bekreftede scorekort mellom klubbene. Spør Trackman om partnertilgang.
- **Norsk offisiell kilde:** bare via avtale med NGF/GolfBox (slik Gimmie har). Ikke høst klubbsider eller GolfBox systematisk (katalogvern).
- **Konsekvens for skjemaet:** API-nøkkelen må ligge på serveren (Supabase Edge Function), ikke i appen. Et felles banekatalog på tvers av klubber (i stedet for bare per klubb) og felt for kilde/ekstern-id krever ny migrering (SQL til godkjenning).

### B16 – Frosset handicap i sesongtabellen · Tatt (meg), kan overstyres
Tabellen og Kveld regner hver runde med handicapet som ble frosset da runden startet (`round_players.playing_handicap`, ellers frosset indeks/seeding). PWA-en regnet matchresultatene i sesongen med spillernes *nåværende* handicap. Bevisst avvik: gamle resultater skal ikke flytte seg når noen endrer handicap. Golfgutu-paritet gjelder ellers.

### B6 – Lokal lagring · Tatt (meg)
**SwiftData** for cache og utboks. Domenelogikken ligger i rene Swift-typer utenfor.

### B7 – Deployment target og Swift · Tatt (meg)
**iOS 26.0 og Swift 6.** Prosjektet står i dag på 26.5 og Swift 5. Endres i Xcode.

### B8 – `referanse/` i git · Tatt (deg)
Holdes utenfor git (`.gitignore`), fordi mappa inneholder nøkler.

### B9 – Innlogging · Tatt (deg)
**Apple, Google og e-postkode.** Apple native (`AuthenticationServices` + `signInWithIdToken`), Google via OAuth i `supabase-swift` uten ekstra SDK, e-postkode som i dag. Med ny database er det ingen gamle kontoer å koble, men en spiller kan koble flere måter til samme konto. Supabase-konfig godkjennes av deg.

### B10 – Veddemål og penger · Tatt (deg): poeng i stedet for penger, i fase 10
Ingen kroner i appen: ingen skyldliste, Vipps, bøter eller utlegg i v1. Tippekupongen bruker poeng eller «for æra». Åpen gjeld i PWA-en gjøres opp der før den fryses.

### B11 – GPS · Tatt (meg)
Utenfor v1. Databasen har ingen banegeometri.

### B12 – Regelsett · Tatt (deg)
**Turneringen styres fra admin-panelet, uten faste tall.** Forslag til hva regelsettet dekker (endelig i fase 2 og 3):
- antall spillere: ubegrenset; maks per bås (standard 4)
- antall kvelder i sesongen, og hva som teller: alle, eller beste N
- tabellmodell: duellpoeng (seier/delt/tap med valgfrie verdier), stableford-sum, eller slag
- sidepremier: LD og KP av/på, poeng per premie, deling ved likt
- rundevekt per runde
- handicapmodell: WHS med andel, seeding-grupper med egne tall, ekstern (Trackman), brutto
- tillatte konkurranseformer
- tiebreak-rekkefølge

**Golfgutu-oppsettet** er en ferdig mal som gjengir PWA-en (7 kvelder, alle teller, duellpoeng 1/0,5/0, LD og KP 1 poeng, seeding 0/5/10, osv.). Det er det paritetstestene kjøres mot.

### B13 – Plattform · Tatt (deg)
**iPhone først, Android senere.**
**Åpent spørsmål:** har noen i gjengen Android? Etter byttet er PWA-en fryst, og da står de uten app til Android finnes. Alternativer: vente med byttet, la dem bruke appen via en annens telefon (markør fører for dem uansett), eller lage en enkel nettversjon senere.

---

## 4. UTENFOR OMFANG (første ferdige versjon)

- **Penger:** skyldliste, Vipps, bøter, utlegg, premiepenger. Veddemål kommer med poeng i fase 10.
- **Android.** Kommer etter v1 (B13).
- **GPS og avstand til green.**
- **Apple Watch.**
- **Ekte bane** (ikke simulator) som eget bruksmønster. Regelsettet stenger ikke for det, men appen er ikke testet for det.
- **iPad-tilpasset bred modus.** Appen kjører på iPad som iPhone-layout.
- **Plakaten for kvelden** (canvas til Instagram).
- **Sameksistens med PWA-en** mot samme database.
- **Skins og halve slag.** Kan legges til i regelsettet senere.
- **Den gamle banken** (`bank_bevegelser`, saldo, innskudd) importeres ikke.

---

## Vedlegg A – PWA-tester og hvor de dekkes

Alle tall gjelder Golfgutu-oppsettet.

| Test | Fase | Merknad |
|---|---|---|
| `brutto-test.js`, `seeding-test.js`, `parspill-test.js`, `baneoppsett-test.js`, `banehull-test.js`, `banebytte-test.js`, `trackman-test.js` | 2 | Regneregler |
| `banepar-test.js` | 2, 3 | |
| `avkorting-test.js` | 2, 7 | Poeng (2), avkort-flyt (7) |
| `paamelding-test.js`, `skjevt-lag-test.js` | 2, 4 | Lagdeling (2), oppsett (4) |
| `innlogging-test.js`, `innmelding-test.js`, `uinnloeste-rader-test.js` | 1 | Oppførsel |
| `banebekreftelse-test.js`, `baneskjema-test.js`, `banevalg-test.js`, `terminliste-test.js`, `tropp-test.js` | 3 | |
| `paamelding-svar-test.js`, `kvelder-test.js`, `neste-kveld-test.js`, `kladd-test.js`, `rediger-kladd-test.js`, `sidepremie-valgfritt-test.js` | 4 | |
| `markor-test.js` | 4, 5 | `foreslaatteBaaser` (4), `kanFore` (5) |
| `matcher-test.js`, `trekant-test.js` | 4, 6 | Oppsett (4), poeng (6) |
| `match-test.js`, `matchrunde-test.js`, `seier-test.js`, `sesong-test.js` | 6 | |
| `rundene-test.js`, `slett-runde-test.js`, `kunngjoring-test.js`, `reaksjoner-test.js`, `kveldens-traad-test.js`, `traad-bilder-test.js`, `tippekupong-test.js` | 7 | Tips uten kroner |
| `push-kategorier-test.js`, `push-paaminnelse-test.js`, `push-status-test.js` | 8 | Edge Function |
| `vilkaar-test.js`, `lockout-test.js`, `kveld-test.js`, `status-del-test.js`, `poster-test.js` | 10 | Med poeng |
| `hent-paa-nytt-test.js`, `skjema-realtime-test.js` | 5 | Oppførsel, ikke tall |
| `kalender-del-test.js`, `klubbilder-test.js` | 7, 8 | Oppførsel |
| `utlegg-test.js`, `push-worker-test.mjs`, `kalender-worker-test.mjs` | – | Penger og PWA-worker, utenfor omfang |
| `knapper-test.js`, `toast-test.js` | – | UI-regler. Hensikten videreføres, ikke testene |
| `porten-test.js`, `bred-test.js`, `globalnavn-test.js`, `plakat-test.js` | – | PWA-spesifikke eller utenfor omfang |
