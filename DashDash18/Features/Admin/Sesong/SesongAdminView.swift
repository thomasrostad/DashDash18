import GolfgutuCore
import SwiftUI

/// «Sesong og regler». Lander rett på den aktive sesongen (reglene, «Endre reglene», status og handlingene),
/// med «Alle sesonger» og «Ny sesong» nederst. Uten aktiv sesong vises lista over sesongene.
struct SesongAdminView: View {
    @Environment(\.clubContext) private var context

    var body: some View {
        if let context {
            SesongAdminRoot(context: context)
        } else {
            ContentUnavailableView("Ingen klubb", systemImage: "list.number",
                                   description: Text("Velg en klubb for å se sesongene."))
                .navigationTitle("Sesong og regler")
                .ddNavigationChrome()
        }
    }
}

private struct SesongAdminRoot: View {
    @State private var model: SesongAdminModel

    init(context: ClubContext) {
        _model = State(initialValue: SesongAdminModel(context: context))
    }

    var body: some View {
        SesongLandingView(model: model)
    }
}

/// Landingen i «Sesong og regler»: den aktive sesongen, eller lista når ingen er aktiv (`SeasonLifecycle.landing`).
struct SesongLandingView: View {
    let model: SesongAdminModel
    @State private var showsNewSeason = false

    var body: some View {
        content
            .navigationTitle("Sesong og regler")
            .ddNavigationChrome()
            .sheet(isPresented: $showsNewSeason) {
                NavigationStack { NySesongView(model: model) }
            }
            .task { await model.load() }
            .refreshable { await model.load() }
    }

    @ViewBuilder private var content: some View {
        switch model.loadState {
        case .loading where model.seasons.isEmpty:
            ProgressView()
        case .failed(let error) where model.seasons.isEmpty:
            ContentUnavailableView {
                Label("Fikk ikke hentet sesongene", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error.message)
            } actions: {
                Button("Prøv igjen") { Task { await model.load() } }
            }
        default:
            switch SeasonLifecycle.landing(model.seasons) {
            case .season(let id):
                if let season = model.season(id: id) {
                    activeSeason(season)
                }
            case .list:
                if model.seasons.isEmpty {
                    ContentUnavailableView {
                        Label("Ingen sesonger ennå", systemImage: "list.number")
                    } description: {
                        Text("Lag den første sesongen. Golfgutu-oppsettet er en ferdig mal.")
                    } actions: {
                        Button("Ny sesong") { showsNewSeason = true }
                    }
                } else {
                    SeasonList(model: model) { showsNewSeason = true }
                        .toolbar {
                            ToolbarItem(placement: .primaryAction) {
                                Button("Ny sesong", systemImage: "plus") { showsNewSeason = true }
                            }
                        }
                }
            }
        }
    }

    private func activeSeason(_ season: SeasonRow) -> some View {
        SesongContentView(model: model, season: season, showsName: true) {
            Section {
                NavigationLink {
                    AllSeasonsView(model: model)
                } label: {
                    Label("Alle sesonger", systemImage: "list.number")
                }
                Button("Ny sesong", systemImage: "plus") { showsNewSeason = true }
            }
        }
    }
}

/// «Alle sesonger»: aktiv, planlagte og ferdige. Nås fra den aktive sesongen.
private struct AllSeasonsView: View {
    let model: SesongAdminModel
    @State private var showsNewSeason = false

    var body: some View {
        SeasonList(model: model) { showsNewSeason = true }
            .navigationTitle("Alle sesonger")
            .ddNavigationChrome()
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Ny sesong", systemImage: "plus") { showsNewSeason = true }
                }
            }
            .sheet(isPresented: $showsNewSeason) {
                NavigationStack { NySesongView(model: model) }
            }
            .refreshable { await model.load() }
    }
}

/// Sesongene gruppert etter status. Uten aktiv sesong står en oppfordring øverst.
private struct SeasonList: View {
    let model: SesongAdminModel
    let newSeason: () -> Void

    var body: some View {
        DDList {
            if let prompt = SeasonLifecycle.listPrompt(model.seasons) {
                Section {
                    Text(prompt)
                    Button("Ny sesong", systemImage: "plus", action: newSeason)
                }
            }
            ForEach(SeasonLifecycle.grouped(model.seasons), id: \.status) { group in
                Section(SeasonLifecycle.title(group.status)) {
                    ForEach(group.seasons) { season in
                        NavigationLink {
                            SesongDetailView(model: model, seasonID: season.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(season.name)
                                Text(RulesetSummary.short(for: season.rules))
                                    .font(.dd(.sans, size: 13, relativeTo: .footnote))
                                    .foregroundStyle(Color.ddInkSecondary)
                                Text(RulesetSummary.badge(for: season.rules))
                                    .font(.dd(.sans, size: 13, relativeTo: .footnote))
                                    .foregroundStyle(RulesetSummary.isTemplate(season.rules) ? Color.ddForestInk : Color.ddInkSecondary)
                            }
                        }
                    }
                }
            }
        }
    }
}
