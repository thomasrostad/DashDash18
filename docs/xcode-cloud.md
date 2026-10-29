# Xcode Cloud og TestFlight

Workflowen **TestFlight fra main** bygger appen og sender den til TestFlight hver gang noe pushes til `main`.

## Oppsett (gjort 07.10.2026)

- **Start:** endringer på `main`. Auto-cancel er på, så en ny push avbryter et bygg som går.
- **Xcode:** 26.6, låst til samme versjon som på Mac-en. Med «Latest Release» bruker `swift-clocks` en nyere manifestfil (Swift 6.4) som krever `swift-issue-reporting`, og da stemmer ikke `Package.resolved`.
- **Handling:** Archive – iOS, skjema `DashDash18`, Deployment Preparation «App Store Connect».
- **Etterpå:** TestFlight External Testing.
- **Byggnummer:** settes av Xcode Cloud (startet på 12). `CURRENT_PROJECT_VERSION` i prosjektet brukes bare ved manuell arkivering.
- **Miljøvariabler:**
  - `SUPABASE_PROJECT_REF`: prosjekt-ID-en til test (Xcode Cloud godtar ikke `https://` i verdier)
  - `SUPABASE_PUBLISHABLE_KEY`: publishable key, merket Secret
- **`ci_scripts/ci_post_clone.sh`** fjerner mellomrom og linjeskift i verdiene, løser pakkene med Xcode-versjonen bygget bruker, og skriver `DashDash18/Config/Supabase-Test.plist` fra variablene. Det stopper hvis nøkkelen ser hemmelig ut eller ikke starter med `sb_publishable_`.

## Vanlig bruk

- Endringer i appen: merge PR-en til `main`. Bygget kommer i TestFlight etter 15–30 minutter.
- Bare dokumentasjon eller SQL: skriv `[ci skip]` i tittelen på PR-en (squash-commiten), så startes ingen bygg.
- SQL, Edge Functions og secrets i Supabase trenger ikke nytt bygg.

## Når Xcode på Mac-en oppdateres

1. Åpne prosjektet og la Xcode løse pakkene. Commit `Package.resolved` hvis den endres.
2. Endre Xcode-versjonen i workflowen til den samme.

## Når det kommer et nytt mål (app, klokke, utvidelse)

Xcode Cloud registrerer ikke selv bundle-id-en til et nytt mål. Arkiveringen går, men eksporten feiler med «Exporting for App Store Distribution failed» (28.10.2026: alle bygg etter klokkeappen, #235–#238).

1. Arkiver og eksporter én gang på Mac-en med automatisk signering, så Xcode registrerer id-en og lager App Store-profilen:
   `xcodebuild archive -project DashDash18.xcodeproj -scheme DashDash18 -destination "generic/platform=iOS" -archivePath ~/Library/Developer/Xcode/DerivedData/DashDash18-cli/Atten.xcarchive -allowProvisioningUpdates`, så `xcodebuild -exportArchive … -exportOptionsPlist <method app-store-connect, destination export> -allowProvisioningUpdates`. Ingenting lastes opp.
2. Start bygget i Xcode Cloud på nytt.

Klokkeappen (`com.dashdash18.app.watchkitapp`) ble registrert slik 29.10.2026.
