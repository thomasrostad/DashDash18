import SwiftUI

/// Velger mellom oppstart, innlogging, klubbvalg og selve appen. Ingenting hentes før du er
/// logget inn, fordi databasen avviser alt fra uinnloggede (skjema v1).
struct AppRoot: View {
    let services: AppServices
    @Environment(\.scenePhase) private var scenePhase
    /// Invitasjon fra en lenke: en løs runde (`dashdash://runde/KODE`, fase 13) eller en privat
    /// konkurranse (`dashdash://konkurranse/KODE`, fase 15). Venter til du er logget inn, og huskes
    /// på telefonen til den er brukt (`PendingLinkStore`), også om iOS lukker appen imens.
    @State private var pendingLink: AppLink? = PendingLinkStore.appLinks.load().flatMap {
        AppLink.parse($0, rounds: LooseRoundsFeature.isEnabled, competitions: CompetitionsFeature.isActive)
    }
    /// Kjøp i appen (fase 17). Lages per innlogging når `PurchaseFeature` er på; ellers nil.
    @State private var purchases: PurchaseService?
    /// Invitasjon til en klubb (`dashdash://klubb/KODE`). Huskes på telefonen gjennom innloggingen,
    /// og vises når klubbene er hentet (`ClubInviteFlow`).
    @State private var pendingClubInvite: ClubInvite? = PendingClubInviteStore().load()
    @State private var presentedClubInvite: PresentedClubInvite?
    /// Følgelenken (`dashdash18.com/folg/KODE`, sql/054). Venter til du er logget inn, og huskes som `pendingLink`.
    @State private var pendingFollow: FollowLink? = PendingLinkStore.follows.load().flatMap(FollowLink.init(url:))

    var body: some View {
        Group {
            switch services.auth.state {
            case .starting:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ddScreenBackground()
            case .signedOut:
                LoginView(hasClubInvite: pendingClubInvite != nil, hasCompetitionInvite: pendingCompetitionInvite)
            case .signedIn(let user):
                // «Oppdater Atten» når bygget er eldre enn app_config.min_ios_build (sql/031).
                MinimumBuildGate(client: services.client) {
                    ClubGate(services: services, user: user)
                }
                .id(user.id)
                // Tabellreglene på runden (sql/047): finnes kolonnene? Svaret huskes til neste oppstart.
                .task(id: user.id) { await RoundRulesFeature.detect(client: services.client) }
                // Formene fra steg 7 (sql/048): finnes konkurransene, sidene og øyeblikksbildet?
                .task(id: user.id) { await RoundFormatsFeature.detect(client: services.client) }
                // Låst kort etter levering (sql/057): finnes kolonnen og funksjonene?
                .task(id: user.id) { await CardLockFeature.detect(client: services.client) }
                // Følge andre spillere (sql/054): finnes funksjonene?
                .task(id: user.id) { await FollowFeature.detect(client: services.client) }
                .task(id: user.id) { await services.club.load(userID: user.id) }
                .task(id: user.id) { services.outbox.start(userID: user.id) }
                .task(id: user.id) { await services.push.start(userID: user.id) }
                .task(id: user.id) { await services.diagnostics.start(userID: user.id) }
                .task(id: user.id) { startPurchases(userID: user.id) }
            }
        }
        .environment(services.auth)
        .environment(services.club)
        .environment(services.outbox.status)
        .environment(services.push)
        .environment(purchases)
        .onOpenURL { url in open(url) }
        // Universelle lenker (`https://dashdash18.com/…`) går samme vei som `dashdash://`.
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
            if let url = activity.webpageURL { open(url) }
        }
        .sheet(item: Binding(get: { signedInUser == nil ? nil : pendingLink }, set: { setPendingLink($0) })) { link in
            if let user = signedInUser {
                switch link {
                case .round(let code):
                    JoinFromLinkView(client: services.client, userID: user.id, code: code)
                        .environment(services.outbox.status)
                        .environment(\.scoreSubmitter, services.scoreSubmitter)
                case .competition(let code):
                    JoinCompetitionFromLinkView(client: services.client, code: code, userID: user.id,
                                                memberships: services.club.memberships.map {
                                                    .init(clubID: $0.clubID, memberID: $0.id, isOrganizer: $0.isOrganizer,
                                                          isActive: $0.status == .active)
                                                })
                    // «Før runden» for et medlem: lukk arket og før på Hjem (`RootView`).
                    .environment(\.showRound) { roundID in
                        setPendingLink(nil)
                        NotificationCenter.default.post(name: RoundRequests.show, object: roundID)
                    }
                }
            }
        }
        .sheet(item: Binding(get: { signedInUser == nil ? nil : pendingFollow }, set: { setPendingFollow($0) })) { link in
            FollowFromLinkView(client: services.client, link: link)
        }
        .onChange(of: clubInviteStep, initial: true) { _, step in presentClubInvite(step) }
        .sheet(item: $presentedClubInvite) { presented in
            if let user = signedInUser {
                ClubInviteSheet(presented: presented, user: user) { presentedClubInvite = nil }
                    .environment(services.club)
            }
        }
        .task { await services.auth.observe() }
        .onChange(of: services.auth.state) { _, state in
            if state == .signedOut {
                services.club.reset()
                services.outbox.stop()
                services.push.stop()
                services.diagnostics.stop()
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
                Task { await services.diagnostics.flush() }
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

    /// En invitasjonslenke: `dashdash://…`, eller `https://dashdash18.com/…` når universelle lenker er på.
    private func open(_ url: URL) {
        if UniversalLink.appURL(url) != nil, !UniversalLinksFeature.isEnabled { return }
        if let invite = ClubInvite(url: url) {
            PendingClubInviteStore().save(invite)
            pendingClubInvite = invite
            return
        }
        if let follow = FollowLink(url: url) {
            PendingLinkStore.follows.save(url)
            pendingFollow = follow
            return
        }
        guard let link = AppLink.parse(url, rounds: LooseRoundsFeature.isEnabled,
                                       competitions: CompetitionsFeature.isActive) else { return }
        PendingLinkStore.appLinks.save(url)
        pendingLink = link
    }

    /// Arket er lukket (lenken er brukt): glem den på telefonen også.
    private func setPendingLink(_ link: AppLink?) {
        if link == nil { PendingLinkStore.appLinks.clear() }
        pendingLink = link
    }

    private func setPendingFollow(_ link: FollowLink?) {
        if link == nil { PendingLinkStore.follows.clear() }
        pendingFollow = link
    }

    /// Hva som skal skje med invitasjonen nå. nil: ingen invitasjon venter.
    private var clubInviteStep: ClubInviteFlow.Step? {
        pendingClubInvite.map {
            ClubInviteFlow.step(isSignedIn: signedInUser != nil, club: services.club.state,
                                memberships: services.club.memberships, invite: $0)
        }
    }

    /// Når innloggingen og klubbene er klare: vis invitasjonen én gang, og glem den på telefonen.
    private func presentClubInvite(_ step: ClubInviteFlow.Step?) {
        guard let step, let invite = pendingClubInvite else { return }
        switch step {
        case .waitForSignIn, .waitForClubs:
            return
        case .join, .confirmJoin, .alreadyMember:
            PendingClubInviteStore().clear()
            pendingClubInvite = nil
            presentedClubInvite = PresentedClubInvite(invite: invite, step: step)
        }
    }

    /// En turneringslenke venter på innloggingen (stripa på innloggingen, sql/060).
    private var pendingCompetitionInvite: Bool {
        if case .competition = pendingLink { return true }
        return false
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
        let home = OpenAppGate.home(club: club.state, choice: choice)
        content(home)
            // sql/060: deltaker i en klubbturnering uten å ha valgt: vennemodus, så turneringen vises.
            .task(id: home == .chooser) {
                guard home == .chooser,
                      let rows = try? await ParticipationQueries.mine(client: services.client, userID: user.id) else { return }
                chooseAutomatically(hasParticipations: !rows.isEmpty)
            }
            .onReceive(NotificationCenter.default.publisher(for: CompetitionJoinEvents.joined)) { _ in
                chooseAutomatically(hasParticipations: false, joinedByLink: true)
            }
    }

    @ViewBuilder
    private func content(_ home: AppHome) -> some View {
        switch home {
        case .loading:
            VStack(spacing: DDSpacing.l) {
                ProgressView("Henter klubben din …")
                if club.isWaitingForNetwork {
                    Text("Dårlig dekning. Prøver igjen …")
                        .font(.ddCallout)
                        .foregroundStyle(Color.ddInkSecondary)
                    SignOutButton()
                }
            }
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
                .environment(\.clubContext, ClubContext(client: services.client, user: user, membership: membership,
                                                      roleAccess: club.roleAccess[membership.clubID]))
                .environment(\.scoreSubmitter, services.scoreSubmitter)
        case .failed(let error):
            ContentUnavailableView {
                Label("Fikk ikke hentet klubben", systemImage: "wifi.exclamationmark")
            } description: {
                Text(error.message)
            } actions: {
                Button {
                    Task { await club.refresh(userID: user.id) }
                } label: {
                    HStack(spacing: DDSpacing.s) {
                        Text("Prøv igjen")
                        if club.isRefreshing { ProgressView() }
                    }
                }
                .buttonStyle(.dd(.primary))
                .disabled(club.isRefreshing)
                SignOutButton()
            }
            .ddScreenBackground()
            .task { await club.reloadWhenOnline(userID: user.id) }
        }
    }

    private func chooseAutomatically(hasParticipations: Bool, joinedByLink: Bool = false) {
        if let next = OpenAppGate.automaticChoice(club: club.state, choice: choice, hasParticipations: hasParticipations,
                                                  joinedByLink: joinedByLink) {
            choose(next)
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
