import SwiftUI

/// Første gang etter innlogging: lag en klubb eller bli med i en.
struct ClubOnboardingView: View {
    let user: AuthUser

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        JoinClubView(user: user)
                    } label: {
                        Label("Bli med i en klubb", systemImage: "person.badge.plus")
                    }
                } footer: {
                    Text("Du trenger invitasjonskoden fra arrangøren.")
                }
                Section {
                    NavigationLink {
                        CreateClubView(user: user)
                    } label: {
                        Label("Lag en ny klubb", systemImage: "flag")
                    }
                } footer: {
                    Text("Du blir arrangør og får en kode du kan dele med resten av gjengen.")
                }
            }
            .navigationTitle("Velkommen")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    SignOutButton()
                }
            }
        }
    }
}

/// Venter på at arrangøren godkjenner en ny spiller.
struct PendingMembershipView: View {
    let membership: Membership
    let user: AuthUser
    @Environment(ClubModel.self) private var club

    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label("Venter på godkjenning", systemImage: "hourglass")
            } description: {
                Text("Du har bedt om å bli med i \(membership.club.name) som \(membership.displayName). Arrangøren må godkjenne deg før du ser noe.")
            } actions: {
                Button("Sjekk igjen") {
                    Task { await club.load(userID: user.id) }
                }
                .buttonStyle(.borderedProminent)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    SignOutButton()
                }
            }
        }
    }
}

struct SignOutButton: View {
    @Environment(AuthModel.self) private var auth

    var body: some View {
        Button("Logg ut") {
            Task { await auth.signOut() }
        }
    }
}
