#!/bin/sh
# Xcode Cloud: skriver Supabase-konfigen, som ikke ligger i git.
# Verdiene settes som miljøvariabler i workflowen (App Store Connect → Xcode Cloud):
#   SUPABASE_URL              f.eks. https://<ref>.supabase.co
#   SUPABASE_PUBLISHABLE_KEY  publishable key (aldri service-role)
# Bygget går alltid mot test. Prod kommer i fase 9.
set -eu

: "${SUPABASE_URL:?Mangler SUPABASE_URL i Xcode Cloud-workflowen}"
: "${SUPABASE_PUBLISHABLE_KEY:?Mangler SUPABASE_PUBLISHABLE_KEY i Xcode Cloud-workflowen}"

case "$SUPABASE_PUBLISHABLE_KEY" in
  sb_secret_*|*service_role*) echo "Feil: hemmelig nøkkel i SUPABASE_PUBLISHABLE_KEY" >&2; exit 1 ;;
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
