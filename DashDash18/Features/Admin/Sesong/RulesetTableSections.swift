import GolfgutuCore
import SwiftUI

/// De avanserte tabellvalgene: trekant (bare med matcher), stablefordsum, skilletegn og avrunding.
/// Duellpoeng og hva som teller står blant de vanligste valgene (`RulesetCommonSections`).
struct RulesetTableSections: View {
    @Binding var draft: RulesetDraft

    var body: some View {
        if draft.countsMatches {
            triangleSection
        }
        otherSections
    }

    private var triangleSection: some View {
        Section {
            ForEach(draft.rules.table.trianglePoints.indices, id: \.self) { i in
                RuleNumberField("\(i + 1). plass", value: $draft.rules.table.trianglePoints[i])
            }
        } header: {
            RuleSectionHeader(title: "Trekant", changeNote: draft.changeNote(.trianglePoints))
        } footer: {
            RuleSectionFooter(text: "Tre i en match får poeng etter plass.",
                              issues: issues { $0.hasPrefix("table.trianglePoints") })
        }
    }

    @ViewBuilder
    private var otherSections: some View {
        Section {
            Picker("Enhet", selection: $draft.rules.table.stablefordCounting.unit) {
                ForEach(RulesetDraft.stablefordUnits, id: \.self) { Text(RuleNames.title($0)).tag($0) }
            }
            .pickerStyle(.segmented)
            Toggle("Alle teller", isOn: $draft.countsAllInStableford)
            if !draft.countsAllInStableford {
                RuleStepper("De beste", value: $draft.stablefordBest)
            }
        } header: {
            RuleSectionHeader(title: "Stablefordsummen", changeNote: draft.changeNote(.stablefordCounting))
        } footer: {
            RuleSectionFooter(text: "Skiller ved likt poeng og vises på profilen.",
                              issues: issues { $0.hasPrefix("table.stablefordCounting") })
        }

        Section {
            ForEach(Array(draft.rules.table.tiebreaks.enumerated()), id: \.element) { i, tiebreak in
                HStack {
                    Text("\(i + 1). \(RuleNames.title(tiebreak))")
                    Spacer()
                    if i > 0 {
                        Button("Flytt opp", systemImage: "arrow.up") {
                            draft.moveTiebreaks(from: [i], to: i - 1)
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                    }
                    Button("Fjern", systemImage: "minus.circle", role: .destructive) {
                        draft.removeTiebreaks(at: [i])
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                }
            }
            if !draft.unusedTiebreaks.isEmpty {
                Menu("Legg til skilletegn") {
                    ForEach(draft.unusedTiebreaks, id: \.self) { t in
                        Button(RuleNames.title(t)) { draft.addTiebreak(t) }
                    }
                }
            }
        } header: {
            RuleSectionHeader(title: "Ved likt poeng", changeNote: draft.changeNote(.tiebreaks))
        } footer: {
            RuleSectionFooter(text: "Brukes i rekkefølge. Navn skiller til slutt.",
                              issues: issues { $0 == "table.tiebreaks" })
        }

        Section {
            Toggle("Rund av tabellpoeng", isOn: $draft.roundsTablePoints)
            if draft.roundsTablePoints {
                RuleNumberField("Til nærmeste", value: $draft.roundingStep)
            }
        } header: {
            RuleSectionHeader(title: "Avrunding", changeNote: draft.changeNote(.rounding))
        } footer: {
            RuleSectionFooter(text: "0,5 gir halve poeng.", issues: issues { $0 == "table.roundingStep" })
        }
    }

    private func issues(_ matches: (String) -> Bool) -> [RulesetIssue] {
        draft.issues(in: .table).filter { matches($0.field) }
    }
}
