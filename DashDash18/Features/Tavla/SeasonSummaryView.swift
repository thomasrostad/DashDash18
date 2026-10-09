import GolfgutuCore
import SwiftUI

/// Sesongoppsummeringen: mester, pall og sesongens tall.
struct SeasonSummaryView: View {
    let standings: TavlaStandings

    var body: some View {
        Group {
            if let s = standings.summary {
                content(s)
            } else {
                ContentUnavailableView("Ingenting å oppsummere ennå", systemImage: "trophy",
                                       description: Text("Kom tilbake når det er spilt minst én runde."))
            }
        }
        .navigationTitle(standings.seasonName)
        .ddNavigationChrome()
    }

    private func content(_ s: SeasonSummary) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DDSpacing.cardGap) {
                DDJacketHero(
                    eyebrow: "\(standings.seasonName) · mester",
                    title: s.champion.name,
                    subtitle: ([s.championLine, "\(standings.points(s.champion.total)) poeng"].compactMap { $0 }
                               + [s.championBasis]).joined(separator: " · ")
                )
                .accessibilityElement(children: .combine)
                .padding(.bottom, DDSpacing.m)

                DDSectionLabel("Pallen")
                placeCard(s.podium)

                if !s.rest.isEmpty {
                    DDSectionLabel("Resten av feltet")
                        .padding(.top, DDSpacing.l)
                    placeCard(s.rest)
                }

                DDSectionLabel("Turneringen i tall")
                    .padding(.top, DDSpacing.l)
                VStack(alignment: .leading, spacing: 12) {
                    DDStatRow(label: DayTerm.capitalized(standings.rules.day.many) + " spilt", value: "\(s.eveningsPlayed) / \(s.eveningsTotal)")
                    if let h = s.bestRound { highlight("Turneringens runde", h) }
                    if let h = s.mostBirdies { highlight("Flest birdies", h) }
                    if let h = s.longestDrive { highlight("Lengste drive", h) }
                }
                .ddCard(.stat)

                Text("Takk for turneringen.")
                    .font(.ddCallout)
                    .foregroundStyle(Color.ddInkSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, DDSpacing.xl)
            }
            .padding(.horizontal, DDSpacing.gutter)
            .padding(.vertical, DDSpacing.l)
        }
    }

    private func placeCard(_ rows: [TavlaStandings.Row]) -> some View {
        VStack(spacing: 0) {
            ForEach(rows) { row in
                DDRankRow(place: "\(row.place).", name: row.name, isMe: row.isMe) {
                    DDRankValue("\(standings.points(row.total)) p", emphasized: row.place == 1)
                }
                if row.id != rows.last?.id { DDDivider() }
            }
        }
        .ddCard(padding: DDSpacing.l)
    }

    private func highlight(_ label: String, _ h: SeasonSummary.Highlight) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.ddCallout)
                    .foregroundStyle(Color.ddStatText)
                Text([h.name, h.detail].compactMap { $0 }.joined(separator: " · "))
                    .font(.ddCaption)
                    .foregroundStyle(Color.ddStatSecondary)
            }
            Spacer(minLength: 8)
            Text(h.value)
                .font(.dd(.sans, size: 15, weight: .medium, relativeTo: .callout))
                .monospacedDigit()
                .foregroundStyle(Color.ddYellow)
        }
        .accessibilityElement(children: .combine)
    }
}
