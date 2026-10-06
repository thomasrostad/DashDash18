import SwiftUI

struct RootView: View {
    let config: AppConfig
    let user: AuthUser
    @State private var selectedTab: AppTab = .kveld

    var body: some View {
        TabView(selection: $selectedTab) {
            ForEach(AppTab.allCases) { tab in
                Tab(tab.title, systemImage: tab.systemImage, value: tab) {
                    NavigationStack {
                        content(for: tab)
                            .navigationTitle(tab.title)
                            .toolbar {
                                if config.environment != .prod {
                                    ToolbarItem(placement: .topBarTrailing) {
                                        EnvironmentBadge(environment: config.environment)
                                    }
                                }
                            }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func content(for tab: AppTab) -> some View {
        switch tab {
        case .kveld: KveldView()
        case .tavla: TavlaView()
        case .deg: DegView(config: config, user: user)
        }
    }
}

/// Merke i verktøylinjen så det aldri er tvil om at appen ikke kjører mot prod.
struct EnvironmentBadge: View {
    let environment: AppEnvironment

    var body: some View {
        Text(environment.displayName.uppercased())
            .font(.caption.monospaced().bold())
            .foregroundStyle(.orange)
            .accessibilityLabel("Miljø: \(environment.displayName)")
    }
}

#Preview {
    RootView(config: .preview, user: .preview)
}

extension AuthUser {
    static let preview = AuthUser(id: UUID(), email: "deg@epost.no")
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
