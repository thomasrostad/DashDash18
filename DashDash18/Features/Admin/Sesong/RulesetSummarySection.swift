import GolfgutuCore
import SwiftUI

/// Sammendraget øverst i «Sesong og regler»: merket «Golfgutu-oppsettet» (eller hvor mye som er endret)
/// og det viktigste i regelsettet i klart språk. Hele forklaringen kan foldes ut under.
struct RulesetSummarySection: View {
    let rules: Ruleset
    var title = "Reglene"
    @State private var showsAll = false

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                DDPill(RulesetSummary.badge(for: rules),
                       tone: RulesetSummary.isGolfgutu(rules) ? .lime : .sun,
                       systemImage: RulesetSummary.isGolfgutu(rules) ? "checkmark.seal" : "slider.horizontal.3")
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
