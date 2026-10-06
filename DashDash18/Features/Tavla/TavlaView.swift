import GolfgutuCore
import SwiftUI

/// Tavla-fanen: sesongens tabell etter regelsettet, med spillerprofil og oppsummering.
struct TavlaView: View {
    @Environment(\.clubContext) private var context

    var body: some View {
        if let context {
            TavlaContent(model: TavlaModel(context: context))
        } else {
            NoSeasonView()
        }
    }
}

private struct TavlaContent: View {
    @State var model: TavlaModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        content
            .task { await model.load() }
            .refreshable { await model.load() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    Task { await model.load() }
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ProgressView("Henter tabellen …")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ContentUnavailableView {
                Label("Fikk ikke hentet tabellen", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Prøv igjen") { Task { await model.load() } }
                    .buttonStyle(.borderedProminent)
            }
        case .loaded:
            if let standings = model.standings {
                TavlaList(standings: standings)
            } else {
                // List, så «dra ned for å hente på nytt» virker også her.
                List {
                    NoSeasonView()
                        .listRowBackground(Color.clear)
                }
            }
        }
    }
}

/// Tabellen, «Slik telles det» og veien til oppsummeringen.
struct TavlaList: View {
    let standings: TavlaStandings

    var body: some View {
        List {
            if standings.status == .finished, standings.summary != nil {
                Section {
                    NavigationLink {
                        SeasonSummaryView(standings: standings)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Sesongen er ferdig")
                                .font(.headline)
                            Text("Se mesteren, pallen og sesongens tall.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section {
                if standings.isEmpty {
                    ContentUnavailableView("Ingen spillere ennå", systemImage: "person.3",
                                           description: Text("Troppen står her når arrangøren har lagt den inn."))
                } else {
                    ForEach(standings.rows) { row in
                        NavigationLink {
                            PlayerProfileView(standings: standings, memberID: row.memberID)
                        } label: {
                            TavlaRowView(row: row, standings: standings)
                        }
                        .listRowBackground(row.isMe ? Color.accentColor.opacity(0.12) : nil)
                    }
                }
            } header: {
                HStack {
                    Text(standings.seasonName)
                    Spacer()
                    Text("\(standings.eveningsPlayed) av \(standings.eveningsTotal) \(standings.eveningsTotal == 1 ? "kveld" : "kvelder") spilt")
                }
            }

            Section {
                DisclosureGroup("Slik telles det") {
                    ForEach(Array(RulesetExplanation.sentences(for: standings.rules).enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

struct TavlaRowView: View {
    let row: TavlaStandings.Row
    let standings: TavlaStandings

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(row.place).")
                .font(.body.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 28, alignment: .trailing)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(row.name)
                        .font(row.isMe ? .body.bold() : .body)
                    if row.isMe {
                        Text("DEG")
                            .font(.caption2.bold())
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.accentColor, in: .capsule)
                            .foregroundStyle(.white)
                    }
                }
                Text(detail)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(standings.points(row.total))
                .font(.title3.monospacedDigit().weight(.semibold))
        }
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        let holes = row.holes > 0 ? "+\(row.holes)" : "\(row.holes)"
        let evenings = row.evenings == 1 ? "1 kveld" : "\(row.evenings) kvelder"
        return "\(holes) hull · \(row.stableford) stableford · \(evenings)"
    }
}

private struct NoSeasonView: View {
    var body: some View {
        ContentUnavailableView(
            "Ingen sesong i gang",
            systemImage: "trophy",
            description: Text("Tabellen fylles når arrangøren har startet sesongen og første kveld er spilt.")
        )
    }
}

#Preview {
    NavigationStack {
        TavlaView()
    }
}
