import GolfgutuCore
import SwiftUI

/// Sammendraget øverst i «Turneringen»: merket med oppsettet («Stableford-serie», eller hvor mye som
/// er endret) og det viktigste i regelsettet i klart språk. Hele forklaringen kan foldes ut under.
struct RulesetSummarySection: View {
    let rules: Ruleset
    var title = "Reglene"
    var kind: CompetitionKind = .season
    @State private var showsAll = false

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
            DisclosureGroup("Alle reglene i detalj", isExpanded: $showsAll) {
                Text(RulesetExplanation.text(for: rules))
                    .font(.dd(.sans, size: 14, relativeTo: .callout))
                    .foregroundStyle(Color.ddInkSecondary)
            }
        } header: {
            DDHeader(title)
        }
    }
}
