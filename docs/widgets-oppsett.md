# Widgets og Live Activity – oppsett i Xcode

Koden er klar, men widget-targetet må lages i Xcode. Til det er gjort, står begge flaggene av, og appen oppfører seg som før.

## Hva som ligger hvor

| Fil | Target |
| --- | --- |
| `DashDash18/LiveActivity/RoundActivityAttributes.swift` | **Begge** (DashDash18 og DashDash18Widgets) |
| `DashDash18/WidgetData/WidgetSnapshot.swift` | **Begge** |
| `DashDash18/LiveActivity/RoundActivityMapping.swift`, `RoundActivityController.swift` | Bare appen |
| `DashDash18/WidgetData/WidgetSnapshotMapping.swift` | Bare appen |
| `DashDash18Widgets/*.swift` | Bare DashDash18Widgets |

De to delte filene bruker bare Foundation, ActivityKit og WidgetKit. Resten av appen skal ikke inn i extension-targetet.

Fargene er kopiert fra `DesignSystem/DDPalette.swift` til `DashDash18Widgets/WidgetPalette.swift`. Ingen filer fra `DesignSystem/` trenger å være med i extension-targetet. Endrer du en farge i `DDToken`, må du endre den i `WidgetPalette` også. Widgetene bruker systemfonten, fordi 42dot Sans ikke er med i extension-targetet.

## Steg i Xcode

1. **Lag targetet.** Velg File → New → Target → iOS → **Widget Extension**.
   - Product Name: `DashDash18Widgets` (nøyaktig dette navnet)
   - Kryss av for **Include Live Activity**
   - Ta bort krysset for *Include Control* og *Include Configuration App Intent*
   - Embed in Application: `DashDash18`
   - Svar *Activate* på spørsmålet om skjemaet (eller *Cancel*, det spiller ingen rolle)

   Mappa `DashDash18Widgets/` finnes allerede på repo-rot, og Xcode legger malfilene inn i den. Er mappa synkronisert, blir filene våre med i targetet automatisk. Nekter Xcode fordi mappa finnes, gjør du slik: gi mappa et midlertidig navn i Finder (`DashDash18Widgets-kode`), lag targetet, flytt de seks `.swift`-filene inn i den nye `DashDash18Widgets/`, og slett den midlertidige mappa.

2. **Slett malfilene** i `DashDash18Widgets/` (Move to Trash): `DashDash18Widgets.swift`, `DashDash18WidgetsBundle.swift` og `DashDash18WidgetsLiveActivity.swift`. Slett også `DashDash18WidgetsControl.swift` og `AppIntent.swift` hvis Xcode laget dem. Behold `Assets.xcassets` og `Info.plist`.

3. **Sjekk at våre filer er med.** Disse seks skal ha target membership **DashDash18Widgets** (File inspector → Target Membership): `DashDash18WidgetBundle.swift`, `RoundLiveActivityWidget.swift`, `NextEveningWidget.swift`, `TopThreeWidget.swift`, `SnapshotProvider.swift` og `WidgetPalette.swift`. Ingen av dem skal være med i DashDash18.

4. **Delte filer i begge targets.** Marker `DashDash18/LiveActivity/RoundActivityAttributes.swift`. Kryss av for **DashDash18Widgets** under Target Membership i File inspector. DashDash18 skal fortsatt være krysset av. Gjør det samme med `DashDash18/WidgetData/WidgetSnapshot.swift`.

5. **Byggeinnstillinger for DashDash18Widgets.** Sett *iOS Deployment Target* til **26.0** og *Swift Language Version* til **Swift 6**. Bundle-id-en skal være `com.dashdash18.app.DashDash18Widgets`, og det foreslår Xcode selv. Koden fungerer både med og uten *Default Actor Isolation = MainActor*.

6. **App Group på begge targets.** Gå til Signing & Capabilities → + Capability → **App Groups**, og legg til `group.com.dashdash18.app`. Gjør det både for **DashDash18** og for **DashDash18Widgets**. Strengen må være lik `AppGroup.identifier` i `WidgetSnapshot.swift`. Xcode oppdaterer entitlements-filene og registrerer gruppa når signeringen er automatisk.

7. **Live Activities i appen.** Velg target **DashDash18** → Build Settings og søk etter «Live Activities». Sett *Supports Live Activities* (`INFOPLIST_KEY_NSSupportsLiveActivities`) til **YES** for både Debug og Release. Den samme nøkkelen kan også legges til under Info-fanen.

8. **Skru på flaggene.**
   - `DashDash18/LiveActivity/RoundActivityController.swift`: `LiveActivityFeature.isEnabled = true`
   - `DashDash18/WidgetData/WidgetSnapshotMapping.swift`: `WidgetFeature.isEnabled = true`

9. **Bygg og prøv.** Kjør skjemaet DashDash18 på simulator eller telefon.
   - **Widgets:** Åpne Kveld og Tavla én gang, så skrives dataene. Legg så til «Neste kveld» og «Tavla topp 3» fra Hjem-skjermen (liten og middels) eller fra låseskjermen.
   - **Live Activity:** Start en runde du spiller i, og lås skjermen. Aktiviteten oppdateres hver gang runden lastes på nytt (føring og realtime). Den avsluttes når runden låses.

## Hvordan det henger sammen

- `RundeModel` kaller `RoundActivityController.shared.sync(game:viewer:)` hver gang runden er bygd på nytt. Kontrolleren starter, oppdaterer eller avslutter aktiviteten. Feil tas stille, så føringen aldri stopper.
- `KveldModel` og `TavlaModel` kaller `WidgetSnapshotPublisher` etter lasting. Den skriver `widget-snapshot.json` i App Group-containeren og ber WidgetKit laste widgetene på nytt, men bare når innholdet faktisk er endret. Mangler containeren, skrives fila til Application Support i stedet.
- Live Activity oppdateres bare lokalt fra appen (`pushType: nil`). Oppdatering med push mens appen er lukket hører til APNs-oppgaven i fase 8.
