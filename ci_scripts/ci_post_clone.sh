#!/bin/sh
# Xcode Cloud: skriver Supabase-konfigen, som ikke ligger i git.
# Verdiene settes som miljøvariabler i workflowen (App Store Connect → Xcode Cloud):
#   SUPABASE_PROJECT_REF      prosjekt-id, f.eks. tsekialrxuhrugscosgi (bare bokstaver;
#                             Xcode Cloud godtar ikke «https://» i verdier)
#   SUPABASE_PUBLISHABLE_KEY  publishable key (aldri service-role)
# Bygget går alltid mot test. Prod kommer i fase 9.
set -eu

# Mellomrom og linjeskift fra liming i Xcode Cloud fjernes før sjekkene.
SUPABASE_PROJECT_REF=$(printf '%s' "${SUPABASE_PROJECT_REF:-}" | tr -d '[:space:]')
SUPABASE_PUBLISHABLE_KEY=$(printf '%s' "${SUPABASE_PUBLISHABLE_KEY:-}" | tr -d '[:space:]')
: "${SUPABASE_PROJECT_REF:?Mangler SUPABASE_PROJECT_REF i Xcode Cloud-workflowen}"
case "$SUPABASE_PROJECT_REF" in
  *[!a-z0-9]*) echo "Feil: SUPABASE_PROJECT_REF skal bare ha små bokstaver og tall" >&2; exit 1 ;;
esac
SUPABASE_URL="https://$SUPABASE_PROJECT_REF.supabase.co"
: "${SUPABASE_PUBLISHABLE_KEY:?Mangler SUPABASE_PUBLISHABLE_KEY i Xcode Cloud-workflowen}"

case "$SUPABASE_PUBLISHABLE_KEY" in
  sb_secret_*|*service_role*) echo "Feil: hemmelig nøkkel i SUPABASE_PUBLISHABLE_KEY" >&2; exit 1 ;;
  sb_publishable_*) ;;
  # Gamle JWT-nøkler (anon og service_role) ser like ut uten dekoding. Prosjektet bruker
  # publishable keys, så alt annet avvises (appen sjekker også, se AppConfig.isSecretKey).
  *) echo "Feil: SUPABASE_PUBLISHABLE_KEY skal starte med sb_publishable_ (begynner med «$(printf '%s' "$SUPABASE_PUBLISHABLE_KEY" | cut -c1-3)…», ${#SUPABASE_PUBLISHABLE_KEY} tegn)" >&2; exit 1 ;;
esac

CONFIG_DIR="$CI_PRIMARY_REPOSITORY_PATH/DashDash18/Config"
mkdir -p "$CONFIG_DIR"
cat > "$CONFIG_DIR/Supabase-Test.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Environment</key>
	<string>test</string>
	<key>SupabasePublishableKey</key>
	<string>$SUPABASE_PUBLISHABLE_KEY</string>
	<key>SupabaseURL</key>
	<string>$SUPABASE_URL</string>
</dict>
</plist>
PLIST
plutil -lint "$CONFIG_DIR/Supabase-Test.plist"
echo "Skrev Supabase-Test.plist for $SUPABASE_URL"

# Pakkene løses med den Xcode-versjonen Xcode Cloud faktisk bruker. Nyere Swift kan velge en
# annen manifestfil i en avhengighet (swift-clocks → swift-issue-reporting), og da stemmer ikke
# Package.resolved fra Mac-en. Oppdateringen skjer bare i bygget, ikke i git.
echo "Xcode: $(xcodebuild -version | head -1)"
xcodebuild -resolvePackageDependencies -project "$CI_PRIMARY_REPOSITORY_PATH/DashDash18.xcodeproj" \
  -scheme DashDash18 >/dev/null
echo "Pakkene er løst."
