import GolfgutuCore
import SwiftUI

/// Sesongene i klubben: aktiv, planlagte og ferdige. Herfra lages nye sesonger og regelsettet redigeres.
struct SesongAdminView: View {
    @Environment(\.clubContext) private var context

    var body: some View {
        if let context {
            SesongListView(context: context)
        } else {
            ContentUnavailableView("Ingen klubb", systemImage: "list.number",
                                   description: Text("Velg en klubb for å se sesongene."))
                .navigationTitle("Sesong og regler")
                .ddNavigationChrome()
        }
    }
}

private struct SesongListView: View {
    @State private var model: SesongAdminModel
    @State private var showsNewSeason = false

    init(context: ClubContext) {
        _model = State(initialValue: SesongAdminModel(context: context))
    }

    var body: some View {
        content
            .navigationTitle("Sesong og regler")
            .ddNavigationChrome()
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Ny sesong", systemImage: "plus") { showsNewSeason = true }
                }
            }
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
            if model.seasons.isEmpty {
                ContentUnavailableView {
                    Label("Ingen sesonger ennå", systemImage: "list.number")
                } description: {
                    Text("Lag den første sesongen. Golfgutu-oppsettet er en ferdig mal.")
                } actions: {
                    Button("Ny sesong") { showsNewSeason = true }
                }
            } else {
                list
            }
        }
    }

    private var list: some View {
        DDList {
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
                                    .foregroundStyle(RulesetSummary.isGolfgutu(season.rules) ? Color.ddForestInk : Color.ddInkSecondary)
                            }
                        }
                    }
                }
            }
        }
    }
}
