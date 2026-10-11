# Konkurranser, påmelding, medlemmer og sosialt lag: gap-analyse og plan

11.10.2026. Grunnlag: oppdraget fra Thomas (konkurranser, påmelding, medlemmer og sosialt lag) og researchrapporten i [`research/golfapper-research.md`](research/golfapper-research.md). Kartlagt mot iOS-appen (`DashDash18/`, `Packages/GolfgutuCore/`), appens SQL (`sql/001`–`043`, alt kjørt på test, ingenting i prod), web (`web/`) og PWA-en (`referanse/golfgutu-pwa/`, bare lest).

**Status:** svarene fra Thomas 11.10.2026 står under «Beslutninger». Ingen Swift-kode eller SQL er skrevet for dette ennå. Fasene er lagt inn i `ROADMAP.md` som fase 27–34.

## Beslutninger 11.10.2026 (Thomas)

| Tema | Beslutning |
|---|---|
| Målgruppe | Alle: vennegjenger, klubber og simulatorsentre fra første versjon |
| Funksjoner | Alt blir med. Ingenting skjules bak flagg som er av (veddemål, tippekupong, spill på runden, Del regningen, TV, web-admin og stab) |
| Rekkefølge | Alle fire bygges: rydde modellen (034–035), påmelding per kveld, tavla og resultatkort, App Store-grunnmur |
| Handicap | Dynamisk: velges i regelsettet per turnering, som i dag. Ingen fast standard |
| Standardsvar | Som i dag: ingen rad betyr «ikke svart» |
| Frister | Ingen frister som standard. Arrangøren slår dem på |
| Venteliste | Automatisk opprykk når det blir ledig plass, med varsel |
| Likhet i sesongtabellen | Playoff, som i PGA, bare om førsteplassen. Spilles på stedet etter siste runde, på banen eller i simulatoren etter hva turneringen bruker. Tabellen viser delt plass til playoffen er spilt. Andre likheter er delt plass |
| Prod | Nytt Supabase-prosjekt «Dash18 Prod», med samme oppsett som Dash18 Test |
| Del regningen | Din del merkes «sendt» automatisk når du kommer tilbake fra Vipps. Mottakeren bekrefter eller sier at den ikke kom. Ingen penger gjennom appen, ingen avtale med Vipps |
| App Store | Målet for første versjon (B1 endres) |
| Roller | Klubben lager egne roller. Malene er Eier, Arrangør, Kasserer, Sosialkomité og Medlem, og klubben kan endre dem, gi dem nytt navn eller lage nye. Hver rolle får rettigheter i fire grupper: turneringer og regler, runder og føring, medlemmer og invitasjon, penger og moderering |

Konsekvenser for planen:

- M4, M5 og spørsmål 2: B10 endres. Del regningen får status «sendt» og «bekreftet» (`bill_splits`, `bill_split_shares`). Veddemål og tippekupong blir med som i dag.
- M6 og spørsmål 9: B1 endres til App Store.
- M2 og spørsmål 3: i stedet for flagg og en eierkolonne kommer `club_roles` (navn, rettigheter) og `club_member_roles`. Hjelperne i RLS spør etter rettighet (`private.has_club_right(club, right)`), ikke etter `is_organizer`. `is_organizer` og `is_treasurer` speiles til gamle bygg er borte.
- Spørsmål 4: påmelding per kveld har tak og automatisk opprykk, frister bare når arrangøren slår dem på, og ingen standardsvar.
- Spørsmål 5: regelsettet får `tieRule = playoff` for førsteplassen. Playoff-hullene føres som en egen kort runde (`rounds.kind = playoff`) koblet til turneringen, slik at slag per hull fortsatt er det eneste som lagres.
- Spørsmål 6: ingen ny standard. NGF-settet legges til som valg i regelsettet.

Fortsatt åpne: aldersgrense (spørsmål 8), blind og ghost (10), «klubb» som navn (11), og valgene i `docs/vedd-per-turnering.md`.

## Kort fortalt

Appen er ikke et tomt prosjekt. Fase 1–26 har bygget mye av det researchen anbefaler: egen Supabase, klubber med flere medlemskap, invitasjon med lenke og QR, ledige navn som kan kreves, regelsett per turnering, beste N, påmelding med tak og venteliste (på turneringsnivå), offline-føring med utboks, Hjem-feed, reaksjoner, push fra Edge Function rett til APNs, Live Activity, rapportering, blokkering og kontosletting.

Det som mangler, er i hovedsak:

1. **Påmelding per kveld** med standardsvar, to frister, tak og venteliste. Dette finnes i dag bare for turneringer, og kveldspåmeldingen skrives rett i tabellen.
2. **Formater i to akser** (lagform og poengtelling), flere spill per runde som likeverdige, og øyeblikksbilde av regler og hull ved start.
3. **Sesongbygger og gjenbruk:** serie fra malkveld, spillbibliotek, «samme som sist», «ny sesong fra forrige».
4. **Sosialt:** kommentarer, reaksjoner på alt (ikke bare hendelser), fri emoji bak «+», felles feed med sideinndeling, galleri og delebilde med bilde.
5. **Moderering og App Store:** myk sletting, tekstfilter, varsel til deg ved rapport, vilkår som håndheves, Apple-token som trekkes tilbake, demogruppe.
6. **Kalender:** abonnement per medlem, «avlys» som er noe annet enn «slett», «ny dato, kan du fortsatt?».

Flere punkter i oppdraget strider mot beslutninger som er tatt (B1, B10, paritet, skins). De står i neste avsnitt og må avgjøres før fase 28.

## Motstrid som må avklares først

| # | Oppdraget sier | Det som gjelder i dag | Mitt forslag |
|---|---|---|---|
| M1 | Tre Supabase-prosjekter: «Golfgutu», «Golfgutu Test», «Native Golfgutu» | Appen bruker sitt eget prosjekt **«Dash18 Test»** (`tsekialrxuhrugscosgi`, B4). Innloggingen jeg har, ser bare det. Prod finnes ikke ennå | Fortsett på Dash18 Test. Si fra om «Native Golfgutu» skal bli prod |
| M2 | `groups`, `group_members(role)` med eier, admin og medlem, `group_id` overalt | `clubs` og `club_members` med flaggene `is_organizer` og `is_treasurer` (sql/001:96), `club_id` overalt, turneringsstab i `competition_staff` | **Behold «klubb» som gruppen.** Navnebytte gir stor migrering uten gevinst. Legg til eier (`clubs.owner_id`) og eieroverføring. Les «group» som «club» i resten av planen |
| M3 | Hjelpefunksjoner i et skjema som ikke er eksponert (`private.my_group_ids()`) | Hjelperne ligger i `public` (`is_club_member` m.fl.), med `revoke … from anon` | Nye hjelpere legges i `private`. De gamle flyttes i én egen migrering med lasttesten fra fase 24 |
| M4 | Penger som regnskap: hvem skylder hvem, betalt og bekreftet | B10: «Ingen kroner i appen: ingen skyldliste, Vipps …». Men «Del regningen» med Vipps er bygget og slått på (#31) | Din avgjørelse (spørsmål 2) |
| M5 | Veddemål, tippekupong og bank bak et flagg som er av | Veddemål med poeng er på (fase 10, `BetsFeature`). Tippekupongen har ikke flagg. Banken er ikke importert | Din avgjørelse (spørsmål 2). Poeng uten innsats er trolig innenfor 5.3, men er ikke avklart |
| M6 | «Før App Store», App Review, demogruppe | B1: «Offentlig App Store er ikke et mål for v1.» Fase 17 er likevel bygget for App Store | Oppdater B1 til App Store som mål |
| M7 | Bygg ikke TV-visning eller cut | TV-visning med kode er bygget (fase 26, din bestilling 10.10). Avkorting er en PWA-regel (gjengen bruker den) | Behold begge. Ingen flere klubbfunksjoner utover det |
| M8 | NGF-standard: Stableford 100 %, én avrunding, 9 hull etter indeks, NGF-prosenter for par | Golfgutu-oppsettet må gi samme svar som `db-nytt.js` (CLAUDE.md): 95 %, avrunding to ganger, halvt handicap på 9 hull, snitt for par | Golfgutu-oppsettet står urørt. NGF blir eget **handicapsett** i regelsettet og standard for *nye* turneringer |
| M9 | Skins som spill | «Skins og halve slag» er utenfor omfang (ROADMAP 4), men skins finnes som spill på runden (fase 14) | Fjern skins fra «utenfor omfang» |
| M10 | Betaling: arrangøren kjøper sesongopplåsing, ikke bygg nå | Kjøp per liga/cup er bygget (sql/023), flagget er av. Sesonger i klubb er gratis | La flagget stå av. Når det slås på, bør modellen være sesongopplåsing for arrangøren |
| M11 | PWA-en må flytte til nye nøkler | B3: PWA-en og PWA-basen er urørt til byttet | Noteres. PWA-en fryses ved byttet, så den trenger bare nye nøkler hvis byttet skjer etter at de gamle nøklene er borte (utgangen av 2026) |
| M12 | Reaksjoner: alle emojier bak «+» | Fast sett på fem (sql/008:125), «må stå likt i appen» som PWA-en | Kravet om likhet gjaldt sameksistens, som ikke skal skje (B3). Fri emoji kan innføres |

## Gap-tabell: de 22 løsningene

Status: **F** finnes, **D** delvis, **M** mangler.

### Grunnmur

| # | Løsning | iOS-app | PWA | Hvor i appen | Hva må gjøres |
|---|---|---|---|---|---|
| 1 | Flere grupper og roller | D | M | `clubs`, `club_members` (sql/001:78, 98), flere klubber per bruker, roller som flagg; `competition_staff` (031); kasserer, sosialkomité (`event_committee`); siste arrangør vernet (`guard_club_members`, 024) | Eier og eieroverføring, «forlat klubben» med etterfølger, rollekartet (dommere har ingen rolle i dag). Telefon og e-post er ikke i `club_members`, så de er allerede skjult |
| 2 | Invitasjon | D | M | Lenke på dashdash18.com, QR (`InvitePlayersViews.swift`), `club_preview`/`join_club` (001:1221), runde- og turneringskoder med utløp (018, 022). Klubbkoden er 12 tegn uten utløp, tak, teller eller tilbaketrekking | `club_invitations` med kort kode (6 tegn), utløp, tak, teller, tilbaketrekking; «krev godkjenning» (i dag alltid), «lås klubben», «ny kode». Nettsiden: klubbnavn og App Store-knapp (i dag en plassholder) |
| 3 | Spillerrader som kan kreves | F | F | Ledige navn (`club_members.user_id null`), «Er dette deg?» i `club_preview`, `claim_round_invite` i løse runder | Bare småting: matching på telefon er ikke mulig (vi lagrer ikke telefon). Gjest på en kveld (se 10) |
| 4 | Formater som data | D | M | `rounds.format` (én verdi), `round_games` med `kind` og `settings` (020); `CompetitionForm.all` blander lagform og poengtelling; frosset indeks, seed, `playing_handicap` (B16), tee og hull for hentede baner (029, 030). Regelsettet leses levende | To akser i motoren (`TeamForm` × `Scoring`) med oversetting fra dagens id-er; `format_version` og `config` per spill; øyeblikksbilde av regelsett og alle hull ved start. Paritetstestene må stå |
| 5 | Apple-pakken | D | M | `ModerationFeature`: `content_reports`, `user_blocks`, blokk filtrert i RLS (019, 025); rapport bare på tråd og bilde; kø for arrangøren; `accept_terms` (stille ved onboarding); `delete-account` deployet; Apple-innlogging | Rapport på profil, medlem og kommentar; tekstfilter; myk sletting (i dag hard); varsel til appeier ved rapport; vilkår godtatt uttrykkelig og håndhevet i serveren; tilbakekalling av Apple-token; demogruppe med kode |
| 6 | Penger som regnskap | D | F | «Del regningen» (lik deling + Vipps, ingen status, ingenting lagret); poengoppgjør med nullsum i spill på runden (020) | Avhenger av spørsmål 2. Med ja: `settlements` med linjer, betalt av betaler, bekreftet av mottaker, nullsumsjekk |
| 7 | Offline scoreføring | F | M | SwiftData-utboks (`OutboxItem`), `save_hole` idempotent med `recorded_at`, nøkkel (runde, spiller, hull), `updated_by`; markør per bås, arrangøren retter alltid | Vis «ført av / når» på tavla; skrivebeskyttet kort med «ta over føringen» (RPC); id fra telefonen sendt med (sporbarhet); prøve med to telefoner (henger sammen med Broadcast) |

### Arrangørens uke

| # | Løsning | iOS-app | PWA | Hvor i appen | Hva må gjøres |
|---|---|---|---|---|---|
| 8 | Sesong som eget objekt | D | D | `seasons.rules` / `competitions.rules`; beste N (`table.counting`, `LeagueRules.bestRounds`), delte poeng (`League.placings`), deltakerpoeng (liga), `rounds.weight` (0 = teller ikke), tiebreak (`Tiebreak`) | Resultattype for sesongen (poeng, Stableford, netto, brutto), snitt, minste antall kvelder, navngitte poengtabeller (finale), «kveld teller ikke» på kvelden, avstand til leder og strøkne kvelder i raden, eclectic, uttrykkelig likhetsregel |
| 9 | Sesongbygger og gjenbruk | D | M | Ny kveld foreslår +7 dager og samme sted; hurtigstart kopierer forrige runde (`QuickStart`); `RoundSetupIssue` | Serie fra malkveld × frekvens × antall med «bare denne / denne og fremtidige»; spillbibliotek per klubb; «samme som sist, ny trekning» som én knapp; «ny sesong fra forrige»; sjekk for spiller uten bås og manglende tee |
| 10 | Påmelding | D | D | Kveld: `signups` (kommer, usikker, kommer ikke + kommentar), skrevet direkte med RLS. Turnering: frister, tak, venteliste med tilbud i 48 t, låsende RPC-er (031–032) | Det samme per kveld: standardsvar, påmeldings- og avmeldingsfrist, tak, ventelisteregel (automatisk, tilbud, arrangøren velger), én RPC med `for update`, logg, «ikke sett», vikar, gjest. Fjerne skrivepolicyene på `signups` |
| 11 | Påminnelser | D | D | `queue_evening_reminders` (alle, 7 dager før), purring til alle som ikke har svart | Purring styrt av svar og frist (48 t før), «det er i kveld» til de som kommer, purring med navnevalg, e-post bare til dem uten push |
| 12 | Trekning | D | D | Trekant ved oddetall (`Triangle`), sveitsisk trekning etter tabellen, flytt og markør i oppsettet | Trekning som unngår gjentakelser, «spilt sammen», balanserte lag etter handicap, «bytt to», status «trukket / ikke møtt» per runde med «resten av sesongen», fyll opp bås. Blind og ghost bare etter ditt ja |
| 13 | Spillehandicap | D | D | `Handicap.swift`, `handicap_allowance`, `formAllowances`, ekstern handicap, frosset spillehandicap | NGF-sett og WHS-sett (merket sekundærkilde) som regelverdier, én avrunding og 9 hull etter indeks som valg utenfor Golfgutu (M8), handicapkilde per sesong med «bekreft før kvelden», likhet (delt, 9-6-3-1, laveste hcp) for slagspill, slag-per-hull-oversikt for Gimmie |
| 14 | Rundestatus og tavle | D | D | `draft/active/locked`, «etter N hull», arrangøren retter etter låsing og alt regnes om | «Uoffisielt» til kvelden avsluttes (likhet og poeng deles ut da), delt plass, pågående Stableford mot par (poeng − 2 × hull), «skjul tre siste hull», «skjul scoren min» |
| 15 | Formatoppskrifter og sidekonkurranser | D | D | Former i `CompetitionForm`, lag mot lag (`MatchPlanner`), skins som spill, ett LD- og ett KP-hull, egne krav i `side_claims` | Oppskriftsliste med «Avansert»; amerikaner og københavner (etter sjekk mot NGF); flere LD/KP-hull, varsel ett hull før, innmelding per flight |

### Det sosiale laget

| # | Løsning | iOS-app | PWA | Hvor i appen | Hva må gjøres |
|---|---|---|---|---|---|
| 16 | Kveldstråd og feed | D | D | `activity` (008, `club_id`), `thread_messages` per kveld med bilde og @-omtale, Hjem-feed (`my_activity`, 037) med tidsvindu og `limit 150` | Felles feed (hendelser + innlegg) med keyset-RPC som også gir tall og mine reaksjoner; innlegg på klubbnivå; `comments` med omtale og sletting; hendelsene «kvelden startet», birdie, «runde ferdig», resultatkort; «følg tråden» og varsel til forfatteren |
| 17 | Reaksjoner | D | D | Fem faste på `activity` (sql/008:130), hvem som reagerte, angre | Reaksjoner på innlegg og kommentarer, fri emoji bak «+», «gratuler» med ett trykk |
| 18 | Live | D | M | «Pågår nå» på Hjem (egen runde), Live Activity (oppdatert lokalt), widgets | Stripe for hele kvelden (hvem er ute, hull, stilling) med vei til tavle, kort og tråd; Live Activity også for en fører som ikke spiller |
| 19 | Varsler | D | D | 12 kategorier og trådvalg (`push_preferences`, 010), APNs fra `push-send`, collapse bare for leder og tabell | Fire grupper med alvorlighet, demping per kveld, collapse-id per kveld og kategori, én «kvelden er i gang», logg per mottaker |
| 20 | Bilder og oppsummering | D | D | Bilder i tråden (privat bøtte, JPEG på telefonen, signerte URL-er; sti `<member_id>/…`), delebilde uten bilde, sesongoppsummering, statistikk | Bildeoppfordring etter runden, galleri per kveld, delebilde med bilde og 9:16, fleipepriser med av-bryter, sti `<club_id>/…` med miniatyr |
| 21 | Kalender og datoer | M | D | Én kveld til kalenderen (EventKit). Kvelder kan bare slettes | ICS per medlem (påmeldte kvelder), «avlys» med begrunnelse, «ny dato, kan du fortsatt?», datoavstemning |
| 22 | Betaling for appen | D | M | Kjøp bygget (sql/023, `PurchaseService`, `verify-purchase`), `PurchaseFeature` av | Ikke nå (M10). Sjekk at låsen aldri stopper påmelding, purring, gjester eller føring |

## Datamodell (forslag)

Alt er additivt, med standardverdier som gir dagens oppførsel, slik 031–043 er gjort. Ingen data flyttes fra PWA-en før byttet (fase 9). Dagens testdata blir stående. Hver migrering får kontrollblokk, rullebakke, lokal prøve og paritetssjekk før den vises deg.

**Medlemskap og invitasjon (fase 28)**
- `clubs`: `owner_id` (fylles med eldste arrangør), `requires_approval bool default true`, `locked bool default false`.
- `club_invitations`: `id`, `club_id`, `token` (langt, tilfeldig), `short_code` (6 tegn, uten I, O, 0, 1), `expires_at`, `max_uses`, `use_count`, `revoked_at`, `created_by`. Ingen skrivepolicy. RPC-er: `club_invite_create`, `club_invite_revoke`, `club_invite_preview(kode)` (anon: klubbnavn, antall medlemmer, ledige navn), `club_invite_accept(kode, member_id?)` som øker telleren med `update … returning` i samme transaksjon. `clubs.join_code` fases ut.
- `transfer_club_ownership`, `leave_club(p_successor)`. Skrivepolicyene på `club_members` byttes med RPC-er.
- Hjelpere i `private` (`private.my_club_ids()`), `security definer`, `search_path = ''`, kalt som `(select …)` i policyer. Indekser på `club_id` der de mangler.
- RLS-tester per tabell (medlem ser, andre ser ikke, arrangør kan, medlem kan ikke) som SQL-prøver i `sql/lokal/`, kjørt mot lokal Postgres slik som `033_prove`.

**Format og runde (fase 29)**
- Motoren: `TeamForm` (individuell, par, lag; four-ball, foursome, greensome, scramble) og `Scoring` (slag, Stableford, match, poengspill, skins). Dagens `CompetitionForm`-id-er oversettes én til én. Golfgutu-fixturene skal gi samme svar.
- `round_games`: `format_version int`, `config jsonb`, `is_main bool`. Hovedformatet blir et spill med `is_main`. `rounds.format` står til gamle bygg er borte.
- `rounds.rules_snapshot jsonb` og `rounds.holes_snapshot` for alle baner (ikke bare hentede), frosset av en trigger ved start. Tildelte slag lagres ikke: de følger av frosset spillehandicap og frosne hull (CLAUDE.md: regn ut i stedet for å lagre).
- `hole_scores`: `client_id uuid` fra utboksen. «Ta over føringen»: `round_take_over_marker(round, bay)`.

**Sesong og gjenbruk (fase 30)**
- Regelsettet (ikke nye tabeller): `resultType`, `aggregation` (sum, snitt), `minEvenings`, navngitte `pointsTables`, `tieRule` for sesongtabellen, `handicapSet` (golfgutu, ngf, whs) og `rounding` (golfgutu, once). Golfgutu-malen beholder dagens verdier.
- `events`: `counts bool default true`, `points_table text null`.
- `event_series` (mal, frekvens, antall) og `events.series_id`. «Denne og fremtidige» skriver alle med senere dato i samme RPC.
- `club_games` (spillbiblioteket): `club_id`, `kind`, `config`, `include_by_default`. `event_games` for av/på per kveld.
- «Spilt sammen» regnes fra `round_players`/`round_matches`, ingen tabell.

**Påmelding og kalender (fase 31)**
- `events`: `default_answer` (`none`, `yes`), `signup_deadline`, `withdraw_deadline`, `max_players`, `waitlist_rule` (`auto`, `offer`, `organizer`), `allow_guests`, `cancelled_at`, `cancel_reason`.
- `signups`: `late bool`, `waitlisted_at`, `offered_at`, `offer_expires_at`, `seen_at`, `guest_name`, `invited_by`. `signup_log` (hvem endret hva, når).
- RPC `evening_signup(event, status, comment, substitute?)` med `select … for update` på kvelden. Skrivepolicyene fjernes. Cron for utløpte tilbud (som 032).
- `calendar_tokens` (per medlem) og Edge Function `calendar` (ICS). `cancel_event` og en trigger på `event_date` som nullstiller svar til «usikker» og varsler. `date_polls`, `date_poll_options`, `date_poll_votes`.

**Sosialt (fase 32)**
- `comments`: `id`, `club_id`, `target_kind` (`activity`, `message`, `comment`), `target_id`, `author_member_id`, `body`, `mentions`, `created_at`, `deleted_at`.
- `reactions`: `target_kind`, `target_id`, `member_id`, `emoji text check (char_length(emoji) between 1 and 16)`, unik per (mål, medlem, emoji). `activity_reactions` flyttes inn, med en view for gamle bygg.
- `thread_messages.deleted_at`, `club_posts` (innlegg på klubbnivå) eller `thread_messages.event_id null`. `thread_follows`.
- RPC `feed_page(p_club_ids, p_before_ts, p_before_id, p_limit)` med reaksjonstall, kommentartall og mine reaksjoner.
- Bilder: ny sti `<club_id>/<event_id>/<uuid>.jpg` og `…_thumb.jpg`, policy via medlemskap. Gamle stier leses som før.

**Varsler og live (fase 33)**
- `push_preferences`: fire grupper med nivå, `event_mutes(member, event)`. `notifications` (én rad per mottaker med status) erstatter `push_queue.result`.
- Broadcast-kanalen `event:<id>` i tillegg til `round:` og `club:` (040).

**App Store (fase 34)**
- `profiles.terms_version`, håndhevet i RPC-ene som skriver innhold. Tekstfilter i de samme RPC-ene. `content_reports` → varsel til appeier (e-post fra Edge Function). Myk sletting via `deleted_at`. Apple-token: lagre `refresh_token` fra Apple ved innlogging og kall `/auth/revoke` i `delete-account`.
- Demogruppe: seed-skript (`sql/lokal/demo.sql`) for test og prod, med kode til App Review.
- Med ja på spørsmål 2: `settlements` og `settlement_lines` (nullsum sjekket i RPC), betalt og bekreftet.

## Faseplan

Fasene følger oppdragets rekkefølge, nummerert videre fra ROADMAP. Hver oppgave er én PR. SQL vises deg før den kjøres.

### Fase 27 (oppdragets fase 0): tekniske prøver
- [ ] **Push fra Edge Function:** finnes allerede (`push-send` kaller APNs med HTTP/2 og token). Ferdig når: et varsel er levert til en telefon fra test, og funnet står i `docs/push-oppsett.md`.
- [ ] **Offline-køen med to telefoner:** drep appen midt i køen, spill av på nytt, to telefoner fører samme hull, med Broadcast på. Ferdig når: ingen hull tapt, siste skriving vinner, og `BroadcastFeature` kan slås på (eller funnene er rettet).

### Fase 28 (fase 1): grunnmur
- [ ] Eier, eieroverføring og «forlat klubben» med etterfølger. Ferdig når: RPC-ene er kjørt på test, siste arrangør kan ikke gå uten etterfølger, og appen har valget i Klubb.
- [ ] Invitasjoner: `club_invitations`, kort kode, utløp, tak, tilbaketrekking, «krev godkjenning», «lås», «ny kode». Ferdig når: en ny bruker kommer inn med koden alene, telleren går opp atomisk (prøvd med samtidige kall lokalt), og en trukket kode avvises.
- [ ] Invitasjonssiden på dashdash18.com med klubbnavn, App Store-knapp og kode. Ferdig når: siden viser navnet uten innlogging og ingen persondata.
- [ ] Skrivepolicyene på `club_members` byttes med RPC-er, hjelpere i `private`. Ferdig når: lasttesten fra fase 24 viser samme eller bedre tider, og alle app-flyter virker.
- [ ] RLS-tester for alle tabeller med klubb. Ferdig når: `sql/lokal/rls_prove.sql` går grønt for alle fire tilfellene per tabell.

### Fase 29 (fase 2): formatmotor og runde
- [ ] Lagform og poengtelling som to akser i motoren, tester først. Ferdig når: alle paritetstester og fixturer er uendret, og hver gammel form-id oversettes.
- [ ] Handicapsett NGF og WHS, én avrunding, 9 hull etter indeks, som regelvalg. Ferdig når: testene har tall fra NGFs dokument og R&As tabell, og Golfgutu er uendret.
- [ ] Flere spill per runde som likeverdige (`round_games.is_main`, `config`, `format_version`). Ferdig når: en runde kan ha Stableford individuelt, bestball i par og skins på samme hullscore, og tavla viser alle.
- [ ] Øyeblikksbilde av regelsett og hull ved start. Ferdig når: endring av regelsett eller bane etter start ikke flytter en ferdig runde (test).
- [ ] Rundestatus med «uoffisielt» til kvelden avsluttes, delt plass og pågående Stableford mot par. Ferdig når: tavla viser «uoffisielt», likhet brytes først ved avslutning.
- [ ] Oppskrifter med «Avansert», amerikaner og københavner etter sjekk mot NGF, flere LD/KP-hull. Ferdig når: en kveld settes opp uten å åpne «Avansert».
- [ ] Føring: «ført av / når», skrivebeskyttet kort og «ta over». Ferdig når: prøvd med to telefoner.

### Fase 30 (fase 3): sesong og gjenbruk
- [ ] Regelsettet: resultattype, snitt, minste antall kvelder, poengtabeller, «teller ikke», likhetsregel. Ferdig når: testene dekker hvert felt og Golfgutu er uendret.
- [ ] Tabellen: avstand til leder, poeng denne kvelden, strøkne kvelder, eclectic. Ferdig når: Tavla og TV viser det.
- [ ] Sesongbygger og «bare denne / denne og fremtidige». Ferdig når: en sesong på 7 kvelder lages i ett ark.
- [ ] Spillbibliotek, «samme som sist, ny trekning», «ny sesong fra forrige». Ferdig når: en vanlig kveld startes uten oppsettsskjermer.
- [ ] Trekning som unngår gjentakelser, «spilt sammen», balanserte lag, «bytt to», status per runde. Ferdig når: testene viser færre gjentakelser enn i dag over en sesong.

### Fase 31 (fase 4): påmelding, påminnelser og kalender
- [ ] Kveldspåmelding med standardsvar, frister, tak og venteliste i én låsende RPC. Ferdig når: samtidige påmeldinger lokalt aldri gir flere enn taket, og skrivepolicyene er borte.
- [ ] Sen avmelding, logg, vikar, gjest, «ikke sett». Ferdig når: arrangøren varsles når noen går fra ja til nei.
- [ ] Påminnelser styrt av svar og frist, purring med navnevalg, e-post bare uten push. Ferdig når: en spiller får høyst én melding per påminnelse.
- [ ] ICS per medlem, «avlys», «ny dato, kan du fortsatt?», datoavstemning. Ferdig når: kalenderen på telefonen viser bare påmeldte kvelder.

### Fase 32 (fase 5): sosialt lag med moderering
- [ ] `comments`, reaksjoner på alt, fri emoji bak «+», «gratuler». Ferdig når: alt i feeden kan kommenteres og reageres på, og blokkerte ikke vises.
- [ ] Felles feed med `feed_page` (keyset). Ferdig når: rulling henter neste side uten hull eller dobbeltrader (test).
- [ ] Nye hendelser: kvelden startet, birdie, runde ferdig, resultatkort. Ferdig når: kvelden gir ett resultatkort.
- [ ] Bilder: oppfordring etter runden, galleri, ny sti med miniatyr, delebilde med bilde og 9:16. Ferdig når: et bilde fra tråden står i galleriet og på delebildet.
- [ ] Moderering: rapport på alt, myk sletting, tekstfilter. Ferdig når: arrangøren fjerner et innlegg med ett trykk.
- [ ] Fleipepriser med av-bryter. Ferdig når: sesongoppsummeringen viser dem.

### Fase 33 (fase 6): varsler og live
- [ ] Fire varselgrupper, demping per kveld, collapse-id per kveld og kategori, logg per mottaker. Ferdig når: en kveld gir ett «kvelden er i gang».
- [ ] Live-stripe for hele kvelden, Live Activity for fører som ikke spiller. Ferdig når: prøvd på en kveld.

### Fase 34 (fase 7): App Store-pakken
- [ ] Vilkår godtatt uttrykkelig og håndhevet. Ferdig når: et innlegg avvises i serveren uten godtatte vilkår.
- [ ] Varsel til deg ved rapport, kø med frist. Ferdig når: en rapport på test gir e-post til kontaktadressen.
- [ ] Kontosletting med Apple-token. Ferdig når: sletting trekker tilbake tokenet (sjekket hos Apple).
- [ ] Demogruppe. Ferdig når: en ny konto kommer inn med koden og ser en sesong med data.
- [ ] Penger som regnskap, hvis du sier ja. Ferdig når: oppgjøret går i null og har betalt/bekreftet.

## Spørsmål til deg

Strøket der ROADMAP allerede svarer.

1. ~~Egen database eller felles med PWA-en?~~ **Besvart (B4):** egen. Men hvilket prosjekt? Appen bruker «Dash18 Test». Skal «Native Golfgutu» bli prod, eller lager vi «Dash18 Prod»? (M1)
2. **Penger og spill.** B10 sier poeng, ingen kroner, men «Del regningen» med Vipps er på. Velg for første App Store-versjon:
   a) veddemål og tippekupong med poeng som i dag (anbefalt), bank ute, «Del regningen» uten status;
   b) det samme pluss regnskap med betalt/bekreftet (endrer B10);
   c) alt bak et flagg som er av, med en egen TestFlight for gjengen.
3. **Roller.** Forslag: eier (ny), arrangør, medlem som roller; kasserer og sosialkomité som i dag; dommere blir «kan avgjøre veddemål» på arrangør. Holder det?
4. **Påmelding per kveld:** standardsvar for faste spillere (ubesvart eller påmeldt)? Frister (forslag: påmelding 24 t før, avmelding 4 t før)? Tak (antall båser × 4)? Ventelisteregel (forslag: tilbud til neste, 2 timer)?
5. **Sesong:** likhet i sesongtabellen (forslag: delt plass, så flest seire, så beste kveld)? Minste antall kvelder for å kvalifisere? Skal finaler kunne telle dobbelt? (N av M og poengtabell velges per turnering, så de trenger ikke svar.)
6. **Handicap:** NGF-settet som standard for nye turneringer, Golfgutu beholder sitt (M8)? Handicapkilde per sesong: offisielt med «bekreft før kvelden», eller seedet gruppehandicap?
7. ~~Utendørsbaner med flere teer?~~ **Besvart (fase 20):** slope.no gir teer med CR, slope og hull.
8. ~~Minste iOS-versjon?~~ **Besvart (B7):** iOS 26. **Aldersgrense:** oppdraget foreslår 18+ hvis innsats følges. Med poeng uten innsats er det trolig lavere, men det avgjøres i spørreskjemaet i App Store Connect. Hva vil du?
9. **App Store som mål (M6):** oppdatere B1?
10. **Blind og ghost** ved oddetall i lagformater: ta inn, eller bare trekant som i dag?
11. **Navn:** behold «klubb» i kode og skjema (M2)? Brukerne ser «klubb» i dag.
