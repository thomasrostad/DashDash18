# golfgutu-core (TypeScript)

Regelmotoren til Atten, oversatt fra Swift-pakken `Packages/GolfgutuCore` til TypeScript, så en server
(for eksempel en Cloudflare Worker) eller en nettside kan regne tabellene selv. Svarene skal være
**nøyaktig de samme** som i appen, også for andre regelsett enn Golfgutu-oppsettet.

Ingen avhengigheter. Node 24 kjører TypeScript direkte (type stripping), så det er ingen byggesteg.
Koden bruker bare syntaks som kan strippes (ingen `enum`, `namespace` eller parameter-egenskaper), og
importer har `.ts` på slutten.

## Kjøre testene

Fra roten av repoet:

```sh
node --test 'web/golfgutu-core/test/*.test.ts'
```

eller fra denne mappa: `npm test`. Swift-siden kjøres som før:

```sh
cd Packages/GolfgutuCore && swift test
```

## Paritet med Swift

Pariteten er sjekket på tre måter:

1. **De samme fixturene.** Testene leser JSON-fixturene i
   `Packages/GolfgutuCore/Tests/GolfgutuCoreTests/Fixtures/` direkte (ingen kopi). Hver Swift-testfil for en
   portert modul har en TS-testfil med de samme sakene: avrunding og norsk sortering, poeng, handicap, bane,
   match, trekant, avkorting, sidepremier, former, regelsett (v1 og v2, malene, validering), WHS, sesongen,
   stableford-tabellen, frosset handicap, liga og cup.
2. **Goldenfiler fra Swift, byte for byte.** `GoldenTests.swift` i Swift-pakken skriver hele sesongtabeller
   (jakketavla, stablefordtavla, utvalget per spiller, rundepoeng, trekning) for alle sakene i `sesong.json`,
   `sesong-stableford.json` og `frosset-handicap.json`, hver med fem regelsett (Golfgutu, stableford-serien
   og tre egne), og alt motoren regner per runde (hull, handicap, poeng, match hull for hull, trekant,
   sidepremiehull) for alle rundene i fixturene. Filene ligger i `Fixtures/golden/`. Vanlig `swift test`
   sjekker at filene stemmer med Swift-motoren; `test/golden.test.ts` regner det samme i TypeScript og krever
   at JSON-teksten (sorterte nøkler) er helt lik.
3. **App-mappingen mot appens egen kode.** `test/fixtures/tavla.json` er et svar fra RPC-en `tavla_data`
   (laget med `tools/tavla-fixture.py` etter `TavlaSamples.swift`, utvidet med lag, trekant, manuelle
   resultater, siste ni, avkorting, frosset handicap, tee, kladd og simulator) og tre sesongrader.
   `tools/swift-tavla/kjor.sh` kompilerer appens filer for Tavla og konkurransene (`TavlaStandings`,
   `RoundsGrid`, `RoundSnapshot`, `CompetitionScope`, `LeagueStandings`, `CupStandings`) mot Swift-pakken og
   skriver fasiten `test/fixtures/tavla.forventet.json`. `test/tavla.test.ts` krever samme rader, tall og
   tekster.

Endres regelmotoren med vilje:

```sh
cd Packages/GolfgutuCore && GOLDEN_WRITE=1 swift test --filter GoldenTests   # nye goldenfiler
cd web/golfgutu-core && sh tools/swift-tavla/kjor.sh                         # ny fasit for Tavla
```

Så må TypeScript-koden endres til testene er grønne igjen.

Regler som gjelder her som i Swift (se `CLAUDE.md`):

- All avrunding som i PWA-en går gjennom `jsRound` = `Math.floor(x + 0.5)`, aldri `Math.round` direkte.
  Der Swift bruker `.rounded()` (bort fra null), brukes `roundAwayFromZero`.
- Norsk sortering med `Intl.Collator('no')`, som `localeCompare(…, 'no')`.
- Ingen regelverdier i koden. Faste tall finnes bare i Golfgutu-malen (`GOLFGUTU` i `src/ruleset.ts`).
- UUID-er holdes med små bokstaver. Appen bruker `UUID.uuidString` (store bokstaver); rekkefølgen og
  likheten er den samme, så tallene blir like.

## Bruk

```ts
import { standingsFromTavlaData } from "./src/index.ts";

// tavlaData: svaret fra `rpc('tavla_data', { p_season_id })`.
// season: raden fra `seasons` (id, club_id, name, status, rules).
const tabell = standingsFromTavlaData(tavlaData, season, medlemsIdTilDenSomSer);
// tabell.rows: plass, navn, total, duell, sidepremier, matcher, hull, stableford, kvelder, isMe,
//   og tekstene placeText («3.» eller «–»), totalText («4,5»), detail («+3 hull · 112 stableford · 4 kvelder»)
//   og basis («4,5 fra 5 dueller · 1 fra sidepremier · +3 hull»).
// tabell.rounds: «Alle runder» (kolonner, poeng/slag/mot par per runde, beste per runde).
```

Stegene finnes også hver for seg: `decodeTavlaData`, `decodeSeasonRow`, `tavlaInput`,
`new TavlaStandings(input, me)`, `tavlaToJSON`. Liga og morro: `PersonDirectory`, `CompetitionScope`
(`input(...)`), `new LeagueStandings(input, me)`. Cup: `CupStandings`, `cupSeeded`, `cupDraw`, `cupBracket`,
`cupDecide`. Selve motoren: `Season` (jakketavla, stablefordsummen, utvalget), `decodeRuleset`/`encodeRuleset`,
`validateRuleset`, `effectiveHandicap`, `roundPoints`, `matchStanding` og resten i `src/`.

## Hva som er portert

| Swift (`Sources/GolfgutuCore`) | TypeScript (`src/`) |
| --- | --- |
| JSMath | `jsmath.ts` |
| Models, Match (modellen), SidePrize (modellen) | `models.ts` |
| Ruleset, DayTerm, RulesetTemplate, RulesetValidation | `ruleset.ts`, `dayterm.ts`, `template.ts`, `validation.ts` |
| CompetitionForm, FormSetup | `forms.ts`, `formsetup.ts` |
| CourseRules | `course.ts` |
| Handicap | `handicap.ts` |
| WHS | `whs.ts` |
| Scoring, Truncation | `scoring.ts`, `truncation.ts` |
| Match, Triangle, SidePrize | `match.ts`, `triangle.ts`, `sideprize.ts` |
| Season | `season.ts` |
| Competitions (liga, cup, SplitMix64) | `competitions.ts` |

Fra appen (`DashDash18/`): radtypene (`Data/Rows.swift`, `FoundationRows.swift`) i `app/rows.ts`,
`RoundSnapshot`/`RoundGame.makeRound` i `app/roundgame.ts`, `TavlaData`, `TavlaStandings` og `RoundsGrid` i
`app/tavla.ts`, og `CompetitionScope`, `LeagueStandings` og `CupStandings` i `app/competition.ts`.

Ikke portert ennå: `Bets` (veddemål), `Games`, `GameNassau`, `GameSkins`, `GameWolf` (spill på runden),
`Tips` (tippekupongen) og `PlayerStats` (profilstatistikk). Regelsettets felt for tips og veddemål leses og
skrives likevel, så regelsett-JSON-en går fram og tilbake uten tap, og valideringen sjekker dem.
