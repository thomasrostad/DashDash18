import SwiftUI

/// Plassholder. Erstattes av runde-oppsettet i fase 4.
struct RundeAdminView: View {
    var body: some View {
        ContentUnavailableView("Runder", systemImage: "flag.2.crossed", description: Text("Oppsett av kveldens runder kommer her."))
            .navigationTitle("Runder")
    }
}
