import GolfgutuCore
import SwiftUI

/// Sammendraget øverst i «Turneringen»: merket med oppsettet («Stableford-serie», eller hvor mye som
/// er endret) og det viktigste i regelsettet i klart språk. Hele forklaringen («Slik telles det») står
/// i et ark bak ⓘ-knappen i verktøylinja (P3, `rulesExplanationButton`).
struct RulesetSummarySection: View {
    let rules: Ruleset
    var title = "Reglene"
    var kind: CompetitionKind = .season

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                let isTemplate = RulesetSummary.isTemplate(rules, kind: kind)
                DDPill(RulesetSummary.badge(for: rules, kind: kind),
                       tone: isTemplate ? .lime : .sun,
                       systemImage: isTemplate ? "checkmark.seal" : "slider.horizontal.3")
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(RulesetSummary.lines(for: rules), id: \.self) { line in
                        Label {
                            Text(line)
                        } icon: {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 5))
                                .foregroundStyle(Color.ddForestInk)
                        }
                        .labelStyle(.titleAndIcon)
                    }
                }
                .font(.dd(.sans, size: 15, relativeTo: .callout))
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
        } header: {
            DDHeader(title)
        }
    }
}

// «Slik telles det»-arket er `RulesExplanationSheet` i `Features/Tavla/TavlaView.swift`, delt med Tavla.

extension View {
    /// ⓘ i verktøylinja som åpner «Slik telles det» for regelsettet (P3).
    func rulesExplanationButton(_ rules: Ruleset) -> some View {
        modifier(RulesExplanationButton(rules: rules))
    }
}

private struct RulesExplanationButton: ViewModifier {
    let rules: Ruleset
    @State private var shows = false

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Slik telles det", systemImage: "info.circle") { shows = true }
                }
            }
            .sheet(isPresented: $shows) { RulesExplanationSheet(rules: rules) }
    }
}
