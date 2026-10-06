import SwiftUI

/// Velger mellom oppstart, innlogging, klubbvalg og selve appen. Ingenting hentes før du er
/// logget inn, fordi databasen avviser alt fra uinnloggede (skjema v1).
struct AppRoot: View {
    let services: AppServices

    var body: some View {
        Group {
            switch services.auth.state {
            case .starting:
                ProgressView()
            case .signedOut:
                LoginView()
            case .signedIn(let user):
                ClubGate(config: services.config, user: user)
                    .task(id: user.id) { await services.club.load(userID: user.id) }
            }
        }
        .environment(services.auth)
        .environment(services.club)
        .task { await services.auth.observe() }
        .onChange(of: services.auth.state) { _, state in
            if state == .signedOut { services.club.reset() }
        }
    }
}

/// Etter innlogging: har du en aktiv klubb, får du appen. Ellers klubbvalg eller venting.
struct ClubGate: View {
    let config: AppConfig
    let user: AuthUser
    @Environment(ClubModel.self) private var club

    var body: some View {
        switch club.state {
        case .loading:
            ProgressView("Henter klubben din …")
        case .noClub:
            ClubOnboardingView(user: user)
        case .pending(let membership):
            PendingMembershipView(membership: membership, user: user)
        case .active(let membership):
            RootView(config: config, user: user, membership: membership)
        case .failed(let error):
            ContentUnavailableView {
                Label("Fikk ikke hentet klubben", systemImage: "wifi.exclamationmark")
            } description: {
                Text(error.message)
            } actions: {
                Button("Prøv igjen") {
                    Task { await club.load(userID: user.id) }
                }
                .buttonStyle(.borderedProminent)
                SignOutButton()
            }
        }
    }
}
