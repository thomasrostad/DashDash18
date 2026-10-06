import GolfgutuCore
import SwiftUI

/// Avkort runden: regel, «etter hull N» og hva det gjør med summene før noe lagres.
struct AvkortSheet: View {
    @Environment(\.clubContext) private var context
    let round: RoundRow
    let title: String
    var onDone: (String) -> Void

    var body: some View {
        if let context {
            AvkortContent(model: RoundReviewModel(context: context, round: round, title: title), onDone: onDone)
        } else {
            ContentUnavailableView("Ingen klubb", systemImage: "flag.2.crossed")
        }
    }
}

private struct AvkortContent: View {
    @State var model: RoundReviewModel
    var onDone: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var choice: CutChoice?
    @State private var confirmCut = false
    @State private var confirmRemove = false
    @State private var error: String?
    @State private var isBusy = false

    var body: some View {
        content
            .navigationTitle("Avkort runden")
            .ddNavigationChrome()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Avbryt") { dismiss() }
                }
            }
            .task {
                await model.load()
                if choice == nil { choice = model.game?.defaultCutChoice }
            }
            .alert("Det gikk ikke", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(error ?? "")
            }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ProgressView("Henter runden …")
        case .failed(let text):
            ContentUnavailableView("Fikk ikke hentet runden", systemImage: "wifi.exclamationmark", description: Text(text))
        case .loaded:
            if let game = model.game, let choice {
                form(game, choice: choice)
            }
        }
    }

    private func form(_ game: RoundGame, choice: CutChoice) -> some View {
        let preview = game.cutPreview(choice)
        return DDForm {
            Section {
                Text("Runden avkortes for alle samtidig. Poengene regnes om med én gang, for hele feltet.")
                    .font(.dd(.sans, size: 13, relativeTo: .footnote))
                    .foregroundStyle(Color.ddInkSecondary)
                if let summary = game.cutSummary {
                    Label(summary + ". Du kan endre valget eller fjerne avkortingen.", systemImage: "scissors")
                        .font(.dd(.sans, size: 13, relativeTo: .footnote))
                }
                if game.status == .locked {
                    Label("Runden er låst og kan ikke avkortes. Enkelthull rettes under Rundene.", systemImage: "lock")
                        .font(.dd(.sans, size: 13, relativeTo: .footnote))
                        .foregroundStyle(Color.ddRustText)
                }
            }

            Section {
                Picker("Uspilte hull", selection: binding(\.rule)) {
                    ForEach(Truncation.Rule.allCases, id: \.self) { rule in
                        Text(rule.name).tag(rule)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                DDHeader("Hva skjer med hullene som ikke ble spilt")
            } footer: {
                DDFooter(choice.rule.help)
            }

            Section {
                Picker("Runden stoppet etter", selection: binding(\.after)) {
                    ForEach(1...game.holeCount, id: \.self) { n in
                        Text(game.cutOptionTitle(n)).tag(n)
                    }
                }
            } footer: {
                DDFooter(game.cutHint(for: choice.rule))
            }

            DDSection("Dette endrer seg") {
                if preview.lines.isEmpty {
                    Text("Ingen poengsummer endrer seg av dette valget.")
                        .foregroundStyle(Color.ddInkSecondary)
                }
                ForEach(preview.lines) { line in
                    HStack {
                        Text(line.name)
                        Spacer()
                        Text("\(line.before) → \(line.after)")
                            .monospacedDigit()
                            .foregroundStyle(Color.ddInkSecondary)
                        Text(CutPreview.signed(line.diff))
                            .monospacedDigit()
                            .frame(minWidth: 36, alignment: .trailing)
                            .foregroundStyle(line.diff < 0 ? Color.ddError : Color.ddForestInk)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(line.text)
                }
            }

            Section {
                Button("Avkort etter \(game.cutOptionTitle(choice.after).lowercased()) · \(choice.rule.name.lowercased())") {
                    confirmCut = true
                }
                .disabled(game.status == .locked || isBusy)
                if game.cutRule != nil {
                    Button("Fjern avkorting", role: .destructive) { confirmRemove = true }
                        .disabled(game.status == .locked || isBusy)
                }
            }
        }
        .disabled(isBusy)
        .confirmationDialog("Avkorte \(model.title) etter hull \(game.holeNumber(choice.after - 1))?",
                            isPresented: $confirmCut, titleVisibility: .visible) {
            Button("Avkort etter hull \(game.holeNumber(choice.after - 1))", role: .destructive) {
                save(choice, done: "Runden er avkortet. Poengene er regnet om.")
            }
        } message: {
            Text(confirmText(choice, preview: preview))
        }
        .confirmationDialog("Fjerne avkortingen av \(model.title)?", isPresented: $confirmRemove,
                            titleVisibility: .visible) {
            Button("Fjern avkorting", role: .destructive) {
                save(nil, done: "Avkortingen er fjernet. Hele runden teller igjen.")
            }
        } message: {
            Text("Hele runden teller igjen, og poengene regnes om.")
        }
    }

    private func confirmText(_ choice: CutChoice, preview: CutPreview) -> String {
        var lines = ["\(choice.rule.name). \(choice.rule.help)"]
        if preview.losers > 0 {
            lines.append(preview.losers == 1 ? "1 spiller mister poeng." : "\(preview.losers) spillere mister poeng.")
        }
        lines.append("Poengene regnes om for hele feltet med én gang.")
        return lines.joined(separator: "\n")
    }

    private func binding<T>(_ key: WritableKeyPath<CutChoice, T>) -> Binding<T> {
        Binding(get: { choice![keyPath: key] }, set: { choice?[keyPath: key] = $0 })
    }

    private func save(_ choice: CutChoice?, done: String) {
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                try await model.saveCut(choice)
                onDone(done)
                dismiss()
            } catch {
                self.error = DataError.from(error).message
            }
        }
    }
}
