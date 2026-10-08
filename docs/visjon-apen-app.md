# Atten for alle – visjon og plan

Besluttet 07.10.2026 (Thomas): appen skal ha flere bruksområder enn turnering og være **åpen for alle**. Bruksområdene er løse runder med venner, spill på runden, flere konkurranser samtidig og egen statistikk.

## Grepet: runden er kjernen

| I dag | Nytt |
|---|---|
| Klubb → sesong (= turnering) → kveld → runde | **Runde** er kjernen. Den kan stå alene, eller telle i null, én eller flere **konkurranser**. |
| Alle må være med i en klubb | **Klubb** (gjeng) er valgfritt: et fast lag med tropp, terminliste og arrangører. |
| Spilleren er et klubbmedlem | Spilleren er en **profil** (én person, én innlogging). Klubbmedlemskap og gjester kommer i tillegg. |
| Baner per klubb | **Felles banebibliotek** for alle (B15), med lokale rettelser. |
| Tavla = jakkeracet | Hver konkurranse har sin tabell. Jakkeracet er én konkurranse i Golfgutu-klubben. |

Alt som finnes i dag, gjenbrukes oppå runden: føring per bås/flight, offline, Live Activity, tråden, veddemål, push og widgets. **Golfgutu-pariteten står**: jakkeracet skal gi nøyaktig samme svar som før.

## Konkurransetyper

- **Turnering/sesong** (som jakkeracet): regelsett, terminliste, tabell.
- **Liga**: flere runder, poeng per runde, tabell.
- **Cup**: utslag (match), trekning og trestruktur.
- **Morroturnering**: kort periode og egne deltakere, ofte oppå samme kvelder.
- **Spill på runden**: skins, Nassau, Wolf, bingo-bango-bongo, 2 mot 2 (best ball). Gjøres opp i poeng (B10).

En runde kan telle i flere konkurranser samtidig (f.eks. jakkeracet + morrocupen + skins i båsen).

## Faser (erstatter «Etter v1» i ROADMAP)

1. **Fase 12 – Fundament:** profiler, runder uten klubb, gjester, konkurranser som eget lag, og deltakelse som tilgangskontroll (RLS). Migrering av dagens data inn i den nye modellen, med jakkeracet som konkurranse. *Gjøres før byttet (fase 9), så gjengen bare flyttes én gang.*
2. **Fase 13 – Løs runde med venner:** «Ny runde» fra hjem-skjermen på sekunder. Inviter med lenke eller QR, legg til gjester med bare navn, og velg bane fra biblioteket.
3. **Fase 14 – Spill på runden:** skins, Nassau, Wolf, bingo-bango-bongo og 2 mot 2. Gjenbruker veddemålsmotoren og poengbanken.
4. **Fase 15 – Flere konkurranser:** liga, cup og morroturneringer samtidig. «Teller også i …» i oppsettet, og konkurransevelger på tabellen.
5. **Fase 16 – Statistikk:** valgfri føring av fairway, green og putter. Historikk, snitt, beste runder, banerekorder og handicaputvikling.
6. **Fase 17 – Åpent for alle (App Store):**
   - Onboarding uten klubb.
   - Sletting av konto i appen (Apples krav).
   - Personvernerklæring og vilkår.
   - Rapporter og blokker for brukerinnhold (Apples krav for tråd og bilder).
   - Innlogging med Google.
   - Prod-oppsett og kostnadskontroll.
   - Android senere (B13).

## Navigasjon (forslag)

Fanene blir **Hjem** (dine runder og det som skjer), **Spill** (ny runde, pågående, spill på runden), **Konkurranser** (tabeller og påmelding) og **Deg** (profil, statistikk, klubber). Kveld og Tavla lever videre inne i klubben og konkurransen.

## Besluttet 07.10.2026 (Thomas)

1. **Rekkefølge:** fundamentet (fase 12) kommer før byttet for gjengen (fase 9), så dataene flyttes én gang.
2. **Banedata:** brukerne legger inn baner nå, i et felles bibliotek. Skjemaet gjøres klart for en ekstern kilde senere (GolfAPI.io eller lignende), med ekstern id, kilde og når banen sist ble hentet. Lokale rettelser skal overleve en ny henting.
3. **Navn:** appen heter **Atten** (besluttet 08.10.2026, erstatter DashDash). «Golfgutu Invitational» blir en klubb i appen.
4. **Forretningsmodell:** gratis å bruke. **Betaling for å kjøre turnering.** Det må skje som kjøp i appen (StoreKit), ikke Vipps, fordi Apple krever det for alt som låser opp funksjoner. Skjemaet får plass til et abonnement eller kjøp per klubb eller turnering.
5. **Penger:** veddemål og spill er fortsatt **bare poeng** (B10). **Vipps-knapp** brukes for å dele **felles utgifter** (simulatorleie, greenfee, mat, premiepotten) med en ferdig utfylt Vipps-forespørsel. Oppgjør av veddemål i kroner tas ikke inn, fordi det kan regnes som pengespill.

## Opprinnelige spørsmål (besvart over)

1. **Rekkefølge:** fundamentet (fase 12) før byttet for gjengen (fase 9)? Anbefaling: ja, så dataene flyttes én gang.
2. **Banedata (B15):** kilde for et felles banebibliotek (GolfAPI.io eller lignende, lisens og pris), eller banene legges inn av brukerne.
3. **Navn og merke:** blir det «DashDash18» for alle, og «Golfgutu Invitational» som en klubb i appen?
4. **Forretningsmodell:** gratis, betalt, eller gratis med betalte konkurranser/klubber? Det påvirker hva som bygges først og hva Supabase-prod koster.
5. **Penger:** fortsatt bare poeng (B10)? Ekte penger i en åpen app gir regulering (pengespill), så anbefalingen er å holde fast ved poeng.
