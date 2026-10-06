import SwiftUI

/// Plassholder. Erstattes av funksjonen i fase 3.
struct BanerAdminView: View {
    var body: some View {
        ContentUnavailableView("Banene", systemImage: "map", description: Text("Banebiblioteket kommer her."))
            .navigationTitle("Banene")
    }
}
