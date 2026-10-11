# Gjennomføringsplan: alt fra beslutningene 11.10.2026

Grunnlag: «Beslutninger» i [`plan-konkurranser-og-sosialt.md`](plan-konkurranser-og-sosialt.md). Denne planen erstatter faseplanen der (fase 27–34) med rekkefølgen arbeidet faktisk gjøres i. Startet 11.10.2026 («Kjør, lag plan for å få inn alt»).

## Slik jobber vi

- **Tolv steg.** Hvert steg er én eller flere PR-er. SQL-en i et steg samles i én fil så langt det går, og vises Thomas samlet før den kjøres på test (B5).
- **Motoren først.** Regelmotoren (Swift og TypeScript) bygges med tester før appen og SQL-en. Golfgutu-fixturene skal gi samme svar etter hvert steg.
- **Parallelt der det går.** Motorarbeid, app og web kan gå i hver sin agent-worktree mens SQL venter på godkjenning. To agenter rører aldri de samme filene samtidig (særlig `Ruleset.swift`).
- **Web-admin følger med.** Alt arrangøren kan gjøre i appen, kommer også i web-admin i samme steg eller rett etter.
- **Prod til slutt.** Dash18 Prod opprettes når stegene 1–11 er kjørt og prøvd på test (steg 12). Opprettelsen og hver kjøring mot prod godkjennes for seg.

## Stegene

| Steg | Innhold | SQL | Kode | Avhenger av |
|---|---|---|---|---|
| **1** | **Rydde modellen.** `min_ios_build` settes til dagens bygg. De gamle unike reglene fjernes (én aktiv runde, én aktiv sesong per klubb, én kveld per dato), ikke-medlemmer i klubbrunder, `bay_no` opp til 99, push og aktivitet per turnering | `034` | Appen tåler flere aktive runder og sesonger. Permanente flagg fjernes der koden er død | – |
| **2** | **Egne roller per klubb.** `club_roles` (navn, rettigheter i fire grupper), `club_member_roles`, malene Eier, Arrangør, Kasserer, Sosialkomité og Medlem. RLS og RPC-er spør etter rettighet (`private.has_club_right`). `is_organizer` og `is_treasurer` speiles til gamle bygg er borte. Eier kan overføres, siste eier kan ikke gå. `clubs.org_number` | `044` | Roller i Klubb og web-admin. Navn fra Enhetsregisteret på organisasjonsnummer | 1 |
| **3** | **Seasons blir view.** `events.season_id` og `bets.season_id` peker på turneringen. Appen og web-admin slutter å lese `seasons` | `035` | Tavla, Vedd, arrangørsiden og web-admin leser `competitions` | 1, 2 |
| **4** | **Påmelding per kveld.** Tak, venteliste med automatisk opprykk, frister bare når arrangøren slår dem på, sen avmelding merkes, logg. Én låsende RPC, skrivepolicyene på `signups` fjernes | `045` | Kveld-skjermen, arrangørsiden, Hjem-kortet, web-admin | 1 |
| **5** | **Varsler.** Fire grupper, demping per kveld, ett «kvelden er i gang», e-post til dem uten push, logg per mottaker | `046` | `push-send`, varselinnstillingene, ny e-postfunksjon | 4. E-post krever SMTP (venter på Thomas) |
| **6** | **Tabellregler og playoff.** Minste antall kvelder, navngitte poengtabeller, snitt, kveld som ikke teller, playoff om førsteplassen (egen kort runde, `rounds.kind = playoff`, hullene velges ved start), «skjul de tre siste hullene», trekningsvalg (tabell, uten gjentakelser, manuelt), tilfeldige lag med bytte | `047` | Motoren først (Swift + TS + fixturer), så Tavla, TV, runde-oppsett, web-admin | 3 |
| **7** | **Formater.** Lagform og poengtelling som to akser, Amerikaner og Københavner (etter NGF), skins som turneringsform, lag mot lag (Ryder Cup), flere konkurranser på samme runde, øyeblikksbilde av regelsett og hull ved start | `048` | Motoren først, så oppsett, føring og Tavla | 6 |
| **8** | **Gjenbruk.** «Samme som sist», «Sesong fra mal» (startdato, ukedag, antall; «bare denne» eller «denne og fremtidige»), egne maler | `049` | Arrangørsiden, Ny turnering, web-admin | 3 |
| **9** | **Sosialt.** Reaksjoner på alt med fri emoji bak «+», flate kommentarer med @-omtale og «følg tråden», felles feed med sider (`feed_page`), bildeoppfordring når runden låses | `050` | Hjem, tråden, varsler | 5 |
| **10** | **Kalender og Del regningen.** Kalenderabonnement per medlem (påmeldte kvelder, ICS fra Workeren). Del regningen lagres med «sendt» (automatisk etter Vipps) og «bekreftet» av mottaker | `051` | Deg, Kveld, Del regningen | 4 |
| **11** | **Veddemål overalt.** Av som standard, slås på per turnering eller runde. Poengbank per turnering eller runde. Profiler i private turneringer. Oppgjør på serveren med motoren i TypeScript når runden låses | `052` | Vedd, oppsett, innstillinger, oppgjørsfunksjon | 3, 7 |
| **12** | **App Store-grunnmur og prod.** Invitasjon med kort kode, utløp, tak og tilbaketrekking, «krev godkjenning», «lås»; vilkår godtatt og håndhevet; myk sletting og tekstfilter; varsel til Thomas ved rapport; Apple-token ved sletting; demogruppe; knappene i verktøylinja (gule). Så Dash18 Prod med alle migreringer | `053` | Klubb, tråd, Deg, `delete-account`, invitasjonssiden | Alle |

Knappefargen (gul med mørk tekst) gjøres med en gang, siden den ikke avhenger av noe.

## Det Thomas må gjøre underveis

- Godkjenne SQL-en i hvert steg (vises samlet).
- SMTP for e-post (steg 5).
- Prøve på telefon etter steg 1, 4, 6 og 9.
- Oppsett i App Store Connect og «Development Region» (nb) i Xcode før steg 12.
- Si ja til at Dash18 Prod opprettes (steg 12).

## Status

| Steg | Status |
|---|---|
| Knappefarge | Pågår |
| 1 | Pågår: 034 skrives |
| 6 (motoren) | Pågår parallelt: tabellregler og playoff i GolfgutuCore og TypeScript, uten SQL |
| Resten | Ikke startet |
