#!/usr/bin/env bash
# Bygg Atten for Garmin (samme oppsett som GolfFace i ~/Garmin klokkeskiver).
#
#   garmin/tools/build.sh            # alle modellene, streng typesjekk og advarsler
#   garmin/tools/build.sh quick      # én per skjermtype
#   garmin/tools/build.sh test       # bygg og kjør testene i simulatoren
#   garmin/tools/build.sh package    # garmin/build/Atten.iq til Connect IQ Store
#   garmin/tools/build.sh beta       # garmin/build/Atten-beta.iq: beta i Connect IQ Store, egen app-id
#
# Utviklernøkkelen ligger utenfor repoet: GARMIN_DEVELOPER_KEY, ellers ~/Garmin klokkeskiver/developer_key.
set -euo pipefail
cd "$(dirname "$0")/.."

# Connect IQ trenger en JDK. macOS har ingen; dette finner Homebrew sin uten at den er lenket.
if ! java -version >/dev/null 2>&1; then
  for c in /opt/homebrew/opt/openjdk@21 /opt/homebrew/opt/openjdk \
           /usr/local/opt/openjdk@21 /usr/local/opt/openjdk; do
    if [ -x "$c/bin/java" ]; then export JAVA_HOME="$c"; export PATH="$c/bin:$PATH"; break; fi
  done
fi
java -version >/dev/null 2>&1 || { echo "Ingen JDK: brew install openjdk@21"; exit 1; }

SDK="$(cat "$HOME/Library/Application Support/Garmin/ConnectIQ/current-sdk.cfg")"
MONKEYC="$SDK/bin/monkeyc"
MONKEYDO="$SDK/bin/monkeydo"
KEY="${GARMIN_DEVELOPER_KEY:-$HOME/Garmin klokkeskiver/developer_key}"
[ -f "$KEY" ] || { echo "Fant ikke utviklernøkkelen: $KEY"; exit 1; }

ALL=(fenix6 fenix6pro fenix6s fenix6spro fenix6xpro
     fenix7 fenix7s fenix7x fenix7pro fenix7spro fenix7xpro fenix7pronowifi fenix7xpronowifi
     fenix843mm fenix847mm fenix8pro47mm fenix8solar47mm fenix8solar51mm
     fr945 fr945lte fr955 fr965 fr970
     epix2 epix2pro42mm epix2pro47mm epix2pro51mm)

# Én per skjermtype: 240 MIP, 260 MIP, 280 MIP, 416 AMOLED, 454 AMOLED.
QUICK=(fr945 fenix7 fenix6xpro fenix843mm fenix847mm)

mkdir -p build

build_list() {
  for d in "$@"; do
    printf '%-18s ' "$d"
    "$MONKEYC" -f monkey.jungle -d "$d" -o "build/Atten-$d.prg" -y "$KEY" -w -l 3
    echo ok
  done
}

case "${1:-all}" in
  quick)   build_list "${QUICK[@]}" ;;
  test)
    "$MONKEYC" -f monkey.jungle -d fenix7 -o build/test.prg -y "$KEY" --unit-test -w -l 3
    "$MONKEYDO" build/test.prg fenix7 -t
    ;;
  package)
    "$MONKEYC" -f monkey.jungle -e -o build/Atten.iq -y "$KEY" -w -l 3 -r
    echo "Til butikken: garmin/build/Atten.iq"
    ;;
  beta)
    # Garmin krever en egen app-id for en beta. Manifestet er det samme, bare med beta-id-en
    # (GarminLink.betaAppID i Atten), så modellene står ett sted.
    # Filene lages ved siden av manifest.xml (stiene i en jungle-fil gjelder fra mappa den ligger i)
    # og holdes utenfor git (.gitignore).
    sed 's/id="df4f21f2526649f4baac635fdd298301"/id="944279ed92854eb2b674f1b9b70a14c3"/' manifest.xml > manifest-beta.xml
    grep -q 944279ed92854eb2b674f1b9b70a14c3 manifest-beta.xml || { echo "Fant ikke app-id-en i manifest.xml"; exit 1; }
    printf 'project.manifest = manifest-beta.xml\nbase.sourcePath = source;source-release\n' > beta.jungle
    "$MONKEYC" -f beta.jungle -e -o build/Atten-beta.iq -y "$KEY" -w -l 3 -r
    echo "Beta til butikken: garmin/build/Atten-beta.iq"
    ;;
  *)       build_list "${ALL[@]}" ;;
esac
