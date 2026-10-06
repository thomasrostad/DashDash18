import SwiftUI

/// Plassholder. Erstattes av funksjonen i fase 3.
struct TroppAdminView: View {
    var body: some View {
        ContentUnavailableView("Troppen", systemImage: "person.3", description: Text("Spillerne i klubben kommer her."))
            .navigationTitle("Troppen")
    }
}
