import SwiftUI

/// Velger mellom oppstart, innlogging, klubbvalg og selve appen. Ingenting hentes før du er
/// logget inn, fordi databasen avviser alt fra uinnloggede (skjema v1).
struct AppRoot: View {
    let services: AppServices
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch services.auth.state {
            case .starting:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ddScreenBackground()
            case .signedOut:
                LoginView()
            case .signedIn(let user):
                ClubGate(services: services, user: user)
                    .task(id: user.id) { await services.club.load(userID: user.id) }
                    .task(id: user.id) { services.outbox.start(userID: user.id) }
                    .task(id: user.id) { await services.push.start(userID: user.id) }
            }
        }
        .environment(services.auth)
        .environment(services.club)
        .environment(services.outbox.status)
        .environment(services.push)
        .task { await services.auth.observe() }
        .onChange(of: services.auth.state) { _, state in
            if state == .signedOut {
                services.club.reset()
                services.outbox.stop()
                services.push.stop()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // Send hull i kø når appen blir aktiv (bare innlogget, ellers avviser serveren).
            if phase == .active, case .signedIn = services.auth.state {
                Task { await services.outbox.flush() }
            }
        }
    }
}

/// Etter innlogging: har du en aktiv klubb, får du appen. Ellers klubbvalg eller venting.
struct ClubGate: View {
    let services: AppServices
    let user: AuthUser
    @Environment(ClubModel.self) private var club

    var body: some View {
        switch club.state {
        case .loading:
            ProgressView("Henter klubben din …")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ddScreenBackground()
        case .noClub:
            ClubOnboardingView(user: user)
        case .pending(let membership):
            PendingMembershipView(membership: membership, user: user)
        case .active(let membership):
            RootView(config: services.config, user: user, membership: membership)
                .environment(\.clubContext, ClubContext(client: services.client, user: user, membership: membership))
                .environment(\.scoreSubmitter, services.scoreSubmitter)
        case .failed(let error):
            ContentUnavailableView {
                Label("Fikk ikke hentet klubben", systemImage: "wifi.exclamationmark")
            } description: {
                Text(error.message)
            } actions: {
                Button("Prøv igjen") {
                    Task { await club.load(userID: user.id) }
                }
                .buttonStyle(.dd(.primary))
                SignOutButton()
            }
            .ddScreenBackground()
        }
    }
}
