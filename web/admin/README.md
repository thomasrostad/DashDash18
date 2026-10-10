# Atten · Arrangør (web-admin)

Arrangørsiden i nettleseren: https://admin.dashdash18.com. Samme innlogging (e-postkode), samme Supabase og
samme tilgangsregler (RLS og RPC-ene) som appen. Bare publishable key; ingen egne servertilganger.
Plan: `docs/fase-26-tv-tidsvindu-web.md`.

## Status

- [x] Del 1 (10.10.2026): innlogging med e-postkode, klubbvalg (klubbene der du er arrangør), turneringer,
  terminliste og tropp (lesing).
- [x] Del 2 (10.10.2026): turneringssiden med påmeldte, påmelding (åpen, hvem, plasser, venteliste, «Finn turneringer»), venteliste, stab (legg til, fjern), «Spill når det passer» og sletting.
- [ ] Del 2b: ny turnering og regler (venter på regelsettmalene i `web/golfgutu-core`).
- [ ] Del 3: terminliste og spilledager (ny, endre, slette, sosialkomité), tropp (godkjenne, roller, handicap, invitasjon med QR).
- [ ] Del 4: startliste og grupper, oppsett av runder, start, lås, avkort og rett score.
- [ ] Del 5: tabeller og «Alle runder» med regelmotoren i TypeScript (`web/golfgutu-core`), eksport og utskrift.

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
