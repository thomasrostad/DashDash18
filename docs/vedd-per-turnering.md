# Veddemål per turnering (forslag, 09.10.2026)

Thomas spurte: «Vedding på hull under turneringer, hva skjer der?» Dette er status og et forslag. Ingenting her er bygget eller kjørt ennå. Valgene nederst må tas før SQL skrives.

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

## Valg for Thomas

1. **Poengbank:** én per turnering (forslaget), eller én felles per klubb og sesong som nå?
2. **Private turneringer uten klubb:** skal de ha veddemål? Det krever B, som er mest arbeid.
3. **Løse runder:** veddemål der også, eller bare «spill i runden» (finnes) som nå?
4. **Oppgjør:** holder C1 (arrangøren fra Hjem) en stund, eller skal C2 prioriteres?
5. **Når:** sammen med trinn 033–035 (krever at alle har fase 23-bygg), eller før?
