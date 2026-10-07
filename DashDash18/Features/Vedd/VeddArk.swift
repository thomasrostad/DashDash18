import GolfgutuCore
import SwiftUI

/// Vedd-arket (`renderUtfordringArk`): malene fra regelmotoren (hull-duell, par, slår, fritekst),
/// egen påstand, side og beløp, og én knapp som sier hva som skjer.
struct VeddArk: View {
    let model: BetsModel
    @State var draft: BetSheetDraft
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            DDForm {
                Section {
                    ForEach(Array(draft.options.enumerated()), id: \.offset) { index, option in
                        Button(option.text) { draft.select(index) }
                            .buttonStyle(DDChoiceButtonStyle(selected: draft.selected == index))
                    }
                    Button("Egen påstand") { draft.select(nil) }
                        .buttonStyle(DDChoiceButtonStyle(selected: draft.selected == nil))
                    if draft.selected == nil {
                        TextField("F.eks. «Per slår under 90 på runde 2»", text: $draft.customText, axis: .vertical)
                            .lineLimit(2...4)
                    }
                } header: {
                    DDHeader("Påstand")
                } footer: {
                    DDFooter(hint)
                }

                Section {
                    HStack(spacing: 8) {
                        ForEach(BetSide.allCases, id: \.self) { s in
                            Button(BetTexts.side(s, against: draft.againstName)) { draft.side = s }
                                .buttonStyle(DDChoiceButtonStyle(selected: draft.side == s, tint: s == .yes ? .lime : .blush))
                        }
                    }
                } header: {
                    DDHeader("Din side")
                }

                Section {
                    HStack(spacing: 8) {
                        ForEach(stakeOptions, id: \.self) { n in
                            Button("\(n)") { draft.points = n }
                                .buttonStyle(DDChoiceButtonStyle(selected: draft.points == n))
                        }
                    }
                } header: {
                    DDHeader("Poeng")
                }

                Section {
                    Button(draft.buttonTitle) { submit() }
                        .buttonStyle(.dd(.money, fullWidth: true))
                        .disabled(problem != nil || model.isSaving)
                    if let text = problem ?? error {
                        Text(text).ddErrorStyle()
                    }
                }
                .listRowBackground(Color.clear)
            }
            .navigationTitle(draft.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Avbryt") { dismiss() }
                }
            }
        }
    }

    private var stakeOptions: [Int] {
        model.board?.rules.bets.stakeOptions ?? Ruleset.golfgutu.bets.stakeOptions
    }

    private var problem: String? {
        model.board.flatMap { draft.problem(board: $0) }
    }

    private var hint: String {
        let ahead = model.board?.rules.bets.lockAheadHoles ?? 1
        let extra = ahead > 1 ? ", og de \(ahead - 1) neste også" : ""
        return "Veddemålet blir åpent for alle. Hullet som spilles nå er stengt\(extra)."
    }

    private func submit() {
        error = nil
        Task {
            do {
                try await model.create(draft)
                dismiss()
            } catch {
                self.error = DataError.from(error).message
            }
        }
    }
}
