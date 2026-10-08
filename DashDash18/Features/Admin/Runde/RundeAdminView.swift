import SwiftUI

/// Alle runder: arkivet over klubbens runder, gruppert per kveld, nyeste først, også fra tidligere
/// turneringer. Under «Arkiv» nederst på arrangørsiden. Planleggingslistene (tidslinja og rundene
/// på kvelden) står eldst først; arkivet står nyest først fordi det brukes til å slå opp. Ny runde og «Avslutt kvelden» ligger på kvelden selv (Kvelden),
/// ikke her. Kladder åpner oppsettet, startede og låste runder åpner rundens skjerm.
struct RundeAdminView: View {
    @Environment(\.clubContext) private var context

    var body: some View {
        if let context {
            RundeAdminContent(model: RundeAdminModel(context: context))
        } else {
            ContentUnavailableView("Ingen klubb", systemImage: "flag.2.crossed")
        }
    }
}

#if DEBUG
/// Alle runder med oppdiktede kvelder (`-DDDesignScreen runder`).
struct RundeAdminSample: View {
    @State private var model = RundeAdminModel.sample(.liveEvening)

    var body: some View {
        RundeAdminContent(model: model)
    }
}
#endif

private struct RundeAdminContent: View {
    @State private var model: RundeAdminModel
    @State private var actions: RoundAdminActions

    init(model: RundeAdminModel) {
        _model = State(initialValue: model)
        _actions = State(initialValue: RoundAdminActions(model: model))
    }

    var body: some View {
        content
            .navigationTitle("Alle runder")
            .ddNavigationChrome()
            .task { await model.load() }
            .refreshable { await model.load() }
            .roundAdminActions(actions)
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ProgressView("Henter rundene …")
        case .failed(let text):
            ContentUnavailableView {
                Label("Fikk ikke hentet rundene", systemImage: "wifi.exclamationmark")
            } description: {
                Text(text)
            } actions: {
                Button("Prøv igjen") { Task { await model.load() } }
                    .buttonStyle(.dd(.primary))
            }
        case .loaded:
            if model.allRounds.isEmpty {
                ContentUnavailableView {
                    Label("Ingen runder ennå", systemImage: "flag.2.crossed")
                } description: {
                    Text("Rundene settes opp fra kvelden på arrangørsiden.")
                }
            } else {
                list
            }
        }
    }

    private var list: some View {
        DDList {
            ForEach(model.groups) { group in
                Section {
                    ForEach(group.rounds) { round in
                        RoundAdminRow(round: round, actions: actions)
                    }
                } header: {
                    DDHeader(group.title)
                }
            }
        }
        .disabled(actions.isBusy)
        .overlay { if actions.isBusy { ProgressView() } }
    }
}
