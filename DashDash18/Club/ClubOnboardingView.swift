import SwiftUI

/// Første gang etter innlogging: bli med i en klubb (lim inn invitasjonen eller skriv koden) eller lag en.
struct ClubOnboardingView: View {
    let user: AuthUser
    /// «Spill med venner i stedet» (OpenAppFeature). nil = som før.
    var onPlayWithoutClub: (() -> Void)?
    @State private var codeText = ""
    @State private var error: String?
    /// Koden som er funnet: «Bli med» åpnes med den.
    @State private var joining: ClubInvite?

    var body: some View {
        NavigationStack {
            DDList {
                ClubCodeEntrySection(text: $codeText, onSubmit: findClub)
                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Color.ddError)
                    }
                }
                if let onPlayWithoutClub {
                    Section {
                        Button("Spill med venner uten klubb", systemImage: "figure.golf", action: onPlayWithoutClub)
                            .fontWeight(.medium)
                    } footer: {
                        DDFooter("Du kan bli med i en klubb senere, fra Deg.")
                    }
                }
                Section {
                    NavigationLink {
                        CreateClubView(user: user)
                    } label: {
                        Label("Lag en ny klubb", systemImage: "flag")
                    }
                } header: {
                    DDHeader("Starter du en ny gjeng?")
                } footer: {
                    DDFooter("Du blir arrangør og får en invitasjon du kan sende til resten av gjengen.")
                }
            }
            .navigationTitle("Velkommen")
            .ddNavigationChrome()
            .navigationDestination(item: $joining) { invite in
                JoinClubView(user: user, initialCode: invite.code)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    SignOutButton()
                }
            }
        }
    }
}

extension ClubOnboardingView {
    private func findClub() {
        guard let invite = ClubInvite.parse(codeText) else {
            error = ClubInvite.notAnInvite
            return
        }
        error = nil
        codeText = invite.code
        joining = invite
    }
}

/// Venter på at arrangøren godkjenner en ny spiller.
struct PendingMembershipView: View {
    let membership: Membership
    let user: AuthUser
    /// «Spill med venner mens du venter» (OpenAppFeature). nil = som før.
    var onPlayWithoutClub: (() -> Void)?
    @Environment(ClubModel.self) private var club
    @State private var checkResult: String?

    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label("Venter på godkjenning", systemImage: "hourglass")
            } description: {
                Text("Du har bedt om å bli med i \(membership.club.name) som \(membership.displayName). Arrangøren må godkjenne deg før du ser noe.")
            } actions: {
                Button {
                    check()
                } label: {
                    HStack(spacing: DDSpacing.s) {
                        Text("Sjekk igjen")
                        if club.isRefreshing { ProgressView() }
                    }
                }
                .buttonStyle(.dd(.primary))
                .disabled(club.isRefreshing)
                if let checkResult {
                    Text(checkResult)
                        .font(.ddCallout)
                        .foregroundStyle(Color.ddInkSecondary)
                }
                if let onPlayWithoutClub {
                    Button("Spill med venner mens du venter", action: onPlayWithoutClub)
                        .buttonStyle(.dd(.secondary))
                }
            }
            .ddScreenBackground()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    SignOutButton()
                }
            }
        }
    }

    /// Godkjent: appen bytter skjerm av seg selv. Ellers sier vi fra, så knappen ikke virker død.
    private func check() {
        checkResult = nil
        Task {
            let failure = await club.load(userID: user.id)
            checkResult = failure?.message ?? "Ikke godkjent ennå. Du kan lukke appen; den sjekker igjen når du åpner den."
        }
    }
}

/// «Logg ut» med bekreftelse (PWA: `bekreftLoggUt`). Push for telefonen avregistreres før
/// økten forsvinner (`AuthModel.willSignOut`).
struct SignOutButton: View {
    /// Hvordan du kommer inn igjen (`LoginMethods.signOutMessage`).
    var loginHint: String = LoginMethods.signOutMessage(identities: [])
    @Environment(AuthModel.self) private var auth
    @Environment(OutboxStatus.self) private var outbox
    @State private var confirming = false
    @State private var isSigningOut = false

    var body: some View {
        Button("Logg ut …", role: .destructive) {
            confirming = true
        }
        .disabled(isSigningOut)
        .confirmationDialog("Logge ut?", isPresented: $confirming, titleVisibility: .visible) {
            Button(outbox.pendingCount > 0 ? "Logg ut likevel" : "Logg ut", role: .destructive) {
                isSigningOut = true
                Task {
                    await auth.signOut()
                    isSigningOut = false
                }
            }
        } message: {
            Text(SignOutButton.confirmation(pending: outbox.pendingCount, loginHint: loginHint))
        }
    }

    /// Teksten i bekreftelsen: hull som ikke er sendt først, så hvordan du kommer inn igjen.
    nonisolated static func confirmation(pending: Int, loginHint: String) -> String {
        pending > 0 ? warning(pending: pending) + " " + loginHint : loginHint
    }

    /// Hull i kø sendes bare når den samme logger inn igjen (utboksen er knyttet til bruker).
    nonisolated static func warning(pending: Int) -> String {
        let hull = pending == 1 ? "1 hull er" : "\(pending) hull er"
        return "\(hull) ikke sendt ennå. De sendes neste gang du logger inn på denne telefonen."
    }
}
