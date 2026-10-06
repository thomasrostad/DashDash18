import SwiftUI

/// Viser runde-skjermen når klubben har en runde som går, ellers innholdet under
/// (neste kveld og påmelding).
struct RundeGate<Fallback: View>: View {
    @State private var model: RundeModel
    private let fallback: Fallback

    @Environment(\.scoreSubmitter) private var submitter
    @Environment(\.scenePhase) private var scenePhase

    init(context: ClubContext, @ViewBuilder fallback: () -> Fallback) {
        _model = State(initialValue: RundeModel(context: context))
        self.fallback = fallback()
    }

    var body: some View {
        content
            .task {
                model.submitter = submitter
                await model.load()
            }
            // Hvert 30. sekund mens skjermen er åpen, når realtime ikke dekker det: ingen runde
            // ennå (en som startes, dukker opp), kanalen er nede, eller hull ligger i kø.
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(30))
                    if Task.isCancelled { break }
                    if !model.hasRound || !model.isLive || !model.pendingHoles.isEmpty {
                        await model.load()
                    }
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    Task { await model.load() }
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if model.hasRound {
            RundeView(model: model)
        } else if model.state == .checking {
            ProgressView("Henter kvelden …")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            fallback
        }
    }
}
