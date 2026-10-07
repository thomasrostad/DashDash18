import Supabase
import SwiftUI

/// Appen uten klubb (`OpenAppFeature`): Spill og Deg. Klubben kan du bli med i fra Deg; da
/// bytter appen til klubbappen av seg selv (ClubGate).
struct FriendsRootView: View {
    let config: AppConfig
    let client: SupabaseClient?
    let user: AuthUser
    @State private var selectedTab: AppTab = .spill

    var body: some View {
        TabView(selection: $selectedTab) {
            ForEach(AppTab.tabsWithoutClub()) { tab in
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
                            }
                    }
                    .tint(Color.ddForestInk)
                    .ddScreenBackground()
                }
            }
        }
        .tint(Color.ddYellowText)
        .environment(\.selectTab) { selectedTab = $0 }
    }

    @ViewBuilder
    private func content(for tab: AppTab) -> some View {
        switch tab {
        case .spill:
            if let client {
                SpillView(model: SpillModel(client: client, userID: user.id))
            }
        case .deg:
            FriendsDegView(config: config, client: client, user: user)
        case .kveld, .tavla:
            EmptyView()
        }
    }
}

/// Deg uten klubb: profilen, klubb (bli med eller lag), innlogging, personvern og konto.
struct FriendsDegView: View {
    let config: AppConfig
    let client: SupabaseClient?
    let user: AuthUser
    /// Profilnavnet (fra `ensure_profile`), eller nil til det er hentet.
    @State private var name: String?

    init(config: AppConfig, client: SupabaseClient?, user: AuthUser, name: String? = nil) {
        self.config = config
        self.client = client
        self.user = user
        _name = State(initialValue: name)
    }

    var body: some View {
        DDList {
            Section {
                HStack(spacing: DDSpacing.m) {
                    DDAvatar(name: name ?? "?", size: 52)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name ?? "Ditt navn")
                            .font(.ddName)
                            .foregroundStyle(Color.ddInk)
                        Text("Spiller uten klubb")
                            .font(.ddCallout)
                            .foregroundStyle(Color.ddInkSecondary)
                    }
                }
                .padding(.vertical, 6)
            }
            Section {
                NavigationLink { JoinClubView(user: user) } label: {
                    Label("Bli med i en klubb", systemImage: "person.badge.plus")
                        .labelStyle(DDIconLabelStyle())
                }
                NavigationLink { CreateClubView(user: user) } label: {
                    Label("Lag en ny klubb", systemImage: "flag")
                        .labelStyle(DDIconLabelStyle())
                }
            } header: {
                DDHeader("Klubb")
            } footer: {
                DDFooter("En klubb er en fast gjeng med terminliste, kvelder og en egen tavle. Rundene dine står uansett.")
            }
            DegAccountSection(user: user)
            DegOpenAppSections(client: client, user: user)
            DDSection("Om appen") {
                LabeledContent("Miljø", value: config.environment.displayName)
                LabeledContent("Database") {
                    Text(config.projectRef).font(.ddMonoSmall)
                }
            }
        }
        .task {
            guard name == nil, let client else { return }
            name = (try? await LooseRoundQueries.ensureProfile(client: client))?.displayName
        }
    }
}
