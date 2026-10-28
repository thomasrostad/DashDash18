# Android: plan

28.10.2026. Grunnlag: ønske fra Thomas om Atten på Android (B13: «iPhone først, Android senere»). Kartlagt mot iOS-appen (`DashDash18/`, ca. 80 000 linjer Swift i 387 filer), regelmotoren (`Packages/GolfgutuCore`, ca. 9 000 linjer, 35 JSON-fixtures), TypeScript-motoren (`web/golfgutu-core`, ca. 9 000 linjer, brukt av web-admin og `bet-settle`), Supabase-funksjonene (`supabase/functions/`) og lenkeworkeren (`web/atten-lenker`).

**Status:** plan, ingen kode skrevet. Klokkeplanen står i [`plan-apple-watch.md`](plan-apple-watch.md) og deler steg 0 med denne.

## Mål

Spillerne med Android-telefon skal kunne gjøre det samme som spillerne med iPhone: melde seg på, føre runden, se Tavla, spille og følge med. Svarene skal være nøyaktig de samme på begge telefonene. Arrangøren skal kunne gjøre jobben fra web-admin.

## Valg av teknologi

**Anbefaling: en ekte Android-app i Kotlin med Jetpack Compose, med regelmotoren GolfgutuCore kompilert for Android (Swift SDK for Android). Hvis en prøve på 1–2 økter viser at det ikke holder, oversettes motoren til Kotlin og sjekkes mot de samme JSON-fixturene.**

| Alternativ | For | Mot |
|---|---|---|
| **Kotlin + Compose, motoren i Swift for Android** (anbefalt) | Beste Android-følelse: Material 3, widgets, varsler og tilbake-knapp oppfører seg som Android-brukere venter. Én regelmotor for iPhone, klokka og Android, så en regel endres ett sted. | Swift SDK for Android kom i Swift 6.3 (mars 2026), men koblingen til Kotlin (swift-java) er fortsatt 0.x. Appen blir noen MB større. |
| Kotlin + Compose, motoren oversatt til Kotlin | Beste Android-følelse og helt vanlig Android-oppsett. | En tredje motor ved siden av Swift og TypeScript. Hver regelendring (som spillformene i dag) må gjøres tre steder og holdes lik med fixturene. |
| React Native med TypeScript-motoren | Gjenbruker TypeScript-motoren og React-kunnskapen fra web-admin direkte. | Dårligere Android-følelse. Widgets, varsler under runden og bakgrunnssending må likevel skrives i Kotlin. Nok en app-ramme å vedlikeholde. |

Hvorfor anbefalingen: motoren endres oftere enn noe annet i Atten, og pariteten med Golfgutu er det viktigste kravet (CLAUDE.md). Én motor er det tryggeste. Koblingen gjøres smal for å minske risikoen med swift-java 0.x: Kotlin sender JSON inn og får JSON ut (`RoundSnapshot` inn, hullkort og stilling ut). Formatet finnes allerede i fixturene.

## Hva finnes i dag som Android kan bruke

- **Supabase** (test og prod), med RLS, RPC-er og Edge Functions. Android bruker de samme tabellene og funksjonene som iPhone.
- **GolfgutuCore** og **35 JSON-fixtures** med fasiten for paritet.
- **TypeScript-motoren**, som allerede gir samme svar som Swift (256 tester). Den brukes som reserve og i testene.
- **Web-admin** (React) for arrangøren: klubb, turneringer, deltakere, roller, påmelding, baner og veddemål.
- **Lenkeworkeren** på dashdash18.com, som allerede serverer `apple-app-site-association` for iPhone.
- **Google-innlogging** i Supabase (test og prod), slått på 28.10.2026.

## Hva Android-appen inneholder (første versjon)

| Med | Ikke med (bruk web-admin eller kommer senere) |
|---|---|
| Innlogging: Google, e-postkode og Apple | Admin i appen (ca. 19 000 linjer på iPhone). Arrangøren bruker web-admin |
| Hjem og feed, varselklokka | Kjøp i appen (er av på iPhone også) |
| Runden: hullkort, føring som spiller og markør, utboks uten nett, markørkonflikter, rundeslutt og scorekort | Apple Watch-tilsvarende (Wear OS) |
| Kveld, påmelding og båser | TV-visning |
| Tavla, jakkeracet, konkurranser og turneringer (lesing) | Plakaten for kvelden |
| Spill på runden (skins, Nassau, Wolf og resten), veddemål og tips | |
| Følge, statistikk, profil, sosialt (reaksjoner og kommentarer), rapporter og blokker | |
| Deg: konto, innloggingsmåter, varsler, slett konto | |
| Push-varsler | |
| Widgets: neste kveld og topp 3 | |
| Løpende varsel under runden (Androids svar på Live Activity) | |
| Lenker til runder, invitasjoner og turneringer (App Links) | |

## Arkitektur

- **Språk og UI:** Kotlin, Jetpack Compose, Material 3 med Attens farger og typografi (fra `DesignSystem`: skog, kort, gul knapp).
- **Android-versjon:** trolig minimum Android 9 (API 28), som er det Swift SDK for Android er oppgitt å kreve. Sjekkes mot swift.org i steg 1.
- **Data:** `supabase-kt` (Supabase sitt Kotlin-bibliotek) for innlogging, tabeller, RPC og sanntid.
- **Lokal lagring og utboks:** Room (Androids database). Samme regler som utboksen på iPhone: lagres før sending, nye forsøk, avvisning beholdes, sendes bare i den innloggedes navn.
- **Bakgrunn:** WorkManager sender utboksen når nettet kommer tilbake.
- **Regelmotor:** GolfgutuCore og AttenRound (fra steg 0) kompilert til et Android-bibliotek. Kotlin kaller én funksjon per utregning med JSON.
- **Repo:** ny mappe `android/` i dette repoet, så motoren, fixturene og SQL-en ligger på ett sted. Egen CI (GitHub Actions) bygger og tester Android. Xcode Cloud påvirkes ikke.
- **Navn:** appen heter Atten. Pakkenavn `com.dashdash18.app`, som bundle-id på iPhone.

## Endringer på serveren (krever godkjenning før de kjøres)

| Hva | Hvorfor | Hvor |
|---|---|---|
| `push_devices` får kolonnen `platform` (`ios`/`android`), og sjekken på token godtar FCM-tokens | Tabellen godtar i dag bare APNs-tokens (heks) | Ny SQL i `sql/`, test først |
| `register_push_device` tar `platform` | Android registrerer seg | Samme SQL |
| `push-send` sender også via FCM (Firebase Cloud Messaging) | Push til Android | Edge Function, ny `fcm.ts` ved siden av `apns.ts` |
| Ny hemmelighet: Firebase-tjenestekonto | FCM krever det | Thomas limer den inn i Supabase |
| Android-klient-ID i Google-oppsettet i Supabase | Google-innlogging på Android | Supabase Auth (test og prod) |
| Apple-innlogging via nettleser (Services ID og nøkkel) | Apple på Android går gjennom nettleseren | Supabase Auth og Apple Developer |
| `assetlinks.json` på dashdash18.com | App Links: lenker åpner appen | `web/atten-lenker` |
| CAPTCHA (Turnstile) for Android | Når CAPTCHA slås på i prod | Samme nøkkel, ny app-verifisering |

## Steg

### Steg 0 – Flytt rundelogikken ut av iPhone-appen *(felles med klokka)*

Se [klokkeplanen](plan-apple-watch.md#steg-0--flytt-rundelogikken-ut-av-appen-felles-med-android). Hullkort, `RoundGame`, `RoundSnapshot`, scorekort, «Bayen nå», markørkonflikter, match og sidepremier flyttes fra iPhone-appen til pakken `AttenRound`. **2–4 økter.** Gjøres én gang for begge.

### Steg 1 – Prøve: regelmotoren på Android

- Kompiler GolfgutuCore og AttenRound med Swift SDK for Android.
- Kjør alle 35 fixturene på en Android-emulator gjennom JSON-koblingen fra Kotlin.
- Mål appstørrelse og tid for én utregning (hullkort, sesongtabell).
- **Ferdig når:** alle fixturene gir samme svar som på iPhone, appen er under ca. 30 MB, og en sesongtabell regnes på under 100 ms. Ellers velges Kotlin-oversettelse, og jeg sier fra med tall.
- **Omfang:** 1–2 økter.

### Steg 2 – Grunnmur

- Android-prosjekt i `android/`, Compose, Material 3-tema med Attens farger, navigasjon med de samme fanene som iPhone.
- `supabase-kt` mot test, miljøvalg test/prod som på iPhone (`ATTEN_ENVIRONMENT`).
- Innlogging: Google (Credential Manager med nonce, som på iPhone), e-postkode og Apple via nettleser.
- CI: bygg og tester på hver PR.
- **Ferdig når:** du logger inn på emulatoren med alle tre måtene og ser klubbene dine.
- **Omfang:** 4–6 økter.

### Steg 3 – Runden

- Hullkort, føring som spiller og markør, utboks i Room, WorkManager, markørkonflikter, rundeslutt og scorekort.
- Løpende varsel under runden: hull, score og stilling (Android 16 «Live Updates», vanlig løpende varsel på eldre).
- Tester: samme scenarier som `SpillformRundeTests` og utbokstestene på iPhone.
- **Ferdig når:** en hel runde føres på Android uten nett og sendes når nettet kommer, og iPhone viser den samme stillingen.
- **Omfang:** 6–8 økter.

### Steg 4 – Hjem, Kveld og Tavla

- Hjem med feed og varselklokka, Kveld med påmelding og båser, Tavla, jakkeracet og konkurranser.
- **Ferdig når:** de samme klubbene og turneringene ser like ut på begge telefonene, med samme tall.
- **Omfang:** 5–7 økter.

### Steg 5 – Spill, veddemål, tips og det sosiale

- Spill på runden, veddemål (poeng), tips, følge, statistikk, profil, reaksjoner og kommentarer, rapporter og blokker.
- **Omfang:** 6–9 økter.

### Steg 6 – Deg, push, widgets og lenker

- Deg: konto, innloggingsmåter, varsler, slett konto.
- Push med FCM (serverendringene over, etter godkjenning).
- Widgets (Jetpack Glance): neste kveld og topp 3.
- App Links og `dashdash://`.
- **Omfang:** 4–6 økter.

### Steg 7 – Google Play

- Utviklerkonto i Google Play (Thomas).
- Butikkside: tekst, skjermbilder, ikon, «Data safety»-skjema (tilsvarer App Privacy) og innholdsklassifisering.
- **Lukket test i 14 dager med minst 12 testere.** Google krever det for nye personlige utviklerkontoer før appen kan publiseres. Testerne må melde seg på og bli med hele perioden.
- Feilrapporter: Android vitals i Play Console. Ingen ny tredjepart.
- **Omfang:** 2 økter, pluss 14 dager kalendertid.

**Totalt: 30–44 økter, pluss 14 dager lukket test.** Steg 0 deles med klokka.

## Det du må avgjøre eller gjøre

1. **Hvem har Android?** B13 er fortsatt åpen. Er det få i gjengen og blant brukerne, bør klokka komme først.
2. **Utviklerkonto i Google Play.** Personlig konto koster 25 dollar én gang og krever lukket test med 12 testere i 14 dager. En organisasjonskonto slipper testkravet, men krever et organisasjonsnummer med D-U-N-S-nummer.
3. **12 testere med Android-telefon** til den lukkede testen.
4. **Firebase-prosjekt** for push. Jeg lager oppsettet. Du limer tjenestekontoen inn i Supabase.
5. **Godkjenne serverendringene** i tabellen over, test først, så prod.

## Risiko

- **Swift på Android** er nytt. Steg 1 er en prøve med klare krav, og planen har en reserve (Kotlin-oversettelse sjekket mot fixturene).
- **To apper å vedlikeholde.** Hver ny funksjon må bygges to ganger. Motoren deles, men skjermene gjør ikke det. Regn med 30–50 % mer tid på nye funksjoner etterpå.
- **Lukket test.** Uten 12 aktive testere står appen stille i Play Console.
- **Admin bare på web.** Arrangører med Android må bruke web-admin. Sjekk at web-admin dekker det arrangøren gjør i appen på iPhone i dag før Android slippes.

## Rekkefølge med klokka

1. Steg 0 (felles): flytt rundelogikken til `AttenRound`.
2. Klokka, steg 1–5. Liten jobb, bruker steg 0 med en gang, og gir noe til iPhone-brukerne.
3. Android, steg 1 (prøven). Gir svaret på motoren før det store arbeidet starter.
4. Android, steg 2–7.

Kilder for Swift SDK for Android og Google Plays testkrav: [Swift 6.3 med Android SDK (i-programmer)](https://www.i-programmer.info/news/98-languages/18766-swift-63-adds-android-sdk.html), [status for swift-java juli 2026](https://www.youngju.dev/blog/2026-07-16-swift-android-sdk-official.en), [Google Play: testkrav for nye personlige kontoer](https://support.google.com/googleplay/android-developer/answer/14151465?hl=en-GB).
