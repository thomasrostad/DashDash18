# Sikkerhet og personvern i iOS-appen (revisjon 07.10.2026)

Omfang: appkoden (`DashDash18/`, `DashDash18Widgets/`), `ci_scripts/`, `.gitignore`, git-historikken, Info.plist og entitlements, StoreKit-fila og `supabase/functions/` (bare lest). Databasen og RLS er revidert for seg og er ikke med her. Det samme gjelder `Features/Konkurranser` og 022/023, som var under arbeid.

Branch: `sikkerhet-app`. Testene: 881 av 881 grønne på egen simulator, ingen nye advarsler.

## Kort fortalt

Ingen kritiske funn. Det finnes ingen hemmeligheter i koden eller i historikken. Økten ligger i nøkkelringen, all trafikk går over HTTPS, appen logger ingenting, og bilder mister GPS før de lastes opp. De viktigste svakhetene var lokale. Etter utlogging kunne widgets, Live Activity og varsler fortsatt vise den forrige brukerens data. En ny installasjon logget inn igjen med den gamle økten. Privacy Manifest manglet. Alt dette er fikset. Det som står igjen, er hovedsakelig server- og oppsettsoppgaver (se sjekklista).

## Funn etter alvorlighet

### Kritisk

Ingen.

### Høy

**H1. Privacy Manifest manglet** – *fikset*
- Scenario: App Store Connect avviser opplastingen, eller sender ITMS-91053-advarsler, fordi appen bruker `UserDefaults` (required-reason API) uten manifest. supabase-swift 2.55.3 har ikke sitt eget manifest. Koden lenkes statisk inn i appen og må derfor dekkes av appens manifest.
- Fiks: `DashDash18/PrivacyInfo.xcprivacy`. Den synkroniserte mappa tar den med i app-targetet (bekreftet i bygget). Innhold: ingen sporing, `UserDefaults` med grunn `CA92.1`, filtidsstempler med grunn `C617.1` (supabase-swift `MultipartFormData` bruker `attributesOfItem`) og datatypene fra App Privacy-tabellen i `docs/app-store.md`. swift-crypto har sine egne manifester. Testen `privacyManifestLiggerIAppen` sjekker at fila ligger i appen.

### Middels

**M1. Widgets, Live Activity og varsler viste den forrige brukerens data etter utlogging** – *fikset*
- Scenario: Per logger ut, og Kari logger inn på samme telefon (eller telefonen lånes bort). Topp 3-widgeten med navn og poeng, neste kveld og Live Activity med navn, bane og score står fortsatt på hjem- og låseskjermen. Det samme gjør leverte push-varsler med meldinger fra tråden.
- Sted: `AppRoot.onChange(state == .signedOut)` ryddet bare klubb, utboks, push og kjøp.
- Fiks: `SignedOutCleanup.run()` (`App/LocalDataReset.swift`) sletter widget-fila (`WidgetSnapshotStore.clear`), avslutter alle Live Activities (`RoundActivityController.endAll`), fjerner leverte varsler og merket på app-ikonet, og tømmer bildebufferen i minnet (`TradImageStore.removeAll`). Den kjøres ved enhver overgang til utlogget, også når en økt ikke kan fornyes.

**M2. En ny installasjon logget inn med den gamle økten** – *fikset*
- Scenario: supabase-swift lagrer økten i nøkkelringen (`kSecAttrAccessibleAfterFirstUnlock`, tjenesten `supabase.gotrue.swift`), og nøkkelringen overlever at appen slettes. Den som sletter appen for å «logge ut», eller gir telefonen videre uten å tilbakestille den, blir logget inn igjen ved neste installasjon.
- Fiks: `FreshInstallGuard` kjøres før Supabase-klienten lages. Er appens `UserDefaults` helt tomme og uten merke, er det en ny installasjon, og supabase-swift sine poster i nøkkelringen slettes. Har en oppdatert app allerede verdier der, beholdes økten, så ingen i gjengen blir logget ut av oppdateringen.

**M3. Sletting av konto ryddet ikke telefonen** – *fikset*
- Scenario: etter «Slett konto» lå kontoens hull fortsatt i utboksen (SwiftData, `Utboks.store`) og innstillingene i `UserDefaults` (onboarding-valg, statistikkbryter, valgt klubb, sist lest, ventende kjøp).
- Fiks: `AuthModel.didDeleteAccount` → `OutboxScoreSubmitter.removeAll(userID:)` og `LocalDataReset.removeAccountData(userID:)`. Andre kontoer på samme telefon beholder sitt. Utlogging rydder i tillegg som i M1.

**M4. Blokkering stopper ikke push** – *foreslått (server)*
- Scenario: Kari blokkerer Per. Pers meldinger skjules i tråden (`ModerationFilter`), men `push-send` sender fortsatt «Per: …» som varsel til Kari, også på låseskjermen. Apple 1.2 forventer at blokkert innhold ikke når frem.
- Sted: `supabase/functions/push-send/logic.ts` (ingen kobling mot `user_blocks`).
- Forslag: filtrer bort mottakere som har blokkert forfatteren, før varslene bygges, når 019 er kjørt.

**M5. Kameraets bruksbeskrivelse var upresis** – *fikset i string-katalogen, bør også endres i Xcode*
- Scenario: teksten sa «DashDash18 … til kveldens tråd», men kameraet brukes også til portrettet. Apple avviser upresise formål (5.1.1).
- Fiks: `Resources/InfoPlist.xcstrings` (en og nb): «Atten bruker kameraet bare når du vil ta et bilde til tråden eller til portrettet ditt.» Testen `kamerateksteneNevnerTradOgPortrett` sjekker teksten. Byggeinnstillingen bør få samme tekst (sjekklista).

### Lav

**L1. Nøkkelen kunne være en gammel service_role-JWT** – *fikset*
- `AppConfig` avviste bare `sb_secret_`. En gammel JWT-nøkkel med `role: service_role` gikk gjennom. `AppConfig.isSecretKey` dekoder nå JWT-en og avviser den. `ci_post_clone.sh` krever `sb_publishable_` (en JWT inneholder ikke ordet `service_role` i klartekst, så den gamle sjekken kunne ikke fange den).

**L2. `.gitignore` dekket ikke Apple-nøkler** – *fikset*
- `docs/app-store.md` ber deg laste ned en `.p8`. Nå ignoreres `*.p8`, `*.p12`, `*.pem` og `*.mobileprovision`. Config, `import-snapshot/`, `import-out/` og `supabase/.temp/` var allerede dekket (sjekket med `git check-ignore`).

**L3. Topp 3 på låseskjermen** – *fikset*
- Den rektangulære widgeten på låseskjermen viste navn og poeng for tre spillere. Nå er raden `.privacySensitive()`, så iOS skjuler den til telefonen er låst opp (Face ID gjør det når du ser på skjermen).

**L4. Varsler fra tråden viser navn og meldingstekst på låseskjermen** – *akseptert, med forslag*
- Det er vanlig for chat og styres av iOS-innstillingen «Vis forhåndsvisninger». Forslag: sett `hiddenPreviewsBodyPlaceholder` på en varselkategori («Ny melding i tråden»), så teksten er nøytral når forhåndsvisning er av. Live Activity viser bare eget navn, banen og egen stilling. Det er greit.

**L5. Den egendefinerte URL-ordningen `dashdash://` kan kapres** – *risikoen er vurdert, forslag*
- Invitasjoner (`dashdash://runde/KODE`): koden valideres strengt (10 tegn i Crockford base32). Lenken viser bare en forhåndsvisning, og du må selv trykke «Bli med» (`JoinRoundView`). Ingenting skjer før du er logget inn. En annen app som registrerer `dashdash://`, kan i verste fall snappe opp en invitasjonskode og bli med i en løs runde. Det er lav konsekvens, men reelt.
- OAuth-tilbakekallet (`dashdash://login-callback`): `ASWebAuthenticationSession` leverer tilbakekallet til økten selv, ikke via systemets URL-ruting. supabase-swift bruker PKCE (`defaultFlowType = .pkce`, verifikatoren ligger i nøkkelringen), så en snappet kode kan ikke brukes. `onOpenURL` sender aldri lenker til `auth.session(from:)`, så en lenke kan ikke logge deg inn på en annens konto.
- `dashdash://konkurranse/…` finnes ikke i koden ennå. Når den legges til, gjelder de samme reglene: valider id-en, vis en forhåndsvisning, og la brukeren bekrefte.
- Forslag: universal links (`https://dashdash18.com/r/KODE`) for invitasjoner. De kan ikke kapres, og de virker som klikkbare lenker i Meldinger og WhatsApp. For Google: iOS 17.4+ kan bruke `ASWebAuthenticationSession` med `.https(host:path:)`-callback når associated domains er satt opp.

**L6. Feilmeldinger viser serverens tekst** – *akseptert*
- `LoginError.unknown`, `DataError.unknown` og lignende viser `localizedDescription`. Det er ingen tokens eller stier der, bare Supabase-meldinger som «JWT expired». Dette er greit for en lukket gjeng. Vurder en generell tekst for prod.

**L7. Nøkkelringen bruker `AfterFirstUnlock` (ikke `ThisDeviceOnly`)** – *foreslått*
- Økten følger med i krypterte sikkerhetskopier og til en ny telefon. Det er praktisk for brukeren. Vil du stramme inn, gi `SupabaseClientOptions.auth.storage` en egen `AuthLocalStorage` med `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, og migrer den eksisterende økten (ellers blir alle logget ut én gang).

**L8. StoreKit: transaksjoner som serveren avviser, blir liggende** – *info*
- `PurchaseService` fullfører (`finish()`) først når `verify-purchase` har registrert kjøpet. Opplåsing avgjøres av `entitlements` fra serveren og `competition_is_unlocked`, aldri av den lokale kvitteringen. Det er riktig. En transaksjon som serveren avviser for godt (f.eks. `appAccountToken` for en annen konto på samme telefon), forblir ufullført og prøves ved hver oppstart. Det er ufarlig, men gir en feilmelding hver gang. Vurder å fullføre ved en endelig avvisning. `PendingPurchaseStore` er ikke per bruker (lav betydning).

### Info (sjekket, ingen funn)

- **Hemmeligheter:** Git-historikken er søkt (alle grener) etter `sb_secret_`, JWT-er, private nøkler, Resend-, AWS- og GitHub-tokens og passord. Treffene er bare testverdier, plassholdere (`sb_publishable_forhandsvisning`) og PEM-parsing i Edge Functions (commit `0b8ff84`, `88de344`: testnøkler som lages under kjøring). Ingen Config-, import-, `.p8`- eller `.env`-filer har noen gang vært sporet. `Config/Supabase-Test.plist` har bare `Environment`, `SupabaseURL` og en `sb_publishable_`-nøkkel. Det er sjekket på prefiks, og verdien ble ikke skrevet ut. `DashDash.storekit` har ingen hemmeligheter.
- **Nettverk:** ingen ATS-unntak, `AppConfig` krever `https`, og signerte bilde-URL-er er HTTPS. Ingen `print`, `os_log`, `Logger` eller `NSLog` i appen eller widgetene. Ingen egen sertifikat-pinning; det er standard for Supabase, og pinning anbefales ikke.
- **Lagring:** økten ligger i nøkkelringen. `UserDefaults` har bare id-er og innstillinger (ingen tokens). `MembershipCache` er per bruker og tømmes ved utlogging. Utboksen merker hull med bruker og sender bare for den som er innlogget. Widget-fila i App Group har neste kveld og topp 3 (navn og poeng). Det er greit, fordi brukeren selv legger widgeten til. Nå ryddes den ved utlogging. Filene har standard databeskyttelse (`CompleteUntilFirstUserAuthentication`). Det trengs for at utboksen kan sende i bakgrunnen og widgetene kan lese.
- **Innlogging:** Apple-nonce lages med `SecRandomCopyBytes`. SHA-256 sendes til Apple og råverdien til Supabase, og en ny nonce lages per forsøk. Google går via Supabase OAuth med PKCE. Utlogging er lokal, og `unregister_push_device` kalles mens økten finnes. Merk CVE-2026-31813 (GHSA-v36f-qvww-8w8m) i Supabase Auth (serveren, ikke klienten): ID-token-flyten med Apple kunne utstede økter. Den er fikset i Auth 2.185.0. Hosted Supabase oppdateres av Supabase. Bekreft versjonen i dashbordet.
- **Bilder:** `TradImageCompressor` og `DegPortraitCompressor` tegner bildet på nytt fra pikslene uten egenskaper, slik at GPS, EXIF og TIFF forsvinner. Det er nå bevist med testene `tradBildeMisterGPS` og `portrettMisterGPS`. Størrelsen er begrenset til 1600 px / 3 MB (tråd) og 600 px (portrett), alltid JPEG. `PhotosPicker` gir bare valgte bilder (ingen tilgang til biblioteket). Grenser i bøtta (størrelse og MIME-type) settes på serveren.
- **Rapporter og blokker** (fase 17, bak flagg): rapporter går via RPC, og blokkering skjuler meldinger lokalt. Se M4 for push.
- **Avhengigheter** (`Package.resolved`): supabase-swift 2.55.3, swift-crypto 4.5.2, swift-asn1 1.7.3, swift-http-types 1.8.0, swift-clocks 1.1.1, swift-concurrency-extras 1.4.1, xctest-dynamic-overlay 1.13.1. Ingen kjente sårbarheter i klientpakkene ble funnet (søk i GitHub Advisory og OSV).

## Sjekkliste for deg

### Xcode (prosjektfila er ikke rørt)

1. Target DashDash18 → Build Settings → `INFOPLIST_KEY_NSCameraUsageDescription`: sett «Atten bruker kameraet bare når du vil ta et bilde til tråden eller til portrettet ditt.» (samme som i string-katalogen).
2. Bekreft at `PrivacyInfo.xcprivacy` vises i navigatoren under DashDash18 med target-medlemskap DashDash18 (ikke widgeten). Ved arkivering: Product → Archive → høyreklikk → **Generate Privacy Report** og sjekk at rapporten stemmer med punkt 2 i `docs/app-store.md`.
3. For universal links (valgfritt, anbefalt før lansering): Signing & Capabilities → **+ Associated Domains** → `applinks:dashdash18.com` (og senere `webcredentials:dashdash18.com`). Håndter `https`-lenker i `onOpenURL` på samme måte som `dashdash://runde/…`.
4. Xcode Cloud: `SUPABASE_PUBLISHABLE_KEY` må starte med `sb_publishable_`, ellers stopper bygget nå.

### App Store Connect

1. App Privacy: svarene i `docs/app-store.md` punkt 2 stemmer med det appen samler inn og med manifestet. Ingen endring.
2. Når kjøp er på, legg til Purchase History (allerede med i tabellen og manifestet).
3. Review-notatet nevner sletting, rapportering og blokkering. Bekreft at blokkering også stopper push (M4) før innsending.

### Universal links / associated domains (server)

1. Publiser `https://dashdash18.com/.well-known/apple-app-site-association` (uten filendelse, `application/json`) med `applinks.details[].appIDs = ["<TeamID>.com.dashdash18.app"]` og `components` for `/r/*` (invitasjoner) og eventuelt `/k/*` (konkurranser).
2. Endre `InviteCode.url` og delingsteksten til https-lenken når domenet er klart. Behold `dashdash://` som reserve.
3. Supabase → Auth → URL Configuration: legg til https-callbacken hvis Google-innloggingen flyttes til universal links.

### Supabase (forslag, ikke gjort)

1. `push-send`: hopp over mottakere som har blokkert forfatteren (M4).
2. Storage: sett filgrense (f.eks. 5 MB) og `allowed_mime_types = ['image/jpeg']` på bøttene for tråden og portrettene.
3. Bekreft at Auth-versjonen er 2.185.0 eller nyere (CVE-2026-31813).
