import GolfgutuCore
import SwiftUI

/// «Turneringen» på arrangørsiden. Lander rett på hovedturneringen, den aktive sesongen (reglene,
/// «Endre reglene», status og handlingene), med «Alle turneringer» og «Ny turnering» nederst. Uten
/// aktiv sesong vises alle turneringene.
struct SesongAdminView: View {
    @Environment(\.clubContext) private var context

    var body: some View {
        if let context {
            SesongAdminRoot(context: context)
        } else {
            ContentUnavailableView("Ingen klubb", systemImage: "trophy",
                                   description: Text("Velg en klubb for å se turneringene."))
                .navigationTitle("Turneringen")
                .ddNavigationChrome()
        }
    }
}

private struct SesongAdminRoot: View {
    @State private var model: SesongAdminModel
    @State private var competitions: CompetitionsModel

    init(context: ClubContext) {
        _model = State(initialValue: SesongAdminModel(context: context))
        _competitions = State(initialValue: CompetitionsModel(context: context))
    }

    var body: some View {
        SesongLandingView(model: model, competitions: competitions)
    }
}

/// Landingen i «Turneringen»: den aktive sesongen, eller alle turneringene når ingen er aktiv
/// (`SeasonLifecycle.landing`).
struct SesongLandingView: View {
    let model: SesongAdminModel
    let competitions: CompetitionsModel
    @State private var showsNew = false

    var body: some View {
        content
            .navigationTitle("Turneringen")
            .ddNavigationChrome()
            .newTournamentSheet(isPresented: $showsNew, seasons: model, competitions: competitions)
            .task { await reload() }
            .refreshable { await reload() }
    }

    private func reload() async {
        await model.load()
        if CompetitionsFeature.isActive { await competitions.load() }
    }

    @ViewBuilder private var content: some View {
        switch model.loadState {
        case .loading where model.seasons.isEmpty:
            ProgressView()
        case .failed(let error) where model.seasons.isEmpty:
            ContentUnavailableView {
                Label("Fikk ikke hentet turneringene", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error.message)
            } actions: {
                Button("Prøv igjen") { Task { await reload() } }
            }
        default:
            switch SeasonLifecycle.landing(model.seasons) {
            case .season(let id):
                if let season = model.season(id: id) {
                    activeSeason(season)
                }
            case .list:
                if items.isEmpty {
                    ContentUnavailableView {
                        Label("Ingen turneringer ennå", systemImage: "trophy")
                    } description: {
                        Text("Lag den første. Du velger hvordan dere vil spille.")
                    } actions: {
                        Button("Ny turnering") { showsNew = true }
                            .buttonStyle(.dd(.primary))
                    }
                } else {
                    TournamentListContent(model: model, competitions: competitions) { showsNew = true }
                        .toolbar {
                            ToolbarItem(placement: .primaryAction) {
                                Button("Ny turnering", systemImage: "plus") { showsNew = true }
                            }
                        }
                }
            }
        }
    }

    private var items: [TournamentList.Item] {
        TournamentList.items(seasons: model.seasons, competitions: competitions.overview.competitions,
                             clubID: competitions.clubID ?? UUID())
    }

    private func activeSeason(_ season: SeasonRow) -> some View {
        SesongContentView(model: model, season: season, showsName: true) {
            Section {
                NavigationLink {
                    AlleTurneringerView(model: model, competitions: competitions)
                } label: {
                    Label("Alle turneringer", systemImage: "trophy")
                }
                Button("Ny turnering", systemImage: "plus") { showsNew = true }
            }
        }
    }
}

/// «Alle turneringer»: klubbens sesonger og konkurranser i én liste, gruppert etter status.
struct AlleTurneringerView: View {
    let model: SesongAdminModel
    let competitions: CompetitionsModel
    @State private var showsNew = false

    var body: some View {
        TournamentListContent(model: model, competitions: competitions) { showsNew = true }
            .navigationTitle("Alle turneringer")
            .ddNavigationChrome()
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Ny turnering", systemImage: "plus") { showsNew = true }
                }
            }
            .newTournamentSheet(isPresented: $showsNew, seasons: model, competitions: competitions)
            .refreshable {
                await model.load()
                if CompetitionsFeature.isActive { await competitions.load() }
            }
    }
}

/// Lista: pågår, planlagt, ferdig, med typen under navnet. Uten aktiv sesong står en oppfordring øverst.
private struct TournamentListContent: View {
    let model: SesongAdminModel
    let competitions: CompetitionsModel
    let newTournament: () -> Void

    var body: some View {
        let items = TournamentList.items(seasons: model.seasons, competitions: competitions.overview.competitions,
                                         clubID: competitions.clubID ?? UUID())
        DDList {
            if let prompt = SeasonLifecycle.listPrompt(model.seasons) {
                Section {
                    Text(prompt)
                    Button("Ny turnering", systemImage: "plus", action: newTournament)
                }
            }
            ForEach(TournamentList.grouped(items), id: \.status) { group in
                Section {
                    ForEach(group.items) { item in
                        NavigationLink {
                            destination(item)
                        } label: {
                            row(item)
                        }
                    }
                } header: {
                    DDHeader(group.title)
                }
            }
        }
    }

    @ViewBuilder
    private func destination(_ item: TournamentList.Item) -> some View {
        switch item {
        case .season(let season):
            SesongDetailView(model: model, seasonID: season.id)
        case .competition(let competition):
            CompetitionDetailScreen(list: competitions, competition: competition)
        }
    }

    private func row(_ item: TournamentList.Item) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon(item))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.ddForestInk)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(.ddBodyEmphasis)
                    .foregroundStyle(Color.ddInk)
                Text(item.subtitle)
                    .font(.ddCaption)
                    .foregroundStyle(Color.ddInkSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func icon(_ item: TournamentList.Item) -> String {
        switch item {
        case .season(let s):
            TournamentSetup.icon(s.rules.table.pointsSource == .stableford ? .stablefordSeries : .matchSeries)
        case .competition(let c):
            CompetitionListRow.icon(c.kind)
        }
    }
}

extension View {
    /// «Ny turnering» i et ark. Lister lastes på nytt når arket lukkes. `seasons` regnes først ut når
    /// arket vises (ikke hver gang lista tegnes), og `NyTurneringView` beholder modellen i `@State`.
    func newTournamentSheet(isPresented: Binding<Bool>, seasons: @autoclosure @escaping () -> SesongAdminModel?,
                            competitions: CompetitionsModel, offersPrivate: Bool = false) -> some View {
        sheet(isPresented: isPresented) {
            NavigationStack {
                NyTurneringView(model: NewTournamentModel(list: competitions, seasons: seasons(),
                                                          offersPrivate: offersPrivate)) {
                    isPresented.wrappedValue = false
                }
            }
        }
    }
}
