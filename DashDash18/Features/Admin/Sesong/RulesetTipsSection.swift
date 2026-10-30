import GolfgutuCore
import SwiftUI

/// Tippekupongen: mal (Klassisk, Birdiejakt, Full kupong, Moro-kupong), hvert spørsmål av eller på, og
/// linjene for over/under-spørsmålene som er med. Linja for snittet settes per kveld på kupongen, som før.
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
                    .disabled(draft.tipsCouponIsFull && !draft.asksTips(q))
            }
            if draft.asksTips(.featuredHole) {
                Stepper(value: $draft.rules.tips.featuredHole, in: Ruleset.TipsRules.featuredHoleLimits) {
                    LabeledContent {
                        Text("Hull \(draft.rules.tips.featuredHole)").monospacedDigit()
                    } label: {
                        RuleFieldLabel(title: "Kveldens hull", changeNote: draft.tipsFeaturedHoleNote)
                    }
                }
            }
            ForEach(draft.rules.tips.questions.filter { Tips.lineLimits(for: $0) != nil }) { q in
                lineStepper(q)
            }
        } header: {
            DDHeader(RulesetSection.tips.title)
        } footer: {
            RuleSectionFooter(text: "Velg en mal og slå enkeltspørsmål av eller på, høyst \(TipsQuestion.maxPerCoupon). "
                                  + "Linja for snittet settes per kveld på kupongen. "
                                  + "Den som ikke har oppdatert appen, ser bare de fem klassiske spørsmålene.",
                              issues: draft.issues(in: .tips))
        }
    }

    /// Velger malen. «Tilpasset» kan ikke velges; den står bare når spørsmålene ikke er som en mal.
    private var templateBinding: Binding<TipsTemplate?> {
        Binding(get: { draft.tipsTemplate }, set: { if let t = $0 { draft.applyTipsTemplate(t) } })
    }

    /// En linje i hele steg, så den blir stående på et halvt tall.
    private func lineStepper(_ q: TipsQuestion) -> some View {
        let value = Binding(get: { draft.rules.tips.line(q) ?? 0 }, set: { draft.rules.tips.setLine(q, $0) })
        return Stepper(value: value, in: Tips.lineLimits(for: q) ?? 0.5...0.5, step: draft.rules.tips.lineStep) {
            LabeledContent {
                Text(Tips.formatPlain(value.wrappedValue)).monospacedDigit()
            } label: {
                RuleFieldLabel(title: Self.lineTitle(q), changeNote: draft.tipsLineNote(q))
            }
        }
    }

    static func lineTitle(_ q: TipsQuestion) -> String {
        switch q {
        case .birdieCount: "Linje for antall birdier"
        case .winnerPoints: "Linje for vinnerens poeng"
        case .lastPlacePoints: "Linje for sistemannens poeng"
        case .winningMargin: "Linje for seiersmarginen"
        case .blankHoles: "Linje for blanke hull"
        case .parOrBetterPlayers: "Linje for antall på par"
        case .longestDriveMeters: "Linje for longest drive (m)"
        default: "Linje"
        }
    }
}
