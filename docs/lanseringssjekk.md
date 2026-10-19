# Lanseringssjekk (17.10.2026)

Gjennomgang av appen, web-admin, dashdash18.com og test-databasen mot en vanlig sjekkliste for «er appen ekte». Bare lesing og SELECT mot test; ingenting er endret. Betaling står nederst.

## Status per punkt

| # | Punkt | Status | Bevis og merknad |
|---|---|---|---|
| 1 | Innlogging og utlogging | OK | Apple og engangskode på e-post, utlogging i appen og web-admin |
| 2 | Tilbakestille passord | Ikke relevant | Ingen passord |
| 3 | E-postverifisering | OK | Engangskoden bekrefter e-posten (`mailer_autoconfirm: false`) |
| 4 | Lastetilstander | OK | `ProgressView` i 74 filer |
| 5 | Tomtilstander | OK | `ContentUnavailableView` i 47 filer |
| 6 | Tydelige feilmeldinger | Delvis | Ukjente feil viser systemets tekst (kan være engelsk): `PurchaseService.swift:193`, `AccountDeletion.swift:114`, `PushRegistrar.swift:106`, `OutboxScoreSubmitter.swift:378`. `verify-purchase` sender `error.message` til klienten |
| 7 | Skjemavalidering | Ikke gjennomgått | |
| 8 | Begrensning av mange forespørsler | Delvis | Noen funksjoner har grense, andre ikke. Detaljene er gitt Thomas utenfor repoet |
| 9 | Databasebackup | Mangler | Ingen plan. Test er på gratisplanen (ingen backup, ingen PITR). Prod finnes ikke ennå |
| 10 | Row Level Security | OK | Tilgangsreglene er på for alle eksponerte tabeller |
| 11 | Nøkler ute av frontend | OK | Ingen hemmeligheter i koden eller git-historikken |
| 12 | Mobillayout | Delvis | Appen er native. Web-admin har `@media` i bare to filer; ikke prøvd på telefon |
| 13 | Egen 404-side | Delvis | dashdash18.com har «Fant ikke siden» (`web/atten-lenker/src/index.ts:216`). Web-admin har ingen |
| 14 | Bruksstatistikk | Mangler | Ingenting installert |
| 15 | Feilsporing | Mangler | Ingen Sentry eller MetricKit. Bare krasj i Xcode Organizer |
| 16 | Personvern | Mangler | Teksten finnes (`docs/personvern.md`), men er ikke publisert; `LegalLinks.privacy = nil` (`OpenAppFeature.swift:48`). Venter på navn/firma, org.nr., adresse og verneting. Apple krever lenken |
| 17 | Vilkår | Mangler | Samme som personvern (`docs/vilkar.md`, `LegalLinks.terms = nil`) |
| 18 | Slett konto | OK | Deg → «Slett konto …», bekreftes med SLETT, `delete-account` med JWT |
| 19 | Onboarding | OK | `OnboardingChoiceView`, `ClubOnboardingView` |

## Viktigst før App Store og prod

1. **Personvern og vilkår publisert** og lenket i appen (krav fra Apple). Venter på opplysningene fra Thomas.
2. **Backup i prod:** Pro-plan med PITR, en prøvegjenoppretting og `docs/backup.md`.
3. **Auth i prod:** egen SMTP, CAPTCHA (Turnstile), engangskode på 8 sifre med 10 minutters levetid, lave grenser.
4. **Grenser og koder:** grense for antall forsøk der det mangler, sterkere koder, og grense og mellomlagring på dashdash18.com.
5. **Feilsporing og feilmeldinger:** Sentry (eller MetricKit) i appen, og norske feiltekster i stedet for systemets.
6. **Hemmeligheter i prod:** egne secrets for prod, ikke gjenbruk fra test, og korte feilkoder fra Edge Functions.

## Betaling

**Reglene (Norge):**

- Det som låser opp noe i appen, må kunne kjøpes med Apples kjøp i appen (3.1.1).
- Salg på web (admin.dashdash18.com, med Stripe eller Vipps) er lov hvis det samme også kan kjøpes i appen (3.1.3(b)). Appen kan ikke lenke til eller nevne web-prisen.
- EUs regler for lenke ut gjelder trolig ikke Norge ennå. Det er ikke bekreftet; spør Apple Developer Support.
- Small Business Program gir 15 % i stedet for 30 %.
- Selges det på web, står vi selv for 25 % mva.

**Planen i appen:**

- Produktene er «Kjør turneringen» (99 kr, forbrukbart kjøp per turnering) og «Arrangør i ett år» (399 kr, abonnement som fornyes).
- Det som er gratis: jakkeracet, løse runder og spill på runden.
- `sql/023` er kjørt på test.
- `verify-purchase` er skrevet, men ikke deployet.
- Kjøpet er av med `PurchaseFeature`.

**Konkurrentene:**

- Apper for vennegjenger tar ikke betalt for å kjøre turnering (Squabbit, 18Birdies). De tjener på at spillerne betaler for premium.
- Verktøy for klubber og ligaer tar rundt 1000–1300 kr per liga per sesong. Golf Genius koster en klubb rundt 3500 USD i året.

**Anbefaling:**

- 99 kr per turnering og 399 kr i året for ubegrenset.
- I tillegg én gratis liten turnering, så folk kan prøve.
- Meld på Small Business Program.
- Bygg App Store Server Notifications før årsabonnementet slås på, ellers fanges ikke refusjoner og fornyelser.
- Prøv prisene på en ekte gjeng.

Det som gjenstår i App Store Connect og Xcode, står i [`gjoremal.md`](gjoremal.md) punkt 9–10.
