import GolfgutuCore
import SwiftUI

/// Tippekupongen: mal (Klassisk, Birdiejakt, Full kupong), hvert spørsmål av eller på, og linjene for
/// antall birdier og vinnerens poeng. Linja for snittet settes per kveld på kupongen, som før.
struct RulesetTipsSection: View {
    @Binding var draft: RulesetDraft

    var body: some View {
        Section {
            Picker(selection: templateBinding) {
                ForEach(TipsTemplate.allCases, id: \.self) { Text($0.title).tag(TipsTemplate?.some($0)) }
                if draft.tipsTemplate == nil {
                    Text("Tilpasset").tag(TipsTemplate?.none)
                }
            } label: {
                RuleFieldLabel(title: "Mal", changeNote: draft.tipsQuestionsNote)
            }
            ForEach(TipsQuestion.catalog) { q in
                Toggle(q.title, isOn: Binding(get: { draft.asksTips(q) }, set: { draft.setTipsQuestion(q, $0) }))
            }
            if draft.asksTips(.birdieCount) {
                lineStepper("Linje for antall birdier", value: $draft.rules.tips.birdieCountLine,
                            in: Tips.birdieCountLineLimits, changeNote: draft.tipsLineNote(\.birdieCountLine))
            }
            if draft.asksTips(.winnerPoints) {
                lineStepper("Linje for vinnerens poeng", value: $draft.rules.tips.winnerPointsLine,
                            in: Tips.winnerPointsLineLimits, changeNote: draft.tipsLineNote(\.winnerPointsLine))
            }
        } header: {
            DDHeader(RulesetSection.tips.title)
        } footer: {
            RuleSectionFooter(text: "Velg en mal og slå enkeltspørsmål av eller på. Linja for snittet settes per kveld på kupongen. "
                                  + "Den som ikke har oppdatert appen, ser bare de fem klassiske spørsmålene.",
                              issues: draft.issues(in: .tips))
        }
    }

    /// Velger malen. «Tilpasset» kan ikke velges; den står bare når spørsmålene ikke er som en mal.
    private var templateBinding: Binding<TipsTemplate?> {
        Binding(get: { draft.tipsTemplate }, set: { if let t = $0 { draft.applyTipsTemplate(t) } })
    }

    /// En linje i hele steg, så den blir stående på et halvt tall.
    private func lineStepper(_ title: String, value: Binding<Double>, in range: ClosedRange<Double>,
                             changeNote: String?) -> some View {
        Stepper(value: value, in: range, step: draft.rules.tips.lineStep) {
            LabeledContent {
                Text(Tips.formatPlain(value.wrappedValue)).monospacedDigit()
            } label: {
                RuleFieldLabel(title: title, changeNote: changeNote)
            }
        }
    }
}
