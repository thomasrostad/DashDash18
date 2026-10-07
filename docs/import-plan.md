# Importplan: PWA → DashDash18 (fase 9)

Status 07.10.2026: forarbeid. Eksport-SQL, importverktøy og paritetssjekk er laget og testet med syntetiske data og mot en lokal Postgres med appens skjema. Ingenting er kjørt mot appens database, og PWA-basen er bare lest.

## 1. Uttaksmetode

**Valgt:** du kjører den rene SELECT-en `sql/import/export_pwa.sql` i PWA-prosjektets SQL Editor og lagrer svaret som `import-snapshot/<dato>/snapshot.json` i repoet. Mappa står i `.gitignore`.

Hvorfor:
- Persondata (navn, meldinger) går rett fra Supabase til disken din. De går ikke gjennom Claude-samtalen eller via MCP. Slik er det ingen fare for at de havner i logger eller i git.
- Ingen nøkler eller passord trengs. SQL Editor bruker innloggingen din, og verktøyet gjør ingen nettverkskall.
- Det er én spørring og én fil. Samme fil kan brukes om igjen til prøveimport, paritetssjekk og byttedag.

**Alternativ:** lesing via MCP (`execute_sql`). Den er brukt til kartleggingen (skjema og radtall), men ikke til selve uttaket, fordi da ville navn og innhold gått gjennom samtalen.

Verktøyet godtar svaret i formen SQL Editor gir: en liste med én rad (`[{"snapshot": …}]`), selve objektet, eller `snapshot` som tekst.

## 2. PWA-basen (lest 07.10.2026, bare tall)

| Tabell | Rader | Tas med |
|---|---|---|
| players | 13 | ja → `club_members` |
| courses / course_holes | 18 / 324 | ja → `courses` / `course_holes` |
| schedule | 7 | ja → `events` (+ `event_committee`) |
| signups | 12 | ja → `signups` |
| rounds | 2 | ja → `rounds` |
| round_holes | 18 | ja → `round_holes` |
| round_bays / round_teams | 20 / 20 | ja → `round_players` |
| round_matches | 5 | ja → `round_matches` |
| hole_scores | 180 | ja → `hole_scores` |
| side_claims | 0 | ja → `side_claims` |
| tips | 0 | ja → `tips` |
| meldinger | 2 | ja (teksten) → `thread_messages` |
| settings | 1 | delvis: navn, år, ferdig og kasserer |
| round_points | 20 | nei, brukes bare i paritetssjekken |
| activity_log / activity_reaksjoner | 93 / 3 | nei (se under) |
| markets / market_stakes | 1 / 1 | nei (B10) |
| fines, poster, bank_bevegelser, utlegg, tips_betalinger | 1, 1, 2, 0, 0 | nei (B10, kroner) |
| push_subscriptions, allowed_emails | 11, 1 | nei (web-push og e-post, persondata) |

Skjemaet i `referanse/golfgutu-pwa/sql/` stemmer med basen. To ting er verdt å merke seg:
- `rounds` har ingen `schedule_id`. En runde kobles til kvelden via datoen, slik `db-nytt.js` gjør.
- Begge rundene er fourball på 9 hull med ekstern handicap: første ni og siste ni samme kveld, med lagmatcher og skjeve lag (1–3 spillere per lag).

## 3. Mapping

Id-ene er stabile: UUIDv5 av `"<type>:<PWA-id>"` i et fast navnerom (`StableID.namespace`). Samme PWA-rad får alltid samme UUID i appen.

| PWA | App | Merknad |
|---|---|---|
| settings.name | clubs.name | Ny klubb med stabil id. Finnes klubben, røres den ikke. `--club-id` velger en klubb som finnes fra før |
| settings.name + year, finished | seasons (name, status `active`/`finished`) | `rules` = `Ruleset.golfgutu` (JSON). Overskrives ikke ved ny import |
| players.name | club_members.display_name | Trimmes, høyst 40 tegn. Like navn (store/små bokstaver) stopper importen |
| players.handicap, seed_group | handicap_index, seed_group | Utenfor −10…54 og 1…9 blir tomt, med merknad |
| players.commissioner | is_organizer | |
| settings.treasurer_id | is_treasurer | |
| players.user_id, phone, prat_push, bilde | – | Ikke med. `user_id` er tom, så navnet er ledig |
| courses.trackman_name, i_bruk, bekreftet_av/at | external_name, in_use, confirmed_by/at | `course_holes` vinner, ellers `courses.holes` (som `banehullFraRader`) |
| course_holes.hcp_index, distance_meters | stroke_index, length_m | Lengde utenfor 50–700 blir tom |
| schedule.date, time | events.event_date, start_time | Første klokkeslett i «18:00–22:00» |
| schedule.social_1/2 | event_committee | |
| schedule.tips_linje | events.tips_line | Bare x,5. `tips_innsats` er kroner og tas ikke med (B10) |
| signups.status `kommer`/`usikker`/`kommer_ikke` | `yes`/`maybe`/`no` | Ukjent status leses som `yes`, som i PWA-en |
| rounds.date | rounds.event_id | Mangler datoen i terminlista, lages kvelden. `round_no` følger `created_at` |
| locked / kladd | status `locked` / `draft` / `active` | Mer enn én pågående runde stopper importen |
| hole_count, hole_start 0/9 | hole_count, first_hole 1/10 | 10 bare når runden har 9 hull |
| game_type | format | Små bokstaver («Stableford» → `stableford`) |
| hcp_allowance, hcp_extern, multiplier | handicap_allowance, external_handicap, weight | |
| longest_drive_hole_index, kp_hole_index, ld_aktiv, kp_aktiv | ld_*, kp_* | Hull utenfor runden blir tomt |
| avkort_regel `felles`/`nettopar`/`'null'`, avkortet_* | cut_rule `common`/`net_par`/`zero`, cut_* | |
| par_bekreftet_av/at | par_confirmed_by/at | |
| created_at, siste score | started_at, locked_at | Ellers ville triggeren satt `now()` |
| round_bays + round_teams (+ scorer og matcher) | round_players (bay_no, is_marker, team_no) | Én markør per bås. Handicapet fryses med PWA-ens tall i dag (B16) |
| round_matches result `A`/`B`/annet | `a`/`b`/`halved` | En trekant får ikke manuelt resultat |
| hole_scores.updated_at | hole_scores.recorded_at | `updated_by` settes av triggeren (null fra SQL Editor) |
| side_claims | side_claims | Bare med runde. Én per spiller, runde og type |
| tips.vinner/forste_ni/flest_par/birdie/over_linja | winner/front_nine/most_pars/birdie/over_line | |
| meldinger.tekst, nevnt | thread_messages.body, mentions | Bilder flyttes ikke. `pushed_at` settes, så gamle meldinger ikke sendes som push |

**Ikke med:** penger og veddemål i kroner (B10: `markets`, `market_stakes`, `fines`, `poster`, `bank_bevegelser`, `utlegg`, `tips_betalinger` og `schedule.utlegg*`), web-push-abonnementer, e-postlista, telefonnumre, bilder (portretter, baner, tråd) og `activity_log` med reaksjoner. Hendelsesloggen i appen bygges fra appens egne handlinger, og innsetting der ville utløst push-køen. `round_points` lagres ikke. Appen regner poengene selv, og tallene brukes bare i paritetssjekken.

## 4. Spillere og innlogging

Importerte medlemmer får `status = 'active'` og `user_id = null`. De er da **ledige navn**, slik fase 1 er laget:
1. Spilleren logger inn i appen (Apple, Google eller e-postkode) og skriver inn invitasjonskoden.
2. `club_preview(kode)` viser de ledige navnene. Spilleren velger sitt, og `join_club(kode, medlem_id)` setter `user_id` med en gang (aktiv, uten godkjenning).
3. En ny import rører aldri `user_id`, status eller invitasjonskoden. Navn, handicap, seeding og roller oppdateres fra PWA-en.

Prøvd lokalt: å ta et ledig navn etter import fungerte. Arrangørflagget fulgte med, og `user_id` sto igjen etter en ny import.

Invitasjonskoden hentes etter importen med kontrollspørringen nederst i den genererte SQL-fila.

## 5. Idempotens

- Alle innsettinger bruker `insert … on conflict … do update` (eller `do nothing` for klubb, komité og tråd), og alt kjører i én transaksjon (`begin … commit`). Feiler noe, rulles alt tilbake.
- Samme `snapshot.json` gir byte for byte samme SQL. Fila har ingen kjøretid, bare sjekksummen av kilden.
- **Speiling under importerte runder og kvelder.** Scorer, deltakere, matcher, rundehull, sidepremier, påmeldinger, komité og banehull som ikke lenger finnes i PWA-en, slettes. PWA-en er fasit fram til byttet.
- En **runde eller spiller som er slettet i PWA-en** etter forrige import, blir stående i appen. Slett den for hånd, eller start på nytt på test.
- Vern: SQL-en stopper hvis den kjøres mot PWA-basen (`public.players` finnes) eller mot en base uten appens skjema.

Prøvd mot lokal Postgres 16 med `sql/lokal/stub*.sql` og 001–011: kjørt to ganger uten feil og uten nye rader, og push-køen forble tom. Etter en endret import (score fjernet, markør flyttet, handicap endret) ble endringene speilet. Etter den opprinnelige importen igjen var alt tilbake.

## 6. Rekkefølge

1. clubs → club_members → seasons
2. courses → course_holes (rydd, så upsert)
3. events → event_committee → signups (rydd, så upsert)
4. rounds
5. Rydd under rundene: side_claims, hole_scores, round_matches, round_players, round_holes. Nullstill markørene.
6. round_players → round_holes → round_matches → hole_scores → side_claims
7. tips → thread_messages

## 7. Kommandoer

```
cd Packages/DashImport
swift run dashimport parity ../../import-snapshot/<dato>                          # Tavla fra importerte data + round_points
swift run dashimport ../../import-snapshot/<dato> ../../import-out/<dato>.sql     # skriver SQL, kjører ingenting
```

`parity` skriver ut jakketabellen og stablefordsummen slik appen regner dem med Golfgutu-oppsettet. Den sammenligner også hver spillers rundepoeng med PWA-ens lagrede `round_points` og avslutter med kode 1 hvis noe avviker. Jakketabellen lagres ikke i PWA-en, så den må sammenlignes med Tavla i PWA-en med øyet.

## 8. Prøveimport mot test (krever ditt ja)

1. Kjør `sql/import/export_pwa.sql` i SQL Editor for PWA-prosjektet «Golfgutu» og lagre svaret som `import-snapshot/<dato>/snapshot.json`.
2. Kjør `swift run dashimport parity …`. Sammenlign med Tavla i PWA-en, og sjekk at det står «0 avvik».
3. Kjør `swift run dashimport … import-out/<dato>.sql`. Les merknadene og fila.
4. **Godkjenn**, og kjør fila i SQL Editor på **Dash18 Test** (`tsekialrxuhrugscosgi`). Sjekk prosjekt-id-en øverst.
5. Kjør kontrollspørringen nederst i fila. Antallene skal stemme med kommentaren.
6. Logg inn i appen, bli med med invitasjonskoden, ta navnet ditt og se på Tavla.

## 9. Byttedag (sjekkliste)

- [ ] Penger og veddemål gjort opp i PWA-en (B10). Åpne poster og markeder står i tallene over.
- [ ] Siste PWA-kveld er ferdig, og alle runder er låst. Ingen kladd som skal med.
- [ ] Skjema 001–011 (+ senere) kjørt på **prod** etter godkjenning. Innlogging og APNs er satt opp.
- [ ] Ferskt øyeblikksbilde av PWA-ens prod. `parity` gir 0 avvik, og Tavla er sjekket med øyet.
- [ ] Import-SQL generert og godkjent. Den er kjørt på test først, så på prod.
- [ ] Kontrollspørringen gir forventede tall. Invitasjonskoden er hentet.
- [ ] TestFlight-invitasjon sendt. Alle har logget inn og tatt navnet sitt (sjekk `user_id is not null`).
- [ ] PWA-en er fryst («Vi har flyttet til appen»). Det er en endring i PWA-ens kode, ikke i basen, og krever ditt ja.
- [ ] Snapshot- og SQL-filene er slettet lokalt når byttet er bekreftet.

## 10. Åpne spørsmål

1. **Klubben:** skal importen lage en ny klubb (standard, stabil id), eller gå inn i en klubb du allerede har på test (`--club-id`)? En eksisterende klubb kan ha en aktiv sesong, en kveld på samme dato eller et navn som kolliderer. Da stopper importen med 23505.
2. **Arrangører:** PWA-en har 3 arrangører. De importeres med arrangørflagget, og den som tar navnet blir arrangør med en gang. Er det greit, eller skal flagget settes for hånd etterpå?
3. **Sesongen:** terminlista går fra oktober 2026 til april 2027, og `settings.year` er 2026. Alt legges i én sesong, «Golfgutu Invitational 2026». Er navnet riktig?
4. **Tippeinnsats:** PWA-ens `tips_innsats` er kroner (50). Den tas ikke med, så kvelden bruker regelsettets standard i poeng. Skal 50 kroner bli 50 poeng?
5. **Hendelsesloggen** (93 linjer) og reaksjonene: er det greit at de ikke tas med?
6. **Bilder i tråden:** én melding har bilde. Bildet flyttes ikke (det ligger i PWA-ens Storage). Holder teksten?
7. **Andre klubb på samme konto:** appen kan ha flere medlemskap. Kan du bli med i den importerte klubben fra appen når du allerede er med i en testklubb? Det må prøves i appen.
8. **Android-brukere** (B13) har ingen app etter byttet. Spør gjengen før datoen settes.
