import SwiftUI

/// Holder klubbens runde levende mens skjermen er åpen (fase 19: Hjem, før Kveld-fanen):
/// henter ved start, hvert 30. sekund når realtime ikke dekker det, når køen er sendt og når appen
/// blir aktiv. Runde-skjermen selv åpnes fra «Pågår nå».
struct RundeFollow: ViewModifier {
    let model: RundeModel

    @Environment(\.scoreSubmitter) private var submitter
    @Environment(\.scenePhase) private var scenePhase
    @Environment(OutboxStatus.self) private var outbox: OutboxStatus?

    func body(content: Content) -> some View {
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
            // Køen er sendt i bakgrunnen (nettet kom tilbake) mens realtime er nede: hent med en
            // gang, så «ikke lagret ennå» forsvinner og stillingen har tallene, uten 30 sekunder.
            .onChange(of: outbox?.pendingCount) { old, new in
                if let old, let new, new < old, !model.isLive {
                    Task { await model.load() }
                }
            }
            // Et hull fra klokka er lagt i utboksen: vis det, og send klokka runden med hullet.
            .onReceive(NotificationCenter.default.publisher(for: WatchRoundController.received)) { _ in
                Task { await model.load() }
            }
            // Et hull i køen ble avvist (runden ble låst før køen kom fram): stripa i føringen sier fra.
            .onChange(of: outbox?.rejectedCount) { _, _ in
                model.queueChanged()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    Task { await model.load() }
                }
            }
    }
}

extension View {
    /// Følger klubbens runde (`RundeFollow`).
    func followsRound(_ model: RundeModel) -> some View {
        modifier(RundeFollow(model: model))
    }
}
