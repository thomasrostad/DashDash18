# Logg inn med Apple på web (og senere Android)

Status 02.11.2026: oppsettet er ikke gjort. Ingenting er endret i Apple Developer eller Supabase. Når punkt 1–3 er gjort på test, legges knappen inn i web-admin (`web/admin/src/SignIn.tsx`, samme mekanisme som Google). Android trenger det samme oppsettet ([`plan-android.md`](plan-android.md), «Apple-innlogging via nettleser»).

**Hvorfor noe nytt:** appen logger inn med Apple direkte på telefonen, med bundle-id-en `com.dashdash18.app`. I nettleseren går innloggingen via Supabase (`signInWithOAuth`), og Apple krever da en egen **Services ID**, adressen Apple sender brukeren tilbake til, og en **client secret** som Supabase sender til Apple. Secret-en lages fra en nøkkel og varer i høyst seks måneder.

**Samme konto:** Apple gir brukeren samme Apple-ID (`sub`) for alle ID-er under samme Team ID. Den som har logget inn med Apple i appen, kommer inn på samme konto på web.

| Prosjekt | Ref | Return-URL hos Apple |
|---|---|---|
| Test | `tsekialrxuhrugscosgi` | `https://tsekialrxuhrugscosgi.supabase.co/auth/v1/callback` |
| Prod | `wxabhadvuzyrmndxpuza` | `https://wxabhadvuzyrmndxpuza.supabase.co/auth/v1/callback` |

## 1. Apple Developer (én gang, dekker test og prod)

1. **App ID:** [Identifiers](https://developer.apple.com/account/resources/identifiers/list) → `com.dashdash18.app` → sjekk at **Sign in with Apple** er krysset av (det er den, appen bruker den). Ikke endre noe annet. Server-to-Server Notification Endpoint står tom (Supabase bruker den ikke).
2. **Services ID:** Identifiers → «+» → **Services IDs** → Continue.
   - Description: `Atten web`
   - Identifier: `com.dashdash18.app.web`
   - Register. Åpne den igjen, kryss av **Sign in with Apple** → **Configure**:
     - Primary App ID: `com.dashdash18.app`
     - **Domains and Subdomains:** `tsekialrxuhrugscosgi.supabase.co, wxabhadvuzyrmndxpuza.supabase.co`
     - **Return URLs:** de to adressene i tabellen over (komma mellom)
   - Next → Done → Continue → **Save**.
   - Merk: domenene er Supabase sine, ikke `admin.dashdash18.com`. Apple sender brukeren til Supabase, og Supabase sender videre til web-admin.
3. **Nøkkel:** bruk samme nøkkel som `delete-account` ([`prod-sjekkliste.md`](prod-sjekkliste.md) punkt 4.5) hvis den er laget: en Sign in with Apple-nøkkel med Primary App ID `com.dashdash18.app` gjelder også Services ID-er under samme App ID. Finnes den ikke: [Keys](https://developer.apple.com/account/resources/authkeys/list) → «+» → kryss av **Sign in with Apple** → Configure → Primary App ID `com.dashdash18.app` → lagre og last ned `AuthKey_XXXXXXXXXX.p8` (kan bare lastes ned én gang). Bruk den da også til 4.5.
4. Noter **Team ID** (øverst til høyre under Membership) og **Key ID** (står på nøkkelen). Begge er 10 tegn.
5. Legg `.p8`-fila i en passordhvelv (f.eks. 1Password), ikke i repoet eller iCloud Drive. Du trenger den hver sjette måned.

## 2. Lag client secret-en

Fra roten av repoet (Node 22.18 eller nyere, ingen installasjon):

```
node docs/apple-web/client-secret.mjs --team <Team ID> --key-id <Key ID> \
  --client com.dashdash18.app.web --p8 ~/Downloads/AuthKey_XXXXXXXXXX.p8 | pbcopy
```

Secret-en (en lang tekst som starter med `eyJ`) ligger nå på utklippstavla, og skriptet sier når den går ut (180 dager). Skriptet leser nøkkelen bare inn i minnet og skriver den aldri ut. Samme secret kan brukes på test og prod. Supabase har også en generator på [dokumentasjonssiden](https://supabase.com/docs/guides/auth/social-login/auth-apple) (virker ikke i Safari); skriptet gjør det samme uten nettleser.

## 3. Supabase, test først (`tsekialrxuhrugscosgi`)

1. **Authentication → Sign In / Providers → Apple** (er allerede på for appen):
   - **Client IDs:** `com.dashdash18.app.web,com.dashdash18.app`. **Services ID først**, komma mellom, ingen mellomrom. Supabase bruker den første ID-en til web-innloggingen. Står bundle-id-en først, avviser Apple web-innloggingen. **Bundle-id-en må stå i lista**, ellers slutter Logg inn med Apple i appen å virke.
   - **Secret Key (for OAuth):** lim inn secret-en fra punkt 2.
   - Save.
2. **Authentication → URL Configuration → Redirect URLs:** samme adresser som Google-knappen i web-admin trenger (lokalt `http://localhost:5178/**` på test, `https://admin.dashdash18.com/**` på prod). Står de der fra Google, er det ingenting å gjøre.
3. Prøv appen på telefon: logg ut og inn med Apple. Skal virke som før.
4. Prøv web-admin mot test (når knappen er lagt inn): Logg inn med Apple, og se at du havner i samme konto som i appen.

## 4. Supabase prod (`wxabhadvuzyrmndxpuza`), når test virker

Samme som punkt 3 på prod-prosjektet: Client IDs `com.dashdash18.app.web,com.dashdash18.app`, samme secret, Redirect URL `https://admin.dashdash18.com/**`. Prøv appen mot prod med Apple rett etterpå.

## 5. Fornyelse hver sjette måned

Secret-en går ut 180 dager etter at den ble laget. Da slutter Apple-innloggingen på web (og Android) å virke. Appen på iPhone påvirkes ikke.

1. Lag en ny secret (punkt 2) minst to uker før utløpsdatoen.
2. Lim den inn i **Secret Key (for OAuth)** på test og prod. Client IDs røres ikke.
3. Prøv web-innloggingen på prod.
4. Oppdater datoen i [`gjoremal.md`](gjoremal.md) og en påminnelse i kalenderen.

Nøkkelen (`.p8`) varer til den trekkes tilbake, og byttes bare om den er lekket. Da må også secrets for `delete-account` (`APPLE_KEY_ID`, `APPLE_PRIVATE_KEY`) byttes.

## Valg og begrunnelser

- **Én Services ID for test og prod:** Apple tillater flere domener og return-URL-er per Services ID, og brukeren ser samme navn i Apple-arket.
- **Ingen domenebekreftelse:** Apple krever ikke lenger fila `apple-developer-domain-association.txt` for innlogging. «Sign in with Apple for Email Communication» trengs bare om vi sender e-post til skjulte Apple-adresser (`@privaterelay.appleid.com`), og det gjelder appen like mye som web.
- **Skriptet bruker `makeClientSecret` fra `delete-account`** (`supabase/functions/delete-account/apple.ts`), så signeringen finnes ett sted.
- **Android senere:** en konto som bare har logget inn med Apple via nettleseren, får ikke Apple-tilbaketrekking ved sletting i dag. `delete-account` bruker koden fra appens Apple-ark (`APPLE_CLIENT_ID` = bundle-id-en). Det må løses når Android bygges.
