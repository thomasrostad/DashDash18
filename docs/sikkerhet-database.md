# Sikkerhetsrevisjon av databasen (Dash18 Test)

Dato: 07.10.2026. Prosjekt: «Dash18 Test» (`tsekialrxuhrugscosgi`). Revisjonen gjelder det som er kjørt på test (001–021, 019 inkludert), forslagene 022 og 023 og Edge Functions i `supabase/functions/`.

**Utgangspunkt:** appen blir åpen for alle. Angriperen er en fremmed med den publiserte nøkkelen (publishable/anon) og en egen konto. Med `create_club` er hen arrangør i sin egen klubb med én gang.

**Metode:**

- Bare lesing mot katalogen: `pg_class`, `pg_policies`, `pg_proc` med funksjonsdefinisjonene, `pg_trigger`, `pg_constraint`, `information_schema`, `pg_default_acl`, `storage.buckets` og publikasjonene. Ingen brukerdata er lest, bare antall rader.
- Supabase sin advisor (`supabase db advisors --linked --type security`).
- Auth-innstillingene som er offentlige (`/auth/v1/settings` med publishable-nøkkelen).
- Kildekoden til migreringene og Edge Functions.
- Lokal prøve av angrepene og av fiksen, i Postgres 16 med `lokal/stub.sql`.

**Samlet fiks:** `sql/024_sikkerhet.sql` (FORSLAG, ikke kjørt). Den retter H1, H2, M1 (nye klubber), M2, L1 og L2. Resten er innstillinger i Supabase-panelet eller endringer i 022/023 og Edge Functions. Se «Hva du må gjøre i panelet» nederst.

## Oversikt

| # | Alvor | Funn | Rettes i |
|---|---|---|---|
| K1 | Kritisk | E-postbekreftelse er av. Hvem som helst kan registrere en annens e-post med passord og kapre kontoen på forhånd | Panelet |
| H1 | Høy | En arrangør kan koble hvilken som helst innlogging til et navn i sin egen klubb | 024 |
| H2 | Høy | Et ledig navn med arrangørrolle kan tas med invitasjonskoden og gir arrangørrettigheter med én gang | 024 |
| H3 | Høy (forslag) | Kjøp i sandkassen låser opp turneringer i produksjon (023 og verify-purchase) | 023 / Edge Function |
| M1 | Middels | Klubbens invitasjonskode er 40 bit, uten utløp, rotasjon eller hastighetsgrense | 024 (nye koder) + appen |
| M2 | Middels | Ingen kvoter: spam i det felles biblioteket, runder, konkurranser, klubber, meldinger og push | 024 |
| M3 | Middels | Medlemmer kan skrive falske hendelser i `activity` (fritt `kind`/`data`), og de går ut som push | 024 (mengden) + senere |
| M4 | Middels (forslag) | verify-purchase godtar kjøp uten `appAccountToken`. Første konto som sender transaksjons-id-en, får kjøpet | Edge Function |
| M5 | Middels | E-postkoden (OTP): lengde, utløp og grenser er ikke sjekket. Ingen CAPTCHA | Panelet |
| M6 | Middels | Navn i det felles banebiblioteket ses av alle, men kan ikke rapporteres | Senere migrering |
| L1 | Lav | `rls_auto_enable()` kan kjøres av anon (advisoren) | 024 |
| L2 | Lav | Standardrettighetene gir anon og PUBLIC tilgang til nye objekter («anon-fella») | 024 |
| L3 | Lav | `register_push_device` flytter en enhet til den som kaller, hvis enhets-id-en er kjent | Senere |
| L4 | Lav | Rundekoden (018) kan fornyes av alle deltakere, og eieren kan ikke trekke den tilbake | Senere |
| L5 | Lav | Storage: filtypen er det klienten sier, blokkering gjelder ikke bilder, og det er ingen grense for antall filer | Senere |
| L6 | Lav | Edge Functions sender interne feilmeldinger (opptil 300 tegn) til klienten | Edge Functions |
| L7 | Lav | Realtime: DELETE-hendelser filtreres ikke av RLS (bare id), og offentlige broadcast-kanaler er åpne | Panelet |
| L8 | Lav | `club_members.user_id` (auth-id-en) ses av alle i klubben. Det er forutsetningen for H1 | Info etter 024 |
| I1–I10 | Info | Det som er i orden, eller er Supabase-standard | – |

---

## Kritisk

### K1. E-postbekreftelse er av: konto kan kapres før offeret registrerer seg

- **Objekt:** Auth-innstillingene. `/auth/v1/settings` viser `"email": true` og `"mailer_autoconfirm": true`. Det betyr at «Confirm email» er av.
- **Angrep:**
  1. Angriperen kaller `POST /auth/v1/signup` med `{"email": "offer@eksempel.no", "password": "…"}`. Den publiserte nøkkelen er nok. Kontoen blir bekreftet med én gang, uten at noen eier e-posten.
  2. Senere logger det ekte offeret inn med e-postkode (`signInWithOTP`). Supabase finner den eksisterende brukeren, og offeret havner i kontoen angriperen har laget.
  3. Angriperen har fortsatt passordet. Hen ser alt offeret ser (klubber, runder, tråd, veddemål og push-innstillinger), kan føre score i offerets navn og kan slette kontoen med `delete-account`.
- **I tillegg:** ubegrenset med kontoer uten noen sjekk av e-posten, altså fri vei for spam og brute force med mange kontoer.
- **Fiks (panelet):** Authentication → Sign In / Providers → Email: slå **på** «Confirm email». E-postkoden i appen virker som før, fordi den bekrefter e-posten. Slå i tillegg på «Secure email change» og «Leaked password protection» (advisoren melder den siste), og sett en minstelengde på passord. Det finnes ingen bryter for å skru av passord når e-post er på, så passordreglene må være strenge.
- **Sjekk etterpå:** `/auth/v1/settings` skal vise `"mailer_autoconfirm": false`.

---

## Høy

### H1. En arrangør kan gjøre hvem som helst til medlem i sin klubb

- **Objekt:** `guard_club_members()` (001), policyene `club_members_insert` og `club_members_update`. Vakta lot en arrangør sette `user_id` til hva som helst, både ved INSERT og ved UPDATE.
- **Angrep:**
  1. Frank kaller `create_club('Spam', 'Frank')` og er arrangør.
  2. Han legger inn en rad med `insert into club_members (club_id, user_id, display_name, status) values (<sin klubb>, <Veras auth-id>, 'Vera', 'active')`.
  3. Vera er nå «aktivt medlem» i Franks klubb uten å vite det.
- **Hvordan Frank får Veras id:** `club_members.user_id` ses av alle i klubber man deler (L8). Profil-id-en lekker også til alle man har spilt en runde eller konkurranse med.
- **Følger:**
  - `can_see_profile` blir sann, så Frank ser Veras profil (navn, handicap og bilde).
  - Han kan legge Vera til i løse runder og konkurranser, så «Mine runder» fylles med søppel.
  - Han kan sende push med `announcement` til Veras telefon.
  - Klubben dukker opp i Veras app.
  - Trusselmodellen i `docs/datamodell-v2.md` (punkt 2 og 3) er brutt.
- **Bevis:** `lokal/024_prove.sql` uten 024 viser «FEIL (gikk gjennom)» på INSERT og UPDATE, og `can_see_profile(Vera)` blir sann for Frank.
- **Fiks (024, avsnitt 1):** `user_id` kan bare settes til deg selv, eller tømmes («koble fra»), også av arrangøren. Ingen flyt i appen setter en annens id. `MemberPatch` sender bare `null`, og importen setter aldri `user_id`. Serveren og SQL Editor (`auth.uid()` tom) slipper som før.

### H2. Et ledig navn med arrangørrolle gir arrangørrettigheter til den som tar det

- **Objekt:** `join_club(kode, medlem_id)` sammen med `guard_club_members()`. Et ledig navn (`user_id` tom, `status = active`) tas uten godkjenning, og rollene følger med.
- **Når finnes slike navn?**
  - Importen (`DashImport/Mapper.swift`) lager kommissæren med `is_organizer = true` og uten `user_id`.
  - «Koble fra innlogging» (`MemberPatch.releaseLogin`) på en arrangør etterlater rollen på navnet.
  - En auth-bruker som slettes i panelet (ikke via `delete-account`), gir `user_id` null via fremmednøkkelen, og rollen står igjen.
- **Angrep:** alle som har invitasjonskoden (hele gjengen, eller en kode som har lekket), kaller `club_preview(kode)`, ser «Kommissær» blant de ledige navnene, og kaller `join_club(kode, <id>)`. Da er de arrangør: de kan slette runder, endre tropp, roller og regler, avgjøre veddemål og lese rapporter.
- **Bevis:** lokal prøve uten 024: «Gro er ikke arrangør: fikk true».
- **Fiks (024, avsnitt 1):** når et ledig navn tas av en som ikke er arrangør, mister det rollene **hvis klubben har en annen aktiv arrangør med innlogging**. Den arrangøren kan gi rollen tilbake. Har klubben ingen slik arrangør (oppstart etter import), beholdes rollen, ellers blir klubben låst ute.
- **Gjør dette:** etter importen må kommissæren ta navnet sitt **før** koden deles. Alternativt kobles kommissæren i SQL Editor. Kontroll 7 i 024 viser om det står ledige navn med roller (på test er det 0 nå).

### H3. Sandkassekjøp låser opp turneringer i produksjon (forslag 023 og verify-purchase)

- **Objekt:** `verify-purchase/appstore.ts` prøver produksjon først og så sandkassen. `logic.ts` setter `environment`. `record_purchase` lagrer `status = 'active'` uansett miljø, og `competition_unlocked_by_purchase` (023) ser ikke på `environment`.
- **Angrep:** et kjøp i TestFlight, Xcode eller en sandkassekonto er gratis. Kjøperen sender transaksjons-id-en til verify-purchase i produksjon. Funksjonen finner den i sandkassen, lagrer et aktivt kjøp, og turneringen er låst opp gratis. Hver offentlig TestFlight-lenke gir gratis turneringer.
- **Fiks (før 023 og funksjonen tas i bruk):** en secret som `APPSTORE_ALLOW_SANDBOX` (av i produksjon). Når den er av, avviser verify-purchase transaksjoner fra sandkassen (`environment !== "Production"`) med `wrong_app`. Gjør i tillegg det samme i databasen: `competition_unlocked_by_purchase` teller bare `e.environment = 'production'` i prod. Det er enklest med en egen innstilling, eller en `prod`-variant av funksjonen. 023 er ikke kjørt, så dette er ikke med i 024. Gi det til den som eier 023.

---

## Middels

### M1. Klubbens invitasjonskode

- **Objekt:** `clubs.join_code` med standarden `upper(substr(replace(gen_random_uuid()::text,'-',''),1,10))`, altså 10 hex-tegn = 40 bit. Den har ingen utløp. Appen har ingen rotasjon. `club_preview` og `join_club` har ingen hastighetsgrense, og `club_preview` viser ledige navn.
- **Angrep:**
  1. Med mange klubber kan en angriper gjette mot alle samtidig: 2^40 / (antall klubber · forsøk per sekund). Med 10 000 klubber og 200 forsøk i sekundet tar det om lag 6 døgn per treff.
  2. En gyldig kode gir navnene på de ledige plassene. Med ett kall tar angriperen et ledig navn, blir **aktiv med én gang** og leser alt i klubben: tropp, kvelder, runder, tråd, tips og veddemål.
  3. En kode som lekker (skjermbilde eller videresendt lenke), virker for alltid.
- **Fiks (024, avsnitt 2):** nye klubber får 12 tegn fra `23456789ABCDEFGHJKLMNPQRSTUVWXYZ` (60 bit, uten 0/O og 1/I). Det gjør gjetting uaktuelt. Eksisterende koder endres ikke, fordi det ville brutt lenker som er delt.
- **Anbefalt i appen:**
  - en knapp for arrangøren: «Ny kode» (`update clubs set join_code = …`, tillatt av `clubs_update`);
  - rotér koden på test og prod etter 024;
  - vurder at «ta ledig navn» også må godkjennes av arrangøren når appen er åpen (svar på åpent spørsmål 1 i `sql/README.md`).
- **Hastighetsgrense:** en ekte grense på `join_club` er vanskelig i SQL. Når koden ikke finnes, kastes en feil, og transaksjonen (med en eventuell telling) rulles tilbake. Med 60 bit trengs den ikke for nye koder.

### M2. Ingen kvoter (spam og kostnad)

- **Objekt:** `create_club`, `create_loose_round` og `start_loose_round`, direkte INSERT i `rounds`, `courses` (det felles biblioteket), `competitions` og `round_participants`, `thread_messages` og `activity`.
- **Angrep:** én konto lager 100 000 baner med støtende navn i det **felles** biblioteket, som alle ser. Den kan også fylle databasen med runder og konkurranser, eller sende hundrevis av meldinger og hendelser i en klubb, og hver av dem blir en push til alle (M3).
- **Fiks (024, avsnitt 3):** trigger `zz_quota` med rause grenser per innlogging:

  | Hva | Grense |
  |---|---|
  | Klubber | 10 per døgn |
  | Felles baner | 30 per døgn |
  | Løse runder | 50 per døgn |
  | Konkurranser uten klubb | 30 per døgn |
  | Deltakere per runde | 48 |
  | Meldinger | 60 per 10 min |
  | Hendelser | 200 per 10 min |

  Feilkoden er `54000`. SQL Editor, importen og serveren telles ikke. Appen bør vise meldingen fra feilen.

### M3. Falske hendelser og push fra medlemmer

- **Objekt:** policyen `activity_insert` (`is_club_member`) og `activity_before_insert`. Avsender (`actor_member_id`) settes av serveren, og bare `announcement`, `nudge`, `reminder` og mottakerlister er sperret for andre enn arrangøren. `kind` og `data` er frie.
- **Angrep:** et medlem skriver `kind = 'round_deleted'`, `big_score` eller `round_started` med `data.course_name = "Logg inn på http://…"`. `push-send` lager tekst av `data`, og alle i klubben får en push som ser ekte ut.
- **Fiks:** 024 begrenser mengden (200 per 10 min). Selve innholdet krever at hendelsene lages av serveren, for eksempel av triggere på `hole_scores`, `side_claims` og `rounds`, eller av en RPC som sjekker `kind` mot hva brukeren faktisk har gjort. Gjør det i en egen migrering når push-flyten endres. Til da er det tillit innad i klubben.

### M4. verify-purchase: kjøp uten `appAccountToken` kan tas av en annen konto

- **Objekt:** `recordFromTransaction` sjekker `appAccountToken` bare hvis den er satt. `record_purchase` lar første profil som sender en `original_transaction_id`, eie kjøpet.
- **Angrep:** en transaksjons-id lekker, for eksempel fra en kvittering, en supportsak eller et kjøp gjort utenfor appen (tilbudskode). Den som sender den først, får kjøpet. Den ekte kjøperen får `wrong_account`.
- **Fiks:** appen setter alltid `appAccountToken` til profil-id-en. Krev da at den er satt og lik brukeren (`wrong_account` ellers). Kjøp uten token behandles manuelt.
- **Ellers:** transaksjonen hentes av serveren fra Apple med vår egen nøkkel over TLS, så appen kan ikke dikte opp et kjøp. JWS-signaturen sjekkes ikke. Det er greit så lenge svaret kommer rett fra Apple. Når App Store Server Notifications kommer (de sendes til oss og ikke hentes), **må** x5c-kjeden verifiseres.

### M5. E-postkode (OTP): brute force og utløp

- **Objekt:** Auth-innstillingene. Lengde og utløp kan ikke leses med SQL. Standarden i Supabase er 6 sifre og 1 time.
- **Angrep:** 10^6 mulige koder i én time. Grensen for verifiseringer er per IP, så en angriper med mange IP-er har en reell sjanse mot en bestemt e-post.
- **Fiks (panelet):**
  - Email OTP Length: 8 (appen godtar 4–10 sifre, se `LoginInput.swift`).
  - Email OTP Expiration: 600 s.
  - Rate Limits: send og verifisering lavt.
  - Egen SMTP. Supabase sin innebygde e-post sender bare til medlemmer av teamet, så den må byttes uansett før appen åpnes.
  - CAPTCHA (Turnstile eller hCaptcha) på registrering og innlogging når appen åpnes. Det krever `captchaToken` i appen.

### M6. Brukerinnhold i det felles biblioteket kan ikke rapporteres

- **Objekt:** `courses` med `club_id` tom: navnene ses av alle innloggede. `report_content` godtar bare `message`, `image`, `member` og `profile`, og `resolve_report` krever en klubb.
- **Følge:** Apple 1.2 krever at brukerinnhold kan rapporteres og fjernes innen 24 timer. En støtende bane eller et støtende gjestenavn i en løs runde kan i dag ikke rapporteres.
- **Fiks (egen migrering):** `kind = 'course'` (og `round_participant` for gjestenavn) med `club_id` tom. Rapporter uten klubb går til oss, og en server-RPC skjuler eller sletter banen. Kvoten i 024 demper volumet til da.

---

## Lav

- **L1. `rls_auto_enable()`:** advisoren melder at anon kan kjøre den via `/rest/v1/rpc/rls_auto_enable`. Det er Supabase sin event trigger-funksjon (slår på RLS for nye tabeller i public). Kalt direkte gjør den ingenting, men den bør ikke ligge åpen. **024 avsnitt 4** tar rettigheten fra public, anon og authenticated. Event triggeren trenger den ikke.
- **L2. Standardrettighetene:** `pg_default_acl` gir anon (og PUBLIC for funksjoner) alt på nye tabeller, sekvenser og funksjoner i public. Hver migrering har til nå husket `revoke … from public, anon`. Glemmer én det, er funksjonen åpen for alle. **024 avsnitt 5** snur standarden: anon får ingenting av seg selv, og nye funksjoner er ikke åpne for PUBLIC. authenticated har standardrettigheten på tabeller som før, og migreringene gir den eksplisitt.
- **L3. Push-enheter:**
  - `register_push_device` gjør `on conflict (device_id) do update set user_id = …`. Den som kjenner en annens enhets-id, kan flytte enheten til sin konto, og da stopper push for eieren.
  - Et kall med en annens APNs-token sletter den registreringen.
  - Begge krever hemmeligheter appen aldri viser (identifierForVendor og token), så risikoen er lav.
  - **Fiks senere:** ved konflikt med en annen bruker, krev at tokenet er det samme.
- **L4. Rundekoden (018):** 10 tegn Crockford (50 bit) og 7 dagers utløp er bra. Men:
  - alle deltakere, også de som kom inn med koden, ser koden (`round_invites_select`);
  - `loose_round_invite` lar enhver deltaker lage en ny når den gamle går ut;
  - eieren kan ikke trekke koden tilbake;
  - en gjesteplass kan tas av den første som har koden.

  **Fiks senere:** bare eieren lager og fornyer koden, pluss `revoke_round_invite`.

  **022-utkastet** (versjonen under arbeid 07.10.2026 kl. 19.21, `competition_invites`) bruker samme mønster: `round_invite_code()` (50 bit) og 7 dager, og eieren og alle påmeldte ser og fornyer koden. Den som blir med, blir påmeldt. Da ser hen profilene til de andre påmeldte (`can_see_profile`) og alle startede runder som teller i konkurransen, med score (`round_in_readable_competition`). En kode som videresendes, gir altså innsyn i andres runder. Anbefalt i 022:
  - bare eieren lager, fornyer og trekker tilbake koden (`revoke_competition_invite`);
  - et tak på antall påmeldte per konkurranse;
  - helst at eieren godkjenner påmeldinger som kommer via kode, når konkurransen er åpen for alle.

  Gjetting er ikke et problem med 50 bit og utløp.
- **L5. Storage:**
  - Bøttene er private, med 3 MB og `image/jpeg` (bra), men MIME-typen er det klienten sender.
  - Det er ingen grense for antall filer per bruker.
  - `storage_can_read` ser ikke på blokkering, så bilder fra en blokkert person kan fortsatt hentes med stien.
  - Det finnes ingen UPDATE-policy, så ingen kan overskrive andres filer (bra). Sletting gjelder egne filer, eller arrangøren for bilder i tråden.
- **L6. Edge Functions:** `delete-account` og `verify-purchase` sender `error.message` (opptil 300 tegn) til appen, også feil fra PostgREST og App Store. Logg detaljene, og send en kort kode til klienten.
- **L7. Realtime:**
  - `postgres_changes` følger RLS for INSERT og UPDATE.
  - DELETE-hendelser sendes til alle som lytter på tabellen, med bare primærnøkkelen (replica identity er default på alle 21 tabellene). Det lekker id-er, ikke innhold.
  - Offentlige broadcast- og presence-kanaler kan brukes av hvem som helst med nøkkelen. Appen bruker dem ikke, men de kan brukes som gratis relé. Vurder «Private channels only» i Realtime-innstillingene når det er prøvd med appen.
- **L8. Auth-id-er:** `club_members.user_id` ses av alle aktive i klubben, og profil-id-er ses av alle man deler noe med. Etter 024 kan en id ikke misbrukes til H1. Det står igjen som informasjon.

---

## Info: det som er i orden

- **I1. RLS:**
  - Alle 39 tabellene i public har RLS.
  - `push_queue` har ingen policy og ingen rettigheter, altså stengt med vilje.
  - Viewet `round_roster` har `security_invoker = true`.
  - anon har ingen rettigheter på tabeller eller views i public.
  - Ingen policy er `true`.
  - SELECT-policyene går gjennom `is_club_member`, `can_read_round`, `can_read_competition` og `can_see_profile`, og de krever aktivt medlemskap, eierskap eller deltakelse. Klubbene er skilt med sammensatte fremmednøkler (`(id, club_id)`) på alle tabeller med klubb.
- **I2. SECURITY DEFINER:**
  - Alle 103 egne funksjoner med `security definer` i public har `search_path = ''`. Den 104. er Supabase sin `rls_auto_enable`, som har `pg_catalog`.
  - Alle RPC-ene sjekker `auth.uid()` og rettighetene før de skriver.
  - Id-er fra klienten (`member_id`, `round_id`, `profile_id` og `participant_id`) sjekkes mot `can_score`, `owns_member`, `is_round_organizer` eller `can_see_profile`.
  - Funksjonene for serveren kan bare kjøres av service_role: `claim_push_jobs`, `finish_push_job`, `push_job_payload`, `queue_evening_reminders`, `delete_account_data`, `account_storage_objects` og alle triggerfunksjonene.
  - Advisorens 63 meldinger om «authenticated kan kjøre SECURITY DEFINER» er med vilje (hjelpere i policyer og RPC-er).
- **I3. Kolonnevakter:**
  - `guard_profiles`: bare din egen profil.
  - `guard_club_members`: roller, seeding og status bare for arrangøren. 024 strammer inn `user_id`.
  - `guard_competitions`: `requires_purchase`, `entitlement_id`, eier, type og hovedturnering settes bare av serveren.
  - `guard_competition_participants`: bare status kan endres, og profilen må være synlig.
  - `rounds_guard_home`: eier, og ingen flytting mellom klubb og løs runde.
  - `round_participants_before_write`: `added_by`, og profilen må være synlig.
  - `courses_guard_library`: kilde og skaper.
  - `course_corrections_before_write`.
  - `tips_before_write`, `hole_scores_before_write` og `hole_stats_before_write` (hvem og når).
  - `entitlements` har ingen skrivetilgang fra appen.
- **I4. Storage:** `avatars` og `thread` er private, med 3 MB og `image/jpeg`. Policyene krever stien `<medlem>/<uuid>.jpg`. Du laster opp og sletter bare i din egen mappe (arrangøren kan slette i tråden). Du leser bare i klubber du er aktivt medlem av.
- **I5. Realtime:** publikasjonen har 21 tabeller, og alle har en SELECT-policy. `realtime.messages` har RLS uten policyer, så private kanaler er stengt.
- **I6. Hemmeligheten til push-webhooken:**
  - Den står i klartekst i definisjonen av triggeren `dd18_push_queue` (`pg_get_triggerdef`). Den ses av alle med tilgang til databasen (panelet og SQL Editor), men ikke via API-et.
  - Den er ikke i repoet eller i git-historikken.
  - Rotér den (`PUSH_HOOK_SECRET` og webhooken) hvis noen andre har hatt tilgang til databasen.
- **I7. Supabase-standard:** `net.*`, `supabase_functions.http_request` (SECURITY DEFINER) og tabellen `supabase_functions.hooks` er åpne for anon og authenticated. Det er ufarlig så lenge bare `public` (og `graphql_public`) er eksponert i Data API. pg_graphql er ikke installert.
- **I8. Små lesehjelpere uten medlemssjekk:** `bet_accepts_stakes`, `tips_open`, `tips_deadline`, `round_is_active`, `can_see_profile` og lignende svarer ja/nei for en hvilken som helst id. Id-ene er tilfeldige uuid-er, og svarene lekker ingenting av verdi.
- **I9. Edge Functions:**
  - `delete-account` finner brukeren fra JWT-en (`/auth/v1/user`), aldri fra innholdet. Den sletter bare den innloggede, og service role-nøkkelen forlater ikke funksjonen.
  - `push-send` sammenligner hemmeligheten i konstant tid (lengden lekker, men den er fast) og bruker service role bare mot egne RPC-er.
  - `verify-purchase` henter transaksjonen selv fra Apple og sjekker bundle-id og produkt (se H3 og M4).
  - JWT-sjekken må stå **på** for `delete-account` og `verify-purchase`, og av bare for `push-send`.
- **I10. Profiler:** `ensure_profile` og `profiles_on_new_user` gjelder bare din egen id og overskriver aldri det du har satt. Ingen kan ta over en annens profil. Navnet fra `raw_user_meta_data` velges av brukeren, akkurat som når hen endrer det i appen.

---

## Hva 024 gjør, og hva som er prøvd

`sql/024_sikkerhet.sql` er idempotent og ligger i én transaksjon. `revoke` kommer etter hver `create or replace`, og fila har kontroll med ok-kolonne og rullebakke, som 017–021. Den gjør dette:

1. `guard_club_members`: H1 og H2.
2. `club_join_code()` og ny standard for `clubs.join_code` (60 bit): M1 for nye klubber.
3. `quota_guard()` med triggeren `zz_quota` på sju tabeller, og fire indekser for tellingen: M2 (og mengden i M3).
4. Rettigheten til `rls_auto_enable()` tas bort, hvis funksjonen finnes: L1.
5. Standardrettighetene for nye objekter: L2.

Ingen policy, kolonne eller RPC endres. `join_club` og `club_preview` er urørt.

**Prøvd lokalt** (Postgres 16.2, egen datakatalog på port 54424, stoppet etterpå):

- 001–021 (019 inkludert), så 024 to ganger: uten feil.
- `lokal/024_prove.sql`: **39 av 39 ok**. Uten 024 gir den samme prøven 7 FEIL. Det viser at H1 og H2 finnes i dag.
- De eldre rolleprøvene med 024 på plass:

  | Prøve | Resultat |
  |---|---|
  | 001 | 63 ok |
  | 010 | 68 ok |
  | 012 | 89 ok |
  | 017 | 129 ok |
  | 018 | 82 ok |
  | 019 | 89 ok |
  | 020 | 73 ok |
  | 021 | 35 ok |

  Det er like mange som uten 024. 008-prøven feiler likt med og uten 024, fordi `register_push_token` ble erstattet i 010.
- 022 og 023 kan kjøres etter 024: `022_prove` 107 ok og `023_prove` 40 ok, ingen FEIL.
- Kontrollen ga 8 av 8 ok. Rullebakken (pluss vakta fra 001) og en ny kjøring av 024 virket.

**Ikke prøvd:** ekte Supabase (Postgres 17, PostgREST, Realtime og Storage-API-et). Endringen i standardrettighetene (`alter default privileges for role postgres`) forutsetter at migreringene kjøres som `postgres` i SQL Editor, slik de gjør nå.

## Hva du må gjøre i panelet (kan ikke settes med SQL)

1. **Authentication → Sign In / Providers → Email:** slå på **Confirm email** (K1). Slå på **Secure email change**. Sett **Email OTP Length** til 8 og **Email OTP Expiration** til 600 s (M5).
2. **Authentication → Passwords** (eller «Attack Protection»): slå på **Leaked password protection** og sett minstelengden til 10 tegn eller mer. Passord kan brukes selv om appen ikke bruker dem.
3. **Authentication → Rate Limits:** lave grenser for e-post sendt, verifiseringer og registreringer per IP. **Authentication → SMTP:** egen SMTP før appen åpnes.
4. **Authentication → Attack Protection:** CAPTCHA (Turnstile) når appen sender `captchaToken`.
5. **Settings → API → Exposed schemas:** bare `public` (og `graphql_public`). Ikke `net`, `supabase_functions`, `extensions` eller `storage` (I7).
6. **Edge Functions:** JWT-sjekk **på** for `delete-account` og `verify-purchase`, og **av** bare for `push-send`. Legg inn `APPSTORE_ALLOW_SANDBOX=false` i prod når H3 er rettet.
7. **Realtime → Settings:** vurder «Private channels only» etter at det er prøvd med appen (L7).
8. **Database → Webhooks:** rotér push-hemmeligheten hvis andre har hatt tilgang til databasen (I6).
9. Etter at 024 er kjørt: **rotér invitasjonskoden** til klubbene på test (og senere prod), og sjekk kontroll 7 (ingen ledige navn med roller).
