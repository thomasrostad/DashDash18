# Veddemål per turnering (forslag 09.10.2026, bygget 12.10.2026)

Thomas spurte: «Vedding på hull under turneringer, hva skjer der?» Under står forslaget, svarene fra Thomas 11.10 og det som er bygget (steg 11, `sql/052_veddemaal.sql`, venter på godkjenning).

## Slik er det nå

- Et veddemål hører til **klubbens sesong** (`bets.season_id`, `bets.club_id`). Poengbanken er 1000 poeng **per sesong og medlem**, og saldoen regnes ut (`bet_points_for`). Det lagres ikke.
- Innsatsene er knyttet til **klubbmedlemmer** (`bet_stakes.member_id` → `club_members`), ikke profiler.
- `create_bet` finner sesongen fra rundens kveld (`events.season_id`). Uten sesong avviser den («krever en aktiv turnering»).
- Appen henter bare veddemålene i hovedturneringen (`BetsQueries.load`: aktiv sesong, ellers siste ferdige).
- Oppgjøret gjøres av regelmotoren på **arrangørens telefon** (`BetsBoard.sweepPlan` → `settle_bet`). Det skjer når veddemålene åpnes, og siden 09.10 også fra Hjem, høyst hvert femte minutt.

Fikset 09.10 (#35): «Vedd» i en runde bruker runden du står i. Er runden i en annen turnering, står det at veddemål foreløpig bare gjelder hovedturneringen.

## Hva som mangler

1. Veddemål i liga, cup og morroturnering, med egen poengbank.
2. Veddemål i private turneringer uten klubb, der deltakerne er profiler og ikke medlemmer.
3. (Kanskje) veddemål i løse runder.
4. Oppgjør uten at en arrangør åpner appen.

## Forslag

### A. Turneringen som nøkkel (fase 22, trinn 5)

- Ny kolonne `bets.competition_id` (→ `competitions`, on delete cascade), fylt fra sesongens speilede turneringsrad for alle veddemål fra før. `season_id` står til gamle bygg er borte (samme mønster som 031–035).
- `create_bet` finner turneringen fra runden: rundens kveld/spilledag (`events.competition_id`), ellers koblingen `competition_rounds` (en runde kan telle i flere, og da velger appen hvilken).
- Banen: 1000 poeng **per turnering og deltaker** (`bet_points_for(competition, person)`), med beløpene fra turneringens regelsett (`BetRules` finnes allerede i `Ruleset`).
- Tilgang: den som kan lese turneringen (`can_read_competition`), og bare påmeldte i turneringen kan satse.

### B. Personer i stedet for medlemmer

`bet_stakes.member_id`, `creator_id`, `against_id` og `resolved_by` peker på `club_members`. For private turneringer trengs profiler. Forslag: nye kolonner `*_profile_id` ved siden av, med regelen «nøyaktig én av medlem og profil», slik `competition_participants` gjør. Klubbveddemålene er urørt.

### C. Oppgjør

Vilkårene (hullduell, birdie, par, pallen) regnes av regelmotoren i Swift. Å gjøre dette i SQL betyr en ny utgave av reglene, og da kan svarene glippe mot GolfgutuCore. Forslag i rekkefølge:

1. **Nå (gjort):** arrangørens telefon gjør opp fra Hjem.
2. **Neste:** la en hvilken som helst deltaker i runden gjøre opp *etter at runden er låst*. `settle_bet` må da sjekke resultatet selv for de enkle vilkårene (hullscorer finnes i basen), eller bare godta det når to telefoner sier det samme. Dette må vurderes for juks.
3. **Senere:** en Edge Function med en TypeScript-utgave av vilkårene, testet mot de samme JSON-fixturene som GolfgutuCore (samme tanke som «tabellen på serveren» i fase 24).

## Svar fra Thomas 11.10.2026

- Veddemål er av som standard og slås på per turnering i innstillingene. For enkeltrunder på banen kan det velges i oppsettet.
- Med i liga, cup og morro, i private turneringer uten klubb (krever B) og i løse runder.
- Poengbanken følger der veddemålene er slått på: én per turnering, og én per runde for enkeltrunder.
- Oppgjøret gjøres av serveren med regelmotoren i TypeScript når runden låses (C3).

## Valg for Thomas (besvart over)

1. **Poengbank:** én per turnering (forslaget), eller én felles per klubb og sesong som nå?
2. **Private turneringer uten klubb:** skal de ha veddemål? Det krever B, som er mest arbeid.
3. **Løse runder:** veddemål der også, eller bare «spill i runden» (finnes) som nå?
4. **Oppgjør:** holder C1 (arrangøren fra Hjem) en stund, eller skal C2 prioriteres?
5. **Når:** sammen med trinn 033–035 (krever at alle har fase 23-bygg), eller før?

## Bygget 12.10.2026 (steg 11, venter på godkjenning)

`sql/052_veddemaal.sql` (detaljene i `sql/README.md`), motoren i TypeScript (`web/golfgutu-core/src/bets.ts`) og Edge Function `supabase/functions/bet-settle`. Ikke kjørt på test, ikke deployet.

- **Nøkkelen:** `bets.competition_id` eller `bets.round_scope` (enkeltrundens bank), nøyaktig én. Veddemålene fra før har fått sesongens turnering. `season_id` fylles fortsatt for sesongturneringer, så gamle bygg ser nye veddemål i hovedturneringen.
- **På/av:** `competitions.bets_enabled` og `rounds.bets_enabled`, standard av. Egne kolonner, ikke i `rules`: regelsettet skrives i sin helhet av «Tilpass reglene», web-admin og gamle bygg, og en løs runde har ikke regelsett. Tallene (startbeholdning, tak, forsprang, desimaler) står fortsatt i `rules->'bets'`. Sesongene som har veddemål i dag (og hovedturneringen i klubber med veddemål) er slått på, og en ny sesong arver det. Slås av og på med `bets_set_enabled(turnering, runde, på)`: turneringens admin eller `money`; runden: den som er arrangør av runden. Av betyr ingen nye veddemål; de som finnes står og gjøres opp.
- **Personer (B):** profil-kolonner ved siden av medlemskolonnene, nøyaktig én når innsatsen lages. `bet_stakes.person_key` husker personen når en konto slettes, så de andres bank ikke endres. Deltakere: klubbens medlemmer (sesong) eller de påmeldte; påmeldte utenfor klubben og alle i turneringer uten klubb som profil; spillerne i en klubbrunde; deltakerne med profil i en løs runde.
- **Banken:** `bet_bank(turnering, runde, medlem = null, profil = null)`: 1000 per turnering og person (eller turneringens `BetRules`), per runde for enkeltrunder.
- **Oppgjøret (C3):** når en runde låses med åpne vilkår, havner den i `bet_settle_queue`. `bet-settle` henter jobbene (`bet_settle_jobs`), regner med motoren i TypeScript (alle sju vilkårene, samme svar som `BetsBoard.sweepPlan`) og skriver med `settle_round_bets`. Bare service_role. Det scorene ikke gir svar på (for eksempel nærmest pinnen uten innmelding), står åpent til arrangøren avgjør det for hånd. Arrangørens telefon (`settle_bet`) virker som før for gamle bygg.

### Det appen må endre

- **Vedd:** hente veddemål per turnering (`bets.competition_id`) og per runde (`bets.round_scope`), ikke per sesong. Velg turnering når runden teller i flere. Tekst «Veddemål er ikke slått på» når `bets_enabled` er av (vis ikke Vedd-knappen).
- **Lage og satse:** `create_bet_v2(p_competition_id, p_round_id, p_question, p_condition, p_against_member, p_against_profile, p_side, p_points)` i stedet for `create_bet`. `place_bet_stake` er som før. Uten 052: den gamle veien.
- **Banken:** `bet_bank(p_competition_id, p_round_id)` (din) og `bet_points_for` regnes ikke lenger i appen for andre banker enn sesongen; poengtabellen grupperer innsatsene på `person_key` (medlem eller profil) og viser navn fra troppen eller profilene.
- **Personer:** `BetRow`/`BetStakeRow` får `creator_profile_id`, `against_profile_id`, `resolved_by_profile`, `profile_id` og `person_key`; `BetMapping.key` må bruke `person_key` (eller profil-id) for spillere uten medlemskap.
- **Innstillinger og oppsett:** bryter «Veddemål» i turneringens innstillinger (`bets_set_enabled(turnering, null, på)`) og i runde-oppsettet for enkeltrunder (`bets_set_enabled(null, runde, på)` etter at runden er laget; steg 7 eier oppsettet, så bryteren legges der når det er ferdig).
- **Oppgjøret:** feiingen fra Hjem kan stå for gamle bygg, men nye bygg trenger den bare som reserve. `bet_resolved` med `server: true` kan vises som «Avgjort av scorene».
- **Web-admin:** samme bryter i turneringens innstillinger.

### Oppsett av `bet-settle` (Thomas, etter godkjenning av 052)

1. `supabase secrets set BET_SETTLE_SECRET=<lang tilfeldig streng>` på test.
2. `supabase functions deploy bet-settle --no-verify-jwt` fra roten av repoet (funksjonen importerer motoren fra `web/golfgutu-core`; tar ikke pakkingen med filer utenfor `supabase/`, må importen peke på en generert kopi). Kjør `deno check supabase/functions/bet-settle/index.ts` først.
3. Database → Webhooks: INSERT på `public.bet_settle_queue` → POST til `/functions/v1/bet-settle` med headeren `x-bet-secret`.
4. Sikkerhetsnett med pg_cron hvert femte minutt (feilede jobber, runder som låses på nytt): `select cron.schedule('dd18-veddemaal', '*/5 * * * *', $$select net.http_post(url := '<prosjekt>/functions/v1/bet-settle', headers := jsonb_build_object('x-bet-secret', '<hemmelighet>'))$$);` (hemmeligheten helst fra Vault).

Testene: `node --test 'web/golfgutu-core/test/*.test.ts'` og `node --import /tmp/deno-shim.mjs --test supabase/functions/bet-settle/logic_test.ts` (shimmen står i `docs/push-oppsett.md`).
