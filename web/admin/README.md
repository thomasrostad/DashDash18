# Atten · Arrangør (web-admin)

Arrangørsiden i nettleseren: https://admin.dashdash18.com. Samme innlogging (e-postkode), samme Supabase og
samme tilgangsregler (RLS og RPC-ene) som appen. Bare publishable key; ingen egne servertilganger.
Plan: `docs/fase-26-tv-tidsvindu-web.md`.

## Status

- [x] Del 1 (10.10.2026): innlogging med e-postkode, klubbvalg (klubbene der du er arrangør), turneringer,
  terminliste og tropp (lesing).
- [x] Del 2 (10.10.2026): turneringssiden med påmeldte, påmelding (åpen, hvem, plasser, venteliste, «Finn turneringer»), venteliste, stab (legg til, fjern), «Spill når det passer» og sletting.
- [x] Del 2b (10.10.2026): «Ny turnering» med de fire oppsettene fra regelmotoren (serie med antall og ordet for dagen, start nå; cup og morro med hvem som er med, påmelding, periode og «Spill når det passer»), og reglene på turneringssiden (antall, hva som teller, beste N, ordet, sidepremier, deltakerpoeng, handicapandel), validert av regelmotoren.
- [x] Del 3 (10.10.2026): terminliste (ny dato i valgt turnering, endre, slette, sosialkomité) og tropp (godkjenne og avvise, arrangør og kasserer, navn, handicap og seeding direkte i tabellen, arkivere og gjenopprette, legge til et ledig navn, invitasjonslenken).
- [x] Del 4 (10.10.2026): rundene på en spilledag, fra «Runder» i terminlista (`src/rounds/`). Lista med status
  (kladd, pågår, låst). «Sett opp runden» som appens hurtigstart: bane (klubbens og «Fra slope.no» med hull) og tee,
  start (hull 1 eller 10, 9 eller 18 hull) og første tee, spillere fra påmeldingen og båser/flighter fordelt etter
  matchene med markør (flytt, gjør til markør, ta ut og inn), form fra regelmotoren, lag, matcher, longest drive og
  nærmest pinnen, vekt, Trackman og handicapandel. Lagres som kladd (`rounds` + `set_round_setup`) eller startes
  (`start_round` med spillehandicap). Lås, slett (`delete_round`, ikke låste), «Avslutt kvelden» med spørsmål om
  avkorting, hele runden som tabell med «Rett en score» (`save_hole`) og «Avkort runden», og startlista (pulje,
  tid, starthull, bås/tee og funksjonær, `save_start_list`). Samme sjekker og norske feilmeldinger som appen.
  Ikke med: «Teller også i …» (`set_round_competitions`) og aktivitetsloggen («Ny runde», «Runde låst», plassbytte).
- [x] Del 5 (10.10.2026): fanen «Tabeller» (`src/standings/`). Velg turnering (serie, liga, morro eller cup).
  Serien hentes med `tavla_data` (sql/036) og sesongraden og regnes med `TavlaStandings`; liga og morro hentes
  som `CompetitionQueries.detail` i appen (påmeldte, koblede runder med alt under, tropp, `round_roster`,
  `round_participants` og profiler) og regnes med `CompetitionScope` og `LeagueStandings`. Tabellen viser plass,
  navn, poeng og linja under som i appen. «Alle runder» har poeng, slag og mot par, beste i runden i gull, sum,
  dempede runder (beste N) og scorekortet hull for hull bak hver rute (Ut/Inn, par, slag, poeng). Cupen vises
  som runder med kampene (`CupStandings`). «Last ned CSV» for tabellen og «Alle runder» (semikolon,
  desimalkomma, UTF-8 med BOM) og «Skriv ut» med eget utskriftsoppsett. Regelmotoren importeres direkte fra
  `../golfgutu-core/src` (tsconfig `include` og `server.fs.allow` i `vite.config.ts`). `test/standings.test.ts`
  sjekker tabellene, «Alle runder», scorekortene og cupen mot appens fasit (`tavla.forventet.json`).
- [x] Pakke 1, gå live (23.10.2026): egne bygg for test og prod med vakter, veddemål skjult i prod og Turnstile ved
  innlogging med e-postkode (se «Miljø» under). Plan: `docs/oppdrag-web-admin-sentre.md`.
- [x] Pakke 2, det et senter trenger (23.10.2026):
  - Fanen «Baner» (retten «Runder og føring», `src/courses.ts`): lage, endre og slette klubbens baner, simulator
    eller ekte, med navn i simulatoren, 9 eller 18 hull, par per hull, valgfri indeks og lengde, rating, «I bruk»
    og «Fyll standard par 72». Samme sjekker og tekster som `CourseDraft.swift`; lagres med `save_course`. Ikke med:
    tees og slope.no, og «Bekreft mot skjermen».
  - Deltakere uten innlogging på turneringssiden (klubbturneringer med påmelding, sql/059–061): lim inn lista
    (navn, handicap, NGF-nummer, høyst 300, `add_competition_participants`) og del lenken til turneringen
    (`competition_invite`, «Ny kode», «Trekk tilbake»). Troppen merker deltakere med «Deltaker».
  - Troppen: «Legg til mange (lim inn liste)», høyst 200 navn i én skriving, som #145.
  - TV-kode og «Del tavla» på turneringssiden (sql/041, 056): koden, lenken, «Ny kode»/«Ny lenke» og «Trekk tilbake».
  - Innlimingen deler logikk (`src/listImport.ts`) og testes mot appens tilfeller og `DashDash18Tests/DegFixtures.json`.

## Kom i gang

```sh
cd web/admin
mkdir -p env/test && cp .env.example env/test/.env   # URL og publishable key for test
npm install
npm run dev                  # http://localhost:5178, mot test
npm test                     # node --test
npm run build:test           # bygg mot test (npm run build gjør det samme)
npm run build:prod           # bygg mot prod, fra env/prod/.env
npm run deploy               # build:prod og legger ut på admin.dashdash18.com (Cloudflare, wrangler)
```

## Miljø: test og prod

Miljøet er byggemodusen (`--mode test` eller `--mode prod`, `src/env.ts`). Hvert miljø har sin egen fil utenfor git,
`env/test/.env` og `env/prod/.env` (mal: `.env.example`), og Vite leser bare fila for modusen, så verdier fra test
aldri blandes inn i prod. Bygget stopper hvis URL eller nøkkel mangler, hvis prod-adressen (`wxabhadvuzyrmndxpuza`)
står i test eller en annen adresse i prod, eller hvis nøkkelen er den hemmelige. Samme regler som `AppConfig` i appen.

- **Veddemål** vises bare i test, som `BetsFeature` i appen (av i prod etter App Review 2.3.6). Slettevarselet
  nevner dem heller ikke i prod.
- **CAPTCHA:** Med `VITE_TURNSTILE_SITE_KEY` viser innloggingen Cloudflare Turnstile før koden sendes, og tokenet
  følger med `signInWithOtp` (som `CaptchaFeature` i appen, #169). Samme skript og nøkkelregel som `/captcha` i
  `web/atten-lenker`. Tom verdi: ingen sjekk. Når CAPTCHA er slått på i Supabase, må site key-en være satt, ellers
  virker ikke innloggingen på web. Domenet (`admin.dashdash18.com`, og `localhost` for utvikling) må være godkjent
  på widgeten i Cloudflare.

Teknikk: Vite, React 18, TypeScript, `@supabase/supabase-js` (godkjent av Thomas 10.10.2026). Faste versjoner i
`package.json`. Statiske filer fra Cloudflare Workers (`wrangler.toml`, `not_found_handling = single-page-application`).

Innlogging på web oppretter ikke nye brukere (`shouldCreateUser: false`): logg inn i appen første gang.
Apple-innlogging på web krever en egen Services ID hos Apple og er ikke med ennå.
