import SwiftUI

struct RootView: View {
    let config: AppConfig
    let user: AuthUser
    let membership: Membership
    @State private var selectedTab: AppTab = .hjem
    @Environment(\.clubContext) private var context
    @Environment(ClubModel.self) private var club: ClubModel?
    /// Hjem-feeden (fase 19). Bor her, så bjella teller i alle fanene. Ny når medlemskapene byttes.
    @State private var home: HomeFeedModel?
    @State private var homeKey: String?
    @State private var router = HjemRouter()

    var body: some View {
        TabView(selection: $selectedTab) {
            ForEach(AppTab.tabs(isOrganizer: context?.isOrganizer ?? false)) { tab in
                Tab(tab.title, systemImage: tab.systemImage, value: tab) {
                    NavigationStack {
                        content(for: tab)
                            .navigationTitle(tab.title)
                            .ddNavigationChrome()
                            .toolbar {
                                // Høyst to: miljømerket (ikke prod)
                                // og bjella.
                                if config.environment != .prod {
                                    ToolbarItem(placement: .topBarTrailing) {
                                        EnvironmentBadge(environment: config.environment)
                                            .tint(Color.ddOnDark)
                                    }
                                }
                                if let home {
                                    ToolbarItem(placement: .topBarTrailing) {
                                        // Lys på den grønne linja. Uten egen tint arver bjella
                                        // skoggrønn, som i lys modus gir en svak mint-kapsel.
                                        HjemBell(model: home)
                                            .tint(Color.ddOnDark)
                                    }
                                }
                            }
                    }
                    // Knapper og lenker i innholdet er skoggrønne; gult er bare aktiv fane.
                    .tint(Color.ddForestInk)
                    .environment(\.currentTab, tab)
                    .ddScreenBackground()
                }
            }
        }
        // Aktiv fane i gult (golfee), mørk oker i lys modus så etiketten holder 4,5:1.
        .tint(Color.ddYellowText)
        .environment(\.selectTab) { selectedTab = $0 }
        .environment(\.showRound) {
            selectedTab = .hjem
            router.showRound()
        }
        .task(id: memberships.map(\.id)) { makeHome() }
    }

    private var memberships: [Membership] {
        club?.memberships.filter { $0.status == .active } ?? [membership]
    }

    /// Én `HomeFeedModel` per innlogging og sett med medlemskap.
    private func makeHome() {
        guard let context else { home = nil; homeKey = nil; return }
        let key = user.id.uuidString + memberships.map(\.id.uuidString).sorted().joined()
        guard key != homeKey else { return }
        let old = home
        Task { await old?.stopRealtime() }
        home = HomeFeedModel(client: context.client, userID: user.id,
                             memberships: memberships.isEmpty ? [membership] : memberships)
        homeKey = key
    }

    @ViewBuilder
    private func content(for tab: AppTab) -> some View {
        switch tab {
        case .hjem: HjemView(home: home, router: router)
        case .spill:
            if let context {
                SpillView(model: SpillModel(client: context.client, userID: user.id))
            }
        case .tavla: TavlaView()
        case .arrangor: AdminHubView()
        case .deg: DegView(config: config, user: user, membership: membership)
        }
    }
}

extension EnvironmentValues {
    /// Bytter fane fra et view inne i en fane.
    @Entry var selectTab: (AppTab) -> Void = { _ in }

    /// Fanen et view ligger i.
    @Entry var currentTab: AppTab? = nil

    /// Åpner runden som går, på Hjem (arrangørsidens «Gå til runden»).
    @Entry var showRound: () -> Void = {}
}

/// Merke i verktøylinjen så det aldri er tvil om at appen ikke kjører mot prod.
struct EnvironmentBadge: View {
    let environment: AppEnvironment

    var body: some View {
        // Gull på grønt, som rundechipen i PWA-ens header.
        DDPill(environment.displayName, tone: .gold)
            .fixedSize()
            .accessibilityLabel("Miljø: \(environment.displayName)")
    }
}

#Preview {
    RootView(config: .preview, user: .preview, membership: .preview)
}

extension AuthUser {
    static let preview = AuthUser(id: UUID(), email: "deg@epost.no")
}

extension Membership {
    static let preview = Membership(
        id: UUID(), clubID: UUID(), displayName: "Thomas", status: .active,
        isOrganizer: true, isTreasurer: false,
        club: ClubInfo(name: "Golfgutu Invitational", joinCode: "A1B2C3D4E5")
    )
}

extension AppConfig {
    static let preview = try! AppConfig(
        plistData: try! PropertyListSerialization.data(
            fromPropertyList: [
                "Environment": "test",
                "SupabaseURL": "https://forhandsvisning.supabase.co",
                "SupabasePublishableKey": "sb_publishable_forhandsvisning",
            ],
            format: .xml,
            options: 0
        ),
        expecting: .test
    )
}
