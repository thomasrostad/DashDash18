# Ny innloggingsskjerm (skisse A, «Ballen på grønt»)

Besluttet av Thomas 27.10.2026. Skissen ligger på designlerretet «Atten – ny innlogging» (artboard A). Denne fila er fasit for implementeringen.

## Hvorfor

- Jakka (`DDJacketIcon`) er Golfgutu-klubbens merke fra PWA-en, ikke Attens. Attens merke er golfballen fra app-ikonet: 18 groper i ring (ett per hull) og to skråstreker (DashDash).
- «Logg inn» står to ganger (navigasjonstittel og overskrift i kortet).
- Under arket vises en mørk stripe nederst på skjermen (se skjermbildet fra 27.10).
- Teksten under navnet skal si hva appen er for.

## Omfang

Bare utseendet på `DashDash18/Auth/LoginView.swift` (e-poststeget og kodesteget) og en ny, gjenbrukbar logo-view. **Ingen endring i innloggingslogikken**: Apple, Google (bak `GoogleLoginFeature`), e-postkode, CAPTCHA (`CaptchaSheet`), invitasjonsstripene, nedtellingen på «Send ny kode» og autofyll av kode skal virke som før.

Jakka beholdes der den hører hjemme (Jakkeracet, Tavla, `DDStatTiles`, `CompetitionDetailView`). Ikke rør app-ikonet.

## 1. Ny logo: `AttenMark`

Ny fil `DashDash18/DesignSystem/AttenMark.swift`. Prosjektet bruker synkroniserte mapper, så fila skal komme med automatisk. Sjekk at den gjør det. Hvis ikke, legg den til med Xcode-verktøyene (aldri rediger `project.pbxproj`).

- En `View` (kvadratisk, skalerer med `frame`), tegnet med `Canvas` eller `Shape`-er. Geometrien er den samme som i app-ikonet. Fasit: `docs/design/innlogging/atten-logo.svg` (viewBox `20 20 60 60`, altså et utsnitt av et rutenett på 100 × 100 med sentrum i 50,50).
  - Ball: sirkel med radius 29,3, fast krem #FFF9DF i begge moduser.
  - 18 groper: sirkler med radius 1,95 på en ring med radius 21,5, hver 20°, den første rett opp (vinkel 0 = toppen). Fast fyll #E4DBBB i begge moduser (samme som `ddRuleCream` i lys modus).
  - To skråstreker: linjer (47,1; 40,6) → (42,2; 58,6) og (56,9; 40,6) → (52,0; 58,6), strektykkelse 3,6, runde ender, farge `Color.ddRust`.
  - Mål i SVG-en er i et rutenett på 100. Skaler etter `min(width, height) / 60` med utsnittet forskjøvet 20 (fordi viewBox starter på 20).
- `accessibilityHidden(true)` som standard (navnet «Atten» står ved siden av).
- Legg en `#Preview` med logoen på `ddForestDeep` og på `ddBackground`, i 112 pt og 36 pt.
- Ta den gjerne med i `DesignCatalogView`.

## 2. Oppsett, e-poststeget

Fra toppen og ned. Verdiene i parentes er skissen; bruk designsystemets tokens.

**Bakgrunn bak hero:** `Color.ddForestDeep` (som i dag).

**Hero** (tar plassen som blir til overs, innholdet midtstilt loddrett og vannrett, `padding(.top, 56)`, `padding(.horizontal, 32)`, `padding(.bottom, 24)`, mellomrom 18):
1. `AttenMark()`, 112 × 112 pt.
2. «Atten»: Figtree medium 48, `relativeTo: .largeTitle`, sporing −0,5, farge `ddOnDark`. Lag gjerne et nytt token `ddBrandDisplay` i `DDFonts.swift` i stedet for et løst tall. 8 pt ekstra luft over navnet.
3. «Turnering, liga og scorekort for golfgjengen.»: `ddBody` (17), farge `ddHeroSecondary`, midtstilt, maks bredde cirka 280 pt.

**Ingen** navigasjonstittel og ingen overskrift «Logg inn» i kortet. Skjul navigasjonslinja på e-poststeget (`.toolbar(.hidden, for: .navigationBar)`). Skjermlesere skal fortsatt få en overskrift: gi «Atten» `.accessibilityAddTraits(.isHeader)`.

**Arket** (`ddCard`, øvre hjørner `DDRadius.sheet` = 32, `padding(.horizontal, 24)`, `padding(.top, 28)`, `padding(.bottom, 40)`, vertikal avstand 14). Rekkefølge:
1. Invitasjonsstripene (`DDInfoStripe`) som i dag, hvis aktuelt.
2. `SignInWithAppleButton`, uendret (hvit i mørk modus, svart i lys modus, kapselform, 56 høy).
3. Google-knappen som i dag, bak flagget.
4. Skille: tynn linje, `ELLER`, tynn linje. Linjer 1 pt `ddHairline`. Teksten i `.ddEyebrow` (mono), farge `ddInkSecondary`. `accessibilityHidden(true)`.
5. Etikett «E-post» (`ddCallout`, `ddInkSecondary`) og feltet med `.ddField()` som i dag. Plassholder `deg@epost.no`.
6. Primærknapp `.ddPrimary`: **«Send engangskode»** (i dag «Send kode»).
7. Én midtstilt linje i `ddCaption`, farge `ddInkSecondary`: «Ingen passord. Ved å fortsette godtar du [vilkårene] og [personvernerklæringen].» Lenkene er `LegalLinks.terms` og `LegalLinks.privacy` i `ddForestInk` (bruk `AttributedString` med lenker, eller `Text` med markdown). Vises bare når `showsLegal` er sann. Hvis en av lenkene er `nil`, faller du tilbake til `LegalLinksRow`.
8. Feil- og infomeldinger som i dag.

Teksten «Vi sender en engangskode til e-posten din. Ingen passord å huske.» fjernes. Den dekkes av knappeteksten og bunnlinja.

## 3. Kodesteget

Samme hero og ark. Innholdet i arket er som i dag («Skriv inn koden», sendt til …, tipset om søppelpost, kodefeltet, «Logg inn», «Send ny kode» med nedtelling, «Bruk en annen e-post»). Overskriften «Skriv inn koden» blir stående her, fordi steget trenger den.

Når tastaturet er oppe skal kodefeltet og «Logg inn» være synlige. Det er greit at heroen ruller ut av bildet.

## 4. Den mørke stripa nederst

Stripa kommer mest sannsynlig fra `.ddNavigationChrome()` (`containerBackground(Color.ddBackground, for: .navigation)`), som legger `ddBackground` bak alt nederst. Sørg for at arkets farge (`ddCard`) går helt ned under hjemindikatoren i begge moduser. For eksempel kan du sette containerbakgrunnen til en gradient eller en VStack (`ddForestDeep` over, `ddCard` under), eller droppe `ddNavigationChrome` på denne skjermen. Sjekk på et skjermbilde i både lys og mørk modus.

## 5. Lys og mørk modus

Skissen er mørk modus. I lys modus gjelder de samme tokenene: heroen er `ddForestDeep` (skogsgrønn i begge moduser), og arket er `ddCard` (hvitt i lys modus). Logoen ser lik ut i begge moduser (bare rust-tonen følger `ddRust`).

## 6. Tilgjengelighet og størrelser

- Dynamic Type helt opp til AX-størrelser: alt ligger i `ScrollView` som i dag. Ingenting skal klippes.
- Små skjermer (iPhone SE, 375 × 667): heroen krymper. Skaler gjerne logoen ned til 80 pt når høyden er under cirka 700 pt (`ViewThatFits` eller `GeometryReader`), slik at Apple-knappen er synlig uten å rulle.
- Kontrast: `ddHeroSecondary` på `ddForestDeep` og `ddInkSecondary` på `ddCard` er allerede i bruk og holder 4,5:1.

## 7. Ferdig når

- [ ] `AttenMark` finnes, med preview, og ligner app-ikonet.
- [ ] E-poststeget ser ut som skisse A i mørk modus, og er tilsvarende i lys modus.
- [ ] Ingen dobbel «Logg inn» og ingen mørk stripe nederst.
- [ ] Kodesteget, CAPTCHA, invitasjonsstripene og Google-knappen (med flagget på i `ApenSamples`) virker og ser riktige ut.
- [ ] Skjermprøvene i `ClubInviteSamples` og `ApenSamples` (og `DesignScreenSamples` hvis innloggingen er der) er sjekket.
- [ ] Bygg uten feil og advarsler, alle tester grønne.
- [ ] Egen branch fra oppdatert `main` (for eksempel `fiks/ny-innlogging`), PR mot `main` med skjermbilder i lys og mørk modus. Ta med denne mappa (`docs/design/innlogging/`) i PR-en. Ingen Supabase-endringer trengs.
