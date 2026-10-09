# Fase 22: turneringen som kjerne

Status 09.10.2026: **design, del 1**. Forslag til godkjenning. Ingenting er kjørt mot Supabase. Første SQL-trinn ligger i `sql/031_turnering_kjerne_trinn1.sql` og er prøvd lokalt (`sql/lokal/031_for.sql`, `sql/lokal/031_prove.sql`). Lasttesten ligger i `sql/lokal/lasttest.sql`.

Bakgrunn: Thomas 08.10.2026. Appen skal kunne brukes av golfklubber og simulatorsentre som kjører **mange turneringer i uka**. Noen går over lang tid (serier og ligaer), noen er over på én dag, og de overlapper ofte. Målet er tusenvis av brukere.

Beslutninger fra Thomas (08.10.2026):

1. En turnering kan ha **åpen påmelding** for folk som ikke er medlem i klubben. Det velges per turnering.
2. **Lasttest gratis først:** lokal Postgres og eventuelt et eget gratis Supabase-prosjekt. Pro kommer senere.
3. **Golfgutu-gjengen forblir én klubb med én hovedturnering.** Ingenting skal endre seg for dem.

---

## 1. Kort fortalt

- **Turneringen blir kjernen**, ikke klubben. En klubb eller arena kan ha mange turneringer i gang samtidig. Spilledager (kvelder) og runder hører til en turnering.
- Reglene som i dag gjelder per klubb, flyttes til turneringen:
  - «én aktiv runde» gjelder per spilledag og pulje,
  - «én kveld per dato» gjelder per turnering,
  - «én aktiv sesong» faller bort, men «én hovedturnering» står.
- **Påmeldingen** får tak, venteliste og et påmeldingsvindu, og kan stå åpen for ikke-medlemmer. En turnering kan ha **flere arrangører**, og funksjonærer som fører for alle.
- **Startlista** gir hver gruppe starttid, starthull og bås eller simulator. Det dekker både simulatorsenteret med båser og ekte bane med tee-tider, flighter og kanonstart.
- Vi går fram i **fem trinn**. Trinn 1 (`031`) legger bare til ting: nye kolonner, nye tabeller og nye indekser ved siden av de gamle. Dagens app merker ingenting, og Golfgutu-dataene får samme Tavla før og etter. Lokalt er det bevist med 78 av 78 sjekker og 12 av 12 i kontrollblokken.
- **Lasttesten** (1 000 brukere, 50 arenaer, 200 turneringer, 22 000 runder og 3 mill. hullscorer) viser at det er **RLS per rad** som koster, ikke datamengden. Å åpne Tavla bruker i dag om lag 700 ms databasetid fordelt på 106 kall. Den samme dataen i én RPC tar 26 ms. «Folk du kjenner» går fra 106 ms til 1 ms med en mengdebasert RPC. Rettelsene hører til fase 24. 031 tar med to indekser som hjelper allerede nå.

---

## 2. Hvor vi er i dag

Datamodell v2 (`docs/datamodell-v2.md`, sql/017) gjorde runden til kjernen og la konkurranser oppå rundene. Klubbsiden er likevel bygget rundt én turnering om gangen:

| Begrensning | Hvor | Virkning |
|---|---|---|
| Én aktiv runde per klubb | `rounds_one_active_per_club` (001) | Et simulatorsenter kan ikke kjøre to turneringer samtidig |
| Én aktiv sesong per klubb | `seasons_one_active_per_club` (001), `activate_season` (004) avslutter de andre | Ingen samtidige serier, for eksempel tirsdagsserie og torsdagsliga |
| Én kveld per dato per klubb | `events_one_per_date` (001) | To turneringer kan ikke spille samme dag |
| Kvelder hører til klubb og sesong | `events.season_id` | En liga eller morroturnering kan ikke ha egne spilledager |
| Hver sesong blir hovedturnering | `competitions_sync_season` (017) setter `is_main = true` | En ny aktiv sesong i tillegg til jakkeracet stopper på `competitions_one_main_active` (prøvd lokalt, del C i 031_prove) |
| Deltakerne er klubbens tropp | `round_players.member_id` → `club_members` i klubbrunder, og `round_participants_before_write` (017) nekter profiler i klubbrunder | Ikke-medlemmer kan ikke spille i en klubbturnering |
| Arrangør = klubbens arrangør | `is_club_organizer`, `is_competition_admin` (017) | Ingen arrangør per turnering |
| Arrangørsiden og Tavla bygger på hovedturneringen | `TavlaQueries.load` henter «den aktive sesongen», `RundeQueries.activeRound` «klubbens pågående runde» | Appen viser én turnering per klubb |
| Tavla regnes på telefonen fra alle hull | `TavlaQueries`: 7 spørringer + én per runde for hullscorene | Se lasttesten: ~700 ms databasetid per åpning med 100 runder |
| Aktivitet og push per klubb | `activity.club_id not null`, `push_queue.club_id not null`, `push_job_payload` sender til klubbens tropp | Ikke-medlemmer i en åpen turnering får verken feed eller push |

---

## 3. Målbildet

### 3.1 Begrepene

| Begrep | I appen | I databasen |
|---|---|---|
| **Arena** | En golfklubb, et simulatorsenter eller en gjeng | `clubs` med `kind` (`group`, `golf_club`, `simulator_center`) |
| **Turnering** | Serie, liga, cup, morroturnering, éndagsturnering | `competitions` (kjernen) |
| **Spilledag** | En kveld eller dag i turneringen | `events` med `competition_id` |
| **Pulje** | Formiddag og ettermiddag, eller to båsrekker samme kveld | `rounds.wave_no` |
| **Runde** | Én runde på en spilledag (eller en løs runde) | `rounds` |
| **Gruppe/flight/bås** | Folk som spiller sammen, med markør | `round_players.bay_no` + `round_start_groups` |
| **Stab** | Arrangører og funksjonærer per turnering | `competition_staff` |
| **Påmeldt / venteliste** | Med i turneringen, eller i kø | `competition_participants` / `competition_waitlist` |

### 3.2 Slik ser det ut for en arena

Et simulatorsenter med 8 båser kan for eksempel ha disse samtidig:

- en **tirsdagsliga** (serie over 10 uker, åpen påmelding, tak 32, venteliste),
- en **torsdagsserie for medlemmer** (som jakkeracet),
- en **éndags firmaturnering** lørdag (åpen med lenke, to puljer),
- en **vintercup** (utslag) der kampene spilles når det passer.

Hver turnering har egne arrangører, egne spilledager, egen påmelding og egen tabell. Flere runder kan gå samtidig i senteret: én per spilledag og pulje. Båsene er ressursene i startlista.

En **golfklubb med ekte bane** har startliste med tee-tider (10 minutters mellomrom), flighter på 3–4 og eventuelt kanonstart (`start_hole`). Funksjonærer kan føre for alle (`competition_staff.role = scorer`).

**Golfgutu** er en arena av typen `group` med én hovedturnering, jakkeracet. Kveldene hører til den, med én runde om gangen og troppen som deltakere. Alt dette er standardverdiene i målbildet, så gjengen ser ingen forskjell.

### 3.3 Påmelding

- `signup_audience`: `members` (standard) betyr bare klubbens medlemmer. I en privat turnering uten klubb betyr det de som har invitasjon. `anyone` betyr alle innloggede som finner turneringen, enten via lenke eller koden fra 022 eller via arenaens offentlige liste (`listed`).
- `max_entrants` er taket på antall aktive påmeldte. `waitlist_enabled` sender nye påmeldinger til ventelista når turneringen er full. Rekkefølgen der er `created_at`.
- Når noen melder seg av, får den første på ventelista **tilbud om plassen** (`offered_at`, `offer_expires_at`) og en push. Tar personen ikke plassen innen fristen, går tilbudet videre. Det skjer i én transaksjon i RPC-en (trinn 2), med `for update` på turneringen, så to som melder seg på samtidig ikke begge får den siste plassen.
- `signup_opens_at` og `signup_closes_at` er påmeldingsvinduet.
- Ventelista er en **egen tabell** og ikke en ny status i `competition_participants`. Dagens app dekoder `status` strengt (`active | withdrawn`), og en ukjent verdi ville gjort hele påmeldingslista ulesbar for gamle bygg. Det samme gjelder `kind`, `entry`, `source` og rundens `status`: ingen nye verdier før den gamle appen er stengt ute (trinn 4).

### 3.4 Flere arrangører

`competition_staff (competition_id, profile_id, role)` har to roller. `organizer` styrer turneringen: spilledager, runder, påmelding og stab. `scorer` kan føre for alle i turneringens runder. Staben er profiler, så en ansatt i senteret trenger ikke være medlem i «klubben». Klubbens arrangører er fortsatt arrangører for alle klubbens turneringer.

---

## 4. Datamodellen før → etter

«031» er det trinn 1 gjør nå. «Senere» viser hvilket trinn resten kommer i (se kap. 10).

| Tabell | I dag | Målbilde | 031 (trinn 1) | Senere |
|---|---|---|---|---|
| `clubs` | Klubb/gjeng | Arena: gjeng, golfklubb eller simulatorsenter | `kind` (standard `group`) | Ressurser (båser, simulatorer) som egen tabell hvis bås-booking trengs |
| `club_members` | Troppen, roller som flagg | Uendret. Medlemskap i arenaen | – | – |
| `profiles` | Én per innlogging | Uendret. Deltakere og stab i åpne turneringer er profiler | – | – |
| `seasons` | Sesong med regelsett, kilde for turneringen | Tynn rad, til slutt et view over `competitions` (kap. 5) | – | Trinn 3: turneringen blir kilden. Trinn 5: view |
| `competitions` | Konkurranse. Sesongens speiles fra `seasons` | **Kjernen.** Påmelding, tak, venteliste, sted | `signup_audience`, `listed`, `max_entrants`, `waitlist_enabled`, `signup_opens_at`, `signup_closes_at`, `venue` + sjekker | Trinn 3: kilden for sesongen; `is_main` bare når klubben ikke har en aktiv |
| `competition_staff` | – | Arrangører og funksjonærer per turnering | Ny (lesing og skriving med dagens `is_competition_admin`) | Trinn 2: rettighetene kobles på |
| `competition_participants` | Påmeldte (medlem eller profil) | Uendret, pluss ikke-medlemmer i klubbturneringer | Indeks på `competition_id` | Trinn 2: `is_competition_participant` som mengde |
| `competition_waitlist` | – | Venteliste med tilbud | Ny (bare lesing) | Trinn 2: RPC-ene som skriver |
| `competition_rounds` | Rundene som teller | Uendret. `source = season` betyr «koblet via spilledagen» | – | Trinn 3: koblingen bruker `events.competition_id` for alle turneringer |
| `events` | Kveld i klubbens terminliste, `season_id` | Spilledag i en turnering | `competition_id` (fylt fra sesongen, holdt i takt begge veier), unik (turnering, dato) | Trinn 4: `events_one_per_date` (klubb) fjernes. Trinn 5: `season_id` peker på turneringen |
| `rounds` | Klubbrunde eller løs runde | Runde på en spilledag (pulje) eller løs | `wave_no` (standard 1), unik aktiv per (spilledag, pulje) | Trinn 4: `rounds_one_active_per_club` fjernes |
| `round_players` | Medlem (klubb) eller deltaker (løs) | Medlem eller profil/gjest også i klubbrunder | – | Trinn 4: ikke-medlemmer i klubbrunder; `bay_no` opp til 99 |
| `round_start_groups` | – (bare `rounds.tee_time`) | Startliste: tid, starthull, bås/simulator per gruppe | Ny (les som runden, skriv som arrangøren) | – |
| `activity` | Per klubb (`club_id not null`) | Per turnering, klubb valgfri | `competition_id` (fylt av trigger + for det som finnes), indeks | Trinn 4: `club_id` valgfri, lesing for deltakere |
| `push_queue` | Per klubb | Per turnering eller klubb | – | Trinn 4: `competition_id`, mottakere fra turneringen |
| `thread_messages`, `tips`, `bets`, `signups` | Per kveld/klubb/sesong | Per spilledag (uendret nøkkel) | – | Tråd for ikke-medlemmer i trinn 4 |
| `app_config` | – | Brytere, bl.a. minste appbygg | Ny, `min_ios_build = 0` | Trinn 3/4: settes til fase-23-bygget |

---

## 5. Hva skjer med `seasons`

Datamodell v2 peker allerede dit: `seasons` blir **en tynn rad, og til slutt et view** over `competitions`.

1. **I dag (017):** `seasons` er kilden. `competitions_sync_season` lager og oppdaterer sesongens turnering (navn, status og regler) og gjør den til hovedturnering.
2. **Trinn 1 (031):** uendret retning. Kveldene får `competition_id` i tillegg, og en trigger holder `season_id` og `competition_id` i takt **begge veier**:
   - dagens app setter `season_id`, og turneringen følger;
   - den nye appen setter `competition_id`, og sesongen følger.

   Dermed ser dagens Tavla en kveld som den nye appen legger i jakkeracet.
3. **Trinn 3:** speilingen snus. Den nye appen lager og endrer turneringen. En trigger på `competitions` skriver navn, status og regler tilbake til `seasons` for turneringer av typen `season`, og en sperre på `pg_trigger_depth()` hindrer at triggerne kaller hverandre i ring. `activate_season` avslutter ikke lenger alle andre sesonger, bare den forrige **hovedturneringen**. Nye serier blir ikke hovedturnering når klubben har en aktiv.
4. **Trinn 5**, når ingen klient leser `seasons`:
   - tabellen erstattes av et view: `select season_id as id, club_id, name, status, rules, created_at from competitions where season_id is not null`;
   - `events.season_id` og `bets.season_id` peker på `competitions(season_id)`, som allerede er unik;
   - sesong-id-ene står, så historikken (veddemål, import) beholder nøklene.

---

## 6. «Én aktiv runde» blir per spilledag og pulje

- I dag gjelder `rounds_one_active_per_club`: én aktiv runde i hele klubben.
- I målbildet gjelder `rounds_one_active_per_event_wave`: høyst én aktiv runde per **(spilledag, pulje)**. En spilledag har normalt én pulje. Da er regelen den samme som i dag for Golfgutu, siden gjengen har én spilledag om gangen.
- Simulatorsenteret kan kjøre runder i flere turneringer samtidig (ulike spilledager), og to puljer samme kveld (`wave_no` 1 og 2).
- En runde rommer fortsatt mange båser eller flighter (`bay_no`). «Pulje» trengs bare når to *runder* skal gå samtidig på samme spilledag, for eksempel to båsrekker med ulik bane.
- Løse runder har ingen slik regel, som i dag.

031 lager den nye indeksen **ved siden av** den gamle. Med dagens data er den alltid oppfylt, fordi én aktiv runde per klubb gir høyst én per kveld. Del C i `031_prove.sql` viser trinn 4 i det små: uten den gamle indeksen kan to runder gå i klubben samtidig, men pulje 1 på samme spilledag avvises fortsatt med 23505.

**Appen i trinn 4:** «Pågår nå» blir en liste: rundene du spiller i eller arrangerer. Det erstatter «klubbens pågående» (`RundeQueries.activeRound`). Feilmeldingen på 23505 blir «En runde går allerede i denne puljen».

---

## 7. RLS: lesing og skriving per turnering

### 7.1 Lesing

| Du ser … | når … |
|---|---|
| turneringen (navn, tid, påmeldingsstatus) | du er medlem i arenaen, du er i staben, du er påmeldt eller på ventelista, du har koden (022), **eller** den er `listed` og åpen (`anyone`) |
| påmeldte og tabell | du kan se turneringen. For `listed`/`anyone` ser ikke-deltakere bare tabellen, ikke rundedetaljene (svar 4 i datamodell-v2) |
| spilledagene | du kan se turneringen |
| en startet runde i turneringen, med hull og scorer | du er medlem i arenaen (som i dag), i staben, eller påmeldt i turneringen |
| kladder | arrangøren og staben (`organizer`) |
| ventelista | din egen plass. Arrangøren og staben ser hele |
| aktivitet i turneringen | du kan se turneringen og runden (som i dag via `can_read_round`) |

### 7.2 Skriving

| Handling | Hvem |
|---|---|
| Endre turneringen, spilledager, runder, startliste | arrangøren (klubbens arrangør, eieren, eller `staff.organizer`) |
| Stab | arrangøren. Du kan gå ut selv |
| Melde seg på, av, ta tilbud fra ventelista | du selv, via RPC (tak, vindu og venteliste i én transaksjon) |
| Føre score | kanFore som i dag, pluss `staff.scorer` og `staff.organizer` |
| Legge en runde i turneringen | arrangøren av turneringen **og** rundens eier (som i 017) |

### 7.3 Hvordan, og i hvilket trinn

- **Trinn 1 (031):** ingen policy og ingen hjelpefunksjon endres. De nye tabellene bruker dagens hjelpere (`can_read_competition`, `is_competition_admin`, `can_read_round`, `is_round_organizer`). Det betyr at bare de som styrer turneringen i dag, kan legge til stab, og at staben ennå ikke får nye rettigheter. Kontroll 7 i 031 sjekker at ingen gammel policy nevner de nye tingene.
- **Trinn 2:** hjelperne utvides med nye grener, slik 017 gjorde for løse runder. For hver innlogging og hver Golfgutu-runde og -turnering skal svaret være likt før og etter (samme metode som kontroll 9 i 017). Det er lett å holde, fordi staben er tom og ingen Golfgutu-turnering er `anyone`.
  - `is_competition_admin`: i tillegg `is_competition_staff(id, 'organizer')`.
  - `can_read_competition`: i tillegg stab, venteliste og `listed and signup_audience = 'anyone'`. Den siste grenen gir bare raden i `competitions`, ikke rundene.
  - `is_round_organizer` / `can_score`: i tillegg staben i turneringen som eier spilledagen (`events.competition_id`).
  - `can_read_round`: i tillegg påmeldte i turneringen som eier spilledagen. Det trengs for ikke-medlemmer.
- **Ytelse (fra lasttesten, kap. 9):** policyene kaller hjelperne én gang **per rad**. Nye grener skal derfor skrives som mengder, med `(select auth.uid())` og `= any(array(...))`, ikke som et funksjonskall per påmeldt. `is_competition_participant` skrives om i trinn 2. Den målte forskjellen er 18,7 → 4,0 ms for turneringslista med 200 turneringer.

---

## 8. Push, aktivitet og Hjem

**I dag:**

- `activity.club_id` er påkrevd.
- `push_enqueue_activity` legger hver linje i `push_queue` (også påkrevd klubb), og `push_job_payload` sender til **klubbens tropp** med klubbens og medlemmets kategorier.
- Hjem leser `activity` for klubbene dine.
- Private turneringer og løse runder har ingen aktivitet. Appen regner kortene selv (027).

**Trinn 1 (031):**

- `activity.competition_id` (valgfri) fylles av en trigger: fra `data->>'competition'` ved plassbytte, ellers fra spilledagen eller rundens spilledag.
- Det som finnes, fylles også.
- Ny indeks `activity (competition_id, created_at desc)`.
- Push, lesing og Hjem er uendret.

**Trinn 2–4:**

1. **Hjem (fase 23):** filterpillene per turnering bruker `competition_id`, ikke en gjetning fra runden. Turneringer der du er påmeldt uten å være medlem, tas med.
2. **Lesing (trinn 4):** `activity_select` får en gren `competition_id is not null and can_read_competition(competition_id)` for deltakere som ikke er medlemmer. `club_id` blir valgfri for private turneringer, med CHECK: klubb eller turnering.
3. **Push (trinn 4):**
   - `push_queue` får `competition_id`, og `club_id` blir valgfri.
   - `push_job_payload` henter mottakerne fra turneringen (påmeldte, stab og arenaens medlemmer når `entry = club`) via `profiles` → `push_devices.user_id`, ikke fra troppen alene.
   - Kategoriene per klubb (`clubs.push_disabled_categories`) gjelder fortsatt for klubbens turneringer. Hver bruker får valg per turnering (`push_preferences` med `competition_id`).
   - `push-send` (Edge Function) må tåle begge formene i overgangen.
4. **Venteliste og påmelding** gir egne hendelser (`waitlist_offer`, `entry_confirmed`) med mottakerliste = personen, som purringen i dag.

---

## 9. Lasttest (lokalt, 09.10.2026)

### 9.1 Oppsett

- **Database:** lokal Postgres 16.2 (pip-pakken `pgserver` i en venv i scratch, ingen global installasjon). Supabase-delene er etterlignet med `lokal/stub.sql`, og `auth.uid()` er byttet til Supabase sin utgave, som leser `request.jwt.claims` som json.
- **Migreringer:** 001–031 i samme rekkefølge som `sql/README.md`.
- **Data:** `sql/lokal/lasttest.sql`. Lastes på om lag 30 sekunder:

  | | Antall |
  |---|---|
  | Brukere | 1 000 |
  | Arenaer | 50 (30 simulatorsentre, 15 golfklubber, 5 gjenger) |
  | Medlemskap | 1 480 |
  | Turneringer | 200 (sesong, liga, morro og cup per arena) |
  | Spilledager | 5 000 |
  | Runder | 22 000 (20 000 klubbrunder i 4 puljer per spilledag, og 2 000 løse) |
  | Spillere i runder | 168 000 |
  | Hullscorer | 3 024 000 |
  | Aktivitetslinjer | 111 000 |
  | Trådmeldinger | 50 000 |
  | Påmeldte | 3 000 |

- **Måling:** hver spørring kjøres 7 ganger med `EXPLAIN (ANALYZE)`, og tabellen viser medianen av planlegging og kjøring. Spørringene kjøres som en vanlig spiller i to klubber (RLS på, slik PostgREST kjører dem) og som postgres (uten RLS).
- **Forbehold:** tallene er databasetid på en rask Mac uten nettverk og PostgREST. Supabase Free/Micro har 2 delte kjerner, så forvent 2–5 ganger lengre tid der. Det er forholdet mellom tallene som teller.

### 9.2 Resultater: spørringene appen gjør i dag

| # | Spørring (slik appen gjør den) | Rader | Med RLS (ms) | Uten RLS (ms) |
|---|---|---:|---:|---:|
| 1 | Tavla: sesongene i klubben | 1 | 0,07 | 0,02 |
| 2 | Tavla: kveldene i sesongen | 25 | 0,14 | 0,02 |
| 3 | Tavla: troppen | 26 | 0,17 | 0,02 |
| 4 | Tavla: rundene i kveldene | 100 | 0,50 | 0,08 |
| 5 | Tavla: spillerne i rundene | 800 | **35,0** | 0,15 |
| 6 | Tavla: matchene | 400 | **17,6** | 0,12 |
| 7 | Tavla: sidepremiene | 200 | 8,8 | 0,09 |
| 8 | Tavla: hullscorer for én runde (appen gjør 100 slike) | 144 | 6,3 | 0,04 |
| 9 | Tavla: hullscorer for 100 runder i én spørring | 14 400 | **636** | 1,95 |
| 10 | Tavla via turneringen: koblingene | 100 | 8,7 | 0,02 |
| 11 | Hjem: aktiviteten siste 30 dager (150) | 150 | **24,3** | 0,13 |
| 12 | Hjem: troppene | 52 | 0,26 | 0,02 |
| 13 | Hjem: reaksjonene | 19 | 0,36 | 1,38 |
| 14 | Hjem: låste klubbrunder siste 30 dager (40) | 40 | 0,38 | 0,08 |
| 15 | Hjem: hvilke av dem du spilte | 11 | 0,60 | 0,06 |
| 16 | Hjem: koblingene for rundene | 40 | 3,7 | 0,04 |
| 17 | Hjem: trådmeldinger der du er nevnt | 2 | 2,0 | 0,52 |
| 18 | Turneringer: alle du ser (uten filter, RLS filtrerer) | 8 av 200 | **18,7** | 0,10 |
| 19 | Turneringer: påmeldte | 120 | 5,1 | 0,03 |
| 20 | «Folk du kjenner»: `profiles` uten filter | 51 av 1 000 | **106** | 0,07 |
| 21 | Løse runder: dine (uten filter, RLS filtrerer) | 8 av 2 000 | **29,0** | 0,99 |
| 22 | Kveld: pågående runde i klubben | 1 | 0,10 | 0,03 |

**Å åpne Tavla én gang** koster om lag **700 ms databasetid**: spørring 1–7 og 100 × spørring 8. Det er **106 HTTP-kall**. Uten RLS ville det tatt om lag 5 ms.

### 9.3 Funnene

1. **RLS per rad er flaskehalsen, ikke datamengden.** Alle indeksene treffer. Kostnaden er hjelpefunksjonen policyen kaller for hver rad: `can_read_round(round_id)` for hver hullscore, spiller, match og sidepremie, og `can_see_profile` for hver profil. Det koster 25–45 µs per rad. Tre millioner hullscorer gjør ingenting med tiden; det gjør antall rader som returneres.
2. **«Hent alt og la RLS filtrere» vokser med hele tabellen**, ikke med det du ser. Dette gjelder `profiles` (spørring 20), løse runder (21) og turneringslista (18). Ved 100 000 brukere tar `profiles`-spørringen i størrelsesorden 10 sekunder.
3. **Et filter i spørringen hjelper ikke** når policyen er dyr. Postgres sjekker RLS før filtre som ikke er «leakproof» (spørring 24 og 26: 18 og 29 ms).
4. **En manglende indeks:** `is_competition_participant` slår opp påmeldte per turnering. Indeksene fra 017 er delindekser (bare medlem eller bare profil), så oppslaget ble en full gjennomgang per turnering. 031 legger til `competition_participants (competition_id)`.
5. **Å skrive policyen om til `EXISTS` mot `rounds`** gjør spørringen per runde 8 ganger raskere (6,3 → 0,75 ms). Men med 100 runder i én spørring velger planleggeren en plan som tar 4,4 s. Den varianten er for skjør.

### 9.4 Forslag, målt på samme data

| Forslag | Før (ms) | Etter (ms) | Trinn |
|---|---:|---:|---|
| **Tavla-data i én RPC** (`tavla_data(competition_id)`): tilgangen sjekkes én gang, og rådata for turneringens startede runder kommer i ett svar. Tabellen regnes **fortsatt på telefonen**, så pariteten står | ~700 (106 kall) | **26** (1 kall) | Fase 24, kan tas i fase 23 |
| «Folk du kjenner» som én mengde (RPC) | 106 | **0,95** | Trinn 2 |
| Dine løse runder som én mengde (RPC) | 29 | **1,7** | Trinn 2 |
| `is_competition_participant` som mengde (med indeksen fra 031) | 18,7 | **4,0** | Trinn 2 |
| Indeks `competition_participants (competition_id)` | 23,4 | 18,7 | **031** |
| Indeks `rounds (club_id, locked_at desc) where status = 'locked'` (Hjem) | 0,64 | 0,38 | **031** (vokser med antall runder per klubb) |
| Indeks `events (season_id, event_date)` | 0,15 | 0,14 | Forkastet: ingen gevinst |

Prototypene ligger i skjemaet `lasttest` i `sql/lokal/lasttest.sql`. De er ikke ferdige: `kontakter()` mangler for eksempel blokkering.

### 9.5 Videre lasttest (fase 24)

1. **Lokalt, ×10:** endre tallene i avsnitt 1–6 i skriptet (10 000 brukere, 500 arenaer). Se at spørring 20 og 21 vokser lineært, og at RPC-ene ikke gjør det.
2. **Gjennom PostgREST:** kjør en lokal Supabase-stakk (`supabase start` i en egen mappe, ikke i repoet) med k6 eller `oha` mot REST-endepunktene, for eksempel 200 samtidige «åpne Tavla». Da kommer nettverk, json og tilkoblingspool med.
3. **Et eget gratis Supabase-prosjekt:** gratisplanen har trolig høyst to aktive prosjekter per organisasjon. Har test og prod begge plassene, må lasttestprosjektet ligge i en egen organisasjon, eller ett prosjekt må pauses. Aldri test eller prod.
4. **Realtime:** `postgres_changes` sjekker RLS for **hver abonnent** ved hver endring. Ti tilskuere på en runde med 32 spillere gir 32 × 18 × 10 RLS-sjekker per runde. Mål det i trinn 2–3. Alternativet er Broadcast (en trigger sender endringen til en kanal per runde eller turnering, og tilgangen sjekkes én gang når du blir med).

---

## 10. Migreringsplan i trinn

Hvert trinn kjøres først på **test**, med kontrollen nederst i fila og paritetskontrollen under, og så på **prod** etter ny godkjenning. Golfgutu-dataene flyttes aldri. De får nye kolonner som fylles fra det de har.

| Trinn | Fil | Hva | Krever | Additivt? |
|---|---|---|---|---|
| **1** | `031` (nå) | Kolonner, tabeller, indekser og triggere ved siden av de gamle. Kveldene får turneringen sin. `app_config.min_ios_build` | 001–030 | **Ja**. Dagens app merker ingenting |
| **2** | `032` (fase 23) | Rettighetene for stab, åpen påmelding og deltakere. RPC-ene: påmelding med tak, vindu og venteliste, tilbud, stab, startliste i én transaksjon, ny spilledag i turneringen. Mengdebaserte hjelpere og RPC-er fra lasttesten | 031 + app fase 23 bak flagg | Ja for Golfgutu: svarene er like for hver innlogging (kontroll som 017/9) |
| **3** | `033` (fase 23) | Speilingen snus: turneringen er kilden, `seasons` følger. `activate_season` avslutter bare forrige hovedturnering. Nye serier blir ikke hovedturnering. Koblingen runde → turnering via `events.competition_id` for alle turneringer | 032 + appen leser via turneringen | Ja for Golfgutu: samme Tavla (paritetskontrollen) |
| **4** | `034` (etter `min_ios_build`) | **Ikke-additivt:** `rounds_one_active_per_club`, `seasons_one_active_per_club` og `events_one_per_date` fjernes. Ikke-medlemmer i klubbrunder. `activity.club_id` og `push_queue.club_id` blir valgfri, med push per turnering. `bay_no` opp til 99 | Alle i bruk har fase-23-bygget (`min_ios_build` satt) | Nei: gamle bygg må være stengt ute |
| **5** | `035` (senere) | `seasons` blir et view. `events.season_id` og `bets.season_id` peker på turneringen. Rydding | Ingen klient leser `seasons` | Nei |

### 10.1 Golfgutu på test og prod

- **Test** har i dag 2 klubber, 1 sesong, 3 kvelder, 5 runder og 300 hullscorer. Golfgutu-historikken er ikke importert ennå (fase 9). 031 fyller `events.competition_id` for de 3 kveldene og `activity.competition_id` der det går.
- **Prod** er ikke tatt i bruk. Anbefalt rekkefølge:
  1. kjør 001–031 på prod,
  2. importer Golfgutu (fase 9, `Packages/DashImport`, uendret),
  3. triggerne fyller `competition_id` på kveldene og kobler rundene, akkurat som 017-triggerne gjør for konkurransene,
  4. kjør trinn 2 og 3 når fase 23 er klar.

  Importeres Golfgutu **før** 031, fyller 031 det samme i etterkant. Begge veier er prøvd lokalt (`031_for.sql` lager verdenen før 031, og A4/B7 i prøven lager kvelder etter).

### 10.2 Paritetskontroll: Tavla før = etter

Kjøres **før og etter hvert trinn** på test (og prod). Den er en ren `select`. Den gir et fingeravtrykk per sesong av alt Tavla bygger på, hentet både slik dagens app gjør det (via `events.season_id`) og via turneringen (`competition_rounds`). Svarene skal være **like i de to kolonnene**, og **like før og etter trinnet**.

```sql
with grunnlag as (
  select s.id as season_id, s.name,
         (select md5(coalesce(string_agg(h.round_id::text || h.member_id || h.hole_index || ':' || h.strokes, ','
                                         order by h.round_id, h.member_id, h.hole_index), ''))
            from public.hole_scores h
            join public.rounds r on r.id = h.round_id
            join public.events e on e.id = r.event_id
           where e.season_id = s.id and r.status in ('active', 'locked')) as via_sesong,
         (select md5(coalesce(string_agg(h.round_id::text || h.member_id || h.hole_index || ':' || h.strokes, ','
                                         order by h.round_id, h.member_id, h.hole_index), ''))
            from public.hole_scores h
            join public.rounds r on r.id = h.round_id
            join public.competition_rounds cr on cr.round_id = r.id
            join public.competitions c on c.id = cr.competition_id
           where c.season_id = s.id and cr.source = 'season' and r.status in ('active', 'locked')) as via_turnering,
         (select count(*) from public.round_players p join public.rounds r on r.id = p.round_id
            join public.events e on e.id = r.event_id
           where e.season_id = s.id and r.status in ('active', 'locked')) as spillere,
         (select count(*) from public.round_matches m join public.rounds r on r.id = m.round_id
            join public.events e on e.id = r.event_id
           where e.season_id = s.id and r.status in ('active', 'locked')) as matcher,
         (select count(*) from public.side_claims c2 join public.rounds r on r.id = c2.round_id
            join public.events e on e.id = r.event_id
           where e.season_id = s.id and r.status in ('active', 'locked')) as sidepremier,
         md5(s.rules::text) as regler
  from public.seasons s
)
select *, via_sesong = via_turnering as lik from grunnlag order by name;
```

I tillegg:

- **I appen:** `KonkurranseJakkeracetTests` (tabellen via turneringen = tabellen fra sesongen) og `Parity.swift` mot PWA-ens `round_points` etter importen.
- **Per innlogging:** `lokal/031_prove.sql` A1–A2 sammenligner alt dagens app henter, med kolonnelistene appen bruker, og `updated_at` på kveldene. Det gjøres for fem innlogginger før og etter. Den samme metoden brukes i trinn 2–4.
- **Manuelt på telefon etter hvert trinn på test:** åpne Tavla, Hjem og Kveld, før et hull, og lås en runde.

---

## 11. 031: hva den gjør, og hvorfor den er trygg for dagens app

**Innhold** (detaljer i kommentaren øverst i fila):

1. `app_config` med `min_ios_build = 0`.
2. `clubs.kind`.
3. Sju kolonner på `competitions` med sjekker. Standardverdiene er de samme som før.
4. `competition_staff` med vakt (`added_by` settes av serveren, og du kan bare legge til folk du kjenner) og RLS.
5. `competition_waitlist` (bare lesing).
6. `events.competition_id`:
   - fylt for alle kvelder i en sesong, uten å røre `updated_at`;
   - sammensatt fremmednøkkel, så turneringen må være i samme klubb;
   - unik (turnering, dato);
   - trigger begge veier;
   - `competition_rounds_sync_event` fyrer også på `competition_id`.
7. `rounds.wave_no` og den nye unike indeksen per spilledag og pulje.
8. `round_start_groups`.
9. `activity.competition_id`: fylt for det som finnes, trigger for nye linjer, sammensatt fremmednøkkel og indeks.
10. `is_competition_staff()`.
11. To indekser fra lasttesten.

**Hvorfor dagens app ikke merker noe:**

- Appen henter **navngitte kolonner** (`*.columns` i `Rows.swift` og `FoundationRows.swift`). Nye kolonner kommer ikke med i svarene. `select *` brukes ikke mot disse tabellene.
- **Ingen ny verdi** i kolonner appen dekoder strengt (`status`, `kind`, `entry`, `source`). Ventelista er derfor en egen tabell.
- **Ingen policy og ingen hjelpefunksjon fra 001–030 endres** (kontroll 7). De gamle unike reglene står (kontroll 3). Det appen får 23505 på i dag, får den fortsatt (A6 og de tre `23505` i prøven).
- **Triggerne setter bare de nye kolonnene.** De kaster ingen nye feil i dagens flyt. Unntaket er fremmednøklene, som bare kan feile når noen setter de nye kolonnene feil, og det gjør ikke dagens app. En kveld med `season_id` får turneringen sin, og en kveld uten sesong får ingen, som før.
- Utfyllingen av kveldene slår av `events_set_updated_at` i transaksjonen, så **`updated_at` flytter seg ikke**. Appen bruker den til å se endringer. A1 sammenligner den.
- **Låser:** `ADD COLUMN` med konstant standardverdi er bare metadata. Indeksene og fremmednøklene bygges på hundrevis av rader på millisekunder. Med store tabeller senere bør indeksene lages `concurrently` utenfor transaksjonen.
- **Rullebakken** er nederst i fila og prøvd lokalt: rull tilbake, kjør 031 på nytt, og kontrollen gir 12 av 12.

**Lokal prøve (09.10.2026):**

- 001–030 og `lokal/031_for.sql`, så 031 **to ganger på rad** uten feil.
- `lokal/031_prove.sql`: 78 linjer, alle `ok`:
  - **A:** samme bilde og Tavla for alle fem innlogginger, og de gamle 23505-reglene står;
  - **B:** spilledag ↔ sesong begge veier, rundene følger, fremmed klubb avvist (23503), aktivitet koblet, stab og venteliste med RLS, startliste, sjekkene og `app_config`;
  - **C:** trinn 4 i det små.
- Kontrollblokken fra fila: 12 av 12.
- Eldre rolleprøver med 031 kjørt: 019 (89 ok), 022 (182 ok), 023 (50 ok), 024 (39 ok), 025 (38 ok), 029 (44 ok), 030 (53 ok). Ingen `FEIL`.

---

## 12. Fase 23 og 24 (ikke bygget)

### Fase 23: appen

1. **Minste appversjon:** les `app_config.min_ios_build` etter innlogging, og vis «Oppdater Atten» under den. Det må ut tidlig, så trinn 4 kan gjøres trygt.
2. **Turneringen i sentrum:**
   - turneringsvelger på Tavla og arrangørsiden; arrangørsiden lander på turneringen du styrer, ikke på klubbens hovedturnering;
   - «Ny spilledag» i turneringen (`events.competition_id`);
   - «Pågår nå» viser alle runder du spiller i eller arrangerer.
3. **Arrangør per turnering:** «Stab» med legg til (folk du kjenner, eller via invitasjon) og roller (arrangør, funksjonær).
4. **Påmelding:**
   - tak, venteliste og vindu i «Ny turnering»;
   - «Meld meg på» viser «Du står som nr. 3 på ventelista»;
   - tilbud om plass med frist og push;
   - åpen for ikke-medlemmer: lenke, kode og arenaens offentlige liste.
5. **Startliste:**
   - grupper med tid, starthull og bås eller simulator;
   - ekte bane: tee-tider med fast mellomrom og kanonstart;
   - simulatorsenter: båsene som faste valg;
   - pulje (`wave_no`) i runde-oppsettet når to runder skal gå samtidig.
6. **Deltakere som ikke er medlemmer:** `PersonDirectory` og `round_roster` (finnes) i klubbrunder, og tabellen regnes med profiler.
7. **Hjem:** filter per turnering via `activity.competition_id`, og turneringer du deltar i uten medlemskap.
8. **Tavla via turneringen** (`CompetitionScope.tavlaInput`, bevist lik). Helst gjennom RPC-en `tavla_data` (fase 24 punkt 1), som kan tas allerede her.

### Fase 24: server, lasttest og sanntid

1. **Tavla-data i én RPC** (målt 700 → 26 ms og 106 → 1 kall). Tabellen regnes fortsatt på telefonen, så pariteten står.
2. **En lagret tabell (valgfritt):** et øyeblikksbilde av poeng per spiller og låst runde (`round_results`), skrevet når runden låses. Det gjør lister, feed og widgets billige. Det er en bevisst avledet verdi (CLAUDE.md), og pariteten sjekkes ved å regne på nytt på telefonen.
   - **Alternativ:** regn tabellen på serveren i en Edge Function med en TypeScript-utgave av regelmotoren, testet mot de samme JSON-fixturene som GolfgutuCore. Det er mer arbeid, men gir én fasit for Android også.
3. **Mengdebaserte RPC-er:** «folk du kjenner», mine løse runder, turneringslista og Hjem-feeden. `is_competition_participant` skrives om. Policyene bruker `(select auth.uid())`.
4. **Lasttest** gjennom PostgREST og i et eget gratis prosjekt (kap. 9.5). Mål før Pro.
5. **Sanntid:** Broadcast per runde og turnering i stedet for `postgres_changes` på `hole_scores`. Live Tavla oppdateres fra endringen i runden, ikke med en ny full henting.

---

## 13. Risikoer og hva som må testes

| Risiko | Tiltak |
|---|---|
| Gamle bygg i bruk når trinn 4 fjerner reglene. To aktive runder i en klubb, og gamle «klubbens pågående runde» viser feil runde | `min_ios_build` (031) ut i fase 23, og trinn 4 først når alle har oppdatert. Sjekk `push_devices`/innlogginger per bygg før |
| Ikke-medlemmer i klubbrunder (trinn 4): gamle bygg finner ikke navnet i troppen | Samme som over. Den nye appen bruker `round_roster` |
| Trigger begge veier (sesong ↔ turnering) i ring | Trinn 1 har én retning per kolonne, og sesongen vinner. Trinn 3 får sperre med `pg_trigger_depth()`, og prøven må dekke alle kombinasjoner |
| `competitions_one_main_active`: en ny aktiv sesong i en klubb med aktiv hovedturnering stopper (23505) | Trinn 3 setter `is_main` bare når klubben ikke har en aktiv (prøvd i C) |
| RLS-kostnaden vokser med antall rader og tilskuere (kap. 9) | RPC-ene i fase 24 må komme før store arenaer tas inn. Lasttest gjennom PostgREST |
| Realtime per abonnent | Mål i fase 24. Broadcast som plan B |
| Venteliste: to tar siste plass samtidig | RPC med `for update` på turneringen. Prøv med to samtidige økter lokalt |
| Åpne turneringer (`anyone`, `listed`) eksponerer navn | Ikke-deltakere ser bare turneringsraden og tabellen, ikke runder eller tropp. Blokkering (019/025) gjelder påmelding. Rapportering av turneringsnavn |
| Spam: mange turneringer, påmeldinger og stab | Kvoter i `quota_guard` (024) for `competition_staff`, `competition_waitlist` og påmeldinger i trinn 2 |
| Store indekser låser tabeller på prod senere | `create index concurrently` utenfor transaksjonen når tabellene er store |
| Paritet for Golfgutu | Paritetskontrollen (10.2), `KonkurranseJakkeracetTests`, `Parity.swift` og manuell kveld på telefon etter hvert trinn |

**Må testes per trinn:**

- kontrollblokken i fila;
- paritetskontrollen før og etter;
- rolleprøven lokalt (alle tidligere `lokal/*_prove.sql` uten `FEIL`);
- appen mot test: innlogging, Tavla, Hjem, Kveld, føring, lås og ny kveld;
- trinn 2: to arrangører i samme turnering, en funksjonær som fører, påmelding til tak, venteliste og tilbud, og en ikke-medlem som melder seg på og ser runden;
- trinn 4: to turneringer med runder samtidig i samme arena, to puljer samme kveld, og push til en ikke-medlem.

---

## 14. Beslutninger Thomas må ta

1. **Godkjenne 031 for test.** Den er additiv og trygg for dagens app, og prøvd lokalt.
2. **Pulje:** er `wave_no` riktig grep for «flere runder samtidig på samme spilledag»? Alternativet er ingen regel i det hele tatt og bare et varsel i appen.
3. **Åpne turneringer, hva kan andre se:**
   - forslag: `listed` + `anyone` viser navn, tid, sted, ledige plasser og tabellen for alle innloggede;
   - rundene og hullscorene ser bare deltakerne;
   - stemmer det?
4. **Venteliste:**
   - forslag: tilbud med frist på 24 timer før spilledagen og 2 timer samme dag;
   - automatisk påmelding uten tilbud når fristen er kort?
5. **Funksjonær (`scorer`):** skal en funksjonær kunne føre for alle, eller bare for gruppene hen er satt på?
6. **Hovedturnering for arenaer:** skal et simulatorsenter ha en hovedturnering (den som vises først), eller ingen?
7. **Tavla i fase 24:** én RPC med rådata (pariteten står, anbefalt først), eller lagrede poeng per runde, eller en serverutgave av regelmotoren (mest arbeid, én fasit for Android)?
8. **Lasttestprosjekt:** egen gratis organisasjon for lasttest i Supabase, eller vente med lasttest gjennom PostgREST til Pro?
9. **Når trinn 4 kan tas:** kreve at alle i gjengen har fase-23-bygget (TestFlight) før `min_ios_build` settes. Er det greit at gamle bygg da må oppdateres?


## Besluttet 09.10.2026 (Thomas: «Ja, alt er fint»)

1. 031 kjøres på test. *(Kjørt 09.10: kontrollen 12 av 12, paritetskontrollen identisk før og etter, lagring av runder og kvelder prøvd.)*
2. Flere runder samtidig på samme spilledag deles i **puljer** (`rounds.wave_no`).
3. **Åpne turneringer:** alle innloggede ser turneringen og tabellen. Bare deltakerne ser runder og hull.
4. **Venteliste:** et tilbud om ledig plass gjelder i **24 timer**, så går det videre.
5. **Funksjonærer** fører bare for gruppene de er satt på. Arrangøren fører for alle.
6. **Hovedturnering** er valgfritt for arenaer. Golfgutu beholder sin.
7. **Tavla (fase 24):** først én RPC med rådata (telefonen regner, pariteten står). Lagret tabell senere.
8. **Lasttest i Supabase:** egen gratis organisasjon, tas i fase 24.
9. **Trinn 034** tidligst når alle i Golfgutu-gjengen har et bygg fra fase 23 (`min_ios_build`).
