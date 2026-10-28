import GolfgutuCore
import SwiftUI

/// «Statistikk» på Tavla: turneringens tall (samme som oppsummeringen) og veien til din egen statistikk.
struct TavlaStatsSection: View {
    let standings: TavlaStandings
    @Environment(\.clubContext) private var context

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DDSpacing.cardGap) {
                DDSectionLabel("Turneringens tall")
                if let summary = standings.summary {
                    DDStatSummary(featured: summary.bestRound.map(Self.item("Beste runde")), [
                        summary.mostBirdies.map(Self.item("Flest birdies")) ?? DDStatItem("Flest birdies", value: nil),
                        summary.longestDrive.map(Self.item("Longest drive")) ?? DDStatItem("Longest drive", value: nil),
                        DDStatItem("Spilt", value: "\(standings.eveningsPlayed) av \(standings.eveningsTotal)",
                                   detail: standings.rules.day.many),
                    ])
                } else {
                    Text("Tallene kommer når første \(standings.rules.day.one) er spilt.")
                        .font(.ddCallout)
                        .foregroundStyle(Color.ddInkSecondary)
                        .frame(maxWidth: .infinity)
                        .ddCard(.empty)
                }
                if context != nil, let me = standings.me, let row = standings.row(me) {
                    DDSectionLabel("Din statistikk").padding(.top, DDSpacing.m)
                    StatsProfileLink(memberID: me, name: row.name)
                }
            }
            .padding(.horizontal, DDSpacing.gutter)
            .padding(.vertical, DDSpacing.l)
        }
    }

    /// «Beste runde: 41 p», med navnet og runden under.
    private static func item(_ label: String) -> (SeasonSummary.Highlight) -> DDStatItem {
        { h in
            DDStatItem(label, value: h.value, detail: [h.name, h.detail].compactMap(\.self).joined(separator: " · "))
        }
    }
}
