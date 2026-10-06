# Regelverdier i GolfgutuCore

Alle verdier i regelmotoren som er et valg for turneringen, ligger i `Ruleset`. Faste tall står bare
i `Ruleset.golfgutu` (Golfgutu-oppsettet, som gir samme svar som PWA-en). Tabellene under viser hver
regelverdi: hvor den brukes, feltet i `Ruleset` (eller hvorfor den blir i koden) og Golfgutu-verdien.

Funksjonene i regelmotoren tar `rules: Ruleset = .golfgutu`. `Season` bruker sitt eget regelsett.

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
