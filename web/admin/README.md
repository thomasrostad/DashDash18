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

## Kom i gang

```sh
cd web/admin
cp .env.example .env.local   # fyll inn URL og publishable key for test
npm install
npm run dev                  # http://localhost:5178
npm test                     # node --test
npm run deploy               # bygger og legger ut på admin.dashdash18.com (Cloudflare, wrangler)
```

Teknikk: Vite, React 18, TypeScript, `@supabase/supabase-js` (godkjent av Thomas 10.10.2026). Faste versjoner i
`package.json`. Statiske filer fra Cloudflare Workers (`wrangler.toml`, `not_found_handling = single-page-application`).

Innlogging på web oppretter ikke nye brukere (`shouldCreateUser: false`): logg inn i appen første gang.
Apple-innlogging på web krever en egen Services ID hos Apple og er ikke med ennå.
