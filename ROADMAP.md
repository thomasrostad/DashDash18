# ROADMAP: DashDash18

Plan fra dagens tomme Xcode-prosjekt til en iOS-app som erstatter GolfGutu-PWA-en for hele gjengen. Grunnlag: `SPEC.md`, `CLAUDE.md`, `referanse/golfgutu-pwa/` (særlig `README.md` og `db-nytt.js`).

Henvisninger som «SPEC 4.9» peker til seksjoner i `SPEC.md`.

---

## STATUS

| | |
|---|---|
| **Nåværende fase** | Fase 3 (nesten ferdig) og fase 4 (påmelding ferdig, oppsett av kveld gjenstår). |
| **Sist gjort** | Fase 4 runde-oppsett og fase 5 utboks slått sammen. RPC-ene fra 002/004/005 i bruk. Enhetstester grønne. |
| **Neste oppgave** | Slå sammen føring (fase 5). Knytte utboksen til bruker. SQL 006 (+ 007) til godkjenning. Prøvekveld på test. |
| **Venter på deg** | Test av arrangørsiden på telefon. Kontakt GolfAPI.io (B15). Google-innlogging. Baneverdier (CR) senere. |

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

- [ ] Påmelding: Kommer / Usikker / Kommer ikke + kommentar, angre, purring av de som ikke har svart. *(06.10: svar og kommentar ferdig. Angre og purring gjenstår.)*
- [x] Kveld-skjerm, rolig: neste kveld, påmeldte, sosialkomité. *(06.10.)*
- [x] Start runde-veiviser i tre steg: bane og tid, hvem og båser, oppsett. Lagre som kladd, rediger kladd, start (blokkert hvis en runde går). *(06.10. Ikke prøvd mot database.)*
- [x] Båser og markør (`foreslaatteBaaser`), matcher for hånd, lag, forslag om form (`oppsettForAntall`, `formerSomPasser`), `trekkMatcher`. *(06.10: trekning på navn til tabellen finnes, fase 6.)*
- [ ] Forslag til LD- og KP-hull. Par-bekreftelse før føring.
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

- [ ] Kveld-skjerm, spill: hullprikker, hullkort for hele båsen, «Bayen nå».
- [ ] Hullkort: stepper, «N slag fått», regnestykket, score-merke, bekreft hver spiller, «Lagre hull» låst til alle er ført.
- [ ] Skriverett (`kanFore`) i appen og i RLS: arrangør, markør for egen bås, ellers seg selv.
- [ ] Lagring av et hull for hele båsen i én RPC (atomisk, idempotent).
- [ ] Seer-modus for ikke-markør. Følg båsens hull, sol-stripe.
- [x] Lokal lagring med SwiftData (B6): cache og utboks. Hull i kø sendes i rekkefølge med nye forsøk, også etter at appen er drept. *(06.10: utboks med kø, komprimering, backoff. Ikke prøvd i flymodus.)*
- [ ] Realtime og henting på nytt når appen blir aktiv.
- [ ] Scorekort Ut/Inn. Feiring (birdie, eagle, albatross, hole in one) med redusert-bevegelse-støtte.
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
- [ ] LD og KP: meld egen lengde, stilling, delt ved likt.
- [ ] Kveld: matchkort, «1 opp / Delt / —», stilling i «Bayen nå».
- [ ] Tavla: tabell, «Slik telles det» generert fra regelsettet, spillerprofil, sesongoppsummering.

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

- [ ] Avkort runden med effekt-forhåndsvisning (`avkortingenKoster`).
- [ ] Avslutt kvelden: lås, kveld ferdig, neste kveld rykker opp.
- [ ] Rett en score, Rundene (tabell, retting i låst runde, logges). Slett runde (én RPC).
- [ ] Aktivitet og varsler i appen: strukturert (type + data), ikke HTML. Reaksjoner.
- [ ] Deg: handicap (komma), portrett, koblede innloggingsmåter, logg ut.
- [ ] Kveldens tråd: tekst, @navn, bilde fra bildebiblioteket, uleste.
- [ ] Tippekupong: fem spørsmål, frist i Oslo-tid, andres tips etter låsing, fasit og resultat. Innsats i poeng eller «for æra» (B10).

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

- [ ] **APNs-push:** tabell for enhetstokens (SQL til godkjenning) og en sender (Supabase Edge Function), med kategorier som kan slås av og på per spiller og av arrangør.
- [ ] Varsler for store scorer, ledelsesskifte, ny runde, påminnelse før kveld, purring, tråd (nevnt/alle/av).
- [ ] **Live Activity** under runde: hull, egen score, stilling i bås og match.
- [ ] **Widgets:** neste kveld og tabell-topp.
- [ ] **Kamera** i tråden.
- [ ] **Kalender:** «Legg i kalender» via EventKit.
- [ ] Deling av tabell og resultater via delingsark.

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

- [ ] Importverktøy (lesing fra PWA-ens prod, skriving til appens database): spillere, baner, terminliste, påmeldinger, runder med oppsett, scorer, sidepremier, tips. Idempotent, kan kjøres flere ganger.
- [ ] Hvordan dataene hentes ut (SQL-eksport, eller lesing med innlogget bruker) avgjøres i fasen. Ingenting skrives til PWA-basen.
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

- [ ] Endelig modell (B10): poengbank per sesong, innsats, tak, oppgjør.
- [ ] Skjema-tillegg (SQL til godkjenning).
- [ ] Vedd-ark med malene fra PWA-en (hull-duell, par, slår, fritekst), låsing (`forsteApneHull`, `markedTarInnsatser`) og automatisk avgjøring (`vilkaarUtfall`).
- [ ] Poengtabell for veddemål, separat fra jakketabellen.

**Ferdig når:**
- Et veddemål på «birdie på hull 5» stenger når hull 4 er ført, og avgjøres riktig når hull 5 føres.
- Poengene i veddemålstabellen stemmer med regnestykket.

**Tester:** `vilkaar-test.js`, `lockout-test.js`, `kveld-test.js`, `status-del-test.js`, `poster-test.js` (`veddemaalPoster` som poeng, og nettoing).

**Avhengigheter og risiko:**
- Krever fase 5 og 6 (match-, drive- og kp-vilkår).
- Kan bygges før fase 9 hvis gjengen savner veddemål ved byttet.

**Anslag:** 6–9 økter.

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
Kartlagt 06.10.2026. Ingen åpen, komplett kilde for norske scorekort med CR/slope, og ingen offentlig kilde for Trackman-scorekort.
- **Anbefalt hovedvei:** GolfAPI.io for søk (par/SI/lengde per tee, CR/slope per kjønn, green-koordinater; caching i egen database er tillatt, videredeling ikke). Pris må hentes inn (contact@golfapi.io), nordisk dekning må testes på 10–20 norske klubber. Reserve: GolfCourseAPI Pro (ca. 10 USD/mnd).
- **Alltid:** «Bekreft mot scorekortet/skjermen» før banen brukes, med kilde (api/ocr/manuell) lagret på banen. Foto av scorekort lest på telefonen (Vision `RecognizeDocumentsRequest`, iOS 26) som reserve.
- **Trackman:** match Trackman-navnet mot den ekte banen i API-et, merk «Trackman-versjon», bekreft mot simulatorskjermen, og del bekreftede scorekort mellom klubbene. Spør Trackman om partnertilgang.
- **Norsk offisiell kilde:** bare via avtale med NGF/GolfBox (slik Gimmie har). Ikke høst klubbsider eller GolfBox systematisk (katalogvern).
- **Konsekvens for skjemaet:** API-nøkkelen må ligge på serveren (Supabase Edge Function), ikke i appen. Et felles banekatalog på tvers av klubber (i stedet for bare per klubb) og felt for kilde/ekstern-id krever ny migrering (SQL til godkjenning).

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
