# Regelverdier i GolfgutuCore

Alle verdier i regelmotoren som er et valg for turneringen, ligger i `Ruleset`. Faste tall står bare
i `Ruleset.golfgutu` (Golfgutu-oppsettet, som gir samme svar som PWA-en). Tabellene under viser hver
regelverdi: hvor den brukes, feltet i `Ruleset` (eller hvorfor den blir i koden) og Golfgutu-verdien.

Funksjonene i regelmotoren tar `rules: Ruleset = .golfgutu`. `Season` bruker sitt eget regelsett.
`Ruleset.validate()` gir en liste med problemer (`RulesetIssue`: felt og norsk melding) før lagring.

## Struktur (versjon 2)

| Felt | Type | Betydning |
|---|---|---|
| `version` | tall | 2. Mangler feltet, eller er det 1, leses den gamle flate formen. |
| `evenings` | tall | Antall kvelder i sesongen. |
| `scoring.netParPoints` | tall | Stablefordpoeng for netto par (og for uspilt hull ved `nettopar`). |
| `scoring.minimumPoints` | tall | Laveste poeng på et hull. |
| `table.matchPoints` | `{win, draw, loss}` | Poeng for utfallet av en duell. |
| `table.trianglePoints` | 3 tall | Poeng etter plass i trekanten, beste først. Delt plass deler. |
| `table.counting` | `{unit, best}` | Hva som teller i tabellen. `unit`: `match`, `round`, `evening`. `best`: N eller `null` (alle). |
| `table.stablefordCounting` | `{unit, best}` | Hva som teller i stablefordsummen. `unit`: `round`, `evening`. |
| `table.tiebreaks` | liste | `holeDifference`, `stableford` i ønsket rekkefølge. Navn skiller alltid til slutt. |
| `table.roundingStep` | tall eller `null` | Avrunding av tabellpoeng (0,5 = halve). `null`: ingen. |
| `sidePrizes.longestDrive`, `sidePrizes.closestToPin` | `{enabled, points}` | Av/på og poeng per premie. |
| `sidePrizes.splitTies` | sann/usann | Likt deler poenget. Usann: alle på delt førsteplass får fullt. |
| `handicap.allowanceOverride` | tall eller `null` | Én andel for alle former. `null`: per form. |
| `handicap.formAllowances` | form-id → tall | Andelen en ny runde i formen får. Mangler formen: 1. |
| `handicap.seedingGroups` | liste | `{number, handicap, name}`. Tom: ingen seeding. |
| `handicap.externalHandicap` | sann/usann | Simulatoren deler ut slagene på nye runder. |
| `handicap.teamHandicap` | form-id → `{method, weights}` | `average`, `weighted` (vekter lavest først) eller `lowest` (laveste · andel). Mangler formen: `lowest`. |
| `formats.defaultFormID` | form-id | Formen en ny runde starter med. Må være tillatt. |
| `formats.allowedFormIDs` | liste | Formene arrangøren kan velge. |
| `formats.maxPerBay` | tall | Største lag i en bås. |
| `formats.matchStrokes` | `lowestFromScratch` / `fullHandicap` | Slag i match. |
| `bets.lockAheadHoles` | tall | Veddemål: hvor mange hull foran spilleren det første åpne hullet ligger. |
| `bets.maxStakePerBet` | tall | Veddemål: mest én spiller kan ha på ett veddemål. |
| `bets.stakeOptions` | liste | Veddemål: beløpsknappene i vedd-arket. |
| `bets.defaultStake` | tall | Veddemål: beløpet som er valgt når arket åpnes. |
| `bets.startingPoints` | tall eller `null` | Poengbanken: startbeholdning per sesong. `null`: ingen bank, bare taket gjelder. |

Felt som mangler i JSON-en, får Golfgutu-verdien. `null` er et valg der feltet tillater det
(`best`, `roundingStep`, `allowanceOverride`). Skjemaets standard `{"version": 1}` blir Golfgutu-oppsettet.

### Golfgutu

Fixture: `Tests/GolfgutuCoreTests/Fixtures/regelsett-golfgutu.json` (lik `Ruleset.golfgutu`).

```json
{
  "version": 2,
  "evenings": 7,
  "scoring": { "netParPoints": 2, "minimumPoints": 0 },
  "table": {
    "matchPoints": { "win": 1, "draw": 0.5, "loss": 0 },
    "trianglePoints": [1, 0.5, 0],
    "counting": { "unit": "match", "best": null },
    "stablefordCounting": { "unit": "round", "best": 5 },
    "tiebreaks": ["holeDifference", "stableford"],
    "roundingStep": 0.5
  },
  "sidePrizes": {
    "longestDrive": { "enabled": true, "points": 1 },
    "closestToPin": { "enabled": true, "points": 1 },
    "splitTies": true
  },
  "handicap": {
    "allowanceOverride": null,
    "formAllowances": {
      "stableford": 0.95, "stableford-brutto": 0, "slag-netto": 0.95, "slag-brutto": 0,
      "par-bogey": 0.95, "maks-score": 0.95, "match": 1, "fourball": 1, "fourball-4": 0.75,
      "sammenlagt-lag": 1, "foursome": 1, "greensome": 1, "chapman": 1, "scramble-2": 1,
      "scramble-4": 1, "skins": 0.95
    },
    "seedingGroups": [
      { "number": 1, "handicap": 0, "name": "Gruppe 1" },
      { "number": 2, "handicap": 5, "name": "Gruppe 2" },
      { "number": 3, "handicap": 10, "name": "Gruppe 3" }
    ],
    "externalHandicap": false,
    "teamHandicap": {
      "fourball": { "method": "average" },
      "sammenlagt-lag": { "method": "average" },
      "foursome": { "method": "average" },
      "greensome": { "method": "average" },
      "chapman": { "method": "average" },
      "scramble-2": { "method": "average" },
      "scramble-4": { "method": "weighted", "weights": [0.25, 0.20, 0.15, 0.10] }
    }
  },
  "formats": {
    "defaultFormID": "stableford",
    "allowedFormIDs": [
      "stableford", "stableford-brutto", "slag-netto", "slag-brutto", "par-bogey", "maks-score",
      "match", "fourball", "fourball-4", "sammenlagt-lag", "foursome", "greensome", "chapman",
      "scramble-2", "scramble-4", "skins"
    ],
    "maxPerBay": 4,
    "matchStrokes": "lowestFromScratch"
  }
}
```

### Et annet oppsett

5 kvelder, de 3 beste kveldene teller (både i tabellen og stablefordsummen), seier 3 / uavgjort 1 / tap 0,
trekant 3/1/0, ingen sidepremier, ingen avrunding, fullt handicap, ingen seeding, fire former og
stablefordsum før hulldifferanse. `formAllowances` og `teamHandicap` er utelatt og får Golfgutu-verdien.
Fixture: `Tests/GolfgutuCoreTests/Fixtures/regelsett-eksempel.json` (testet i `annetOppsettFraJSON`).

```json
{
  "version": 2,
  "evenings": 5,
  "scoring": { "netParPoints": 2, "minimumPoints": 0 },
  "table": {
    "matchPoints": { "win": 3, "draw": 1, "loss": 0 },
    "trianglePoints": [3, 1, 0],
    "counting": { "unit": "evening", "best": 3 },
    "stablefordCounting": { "unit": "evening", "best": 3 },
    "tiebreaks": ["stableford", "holeDifference"],
    "roundingStep": null
  },
  "sidePrizes": {
    "longestDrive": { "enabled": false, "points": 0 },
    "closestToPin": { "enabled": false, "points": 0 },
    "splitTies": true
  },
  "handicap": {
    "allowanceOverride": 1,
    "seedingGroups": [],
    "externalHandicap": false
  },
  "formats": {
    "defaultFormID": "stableford",
    "allowedFormIDs": ["stableford", "match", "fourball", "scramble-2"],
    "maxPerBay": 4,
    "matchStrokes": "lowestFromScratch"
  }
}
```

### Versjon 1 (lest, ikke skrevet)

Flat form: `allowanceOverride`, `seedingGroups`, `externalHandicap`, `defaultFormID`, `maxPerBay`,
`evenings`, `countingEvenings` (→ `table.counting` med `unit: match`), `stablefordCountingEvenings`
(→ `table.stablefordCounting` med `unit: round`), `matchPoints`, `sidePrizes {enabled, points}`
(→ begge premiene), `trianglePoints`, `tiebreaks`. Fixture: `regelsett-golfgutu-v1.json`.

## Gyldighetssjekk

`validate()` melder blant annet: under én kveld; «beste N» under 1, eller flere kvelder enn sesongen har;
stablefordsum som teller matcher; negative poeng (duell, trekant, sidepremier, netto par); seier under
uavgjort eller uavgjort under tap; trekant uten tre plasser eller med bedre plass som gir mindre;
avrunding 0 eller mindre; samme skilletegn to ganger; laveste hullpoeng over netto par; andel utenfor
0–100 %; to seedinggrupper med samme nummer; vektet lagshandicap uten vekter eller med negative vekter;
maks per bås under 1; ingen tillatte former, ukjent form, og standardform som ikke er tillatt.

## Poeng per hull og runde

| Verdi | Brukes i | Ruleset | Golfgutu |
|---|---|---|---|
| Stableford: poeng for netto par | `Scoring.points` | `scoring.netParPoints` | 2 |
| Stableford: laveste poeng på et hull | `Scoring.points` | `scoring.minimumPoints` | 0 |
| Poeng for tomt hull ved `nettopar` (`POENG_NETTO_PAR`) | `Truncation.pointsForEmptyHole` | `scoring.netParPoints` (samme tall per definisjon) | 2 |
| Navn på hull (eagle ≤ −2 … blowup) | `Scoring.scoreName` | bli (golfbegreper, bare visning) | – |
| Slagfordeling etter stroke index, 9 eller 18 hull | `Scoring.handicapStrokes` | bli (golfregel) | – |
| Lagets poeng per hull (`sum-netto`, `beste-netto`, ett kort) | `Scoring.teamPoints` | bli (formens definisjon) | – |

## Avkorting

| Verdi | Brukes i | Ruleset | Golfgutu |
|---|---|---|---|
| Reglene `felles`, `nettopar`, `null` | `Truncation.Rule` | bli (velges per runde, lagres på runden) | – |
| `felles` kutter til `round(avkortetEtter)` | `Truncation.countingHoles` | bli (dataregel) | – |

## Bane

| Verdi | Brukes i | Ruleset | Golfgutu |
|---|---|---|---|
| `DEFAULT_PAR` | `Course.defaultPar` | bli (reserve når banedata mangler) | par 72 |
| Gyldig par 3–6 | `Course.isValidPar` | bli, se åpne spørsmål | 3…6 |
| Lengde per par (`PAR_LENGDE`) | `Course.parLengthRange` | bli, se åpne spørsmål | 3: 90–210, 4: 230–440, 5: 420–580 |
| 9 eller 18 hull, start på hull 10 | `Round.numberOfHoles`, `courseHoles` | bli (dataregel) | – |

## Handicap

| Verdi | Brukes i | Ruleset | Golfgutu |
|---|---|---|---|
| Andel per form for nye runder | `Ruleset.allowance(for:)` | `handicap.formAllowances`, `handicap.allowanceOverride` | stableford 0,95, match 1, fourball-4 0,75, brutto 0, lagformer 1 |
| Seeding-grupper | `Handicap.groupHandicap` | `handicap.seedingGroups` | 1/2/3 = 0/5/10 |
| Ekstern handicap (simulator) for nye runder | – | `handicap.externalHandicap` | av |
| Lagshandicap per form | `Handicap.teamHandicap` | `handicap.teamHandicap` (`average`, `weighted` med `weights`, `lowest`; mangler = `lowest`) | toerformer snitt, scramble-4 25/20/15/10, ellers laveste · andel |
| WHS: `indeks · slope/113 + (CR − par)` | `Handicap.courseHandicap` | bli (WHS) | – |
| Lagsgrunnlag: banehandicap · hull/18 | `Handicap.teamBasis` | bli (matematikk) | – |
| `effectiveHandicap`: `round(bane · andel · hull/18)` | `Handicap.effective` | bli (matematikk) | – |
| Rundens andel mangler → 1 | `Handicap.allowance` | bli (eldre runder) | 1 |

## Match og trekant

| Verdi | Brukes i | Ruleset | Golfgutu |
|---|---|---|---|
| Matchslag | `MatchPlay.strokeOffset` | `formats.matchStrokes` (`lowestFromScratch`, `fullHandicap`) | laveste fra scratch |
| Poeng for seier/uavgjort/tap | `MatchPlay.points(forOutcome:)` | `table.matchPoints` | 1/0,5/0 |
| Trekantpoeng etter plass | `Triangle.points` | `table.trianglePoints` | 1/0,5/0 |
| Laveste netto vinner hullet, avgjort når opp > igjen | `MatchPlay` | bli (golfregel) | – |
| Utfall 1/0,5/0 (intern koding) | `MatchPlay.outcomeForA` | bli (koding; poengene fra `table.matchPoints`) | – |
| Trekant rangeres på stablefordsum, delt plass deler | `Triangle.points` | bli, se åpne spørsmål | – |
| Trekning (stilling, navn, snu, trekant av de tre siste) | `Triangle.drawMatches` | bli (algoritme) | – |

## Sidepremier

| Verdi | Brukes i | Ruleset | Golfgutu |
|---|---|---|---|
| Longest drive av/på og poeng | `Season.sidePrizeResults` | `sidePrizes.longestDrive` | på, 1 |
| Nærmest pinnen av/på og poeng | `Season.sidePrizeResults` | `sidePrizes.closestToPin` | på, 1 |
| Deling ved likt (1/n) | `Season.sidePrizeResults` | `sidePrizes.splitTies` (av: alle på delt førsteplass får fullt) | deles |
| Drive: lengst vinner. KP: kortest vinner | `SidePrizes` | bli (premiens definisjon) | – |
| Foreslått LD- og KP-hull | `SidePrizes.suggested…Hole` | bli (bare forslag; arrangøren velger hull) | – |

## Tabell og sesong

| Verdi | Brukes i | Ruleset | Golfgutu |
|---|---|---|---|
| Antall kvelder | – | `evenings` | 7 |
| Hva som teller i tabellen (`TELLENDE_MATCHER`) | `Season.tableSelection`, `matchResults` | `table.counting` (`unit`: `match`, `round`, `evening`; `best`: N eller `null` = alle) | `match`, alle |
| Hva som teller i stablefordsummen (`TELLENDE_RUNDER`) | `Season.countingRounds` | `table.stablefordCounting` (`unit`: `round`, `evening`) | `round`, beste 5 |
| Avrunding av tabellpoeng | `Season.matchSum`, `jacketBoard`, `formatPoints` | `table.roundingStep` (`null` = ingen) | 0,5 |
| Skilletegn | `Season.jacketBoard` | `table.tiebreaks` | hulldifferanse, stablefordsum |
| Utvalg sorteres på poeng, så hulldifferanse | `Season.matchResults` | bli (del av «beste N») | – |
| Navn skiller til slutt | `Season.jacketBoard` | bli (alltid siste) | – |
| Rundevekt (`multiplier`), 0 = teller ikke | `Season.weight` | bli (lagres per runde av arrangøren) | 1 |
| To runder samme dato = én kveld | `Season.eveningDates` | bli (definisjon) | – |

## Former og oppsett

| Verdi | Brukes i | Ruleset | Golfgutu |
|---|---|---|---|
| Standardform | – | `formats.defaultFormID` | stableford |
| Tillatte former | `Ruleset.suggestions`, `allowedForms` | `formats.allowedFormIDs` | alle 16 |
| Maks per bås | `Ruleset.setup`, `suggestions` | `formats.maxPerBay` | 4 |
| Formkatalogen (lag, kort, regning, støtte, hjelpetekst) | `CompetitionForm.all` | bli (katalog; andelen ligger i regelsettet) | 16 former |
| Ukjent form → stableford | `CompetitionForm.form(id:)` | bli (som `formForRunde`, gjelder lagrede runder) | – |
| Minst 2 spillere, oddetall gir én trekant | `CompetitionForm.setup` | bli, se åpne spørsmål | – |

### Telling («beste N»)

- `match` (Golfgutu): de N beste matchene, sortert på poeng og så hulldifferanse. Sidepremiene strykes aldri (som PWA-en).
- `evening`: spillerens tabellpoeng (matcher og sidepremier, vektet) summeres per kveld, altså rundene med samme dato. De N beste kveldene teller, med alt som ble vunnet der. Likt: hulldifferanse, så den tidligste kvelden.
- `round`: som `evening`, men per runde.
- Stablefordsummen: `round` (Golfgutu, beste 5 runder) eller `evening` (summen av kveldens runder).
- Med `best: null` gir alle enhetene samme svar: alt teller.

## Veddemål

Se `Bets.swift` og `docs/veddemaal-poeng.md`. Fixture: `veddemaal.json`.

| Verdi | Brukes i | Ruleset | Golfgutu |
|---|---|---|---|
| Forsprang (`VEDDEMAAL_FORSPRANG`) | `Bets.firstOpenHole`, `acceptsStakes`, `templates` | `bets.lockAheadHoles` | 1 |
| Tak per veddemål (`VEDD_TAK`) | `Bets.stakeProblem` | `bets.maxStakePerBet` | 200 |
| Beløpsknapper (`VEDD_BELOP`) | vedd-arket | `bets.stakeOptions` | 50, 100, 200 |
| Valgt beløp når arket åpnes | vedd-arket | `bets.defaultStake` | 100 |
| Startbeholdning (ny, ikke i PWA-en) | `Bets.balance`, `available`, `table` | `bets.startingPoints` | 1000 (forslag) |
| Grenser for birdie (≤ −1) og par (≤ 0) netto mot par | `Bets.outcome` | bli (vilkårets definisjon) | – |
| Vinnersiden deler taperpotten etter innsats, to desimaler (`rund2`) | `Bets.transfers`, `net` | bli (oppgjørsmodellen) | – |
| Største innsats og startbeholdning databasen godtar | `Bets.stakeLimits`, `bankLimit` | bli (datagrense) | 10 000 og 1 000 000 |

## Hvorfor noe blir i koden

- **Golfregler og WHS** (slagfordeling, WHS-formelen, hullvinner i match, «avgjort») er ikke valg en turnering tar. Endres de, er det ikke golf lenger.
- **Data og definisjoner** (9/18 hull, kveld = dato, rundens andel og vekt, avkortingsregel per runde) hører til runden og lagres der. Arrangøren setter dem når runden startes.
- **Visning og forslag** (navn på hull, foreslåtte LD/KP-hull) påvirker ikke poengene.
- **Banebiblioteket** deles mellom sesongene og kan ikke avhenge av én sesongs regelsett.

## Åpne spørsmål

1. **Par 3–6 og lengdegrensene** er plausibilitetssjekker for banebiblioteket. Blir i koden til vi vet om noen trenger par 7 eller andre grenser.
2. **Trekant rangert på stableford** og **oddetall gir trekant** er slik PWA-en gjør det. Andre grupper vil kanskje ha fri runde (bye) i stedet. Ikke tatt med nå.
3. **Sidepremier i kvelds-telling:** med `evening` og `round` er sidepremiene en del av kveldens poeng og strykes med kvelden. Med `match` strykes de aldri (PWA-en). Valgt fordi «tabellpoeng per kveld» naturlig tar med alt kvelden ga. Brukeren bør bekrefte.
4. **`fullHandicap` i match** er det eneste alternativet til «laveste fra scratch». Prosent av forskjellen (f.eks. 90 % som WHS anbefaler for fourball) er ikke tatt med.
