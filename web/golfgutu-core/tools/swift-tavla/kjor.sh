#!/bin/sh
# Lager test/fixtures/tavla.forventet.json med appens egen Swift-kode (TavlaStandings, RoundsGrid,
# CompetitionScope, LeagueStandings, og scorekortet fra RoundGame), så TS-mappingen kan sjekkes mot appen.
#
#   sh tools/swift-tavla/kjor.sh          (fra web/golfgutu-core)
#
# Kopierer de rene app-filene inn i Sources/TavlaFasit/App (ikke i git), uten SwiftUI-delen av TavlaRounds.swift.
set -eu
cd "$(dirname "$0")"
APP=../../../../DashDash18
OUT=Sources/TavlaFasit/App
rm -rf "$OUT"
mkdir -p "$OUT"
for f in Data/Rows.swift Data/FoundationRows.swift Features/Runde/RoundSnapshot.swift \
         Features/Admin/Runde/RoundVenue.swift Features/Tavla/TavlaData.swift Features/Tavla/TavlaStandings.swift \
         Features/Konkurranser/CompetitionScope.swift Features/Konkurranser/CompetitionStandings.swift; do
  cp "$APP/$f" "$OUT/"
done
# RoundsGrid og TavlaStandings.roundGrid, uten visningene under.
sed -e 's/^import SwiftUI$/import Foundation/' -e '/^\/\/\/ Hvilken spiller i hvilken runde scorekortet viser\./,$d' \
  "$APP/Features/Tavla/TavlaRounds.swift" > "$OUT/TavlaRounds.swift"
# Scorekortet (RoundGame.scorecard og total) fra føringen, uten resten av ForingLogic.swift.
{
  echo 'import Foundation'
  echo 'import GolfgutuCore'
  sed -n '/^\/\/\/ Hvem som ser på runden\./,/^}/p' "$APP/Features/Runde/ForingLogic.swift"
  sed -n '/^\/\/ MARK: - Bayen nå/,/^\/\/ MARK: - Feiringen/p' "$APP/Features/Runde/ForingLogic.swift" | sed '$d'
} > "$OUT/Scorecard.swift"
swift run -c debug --quiet TavlaFasit ../../test/fixtures/tavla.json > ../../test/fixtures/tavla.forventet.json
echo "Skrev test/fixtures/tavla.forventet.json"
