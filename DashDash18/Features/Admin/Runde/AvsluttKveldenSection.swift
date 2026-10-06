import GolfgutuCore
import SwiftUI

/// «Avslutt kvelden …» i rundelisten: spør om avkorting når noen mangler hull, og låser
/// alle pågående runder på kvelden.
struct AvsluttKveldenSection: View {
    @Environment(\.clubContext) private var context
    /// Kveldens runder.
    let rounds: [RoundRow]
    let title: (RoundRow) -> String
    /// Etter låsing: meldingen som skal vises. Lista lastes på nytt av den som kaller.
    var onDone: (String) async -> Void

    @State private var pending: Pending?
    @State private var cutting: RoundRow?
    @State private var isBusy = false
    @State private var error: String?

    private struct Pending: Identifiable {
        let id = UUID()
        let prompt: EveningClosePrompt
        let roundIDs: [UUID]
    }

    private var active: [RoundRow] { rounds.filter { $0.status == .active } }

    var body: some View {
        if !active.isEmpty {
            Section {
                Button {
                    ask()
                } label: {
                    HStack {
                        Label("Avslutt kvelden …", systemImage: "flag.checkered")
                        if isBusy { Spacer(); ProgressView() }
                    }
                }
                .disabled(isBusy || context == nil)
            } footer: {
                Text("Låser \(active.count == 1 ? "runden som går" : "rundene som går"). Mangler noen hull, får du spørsmål om å avkorte først.")
            }
            .confirmationDialog(pending?.prompt.title ?? "", isPresented: Binding(
                get: { pending != nil }, set: { if !$0 { pending = nil } }
            ), titleVisibility: .visible, presenting: pending) { item in
                Button("Avslutt kvelden", role: .destructive) { close(item.roundIDs) }
                if let cutID = item.prompt.suggestCut, let round = rounds.first(where: { $0.id == cutID }) {
                    Button("Avkort runden først") { cutting = round }
                }
            } message: { item in
                Text(item.prompt.lines.joined(separator: "\n"))
            }
            .sheet(item: $cutting) { round in
                NavigationStack {
                    AvkortSheet(round: round, title: title(round)) { _ in }
                }
            }
            .alert("Det gikk ikke", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(error ?? "")
            }
        }
    }

    private func ask() {
        guard let context else { return }
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                let games = try await EveningCloser.games(context: context, rounds: active)
                let checks = games.map { game in
                    EveningClose.check(game, title: rounds.first { $0.id == game.roundID }.map(title) ?? "Runden")
                }
                if let prompt = EveningClose.prompt(checks) {
                    pending = Pending(prompt: prompt, roundIDs: games.map(\.roundID))
                }
            } catch {
                self.error = DataError.from(error).message
            }
        }
    }

    private func close(_ ids: [UUID]) {
        guard let context else { return }
        isBusy = true
        Task {
            defer { isBusy = false }
            let locked = await EveningCloser.lock(context: context, roundIDs: ids)
            let names = { (filter: (RoundRow) -> Bool) in rounds.filter(filter).map(title) }
            let text = EveningClose.summary(
                locked: names { locked.contains($0.id) },
                drafts: names { $0.status == .draft },
                failed: names { ids.contains($0.id) && !locked.contains($0.id) }
            )
            await onDone(text)
        }
    }
}
