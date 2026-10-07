# Datamodell v2: runden er kjernen

Status 07.10.2026: forslag (fase 12). Første steg ligger i `sql/017_fundament.sql` og er **ikke kjørt** mot Supabase. Appens datalag er laget bak `FoundationFeature.isEnabled = false`, så appen oppfører seg som før.

Bakgrunn: `docs/visjon-apen-app.md` (besluttet 07.10.2026). Appen heter DashDash og skal være åpen for alle. Runden er kjernen, og klubb er valgfritt. «Golfgutu Invitational» blir én klubb, med jakkeracet som hovedkonkurranse.

## 1. Måltilstanden

```
profiles ──< club_members >── clubs ──< seasons ──< events
   │              │              │                    │
   │              │              └──< competitions ───┼──< competition_participants
   │              │                     │             │
   │              └─────────┐           └──< competition_rounds >──┐
   │                        ▼                                       ▼
   └──< round_participants ─► round_players ◄──────────────────── rounds ──► courses (klubb eller felles)
                                  │
                                  └──< hole_scores, side_claims, round_matches
```

### Profil: én person, én innlogging
`profiles` har én rad per innlogging (`id` = `auth.users.id`) med visningsnavn, portrett og handicap. Det finnes ett klubbmedlemskap per klubb (`club_members.user_id` peker på profilen) og én deltakelse per løs runde. Profilen lages av en trigger på `auth.users` når noen registrerer seg. `ensure_profile()` fyller tomme felt fra klubbmedlemskapet ved første innlogging, men overskriver aldri det personen har satt selv.

**Handicap:** i klubbrunder bruker appen fortsatt `club_members.handicap_index` (og seedet gruppe). Det holder pariteten. I løse runder gjelder profilens indeks. Begge fryses i `round_players` når runden startes, som før.

### Runden: med eller uten klubb
`rounds.club_id` og `rounds.event_id` kan være tomme. En CHECK (`rounds_home_check`) krever at begge er satt, som i en klubbrunde i dag, eller at begge er tomme, som i en løs runde. En løs runde har en eier (`owner_id`, profil) som serveren setter. Den må bruke en bane fra det felles biblioteket. Alt under runden (hull, deltakere, score, match, sidepremier) er likt for begge typer.

### Deltakere: klubbmedlem, profil eller gjest
`round_players.member_id` er spillerens id i runden. Det er den hullscorene, matchene og sidepremiene peker på.

- **Klubbrunde:** id-en er `club_members.id`, som i dag.
- **Løs runde:** id-en er `round_participants.id`. Raden er enten en profil (`profile_id`) eller en **gjest** (bare navn, `profile_id` tom). En gjest kan senere kobles til en profil, og navnet står igjen hvis kontoen slettes. Triggeren lager `round_players`-raden automatisk, så føring, bås/flight, markør og match virker uendret. `round_players.club_id` er da tom. En fremmednøkkel via den genererte kolonnen `participant_round_id` sikrer at deltakeren finnes i samme runde.

Viewet `round_roster` gir navn og profil for alle deltakerne i en runde, uansett type.

### Konkurranser: eget lag over rundene
`competitions` har disse feltene:

| Felt | Innhold |
|---|---|
| `kind` | `season` (turnering/sesong, som jakkeracet), `league`, `cup` (utslag), `fun` (morroturnering), `game` (spill på runden) |
| `rules` | Regelsettet som jsonb med versjon, samme format som `seasons.rules`. GolfgutuCore leser det, og Golfgutu-verdiene gjelder for felt som mangler. |
| `starts_on`, `ends_on` | Perioden (valgfri) |
| eier | En klubb (`club_id`, der arrangørene styrer) eller en profil (`owner_id`, når `club_id` er tom) |
| `is_main` | Klubbens hovedturnering. Høyst én aktiv per klubb (unik indeks). |
| `entry` | `club` = troppen (aktive pluss dem som har spilt, som Tavla), `listed` = de påmeldte, `open` = alle som spiller en tellende runde |
| `requires_purchase`, `entitlement_id` | Klart for StoreKit. Bare serveren setter dem, se `entitlements`. |
| `season_id` | Satt for sesongens konkurranse. Navn, status og regler speiles da fra sesongen (se kap. 3). |

`competition_participants` er de påmeldte: et klubbmedlem eller en profil. Gjester er med gjennom rundene (`entry = open`).

`competition_rounds` er rundene som teller. **En runde kan telle i flere konkurranser**, for eksempel jakkeracet, morrocupen og skins i båsen. `source = season` er koblet av databasen, og `manual` er lagt til av en arrangør eller eier.

**Samme person på tvers av runder** (`PersonDirectory.entrant` i appen): i klubbens egen konkurranse er et medlem alltid medlemmet, også når hen spiller en løs runde med profilen sin. Ellers er det profilen når den er kjent. Er den ikke kjent, er det bare spilleren i den runden (gjest).

### Felles banebibliotek
`courses.club_id` kan være tom. Da ligger banen i det felles biblioteket, som alle innloggede leser. Klubbens egne baner er som før. For en ekstern kilde senere (GolfAPI.io eller lignende) finnes `source`, `external_id` (unik sammen med `source`) og `fetched_at`. Bare serveren setter de tre feltene.

**Rettelser som overlever en ny henting** (neste migrering): en ny henting skriver bare grunnlaget, altså `courses` og `course_holes` for banen med `source`. Rettelser lagres for seg i `course_corrections` (`course_id`, enten `club_id` eller `profile_id`, valgfritt `hole_number`, og feltene par, indeks, lengde, CR og slope som kan overstyres). Appen legger rettelsen oppå grunnlaget når den leser: brukerens egen, så klubbens, så kilden. Siden hentingen aldri rører `course_corrections`, står rettelsene. En rettelse som blir lik kilden, kan ryddes bort. Brukerlagte felles baner (`source` tom) rettes av den som la dem inn. Andre lager en rettelse.

**Hvorfor ikke kopiere banen per klubb?** Da må hver klubb rette det samme én gang til, og en ny henting kan ikke vite hva som er rettet.

### Kjøp i appen (StoreKit)
`entitlements` har én rad per kjøp eller abonnement med `product_id`, `original_transaction_id`, miljø, status og utløp. Raden hører til en profil og eventuelt en klubb. Bare serveren skriver den, med service_role i en Edge Function som har sjekket kvitteringen mot App Store Server API. Appen leser sine egne, og arrangøren leser klubbens. En konkurranse som krever kjøp, peker på kjøpet (`competitions.entitlement_id`). Jakkeracet krever ikke kjøp.

## 2. Tilgang ved deltakelse (RLS)

| Du ser … | når … |
|---|---|
| en klubbrunde | du er aktivt medlem i klubben (kladder bare som arrangør), som før |
| en løs runde | du eier den eller er med i den (også kladden) |
| en startet runde | den teller i en konkurranse du kan se |
| en konkurranse | den er i en klubb der du er aktivt medlem, du eier den, eller du deltar i den |
| en profil | det er deg, eller du deler en klubb, en løs runde eller en konkurranse med personen |
| en bane | den er i klubben din, eller i det felles biblioteket |

Skriving:

- **Klubbrunder:** uendret. Arrangøren styrer, kanFore gjelder for føring, og alle RPC-ene fra 001–016 virker som før.
- **Løse runder:** eieren har arrangørens rett. kanFore gjelder ellers likt: en markør i båsen fører for båsen, ellers fører spilleren selv. En gjest uten profil føres av markøren eller eieren.
- **Konkurranser:** klubbens arrangør, eller eieren. For å legge en runde inn i en konkurranse må du styre konkurransen **og** være rundens «eier» (arrangøren i klubben, eller eieren av den løse runden). Da samtykker den som eier runden, til at deltakerne i konkurransen ser den.
- **Profiler og påmelding:** du kan bare legge til en profil (i en runde eller en konkurranse) som du allerede kan se. Nye forbindelser lages med invitasjon (fase 13 og 15).

Hjelpefunksjonene `can_read_round`, `is_round_organizer` og `can_score` er utvidet i 017. For klubbrunder gir de nøyaktig samme svar som i 001. Kontroll 9 i 017 og `lokal/017_prove.sql` sammenligner det for hver innlogging og hver runde, før og etter. Uttrykkene som må kunne lese tilbake en ny rad (`insert … returning`), står i policyen og ikke bare i en funksjon. Ellers ville den nye raden ikke vært synlig for funksjonen.

### Trusselmodell: hva en fremmed bruker ikke skal kunne

Når alle kan registrere seg, er en «fremmed» en innlogget bruker uten forbindelse til deg. Hen skal ikke kunne:

1. **Lese noe i en klubb hen ikke er med i:** tropp, kvelder, sesonger, runder, scorer, tråd, tips, veddemål eller bilder. RLS fra 001–016 står uendret.
2. **Finne folk:** det finnes ikke noe søk i `profiles`, og `can_see_profile` krever en felles klubb, runde eller konkurranse. Profil-id-er lekker bare til folk du allerede deler noe med.
3. **Trekke deg inn i noe:** hen kan ikke legge til profilen din i en runde eller en konkurranse uten å kunne se den, så «Mine runder» kan ikke fylles med søppel. Gjester er bare navn i eierens runde.
4. **Se rundene dine via en konkurranse:** bare rundens eier eller klubbens arrangør kan legge en runde inn i en konkurranse.
5. **Føre, endre eller slette i andres runder:** kanFore og eier- og arrangørsjekkene gjelder. Eier, klubb, kilde og «hvem la til» settes av serveren. Kolonnevaktene stopper forsøk på å endre dem (42501).
6. **Låse opp betalte funksjoner:** `requires_purchase` og `entitlement_id` settes bare av serveren, og `entitlements` har ingen skrivetilgang fra appen.
7. **Endre det felles biblioteket for andre:** bare den som la inn en bane, kan endre den, og hentede baner kan ingen endre fra appen. Alle andre lager en rettelse (neste migrering).
8. **Gjette seg inn:** id-ene er tilfeldige uuid-er, og invitasjonskodene (klubb nå, runde senere) er minst 40 bit. Et uuid er likevel ikke en tilgang. Alle oppslag går gjennom RLS.

Dette står igjen og må håndteres senere: hastighetsgrenser (spam med runder, konkurranser og baner) og moderering av navn på felles baner og gjester. Supabase Auth har grenser for innlogging. For resten trengs en kvote per profil (fase 17).

### Apples krav og hva de krever av skjemaet

- **Sletting av konto i appen** (App Store 5.1.1(v)): RPC-en `delete_my_account()` kommer i fase 17. Den sletter `auth.users`-raden (via en Edge Function med service_role, fordi `auth.admin.deleteUser` ikke er SQL). Skjemaet i 017 er laget for det, og `lokal/017_prove.sql` har prøvd det:
  - profilen slettes (`on delete cascade`), og det gjør også påmeldingene i konkurranser;
  - løse runder og konkurranser står igjen uten eier (`set null`), slik at de andres historikk står;
  - deltakeren i en løs runde blir en gjest med navnet sitt;
  - klubbmedlemskapet blir et ledig navn (`club_members.user_id set null`, fra 001);
  - kolonnevaktene slipper gjennom at nøkkelen settes til null når profilen er borte.

  **Åpent spørsmål:** skal navnet anonymiseres («Tidligere spiller») i løse runder og i troppen? Det er personopplysninger i andres historikk.
- **Rapportere og blokkere** (App Store 1.2, brukerinnhold): tråd, bilder og navn er innhold. Neste migrering legger til:
  - `user_blocks (blocker_id, blocked_id)`: den som blokkerer, ser ikke lenger trådmeldinger, reaksjoner og bilder fra den blokkerte. Den blokkerte kan ikke legge deg til i runder eller konkurranser (`can_see_profile` og trådpolicyene får et `not blocked`-ledd).
  - `content_reports (reporter_id, kind, target_id, reason, status, created_at)`, som den som rapporterer, skriver. Bare serveren og moderatorer leser den, og det kommer en e-post eller push til oss når det kommer en rapport. Apple krever handling innen 24 timer.
  - Vilkår (EULA) med «ingen toleranse for støtende innhold» godkjennes ved registrering: `profiles.terms_accepted_at`.

## 3. Hvordan dagens tabeller mappes

| I dag | I v2 | Hva 017 gjør |
|---|---|---|
| `auth.users` | `profiles` (1–1) | Profil til alle, fylt fra første aktive medlemskap |
| `clubs` | `clubs` (valgfritt lag) | Uendret |
| `club_members` | Medlemskap: profil × klubb, med klubbens handicap og seeding | Uendret. `user_id` = `profiles.id` |
| `seasons` | `competitions` med `kind = season` og `is_main` | En konkurranse per sesong. Navn, status og regler speiles av en trigger |
| `events` | Kvelder i klubbens terminliste. En runde kan ligge i en kveld | Uendret. En kveld som bytter sesong, tar rundene med seg |
| `rounds` | `rounds` med valgfri klubb og kveld | `club_id`/`event_id` kan være tomme (med CHECK), `owner_id` |
| `round_players` | Deltakelse. `member_id` er spillerens id i runden | `club_id` kan være tom for deltakere i løse runder |
| (ingen) | `round_participants` (profil eller gjest i løs runde) | Ny |
| `hole_scores`, `side_claims`, `round_matches`, `round_holes` | Uendret, de peker på `round_players` | Uendret |
| `courses`, `course_holes` | Klubbens baner + det felles biblioteket | `club_id` kan være tom, `source`, `external_id`, `fetched_at`, `created_by_profile` |
| (ingen) | `competition_participants`, `competition_rounds`, `entitlements` | Nye |
| `activity`, `thread_messages`, `tips`, `bets`, `push_*` | Hører fortsatt til klubb/kveld | Uendret. Løse runder får tråd og spill i fase 13–14 |

**Golfgutu-klubben:** klubben står. Hver sesong blir en konkurranse med `kind = season`, `is_main = true` og `entry = club`, og rundene i sesongens kvelder kobles til den. Det skjer både for det som finnes nå og for alt som lages senere, uansett om det kommer fra appen, `activate_season` eller importen. Jakkeracet er da hovedkonkurransen. Testene `KonkurranseJakkeracetTests` viser at tabellen regnet via konkurransen er **nøyaktig den samme** som Tavla regner fra sesongen i dag: plass, poeng, duell, sidepremier, matcher, hull, stableford, kvelder, oppsummering og rundenavn. Det gjelder med Golfgutu-oppsettet og med et annet regelsett, og med støy i form av kladder, andre sesonger og runder koblet til andre konkurranser.

## 4. Migreringsvei: additiv og trinnvis

**Valgt:** nye tabeller og kolonner som kan være tomme, i tillegg til views og hjelpefunksjoner. Ingenting bytter navn, og alle RPC-er fra 001–016 virker som før.

Hvorfor ikke en stor omskriving (for eksempel `round_participants` som eneste deltakertabell, og `hole_scores` på deltaker-id):

1. **Pariteten er viktigst.** En omskriving rører hver spørring i Kveld, Runde, Tavla, Tips, Vedd og widgets på en gang. Med additive steg står dagens vei urørt. Den nye veien kan regnes ved siden av og sammenlignes (testene og kontroll 9), og flagget slås på når de er like.
2. **Fase 9 (byttet for gjengen) kommer etter 12.** Importen skriver til dagens tabeller (`Packages/DashImport`). Triggerne i 017 fører dataene over til konkurransene, så importen virker uten endring, og gjengen flyttes én gang.
3. **Rullebakke på test er mulig.** Hvert steg kan tas tilbake for seg (rullebakken i 017 er prøvd lokalt). En omskriving kan i praksis ikke tas tilbake.
4. **`round_players.member_id` er allerede en «spiller-id i runden».** Ved å la den være enten et medlem eller en deltaker slipper vi å flytte hullscorene. Prisen er et navn som ikke lenger er helt presist. Det er dokumentert, og viewet `round_roster` skjuler det.

Prisen ved additivt: noe overlapp i overgangen. Sesongens navn, status og regler finnes både i `seasons` og i `competitions`. Hjelpefunksjonene har to grener. Trinnene under fjerner overlappet.

| Trinn | Innhold |
|---|---|
| 017 (nå) | Fundamentet: profiler, løse runder, gjester, konkurranser, kobling, banefelt og RLS. Seasons er kilden, og konkurransen er et speil. |
| 018 | Invitasjoner (runde, konkurranse), banerettelser (`course_corrections`), blokkering og rapportering, `delete_my_account`, RPC-er for løse runder (`set_loose_round_setup`, `start` og `lock` for eier og `confirm_round_par` for løse runder) |
| 019 | Appen leser konkurranser (flagget på). Speilingen snus: `competitions` blir kilden, og `seasons` blir et view eller en tynn rad med terminliste-tilknytning |
| Senere | Tråd, veddemål og spill på runden for løse runder og konkurranser (`club_id` blir valgfritt der også). Rydde bort `seasons` når ingen klient bruker den |

## 5. Neste steg

**Fase 13 – Løs runde med venner (UI):**
1. Kjør 017 på test etter godkjenning, og så `FoundationFeature.isEnabled = true`. Kall `ensure_profile()` etter innlogging.
2. Lag «Ny runde» på hjem-skjermen med bane fra det felles biblioteket, deltakere (deg, folk du kjenner og gjester med navn) og `create_loose_round`.
3. 018: invitasjon med lenke eller QR (`round_invites` med token og utløp, og RPC-en `claim_round_invite` som kobler en gjest til profilen din), `set_loose_round_setup` og start/lås for eieren.
4. Gjenbruk føringen: `RundeQueries` henter en løs runde på id i stedet for «klubbens pågående», og `RoundSnapshot` får en variant uten klubb og kveld (`RoundOriginRow` finnes).
5. «Ny bane» i det felles biblioteket, og rettelser (`course_corrections`).

**Fase 15 – Konkurranser (UI):**
1. Hent konkurransene: klubbens, egne og de du deltar i. Velg konkurranse på Tavla.
2. Tabellen: klubbkonkurranser bruker `CompetitionScope.tavlaInput` og `TavlaStandings`, som er bevist lik dagens. Andre bruker `CompetitionScope.input` og `CompetitionBoard`.
3. «Teller også i …» i runde-oppsettet (legg til eller fjern i `competition_rounds`), og påmelding med invitasjon.
4. Snu speilingen (019) når Tavla leser via konkurransen.

**Import (fase 9) mot den nye modellen:**
1. Importen kan kjøres uendret etter 017. Triggerne lager konkurransen for sesongen og kobler rundene. Kontroll 6 og 7 i 017 bekrefter det etter importen.
2. Paritetssjekken (`Parity.swift`) utvides til også å regne tabellen via `competitions`/`competition_rounds` og sammenligne med PWA-ens `round_points`.
3. Når gjengen logger inn, lager `ensure_profile()` profilen fra `club_members`. Navnene i troppen blir profilnavn.
4. Senere (etter 019): `ImportPlan` skriver konkurransen eksplisitt i stedet for å stole på triggeren.

## 6. Åpne spørsmål

1. **Trigger på `auth.users`:** Supabase tillater den (det er det vanlige `handle_new_user`-mønsteret), men den må lages som `postgres` i SQL Editor. Alternativet er bare `ensure_profile()` fra appen. Den finnes uansett.
2. **Profilens navn og troppens navn:** skal profilnavnet følge troppen (klubben eier navnet), eller omvendt? 017 fyller bare tomme felt.
3. **Gjester i klubbrunder:** 017 tillater gjester bare i løse runder. Skal en gjest kunne være med på en kveld i Golfgutu (uten å telle i jakkeracet)?
4. **Hvem ser en løs runde i en konkurranse:** nå ser alle som kan se konkurransen, alle startede runder i den, med navn. Er det riktig for åpne konkurranser?
5. **Anonymisering ved sletting:** se Apple-kravene over.
6. **Hovedturnering:** 017 lar bare sesongen være hovedturnering. Skal arrangøren kunne velge en annen konkurranse som hovedturnering?

## Foreslåtte svar på de åpne spørsmålene (07.10.2026, kan overstyres)

Disse legges til grunn for fase 13–17 til brukeren sier noe annet.

1. **Profilen lages begge steder:** triggeren på `auth.users` og `ensure_profile()` fra appen, som sikkerhetsnett.
2. **Navnet:** profilen eier navnet. En klubb kan vise et eget kallenavn (troppens navn) inne i klubben.
3. **Gjester i klubbrunder:** ja, som i løse runder. De teller ikke i klubbens hovedkonkurranse med mindre arrangøren sier det.
4. **Åpne konkurranser:** deltakerne ser rundene som teller, med navn. Andre ser bare tabellen.
5. **Slettet konto:** navnet erstattes med «Slettet spiller». Scorene blir stående, så tabellene ikke endres.
6. **Hovedturnering:** som standard sesongen. Arrangøren kan velge en annen konkurranse senere (fase 15).
