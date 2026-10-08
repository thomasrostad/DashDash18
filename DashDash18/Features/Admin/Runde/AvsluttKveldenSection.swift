import GolfgutuCore
import SwiftUI

/// «Avslutt kvelden …» på Kvelden: spør om avkorting når noen mangler hull, og låser
/// alle pågående runder på kvelden.
struct AvsluttKveldenSection: View {
    /// Kveldens runder.
    let rounds: [RoundRow]
    let title: (RoundRow) -> String
    /// Etter låsing: meldingen som skal vises. Lista lastes på nytt av den som kaller.
    var onDone: (String) async -> Void

    private var active: [RoundRow] { rounds.filter { $0.status == .active } }

    var body: some View {
        if !active.isEmpty {
            Section {
                AvsluttKveldenButton(rounds: rounds, title: title, prominent: false, onDone: onDone)
            } footer: {
                DDFooter("Låser \(active.count == 1 ? "runden som går" : "rundene som går"). Mangler noen hull, får du spørsmål om å avkorte først.")
            }
        }
    }
}

/// Knappen «Avslutt kvelden» med hele flyten: spørsmålet, avkorting og låsing. Som rad på Kvelden,
/// eller som stor hovedknapp på arrangørsiden.
struct AvsluttKveldenButton: View {
    @Environment(\.clubContext) private var context
    let rounds: [RoundRow]
    let title: (RoundRow) -> String
    /// Stor gul hovedknapp i stedet for en rad.
    var prominent = false
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
        button
            .disabled(isBusy || context == nil || active.isEmpty)
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
                    // Avkortet: lista hentes på nytt og meldingen vises, så «Avslutt kvelden» kan trykkes igjen.
                    AvkortSheet(round: round, title: title(round)) { text in Task { await onDone(text) } }
                }
            }
            .messageAlert("Det gikk ikke", text: $error)
    }

    @ViewBuilder
    private var button: some View {
        if prominent {
            Button {
                ask()
            } label: {
                HStack(spacing: 8) {
                    Text("Avslutt kvelden")
                    if isBusy { ProgressView() }
                }
            }
            .buttonStyle(.dd(.primary, fullWidth: true))
        } else {
            Button {
                ask()
            } label: {
                HStack {
                    Label("Avslutt kvelden …", systemImage: "flag.checkered")
                    if isBusy { Spacer(); ProgressView() }
                }
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
