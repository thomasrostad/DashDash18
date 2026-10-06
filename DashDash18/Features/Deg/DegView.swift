import SwiftUI

struct DegView: View {
    let config: AppConfig
    let user: AuthUser
    let membership: Membership
    @Environment(AuthModel.self) private var auth
    @Environment(ClubModel.self) private var club

    var body: some View {
        List {
            Section("Klubb") {
                LabeledContent("Klubb", value: membership.club.name)
                LabeledContent("Navn i troppen", value: membership.displayName)
                LabeledContent("Rolle", value: membership.roleText)
                if membership.isOrganizer, let code = membership.club.joinCode {
                    LabeledContent("Invitasjonskode") {
                        Text(code).font(.body.monospaced()).textSelection(.enabled)
                    }
                    ShareLink(
                        "Del invitasjonen",
                        item: "Bli med i \(membership.club.name) i DashDash18. Invitasjonskode: \(code)"
                    )
                }
                if otherActiveClubs.count > 0 {
                    Menu("Bytt klubb") {
                        ForEach(otherActiveClubs) { other in
                            Button(other.club.name) { club.select(other) }
                        }
                    }
                }
            }
            if membership.isOrganizer {
                Section {
                    NavigationLink { AdminHubView() } label: {
                        Label("Arrangørsiden", systemImage: "slider.horizontal.3")
                    }
                }
            }
            Section("Konto") {
                LabeledContent("Logget inn som", value: user.email ?? "ukjent e-post")
                Button("Logg ut", role: .destructive) {
                    Task { await auth.signOut() }
                }
            }
            Section("Om appen") {
                LabeledContent("Miljø", value: config.environment.displayName)
                LabeledContent("Database", value: config.projectRef)
            }
        }
    }

    private var otherActiveClubs: [Membership] {
        club.memberships.filter { $0.status == .active && $0.clubID != membership.clubID }
    }
}
