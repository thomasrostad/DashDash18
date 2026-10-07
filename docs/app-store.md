# App Store: alt som må på plass for fase 17

Status 07.10.2026: koden er bygget bak flagg (alle av). SQL `019` og `023` og Edge Functions `delete-account` og `verify-purchase` er **forslag**, ikke kjørt eller deployet. Denne fila er sjekklisten for innsending.

## 1. Flaggene

| Flagg | Fil | Slås på når |
|---|---|---|
| `OpenAppFeature.flag` | `Features/Apen/OpenAppFeature.swift` | 017 og 018 er kjørt (`LooseRoundsFeature` på) og onboarding uten klubb er godkjent |
| `AccountDeletionFeature` | samme | 019 er kjørt og `delete-account` er deployet |
| `ModerationFeature` | samme | 019 er kjørt (rapporter, blokker, vilkår godtatt) |
| `GoogleLoginFeature` | samme | Google er satt opp i Google Cloud og Supabase (punkt 4) |
| `PurchaseFeature` | samme | 023 er kjørt, `verify-purchase` er deployet, produktene finnes i App Store Connect |
| `BillSplitFeature` | samme | Når du vil (trenger ingenting på serveren) |
| `LegalLinks.privacy` / `.terms` | samme | Personvern og vilkår er publisert (punkt 6) |

## 2. App Privacy («Personvern i appen» i App Store Connect)

Svar i App Store Connect → appen → **App Privacy**. Ingen sporing: svar **Nei** på «Do you or your third-party partners use data for tracking?».

| Datatype (Apples navn) | Samles inn? | Koblet til brukeren | Sporing | Formål |
|---|---|---|---|---|
| Contact Info → **Email Address** | Ja | Ja | Nei | App Functionality (innlogging) |
| Contact Info → **Name** | Ja | Ja | Nei | App Functionality |
| User Content → **Photos or Videos** | Ja (tråd og portrett) | Ja | Nei | App Functionality |
| User Content → **Other User Content** (meldinger, scorer, statistikk) | Ja | Ja | Nei | App Functionality |
| Identifiers → **User ID** | Ja (konto-id) | Ja | Nei | App Functionality |
| Identifiers → **Device ID** | Ja (push-token, identifierForVendor) | Ja | Nei | App Functionality |
| Purchases → **Purchase History** | Ja (når kjøp er på) | Ja | Nei | App Functionality |
| Usage Data, Diagnostics, Location, Contacts, Health, Financial Info, Browsing, Search, Sensitive Info | **Nei** | – | – | – |

Merk: «Sports»-statistikk som handicap regnes som Other User Content. Krasjrapporter fra Apple (Xcode Organizer) teller ikke, fordi Apple samler dem.

## 3. App Store Connect

1. **App-informasjon:** navn «DashDash», undertittel, kategori **Sports**, aldersgrense (svar «Unrestricted Web Access: Nei», «User-Generated Content: Ja» → 12+ eller etter Apples svar).
2. **Personvern-URL** (påkrevd) og **support-URL**: adressene fra punkt 6.
3. **Lisensavtale:** Apples standard (EULA) holder; vilkårene våre lenkes i appen.
4. **Kjøp i appen** (Features → In-App Purchases):
   - `no.dashdash.turnering.sesong`: **Consumable**, «Kjør turneringen», pris f.eks. 99 kr (Tier etter ønske), norsk tekst, skjermbilde av betalingsveggen (`-DDDesignScreen apenbetaling`).
   - Valgfritt: abonnementsgruppe «Arrangør» med `no.dashdash.turnering.ar`, **Auto-Renewable**, 1 år, f.eks. 399 kr.
   - Legg kjøpene til i versjonen som sendes inn («In-App Purchases and Subscriptions» på versjonssiden).
5. **Nøkkel for App Store Server API:** Users and Access → Integrations → **In-App Purchase** → generer nøkkel. Noter Issuer ID og Key ID, last ned `.p8` (kan bare lastes ned én gang). Brukes av `verify-purchase`.
6. **App Store Server Notifications** (senere): når en egen funksjon for varsler finnes, settes adressen her.
7. **Paid Apps Agreement** (Business): må være signert, med bank og skatt, før kjøp virker i produksjon.
8. **Review-notater:** demokonto (e-post med fast kode eller en testbruker), og kort forklaring: «Kontosletting: Deg → Slett konto. Rapportering: hold inne på en melding i tråden. Blokkering: samme meny.»
9. **Sandbox-testere:** Users and Access → Sandbox → legg til en tester for kjøpstest på TestFlight.

## 4. Google Cloud og Supabase (Google-innlogging)

1. Google Cloud Console → nytt prosjekt (eller eksisterende) → **APIs & Services → OAuth consent screen**: External, appnavn «DashDash», support-e-post, logo, domene, lenke til personvern og vilkår. Scopes: `openid`, `email`, `profile`. Publiser (In production).
2. **Credentials → Create OAuth client ID → Web application** (Supabase bruker web-flyten):
   - Authorized JavaScript origins: `https://<prosjekt-ref>.supabase.co`
   - Authorized redirect URI: `https://<prosjekt-ref>.supabase.co/auth/v1/callback`
   - Noter Client ID og Client Secret.
3. Supabase (test først) → **Authentication → Providers → Google**: slå på, lim inn Client ID og Secret.
4. Supabase → **Authentication → URL Configuration → Redirect URLs**: legg til `dashdash://login-callback`.
5. Valgfritt: Supabase → Auth → «Allow manual linking» (for å koble Google til en eksisterende konto senere).
6. Appen trenger **ikke** et nytt URL-skjema for Google: `ASWebAuthenticationSession` fanger `dashdash://login-callback` selv. (`dashdash://` for invitasjoner fra fase 13 er uavhengig av dette.)
7. Slå på `GoogleLoginFeature` og prøv på telefon mot test.

## 5. Supabase (etter godkjenning, test først)

1. Kjør `sql/019_konto_og_moderering.sql` i SQL Editor, så kontrollen nederst (10 av 10 skal være `true`).
2. Kjør `sql/023_kjop.sql`, så kontrollen (7 av 7).
3. Deploy Edge Functions:
   ```
   supabase functions deploy delete-account --project-ref <ref>
   supabase functions deploy verify-purchase --project-ref <ref>
   ```
   Begge med JWT-sjekk på (standard).
4. Secrets for `verify-purchase` (Edge Functions → Secrets): `APPSTORE_ISSUER_ID`, `APPSTORE_KEY_ID`, `APPSTORE_PRIVATE_KEY` (innholdet i `.p8`), `APPSTORE_BUNDLE_ID` = `com.dashdash18.app`. `delete-account` trenger ingen egne.
5. **Varsel om nye rapporter** (Apple vil ha oppfølging innen 24 timer): Database → Webhooks → på INSERT i `public.content_reports` → send e-post (f.eks. via en liten Edge Function med Resend) til personvern@dashdash18.com. Til da: kjør kontroll 10 i 019 daglig.
6. Prod: samme rekkefølge når test er godkjent.

## 6. Personvern og vilkår

1. Les `docs/personvern.md` og `docs/vilkar.md`, fyll inn [behandlingsansvarlig, org.nr., verneting, sletting av sikkerhetskopier].
2. Publiser dem (f.eks. `https://dashdash18.com/personvern` og `/vilkar`, eller GitHub Pages / Notion).
3. Sett adressene i `LegalLinks.privacy` og `LegalLinks.terms`, og i App Store Connect.
4. Opprett e-postadressen `personvern@dashdash18.com` (eller endre `LegalLinks.contactEmail`).
5. Inngå databehandleravtale med Supabase (Dashboard → Organization → Legal → DPA) og Resend.

## 7. Xcode

Ingenting i prosjektfila er endret. Dette må gjøres i Xcode:

1. **Kjøp i appen (capability):** target DashDash18 → Signing & Capabilities → **+ Capability → In-App Purchase**.
2. **StoreKit-test lokalt:** dra `StoreKit/DashDash.storekit` inn i prosjektnavigatoren (ikke huk av for noe target, så den ikke havner i appen), og velg den i **Product → Scheme → Edit Scheme → Run → Options → StoreKit Configuration**. Da viser betalingsveggen pris og kan «kjøpe» i simulatoren uten App Store Connect. Fjern valget før TestFlight.
3. **Kamera-tekst:** `NSCameraUsageDescription` sier «DashDash18 …». Endre til «DashDash bruker kameraet til å ta bilder til tråden og portrettet ditt.» (Build Settings → Info.plist Values) når appnavnet byttes.
4. **Visningsnavn:** når appen skal hete DashDash i App Store, sett `CFBundleDisplayName` (target → General → Display Name) og vurder innloggingsskjermens «DashDash18 / GolfGutu Invitational».
5. Push: `aps-environment` står som `development` i entitlements; Xcode setter production ved arkivering for App Store. Ingenting å gjøre.

## 8. Koblingen til fase 15 (konkurranser)

Fase 15 har en stubb `CompetitionPurchase.isUnlocked(...)`. Den røres ikke her. Når 023 er kjørt og `PurchaseFeature` er på:

- `AppRoot` lager én `PurchaseService` per innlogging og legger den i miljøet: `@Environment(PurchaseService.self) private var purchases: PurchaseService?`.
- Stubben kan svare med `purchases?.isUnlocked(CompetitionPurchaseInfo(id:requiresPurchase:entitlementID:ownerID:clubID:))` (fra kjøpene som er hentet, virker uten nett) eller `await purchases?.serverIsUnlocked(competitionID)` (fasit fra `competition_is_unlocked`).
- Når en turnering som krever kjøp skal startes, vises `PaywallView(service: purchases, competitionID:, competitionName:, clubID:)`. Har brukeren en ledig kreditt, brukes den uten nytt kjøp.
- `requires_purchase` settes av serveren (023: league, cup og fun). Sesongens konkurranse (jakkeracet) og spill på runden er gratis.

## 9. Valg og begrunnelser

- **Forbrukbar per turnering** (`no.dashdash.turnering.sesong`): en ikke-forbrukbar kan bare kjøpes én gang per Apple-ID, og passer derfor ikke «betal per turnering». Et forbrukbart kjøp gjenopprettes ikke av App Store, så serverens `entitlements` er fasiten, og et kjøp som ikke ble koblet (appen lukket midt i), står som en ledig kreditt (`assign_purchase`). Abonnementet (`.ar`) er valgfritt for klubber som kjører mange turneringer.
- **Verifisering:** serveren henter transaksjonen selv fra App Store Server API med vår nøkkel (ikke kvitteringen fra appen), sjekker app, produkt og `appAccountToken` (= profil-id), og bare `record_purchase` (service_role) skriver.
- **Vipps:** Vipps har ingen offentlig dyp lenke for private betalingsforespørsler med beløp. Dype lenker med beløp lages av Vipps sitt betalings-API for bedrifter med avtale, og varer i fem minutter. «Del regningen» åpner derfor Vipps (`vipps://`, ellers App Store) og viser beløp og mottaker til å kopiere, og kan dele oppgjøret som tekst.
- **Sletting:** navnet blir «Slettet spiller», scorene står (andres tabeller endres ikke). Er du eneste arrangør, tar det eldste aktive medlemmet med innlogging over.
