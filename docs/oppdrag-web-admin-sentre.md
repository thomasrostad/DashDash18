# Oppdrag: adminsiden klar for klubber og simulatorsentre (pakke 1 og 2)

Skrevet 23.10.2026 etter en gjennomgang av `web/admin` mot appen. Start en ny økt og si: «Les `docs/oppdrag-web-admin-sentre.md` og gjør oppdraget.»

## Bakgrunn

`web/admin` (Vite, React, TypeScript, `@supabase/supabase-js`, `web/golfgutu-core`) er arrangørsiden i nettleseren. Den fulgte appen til 12.10.2026 (steg 1–11), men nesten ingenting av det appen har fått siden, er med. Målet er at klubber og simulatorsentre kan styre turneringer fra en PC. Thomas pitcher Atten til et simulatorsenter i Oslo med en prøveliga.

Funn 23.10:
- **Live-siden er ikke koblet til noen database.** https://admin.dashdash18.com er bygget uten miljøvariabler. Bundelen peker på `http://localhost` og viser bare «Mangler VITE_SUPABASE_URL eller VITE_SUPABASE_KEY». `web/admin/.env.local` peker på test (`tsekialrxuhrugscosgi`). Prod er `wxabhadvuzyrmndxpuza`.
- **Veddemål vises i prod.** `TournamentDetail.tsx` viser «Veddemål»-bryteren uten å skjule den i prod. Appen har veddemål av i prod etter App Review 2.3.6 (#166, #170).
- **Innloggingen mangler CAPTCHA.** `Login.tsx` kaller `signInWithOtp` uten captchaToken. Appen fikk Turnstile i #169, og CAPTCHA skal slås på i prod-Supabase. Da slutter web-innloggingen å virke.
- **Web har allerede:** simulator eller ekte bane, «Trackman fordeler slagene», skjul siste hull, slope.no, roller og funksjonærer i startlista.
- **Web mangler:**
  - å lage og endre baner (den gjør bare `select` på `courses`)
  - deltakere uten innlogging (059–061: `add_competition_participants`, NGF-nummer, `competition_invite`)
  - «lim inn liste» i Troppen (#145)
  - TV-kode (041/043, `tv_code`)
  - Del tavla (056, `tavla_share_code`)

## Pakke 1: gå live

1. **Skjul veddemål på web i prod**, på samme måte som appen avgjør det (se `BetsFeature`, #166 og #170). Bruk ett miljøflagg, ikke et nytt system.
2. **Turnstile-CAPTCHA ved innlogging med e-postkode.** Gjenbruk mønsteret fra appen (#169, `CaptchaFeature`, `/captcha` i `web/atten-lenker`) der det passer. Si fra hva Thomas må gjøre i Cloudflare, for eksempel å legge `admin.dashdash18.com` på widgeten.
3. **Prod-oppsett.** Lag et bygg mot prod-Supabase med publishable key, uten hemmeligheter i repoet, og en tydelig måte å bygge for test og for prod. **Ikke deploy.** Thomas godkjenner deploy etter å ha sett PR-en.

## Pakke 2: det et senter trenger

4. **Lage og endre baner, også simulatorbaner.** Det gjelder navn i simulatoren, 9 eller 18 hull, par, valgfri indeks og «Fyll standard par 72». Gjør det som `CourseEditView.swift` og `CourseDraft.swift`, med samme tilgang som appen.
5. **Deltakere uten innlogging.** Lim inn en liste (`add_competition_participants`, høyst 300), med NGF-nummer og turneringslenken (`competition_invite`). Se `ParticipantInviteViews.swift` og sql/059–061.
6. **Troppen:** legg til mange navn på én gang, som i #145.
7. **TV-kode og Del tavla på turneringssiden.** Vis koden, lenken og QR-koden, med «Ny kode» og «Trekk tilbake», som `TVCode.swift` og `TavlaShare.swift`.

## Slik jobber du

- Les `CLAUDE.md`, `ROADMAP.md`, `web/admin/README.md` og `docs/fase-26-tv-tidsvindu-web.md` først.
- Følg reglene der:
  - egen branch fra oppdatert `main`, og PR mot `main`
  - ingen endringer i Supabase uten godkjent SQL
  - forklar før du endrer, og bekreft med kjørte tester
- Gjenskap oppførselen i appen, med samme sjekker og norske tekster.
- Skriv tester i `web/admin/test`, og kjør `npm test` og `npm run build`.
- Trenger noe SQL: stopp og vis SQL-en til Thomas.
- Lag to PR-er: først pakke 1, så pakke 2. Web-PR-er trenger ikke Xcode Cloud, så spør om `[ci skip]` i tittelen.
- Oppdater `web/admin/README.md`.

## Ferdig betyr

- PR-ene er åpne, og testene og bygget er grønne.
- Beskrivelsen sier hva som er prøvd mot test-Supabase, hva Thomas må prøve selv (innlogging) og hva han må gjøre før deploy.
- Ingen merge og ingen deploy før Thomas sier ja.
