# Regelverdier i GolfgutuCore

Kartlegging (fase 3, regelsett-revisjon, R1). Hver verdi som står fast i koden, hvor den brukes,
om den ligger i `Ruleset` i dag, og Golfgutu-verdien (PWA-en, `db-nytt.js`).

Status: **Ja** = i `Ruleset`. **Nei** = fast i koden. Vurdering: **flytt** = turneringsvalg som
skal inn i regelsettet (R2), **bli** = golfregel, WHS-matematikk, dataregel eller ren visning.

## Poeng per hull og runde

| Verdi | Brukes i | I Ruleset | Golfgutu | Vurdering |
|---|---|---|---|---|
| Stableford: poeng for netto par | `Scoring.points` (`par − netto + 2`) | Nei | 2 | flytt |
| Stableford: laveste poeng på et hull | `Scoring.points` (`max(0, …)`) | Nei | 0 | flytt |
| Poeng for tomt hull ved `nettopar` (`POENG_NETTO_PAR`) | `Truncation.pointsForEmptyHole`, `netParPoints` | Nei | 2 | følger «poeng for netto par» (samme tall per definisjon) |
| Navn på hull (eagle ≤ −2 … blowup) | `Scoring.scoreName` | Nei | −2/−1/0/1/2 | bli (golfbegreper, bare visning) |
| Slagfordeling etter stroke index, 9 eller 18 hull | `Scoring.handicapStrokes` | Nei | – | bli (golfregel) |
| Lagets poeng per hull (`sum-netto`, `beste-netto`, ett kort) | `Scoring.teamPoints` | Nei | – | bli (del av formens definisjon) |

## Avkorting

| Verdi | Brukes i | I Ruleset | Golfgutu | Vurdering |
|---|---|---|---|---|
| Reglene `felles`, `nettopar`, `null` | `Truncation.Rule` | Nei | alle tre | bli (velges per runde av arrangøren, lagres på runden) |
| `felles` kutter til `round(avkortetEtter)`, under 1 = hele runden | `Truncation.countingHoles` | Nei | – | bli (dataregel) |

## Bane

| Verdi | Brukes i | I Ruleset | Golfgutu | Vurdering |
|---|---|---|---|---|
| `DEFAULT_PAR` (par 72) | `Course.defaultPar`, `courseHoles` | Nei | 4,5,3,4,4,3,5,4,4,4,3,5,4,4,3,4,5,4 | bli (reserve når banedata mangler) |
| Gyldig par 3–6 | `Course.isValidPar`, `isReady`, `courseHoles` | Nei | 3…6 | bli, se åpne spørsmål |
| Lengde per par (`PAR_LENGDE`) | `Course.parLengthRange` | Nei | 3: 90–210, 4: 230–440, 5: 420–580 | bli, se åpne spørsmål |
| 9 eller 18 hull, start på hull 10 | `Round.numberOfHoles`, `courseHoles` | Nei | – | bli (dataregel) |

## Handicap

| Verdi | Brukes i | I Ruleset | Golfgutu | Vurdering |
|---|---|---|---|---|
| WHS: `indeks · slope/113 + (CR − par)`, 113, par 72 som reserve | `Handicap.courseHandicap` | Nei | – | bli (WHS) |
| Andel per form (`hcpAndel`) og regelen «per spiller, ellers 1» | `CompetitionForm.all`, `Ruleset.allowance(for:)` | Delvis (`allowanceOverride`) | stableford 0,95, match 1, fourball-4 0,75, brutto 0, øvrige 1 | flytt (andel per form) |
| Seeding-grupper | `Handicap.groupHandicap` | Ja | 1/2/3 = 0/5/10 | – |
| Ekstern handicap (simulator) for nye runder | `Ruleset.externalHandicap` | Ja | av | – |
| Lagshandicap, toerformer: snitt av grunnlagene | `Handicap.teamHandicap` | Nei | snitt | flytt |
| Lagshandicap, `scramble-4`: 25/20/15/10 % (lavest først) | `Handicap.scramble4Weights` | Nei | 0,25/0,20/0,15/0,10 | flytt |
| Lagshandicap, øvrige: laveste · andel | `Handicap.teamHandicap` | Nei | laveste | flytt (samme regel som over) |
| Lagsgrunnlag: banehandicap · hull/18, seedet = gruppetall | `Handicap.teamBasis` | Nei | – | bli (matematikk) |
| `effectiveHandicap`: `round(bane · andel · hull/18)` | `Handicap.effective` | Nei | – | bli (matematikk) |
| Rundens andel mangler → 1 | `Handicap.allowance` | Nei | 1 | bli (eldre runder) |

## Match og trekant

| Verdi | Brukes i | I Ruleset | Golfgutu | Vurdering |
|---|---|---|---|---|
| Matchslag: laveste spiller fra scratch (full forskjell) | `MatchPlay.strokeOffset` | Nei | laveste fra scratch | flytt |
| Laveste netto vinner hullet, avgjort når opp > igjen | `MatchPlay.holeWinner`, `standing` | Nei | – | bli (golfregel) |
| Utfall 1/0,5/0 (intern koding) | `MatchPlay.outcomeForA` | Nei | – | bli (koding; poengene kommer fra `matchPoints`) |
| Poeng for seier/uavgjort/tap | `MatchPlay.points(forOutcome:)` | Ja | 1/0,5/0 | – |
| Trekantpoeng etter plass | `Triangle.points` | Ja | 1/0,5/0 | – |
| Trekant rangeres på stablefordsum, delt plass deler | `Triangle.points` | Nei | – | bli, se åpne spørsmål |
| Trekning: stilling, navn, snu på oddetall omgang, trekant av de tre siste | `Triangle.drawMatches` | Nei | – | bli (algoritme) |

## Sidepremier

| Verdi | Brukes i | I Ruleset | Golfgutu | Vurdering |
|---|---|---|---|---|
| Sidepremier av/på | `Season.sidePrizeResults` | Ja (felles for LD og KP) | på | flytt til av/på per premie |
| Poeng per premie | `Season.sidePrizeResults` | Ja (felles) | 1 | flytt til per premie |
| Deling ved likt (1/n) | `Season.sidePrizeResults` | Nei | deles | flytt |
| Drive: lengst vinner. KP: kortest vinner | `SidePrizes.longestDriveClaims`, `closestToPinClaims` | Nei | – | bli (premiens definisjon) |
| Foreslått LD-hull (lengste par ≥ 4 …) og KP-hull (første par 3 fra hull 4 …) | `SidePrizes.suggested…Hole` | Nei | – | bli (bare forslag; arrangøren velger hull) |

## Tabell og sesong

| Verdi | Brukes i | I Ruleset | Golfgutu | Vurdering |
|---|---|---|---|---|
| Antall kvelder | `Ruleset.evenings` | Ja | 7 | – |
| Hva som teller i tabellen (`TELLENDE_MATCHER`) | `Season.matchResults` | Ja (`countingEvenings`, men betyr matcher) | alle | gjøres eksplisitt (R3) |
| Hva som teller i stablefordsummen (`TELLENDE_RUNDER`) | `Season.countingRounds` | Ja | beste 5 runder | gjøres eksplisitt (R3) |
| Utvalg sorteres på poeng, så hulldifferanse | `Season.matchResults` | Nei | – | bli (del av «beste N») |
| Sidepremier strykes aldri | `Season.jacketBoard` | Nei | – | se R3 |
| Avrunding til halve poeng i tabellen | `Season.matchSum`, `jacketBoard`, `formatPoints` | Nei | 0,5 | flytt |
| Skilletegn | `Season.jacketBoard` | Ja | hulldifferanse, stablefordsum | – |
| Navn skiller til slutt | `Season.jacketBoard` | Nei | – | bli (alltid siste) |
| Rundevekt (`multiplier`), 0 = teller ikke | `Season.weight` | Nei | 1 | bli (lagres per runde av arrangøren) |
| To runder samme dato = én kveld | `Season.eveningDates` | Nei | – | bli (definisjon) |

## Former og oppsett

| Verdi | Brukes i | I Ruleset | Golfgutu | Vurdering |
|---|---|---|---|---|
| Standardform | `Ruleset.defaultFormID` | Ja | stableford | – |
| Maks per bås | `Ruleset.maxPerBay`, `CompetitionForm.golfgutuMaxPerBay` | Ja | 4 | – |
| Tillatte former | – | Nei | alle | flytt |
| Formkatalogen (lag, kort, regning, støtte, skjeve lag, hjelpetekst) | `CompetitionForm.all` | Nei | 16 former | bli (katalog; andelen flyttes) |
| Minst 2 spillere, oddetall gir én trekant | `CompetitionForm.setup` | Nei | – | bli, se åpne spørsmål |

## Åpne spørsmål

1. **Par 3–6 og lengdegrensene** er plausibilitetssjekker for banebiblioteket, som deles av alle sesonger. De kan ikke avhenge av én sesongs regelsett. Blir i koden til vi vet om noen trenger par 7 eller andre grenser.
2. **Trekant rangert på stableford** og **oddetall gir trekant** er slik PWA-en gjør det. Andre grupper vil kanskje ha en fri runde (bye) i stedet. Ikke tatt med nå.
