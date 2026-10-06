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

## Prod

Ingenting av dette gjøres på prod før du sier ja. Da gjentas steg 3–6 mot prod. TestFlight-bygg bruker production-APNs også mot test-databasen, og det fungerer fordi miljøet står på hver telefon.
