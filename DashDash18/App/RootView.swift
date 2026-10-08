import SwiftUI

struct RootView: View {
    let config: AppConfig
    let user: AuthUser
    let membership: Membership
    @State private var selectedTab: AppTab = .kveld
    @Environment(\.clubContext) private var context
    /// Uleste til bjella, én per klubb (byttes når klubben byttes).
    @State private var badge: UnreadBadge?
    @State private var badgeClubID: UUID?

    var body: some View {
        TabView(selection: $selectedTab) {
            ForEach(AppTab.tabs()) { tab in
                Tab(tab.title, systemImage: tab.systemImage, value: tab) {
                    NavigationStack {
                        content(for: tab)
                            .navigationTitle(tab.title)
                            .ddNavigationChrome()
                            .toolbar {
                                if config.environment != .prod {
                                    ToolbarItem(placement: .topBarTrailing) {
                                        EnvironmentBadge(environment: config.environment)
                                            .tint(Color.ddOnDark)
                                    }
                                }
                                if let badge {
                                    ToolbarItem(placement: .topBarTrailing) {
                                        // Lys på den grønne linja. Uten egen tint arver bjella
                                        // skoggrønn, som i lys modus gir en svak mint-kapsel.
                                        VarslerBell(badge: badge)
                                            .tint(Color.ddOnDark)
                                    }
                                }
                            }
                    }
                    // Knapper og lenker i innholdet er skoggrønne; rust er bare aktiv fane.
                    .tint(Color.ddForestInk)
                    .environment(\.currentTab, tab)
                    .ddScreenBackground()
                }
            }
        }
        // Aktiv fane i gult (golfee), mørk oker i lys modus så etiketten holder 4,5:1.
        .tint(Color.ddYellowText)
        .environment(\.selectTab) { selectedTab = $0 }
        .task(id: context?.clubID) { makeBadge() }
    }

    /// Én `UnreadBadge` per klubbkontekst: samme klubb beholder den, en ny klubb får en ny.
    private func makeBadge() {
        guard let context else { badge = nil; badgeClubID = nil; return }
        guard badgeClubID != context.clubID else { return }
        badge = UnreadBadge(context: context)
        badgeClubID = context.clubID
    }

    @ViewBuilder
    private func content(for tab: AppTab) -> some View {
        switch tab {
        case .kveld: KveldView()
        case .spill:
            if let context {
                SpillView(model: SpillModel(client: context.client, userID: user.id))
            }
        case .tavla: TavlaView()
        case .deg: DegView(config: config, user: user, membership: membership)
        }
    }
}

extension EnvironmentValues {
    /// Bytter fane fra et view inne i en fane (arrangørsidens «Gå til runden»).
    @Entry var selectTab: (AppTab) -> Void = { _ in }

    /// Fanen et view ligger i. Arrangørsiden åpnet fra Kveld går tilbake i stedet for å bytte fane.
    @Entry var currentTab: AppTab? = nil
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
