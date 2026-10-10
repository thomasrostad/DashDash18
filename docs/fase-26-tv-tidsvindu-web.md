# Fase 26: TV med kode, turneringer med tidsvindu og web-admin

Thomas 10.10.2026:
- «TV-visning bør være tilgjengelig fra en ekstern enhet via en kode.»
- «Turneringer med tidsvindu bør være tilgjengelig som en mulighet å velge.»
- «Adminpanelet bør være tilgjengelig i en browser slik at man kan planlegge utenfor telefonen ved større turneringer eller golfklubber som skal planlegge for sine medlemmer.»

Valg (samme dag): serveren regner tabellen (regelmotoren også i TypeScript), «beste N teller» i tidsvinduet, og web-admin med alt som i appen.

## 1. Regelmotoren i TypeScript

- `web/golfgutu-core/`: GolfgutuCore skrevet om til TypeScript, uten avhengigheter. Kjøres og testes med Node 24 (`node --test`), og bygges inn i Cloudflare Worker og web-appen.
- **Paritet:** testene leser de samme JSON-fixturene som Swift-testene (`Packages/GolfgutuCore/Tests/GolfgutuCoreTests/Fixtures`), og hele sesongtabeller sammenlignes med gylne filer laget av Swift. Golfgutu-oppsettet skal gi nøyaktig samme svar som appen og PWA-en.
- Det samme grunnlaget kan brukes av Android senere (ROADMAP fase 24, «én fasit»).

## 2. TV-visning med kode

| Del | Hva |
|---|---|
| SQL 041 | `tv_codes`, `tv_code(turnering, forny)` (arrangøren), `tv_code_revoke`, `tv_board_data(kode)` (anon): rådataene som `tavla_data`, uten innlogging og bilder |
| Worker | `dashdash18.com/tv/KODE`: henter `tv_board_data`, regner tabellen med `web/golfgutu-core` i Workeren, og gir en fullskjermside som henter på nytt hvert 15. sekund |
| Appen | «TV-kode» i TV-visningen og på arrangørsiden: koden, lenken og QR-koden, «Ny kode» og «Trekk tilbake» |

Første versjon gjelder turneringer med kvelder (sesongen og seriene). Liga og morro kommer i samme lesevei når Workeren regner dem.

## 3. Turneringer med tidsvindu («Spill når det passer»)

| Del | Hva |
|---|---|
| SQL 042 | `competitions.auto_count`. Når en påmeldt starter eller låser en runde i perioden (løs runde eller klubbrunde), kobles den til turneringen av seg selv. Også når en påmeldt legges til i en runde som går |
| Appen | I «Ny turnering» (liga og morro): «Spill når det passer» med periode og «de beste N teller». Turneringssiden viser perioden og hvor mange runder hver har spilt |

Beste N står i regelsettet som før (`competitionRules.league.bestRounds` / `fun.bestRounds`). Golfgutu og sesongene berøres ikke.

## 4. Web-admin (admin.dashdash18.com)

Hele arrangørsiden i nettleseren, med samme innlogging (e-postkode og Apple) og de samme tilgangsreglene (RLS og RPC-ene) som appen. Ingen egne servertilganger: nettleseren snakker med Supabase med publishable key, akkurat som appen.

Forslag til teknikk: TypeScript, Vite og React, `@supabase/supabase-js` og `web/golfgutu-core`, levert som statiske filer fra Cloudflare (samme konto som dashdash18.com). Krever godkjenning av nye avhengigheter for web-delen.

Rekkefølge:
1. Innlogging, klubbvelger og turneringsvelger. Lesing av turneringer, terminliste og tropp.
2. Turneringer: ny, endre regler, påmelding og venteliste, stab, sletting.
3. Terminliste og spilledager: ny, endre, slette, sosialkomité. Tropp: godkjenne, roller, handicap, invitasjon med QR.
4. Startliste og grupper, oppsett av runder (bane, tee, form, båser), start, lås, avkort og rett score.
5. Tabeller og «Alle runder» med regelmotoren i TypeScript, eksport (CSV) og utskrift av startliste.

Hver del får tester mot test-Supabase med en egen testbruker, og ingenting går mot prod før Thomas sier ja.

## Status

- [ ] TypeScript-regelmotoren (agent i gang 10.10).
- [ ] 041 og 042: skrevet og prøvd lokalt (`sql/lokal/041_042_prove.sql`, 18 av 18; 033-prøven 81 av 81 med 041 og 042 inne). Venter på godkjenning.
- [ ] TV-siden i Workeren og TV-kode i appen.
- [ ] «Spill når det passer» i appen.
- [ ] Web-admin, del 1–5.
