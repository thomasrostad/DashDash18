# sql/: migreringer for appens egen Supabase

Dette er skjemaet for appens **nye, egne** database. PWA-ens database røres ikke. Den brukes bare som kilde for import i fase 9.

> **Status 06.10.2026:** `001_skjema_v1.sql` er et **utkast til godkjenning**. Ingenting er kjørt mot Supabase.

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
| `001_skjema_v1.sql` | Kjernen for fase 1–5 | Utkast, venter på godkjenning |
| `lokal/stub.sql`, `lokal/001_prove.sql` | Lokal syntaks- og rolleprøve. **Aldri mot Supabase.** | Hjelpefiler |

Kommer senere, som egne filer: par-bekreftelse for markør (se åpne spørsmål), aktivitetslogg og varsler, tråd, tippekupong, push-tokens (APNs), Storage-bøtter for bilder, og poeng/veddemål (fase 10).

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
