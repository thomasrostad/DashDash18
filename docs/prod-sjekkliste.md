# Sjekkliste: Atten i prod

Startet 20.10.2026. Kilder: `sql/README.md`, `docs/gjoremal.md`, `docs/lanseringssjekk.md` og en gjennomgang av test-basen mot filene i `sql/`. Vi tar ett steg om gangen og krysser av her.

**Hvem:** (C) = Claude gjør det, (T) = Thomas gjør det, (C+T) = Claude forbereder og Thomas sier ja eller klikker.

Prod-prosjektet er **Atten Prod** (`wxabhadvuzyrmndxpuza`, `eu-west-1`, Postgres 17.11), opprettet 20.10.2026. Test er `tsekialrxuhrugscosgi`.

## 1. Forberedelse i repoet (C)

- [x] 1.1 Fjern iCloud-kopiene i `sql/` (`043_tv_liga 2.sql`, `052b_bet_settle_utlosing 2.sql`, identiske med originalene).
- [x] 1.2 Sjekk test-basen mot filene. Alle tabeller, funksjoner, policyer, bøtter og realtime-tabeller på test finnes i en fil. Bare `calendar_feed` og `tv_board_data` er åpne for anon, og det er med vilje.
- [x] 1.3 Prøvekjør alle migreringene i prod-rekkefølgen (avsnitt 3) mot en tom, lokal Postgres (PG 16.2, `lokal/stub.sql` og en ekstra stub for realtime, Vault, pg_net og pg_cron). *(20.10: alle 58 filer med 062 gikk uten feil, og kontrollene i filene var ok. Resultat: 67 tabeller og 2 views i public, 350 funksjoner, 140 policyer, ingen tabell uten RLS, 27 tabeller i realtime.)* **Rekken skal kjøres bare én gang:** 001, 004, 017 og 044 feiler på en ferdig base fordi `seasons` er et view etter 035.
- [x] 1.4 *(062, kjørt på test 20.10)* Gjør 052b klar for prod: URL-en til `bet-settle` er hardkodet til test (`052b_bet_settle_utlosing.sql:33` og `:53`).
- [x] 1.5 *(062, kjørt på test 20.10)* Lag kjørbar SQL for det som bare står som kommentar i filene: webhooken `dd18_push_queue` (010) og cron-jobbene `dd18-slope-sync` (029), `dd18-waitlist-offers` (032) og eventuelt `dd18-paaminnelse` (010). Hemmelighetene skal ligge i Vault, ikke i SQL-en.
- [x] 1.6 Rett opp statusen i `sql/README.md`: 055 er kjørt på test. Filhodene i 024 og 040–043 sier fortsatt «IKKE KJØRT», men de får stå, så filene er de samme som ble kjørt på test. Statusen i README er den som gjelder.
- [ ] 1.7 Appen: legg til prod-miljø i `ci_scripts/ci_post_clone.sh` og `AppEnvironment.current`, så et bygg kan gå mot prod.
- [ ] 1.8 Avklar `053` (gjennomføringsplanen steg 12, «App Store-grunnmur og prod»): skal den med før prod, eller kan prod settes opp uten den?

## 2. Prod-prosjektet (T)

- [x] 2.1 *(20.10, heter Atten Prod, foreløpig gratisplan)* Opprett **Dash18 Prod** i samme organisasjon, region `eu-west-1` som test. Pro-plan.
- [ ] 2.2 Backup: slå på PITR og lag `docs/backup.md` etter en prøvegjenoppretting (lanseringssjekk punkt 9).
- [x] 2.3 *(20.10, samme versjoner og skjemaer som test)* Database → Extensions: slå på **pg_cron** og **pg_net** (ingen fil lager dem, og 052b feiler uten).
- [x] 2.4 *(20.10: likt test. Leaked password protection krever Pro og er av, som på test)* Authentication som på test (gjøremål A1, 6–8): Confirm email, Secure email change, OTP 8 sifre og 600 s, Leaked password protection, lave rate limits, bare `public` i Data API, Auth 2.185.0 eller nyere.
- [x] 2.5 *(20.10)* Apple-innlogging i prod-Auth med Client ID `com.dashdash18.app`. Site URL `https://dashdash18.com`. `dashdash://login-callback` legges i Redirect URLs først når Google slås på (test har den heller ikke).
- [ ] 2.6 *(SMTP gjort 20.10: Resend med egen nøkkel for prod, avsender «Atten» <noreply@dashdash18.com>, 30 e-poster per time. E-postmalene «Confirm sign up» og «Magic link or OTP» viser koden, sier Atten og ti minutter.)* Egen SMTP (gjøremål 13) og CAPTCHA (Turnstile). CAPTCHA gjenstår.
- [x] 2.7 Send prosjekt-ref og publishable key til Claude. Aldri secret key i chatten.

## 3. Databasen i prod (C, etter ja fra Thomas)

Rekkefølgen er den samme som på test, ikke den numeriske. 044 lager policyer på `seasons`, så den må kjøres **før** 035, som gjør `seasons` til et view. Kontrollen nederst i hver fil kjøres før neste fil.

001, 002, 004, 005, 006, 007, 008, 010, 011, 012, 015, 016, 014, 017, 020, 018, 019, 021, 024, 022, 023, 025, 026, 027, 029, 030, 031, 032, 033, 036, 037, 038, 039, 040, 041, 042, 043, 034, 044, 045, 047, 046, 049, 050, 051, 048, 052, 052b, 054, 055, 035, 056, 057, 058, 059, 060, 061, 062.

Skal ikke kjøres: 009 (tatt med i 011), `010_kontroll.sql`, `lokal/` og `import/`.

- [x] 3.1 *(20.10, laget av `prod_secrets.sh`; prøvekall til push-send og bet-settle ga 200)* Vault: `project_url`, `push_hook_secret`, `bet_settle_secret` og `slope_sync_secret`, med nye verdier for prod (ikke gjenbruk fra test).
- [x] 3.2 *(20.10, alle 58 uten feil)* Kjør migreringene i rekkefølgen over.
- [x] 3.3 Webhooken og cron-jobbene kommer med 062. Ingen webhook skal lages i dashboardet.
- [x] 3.4 *(20.10: alle 879 objekter er like på test og prod, med funksjonskroppene; eneste forskjell er Supabase sin egen `rls_auto_enable`)* Kontroller: Security Advisor, anon-tilgang (bare `calendar_feed` og `tv_board_data`), realtime-publikasjonen (27 tabeller), bøttene `avatars` og `thread`, og `app_config` (`min_ios_build`, `waitlist_offer_hours`).
- [ ] 3.5 Første slope-sync for hånd (030).

## 4. Edge Functions i prod (C)

- [x] 4.1 *(20.10: alt unntatt `APPSTORE_*`)* Secrets for prod: `APNS_*` (produksjonsmiljø), `PUSH_HOOK_SECRET`, `BET_SETTLE_SECRET`, `SLOPE_SYNC_SECRET`. `APPSTORE_*` venter på kjøpene. `APPSTORE_ALLOW_SANDBOX` skal ikke settes i prod.
- [x] 4.2 *(20.10)* Deploy `push-send`, `bet-settle` og `slope-sync` med `--no-verify-jwt`, og `delete-account` med JWT-sjekk. `bet-settle` deployes fra roten av repoet (den importerer `web/golfgutu-core`).
- [ ] 4.3 `verify-purchase` venter på kjøpene (avsnitt 6).

## 5. Web og app mot prod (C+T)

- [ ] 5.1 Workeren `atten-lenker`: `SUPABASE_URL` til prod og ny `SUPABASE_KEY`. Det finnes bare én worker, så TV-, Tavla- og kalenderlenkene mot test slutter å virke ved byttet. `APP_STORE_URL` og teksten «hent appen» sier TestFlight.
- [ ] 5.2 Web-admin: bygg på nytt med prod-verdier (`VITE_SUPABASE_URL` og `VITE_SUPABASE_KEY` blir bakt inn i bygget).
- [ ] 5.3 Xcode Cloud: prod-verdiene i en egen workflow (T), sånn at TestFlight fra test kan gå videre.
- [ ] 5.4 Prøv appen mot prod med to kontoer: innlogging, klubb, runde, push og sletting av konto.

## 6. App Store (T, fra gjøremål C)

- [ ] 6.1 Personvern og vilkår: navn eller firma, org.nr., adresse og verneting. Claude publiserer dem og setter `LegalLinks` (Apple krever dette).
- [ ] 6.2 App Store Connect: navnet Atten, Paid Apps Agreement, kjøpene `no.atten.turnering.sesong` og `.ar`, In-App Purchase-nøkkelen, App Privacy, support-URL, aldersgrense, demokonto og sandbox-tester.
- [ ] 6.3 Xcode: capability In-App Purchase. Slå av «Default»-workflowen i Xcode Cloud.
- [ ] 6.4 Google OAuth-klient med prod-redirecten (valgfritt, flagget er av).
- [ ] 6.5 Deretter: deploy `verify-purchase` og slå på `PurchaseFeature` og `GoogleLoginFeature`.

## 7. Før lansering (C, fra lanseringssjekken)

- [ ] 7.1 Feilsporing (MetricKit eller Sentry) og norske feiltekster i stedet for systemets.
- [ ] 7.2 Grenser for antall forsøk der de mangler, og grense på dashdash18.com.

## 8. Byttet for gjengen (fase 9, utsatt)

Thomas tar dette opp når det passer. Gjelder prøveimport fra PWA-en og byttedagen (`docs/import-plan.md`). NB: etterfyllingene i 017, 048, 052 og 054 gjør ingenting på en tom base, så DashImport må lage de samme radene for importerte data.
