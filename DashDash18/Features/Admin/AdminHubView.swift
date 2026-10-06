import SwiftUI

/// Arrangørsiden: inngangen til alt arrangøren setter opp. Vises bare for arrangører.
struct AdminHubView: View {
    var body: some View {
        List {
            Section("Kvelden") {
                NavigationLink { RundeAdminView() } label: {
                    Label("Runder", systemImage: "flag.2.crossed")
                }
            }
            Section("Sesongen") {
                NavigationLink { SesongAdminView() } label: {
                    Label("Sesong og regler", systemImage: "list.number")
                }
                NavigationLink { TerminlisteAdminView() } label: {
                    Label("Terminliste", systemImage: "calendar")
                }
            }
            Section("Klubben") {
                NavigationLink { TroppAdminView() } label: {
                    Label("Troppen", systemImage: "person.3")
                }
                NavigationLink { BanerAdminView() } label: {
                    Label("Banene", systemImage: "map")
                }
            }
        }
        .navigationTitle("Arrangørsiden")
    }
}
