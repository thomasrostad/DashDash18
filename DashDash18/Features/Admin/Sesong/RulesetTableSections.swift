import GolfgutuCore
import SwiftUI

/// Tabellen: duellpoeng, trekant, hva som teller, stablefordsum, skilletegn og avrunding.
struct RulesetTableSections: View {
    @Binding var draft: RulesetDraft

    var body: some View {
        Section {
            RuleNumberField("Seier", value: $draft.rules.table.matchPoints.win)
            RuleNumberField("Uavgjort", value: $draft.rules.table.matchPoints.draw)
            RuleNumberField("Tap", value: $draft.rules.table.matchPoints.loss)
            ForEach(draft.rules.table.trianglePoints.indices, id: \.self) { i in
                RuleNumberField("Trekant, \(i + 1). plass", value: $draft.rules.table.trianglePoints[i])
            }
        } header: {
            DDHeader("Tabellen: poeng")
        } footer: {
            RuleSectionFooter(text: "Poeng for utfallet av en match. Blir det oddetall, spiller tre i en trekant og får poeng etter plass.",
                              issues: issues { $0.hasPrefix("table.matchPoints") || $0.hasPrefix("table.trianglePoints") })
        }

        Section {
            Picker("Enhet", selection: $draft.rules.table.counting.unit) {
                ForEach(Ruleset.Counting.Unit.allCases, id: \.self) { Text(RuleNames.title($0)).tag($0) }
            }
            .pickerStyle(.segmented)
            Toggle("Alle teller", isOn: $draft.countsAllInTable)
            if !draft.countsAllInTable {
                RuleStepper("De beste", value: $draft.tableBest)
            }
        } header: {
            DDHeader("Tabellen: hva teller")
        } footer: {
            RuleSectionFooter(text: "Matcher: de beste matchene teller, sidepremiene teller alltid. Runder eller kvelder: alt spilleren vant der, teller sammen.",
                              issues: issues { $0.hasPrefix("table.counting") })
        }

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
            DDHeader("Stablefordsummen")
        } footer: {
            RuleSectionFooter(text: "Summen brukes som skilletegn og vises på profilen.",
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
            DDHeader("Ved likt poeng")
        } footer: {
            RuleSectionFooter(text: "Skilletegnene brukes i rekkefølge. Navn skiller alltid til slutt.",
                              issues: issues { $0 == "table.tiebreaks" })
        }

        Section {
            Toggle("Rund av tabellpoeng", isOn: $draft.roundsTablePoints)
            if draft.roundsTablePoints {
                RuleNumberField("Til nærmeste", value: $draft.roundingStep)
            }
        } header: {
            DDHeader("Avrunding")
        } footer: {
            RuleSectionFooter(text: "0,5 gir halve poeng, 1 gir hele.", issues: issues { $0 == "table.roundingStep" })
        }
    }

    private func issues(_ matches: (String) -> Bool) -> [RulesetIssue] {
        draft.issues(in: .table).filter { matches($0.field) }
    }
}
