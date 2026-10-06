# SPEC: DashDash18

Kartlegging av GolfGutu-PWA-en (`referanse/golfgutu-pwa/`) som grunnlag for en native iOS-klient mot samme Supabase-database. PWA-en er fasit for funksjon og regler. Ingen Swift-kode her.

## Om grunnlaget

Kilder: `README.md` (hele), `db-nytt.js` (hele), `db.js`, alle 52 filer i `sql/`, `app-nytt.js` (kjerneflytene), `_worker.js`, `sw.js`, og skjermbildene i `docs/skjermbilder/png/` og `bred/`.

Kjente forbehold:

- **`app-nytt.js` er ikke lest linje for linje** (10 681 linjer). Kjerneflytene er lest. Tips-UI, plakat, tråd og deler av klubb-oppsett er bare delvis lest.
- **Skjermbildene er eldre enn koden.** De viser blant annet bank og saldo, som ble fjernet 02.10.2026. Bruk dem som visuell referanse, ikke som fasit.
- **README er en dagbok, ikke en ren spec.** Eldre avsnitt er overstyrt av senere (se 5.4). Der README og kode er uenige, gjelder koden.
- **Basetabellene finnes ikke som `CREATE TABLE` i `sql/`.** Kolonnene er kjent fra ALTER-filer, kode og kommentarer. Se 3.5.
- Avsnitt merket **(uavklart)** må sjekkes mot kilden eller den levende databasen før de bygges.

---

## 1. Skjermer

PWA-ens navigasjon (siden 18.09.2026): tre faner **Kveld · Penger · Tavla**, pluss en stabel av undervisninger («‹ tilbake») og overlegg (ark, feiring, toast). Bjelle i headeren åpner Varsler. Eldre tekst snakker om fanen «Mer» (5 faner → 2 → 3). Den finnes ikke lenger, men grupperingen under følger din inndeling:

- **Kveld**: alt som hører til en kveld, fra påmelding til avslutning.
- **Mer**: alt annet (Penger, Tavla, Deg, Varsler, Sesong, Arrangørsiden for klubbdrift).

### 1.1 Før appen åpnes (innlogging og onboarding)

| Skjerm | Funksjon | Native |
|---|---|---|
| Porten / velkomst | Tvinger installasjon på hjemskjermen (iOS/Android) før bruk. Nødutgang «Jeg får det ikke til». | **Bortfaller** |
| Innlogging | E-post, så engangskode (6 eller 8 siffer, innstilling i Supabase). Ikke magic link. | Beholdes |
| Velg navn / «Bli med» | Etter innlogging uten spillerrad: ta en ledig tropprad (`players.user_id` settes), eller opprett ny med navn og handicapindeks (0–54, komma godtas). | Beholdes |
| «Vi kjenner deg ikke igjen» | Feil e-post. Arrangør kan frigjøre en innlogging («Logget inn med feil e-post?»). | Beholdes |

### 1.2 Kveld

| Skjerm | Funksjon |
|---|---|
| **Kveld, rolig** (ingen runde i gang) | «Neste runde»-kort (dato, tid, sted, nedtelling, sosialkomité). Svarkort: Kommer / Usikker / Kommer ikke + kommentar (maks 80 tegn), arrangør kan purre. Kalenderabonnement. Tippekupong-kort. Kveldens tråd. Topp 3 i Jakkeracet + egen rad. Siste aktivitet med reaksjoner. Når alle runder er låst, rykker neste kveld opp (`kveldErFerdig`). |
| **Kveld, spill** (runde i gang) | Hullprikker (18 piller, LD/KP-merker), hullkort, «Bayen nå» (live-liste, sortert på netto eller matchstilling, «Vedd»-knapp per spiller), matchkort, LD-/KP-bokser på riktig hull, lenke til alle veddemål, tråd og tips. |
| **Par-bekreftelse** | Før føring: «Stemmer dette med skjermen?» Alle hullbokser med par, «Dette stemmer — start føringen». Blokkerer hullkortet til det er gjort (`parErBekreftet`). |
| **Hullkort** | Par, meter, stroke index, LD/KP-merke. Én rad per spiller i båsen med −/+ stepper, «N slag fått», regnestykket «5 brutto − 1 = 4 netto», score-merke (Eagle/Birdie/Par/Bogey/Dobbel/Blowup) og poeng. Standardverdi er par (stiplet). Hver spiller må bekreftes med trykk. «Lagre hull N → hull N+1» låses til alle i båsen er ført. Én lagring og én feiring per hull. |
| **Seer-modus** | Ikke-markør ser bås live uten stepper: «Bås 1 · Thomas fører · du ser det live», «Feil tall? Si det til [markør]». Linjen finnes med vilje: uten den trykker folk på en knapp som ikke er der. |
| **Sol-stripe** | «Du ser på hull X. Båsen er på hull Y», med hopp. Hullkortet følger båsen når noen lagrer (`baasensHull`, `folgerBaasen`). |
| **Scorekort** | Ut/Inn-bryter, par/slag/poeng per hull, SUM. Trykk for å rette (arrangør). |
| **Rett en score** | Arrangør (eller den som ikke er markør) velger spiller og hull. Logges «rettet hull … a → b», uten feiring. |
| **Feiring** | Fullskjerm per hull: birdie 1,5 s, eagle 2,3 s, albatross 2,9 s, hole in one (brutto 1) 5,2 s med konfetti. Utløses av **netto** mot par. Respekterer redusert bevegelse. |
| **Vedd-ark** | Hull-duell, «holder par på hull N», «slår X netto i runden», «kommer på pallen» (fritekst). JA/NEI, 50/100/200 kr. Blir i hullet etter opprettelse (toast med «Se →»). |
| **Longest drive / nærmest pinnen** | Spilleren melder egen lengde i meter (arrangør kan melde for andre). Én per runde per type. |
| **Matchkort** | Viser hull opp/ned («2 opp etter 3»), ikke poeng, når runden har matcher mellom to sider. Trekant viser poengsum. |
| **Kveldens tråd** | Chat per dato (1–500 tegn, @navn, bilde komprimert til 1600 px JPEG). Push per spiller: Alle / Når jeg nevnes (standard) / Av. |
| **Tippekupong** | Fem spørsmål per kveld (se 4.7). Låses ved starttid eller første slag. Andres tips skjules til låsing. |
| **Start runde** (arrangør, veiviser i 3 steg) | 1: bane, dato, første tee. 2: hvem (fra påmelding) og båser, automatisk fordeling, markør, flytt via ark. 3: 9/18 hull, LD-/KP-hull (med forslag), rundevekt (×1, ×2, 0), konkurranseform, lag, matcher, «Avansert» (antall båser, Trackman/app-fordelte slag). Lagrer som **kladd** eller starter. |
| **Rediger kladd** | Åpner veiviseren med alt lagret. Kladdene startes etter tur. |
| **Båser og markører** | Én markør per bås. Dra-og-slipp i bred modus. |
| **Matchene** | Settes for hånd: hver spiller på match + side, lag utledes. |
| **Innstillinger for runden** | Bytt bane (poeng regnes om), «Appen fordeler» eller «Trackman fordeler» slag, LD-/KP-hull, vekt, par-bekreftelse. |
| **Avkort runden** | Tre regler (4.5). Bekreftelsen viser effekt per spiller («Anders 36 → 28 (−8)») og åpne hullveddemål utenfor kuttet. |
| **Avslutt kvelden** | Spør om avkorting hvis noen mangler hull, låser runden, avgjør veddemål, avregner poster, kunngjør tippekonge. |
| **Rundene** | Hele runden som tabell spillere × hull. Rett også i låst runde (logges med gammelt/nytt tall). |
| **Slett runde** | To trykk, teller opp hva som følger med. Kun ulåst runde. |
| **Plakat** | Canvas 1080×1440 med bane, matcher, båser, portretter. Deles som PNG. |

### 1.3 Mer

| Skjerm | Funksjon |
|---|---|
| **Penger** | «Du skal betale» / «Du får», per motpart nettet. Betal med Vipps (personlig QR-lenke, tar ikke beløp), «Betalt Vipps/Annet», «Mottatt», «Ikke mottatt?». Åpne og avgjorte veddemål. Utlegg. Regnestykke-ark per motpart. Oppgjort-liste. |
| **Veddemål** | Parimutuel JA/NEI, tak 200 kr per spiller per veddemål. Kan avgjøres automatisk fra score, ellers manuelt av arrangør. |
| **Utlegg** | Sosialkomiteen melder utlegg (innen 21 dager), arrangør godkjenner, utlegget fordeles på deltakerne som poster. |
| **Tavla / Jakkeracet** | Én tabell over alle spillere. «Slik telles det». Rader til Sesongen, Deg, Arrangørsiden. Delknapp. |
| **Spillerprofil** | Poeng, stableford, snitt, beste runde, birdies, lengste drive, runde for runde, innbyrdes mot deg, «Utfordre til veddemål». |
| **Sesongoppsummering** | Mester, pall med premie, bøtekasse, beste runde, største gevinst/tap, mest bøtelagt. |
| **Deg** | Portrett (600 px), handicapindeks, Vipps-nummer, push, kalenderabonnement, arrangørliste, bøter, terminliste, logg ut. |
| **Varsler** | Aktivitetslogg «I dag / Tidligere», ulest per enhet, reaksjoner (👍😂⛳🔥❤️), dyplenker, «Svar på veddemål». |
| **Arrangørsiden** | Statusliste og «Avslutt kvelden» øverst, «Under kvelden», «Mellom kveldene» (Rundene, Klubb-oppsett, Plakat, Melding til alle, Hvem har push, Hva blir push). |
| **Klubb-oppsett** | Spillerne (tropp, seeding, frigjør innlogging), Banene (par/indeks/CR/slope, bekreftelse), Terminliste (+ sosialkomité, tipsinnsats/-linje), Bøtekasse, Arrangører, kasserer. |
| **Bøter** | Typer: Forsentkomst 100, Kverulering 50, Usportslig 200, Annet. Arrangør gir og merker betalt. Går til `kassa`. |

Bred modus (≥ 900 px, kun arrangør) gir sidemeny og flerkolonne. Relevant for iPad, ikke for iPhone.

---

## 2. Flyten for en kveld

Kveld = én dato i terminlisten. En kveld kan ha flere runder (typisk første og siste ni, to rader i `rounds` med samme dato). Påmelding gjelder datoen.

### 2.1 Påmelding
1. Arrangør legger kvelden i terminlisten (`schedule`: dato, klokkeslett som fritekst, sosialkomité).
2. Påminnelse en uke før går som push (pg_cron 08:05 UTC, `send_paaminnelser()`).
3. Spiller svarer Kommer / Usikker / Kommer ikke (+ kommentar) i `signups`. Bare «kommer» forhåndsvelger deltakere i veiviseren.
4. Arrangør kan purre dem som ikke har svart (`activity_log`, kategori `purring`, `til` = de som mangler). Uten `til` sendes purring aldri.

### 2.2 Kladd
1. Arrangør setter opp runden som **kladd** (`rounds.kladd = true`): bane, tee, deltakere, båser og markør, form, lag, matcher, LD-/KP-hull, vekt, 9 eller 18 hull, `hcp_extern`.
2. Kladder er usynlige for andre og gir ingen aktivitetslogg eller push.
3. En kveld kan ha to kladder. De startes etter tur, og nummer to nektes mens første går.
4. Kladden hoppes over av `activeRound()`. Den dukker ikke opp av seg selv ved dato.

### 2.3 Start og par-bekreftelse
1. «Start runden» setter `kladd = false`, logger «Ny runde» (push).
2. Blokkeres hvis en annen runde er i gang.
3. Før føring bekrefter noen at par stemmer med Trackman-skjermen (`par_bekreftet_av/at`, og `course_holes` + `courses.bekreftet_*` oppdateres).

### 2.4 Føring per bås
1. Én **markør** per bås fører brutto per hull for alle i båsen. De andre ser live.
2. Skrivereglene (`kanFore`, speilet av RLS, se 3.3):
   - arrangør kan alltid skrive (også i låst runde);
   - låst runde: ingen andre;
   - uten bås eller uten markør: spilleren fører selv;
   - med markør: **bare markøren**, ikke spilleren selv.
3. Hullkortet viser alle fire. Hver spiller må tappes (starter på par) før «Lagre hull» låses opp.
4. Lagring (`saveHoleScore`, se 4.9): upsert i `hole_scores`, regn om fra databasen, skriv `round_points`. Tre forsøk med 400 ms backoff.
5. Etter lagring: feiring, aktivitetslogg (store scorer; ledelse etter hull 3/6/9/12/15/18), automatisk avgjørelse av veddemål (kun på arrangørens enhet).
6. LD og KP meldes inn av spilleren selv i meter.

### 2.5 Veddemål
1. «Vedd» ved en spiller i bayen, eller fra profil/Penger.
2. Hullveddemål (`birdie`, `par`, `hull`) stenger når hull N−1 er ført (forsprang 1, `veddemaal_tar_innsatser` i DB). Andre typer stenger ved første slag i runden.
3. Innsats 50/100/200, tak 200 per spiller per veddemål (DB-trigger).
4. Autoavgjørelse fra score (`vilkaarUtfall`), ellers manuelt av arrangør. Likt gir ingen avgjørelse.
5. Oppgjøret blir `poster` når siste runde er låst (`avregnKvelden`).

### 2.6 Avslutning
1. Mangler hull ved kl 20: arrangør avkorter for alle (4.5).
2. «Avslutt kvelden» låser runden. Poeng, jakketavle og tips regnes fra scorene.
3. Når alle runder på datoen er låst, er kvelden ferdig (`kveldErFerdig`): veddemål og tippekupong avregnes til poster, tippekonge kunngjøres, neste kveld rykker opp.
4. Oppgjør: Vipps utenfor appen, status markeres i appen (`apen → betalt → oppgjort`).

**PWA-plikter som krever åpen app** (viktig for sameksistens, se 5): avgjørelse av veddemål (kun arrangørens enhet), `avregnKvelden`, `oppgjorNullPar`, `sendPaaminnelser` (poster eldre enn 3 dager). Hvis iOS-appen overtar disse, må den være idempotent likt PWA-en.

---

## 3. Supabase: tabeller og RLS-avhengigheter

Alt domene ligger i Supabase Postgres via PostgREST. Realtime og Storage brukes. Prod og test er to separate prosjekter. **`db.js` peker på prod.** Test-prosjektet (`tihudaeamrnrukjyplvf`) ligger i `test-overrides/supabase.env`. iOS-appen skal bruke test først (se CLAUDE.md).

### 3.1 Tabeller (effektivt skjema, utdrag)

| Tabell | Nøkkel / viktig |
|---|---|
| `players` | `user_id` (unik, null = ledig tropprad), `commissioner`, `handicap`, `seed_group` (1–3 → 0/5/10 slag), `phone`, `prat_push`, `bilde` |
| `rounds` | `game_type`, `hcp_allowance` (0–1), `hcp_extern`, `hole_count` (9/18), `hole_start` (0/9), `multiplier` (0–5), `longest_drive_hole_index`, `kp_hole_index`, `ld_aktiv`, `kp_aktiv`, `kladd`, `locked`, `par_bekreftet_av/at`, `avkortet_etter`, `avkort_regel` (`felles`/`nettopar`/`null`), `course_id` |
| `courses` | `par`, `course_rating`, `slope_rating`, `holes` (jsonb, eldre), `i_bruk`, `trackman_name`, `bekreftet_av/at`, `bilde` |
| `course_holes` | PK (`course_id`, `hole_number`), `par` 3–6, `hcp_index` 1–18, `distance_meters` 50–700. Unik (`course_id`, `hcp_index`), utsatt til commit |
| `hole_scores` | (`round_id`, `player_id`, `hole_index`) → `strokes`. Råsannhet |
| `round_points` | (`round_id`, `player_id`) → `points`. Denormalisert, skrives av klienten |
| `round_holes` | per-runde overstyring av par/indeks (og `meters` **(uavklart)**) |
| `round_bays` | (`round_id`, `player_id`) → `bay_no` 1–6, `er_markor`. Unik markør per (runde, bås) |
| `round_teams` | (`round_id`, `player_id`) → `team_no` 1–20 |
| `round_matches` | (`round_id`, `match_no`) → `player_a/b/c` eller `team_a/b`, `result` A/B/H |
| `markets`, `market_stakes` | `vilkaar` jsonb `{t, r, h, p, a, b}`, `lukket_at`, `mot`, `status`, `resolution`; innsats `side`, `amount` |
| `fines` | spiller, type, beløp, betalt |
| `side_claims` | `type` (`drive`/`kp`), `round_id`, `hole_index`, `meters` (>0, ≤500). Unik (`round_id`, `player_id`, `type`) |
| `schedule` | `date` (unik), `time` (fritekst), `social_1/2`, `tips_innsats`, `tips_linje`, `paaminnelse_sendt` |
| `signups` | (`schedule_id`, `player_id`) → `status`, `kommentar` ≤ 80 |
| `settings` (rad id=1) | `treasurer_id`, `kalender_token`, `finished`, `year`, premier, `push_av` (liste over kategorier som er **av**) |
| `poster` | `fra`, `til` (`kassa` mulig), `belop`, `kilde` (`vedd`/`bot`/`kupong`/`utlegg`), `kilde_id`, `status`, `betalt_*`, `metode`, `paaminnet_tid`. Unik (`kilde`, `kilde_id`, `fra`, `til`) |
| `utlegg` | (`dato_id`, `spiller_id`) → `belop`, `status` meldt/godkjent |
| `tips`, `tips_betalinger` | fem svar per spiller per dato |
| `meldinger` | tråd, `nevnt`, `bilde` |
| `activity_log`, `activity_reaksjoner` | logg (HTML-tekst med emoji-prefiks, også pushkø), `kategori`, `til` |
| `push_subscriptions` | web push (ikke relevant for APNs) |
| Legacy, ikke bruk | `bank_bevegelser`, `spiller_saldo()`, `settings.starting_bank`, `schedule.utlegg(_av)`, `allowed_emails`, `rounds.poengform` (fjernet) |

Storage: private bøtter `traad` (`<spiller>/<melding>.jpg`) og `klubbilder` (`spillere/…`, `baner/…`). Maks 3 MB, JPEG, signerte lenker (1 time). Ingen overskriving: nytt bilde får ny sti, gammelt slettes separat.

### 3.2 Grunnregler
- Alle innloggede leser alt (`select_authenticated`). **Anon får tomt svar, ikke feil.** Appen må logge inn før første henting.
- Skriving er arrangørens, unntatt eget (se under).
- RLS er eneste tilgangskontroll. PostgREST skiller ikke «RLS stoppet deg» fra «ingen rader». **Sjekk rader tilbake** (`.select('id')`) på update/delete.
- 23505 kan være unik-brudd og ikke RLS. Sjekk SQLSTATE før du konkluderer.

### 3.3 RLS-regler iOS-appen er avhengig av

1. **Score** (`hole_scores`, `round_points`; samme policy):
   `is_commissioner() OR (NOT round_is_locked(round_id) AND (baasen_har_markor ? er_markor_for : owns_player))`.
   Med markør i båsen kan **bare markøren** skrive, ikke spilleren selv. Låst runde blokkerer alle utenom arrangør. Lagsform: samme slag skrives for alle på laget, så regelen må slippe gjennom for hvert lagmedlem.
2. **`players`**: kun arrangør setter `commissioner` og `seed_group` (triggere). Egen rad: `user_id = auth.uid()`. Å ta en ledig rad: `update … where id = ? and user_id is null`, og sjekk at én rad kom tilbake. Å legge til navn uten bruker er arrangørens.
3. **`rounds`**: INSERT er åpent for alle innloggede (hull i RLS). UPDATE og DELETE er arrangørens (lås, kladd, vekt, par-bekreftelse, avkorting). Runder slettes **bare** via RPC `slett_runde(rid)` (arrangør, ulåst).
4. **`round_holes`, `round_bays`, `round_teams`, `round_matches`**: kun arrangør skriver.
5. **`market_stakes`** INSERT: `owns_player(player_id) AND veddemaal_tar_innsatser(market_id)`. Trigger: sum per (veddemål, spiller) ≤ 200. UPDATE/DELETE er arrangørens. Ingen saldosperre lenger.
6. **`markets`**: INSERT åpent. UPDATE/DELETE arrangørens, så autoavgjørelse virker bare fra arrangørens enhet.
7. **`side_claims`**: INSERT/DELETE for eier (eller arrangør) i ulåst runde. Rettelse = slett + sett inn.
8. **`signups`**: egen rad, upsert krever INSERT og UPDATE. `onConflict: schedule_id,player_id`.
9. **`poster`**: INSERT/DELETE kun arrangør. Partene kan bare endre `status`, `betalt_av`, `betalt_tid`, `metode`, `paaminnet_tid` (trigger).
10. **`utlegg`**: arrangør, eller sosialkomité-medlemmet for egen rad mens status er `meldt`.
11. **`tips`**: eget tips kun mens kupongen er åpen (`tips_aapen`). Andres tips skjules til låsing. `tips_levert()` (RPC) viser hvem som har levert, uten svar.
12. **`activity_log`**: append-only. Kategoriene `melding`, `purring`, `paaminnelse` og `til` er kun for arrangør (42501 ellers).
13. **`meldinger`**: INSERT krever `created_at` innen ±1 min (utelat feltet) og `pushet_at` null. Bilde-sti må være `<player_id>/<id>.jpg`, så klienten må generere melding-id før opplasting.
14. **`courses` / `course_holes`**: INSERT/UPDATE åpent for alle innloggede (unntatt `bilde`, kun arrangør).
15. **RPC-er**: `slett_runde(rid)`, `tips_levert()`, `push_status()` (kun arrangør). `send_paaminnelser()` er kun for cron.

**Unik-nøkler klienten må respektere ved upsert:**
`hole_scores` (round_id, player_id, hole_index) · `round_points` (round_id, player_id) · `signups` (schedule_id, player_id) · `tips` (schedule_id, player_id) · `course_holes` (course_id, hole_number) · `poster` (kilde, kilde_id, fra, til).
Delete-then-insert brukes for `round_bays`, `round_teams`, `round_matches` (per runde), `side_claims` og `push_subscriptions`.

**Paginering:** PostgREST kapper på 1000 rader og trunkerer stille. PWA-en henter 1000 om gangen med eksplisitt `ORDER BY` på `round_points`, `market_stakes`, `side_claims`, `round_holes`, `hole_scores`, `signups`, `course_holes`, `round_teams`, `round_matches`, `round_bays`, `meldinger`, `tips`, `tips_betalinger`. Bruk samme mønster.

### 3.4 Realtime
PWA-en abonnerer på ca. 24 tabeller, ignorerer payload og henter alt på nytt (debounce 250 ms). Native bør heller bruke payload eller målrettet refetch per tabell.

### 3.5 Hull og motsigelser i grunnlaget

- **Basetabellene** (14 stk) er ikke definert i `sql/`. Kolonnetyper for `markets`, `market_stakes`, `fines`, `activity_log`, `rounds.date` (dato eller tekst?) og PK-er er utledet.
- **Realtime-publikasjonen** for flere tabeller er ikke satt i `sql/` (sjekk i den levende basen).
- **`round_holes.meters`**: koden leser kolonnen, ingen SQL-fil oppretter den. **(uavklart)**
- **Markør og par-bekreftelse:** `rounds` og `round_holes` kan bare skrives av arrangør, men markøren er den som «bekrefter» par. Om flyten virker for en markør som ikke er arrangør, er **uavklart**. Test mot test-prosjektet før den bygges.
- **`side_claims`-policyen** avhenger av kjørerekkefølgen på tre filer. Intendert sluttform: eier eller arrangør, og ikke låst runde.
- **`send_paaminnelser()`** står i tre filer. Siste kjørte vinner.
- **Åpne INSERT-policyer** (`rounds`, `markets`, `schedule`, `courses`, `activity_log`) lar en vanlig bruker lage en låst runde eller et veddemål med annen `creator_id`. Klienten bør ikke gjøre det, og vi endrer ikke basen uten godkjent SQL.

---

## 4. Spillogikk som må gi likt svar i Swift

Kilde er `db-nytt.js` (linjenummer i parentes). Testene er Node-harnesser i `referanse/golfgutu-pwa/tests/` (kjøres med `tests/kjor.sh`). De kan ikke gjenbrukes direkte, men **forventede tall kan løftes rett over** til Swift Testing. «Ingen test» betyr at vi må skrive en egen test fra algoritmen, ikke at logikken kan hoppes over.

### 4.0 Fallgruver ved porting (gjelder alt under)
1. **Avrunding:** JS `Math.round(x)` er `floor(x + 0.5)`. -2,5 → -2, 2,5 → 3. Swifts `.rounded()` runder bort fra null (-2,5 → -3). Bruk `floor(x + 0.5)` overalt. Samme for `rund2(x) = round(x·100)/100` og «nærmeste halve» (`round(x·2)/2`).
2. **JS-sannhet:** `custom.strokeIndex || bane.si || (i+1)` faller gjennom på 0, null og undefined. Ikke bruk `??` uten å sjekke nøyaktig.
3. **Navnesortering:** `localeCompare(…, 'no')` er norsk kollasjon (æøå etter z). Bruk `nb`-locale.
4. **`Object.keys`-rekkefølge** for heltallsnøkler er stigende numerisk (påvirker `lagForRunde`).
5. **`typeof x === 'number'`** skiller tall fra null i `holeScores`. Modeller score som `Int?`.
6. `Number('') = 0`, men `courseRating` med tom streng behandles som manglende.
7. **Tilfeldighet** (`trekkSosialkomite`) må injiseres for å kunne testes.
8. **Tid:** `tipsFrist` regnes i Europe/Oslo med sommertid. Bruk `TimeZone(identifier: "Europe/Oslo")`.
9. **Tall er `Double`.** Handicap er ofte brøk til siste avrunding.

### 4.1 Hulldata og bane

| Logikk (linje) | Regel | Testet av |
|---|---|---|
| `DEFAULT_PAR` (17) | `[4,5,3,4,4,3,5,4,4,4,3,5,4,4,3,4,5,4]` (par 72) | `banepar-test.js` |
| `parErEtTall` (102) | tall, 3 ≤ p ≤ 6 (ikke heltallskrav) | indirekte via `baneErKlar` i `banepar-test.js` |
| `banehullFraRader` (113) | `course_holes` gjelder når 9 eller 18 sammenhengende hull fra 1; ellers null | `banepar-test.js` |
| `lengdePasserParet` (142), `hullMedRarLengde` (149) | par 3: 90–210 m, par 4: 230–440, par 5: 420–580 (inkl.) | `banepar-test.js` |
| `baneErKlar` (171) | 9 eller 18 hull, par 3–6 på alle | `banepar-test.js`, `brutto-test.js` |
| `baneHarIndeks` (166) | alle hull har `si > 0` | `brutto-test.js` |
| `courseForRound` (184) | Se 4.1.1 | `baneoppsett-test.js`, `banepar-test.js`, `brutto-test.js`, `banebytte-test.js`, `banehull-test.js`, `trackman-test.js`. **`holeStart:9` mot 18-hulls bane har liten dekning, skriv egen test.** |
| `antallHull` (180) | 9 eller 18, ellers 18 | indirekte (`brutto-test.js`) |

**4.1.1 `courseForRound`:** `antall = antallHull`. `start = 9` bare hvis `antall == 9 && holeStart == 9 && banen har 18 hull`, ellers 0. For hvert hull i: `par` = rundens eget (`round.holes[i]`, hvis gyldig) → banens `[start+i]` → `DEFAULT_PAR[i]` (NB: `i`, ikke `start+i`). `kortIndeks` = egen → banens `si` → `i+1`. **`strokeIndex` er rang:** sorter (i, kortIndeks) stigende, uavgjort lavest `i` først, rang + 1. 9-hulls eksempel: `[11,5,17,9,3,13,1,7,15]` → hull7=1, hull5=2, hull2=3, hull8=4, hull4=5, hull1=6, hull6=7, hull9=8, hull3=9.

### 4.2 Handicap og slag

| Logikk (linje) | Regel | Testet av |
|---|---|---|
| `courseHandicap` (233) | `round(idx · slope/113 + (rating − par))`. Mangler rating → par (eller 72). Mangler slope → 113. idx NaN → 0 | `seeding-test.js` (18,4 / 74,1 / 136 / par 72 = 24), `brutto-test.js` |
| `rundeAndel` (253) | `hcpAllowance` hvis tall ≥ 0, ellers 1. 0 er gyldig (brutto) | indirekte (`brutto-test.js`). **Ingen direkte test** |
| `seedingGruppe`/`gruppeHandicap` (58–82) | gruppe 1/2/3 = 0/5/10. `null` (ikke seedet) er ikke 0 | `seeding-test.js` |
| `banehandicap` (258) | seedet → gruppetallet rått. Ellers med bane: `courseHandicap`. Uten bane: rå indeks (ikke avrundet) | `seeding-test.js`, `parspill-test.js`, `brutto-test.js`, `trackman-test.js` |
| `lagGrunnlag` (273) | seedet → gruppetallet. Ellers `banehandicap · antallHull/18` (ikke avrundet) | indirekte (`parspill-test.js`). **Ingen direkte test** |
| `lagHandicap` (302) | Toerformer: snitt av grunnlag, **ett** avrundingstrinn. `scramble-4`: lavest·0,25 + 0,20 + 0,15 + 0,10 (sortert stigende). Ellers (1 eller 4 uten scramble): laveste · `rundeAndel`. `rundeAndel = 0` → 0 | `parspill-test.js` (5&10 → 8, 0&5 → 3, 18&9 → 14, 9 hull (9+4,5)/2 → 7, tre mann 5+5+10 → 7, scramble-4 [0,5,5,10] → 3), `skjevt-lag-test.js` |
| `effectiveHandicap` (321) | **1)** `hcpExtern` → 0 (før alt). **2)** lagsform/toerform med lag: `lagHandicap`. **3)** seedet: gruppetall (0 hvis andel 0). **4)** `round(banehandicap · rundeAndel · antallHull/18)` (ett avrundingstrinn) | `seeding-test.js`, `parspill-test.js`, `brutto-test.js`, `trackman-test.js`, `tropp-test.js`, `banebytte-test.js`, `skjevt-lag-test.js` |
| `handicapStrokesForHole` (827) | `n` = 9 eller 18. `h = max(0, round(handicap))`. `floor(h/n) + (strokeIndex ≤ h mod n ? 1 : 0)` | `seeding-test.js` (10−5=5 → slag på indeks 1–5), `baneoppsett-test.js` (hcp 5 på 9 hull → hull 2,4,5,7,8), `brutto-test.js` |

### 4.3 Stableford og poeng per runde

| Logikk (linje) | Regel | Testet av |
|---|---|---|
| `pointsForHole` (906) | `max(0, par − netto + 2)`, netto = brutto − slag fått | `brutto-test.js` (par 5, 6 brutto med ett slag = 2 p; 5 → 3; 8 → 0; hcp 7 → 36+7 = 43), `trackman-test.js`, `matchrunde-test.js` |
| `scoreNameForHole` (1026) | netto − par: ≤ −2 eagle, −1 birdie, 0 par, 1 bogey, 2 dobbel, ellers blowup | **Ingen test** |
| `poengFraHull` (1003) | Summer over `tellendeHull`. Hull uten score gir `poengForTomtHull`. Ingen score i det hele tatt → 0 (også ved `nettopar`). Nøkkel = rundens 0-baserte hullindeks | `avkorting-test.js`, `seier-test.js`, `trekant-test.js`, `tropp-test.js` |
| `roundNetTotal(ForPlayer)` (1042/1048) | `poengFraHull(runde, holeScores[pid], effectiveHandicap)` | via over |

### 4.4 Konkurranseformer

16 former i `KONKURRANSEFORMER` (859). Felter: `id`, `navn`, `lag`, `kort` (per spiller / per lag), `regning`, `hcpAndel`, `stotte` (full / delvis / mangler), `taalerSkjevtLag`, `hjelp`. De eksakte norske hjelpetekstene står på linje 861–891 og kopieres derfra.

| id | lag | kort | regning | hcpAndel | stotte |
|---|---|---|---|---|---|
| stableford | 1 | spiller | stableford | 0,95 | full |
| stableford-brutto | 1 | spiller | stableford-brutto | 0 | delvis |
| slag-netto / slag-brutto | 1 | spiller | slag-… | 0,95 / 0 | delvis |
| par-bogey, maks-score | 1 | spiller | … | 0,95 | delvis |
| match | 1 | spiller | match | 1,00 | full |
| fourball | 2 | spiller | beste-netto | – | full (skjevt ok) |
| fourball-4 | 4 | spiller | beste-netto | 0,75 | full (skjevt ok) |
| sammenlagt-lag | 2 | spiller | sum-netto | – | full |
| foursome | 2 | lag | stableford | 0,50 (arvet, ignoreres) | full |
| greensome, chapman | 2 | lag | stableford | – | full |
| scramble-2 / scramble-4 | 2 / 4 | lag | stableford | – | full (skjevt ok) |
| skins | 1 | spiller | skins | 0,95 | **mangler** (blokkert) |

`formForRunde` (900): `lowercase(gameType)`, ukjent/tom → stableford. `erLagform` = `lag > 1`. Testet av `paamelding-test.js` (`konkurranseform`). `formForRunde` og `erLagform` har ingen direkte test. `hcpAndel` fra formen lagres på runden som `hcp_allowance` når den startes.

**Lagdeling og forslag** (`lagdeling` 1476, `oppsettForAntall` 1494, `formerSomPasser`): tester i `paamelding-test.js` og `skjevt-lag-test.js` (11 i scramble-2 = 3+3+3+2 og skjevt; foursome med 11 ikke ok, med 12 ok; 7 spillere foreslår bare individuelle former; oddetall individuelt = trekant). `lagdeling` har ingen direkte test.

### 4.5 Avkorting

| Logikk (linje) | Regel | Testet av |
|---|---|---|
| `avkortRegel` (948) | `felles`, `nettopar` eller `null` (strengen «null» er en gyldig regel, JS-null betyr «ingen») | `avkorting-test.js` |
| `tellendeHull` (955) | Kun `felles` kutter, til `min(antall, round(avkortetEtter))`. Ugyldig/mindre enn 1 → `antall` | `avkorting-test.js`, `match-test.js` |
| `poengForTomtHull` (~946) | `nettopar` → 2, ellers 0 | indirekte. **Ingen direkte test** |
| `lavesteFellesHull` (976) | Per spiller antall *sammenhengende* hull fra hull 0. Minimum. Spillere uten score teller ikke. Ingen score → 0 | `avkorting-test.js` (14; hoppet hull gir 3) |
| `avkortingenKoster` (1938) | Forskjell per spiller (uavkortet vs. avkortet) sortert størst tap først, pluss åpne hullveddemål utenfor kuttet | `avkorting-test.js` |
| `saveAvkorting` (1920) | Oppdaterer `rounds`, så `regnOmRundePoeng` | **Ingen test på selve funksjonen** |

Nøkkeltall fra `avkorting-test.js`: uavkortet Anders 36, Bjørn 28. `felles` etter 14 hull: Anders 28, Bjørn uendret, Cato 28. `nettopar`: Bjørn 28 + 8 = 36, Cato 32 + 4 = 36, Dag 0.

### 4.6 Match, trekant, jakketabell

| Logikk (linje) | Regel | Testet av |
|---|---|---|
| `matchSider` (403) | `teamA/teamB` satt → lag. Ellers `playerA/B/C` | `skjevt-lag-test.js` |
| `sideNettoPaaHull` (424) | Beste netto på siden. Slag = `effectiveHandicap − ekstraSlag`, ikke under 0 | indirekte (`match-test.js`, `matchrunde-test.js`). **Ingen direkte test** |
| `matchSlag` (449) | `min(sideHandicap(a), sideHandicap(b))` trekkes fra begge (laveste spiller fra scratch). `sideHandicap` = laveste `effectiveHandicap` på siden | `parspill-test.js`, `seeding-test.js` |
| `matchHullVinner` (481) | lavere netto vinner hullet (1 / −1 / 0). Én mangler score → null. **Ikke stableford** | `matchrunde-test.js` (6 mot 7 på par 4 = vunnet selv om begge gir 0 p) |
| `matchHullDiff` (455) | summerer over `tellendeHull`; slagfordeling bruker full `antallHull` | `match-test.js` (16 ført uavkortet: opp −12, spilt 16; avkortet 14: spilt 14, opp −14), `matchrunde-test.js` |
| `matchUtfallForA` (509) | `result` `A`→1, `B`→0, annet→0,5. Ellers fra hulldifferanse: >0→1, <0→0, 0→0,5. Ingen hull spilt → null. Trekant → null | `trekant-test.js` |
| `matchStilling` (570) | `{opp, spilt, igjen, avgjort: |opp| > igjen && spilt > 0, motstandere}` | `match-test.js`, `matchrunde-test.js`, `skjevt-lag-test.js`, `trekant-test.js` |
| `matchTekst` (588) | Se 4.6.1 | `match-test.js` (bare «Vunnet»-prefiks). **De andre grenene har ingen test** |
| `matchStillingKort` (605) | `—` / `Delt` / `N opp` / `N ned` | `matchrunde-test.js` |
| `trekantPoeng` (539) | Rangert på stableford (`roundNetTotalForPlayer`). Fordeler `[1, 0.5, 0]` med deling ved likt. Mangler en spiller score → null | `trekant-test.js` (36/18/0 → 1/0,5/0; delt 1.: 0,75/0,75/0; delt 2.: 1/0,25/0,25; alle likt 0,5) |
| `trekkMatcher` (779) | Sorter på stilling (synkende) så navn (norsk). Oddetall rundenummer reverseres. Oddetall: siste tre blir trekant. < 2 → [] | `trekant-test.js` (antall og trekant). **Rekkefølgen er ikke testet** |
| `matchResultaterFor` (646) | Per runde: vekt 0 hopper over alt. Trekant: `poeng·vekt`. Ellers 1/0,5/0 · vekt og hulldifferanse. Sortert poeng så hull | `match-test.js` (5 knepne seire + 2 knusende tap: poeng 5, hull −31; 7 matcher), `seier-test.js` (7 seire = 7; lagseier gir hver mann 1; vekt 0 → alt 0) |
| `matchSum` (686) | `{poeng: round(Σ·2)/2, hull, matcher}` | **Ingen direkte test** |
| `sidepremieVinnere` (717), `sidepremieResultaterFor` (726) | Lik lengde deler poenget (1/n · vekt). Drive: lengst. KP: kortest | `seier-test.js` (LD gir 1 poeng). **Delt (0,5 hver) har ingen test** |
| `jakketavle` (755) | `total = round((duell + side)·2)/2`. Sorter: total, hulldifferanse, stableford (`seasonTotalNytt`), navn (norsk) | `seier-test.js`, `match-test.js`, `tropp-test.js` |
| `fmtPoeng` (380) | `round(n·2)/2`, komma som desimal | `seier-test.js` |
| `seasonTotalNytt` (1077), `tellendeRunderFor` (1066) | Brukes kun som skilletegn (best 5 av 7 runder, vektet) | `sesong-test.js` (7 runder = 130 fra 5 beste; dobbelrunde 30 → 104; 4 runder = 30+28+26+24) |

**4.6.1 `matchTekst`:** ingen stilling → «»; ingen spilt → «Ikke startet». Avgjort (eller `igjen = 0`): `opp = 0` → «Delt»; ellers «Vunnet »/«Tapt » + (`igjen > 0` ? `|opp|&igjen` («3&2») : `|opp|` + (opp>0 ? « opp» : « ned»)). Pågående: `opp = 0` → «Delt etter N», ellers `|opp|` + « opp»/« ned» + « etter N».

**4.6.2 Poengmodell («én seier, ett poeng»):** seier 1, delt 0,5, tap 0. Vinnerlag: hver mann 1. LD og KP 1 poeng hver. Rundevekt (`multiplier`) multipliserer, 0 hopper over runden. En kveld er verdt opptil 3 poeng. **Alle 7 kvelder teller, ingen stryking** (best 5 av 7 ble innført 16.09 og reversert 17.09). `TELLENDE_RUNDER = 5` brukes bare på stablefordsummen som skilletegn. UI-teksten på Sesongsiden sier fortsatt «tre beste» **(uavklart om utdatert)**.

### 4.7 Tippekupong

| Logikk (linje) | Regel | Testet av |
|---|---|---|
| `tipsInnsats`/`tipsLinje` | standard 50 / 2,5 | `tippekupong-test.js` |
| `tipsStarttid` | første `H:MM`/`H.MM` i `schedule.time` (0–23, 0–59), ellers 17:00 | `tippekupong-test.js` |
| `osloTidspunkt`/`tipsFrist` | Oslo-tid til UTC med to-pass DST-korreksjon | `tippekupong-test.js` (2026-10-08 17:00 → 15:00Z; 2026-11-05 → 16:00Z; 2026-10-25 → 16:00Z; 2026-03-29 → 15:00Z) |
| `tipsAapen` | `nå < frist` og ingen score på datoen. Kladder teller ikke som utelukkelse | `tippekupong-test.js` (14:59Z åpen, 15:00Z låst) |
| `tipsFasit` (3366) | Stableford summert over datoens runder. Første ni (kun første-ni-runden). Par-eller-bedre-antall. Birdie ja/nei. Snitt netto mot par per ni hull (`round(sum/ballHull·9·100)/100`), lagsform teller én ball per lag. Over/under mot linja, likt = null | `tippekupong-test.js` (A 36, B 27, C 27, D 36; første ni D 35; snitt 2,25 mot linje 2,5 → under) |
| `tipsRiktig`, `tipsBeste`, `tipsKomplett` | fasit null = spørsmålet gjelder ikke; uavgjort = alle vinner | **Ingen direkte test** |
| `tipsResultat` | poeng per spiller, `vinnere` først når kvelden er ferdig | `tippekupong-test.js` |
| `tipsOppgjor` (3483) | pott = innsats × deltakere. Hver vinner får `floor(pott/n)`, restkroner til de første alfabetisk. Taperne betaler `innsats` hver, fordelt til vinnerne i kø. Ingen overføring hvis innsats 0, < 2 deltakere, ingen/alle vinnere | `tippekupong-test.js` (pott 200 → 100/100; sju spillere, tre vinnere, 350 → 117/117/116) |

### 4.8 Penger: veddemål, poster, utlegg

| Logikk (linje) | Regel | Testet av |
|---|---|---|
| `forsteApneHull` (2480) | `front = 0 ? 0 : front+1`. Null hvis ≥ `tellendeHull`. Må matche DB `veddemaal_tar_innsatser` og `VEDDEMAAL_FORSPRANG = 1` | `lockout-test.js`, `avkorting-test.js` |
| `markedTarInnsatser` (2495) | Åpen, ikke `lukket_at`, runde ikke låst. Hullmarkeder: `h >= forsteApneHull`. Andre: stengt etter første slag | `lockout-test.js`, `vilkaar-test.js`, `kveld-test.js`, `status-del-test.js` |
| `vilkaarUtfall` (2513) | `birdie`/`par`/`hull`/`slaar`/`drive`/`kp`/`match` → JA/NEI/null. Likt = null (manuelt). `slaar`/`drive`/`kp` kun når runden er låst | `vilkaar-test.js`, `kveld-test.js` |
| `skalLukkes`, `oppdaterMarkeder` (2593/2605) | Lukker per hull, avgjør ved sikkert utfall. Kun arrangør skriver | `vilkaar-test.js`, `kveld-test.js` |
| `veddemaalPoster` (2743) | Hver taper betaler hver vinner `innsats·vinnerinnsats/vinnerpott`, `rund2`, bare `> 0`. Ingen vinnere eller tapere → ingen poster | `poster-test.js` (me JA 100, e JA 50, t NEI 150 → t→me 100, t→e 50) |
| `marketNetFor` (1098) | `net = −Σ innsats + (vinnerinnsats + andel av tapspott)`. Ingen vinner → alle får igjen innsats | **Ingen test** |
| `skyldOversikt` (2667) | Se 4.8.1 | `poster-test.js`, `tropp-test.js`, `utlegg-test.js` |
| `kortRegnestykke` (2727) | «Kupongen 50 − veddemål 30» (U+2212) | `poster-test.js` |
| `kupongPoster` (2766) | Fra `tipsOppgjor`, bare når kvelden er ferdig | `tippekupong-test.js` |
| `avregnKvelden` | Idempotent, kun arrangør, krever `posterFinnes` | `poster-test.js` |
| `sendPaaminnelser` | Én gang per økt. Poster ≥ 3 dager gamle uten `paaminnet_tid`, `klaimPaaminnelse` (compare-and-set) | `poster-test.js` |
| `utleggsOppgjor`/`utleggPoster` | `perMann = rund2(belop/deltakere)`. **Ingen restfordeling, rest går tapt.** Må porteres likt | `utlegg-test.js` (1400/4 = 350, 640/4 = 250) |

**4.8.1 `skyldOversikt`:** poster grupperes per motpart. Poster *til* `kassa` nettes **ikke** mot egne poster (de tilhører kun betaleren). Åpne poster: `netto = rund2(Σ ±belop)`. `|netto| < 0,005` → `nullPar`. `netto > 0` → `betaler`, `< 0` → `faar`. Ikke-åpne grupperes på `status|betaltAv|første 16 tegn av tid` (minuttoppløsning). `betalt` av motparten og yngre enn 2 dager → `betaltTilDeg` («Ikke mottatt?»), ellers `oppgjort`. Sortering: eldste først, så størst netto. Tester: `betaler` t 20 og kassa 100, `faar` e 40, sum 120/40; nullpar-par oppgjøres automatisk; yngre enn 2 dager betalt → `betaltTilDeg`.

### 4.9 Skriving av score (kontrakten med PWA-en)

Appen og PWA-en brukes samtidig, så skrivemønsteret må være identisk:

1. **`saveHoleScore`** (1773): mottakere = alle på laget hvis `kort == 'per lag'` og laget ikke er tomt, ellers spilleren. **Upsert** i `hole_scores` (`round_id, player_id, hole_index, strokes, updated_by, updated_at`). Så **les tilbake fra databasen** (`hole_index, strokes` for spilleren) og regn `poengFraHull(effectiveHandicap)` fra disse, **ikke fra lokal tilstand**. Så upsert i `round_points`. For lag: `skrivLagpoeng`.
2. **`skrivLagpoeng`** (1815): summerer lagets poeng per hull (`sum-netto` = sum, `beste-netto` = maks, ellers ett kort), tomme hull gir `poengForTomtHull`. Samme total skrives til alle på laget.
3. **`regnOmRundePoeng`** (1864): leser alle `hole_scores`, skriver lagpoeng først (én gang per lag), så alle individuelle `round_points` i én upsert. Kun spillere med score får rad.
4. Begrunnelse for les-tilbake: 07.09.2026 falt en runde fra 41 til 3 poeng fordi totalen ble regnet fra delvis lokal tilstand.
5. Endring som avkorting, banebytte og retting ender i `regnOmRundePoeng`.

Tester: `banebytte-test.js` (3 spillere × 18 hull, poeng per spiller lik `pointsForHole`-summen, scramble skriver laget én gang). **`saveHoleScore`, `skrivLagpoeng`, `saveAvkorting`, `saveBaaser`, `saveMatcher`, `saveLag` og de fleste øvrige skrivefunksjonene har ingen direkte test.** Se L i del 2-rapporten: `saveRoundHoles`, `saveCourse`, `saveSideClaim`, `saveKpHole`, `saveLongestDriveHole`, `savePhone`, `saveHandicap`, `saveSeedGroup`, `claimPlayer`-varianter og push-funksjoner.

### 4.10 Markør og bås

| Logikk (linje) | Regel | Testet av |
|---|---|---|
| `kanFore` (2033) | Se 2.4. Må speile RLS i 3.3 | `markor-test.js`, `tropp-test.js` |
| `baaserForRunde`, `baasFor`, `erMarkor` | Spillere i bås sortert på navn (norsk). Markør = den med `markor`, siste vinner | `markor-test.js` |
| `deltakereIRunden` (2054) | Union av matchsider, lag, båser, spillere med score og påmeldte. Tom → alle | `markor-test.js`, `matcher-test.js` |
| `foreslaatteBaaser` (2078) | Duellpartnere samles. Fyller bås med færrest. Markør = første i en tom bås | `markor-test.js`, `paamelding-test.js` (12 → 4/4/4, én markør per bås) |

### 4.11 Kveld, påmelding, sideoppgaver

| Logikk (linje) | Regel | Testet av |
|---|---|---|
| `kveldsDatoer`, `rundeNummerFor` | to runder samme dato = én kveld | `kvelder-test.js` (via `antallKvelder`) |
| `kveldErFerdig` (2339) | runder finnes og alle er låst. Kladd/pågående holder kvelden åpen | `neste-kveld-test.js` |
| `svarPaaDato` (1626) | ukjent status avvises, kommentar trimmet til 80 tegn, upsert med `onConflict`. Fallback når svarkolonner mangler | `paamelding-svar-test.js` |
| `paameldteForDato` | `null` hvis datoen ikke er i terminlisten, tom liste ≠ null | `paamelding-test.js`, `kvelder-test.js` |
| `deltakereForDato` | spillere med score → ellers påmeldte → ellers alle | **Ingen test** |
| `foreslaattLongestDriveHull` (2845) | lengste hull ≥ par 4 med meter. Ellers første par ≥ 5 fra indeks 3 → fra 0 → første par ≥ 4 → 0. `foreslaattKpHull`: første par 3 fra indeks 3 → fra 0 → 2 | delvis `sidepremie-valgfritt-test.js`. **Forslagene har ingen direkte test** |
| `longestDriveClaims`/`kpClaims` | drive: meter synkende; KP: stigende; så tid. Tomme hvis sideprisen er av | `sidepremie-valgfritt-test.js` |
| `trekkSosialkomite` (1394) | minst antall turer først, tilfeldig blant likestilte, to per kveld | **Ingen test** |
| `slettRunde`, `rundenTarMedSeg` | RPC `slett_runde(rid)`. Oppsummering (hull, spillere, markeder, kroner, sidepremier) | `slett-runde-test.js` |
| `bekreftBaneoppsett` (2211) | upsert `course_holes`, ved 23505 nulles kolliderende `hcp_index` og det prøves igjen, så stempel `courses.bekreftet_*` (+ `par` hvis 18 hull) | `banebekreftelse-test.js` |

### 4.12 Ikke spillogikk, men må være likt
Utleggsfordeling (4.8), `fmtMeter` (`round(m·10)/10`, komma, « m», ingen test), `fmtPoeng`, kategori-listen for push (12 stk, `VARSEL_KATEGORIER`, `push_av` lagrer de som er **av**; `push-kategorier-test.js`).

---

## 5. PWA-problemer og hvordan native løser dem

### 5.1 Problemer som skyldes at det er en PWA

| # | Problem (README-ref.) | Native |
|---|---|---|
| 1 | **Må installeres på hjemskjermen**, ingen «installer»-knapp på iOS, en hel «Porten»-skjerm og nødutgang. «De aller fleste trykket der, og ble boende i Safari hele sesongen.» (L1611, 1699) | Forsvinner. Appen installeres fra App Store/TestFlight. |
| 2 | **Ingen push i Safari**, kun med hjemskjerm-install. «Pushen gikk til alle åtte telefonene med push» (av 12), resten får e-postreserve (L3486) | APNs fungerer for alle. **Krever en server-side sender** (se 5.3). |
| 3 | **Separat lagring Safari vs. hjemskjerm**, innlogging må gjøres om, derfor engangskode i stedet for lenke (L1563) | Én sandbox. Engangskode kan beholdes. Lenke/passkey blir mulig, men ikke nødvendig. |
| 4 | **Realtime dør i bakgrunnen** på iOS. Appen viste gammelt innhold til den ble startet på nytt (L247). Fiks: full henting ved `visibilitychange`/`online`. **«Ikke prøvd på en iPhone ennå.»** | Håndter scenefase. Hent på nytt ved aktivering, og bruk push til å vekke. Krever uansett re-sync ved reconnect. |
| 5 | **Ingen offline-data, ingen skrivekø.** Tilstand kun i minnet. Etter tre forsøk ligger hullet bare i minnet og er borte ved reload (README sier lite, koden bekrefter) | Lokal lagring + utboks. **Største gevinsten for en ekte kveld** (dårlig dekning i simulatorhallen). |
| 6 | **Full refetch av ca. 25 tabeller** ved hver realtime-hendelse. Skjermen redrawes helt, med hacks for å bevare tastet tekst (`huskSkjema`, `scoreUtkast` utenfor STATE) | SwiftUI med observerbar tilstand og målrettede oppdateringer. Utkast er lokal tilstand. |
| 7 | **iOS-bunn:** 62 px utenfor appen med `black-translucent`. Løst ved `default`. Dobbelttrykk-bug flytter treffsonen 62 px (L2888–3007) | Forsvinner (ekte safe area). |
| 8 | **Tastatur/fokus:** nytt felt tar fokus og lukker tastaturet ved realtime-redraw. `type="number"` gir tom streng for «18,4» (komma) og stille 0 som handicap (L3429, 1584) | Native tekstfelt og `Decimal`-parsing med komma. Handicap må parses som i `parseHcp`. |
| 9 | **Kalender:** `.ics`-lenke virket ikke fra hjemskjermen. Løsning: abonnement via worker (`webcal://`, Google, Outlook) (L275) | EventKit, eller fortsatt abonnement mot worker-endepunktet. |
| 10 | **Vipps:** `vipps://pay?…amount=` virker ikke. Personlig QR-lenke tar ikke beløp. iOS slipper bare til annen app direkte i trykket (L2819) | Vipps-lenke via `UIApplication.open` direkte i handlingen. Beløp kan fortsatt ikke sendes med. |
| 11 | **Deling:** `navigator.share()` bare rett i trykket. Plakat tegnes i forkant (L3541) | `ShareLink`, `UIActivityViewController`. |
| 12 | **Tilbake-knapp** var uforutsigbar, ingen nettleser-back (designgjeld) | `NavigationStack` og ekte back-gest. |
| 13 | **Cache-busting for hånd** (`?v=N`), service worker `skipWaiting` kan laste om midt i føring | Forsvinner. |
| 14 | **Hjemskjerm-meta caches av iOS**: ikon må slettes og legges til på nytt for å få endringer | Forsvinner. |
| 15 | **Live-oppdatering uten Live Activity/Watch/widget**: PWA-en kan ikke vise stilling på låseskjermen | Live Activity, widgets, Apple Watch (senere mål). |
| 16 | **GPS og kart finnes ikke.** Appen er et simulatorfølge | Native `CoreLocation` gjør «avstand til green» mulig, men **kilde til green-posisjoner finnes ikke i databasen** (se 6.3 og åpne spørsmål). |

### 5.2 Problemer som *ikke* skyldes PWA (native løser dem ikke av seg selv)
- **Forretningslogikk i klienten:** poeng, avregning og veddemålsavgjørelse regnes lokalt og skrives til basen. Eieren kan skrive egne `round_points` direkte i en ulåst runde. Native arver dette.
- **Ikke-atomiske skriv:** `saveHoleScore` (to skriv), `saveBaaser`/`saveMatcher`/`saveLag` (slett så sett inn). En feil midt i etterlater en runde uten lag/båser/matcher.
- **Plikter krever åpen app** (avgjørelse, avregning, purring), og kun på arrangørens enhet for veddemål.
- **Siste skriving vinner** på score. Bås/markør-modellen demper det.
- **Klientens klokke** brukes til `updated_at` og `lukket_at`.
- **Åpne INSERT-policyer** (3.5).
- **Aktivitetslogg som HTML-tekst** parset for ikon.
- **Åpen påmelding:** hvem som helst med URL-en kan bli med.
- **Banedata:** 17 av 18 baner er aldri bekreftet mot simulatorskjerm. Glen Abbey har motstridende par, Great Northern, Lofoten Links og Barsebäck er uløst. Le Golf National er ikke rørt. Lengder for 9 hull er NULL.
- **Halve slag finnes ikke** (7,5 → 8). Skins er ikke støttet. Ikke to runder samtidig (`activeRound()` viser én). Påmelding er per dato, ikke per runde.
- **Vipps tar ikke beløp.** Penger er tillitsbasert.

### 5.3 Konsekvenser for native som krever beslutning
- **Push/Live Activity** trenger en sender. PWA-ens worker sender web push (VAPID) via database-webhook på `activity_log`. APNs krever en tabell for enhetstokens og en server-komponent. **Begge er endringer utenfor klienten og går via godkjent SQL/worker.** Inntil da kan appen bruke lokale varsler og Live Activity oppdatert fra appen selv.
- **Auth:** e-postkodens lengde (6 eller 8) er en Supabase-innstilling. Ikke anta lengde (PWA-en rettet en feil her, `maxlength=10`, min 4).
- **Test først:** `db.js` har prod-URL og publishable key. Appen må ha egen konfig for test-prosjektet.

### 5.4 README-utsagn som er utdatert (ikke bygg etter dem)
- **Bank, innskudd, saldo, saldosperre** (L2634–2874, 2117, 1980): erstattet 02.10 av skyldlisten `poster`. `bank_bevegelser` og `spiller_saldo()` står urørt som historikk. «Saldo» i oppgaven din tolkes derfor som `poster`/`skyldOversikt`.
- **«Mer»-fanen, Klubb-fanen, Hjem**: erstattet av tre faner 18.09.
- **«Best 5 av 7»**, strykregler og kamppoeng 3/1/0: reversert og erstattet av «én seier, ett poeng».
- **Vipps `vipps://pay?recipient=…`**: virker ikke.
- **`rounds.poengform`**: bygget og fjernet 17.09.
- **«Fører for»-nedtrekk**: erstattet av hullkort for hele bås.
- **`black-translucent`-konklusjonene** om iOS-bunn: overstyrt av «Løst» (L2954).
- **`docs/e-post-oppsett.md`** sier «parkert 31.08», men OTP ble levert 01.09.

---

## 6. Forslag til rekkefølge

Prinsipp: minst mulig som er nyttig for en **ekte kveld**, og ingen skriving mot basen før lese- og regnelaget er bevist mot PWA-en. PWA-en fortsetter å være arrangørens verktøy i starten.

### 6.0 Hva en ekte kveld trenger fra iOS-appen
En spiller åpner appen, logger inn, ser at kvelden er i gang, føres som markør for båsen sin (eller følger med live), ser scorekort og stilling. Arrangøren kan fortsette å sette opp kladd, båser og avslutte kvelden i PWA-en.

### 6.1 Steg

| # | Steg | Hvorfor | Skriver til basen? |
|---|---|---|---|
| 0 | **Kontrakt og konfig:** Supabase-klient mot **test**, miljøbryter, ingen prod i klienten | Sikkerhet | Nei |
| 1 | **Spillogikk-kjerne** (ren Swift, ingen UI/nett): bane/hull (`courseForRound`), handicap, slag per hull, stableford, `tellendeHull`/avkorting. Tester løftet fra 4.1–4.5 | Alt annet hviler på dette. Må gi likt svar som `db-nytt.js` | Nei |
| 2 | **Les-lag:** modeller for rader som i 3.1, paginert henting, innlogging (engangskode), koble til/velg spillerrad | Gir noe å regne på | Nei |
| 3 | **Kveld, lesemodus:** neste kveld, aktiv runde, bås, «Bayen nå», scorekort, regnet stilling. Verifiser at **poengene matcher PWA-en** på samme data i test-prosjektet | Bevis for paritet før skriving | Nei |
| 4 | **Match, trekant, jakketavle, sidepremier** (4.6) og Tavla (les) | Paritet på stillingen | Nei |
| 5 | **Føring som markør:** hullkort for hele båsen, `saveHoleScore` (upsert + les tilbake + `round_points` + lag), `kanFore`. Test mot test-prosjektet og PWA-en samtidig | **Kjernen for en ekte kveld** | **Ja** (score) |
| 6 | **Lokal utboks og offline-føring** (hull i kø, gjentatte forsøk, tydelig «ikke lagret»). Idempotent upsert | Hovedgevinsten over PWA-en | Ja |
| 7 | **Påmelding (svar + kommentar)** og terminliste (les) | Gjør at kvelden kan startes uten PWA hos spilleren | Ja (egen rad) |
| 8 | **Live Activity** under runde (stilling, hull, bås). Lokal oppdatering først | Eksplisitt mål | Nei |
| 9 | **LD/KP-innmelding** (`side_claims`) | Del av kvelden | Ja |
| 10 | **Veddemål:** vis, vedd, `markedTarInnsatser`, `vilkaarUtfall` (kun lese/forhåndsvise, la PWA-arrangør avgjøre) | Ekte penger, krever stor presisjon | Ja (innsats) |
| 11 | **Penger:** `skyldOversikt`, merk betalt/mottatt, Vipps-åpning. Lesemodus først | | Ja (status) |
| 12 | **Arrangørverktøy** (kladd, båser, matcher, avkort, lås, rett score) | Fjerner siste PWA-avhengighet | Ja (arrangør) |
| 13 | **Tråd, tips, varsler, tippekupong** | Nyttig, ikke nødvendig for en kveld | Ja |
| 14 | **Widgets, Apple Watch, GPS/avstand til green** | Senere mål, krever banegeometri (åpne spørsmål) | Nei/ja |

### 6.2 Underveis
- **Sameksistens:** så lenge PWA-en lever, skal iOS-appen ikke skrive noe PWA-en ville skrevet annerledes (4.9). Plikter som kun kjører i PWA-en (avgjørelse, avregning) beholdes der til appen eksplisitt overtar dem likt.
- **Ingen endring i databasen uten godkjent SQL** (CLAUDE.md). Hull funnet i 3.5 rapporteres, de rettes ikke.
- **Test først, prod sist.** Før første skriving: en kveld i test-prosjektet med PWA og iOS side om side.

### 6.3 Åpne spørsmål
1. **Banegeometri for GPS:** `course_holes` har bare par, indeks og meter. Hvor kommer green-/tee-posisjoner fra (egen innsamling, OpenStreetMap, kommersielt)? Krever sannsynligvis en ny tabell, altså godkjent SQL.
2. **Push til APNs:** skal serveren (worker eller Edge Function) utvides, og i så fall hvem eier den?
3. **Lokal lagring:** SwiftData eller annet for utboks og cache? Ikke avgjort (CLAUDE.md nevner det ikke lenger).
4. **Skal appen støtte ekte bane**, ikke bare simulator? Par-bekreftelse, Trackman-modus og «bås» er simulatorkonsepter.
5. **Markørens par-bekreftelse** (3.5): virker den for en vanlig markør, eller må arrangør gjøre den?
6. **Skal iOS-appen ta over plikter** som i dag krever åpen PWA hos arrangør (avgjørelse av veddemål, avregning)?
7. **Utdatert tekst:** «tre beste runder» på Sesongsiden, og om `TELLENDE_RUNDER` skal beholdes som skilletegn.
