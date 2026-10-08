# Arrangørsiden – vurdering mot beste praksis (08.10.2026)

Status: gjennomført 08.10.2026 (se fase 11 i ROADMAP). Arrangør-fanen ble en knapp i Kveld-fanen i stedet. Grunnlag: gjennomgang av `Features/Admin/` og research på Apple HIG, Nielsen Norman Group, OOUX og arrangørflyten i Spond, TeamSnap, Golf Genius, 18Birdies og Heja.

## Konklusjon

Hovedgrepet fra fase 11 («I kveld» øverst, sjeldne ting under) er riktig. Det som gjør siden kronglete, er under huben: tre rundelister med nesten likt navn, to parallelle oppsettsflyter, samme handling på tre–fire steder, rader som åpner menyer i stedet for å navigere, og at «Kvelden» ikke finnes som ett sted. I tillegg er arrangørhandlinger spredt ut over Kveld, Varsler, Runde, Tips, Vedd og Deg.

## Hva som skurrer i dag

1. **Tre rundelister.** Raden «Alle runder» (AdminHubView) → skjerm «Runder» (RundeAdminView, én kveld om gangen med Picker) → rad «Rundene» (RundeneView, alle startede) → rundetabell. «Alle runder» leder ikke til alle runder, og «Runder» og «Rundene» er to ulike ting.
2. **To oppsettsflyter for samme kladd.** Hurtigstart er standard, «Steg for steg»-veiviseren ligger bak en «Mer»-meny (RundeQuickStartView). Hurtigstarten pusher i tillegg to skjermer inne i arket («Spillere og båser», «Flere valg»). HIG fraråder navigasjonshierarki inni en modal.
3. **Samme handling flere steder.** «Avslutt kvelden» finnes som hovedknapp på huben og som seksjon i Runder. «Lås» og «Avkort» finnes i radmenyen, i rundetabellens verktøylinje og i avslutt-dialogen. Apple (WWDC22): duplisering gjør det uklart «hvor ting hører hjemme og hvorfor».
4. **Rader som er menyer.** I Runder åpner trykk på en rad en `Menu`, ikke en skjerm. Det bryter forventningen fra resten av appen og skjuler handlingene.
5. **«Ferdig»-alert etter hver handling.** Lagre kladd, slett, lås: alle gir en modal med OK. NN/g: hver avbrytelse koster tid; statusen bør vises der den gjelder.
6. **«I kveld» når kvelden er om fem dager.** Overskriften sier én ting, nedtellingspillen en annen.
7. **Fire–fem nivåer for å endre én regel.** Hub → Sesong og regler → liste over sesonger → sesong → Endre reglene → Avanserte valg. Normalen er én aktiv sesong; lista er et ekstra nivå uten verdi.
8. **Terminlista ligger under «Sesongen», men er uavhengig av sesong** (egen tekst sier det). Kvelder og runder er i praksis samme objekt sett fra to kanter, men bor på to steder.
9. **Avhengigheter oppdages som blindveier.** Terminlista sier «lag sesong først», banevalget sier «legg inn par først», huben sier «legg inn kveldene først». Rekkefølgen sesong → baner → tropp → terminliste → runde vises aldri samlet.
10. **Arrangørhandlinger utenfor huben.** Purring (Kveld), Melding til alle (Varsler-verktøylinja), par-bekreftelse (Runde), tips-innstillinger (Tips), avgjør veddemål (Vedd), Rapporter og invitasjonskode (Deg). Noe av dette hører hjemme i kontekst, men arrangøren har ingen oversikt over hva hen kan gjøre.
11. **Inngangen ligger tre nivåer ned** (Deg → Arrangørsiden → område). Under en kveld veksler arrangøren mellom Kveld-fanen og Deg → Arrangørsiden → Runder.

## Beste praksis, kort

- **Hub-mønsteret passer** når brukeren holder seg til én gren per økt, som en arrangør gjør på en kveld (NN/g, mobile navigation patterns). Huben må da svare på «hva er neste steg» øverst (NN/g, visibility of system status).
- **Skill «denne kvelden» fra «oppsett som sjelden endres».** HIG Settings: sjeldne innstillinger i eget område, oppgavespesifikke valg der oppgaven er. Golf Genius gjør akkurat dette: oppsett på web, «Round Settings» på spilledagen.
- **Organiser etter objekter, legg handlingene på objektet** (OOUX). Objektene her er Sesong, Kveld, Runde, Spiller, Bane. Spond og Heja legger admin-inngangen på objektet (gruppen, arrangementet), ikke i en løs meny.
- **Maks to nivåer under huben** (NN/g progressive disclosure: over to nivåer gir dårlig brukbarhet).
- **Én sheet om gangen, ingen hierarki inni en modal** (HIG Modality og Sheets). Lange flyter bør være skjermer, ikke ark.
- **Én primærhandling per skjerm**, sekundære i en mer-meny (HIG Toolbars).
- **Samme ord betyr samme ting overalt**, og tittelen på skjermen gjentar raden du trykket på (NN/g konsistens, HIG titler).
- **Tomme tilstander forklarer hva som kommer der og har knappen som fyller dem** (NN/g empty states).
- **Antall felt, ikke antall steg, avgjør hvor tungt et skjema føles** (Baymard). Gjenbruk forrige kvelds valg som standard (NN/g wizards).

## Forslag til ny struktur

### Inngang
Egen fane **Arrangør** som bare arrangører ser (som Spond og 18Birdies). Da er arrangørrollen synlig, ett trykk unna, og Deg blir ren profil. Alternativ hvis fem faner blir for mye: knapp i Kveld-fanens verktøylinje.

### Huben (tre blokker)

**1. Neste steg** (øverst, tilstandsstyrt). Beholder TonightCard og hovedknappen, men:
- Overskriften er datoen («Torsdag 15. oktober · om 5 dager»), ikke «I kveld».
- Når noe mangler for å komme i gang, vises en kort sjekkliste med lenker: Sesong, Baner klare, Tropp, Neste kveld. Hvert punkt har ✓ eller en knapp. Det erstatter dagens blindveier.

**2. Kveldene.** Én rad → én liste over kveldene (dagens terminliste), der hver rad viser dato, påmeldte og rundestatus (Kladd / Pågår / Låst). Trykk på en kveld → **Kvelden**-skjermen med alt som hører til den: tid og sted, sosialkomité, påmelding og purring, kveldens runder (+ Ny runde), «Melding til alle» og «Avslutt kvelden». Det slår sammen Terminliste, Runder, Rundene og AvsluttKveldenSection til ett objekt.

Rundetabellen (RoundTableView) blir rundens skjerm, nådd ved trykk på runden. Avkort, lås, rett hull og slett ligger der, og bare der. Radmenyen forsvinner.

**3. Oppsett** (sjelden).
- **Sesong og regler**: lander rett på aktiv sesong med sammendrag og «Endre reglene». «Alle sesonger» og «Ny sesong» som rader nederst.
- **Troppen**: som nå, pluss invitasjonskoden og «Del invitasjonen» flyttet hit fra Deg.
- **Banene**: som nå.
- **Varsler til troppen**: «Hva blir push», «Hvem har push» og en snarvei til «Melding til alle» samlet.
- **Rapporter** flyttes hit fra Deg når moderering er på.

### Ny runde
Én flyt. Hurtigstarten beholdes, «Steg for steg»-veiviseren fjernes. Flyten åpnes som pushet skjerm fra Kvelden (ikke sheet), så «Spillere og båser» og «Flere valg» blir vanlige undernivåer med tilbakeknapp. Kladden er allerede eksplisitt lagring, og DiscardChangesGuard dekker avbryt.

### Tilbakemelding
«Ferdig»-alertene erstattes av status i lista (pillen skifter til «Pågår» eller «Låst») og en kort ikke-blokkerende melding. Alert bare ved feil.

## Prioritert rekkefølge

1. Navn og rundelister: slå sammen Runder/Rundene, la rader navigere, flytt rundehandlinger til rundens skjerm. Størst forvirring, minst risiko.
2. Huben: datooverskrift og sjekkliste i «Neste steg».
3. Kvelden som ett objekt (terminliste + runder + purring + melding + avslutt).
4. Sesong og regler lander på aktiv sesong.
5. Én oppsettsflyt, pushet i stedet for ark.
6. Samle varsler, flytt invitasjonskode og rapporter.
7. Egen Arrangør-fane.

## Kilder

- HIG Tab bars, Toolbars, Modality, Sheets, Settings, Lists and tables: developer.apple.com/design/human-interface-guidelines/
- WWDC22 «Explore navigation design for iOS»: developer.apple.com/videos/play/wwdc2022/10001/
- NN/g: mobile-navigation-patterns, progressive-disclosure, complex-application-design, wizards, visibility-system-status, empty-state-interface-design, modal-nonmodal-dialog, consistency-and-standards, modes, flat-vs-deep-hierarchy (nngroup.com/articles/…)
- OOUX: alistapart.com/article/object-oriented-ux/
- Baymard: baymard.com/blog/checkout-flow-average-form-fields
- Spond: help.spond.com/app/en/articles/133292 · TeamSnap: helpme.teamsnap.com/article/831 · Golf Genius: intercom.help/tournament-management/en/articles/10777399 · 18Birdies: help.18birdies.com/article/774 · Heja: help.heja.io/en/articles/5700940
