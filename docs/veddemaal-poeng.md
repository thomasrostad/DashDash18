# Veddemål med poeng (fase 10, B10)

Beslutningsnotat. Spørsmålene er besluttet 07.10.2026 (se nederst), og regelmotoren (`Packages/GolfgutuCore/Sources/GolfgutuCore/Bets.swift`), SQL-forslaget (`sql/012_veddemaal.sql`) og appen er oppdatert etter dem. SQL-en er fortsatt et forslag som venter på godkjenning (ikke kjørt mot Supabase), og appen har skjermene bak `BetsFeature.isEnabled = false`.

## Hva PWA-en gjør (fasit)

- Et **veddemål** (`markets`) er en påstand. Alle kan satse JA eller NEI. Med et **vilkår** (`vilkaar`) avgjør appen det selv (`vilkaarUtfall`); uten vilkår er det fri tekst, og arrangøren avgjør.
- **Malene** i vedd-arket (`utfordringMaler`): mot en spiller «han slår meg netto på hull N» (hull-duell), «han holder par eller bedre på hull N», «han slår meg netto i runden» (bare før første slag) og «han kommer på pallen» (fri tekst). Om deg selv: birdie og par på ditt neste hull, «noen får birdie», ellers «vinner runden» og «pallen i sesongen» (fri tekst).
- **Låsing:** et hullveddemål må ligge fram i tid. Fronten er høyeste førte hull + 1, målt per spiller (duellen følger den av de to som har kommet lengst, «noen» følger lederen). Første åpne hull er fronten + forspranget (1). Før noen har begynt, er hull 1 åpent. Veddemål om hele runden stenger ved første score (`forsteApneHull`, `markedTarInnsatser`).
- **Avgjøring:** arrangørens telefon feier etter hver henting og avgjør det vilkåret gir svar på (`oppdaterMarkeder`). Delt hull, delt match og likt resultat gir ikke noe svar, og arrangøren tar dem for hånd.
- **Oppgjør:** vinnersiden deler taperpotten etter innsats. Ingen på vinnersiden, eller ingen tapere: alle får innsatsen tilbake (`marketNetFor`, `veddemaalPoster`). Overføringene nettes per motpart (`skyldOversikt`).
- **Beløp:** 50, 100 eller 200 kr, tak 200 kr per veddemål summert over dine innsatser. Ingen saldo; gjelden ble gjort opp med Vipps.

## Modellen: samme veddemål, med poeng

1. **Poengbank per sesong.** Hver spiller starter sesongen med en startbeholdning (**1000 poeng**). Ny sesong gir ny bank. Saldo = start + netto fra avgjorte veddemål. Ledig = saldo − det som står i åpne veddemål. Du kan ikke sette mer enn du har ledig. Saldoen **lagres ikke**; den regnes av innsatsene, i appen (`Bets.balance`, `available`) og i databasen (`bet_points`), med samme regnestykke.
2. **Innsats:** knappene 50, 100 og 200, 100 er valgt når arket åpnes (som PWA-en). Flere innsatser på samme veddemål er lov, men alltid på samme side (nytt: PWA-en sperret ikke den andre siden).
3. **Tak:** 200 poeng per veddemål og spiller, summert. Sjekkes i appen og i databasen.
4. **Oppgjør:** som PWA-en, men i **hele poeng**. Vinnersiden deler taperpotten etter innsats. Hver vinners gevinst rundes med `floor(x + 0.5)`, og det avrundingen skapte eller fjernet, gis eller tas ett poeng om gangen fra vinnerne etter største innsats (likt: laveste id). Hvert veddemål går da nøyaktig i null, og summen over alle spillere er null (`Bets.payouts` og `bet_points_for`, samme regnestykke). Eksempel: 100 delt på tre like innsatser gir 34, 33 og 33. Poengene flytter seg **i det veddemålet avgjøres** (PWA-en skrev poster først når kvelden var ferdig, fordi det var ekte penger som skulle betales). Overføringene per motpart («Du vant 33 fra Erik») rundes hver for seg, som i PWA-en, og kan avvike med et poeng fra netto.
5. **Annullert** (nytt): arrangøren kan annullere et veddemål. Alle får innsatsen tilbake. **Delt hull, delt match og likt resultat annulleres automatisk** av feiingen.
6. **Poengtabellen for veddemål** er egen, ved siden av jakketabellen under Tavla: saldo, netto, det som står ute og antall vunnet. Sortert på saldo, så navn. Den påvirker ikke jakkeracet.
7. **Fritekst** avgjøres av **arrangøren**, som i PWA-en. Veddemål med vilkår avgjøres av feiingen på arrangørens telefon (`settle_bet`), og arrangøren har knappene som nødutgang (`resolve_bet`).
8. **Den som avgjør, vedder ikke.** En arrangør med innsats i et veddemål kan ikke avgjøre det for hånd: `resolve_bet` avviser det («Du har satset på dette veddemålet og kan ikke avgjøre det. En annen arrangør må gjøre det.»), og appen viser ikke «Avgjør» for henne, bare at en annen arrangør må gjøre det. Arrangøren kan fortsatt satse, også på fritekst. Feiingen gjelder også veddemål arrangøren har satset på, fordi det er scorene som avgjør. `settle_bet` godtar bare veddemål med vilkår, og bare når scorene kan ha gitt svar (hullet er ført, eller runden er låst); annullering bare for duell, «slår i runden» og match.
9. **Push** bare for nye og avgjorte veddemål, ikke for hver innsats.
10. **Én side per spiller:** når du har satset, er den andre siden sperret.

## Regelverdier i regelsettet (`Ruleset.bets`)

| Felt | Betydning | Golfgutu |
|---|---|---|
| `lockAheadHoles` | Forspranget: hvor mange hull foran spilleren det første åpne hullet ligger (`VEDDEMAAL_FORSPRANG`) | 1 |
| `maxStakePerBet` | Tak per veddemål og spiller (`VEDD_TAK`) | 200 |
| `stakeOptions` | Beløpsknappene (`VEDD_BELOP`) | 50, 100, 200 |
| `defaultStake` | Valgt beløp når arket åpnes | 100 |
| `startingPoints` | Startbeholdning per sesong. `null` = ingen bank (bare taket gjelder, saldo kan gå under null) | 1000 (besluttet; finnes ikke i PWA-en) |
| `payoutDecimals` | Desimaler i oppgjøret, 0–2. 0 = hele poeng | 0 (besluttet; PWA-en: 2, `rund2`) |
| `voidTies` | Delt hull, delt match og likt resultat annulleres av feiingen | `true` (besluttet; PWA-en: arrangøren for hånd) |

Grensene for birdie (netto ≤ −1) og par (≤ 0) og oppgjørsmodellen er vilkårets og oppgjørets definisjon og blir i koden. Med Golfgutu-oppsettet gir motoren samme låsing, utfall og maler som PWA-en. Oppgjøret og feiingen gir PWA-ens svar med `Ruleset.BetRules.pwa` (to desimaler, ingen automatisk annullering), og det er det paritetstestene kjører med (`Fixtures/veddemaal.json`, regnet ut av PWA-koden). PWA-ens `marketNetFor` runder ikke; med to desimaler er netto høyst en hundredel unna per veddemål.

## Avvik og funn i PWA-en

- Et hullveddemål på et hull etter avkortingen («felles» etter hull 14, veddemål på hull 15) står fortsatt **åpent** i `markedTarInnsatser` (sperra sjekker ikke øvre grense), men kan aldri avgjøres. PWA-en varsler om dem ved avkorting (`hengende`). Beholdt for paritet; appen bør vise dem som «må avgjøres for hånd».
- En spiller uten score (front 0) har hull 1 åpent midt i runden. Malene mot ham tilbyr da par på hull 1. Riktig etter regelen («ingen har begynt»), men rart for en som ikke er i runden. Beholdt.

## Besluttet 07.10.2026

Brukerens svar på de åpne spørsmålene, og hvor de er bygd inn.

1. **Startbeholdning:** 1000 poeng per sesong, som foreslått (`startingPoints`, Golfgutu 1000).
2. **Ved sesongslutt:** saldoen nullstilles. Ny sesong er ny bank, og det er ingen premie. Saldoen regnes per sesong av innsatsene, så det trengs ingen jobb ved sesongslutt.
3. **Fritekst** avgjøres av arrangøren (`resolve_bet`).
4. **Arrangøren kan ikke vedde på et veddemål hun selv avgjør.** Bygd som: den som avgjør for hånd kan ikke ha innsats i veddemålet. `resolve_bet` avviser det med norsk feilmelding (55000), `BetsModel.resolve` avviser det før kallet, og kortet skjuler «Avgjør» for en arrangør med innsats (en annen arrangør må gjøre det; `Bets.canResolve`). Arrangøren hindres ikke i å satse, heller ikke på fritekst. Feiingen (`settle_bet`) er ikke arrangørens skjønn og gjelder også veddemål hun har satset på.
5. **Annullering** er ok. **Delt hull, delt match og likt resultat annulleres automatisk** av feiingen, og alle får innsatsen tilbake (`voidTies`, Golfgutu `true`; `Bets.verdict`, `settle_bet` med `void`).
6. **Hele poeng.** Oppgjøret rundes til hele poeng (`payoutDecimals`, Golfgutu 0) med `floor(x + 0.5)`, og resten går til største innsats, så ingen poeng skapes eller forsvinner (testet i `BetsTests` og i `sql/lokal/012_prove.sql`).
7. **Push** bare for nye og avgjorte veddemål, som foreslått.
8. **Én side per spiller:** den andre siden sperres etter innsats, som foreslått.
9. **Tippekupongen** har egen bank, ikke samme som veddemålene.

Restrisiko å kjenne til: `settle_bet` sjekker at scorene kan ha gitt svar, men ikke selve svaret (databasen regner ikke netto mot par). En arrangør med innsats kan i prinsippet kalle den direkte med feil utfall på et veddemål med vilkår. Avgjøringene står i aktivitetsloggen (`auto: true`).
