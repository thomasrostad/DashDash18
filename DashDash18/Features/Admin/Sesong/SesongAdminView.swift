import SwiftUI

/// Plassholder. Erstattes av funksjonen i fase 3.
struct SesongAdminView: View {
    var body: some View {
        ContentUnavailableView("Sesong og regler", systemImage: "list.number", description: Text("Sesongen og regelsettet kommer her."))
            .navigationTitle("Sesong og regler")
    }
}
