# Veddemål med poeng (fase 10, B10)

Beslutningsnotat. Forslag til godkjenning. Regelmotoren er bygd (`Packages/GolfgutuCore/Sources/GolfgutuCore/Bets.swift`), SQL-en er et forslag (`sql/012_veddemaal.sql`, ikke kjørt), og appen har skjermene bak `BetsFeature.isEnabled = false`.

## Hva PWA-en gjør (fasit)

- Et **veddemål** (`markets`) er en påstand. Alle kan satse JA eller NEI. Med et **vilkår** (`vilkaar`) avgjør appen det selv (`vilkaarUtfall`); uten vilkår er det fri tekst, og arrangøren avgjør.
- **Malene** i vedd-arket (`utfordringMaler`): mot en spiller «han slår meg netto på hull N» (hull-duell), «han holder par eller bedre på hull N», «han slår meg netto i runden» (bare før første slag) og «han kommer på pallen» (fri tekst). Om deg selv: birdie og par på ditt neste hull, «noen får birdie», ellers «vinner runden» og «pallen i sesongen» (fri tekst).
- **Låsing:** et hullveddemål må ligge fram i tid. Fronten er høyeste førte hull + 1, målt per spiller (duellen følger den av de to som har kommet lengst, «noen» følger lederen). Første åpne hull er fronten + forspranget (1). Før noen har begynt, er hull 1 åpent. Veddemål om hele runden stenger ved første score (`forsteApneHull`, `markedTarInnsatser`).
- **Avgjøring:** arrangørens telefon feier etter hver henting og avgjør det vilkåret gir svar på (`oppdaterMarkeder`). Delt hull, delt match og likt resultat gir ikke noe svar, og arrangøren tar dem for hånd.
- **Oppgjør:** vinnersiden deler taperpotten etter innsats. Ingen på vinnersiden, eller ingen tapere: alle får innsatsen tilbake (`marketNetFor`, `veddemaalPoster`). Overføringene nettes per motpart (`skyldOversikt`).
- **Beløp:** 50, 100 eller 200 kr, tak 200 kr per veddemål summert over dine innsatser. Ingen saldo; gjelden ble gjort opp med Vipps.

## Forslaget: samme veddemål, med poeng

1. **Poengbank per sesong.** Hver spiller starter sesongen med en startbeholdning (forslag **1000 poeng**). Saldo = start + netto fra avgjorte veddemål. Ledig = saldo − det som står i åpne veddemål. Du kan ikke sette mer enn du har ledig. Saldoen **lagres ikke**; den regnes av innsatsene, i appen (`Bets.balance`, `available`) og i databasen (`bet_points`), med samme regnestykke.
2. **Innsats:** knappene 50, 100 og 200, 100 er valgt når arket åpnes (som PWA-en). Flere innsatser på samme veddemål er lov, men alltid på samme side (nytt: PWA-en sperret ikke den andre siden).
3. **Tak:** 200 poeng per veddemål og spiller, summert. Sjekkes i appen og i databasen.
4. **Oppgjør:** som PWA-en. Vinnersiden deler taperpotten etter innsats. Poengene flytter seg **i det veddemålet avgjøres** (PWA-en skrev poster først når kvelden var ferdig, fordi det var ekte penger som skulle betales). Overføringene vises som regnestykket («Du vant 50 fra Erik»), nettet per motpart.
5. **Annullert** (nytt): arrangøren kan annullere et veddemål. Alle får innsatsen tilbake. Utveien for delt hull, delt match og likt resultat.
6. **Poengtabellen for veddemål** er egen, ved siden av jakketabellen under Tavla: saldo, netto, det som står ute og antall vunnet. Sortert på saldo, så navn. Den påvirker ikke jakkeracet.
7. **Fritekst** avgjøres av **arrangøren**, som i PWA-en. Veddemål med vilkår avgjøres av feiingen på arrangørens telefon, og arrangøren har knappene som nødutgang.

## Regelverdier i regelsettet (`Ruleset.bets`)

| Felt | Betydning | Golfgutu |
|---|---|---|
| `lockAheadHoles` | Forspranget: hvor mange hull foran spilleren det første åpne hullet ligger (`VEDDEMAAL_FORSPRANG`) | 1 |
| `maxStakePerBet` | Tak per veddemål og spiller (`VEDD_TAK`) | 200 |
| `stakeOptions` | Beløpsknappene (`VEDD_BELOP`) | 50, 100, 200 |
| `defaultStake` | Valgt beløp når arket åpnes | 100 |
| `startingPoints` | Startbeholdning per sesong. `null` = ingen bank (bare taket gjelder, saldo kan gå under null) | 1000 (forslag, finnes ikke i PWA-en) |

Grensene for birdie (netto ≤ −1) og par (≤ 0), oppgjørsmodellen og avrundingen til to desimaler (`rund2`) er vilkårets og oppgjørets definisjon og blir i koden. Med Golfgutu-oppsettet gir motoren samme låsing, utfall, maler og oppgjør som PWA-en (`Fixtures/veddemaal.json`, regnet ut av PWA-koden).

## Avvik og funn i PWA-en

- Et hullveddemål på et hull etter avkortingen («felles» etter hull 14, veddemål på hull 15) står fortsatt **åpent** i `markedTarInnsatser` (sperra sjekker ikke øvre grense), men kan aldri avgjøres. PWA-en varsler om dem ved avkorting (`hengende`). Beholdt for paritet; appen bør vise dem som «må avgjøres for hånd».
- En spiller uten score (front 0) har hull 1 åpent midt i runden. Malene mot ham tilbyr da par på hull 1. Riktig etter regelen («ingen har begynt»), men rart for en som ikke er i runden. Beholdt.

## Åpne spørsmål til deg

1. **Startbeholdning:** 1000 poeng? Eller ingen bank (`null`), slik at bare taket gjelder og saldoen kan gå under null, som i PWA-en med kroner?
2. **Ved sesongslutt:** skal noe skje med saldoen (premie for flest poeng, nullstilling, overføring til neste sesong)? Forslaget nullstiller ved ny sesong (banken er per sesong) og gjør ingenting annet.
3. **Hvem avgjør fritekst?** Arrangøren (forslaget). Alternativ: den som la det ut og den det gjelder er enige, eller flertall av dem som har satset.
4. **Skal arrangøren kunne satse** på veddemål han selv avgjør? PWA-en tillot det.
5. **Annullering:** ok som ny mulighet? Og skal delt hull eller likt resultat annulleres automatisk i stedet for å vente på arrangøren?
6. **Avrunding:** oppgjøret gir desimaler (100 delt på tre = 33,33). Holde to desimaler som PWA-en, eller runde til hele poeng (største rest) så tabellen bare har heltall?
7. **Push for hver innsats:** PWA-en logget «X satset 100 på JA». Forslaget logger bare nye og avgjorte veddemål. Ok?
8. **Én side per spiller:** ok å sperre den andre siden når du har satset?
9. **Tippekupongen** har egen innsats i poeng (fase 7). Skal den gå inn i den samme poengbanken?
