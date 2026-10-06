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
        .navigationBarTitleDisplayMode(.inline)
    }

    private func content(_ s: SeasonSummary) -> some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Mester", systemImage: "trophy.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.green)
                    Text(s.champion.name)
                        .font(.largeTitle.bold())
                    Text(([s.championLine, "\(standings.points(s.champion.total)) poeng"].compactMap { $0 }
                          + [s.championBasis]).joined(separator: " · "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }

            Section("Pallen") {
                ForEach(s.podium) { row in
                    placeRow(row)
                }
            }

            if !s.rest.isEmpty {
                Section("Resten av feltet") {
                    ForEach(s.rest) { row in
                        placeRow(row)
                    }
                }
            }

            Section("Sesongen i tall") {
                TavlaStatRow(label: "Kvelder spilt", value: "\(s.eveningsPlayed) / \(s.eveningsTotal)")
                if let h = s.bestRound { highlight("Sesongens runde", h) }
                if let h = s.mostBirdies { highlight("Flest birdies", h) }
                if let h = s.longestDrive { highlight("Lengste drive", h) }
            }

            Section {
                Text("Takk for sesongen.")
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            }
        }
    }

    private func placeRow(_ row: TavlaStandings.Row) -> some View {
        HStack {
            Text("\(row.place).")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(minWidth: 28, alignment: .trailing)
            Text(row.name)
                .fontWeight(row.place == 1 ? .semibold : .regular)
            if row.isMe {
                Text("DEG")
                    .font(.caption2.bold())
                    .foregroundStyle(Color.accentColor)
            }
            Spacer()
            Text("\(standings.points(row.total)) p")
                .monospacedDigit()
        }
    }

    private func highlight(_ label: String, _ h: SeasonSummary.Highlight) -> some View {
        LabeledContent {
            Text(h.value).monospacedDigit()
        } label: {
            Text(label)
            Text([h.name, h.detail].compactMap { $0 }.joined(separator: " · "))
        }
    }
}
