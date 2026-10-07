# sql/: migreringer for appens egen Supabase

Dette er skjemaet for appens **nye, egne** database. PWA-ens database røres ikke. Den brukes bare som kilde for import i fase 9.

> **Status 06.10.2026:** `001_skjema_v1.sql` er **godkjent av brukeren og kjørt på test** (`tsekialrxuhrugscosgi`). Kontrollspørringene ga 10 av 10 ok, og uinnloggede forespørsler mot tabeller og RPC-er får 42501. Åpne spørsmål er besvart etter anbefalingene: markørens par-bekreftelse kommer som egen RPC i neste migrering, og `playing_handicap` lagres ved start. Ikke kjørt på prod.

## Prosess (ROADMAP B5)

1. **Fil:** hver endring er en nummerert fil her (`001_…`, `002_…`). Én fil er én transaksjon.
2. **Godkjenning:** du leser fila (eller oversikten under) og sier ja. Uten ja kjøres ingenting.
3. **Test:** fila kjøres på **test**-prosjektet (`tsekialrxuhrugscosgi`). Kontrollspørringene nederst i fila kjøres etterpå.
4. **Appen mot test:** innlogging og rolleprøver med to kontoer.
5. **Prod:** først etter ny godkjenning.
6. **Anon-fella:** hver ny funksjon får `revoke … from public, anon` **etter** `create or replace`. Kontrollspørring 4 viser `anon_kan` per funksjon, og alle skal være `false`.

## Rekkefølge

| Fil | Innhold | Status |
|---|---|---|
| `001_skjema_v1.sql` | Kjernen for fase 1–5 | Godkjent, kjørt på test 06.10.2026. Ikke prod |
| `002_baner.sql` | `save_course`, `confirm_course` | Godkjent, kjørt på test 06.10.2026. Ikke prod |
| `004_sesong.sql` | `activate_season`, sletting bare av planlagte sesonger | Godkjent, kjørt på test 06.10.2026. Ikke prod |
| `005_kveld.sql` | `set_event_committee` | Godkjent, kjørt på test 06.10.2026. Ikke prod |
| `006_runder.sql` | `start_round` (oppsett og start i én transaksjon) | Godkjent, kjørt på test 06.10.2026. Ikke prod |
| `007_foring.sql` | `confirm_round_par` (markør eller arrangør bekrefter par) | Godkjent, kjørt på test 06.10.2026. Ikke prod |
| `008_sosialt.sql` | Aktivitet, reaksjoner, kveldens tråd, tippekupong, push-tokens (APNs), bøttene `avatars` og `thread` | Godkjent og kjørt på test 06.10.2026. Ikke prod |
| `009_ledelse_en_gang.sql` | Unik indeks: ledelsesvarsel bare én gang per runde og sjekkpunkt | Forslag, ikke kjørt. Tatt med i 011 |
| `010_push.sql` | Push (fase 8): `push_devices` (erstatter `push_tokens`), `push_preferences`, `clubs.push_disabled_categories`, `push_queue` med triggere, RPC-er for appen og senderen | Godkjent og kjørt på test 07.10.2026 (`010_kontroll.sql`: 12 av 12 ok). Ikke prod |
| `010_kontroll.sql` | Samlet kontroll for 010, én rad per sjekk | Hjelpefil |
| `011_varsler_en_gang.sql` | Unike indekser: stor score (runde, spiller, hull), ledelsen (runde, sjekkpunkt, fra 009) og «ny runde» (runde) bare én gang, så to telefoner ikke gir dobbel push | Godkjent og kjørt på test 07.10.2026 (tre indekser på plass). Erstatter 009. Ikke prod |
| `012_veddemaal.sql` | Veddemål med poeng (fase 10): `bets`, `bet_stakes`, sperra `bet_accepts_stakes`, poengbanken regnet av `bet_points` (ikke lagret), RPC-ene `create_bet`, `place_bet_stake`, `resolve_bet`, `mark_bets_closed` | **Godkjent og kjørt på test 07.10.2026** (kontrollen 12 av 12 ok). Ikke prod. Lokalt: kjørt to ganger, `lokal/012_prove.sql` 60 av 60 ok, kontrollen 10 av 10, rullebakken prøvd |
| `015_runde_sted.sql` | `rounds.venue` (simulator/course), bås ↔ flight | Godkjent og kjørt på test 07.10.2026. Ikke prod |
| `016_banetype.sql` | `courses.kind` (simulator/course) | Godkjent og kjørt på test 07.10.2026. Ikke prod |
| `014_par_uten_markor.sql` | `confirm_round_par` som PWA-ens `kanBekrefteBaneoppsett`: uten båser, eller i en bås uten markør, kan alle som spiller bekrefte parene | Godkjent og kjørt på test 07.10.2026. Ikke prod |
| `017_fundament.sql` | Fase 12, fundamentet for en åpen app: `profiles`, løse runder (`rounds.club_id`/`event_id` kan være tomme, med CHECK), deltakere som profil eller gjest (`round_participants`), `competitions`, `competition_participants`, `competition_rounds`, `entitlements`, felles banebibliotek med felt for ekstern kilde, utvidet RLS, RPC-ene `ensure_profile`, `create_loose_round` og `create_competition`, og en konkurranse per sesong med rundene koblet. Se `docs/datamodell-v2.md` | Godkjent og kjørt på test 07.10.2026 (kontrollen 14 av 14). Ikke prod |
| `lokal/017_for.sql`, `lokal/017_prove.sql` | Lokal rolleprøve for 017: «verden før» (kjøres før 017, tar et bilde av hva hver innlogging ser og kan), så prøven etter. **Aldri mot Supabase.** | Hjelpefiler |
| `021_statistikk.sql` | Fase 16: `hole_stats`, valgfri føring per hull (fairway på par 4/5, green i regulering, putter, bunker, straffeslag) med samme nøkkel som `hole_scores`. Lese som `hole_scores`. Skrive: den som kan føre (`can_score`), pluss spilleren selv mens runden pågår (`can_write_hole_stats`). Vakt for hull i runden og fairway bare på par 4/5. Snitt og prosenter regnes i appen | Godkjent og kjørt på test 07.10.2026. Ikke prod |
| `lokal/021_prove.sql` | Lokal rolleprøve for 021 (kjøres etter `lokal/017_prove.sql` og 021). **Aldri mot Supabase.** | Hjelpefil |
| `lokal/012_prove.sql` | Lokal rolleprøve for 012. **Aldri mot Supabase.** | Hjelpefil |
| `import/export_pwa.sql` | Fase 9: ren SELECT som lager et øyeblikksbilde (JSON) av **PWA-basen**. Kjøres i PWA-ens SQL Editor, og svaret lagres i `import-snapshot/` (ikke i git). Se `docs/import-plan.md` | Bare lesing. Ingen godkjenning trengs for å kjøre den, men den gir persondata |
| `lokal/010_prove.sql` | Lokal rolleprøve for 010. **Aldri mot Supabase.** | Hjelpefil |
| `lokal/stub.sql`, `lokal/001_prove.sql` | Lokal syntaks- og rolleprøve. **Aldri mot Supabase.** | Hjelpefiler |
| `lokal/stub_storage.sql`, `lokal/008_prove.sql` | Lokal Storage-etterligning og rolleprøve for 008. **Aldri mot Supabase.** | Hjelpefiler |

Kommer senere, som egne filer: banebilder.

## Slik kjøres en migrering i SQL Editor

1. Åpne **test**-prosjektet i Supabase og velg SQL Editor. Sjekk prosjekt-id-en øverst.
2. Lim inn hele fila og trykk Run. Fila har sin egen `begin; … commit;`. Feiler noe, rulles alt tilbake.
3. Kjør kontrollblokkene nederst i fila én om gangen. Fjern `-- ` foran linjene. Forventet svar står ved hver blokk.
4. Kjør Security Advisor i Supabase. Den skal ikke melde `anon` på noen funksjon. Den vil fortsatt melde «Signed-In Users Can Execute SECURITY DEFINER Function». Det er med vilje: policyene kaller hjelpefunksjonene som den innloggede brukeren.
5. Rullebakke (bare på test, sletter data) står som kommentar nederst i fila.

## Lokal sjekk (gjort for dette utkastet)

Uten tilgang til Supabase er fila kjørt mot en midlertidig, lokal **Postgres 16.2** i scratch-mappa. Den kommer fra pip-pakken `pgserver` i et virtuelt miljø, uten global installasjon. Supabase-delene er etterlignet i `lokal/stub.sql`: rollene `anon`, `authenticated` og `service_role`, `auth.users`, `auth.uid()`, standardrettighetene og publikasjonen `supabase_realtime`.

- Migreringen kjørte **to ganger på rad** uten feil. Den andre kjøringen ga bare «finnes allerede»-meldinger, altså er den idempotent.
- `lokal/001_prove.sql` ga **63 av 63 ok**. Den dekker anon, ikke-medlem, ventende medlem, spiller, markør og arrangør, kolonnevaktene, kanFore, alle RPC-ene, idempotens, gammel innsending fra utboksen, unik markør per bås, utsatt indeks-unikhet og én pågående runde.
- Kontrollspørringene og rullebakken er kjørt og ga forventet svar.
- **Forbehold:** Supabase kjører Postgres 17, og lokalt ble det kjørt på 16. Fila bruker ingen syntaks som er ny i 17. Ekte Supabase (Realtime, PostgREST og advisoren) er ikke prøvd.

Slik kjøres sjekken på nytt: start en tom Postgres og kjør `lokal/stub.sql`, så `001_skjema_v1.sql` (gjerne to ganger), så `lokal/001_prove.sql` med `psql -v ON_ERROR_STOP=1`.

---

## Oversikt for godkjenning

### Tabellene

| Tabell | Hva den er |
|---|---|
| `clubs` | En klubb eller gjeng med navn og invitasjonskode. Alt annet henger på en klubb. |
| `club_members` | Troppen. Én rad per spiller i klubben, med navn, handicapindeks, seedet gruppe, rollene arrangør/kasserer og status. Er `user_id` tom, er raden et ledig navn. |
| `seasons` | En sesong med regelsettet som jsonb. Høyst én aktiv sesong per klubb. |
| `events` | En kveld i terminlista med dato, klokkeslett, sted og notat. Én kveld per dato per klubb. |
| `event_committee` | Sosialkomiteen for en kveld, uten fast antall. |
| `signups` | Påmelding per kveld og spiller: `yes`/`maybe`/`no` og kommentar på høyst 80 tegn. Ingen rad betyr ikke svart. |
| `courses` | Banebiblioteket per klubb med CR, slope, navn i simulatoren og hvem/når den ble bekreftet. Par regnes fra hullene. |
| `course_holes` | Hullene på en bane: par 3–6, indeks 1–18 (unik per bane, sjekket ved commit), lengde. |
| `rounds` | En runde på en kveld: status (kladd/pågår/låst), 9/18 hull, første hull, form, handicapandel, ekstern handicap, vekt, LD/KP av/på og hull, avkorting, par-bekreftelse. |
| `round_holes` | Overstyring av par, indeks og lengde for én runde. |
| `round_players` | Deltakerne i runden med frosset handicap, bås, markør (én per bås) og lag. Erstatter PWA-ens `round_bays` og `round_teams`. |
| `round_matches` | Matcher mellom spillere eller lag, trekant med tredje spiller, og manuelt resultat. |
| `hole_scores` | Brutto slag per runde, spiller og hull, med `updated_by` og `updated_at` satt av serveren. **Ingen poengtabell.** Poeng regnes i appen. |
| `side_claims` | Longest drive og nærmest pinnen. Lengden er over 0 og høyst 500 m, og hver spiller har én per runde og type. |

### Hvem kan hva (RLS i klartekst)

- **Uinnlogget (anon):** ingenting. Alle tabeller og funksjoner gir «permission denied». Appen må logge inn før første henting (jf. 23505-feilen i PWA-en 17.09).
- **Innlogget, men ikke medlem:** ser ingen data. Kan bare lage en ny klubb (`create_club`), se klubbnavn og *ledige* navn bak en invitasjonskode (`club_preview`) og melde seg inn (`join_club`).
- **Ventende medlem:** ser klubbnavnet og sin egen rad, ellers ingenting, til arrangøren godkjenner.
- **Spiller (aktivt medlem):**
  - leser alt i egen klubb, unntatt kladdrunder og det som hører til dem;
  - endrer egen rad (navn, handicapindeks, bilde), men **ikke** rolle, seedet gruppe, status eller kobling til innlogging (kolonnevakt);
  - melder seg selv på og av;
  - melder inn egne sidepremier mens runden pågår;
  - **fører score** etter kanFore, se under.
- **Arrangør:** skriver alt i egen klubb: tropp, roller, sesong, kveld, baner, runder og oppsett. Godkjenner nye og kobler fra feil innlogging. Fører alltid, også i låst runde. Klubben kan ikke miste sin siste arrangør.
- **Kasserer:** bare et flagg i v1. Rettighetene kommer med poeng og penger senere.
- **Score (kanFore)**, samme regel som PWA-en:
  1. Arrangøren kan alltid føre.
  2. Er runden ikke i gang (kladd eller låst), kan ingen andre føre.
  3. Har spillerens bås en markør, kan bare markøren føre (også for seg selv).
  4. Ellers fører spilleren selv.
- **Runder slettes** bare av arrangør og aldri når de er låst. Alt under runden følger med (cascade). En spiller som har scorer, kan ikke tas ut av runden.
- Klubbene er skilt med sammensatte fremmednøkler. En spiller, bane eller kveld fra én klubb kan ikke havne i en annen klubbs runde, heller ikke via SQL Editor.

### RPC-er (én transaksjon hver)

| Funksjon | Hvem | Hva |
|---|---|---|
| `create_club(navn, visningsnavn, hcp)` | innlogget | Ny klubb med deg som første arrangør |
| `club_preview(kode)` | innlogget | Klubbnavn og ledige navn bak koden |
| `join_club(kode, medlem_id \| navn, hcp)` | innlogget | Tar et ledig navn (aktiv med én gang) eller lager en ny rad som venter på godkjenning. Idempotent. |
| `save_hole(runde, hull, [{member_id, strokes}], tastet_tid)` | etter kanFore | Lagrer et hull for hele båsen. Alt eller ingenting, og idempotent. En gammel innsending fra utboksen overskriver ikke en nyere retting. Returnerer serverens rader. |
| `set_round_setup(runde, spillere, matcher)` | arrangør, ikke låst | Deltakere, båser, markører, lag og matcher i ett kall. Erstatter slett-så-sett-inn. |
| `delete_round(runde)` | arrangør, ikke låst | Sletter runden og alt under, og returnerer hva som forsvant |

Feilkoder appen må skille: `42501` (ikke lov), `P0002` (finnes ikke), `22023` (ugyldig input), `55000` (feil tilstand, f.eks. låst), `23505` (unik-brudd, f.eks. «en runde går allerede» eller «navnet er tatt»), `23503` (fremmednøkkel), `23514` (check). **Sjekk SQLSTATE før du konkluderer med at RLS stoppet deg.**

### Valg jeg har tatt, og alternativene

1. **Engelske tabell- og kolonnenavn, norske kommentarer.** Dette følger CLAUDE.md («kodeidentifikatorer på engelsk»), supabase-swift mapper snake_case rett til Swift, og vi slipper æøå i identifikatorer. *Alternativ:* norske navn som i PWA-en. Det gir lettere import, men blander språk i Swift-koden. Ordliste står under.
2. **Regelsett som jsonb med `version`**, ikke typede kolonner. Regelsettet designes nå i fase 2 og 3, har lister og nøstede verdier (tillatte former, seeding-grupper, tiebreak-rekkefølge) og vil endre seg. Med jsonb krever ikke hver justering en migrering, og Swift dekoder det som en `Codable` med versjon. Databasen sjekker bare at det er et objekt, at `version` er et tall ≥ 1, og at det er under 64 kB. Ellers validerer regelmotoren. *Alternativ:* typede kolonner med CHECK. Det gir sterkere garantier i databasen, men koster en migrering per endring og passer dårlig til lister. Eksempel (ikke bindende, fase 2 bestemmer):
   ```json
   {"version": 1, "preset": "golfgutu", "maxPerBay": 4, "countedEvents": "all",
    "tableModel": {"kind": "duel", "win": 1, "halved": 0.5, "loss": 0},
    "sidePrizes": {"ld": {"enabled": true, "points": 1}, "kp": {"enabled": true, "points": 1}},
    "handicap": {"model": "whs", "seedGroups": {"1": 0, "2": 5, "3": 10}},
    "formats": ["stableford", "match", "fourball"], "tiebreak": ["holes", "stableford", "name"]}
   ```
3. **Flere klubber, men lett.** `club_id` ligger på de store tabellene, og helper-funksjonene tar klubb som parameter. Én innlogging kan være med i flere klubber. *Alternativ:* én klubb hardkodet. Det er enklere nå, men en tung migrering senere.
4. **Roller som flagg** (`is_organizer`, `is_treasurer`) på medlemsraden. *Alternativ:* en egen rolletabell. Den er mer fleksibel, men gir flere oppslag i hver policy.
5. **Bås, markør og lag er kolonner på `round_players`**, ikke egne tabeller. Hele oppsettet skrives atomisk, og score kan bare finnes for deltakere (fremmednøkkel). *Alternativ:* PWA-ens tre tabeller.
6. **Frosset handicap:** indeks og seedet gruppe kopieres fra troppen når runden **startes**. Senere endringer flytter dermed ikke poeng i gamle runder. Det gjorde de i PWA-en, som alltid regnet med dagens handicap. I tillegg finnes `playing_handicap` som appen *kan* lagre ved start, et bevisst lagret avledet tall (se åpne spørsmål).
7. **Ingen `round_points`.** Poeng regnes alltid fra `hole_scores` (CLAUDE.md, og 41 → 3-feilen i SPEC 4.9).
8. **`recorded_at` på score** (tidspunktet hullet ble tastet) gjør utboksen trygg: en gammel innsending overskriver ikke en nyere. Klokkeslett fram i tid klemmes til serverens tid. `updated_at` og `updated_by` settes alltid av serveren.
9. **RPC-ene er SECURITY DEFINER** og bruker de samme hjelpefunksjonene som policyene. Ingen har bakvei for `auth.uid() is null` (PWA-ens slett_runde-lærdom). *Alternativ:* SECURITY INVOKER, som lar RLS gjøre jobben. Det er like trygt og gir én sannhet færre, men feilmeldingene blir dårligere.
10. **anon har ingen tabellrettigheter.** PWA-en lot anon få tom liste. Native skal få en tydelig feil.
11. **Kladder er skjult** for andre enn arrangøren i databasen, ikke bare i UI-et.
12. **Høyst én pågående runde per klubb** (unik indeks). Indeksen er lett å fjerne hvis to samtidige runder blir ønsket.
13. **Banebiblioteket er per klubb.** Import av PWA-ens 18 baner kopieres inn i klubben.
14. **Strammere enn PWA-en:** bare arrangøren oppretter runder, kvelder og baner (PWA-en hadde åpen INSERT, SPEC 3.5), og ingen kan føre score i en kladd.

### Ordliste PWA → nytt skjema (for importen i fase 9)

| PWA | Nytt |
|---|---|
| `players` | `club_members` (`commissioner` → `is_organizer`, `settings.treasurer_id` → `is_treasurer`, `handicap` → `handicap_index`, `name` → `display_name`) |
| `schedule` (`date`, `time`, `social_1/2`) | `events` (`event_date`, `start_time`), `event_committee` |
| `signups.status` `kommer`/`usikker`/`kommer_ikke` | `yes`/`maybe`/`no`; `kommentar` → `comment` |
| `rounds.kladd` / `locked` | `status` `draft`/`active`/`locked` |
| `hole_start` 0/9 | `first_hole` 1/10 |
| `game_type`, `hcp_allowance`, `hcp_extern`, `multiplier` | `format`, `handicap_allowance`, `external_handicap`, `weight` |
| `longest_drive_hole_index`, `kp_hole_index`, `ld_aktiv`, `kp_aktiv` | `ld_hole_index`, `kp_hole_index`, `ld_enabled`, `kp_enabled` |
| `avkort_regel` `felles`/`nettopar`/`'null'`, `avkortet_etter/av/at` | `cut_rule` `common`/`net_par`/`zero`, `cut_after/by/at` |
| `par_bekreftet_av/at` | `par_confirmed_by/at` |
| `round_bays` (`bay_no`, `er_markor`), `round_teams` (`team_no`) | `round_players` (`bay_no`, `is_marker`, `team_no`) |
| `round_matches.result` `A`/`B`/`H` | `a`/`b`/`halved` |
| `hole_scores.player_id` | `member_id` |
| `round_points` | utgår (regnes) |
| `side_claims.type` | `kind` |
| `courses.par`, `holes` (jsonb) | regnes fra `course_holes` |
| `course_holes.hcp_index`, `distance_meters` | `stroke_index`, `length_m` |
| `courses.trackman_name`, `i_bruk`, `bekreftet_av/at`, `bilde` | `external_name`, `in_use`, `confirmed_by/at`, `image_path` |

Hull i runden er 0-baserte (`hole_index` 0–17), som i PWA-en. Banens hull er 1–18 (`hole_number`).

### Åpne spørsmål til deg

1. **Innmelding:** den som tar et ledig navn med invitasjonskoden, blir aktiv med én gang (arrangøren kan koble fra). Den som melder seg inn som ny, venter på godkjenning. Er det riktig, eller skal begge vente?
2. **Hvem kan lage en klubb?** Nå kan enhver innlogget det via `create_club`. Klubben er helt isolert. Alternativet er bare via SQL Editor.
3. **Markørens par-bekreftelse** (SPEC 3.5): i v1 kan bare arrangøren skrive `rounds`, `round_holes` og `course_holes`. Skal markøren kunne bekrefte og rette par og indeks før føring? I så fall foreslår jeg en egen RPC (`confirm_round_par`) i neste migrering, ikke åpnere policyer.
4. **`playing_handicap`:** skal appen lagre det utregnede spillehandicapet ved start, så runden står seg selv om regelsett eller bane endres senere? Eller skal vi bare fryse indeks og gruppe og alltid regne resten? Feltet er valgfritt nå.
5. **Én pågående runde per klubb:** beholde sperra?
6. **Én kveld per dato per klubb:** riktig?
7. **Kladd:** PWA-en lot spillere føre i en ulåst kladd. Her må runden være startet. OK?
8. **Sidepremier:** spilleren melder inn bare mens runden pågår, mens arrangøren kan når som helst. Databasen sjekker ikke om LD/KP er slått på for runden (det gjør appen). Godt nok?
9. **Eget navn:** en spiller kan endre sitt eget visningsnavn. Skal bare arrangøren kunne det?
10. **Regelsettets innhold** avtales med regelmotoren (fase 2). Er jsonb med versjon greit, eller vil du ha typede kolonner?
11. **Banebibliotek:** per klubb (nå) eller et felles bibliotek som alle klubber leser?
12. **Sletting av et hull** (strokes `null` i `save_hole`) etterlater ikke noe tidsstempel. En *eldre* innsending som kommer etter slettingen, kan derfor legge hullet inn igjen. Det er sjelden, men skal vi heller lagre tomme hull som egne rader?

### Med vilje utenfor v1

Penger, veddemål, bøter, tråd, tippekupong, aktivitetslogg og push-tokens. De henger på `club_id`, `event_id`, `round_id` og `club_members.id`, så de kan legges til uten å endre det som er her. **Krav til veddemål senere:** ekte fremmednøkkel til `rounds` (PWA-en hadde runde-id inne i jsonb, slik at sletting etterlot åpne veddemål).


---

## Oversikt for godkjenning: 008 (sosialt)

> **Status 06.10.2026:** utkast, **ikke kjørt** noe sted utenom lokal Postgres. Krever 001. Ingen avhengighet til 002–007.

### Tabellene

| Tabell | Hva den er |
|---|---|
| `activity` | Hendelsesloggen per klubb: `kind` (f.eks. `eagle`, `round_locked`) og `data` (jsonb), ikke HTML. Appen lager teksten. `category` er push-kategorien, `recipients` er en valgfri mottakerliste. |
| `activity_reactions` | Én rad per hendelse, medlem og emoji fra det faste settet 👍 😂 ⛳ 🔥 ❤️. |
| `thread_messages` | Kveldens tråd: melding per kveld med tekst (høyst 500 tegn, minst 1 uten bilde), @nevnte og valgfri bildesti. |
| `tips` | Tippekupongen: ett tips per kveld og medlem med de fem svarene fra PWA-en (vinner, første ni, flest par, birdie, over/under). |
| `push_tokens` | APNs-token per medlem og enhet (fase 8), med miljø (`sandbox`/`production`). |
| `events` (nye kolonner) | `tips_stake_points` (innsats i **poeng**, B10) og `tips_line` (x,5). Tom = regelsettets standard. |
| `club_members.avatar_path` | Formatet låses til `<member_id>/<uuid>.jpg`. |
| Storage | Private bøtter `avatars` og `thread`, bare JPEG, maks 3 MB. |

Fasit, poeng og resultat for tippekupongen lagres ikke. De regnes fra hullscorene i regelmotoren. Det finnes ingen betalingstabell, fordi innsatsen er poeng. Poengbanken kommer i fase 10.

### Hvem kan hva (RLS i klartekst)

- **Uinnlogget (anon), ventende medlem og andre klubber:** ingenting. Ingen tabeller, funksjoner eller filer.
- **Aktivitet:** alle i klubben leser. Alle kan legge til en linje. Serveren setter hvem og når. Ingen kan endre eller slette en linje, heller ikke arrangøren (append-only, som i PWA-en). «Melding til alle» (`announcement`), purring (`nudge`), påminnelse (`reminder`) og mottakerliste er bare for arrangøren (og cron). Mottakerne må være i klubben. En tom liste betyr ingen, aldri alle.
- **Reaksjoner:** alle i klubben ser dem. Du setter og fjerner bare dine egne.
- **Tråden:** alle i klubben leser. Du skriver på egne vegne og sletter dine egne. Arrangøren sletter alle. Ingen redigering. `created_at` settes av serveren, og `pushed_at` kan ikke settes av klienten. Nevnte må være i klubben. Bildet må ligge i avsenderens mappe med meldingens egen id.
- **Tippekupongen:** du ser alltid ditt eget tips. De andres ser du først når kupongen er låst. Du leverer, endrer og trekker eget tips bare mens den er åpen. Arrangøren kan fjerne et tips når som helst. `tips_submitted(kveld)` viser hvem som har levert og når, aldri svarene.
  - **Låsen:** kupongen er åpen før fristen og før første score på en runde den kvelden, det som kommer først. Fristen er kveldens dato og `start_time` som Europe/Oslo, ellers 17:00. Sjekket lokalt: 8.10 → 15:00Z, 5.11 → 16:00Z, 25.10 → 16:00Z og 29.03 → 15:00Z, som i `tippekupong-test.js`.
  - Innsats og linje står fast når første kupong er levert (55000).
- **Push-tokens:** bare eieren ser og sletter sine egne (logg ut). Skriving går via `register_push_token(enhet, token, miljø)`. Den registrerer enheten for alle dine aktive medlemskap og tar over en enhet eller et token som tilhørte en annen innlogging. Senderen (Edge Function med service_role, aldri i appen) må bare bruke rader der medlemmet fortsatt er koblet til samme innlogging og er aktivt.
- **Bilder:** alle i klubben ser bildene til klubbens medlemmer. Portrett: du selv eller arrangøren laster opp og sletter. Trådbilde: bare avsenderen laster opp, avsenderen eller arrangøren sletter. Ingen kan overskrive (ingen update-policy). Appen laster opp med `upsert = false` og ny sti for nytt bilde.
- **Realtime:** `activity`, `activity_reactions`, `thread_messages` og `tips`. Realtime følger policyene, så før låsing får du bare hendelser for ditt eget tips.

### RPC-er og hjelpere

| Funksjon | Hvem | Hva |
|---|---|---|
| `tips_deadline(kveld)` | medlem | Fristen som tidspunkt (UTC). |
| `tips_open(kveld)` | medlem | Om kupongen er åpen. Brukes i policyene. |
| `tips_submitted(kveld)` | medlem | Hvem som har levert og når. |
| `register_push_token(enhet, token, miljø, bundle)` | innlogget | Registrerer enheten i én transaksjon og returnerer radene. |
| `storage_can_read/write(sti)` | innlogget | Sti-reglene for bøttene. Mappen sjekkes som uuid før oppslag. |

### Valg jeg har tatt

1. **Logg skrevet av klienten, som i PWA-en,** med vakter i databasen (hvem, når, arrangørens kategorier, mottakere). *Alternativ:* triggere som skriver loggen selv (f.eks. ved låst runde eller eagle). Det er sikrere, men gir mer SQL.
2. **Kategoriene står i en CHECK-liste** med engelske id-er (`score`, `lead`, `side_prize`, `round`, `setup`, `bet`, `signup`, `social`, `club`, `tips`, `announcement`, `nudge`, `reminder`). En ny kategori krever en migrering. `penger` og `boter` er utelatt (B10).
3. **Tråden følger PWA-en:** en melding med bilde kan ha tom tekst. Uten bilde må det være 1–500 tegn.
4. **Bilder i medlemmets mappe** (`<member_id>/…`). Medlems-id-en er unik på tvers av klubber, så mappen sier også hvilken klubb som kan lese. Portrettet har egen bøtte (`avatars`) i stedet for PWA-ens `klubbilder/spillere/`.
5. **Ett push-token per medlemskap og enhet.** En innlogging i to klubber gir to rader, så hver klubb kan få egne kategorier senere.
6. **Fristens standard 17:00** står i SQL-en (Golfgutu-verdien). Innsats og linje er tomme og hentes fra regelsettet.
7. **Linja må være x,5**, som i PWA-en.

### Åpne spørsmål til deg

1. **Innsats i poeng:** er det riktig at innsatsen per kveld er et heltall poeng (0 = «for æra»), uten oppgjør før poengbanken i fase 10?
2. **Standard for frist, innsats og linje:** regelmotoren har ennå ikke felt for tippekupongen. Skal 17:00 også flyttes inn i regelsettet, eller er det greit at den står i databasen?
3. **Mottakerliste:** *Besvart 06.10:* en linje med mottakere vises bare for mottakerne, den som laget den og arrangøren (RLS på `activity`).
4. **Push-valg for tråden** (alle / når jeg nevnes / av) og kategorier av/på per spiller og for klubben: lar jeg det vente til fase 8 sammen med Edge Function-en?
5. **Banebilder** (`courses.image_path`, plakaten): egen bøtte nå, eller senere?
6. **Hendelser om kladder:** *Besvart 06.10:* databasen skjuler linjer som peker på en runde du ikke kan se (`can_read_round`).
7. **Sletting av bilder:** når en melding slettes, sletter appen fila. Supabase lar ikke SQL slette filer. Holder det, eller vil du ha en opprydding som Edge Function senere?

### Lokal sjekk av 008

Kjørt mot en midlertidig, lokal Postgres 16.2 (pip-pakken `pgserver` i et virtuelt miljø i scratch). Supabase Storage er etterlignet i `lokal/stub_storage.sql` (`storage.buckets`, `storage.objects` med RLS, `storage.foldername`). Aldri mot Supabase.

- `lokal/stub.sql`, `lokal/stub_storage.sql`, 001, 002, 004, 005, 006, 007 og 008 to ganger på rad: ingen feil. Andre kjøring er idempotent.
- `lokal/008_prove.sql` i en tom base etter 001 og 008: **102 av 102 ok**. Den dekker anon, ventende, annen klubb, spiller og arrangør for alle tabellene, vaktene, fristen rundt sommertid, låsen ved første score, overtakelse av enhet og sti-reglene i Storage.
- Kontrollspørringene og rullebakken er kjørt med forventet svar, og 008 gikk inn igjen etter rullebakken.
- **Forbehold:** ekte Supabase Storage, Realtime og PostgREST er ikke prøvd. På Supabase eier `supabase_storage_admin` `storage.objects`. Policyene opprettes som `postgres` i SQL Editor, slik PWA-ens `traad-bilder.sql` gjorde.


---

## Oversikt for godkjenning: 010 (push)

> **Status 07.10.2026:** forslag, **ikke kjørt** noe sted utenom lokal Postgres. Krever 001 og 008. Oppsettet steg for steg står i `docs/push-oppsett.md`.

### Tabellene

| Tabell | Hva den er |
|---|---|
| `push_devices` | Én rad per telefon: innlogging, `device_id` (identifierForVendor), token (unikt, heks), miljø `sandbox`/`production`, bundle og `last_seen_at`. **Erstatter 008s `push_tokens`** (én rad per medlemskap). Eventuelle rader flyttes over, så fjernes `push_tokens` og `register_push_token`. |
| `push_preferences` | Spillerens valg per medlemskap: `disabled_categories` (det som er AV) og `thread_mode` (`all`/`mentions`/`off`). Ingen rad = alt på, tråden `mentions`. |
| `clubs.push_disabled_categories` | Arrangørens «Hva blir push» for hele klubben (PWA: `settings.push_av`). |
| `push_queue` | Køen: én jobb per `activity`-linje eller trådmelding, fylt av triggere. Bare service_role. En Database Webhook på INSERT vekker `push-send`. |

### Hvem kan hva

- **anon:** ingenting.
- **Spiller:** ser bare sin egen telefon og registrerer eller fjerner den via RPC. Leser, lager og endrer bare egne valg (aktivt medlemskap). Leser klubbens valg.
- **Arrangør:** endrer `clubs.push_disabled_categories` med vanlig `clubs_update`. Ser hvem som har push via `push_status` (aldri tokens).
- **Senderen (service_role i Edge Function):** tar jobber, henter alt for én jobb, merker den ferdig og sletter døde tokens.
- «Melding til alle» kan ikke slås av, verken av klubben eller spilleren. Purring kan ikke slås av for klubben (PWA: ALLTID), men spilleren kan.

### RPC-er

| Funksjon | Hvem | Hva |
|---|---|---|
| `register_push_device(enhet, token, miljø, bundle)` | innlogget | Registrerer eller tar over telefonen i én transaksjon. Returnerer raden. |
| `unregister_push_device(enhet)` | innlogget | Fjerner min telefon (logg ut). |
| `push_status(klubb)` | arrangør | Medlem, har innlogging, antall telefoner, sist sett. |
| `claim_push_jobs(n)` | service_role | Tar de neste jobbene (skip locked, høyst 5 forsøk, høyst en time gamle). |
| `push_job_payload(jobb)` | service_role | Linja eller meldingen, klubbens valg og alle medlemmer med valg og telefoner, som jsonb. |
| `finish_push_job(jobb, ok, resultat, feil, døde tokens)` | service_role | Ferdig eller prøv igjen, slett døde tokens, merk tråden `pushed_at`. |
| `queue_evening_reminders(dager)` | service_role (pg_cron) | Påminnelse i aktivitetsloggen for kvelder om N dager (standard 7), én per kveld. |

### Lokal sjekk av 010

Lokal Postgres 16.2 (pgserver i scratch): `stub`, `stub_storage`, 001–009 og 010 **to ganger på rad** uten feil. `lokal/010_prove.sql`: **68 av 68 ok**. Flytting fra `push_tokens`, kontrollspørringene og rullebakken (og 010 på nytt etterpå) er prøvd. Webhooken, pg_cron, PostgREST og ekte APNs er ikke prøvd.


---

## Oversikt for godkjenning: 012 (veddemål med poeng)

> **Status 07.10.2026:** forslag, **ikke kjørt** mot Supabase. Krever 001, 008 og 010. Modellen og de åpne spørsmålene står i `docs/veddemaal-poeng.md`.

### Tabellene

| Tabell | Hva den er |
|---|---|
| `bets` | Ett veddemål: sesong, valgfri kveld og runde (ekte fremmednøkler), hvem som la det ut, hvem det er rettet mot (`against_id`), påstanden (4–140 tegn), vilkåret (jsonb, `null` = fri tekst), status `open`/`resolved`/`void`, utfall `yes`/`no`, stempelet `closed_at` og hvem som avgjorde. |
| `bet_stakes` | Innsatsene i **poeng** (1–10 000), side `yes`/`no`. Flere innsatser per spiller er lov, men alltid på samme side og under taket. |

**Ingen saldotabell.** Saldo = startbeholdning (regelsettet) + netto fra avgjorte veddemål. `bet_points(sesong, medlem)` regner netto, stående, saldo og ledig, med samme regnestykke som `Bets.swift` i appen.

### Hvem kan hva

- **Uinnlogget:** ingenting (42501 på tabeller og funksjoner).
- **Spiller:** leser veddemål og innsatser i egen klubb (veddemål om en kladd bare om du ser runden). Legger ut veddemål med første innsats (`create_bet`) og satser (`place_bet_stake`). Skriver aldri rett i tabellene.
- **Arrangør:** som spiller, pluss `resolve_bet` (JA, NEI eller annullert) og `mark_bets_closed` (journalstempelet).

### Sjekkene i databasen

- **Sperra** (`bet_accepts_stakes`): stemplet eller avgjort tar ingenting. Hullvilkår: hullet må ligge minst forspranget (regelsettet, Golfgutu 1) foran den eller dem det gjelder, målt fra hullscorene. Rundevilkår: før første score. Låst runde: ingenting. Fri tekst: alltid.
- **Tak** per veddemål og spiller fra regelsettet (Golfgutu 200), summert over innsatsene. **Samme side** som før. **Ledige poeng** når sesongen har bank. Innsatsene til ett medlem i én sesong låses mot hverandre (advisory lock), så to samtidige ikke bruker de samme poengene.
- **Vilkåret** sjekkes for form (`bet_condition_valid`), og spillerne i det må være med i runden.
- Avvises første innsats, rulles hele veddemålet tilbake.

### Aktivitet og push

`create_bet` skriver `bet_created` (eller `bet_challenge` når veddemålet er rettet mot noen), og `resolve_bet` skriver `bet_resolved`, i kategorien `bet` og i samme transaksjon. Køtriggeren fra 010 gjør dem til push. Enkeltinnsatser gir ingen linje.

### Valg jeg har tatt

1. **Saldo regnes, lagres ikke** (CLAUDE.md). Prisen er at regnestykket står to steder (SQL og Swift), slik PWA-ens `spiller_saldo` og `balanceFor` gjorde. Begge er prøvd med de samme tallene.
2. **Regelverdiene leses fra sesongens regelsett** (`rules->'bets'`). Mangler feltet, gjelder Golfgutu-verdien, som i appens dekoder.
3. **Slettes runden, går veddemålene om den med** (cascade), som PWA-ens slett_runde. `delete_round` teller dem ikke i svaret sitt.
4. **Annullert** (`void`) er nytt: arrangørens utvei for delt hull, delt match og likt resultat, der vilkåret ikke gir svar.


---

## Oversikt for godkjenning: 017 (fundament, fase 12)

> **Status 07.10.2026:** forslag, **ikke kjørt** mot Supabase. Krever 001–016. Modellen, trusselmodellen og veien videre står i `docs/datamodell-v2.md`. Appen rører ingenting av dette før `FoundationFeature.isEnabled` slås på.

### Tabellene

| Tabell | Hva den er |
|---|---|
| `profiles` | Én rad per innlogging (`id` = `auth.users.id`): visningsnavn (tomt til det er satt), handicap og portrett. Lages av en trigger på `auth.users` og av `ensure_profile()`. |
| `round_participants` | Deltaker i en løs runde: en profil eller en gjest (bare navn). `round_players.member_id` = `id`, og raden i `round_players` lages av en trigger. |
| `competitions` | En konkurranse: `season`/`league`/`cup`/`fun`/`game`, regelsett (jsonb med versjon), periode, eier (klubb eller profil), `entry`, `is_main` (høyst én aktiv per klubb), `requires_purchase` og `entitlement_id` (bare serveren). |
| `competition_participants` | Påmeldte: klubbmedlem eller profil. |
| `competition_rounds` | Rundene som teller. En runde kan telle i flere. `source` er `season` (triggeren) eller `manual`. |
| `entitlements` | Kjøp i appen (StoreKit). Bare serveren skriver. |
| `round_roster` (view) | Deltakerne i en runde med navn og profil, uansett type. `security_invoker`. |

### Hva som endres for dagens data

- `rounds.club_id` og `rounds.event_id` kan være tomme, men `rounds_home_check` krever begge eller ingen. Alle runder som finnes, har begge. Nye kolonner: `owner_id`. Ny fremmednøkkel: `course_id → courses(id)`.
- `round_players.club_id` kan være tom (deltaker i løs runde). Ny generert kolonne: `participant_round_id`. To nye fremmednøkler.
- `courses.club_id` kan være tom (det felles biblioteket). Nye kolonner: `source`, `external_id`, `fetched_at`, `created_by_profile`.
- **Data:** en profil per innlogging (fra første aktive medlemskap), en konkurranse per sesong (`season`, `is_main`, `entry = club`), og rundene i sesongens kvelder koblet til den.
- **Triggere:** sesongen speiles til konkurransen (navn, status, regler). Nye runder og kvelder som bytter sesong, kobles om. Vakter finnes for løse runder, baner, konkurranser og påmeldinger.
- **Utvidede hjelpere** (create or replace, samme svar for klubbrunder): `can_read_round`, `is_round_organizer`, `can_score`, `side_claims_before_write`.
- **Policyer som byttes** (klubbuttrykket er uendret, nytt ledd for løse runder og biblioteket): `rounds_*`, `side_claims_insert/update/delete`, `courses_*`, `course_holes_*`.

### Hvem kan hva

- **anon:** ingenting (42501 på alle nye tabeller, viewet og funksjonene).
- **Klubbmedlem:** ser og kan nøyaktig det samme i klubben som før. Kontroll 9 sammenligner med 001-utgavene for hver innlogging, og `lokal/017_prove.sql` sammenligner et bilde tatt før og etter.
- **Eier av en løs runde:** arrangørens rett i runden. Legger til gjester og folk hen kan se.
- **Deltaker i en løs runde:** ser runden og fører etter kanFore (seg selv, eller som markør).
- **Konkurranse:** arrangøren (klubbens) eller eieren styrer. Deltakerne ser den og de startede rundene i den. Bare rundens eier kan legge runden inn.
- **Fremmed:** ser ingen profiler, runder, konkurranser eller klubbdata. Ser bare det felles banebiblioteket. Kan ikke legge deg til noe sted.

### RPC-er

| Funksjon | Hvem | Hva |
|---|---|---|
| `ensure_profile()` | innlogget | Lager profilen om den mangler og fyller tomme felt fra klubbmedlemskapet. Idempotent. |
| `create_loose_round(bane, hull, første hull, form, sted, spillere, start)` | innlogget | Løs runde med deg som eier og første deltaker, profiler du kan se og gjester, i én transaksjon. Banen må være i det felles biblioteket. |
| `create_competition(type, navn, klubb, entry, regler, fra, til)` | innlogget (arrangør for klubb) | Ny konkurranse (ikke sesong). Uten klubb blir du eier og første påmeldte. |

### Lokal sjekk av 017

Lokal Postgres 16.2 (pgserver i scratch, egen datakatalog og port): `stub`, `stub_storage`, 001–016, `lokal/017_for.sql`, 017 **to ganger**, så `lokal/017_prove.sql`: **129 av 129 ok**. Prøven dekker:

- at hver innlogging ser og kan det samme som før;
- migreringen av profiler, konkurranser og koblinger;
- speilingen (ny runde, kvelden som bytter sesong, nytt navn på sesongen, `activate_season` fram og tilbake);
- profiler (egne, andres, ventende);
- to fremmede som registrerer seg, med felles bane, løs runde med gjest, føring og vaktene;
- en løs runde med en klubbvenn og en gjest som kobles til en profil;
- en konkurranse som teller en klubbrunde og en løs runde (runder fra to steder), med hvem som ser hva;
- at dagens RPC-er virker (`save_hole`, `confirm_round_par`, `create_bet`, `set_round_setup`, `start_round`, `delete_round` og `create_club`);
- sletting av runde og konto, og anon.

Kontrollblokken nederst i fila ga **14 av 14** rett etter migreringen. Kontroll 9 ble prøvd med en bevisst feil i `can_score` og ga `false`. Rullebakken er kjørt både på en fersk base og etter rolleprøven (med løse runder, gjester og felles baner). Etter rullebakken ser alle det samme som før 017, og 017 gikk inn igjen. `lokal/001_prove`, `008_prove`, `010_prove` og `012_prove` gir **like linjer med og uten 017**. 008 har to kjente FEIL i begge, fordi 010 har erstattet `push_tokens`. **Forbehold:** ekte Supabase (PG 17, PostgREST, Realtime, Auth-triggeren og advisoren) er ikke prøvd.

