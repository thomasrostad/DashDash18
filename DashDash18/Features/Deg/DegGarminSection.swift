import SwiftUI

/// «Garmin-klokke» under Deg: klokkene Atten snakker med, og knappen som velger dem i Garmin Connect.
/// Føringen på klokka skjer i Atten-appen på Garmin (docs/plan-garmin.md).
struct DegGarminSection: View {
    private var link: GarminLink { .shared }

    var body: some View {
        Section {
            ForEach(link.watches) { watch in
                LabeledContent(watch.name, value: watch.isConnected ? "Tilkoblet" : "Ikke tilkoblet")
            }
            Button(link.watches.isEmpty ? "Koble til Garmin-klokke" : "Velg klokker på nytt") {
                link.chooseWatches()
            }
        } header: {
            DDHeader("Garmin-klokke")
        } footer: {
            DDFooter("Garmin Connect åpnes, og du velger klokkene Atten kan snakke med. Før hullet i Atten-appen på klokka, så havner slagene her.")
        }
    }
}
