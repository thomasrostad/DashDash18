import SwiftUI

/// Plassholder. Erstattes av funksjonen i fase 3.
struct TerminlisteAdminView: View {
    var body: some View {
        ContentUnavailableView("Terminliste", systemImage: "calendar", description: Text("Kveldene i sesongen kommer her."))
            .navigationTitle("Terminliste")
    }
}
