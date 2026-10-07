import SwiftUI

/// Velger mellom oppstart, innlogging, klubbvalg og selve appen. Ingenting hentes før du er
/// logget inn, fordi databasen avviser alt fra uinnloggede (skjema v1).
struct AppRoot: View {
    let services: AppServices
    @Environment(\.scenePhase) private var scenePhase
    /// Invitasjon fra en lenke: en løs runde (`dashdash://runde/KODE`, fase 13) eller en privat
    /// konkurranse (`dashdash://konkurranse/KODE`, fase 15). Venter til du er logget inn.
    @State private var pendingLink: AppLink?
    /// Kjøp i appen (fase 17). Lages per innlogging når `PurchaseFeature` er på; ellers nil.
    @State private var purchases: PurchaseService?

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
                    .id(user.id)
                    .task(id: user.id) { await services.club.load(userID: user.id) }
                    .task(id: user.id) { services.outbox.start(userID: user.id) }
                    .task(id: user.id) { await services.push.start(userID: user.id) }
                    .task(id: user.id) { startPurchases(userID: user.id) }
            }
        }
        .environment(services.auth)
        .environment(services.club)
        .environment(services.outbox.status)
        .environment(services.push)
        .environment(purchases)
        .onOpenURL { url in
            guard let link = AppLink.parse(url, rounds: LooseRoundsFeature.isEnabled,
                                           competitions: CompetitionsFeature.isActive) else { return }
            pendingLink = link
        }
        .sheet(item: Binding(get: { signedInUser == nil ? nil : pendingLink }, set: { pendingLink = $0 })) { link in
            if let user = signedInUser {
                switch link {
                case .round(let code):
                    JoinFromLinkView(client: services.client, userID: user.id, code: code)
                        .environment(services.outbox.status)
                        .environment(\.scoreSubmitter, services.scoreSubmitter)
                case .competition(let code):
                    JoinCompetitionFromLinkView(client: services.client, code: code)
                }
            }
        }
        .task { await services.auth.observe() }
        .onChange(of: services.auth.state) { _, state in
            if state == .signedOut {
                services.club.reset()
                services.outbox.stop()
                services.push.stop()
                purchases?.stop()
                purchases = nil
                SignedOutCleanup.run()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // Send hull i kø når appen blir aktiv (bare innlogget, ellers avviser serveren),
            // og hent medlemskapet på nytt, så ny rolle eller godkjenning slår inn uten omstart.
            if phase == .active, case .signedIn(let user) = services.auth.state {
                Task { await services.outbox.flush() }
                Task { await services.club.refresh(userID: user.id) }
            }
        }
    }
}

extension AppRoot {
    /// Lytter på transaksjoner fra App Store (også dem som ikke ble fullført sist) og henter kjøpene.
    private func startPurchases(userID: UUID) {
        guard PurchaseFeature.isEnabled else { return }
        purchases?.stop()
        let service = PurchaseService(client: services.client, profileID: userID)
        purchases = service
        service.start()
        Task { await service.refreshEntitlements() }
    }

    private var signedInUser: AuthUser? {
        if case .signedIn(let user) = services.auth.state { return user }
        return nil
    }
}

/// Etter innlogging: har du en aktiv klubb, får du appen. Ellers klubbvalg eller venting.
/// Med `OpenAppFeature` kan du også spille uten klubb (`OpenAppGate`).
struct ClubGate: View {
    let services: AppServices
    let user: AuthUser
    @Environment(ClubModel.self) private var club
    @State private var choice: AppHomeChoice?
    private let choices = AppHomeChoiceStore()

    init(services: AppServices, user: AuthUser) {
        self.services = services
        self.user = user
        _choice = State(initialValue: AppHomeChoiceStore().load(userID: user.id))
    }

    var body: some View {
        switch OpenAppGate.home(club: club.state, choice: choice) {
        case .loading:
            ProgressView("Henter klubben din …")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ddScreenBackground()
        case .chooser:
            OnboardingChoiceView { choose($0) }
        case .clubOnboarding:
            ClubOnboardingView(user: user, onPlayWithoutClub: OpenAppFeature.isEnabled ? { choose(.friends) } : nil)
        case .friends:
            FriendsRootView(config: services.config, client: services.client, user: user)
                .environment(\.scoreSubmitter, services.scoreSubmitter)
        case .pending(let membership):
            PendingMembershipView(membership: membership, user: user,
                                  onPlayWithoutClub: OpenAppFeature.isEnabled ? { choose(.friends) } : nil)
        case .club(let membership):
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

    /// Lagrer valget på telefonen og godtar vilkårene på serveren (019, når moderering er på).
    private func choose(_ next: AppHomeChoice) {
        choices.save(next, userID: user.id)
        choice = next
        if ModerationFeature.isEnabled {
            let service = ModerationService(client: services.client)
            Task { try? await service.acceptTerms() }
        }
    }
}
