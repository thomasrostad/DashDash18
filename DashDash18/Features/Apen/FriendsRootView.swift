import Supabase
import SwiftUI

/// Appen uten klubb (`OpenAppFeature`): Spill og Deg. Klubben kan du bli med i fra Deg; da
/// bytter appen til klubbappen av seg selv (ClubGate).
struct FriendsRootView: View {
    let config: AppConfig
    let client: SupabaseClient?
    let user: AuthUser
    @State private var selectedTab: AppTab = .spill
    /// Rundene som pågår, for baren over fanelinja (utbedringsplanen V1).
    @State private var liveRounds: LiveRoundsModel
    /// Runden baren (eller en push) åpnet, i Spill-fanen.
    @State private var openRound: FriendsRound?
    @Environment(\.scenePhase) private var scenePhase

    init(config: AppConfig, client: SupabaseClient?, user: AuthUser) {
        self.config = config
        self.client = client
        self.user = user
        _liveRounds = State(initialValue: LiveRoundsModel(client: client, userID: user.id))
    }

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
                                            .tint(Color.ddForestInk)
                                    }
                                }
                            }
                            .navigationDestination(item: roundBinding(for: tab)) { round in
                                if let client {
                                    roundScreen(round, client: client)
                                        .toolbar(.hidden, for: .tabBar)
                                        // Avsluttet runde: ut av baren med en gang, ikke etter neste henting.
                                        .onDisappear { Task { await liveRounds.load() } }
                                }
                            }
                    }
                    .tint(Color.ddForestInk)
                    .ddScreenBackground()
                }
            }
        }
        .hjemLiveAccessory(liveRounds.live) { live in
            if live.isLoose {
                selectedTab = .spill
                openRound = .loose(live.roundID)
            } else if let round = liveRounds.participantRounds[live.roundID] {
                selectedTab = .spill
                openRound = .participant(round)
            }
        }
        .tint(Color.ddForestInk)
        .environment(\.selectTab) { selectedTab = $0 }
        // Hentes jevnlig mens appen står framme, så en runde startet i Spill dukker opp i baren.
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                await liveRounds.load()
                try? await Task.sleep(for: .seconds(60))
            }
        }
        // Trykk på en push om en løs runde: åpnes i Spill. En klubbrunde åpnes når du er deltaker i
        // klubben (sql/059). Resten gjelder klubben og venter på den.
        .onChange(of: PushTapInbox.shared.pending, initial: true) { _, pending in
            switch pending?.destination {
            case .looseRound(let id):
                guard PushTapInbox.shared.take() != nil else { return }
                selectedTab = .spill
                openRound = .loose(id)
            case .clubRound(let id):
                Task { await openParticipantRound(id) }
            default:
                break
            }
        }
        .onChange(of: openRound) { _, round in
            if round == nil { Task { await liveRounds.load() } }
        }
    }

    /// Runden fra baren åpnes i Spill-fanen.
    private func roundBinding(for tab: AppTab) -> Binding<FriendsRound?> {
        tab == .spill ? $openRound : .constant(nil)
    }

    @ViewBuilder
    private func roundScreen(_ round: FriendsRound, client: SupabaseClient) -> some View {
        switch round {
        case .loose(let id):
            LooseRoundScreen(context: LooseRoundContext(client: client, userID: user.id, roundID: id))
        case .participant(let round):
            LooseRoundScreen(participant: ParticipantRoundContext(client: client, userID: user.id, round: round))
        }
    }

    /// En push om en klubbrunde: åpnes bare når runden hører til en klubb der du er deltaker. Ellers
    /// blir trykket liggende som før (det gjelder en klubb du ikke er med i her).
    private func openParticipantRound(_ roundID: UUID) async {
        guard let client,
              let round = await ParticipationQueries.participantRound(client: client, userID: user.id, roundID: roundID),
              case .clubRound(roundID) = PushTapInbox.shared.pending?.destination,
              PushTapInbox.shared.take() != nil else { return }
        selectedTab = .spill
        openRound = .participant(round)
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
        case .hjem, .tavla, .arrangor:
            EmptyView()
        }
    }
}

/// Runden som åpnes i Spill-fanen uten klubb.
enum FriendsRound: Hashable {
    case loose(UUID)
    /// En klubbrunde du spiller som deltaker i en turnering (sql/059).
    case participant(ParticipantRound)
}

/// Deg uten klubb: profilen (navn, handicap, NGF-nummer), klubb (bli med eller lag), innlogging,
/// personvern og konto.
struct FriendsDegView: View {
    let config: AppConfig
    let client: SupabaseClient?
    let user: AuthUser
    @State private var profile: OwnProfileModel

    init(config: AppConfig, client: SupabaseClient?, user: AuthUser) {
        self.config = config
        self.client = client
        self.user = user
        _profile = State(initialValue: OwnProfileModel(client: client, userID: user.id))
    }

    #if DEBUG
    /// Skjermprøve uten nett.
    init(config: AppConfig, user: AuthUser, preview row: OwnProfileRow) {
        self.config = config
        client = nil
        self.user = user
        _profile = State(initialValue: OwnProfileModel(preview: row))
    }
    #endif

    var body: some View {
        DDList {
            OwnProfileSections(model: profile)
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
                if let version = AppVersion.text() {
                    Text(version)
                }
                // Miljø og database vises bare i test-bygg.
                if config.environment != .prod {
                    LabeledContent("Miljø", value: config.environment.displayName)
                    LabeledContent("Database") {
                        Text(config.projectRef).font(.ddMonoSmall)
                    }
                }
                if SlopeNoFeature.isEnabled {
                    SlopeNoAboutRow()
                }
            }
        }
    }
}
