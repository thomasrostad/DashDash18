# Gjøremål for Thomas

Oppdatert 08.10.2026. Det Claude ikke kan gjøre selv, i den rekkefølgen det bør gjøres. Kryss av etter hvert.

## A. Nå (sikkerhet og bygg)

- [x] **1. Supabase → Authentication → Email:** slå på **Confirm email** og **Secure email change**. Sett OTP-lengde **8** og utløp **600 s**. *Kritisk: uten dette kan noen lage konto med din e-post.*
- [x] **2. Xcode Cloud-workflowen** *(08.10: Xcode 26.6, nøkkelen OK, intern gruppe «Utviklere» får byggene. Gjenstår: slå av «Default»-workflowen)* (App Store Connect → Xcode Cloud → Workflows → TestFlight fra main → Edit):
  - Environment → **Xcode Version = Xcode 26.6** (ikke «Latest Release»).
  - Sjekk at `SUPABASE_PUBLISHABLE_KEY` starter med `sb_publishable_`. Skriv den gjerne inn på nytt: ⌘V, uten mellomrom foran.
- [x] **3. Kjør SQL på test, i denne rekkefølgen.** Claude legger fila på utklippstavla og sjekker den etterpå.
  - [x] **024** sikkerhet (kjørt 08.10, kontrollen 8/8)
  - [x] **022** konkurranser (kjørt 08.10, kontrollen 15/15)
  - [x] **023** kjøp (kjørt 08.10, kontrollen 9/9)

## B. Snart (for TestFlight og testing)

- [ ] **4. Xcode, kamerateksten (valgfritt):** teksten står allerede i `InfoPlist.xcstrings`. Sett også grunnteksten `Privacy – Camera Usage Description` = «Atten bruker kameraet bare når du vil ta et bilde til tråden eller til portrettet ditt.»
- [ ] **5. Xcode, appnavnet (valgfritt):** appen heter **Atten**, og navnet står i `InfoPlist.xcstrings`. Sett også `Bundle Display Name` = **Atten** (target DashDash18 → General → Display Name) og widget-utvidelsens Display Name (`DashDash18Widgets`) = **Atten**.
- [x] **6. Supabase → Settings → Infrastructure:** *(08.10: Auth 2.197.0 – OK)* sjekk at Auth er **2.185.0 eller nyere** (kjent hull i Apple-innloggingen i eldre versjoner).
- [x] **7. Supabase → Authentication:** *(08.10)* slå på **Leaked password protection** og sett minstelengde på passord. Sett lave **rate limits**.
- [x] **8. Supabase → Data API:** *(08.10)* sjekk at bare `public` er eksponert.

## C. Før appen åpnes for alle (fase 17)

- [ ] **9. App Store Connect:**
  - Appnavnet er **Atten** (App Information → Name; er det tatt, f.eks. «Atten – golf med gjengen»).
  - Signer **Paid Apps Agreement** (Business).
  - Opprett kjøpene `no.atten.turnering.sesong` (Consumable) og eventuelt `no.atten.turnering.ar` (årsabonnement).
  - Lag en **In-App Purchase-nøkkel** (.p8 med Key ID og Issuer ID). Claude legger den inn som secret og deployer `verify-purchase`.
  - Fyll ut **App Privacy** etter `docs/app-store.md`.
  - Legg inn personvern- og support-URL, aldersgrense, en demokonto til review og en sandbox-tester.
- [ ] **10. Xcode:** legg til capability **In-App Purchase**.
- [ ] **11. Google Cloud:** sett opp OAuth consent screen og en Web-klient med redirect `https://tsekialrxuhrugscosgi.supabase.co/auth/v1/callback`. Legg Client ID og Secret inn i **Supabase → Auth → Google**, og legg `dashdash://login-callback` i Redirect URLs.
- [ ] **12. Personvern og vilkår:** fyll inn hakeparentesene i `docs/personvern.md` og `docs/vilkar.md`, publiser dem og send adressene til Claude. Opprett `personvern@…`.
- [ ] **13. Egen SMTP** i Supabase (e-postkoder fra eget domene) før mange brukere.
- [ ] **14. (Valgfritt) Universal links** på dashdash18.com for invitasjoner.

## D. Byttet for gjengen (fase 9, til slutt)

- [ ] **15.** Eksporter fra PWA-en og kjør prøveimport (stegene står i `docs/import-plan.md`).
- [ ] **16.** Si ja til prod-oppsett, så setter Claude det opp på samme måte som test.

## Venter på svar fra deg

- Skal noen du har blokkert, kunne bli med i din private konkurranse med koden? *(Forslag: nei.)*
- Skal en låst konkurranse (kjøp som ikke ble koblet) få en betalingsknapp på konkurransesiden? *(Forslag: ja.)*
- Skal push fra en blokkert bruker stoppes? *(Forslag: ja. Claude retter `push-send`.)*

## E-postene fra Xcode Cloud

Du får e-post for hvert bygg. Røde bygg skyldes nesten alltid punkt 2 (Xcode-versjonen eller nøkkelen). Grønne bygg kan du se bort fra. Videresend eller ta skjermbilde av røde, så retter Claude dem. Vil du ha færre e-poster: App Store Connect → Xcode Cloud → workflowen → Post-Actions → slå av varsler for vellykkede bygg.
