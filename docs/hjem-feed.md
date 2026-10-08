# Hjem-fanen: aktivitetsfeed (forslag til sparring)

Repo: `thomasrostad/DashDash18` (SwiftUI, iOS 26). Forslaget bygger på fanene i `docs/visjon-apen-app.md`: **Hjem · Spill · Konkurranser · Deg**. Hjem skal vise det som har skjedd i det siste på tvers av alle konkurranser og runder du er med i.

## Om filene
`docs/design/hjem-feed/Hjem.dc.html` er en **designreferanse laget i HTML**, ikke kode som skal kopieres. Den skal gjenskapes i SwiftUI med det eksisterende designsystemet (`DashDash18/DesignSystem/`). Åpne fila i nettleseren sammen med `support.js` (stilarkene under `_ds/` mangler i pakken, men skjermene tegnes riktig uten dem).

Fidelity: **hi-fi** for farger, type og komponenter (alt hentet fra `DDPalette`, `DDFonts`, `DDSurfaces`, `DDLabels`, `DDSocial`, `DDStatTiles`, `DDButtons`). Innhold og navn er oppdiktet. Ikonene er Lucide-streker som erstatning for SF Symbols.

## To retninger

### 1a – Kronologisk feed
Én tidslinje, nyeste først, gruppert i **I dag · I går · Tidligere** (Varsler har i dag bare «I dag» og «Tidligere», se `ActivityFeed.sections`).

Fra toppen:
1. **Filterpiller** (vannrett rull): Alt · én per klubb/konkurranse · Løse runder. Valgt = `accentLime #6BE07A` / `#0F2E17`, ellers kort med hårstrek `#D5D5D5` (samme logikk som `DDChoiceButtonStyle`).
2. **Pågår nå** – svart `.stat`-kort (radius 30, padding 22): live-pille, bane + rundenummer, «Teller i Jakkeracet og Morrocupen · bås 2», Bayen nå topp 3 (deg i gult `#F5C842`), gul hovedknapp «Fortsett føringen» (56 høy).
3. **Neste kveld** – standardkort med dato, nedtelling (sol-pille) og svarknappene Kommer / Usikker / Kommer ikke (som `SignupSection`), så man kan svare rett fra Hjem.
4. **Feed-kort**, fire typer:
   - **Din runde** (stort kort, radius 30): bane, poeng i 52 lett, plass, scoremerker (Birdie/Par/Bogey/Dobbel med tonene fra `ScoreName.tone`), earth-stripe med innsikt («Beste runde på … i år»), vinnerlinje og «Del» (→ `ResultShare`).
   - **Bragd** (eagle, albatross, hole in one fra `big_score`): avatar, hvem/hvor/tid, sol-blokk med slag stort, reaksjonsbrikker (`DDReactionChip`) og konkurranse-pille.
   - **Tabell** (`lead_changed` + ny type for plassbytte): tekst, mini-tabell topp 3 med deg uthevet (`youRow`), ↑/↓-merke, «Se tabellen →».
   - **Kompakte linjer** (som `ActivityRowView`): sidepremier, tippekonge, melding til alle, påmeldinger. Kontekstlinje under («Jakkeracet · runde 3»).
   Hvert kort har en pille som sier hvor det kommer fra: Jakkeracet (lime), Morrocupen (sol), Løs runde (earth).

### 1b – Siden sist, per konkurranse
1. **Grønt oppsummeringskort** (hero, `#1C483A`): én setning om det viktigste siden du sist var inne + tre tall (nye runder, bragder, plasser).
2. **Kompakt live-stripe** (svart, én linje) med «Før»-knapp.
3. **Ett kort per konkurranse**: navn, «Runde 4 av 7 · 12 spillere», din plass stort (40 lett) med ↑/↓ siden sist, og de 2–3 siste hendelsene med fargede merker (Eagle, LD, Ledelse, Tabell).
4. **Dine siste runder**: vannrett rad med små svarte fliser (dato, poeng, bane, plass).

## Datagrunnlag – hva finnes, hva mangler
Finnes:
- `activity` + `activity_reactions` (`Data/Activity.swift`): big_score, lead_changed, side_prize, round_started/locked, signup, announcement, tips_king, committee_drawn.
- `MyRounds.lists` gir løse runder med «Du: 2. plass · 34 p» og vinner/leder.
- `CompetitionScope` + `CompetitionBoard.rows` gir tabellen per konkurranse.

Mangler / må avklares:
- `activity` er per klubb (`club_id`). Hjem trenger en **samlet spørring på tvers av klubber, konkurranser og løse runder** (ny RPC eller view, RLS via deltakelse).
- **Plassbytte i tabellen** finnes ikke som hendelse. Regne ut ved låsing av runde (før/etter `jacketBoard`) og logge som ny `kind`, eller regne i klienten.
- **«Din runde ferdig»** og **personlige rekorder** («beste runde på banen i år») krever statistikk fra fase 16 (`StatsQueries`).
- **«Sist sett»** for oppsummeringen i 1b: `ActivitySeenStore` er per klubb i dag.
- Hvordan Hjem forholder seg til **bjella/Varsler**: blir Varsler overflødig, eller er Varsler bare det som angår deg direkte?

## Spørsmål å sparre om
1. 1a, 1b eller en blanding (f.eks. 1b-oppsummering øverst, 1a-feed under)?
2. Skal andres runder vises (alle ferdige runder i konkurransen), eller bare bragder og tabellendringer?
3. Hva er terskelen for en «bragd»? I dag er det brutto eagle og bedre. Birdie-rekker, pers, sidepremier?
4. Filter per klubb eller per konkurranse når én klubb har flere konkurranser?
5. Skal man kunne reagere på alle kort, eller bare bragder og meldinger?
6. Push vs. feed: hvilke av disse skal også gå som push (`ActivityCategory`)?

## Tokens brukt (fra DDPalette, lys modus)
- Bakgrunn `#FFF9DF`, kort `#FFFFFF` med kant `rgba(28,72,58,.07)`, hero `#1C483A`, statkort `#000000`
- Tekst `#21292B`, sekundær `#727065`, skoggrønn `#1C483A`, krem på grønt `#FFF9DF`, stat sekundær `#9A9A9A`
- Lime `#D9EBD0`/`#21451F`, sol `#EFE3B0`/`#4B4A35`, earth `#F3E9DD`/`#612807`, blush `#FCE5DB`, blushDeep `#F7D4C6`, gull `#E4C767`/`#4B3A0B`
- Aksent lime `#6BE07A`/`#0F2E17`, gul `#F5C842`/`#1E1A05`, aktiv fane `#7A5C00`, tallmerke `#A84A10`
- Skrift: 42dot Sans (tittel 24 medium, korttittel 20 medium, brød 16, callout 14, caption 13, heltall 52 lett), Sometype Mono (eyebrow 10, sporing 1,4, versaler; pille 9,5, sporing 1,1)
- Radius: kort 24, stort kort 30, stripe 16, piller fulle. Sideluft 20, mellom kort 10.

## Filer
- `Hjem.dc.html` – begge retningene side om side (filterpillene, svarknappene og reaksjonene er klikkbare i 1a)
- `support.js` – kjøretiden som trengs for å åpne fila

## Vurdering 08.10.2026 (Claude, til beslutning)

- **Plassering:** Hjem er etterfølgeren til Kveld-fanen. «Pågår nå» og «Neste kveld» er det Kveld gjør i dag; resten er Varsler-bjella utvidet til flere klubber og løse runder.
- **Varsler:** blir Hjem feeden, bør bjella forsvinne eller bare vise det som angår deg direkte. To feeder er samme duplisering som de tre rundelistene som ble slått sammen i fase 11.
- **Arrangøren:** i stedet for en egen Arrangør-fane bærer «Neste kveld»-kortet arrangørens hovedknapp (sett opp runden, avslutt kvelden) og lenken til arrangørsiden. Fanene må bestemmes før dette bygges.
- **Data:** krever egen fase med SQL til godkjenning: samlet aktivitet på tvers av klubber og konkurranser, plassbytte som hendelse, «sist sett» på tvers, og statistikk fra fase 16 for «din runde».
- **Anbefalte svar på spørsmålene over:** (1) 1a med 1b-oppsummeringen øverst bare når noe har skjedd siden sist. (2) Bragder, tabellendringer og egne runder, ikke alle andres runder. (3) Brutto eagle og bedre. (4) Filter per konkurranse. (5) Reaksjoner på alt. (6) Push bare det som allerede er kategorier i «Hva blir push».
- **Tidspunkt:** etter byttet for gjengen og App Store-gjøremålene.
