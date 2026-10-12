# Push (APNs): det du må gjøre selv

Fase 8. Koden ligger klar, men push er **av** til stegene under er gjort. Rekkefølgen betyr noe: appen skal ikke kalle RPC-er som ikke finnes.

Filene:

- `sql/010_push.sql`: tabeller, RLS og RPC-er (forslag, ikke kjørt)
- `supabase/functions/push-send/`: senderen (Edge Function) med tester
- `DashDash18/Push/`: appens del, slått av med `PushFeature.isEnabled = false`

## 1. APNs-nøkkel i Apple Developer

1. Gå til developer.apple.com → Certificates, IDs & Profiles → **Keys** → **+**.
2. Gi nøkkelen et navn (for eksempel «DashDash18 push»), kryss av **Apple Push Notifications service (APNs)** og velg **Sandbox & Production**.
3. Last ned `AuthKey_XXXXXXXXXX.p8`. **Den kan bare lastes ned én gang.** Legg den i passordhvelvet, aldri i repoet eller i iCloud-mappa med prosjektet.
4. Noter **Key ID** (10 tegn, står på nøkkelen) og **Team ID** (øverst til høyre, eller under Membership).
5. Under **Identifiers** → appens bundle-id: sjekk at **Push Notifications** er krysset av. Xcode gjør det ofte selv i steg 2.

## 2. Push Notifications i Xcode

1. Åpne prosjektet → target **DashDash18** → **Signing & Capabilities** → **+ Capability** → **Push Notifications**.
2. Xcode legger `aps-environment` i `DashDash18.entitlements` og oppdaterer profilen. Ikke rediger fila for hånd.
3. Bygg én gang. Debug-bygg fra Xcode får **sandbox**-tokens, TestFlight og App Store får **production**. Appen sender riktig miljø selv (`PushEnvironment.current`).

## 3. Godkjenn og kjør 010 på test

1. Les `sql/010_push.sql` (sammendraget står i rapporten og øverst i fila). Si ja eller be om endringer.
2. Supabase → **test**-prosjektet (`tsekialrxuhrugscosgi`) → SQL Editor. Lim inn hele fila og kjør.
3. Kjør kontrollspørringene nederst i fila én om gangen. Forventet svar står ved hver.
4. Kjør Security Advisor. Ingen funksjon skal være åpen for `anon`.

NB: 010 flytter eventuelle rader fra `push_tokens` (008) til `push_devices` og fjerner `push_tokens` og `register_push_token`. Appen har aldri brukt dem.

## 4. Secrets i Supabase (test)

Supabase → test → **Edge Functions** → **Secrets** (eller `supabase secrets set --project-ref tsekialrxuhrugscosgi …`):

| Navn | Verdi |
|---|---|
| `APNS_KEY_ID` | Key ID fra steg 1 |
| `APNS_TEAM_ID` | Team ID |
| `APNS_PRIVATE_KEY` | Hele innholdet i `.p8`-fila, med `BEGIN`- og `END`-linjene. Linjeskift eller `\n` går begge |
| `APNS_BUNDLE_ID` | Appens bundle-id (Xcode → General → Bundle Identifier) |
| `PUSH_HOOK_SECRET` | En lang tilfeldig streng, for eksempel fra `openssl rand -hex 32` |

`SUPABASE_URL` og `SUPABASE_SERVICE_ROLE_KEY` setter Supabase selv. Service-role-nøkkelen skal aldri inn i appen.

## 5. Deploy funksjonen

```sh
supabase functions deploy push-send --project-ref tsekialrxuhrugscosgi --no-verify-jwt
```

`--no-verify-jwt` fordi webhooken autentiserer seg med `x-push-secret`, ikke med en innlogging. Uten riktig hemmelighet svarer funksjonen 401.

Testene kjøres med `deno test supabase/functions/push-send/`. De trenger verken nett, APNs eller database.

## 6. Webhook som vekker senderen

Supabase → test → **Database** → **Webhooks** → **Create a new hook**:

- Navn: `dd18_push_queue`
- Tabell: `public.push_queue`, hendelse: **Insert**
- Type: **Supabase Edge Functions**, funksjon: `push-send`, metode `POST`
- HTTP-header: `x-push-secret` = samme verdi som `PUSH_HOOK_SECRET`

Hver ny linje i aktivitetsloggen og hver trådmelding gir en jobb i køen. Webhooken vekker `push-send`, som sender alle ventende jobber. En jobb som feilet, prøves igjen ved neste vekking (høyst 5 forsøk, innen en time).

Valgfritt, påminnelsen en uke før kvelden: slå på **pg_cron** (Integrations) og kjør

```sql
select cron.schedule('dd18-paaminnelse', '0 8 * * *', $$select public.queue_evening_reminders(7)$$);
```

## 7. Skru på flagget

1. Sett `PushFeature.isEnabled = true` i `DashDash18/Push/PushModels.swift`.
2. Bygg og kjør på en ekte iPhone (simulatoren får ikke ekte APNs-tokens fra Xcode-bygg uten videre).
3. Deg → **Varsler** → **Slå på varsler**. Sjekk at telefonen står i `push_devices` (SQL Editor: `select device_id, environment, last_seen_at from public.push_devices;`).
4. Prøv med to kontoer: en eagle, en melding til alle og en trådmelding med @navn. Se på `push_queue` (kontrollspørring 7) hvis noe ikke kommer fram. `result` og `last_error` sier hvorfor.

## Blokkering

Har du blokkert noen (`user_blocks`, sql/019), får du ikke push om det de gjør: trådmeldingene deres (også når de nevner deg), og linjer der de er aktøren eller spilleren det handler om (store scorer, sidepremier, påmelding, ny spiller, ledelsen, tippekongen, melding til alle og purring fra dem). Bare den som blokkerer slipper, som i tråden. Linja står fortsatt i Varsler. `push-send` leser `club_members` og `user_blocks` med service-rollen for hver jobb som ellers ville blitt sendt. Feiler lesingen, prøves jobben igjen i stedet for å sendes ufiltrert. Ingen ny SQL trengs. Reglene står i `pushOriginators` i `logic.ts`.

## Varsler, steg 5 (sql/046)

`sql/046_varsler.sql` er kjørt på test (12.10). Den gir fire grupper (Spillet, Sosialt, Kvelden, Arrangør), demping av én kveld, ett «kvelden er i gang» per kveld (`round_started` går ikke lenger som push), `collapse` per kveld og gruppe i `push_job_payload`, push i turneringer uten klubb, loggen `notifications` og grunnmuren for e-post til dem uten push.

Det `push-send` gjør med 046 (krever ny deploy, se steg 5 over):

- **Collapse.** `payload.collapse` (`event-<kveld>-<gruppe>`) blir `apns-collapse-id`, så et nyere varsel i samme gruppe samme kveld erstatter det forrige. Uten den: `lead-<runde>` og `table-<turnering>` som før.
- **«Kvelden er i gang».** `🏁 Kvelden er i gang: torsdag 8. oktober · Runde 1 – Pebble Beach`. Står ordet for dagen i svaret (`day_term`), brukes «Kvelden» eller «Spilledagen»; ellers «Runden er i gang».
- **Logg.** Etter hver jobb kalles `push_log_result` med én rad per mottaker med innlogging: `sent` eller `failed` (med APNs-grunnen) etter sendingen, og `skipped` med grunn: `actor`, `not_recipient`, `too_old`, `club_off`, `muted`, `group_off`, `category_off` eller `blocked`. Ledige navn uten innlogging logges ikke. Feiler loggen (for eksempel uten 046), går pushen som før, og feilen står i svaret som `log_error`.
- **Turneringer uten klubb** (`audience = 'competition'`): mottakerne er profiler, blokkering leses rett fra `user_blocks`, og varslene grupperes som `competition-<id>` på låseskjermen.
- **E-post** (`email.ts`): se under.

Testene: `deno test supabase/functions/push-send/`. Uten Deno går de med Node 22+ og en liten shim som gjør `Deno.test` om til `node:test`:

```sh
echo 'import { test } from "node:test"; globalThis.Deno = { test: (n, f) => test(n, f), env: { get: () => undefined } };' > /tmp/deno-shim.mjs
cd supabase/functions/push-send && node --import /tmp/deno-shim.mjs --test logic_test.ts apns_test.ts email_test.ts
```

### E-post til dem uten push (av til du setter opp SMTP)

`push-send` sender e-post bare når alle fire secrets under finnes. Mangler én, skjer ingenting: ingen oppslag, ingen e-post, ingen logg. Da kaller den `push_email_recipients(jobb)` for linjene som kan gå som e-post (melding til alle, purring, påminnelse, plass fra ventelista og avmelding til arrangøren), sender én e-post per mottaker og logger `channel = 'email'` i `notifications`. Mottakerne er de som har e-post på (Deg → Varsler, på som standard), ikke har noen telefon registrert og ikke har slått av kategorien, gruppen eller kvelden.

Ingen nye avhengigheter: en liten SMTP-klient over TLS (`Deno.connectTls`, `AUTH LOGIN`) i `email.ts`. Edge Functions stenger port 25 og 587, så bruk **465** (TLS fra start).

Det du må gjøre:

1. Velg en e-posttjeneste med SMTP på port 465 (for eksempel Resend, Postmark, SendGrid eller Brevo) og godkjenn avsenderdomenet der (SPF og DKIM i DNS for `dashdash18.com`).
2. Supabase → test → **Edge Functions** → **Secrets**:

| Navn | Verdi |
|---|---|
| `SMTP_HOST` | Verten, for eksempel `smtp.resend.com` |
| `SMTP_USER` | Brukernavnet (hos Resend: `resend`) |
| `SMTP_PASS` | Passordet eller API-nøkkelen |
| `SMTP_FROM` | Avsenderen, for eksempel `Atten <varsler@dashdash18.com>` |
| `SMTP_PORT` | Valgfri, standard `465` |

3. Deploy `push-send` på nytt (steg 5). Prøv med en konto uten telefon i `push_devices`: send «Melding til alle», og se `notifications` (`channel = 'email'`) og `push_queue.result` (`email_sent`, `email_failed`).

Samme tjeneste kan brukes for innloggingskodene (Authentication → SMTP Settings), men det er en egen innstilling.

## Prod

Ingenting av dette gjøres på prod før du sier ja. Da gjentas steg 3–6 mot prod. TestFlight-bygg bruker production-APNs også mot test-databasen, og det fungerer fordi miljøet står på hver telefon.
