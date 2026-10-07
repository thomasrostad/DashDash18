import GolfgutuCore
import SwiftUI

// Inngangene til veddemålene fra runden, Kveld og Tavla. Vises bare med `BetsFeature.isEnabled`.

/// Under runden: «Vedd» med spillerne i runden og deg selv, og veien til alle veddemål.
struct VeddKnapp: View {
    let game: RoundGame
    let me: UUID
    @State private var target: VeddTarget?

    var body: some View {
        if BetsFeature.isEnabled {
            HStack(spacing: DDSpacing.s) {
                Menu {
                    Button("Om meg selv") { target = VeddTarget(against: nil) }
                    Section("Vedd på") {
                        ForEach(opponents, id: \.self) { id in
                            Button(game.name(id)) { target = VeddTarget(against: id) }
                        }
                    }
                } label: {
                    Label("Vedd", systemImage: "die.face.5")
                }
                NavigationLink {
                    BetsView()
                } label: {
                    Label("Alle veddemål", systemImage: "list.bullet")
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .buttonStyle(.dd(.secondary, fullWidth: true, compact: true))
            .navigationDestination(item: $target) { t in
                BetsView(against: t.against ?? me)
            }
        }
    }

    private var opponents: [UUID] {
        game.snapshot.players.map(\.memberID)
            .filter { $0 != me }
            .sorted { NorwegianSort.areInIncreasingOrder(game.name($0), game.name($1)) }
    }
}

/// Hvem arket skal åpnes for. `against == me` betyr «om meg selv» i `BetsView`.
struct VeddTarget: Identifiable, Hashable {
    let against: UUID?
    var id: String { against?.uuidString ?? "meg" }
}

/// Kortet på Kveld før runden.
struct BetsKveldCard: View {
    var body: some View {
        if BetsFeature.isEnabled {
            NavigationLink {
                BetsView()
            } label: {
                HStack(spacing: DDSpacing.m) {
                    Image(systemName: "die.face.5")
                        .font(.title3)
                        .foregroundStyle(Color.ddForestInk)
                        .frame(width: 32)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Veddemål")
                            .font(.ddBodyEmphasis)
                            .foregroundStyle(Color.ddInk)
                        Text("Vedd poeng på kvelden og hverandre")
                            .font(.ddCallout)
                            .foregroundStyle(Color.ddInkSecondary)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.ddInkSecondary)
                }
                .contentShape(.rect)
                .ddCard()
                .accessibilityElement(children: .combine)
            }
            .buttonStyle(.plain)
        }
    }
}

/// Tavla: veien til poengtabellen for veddemål, under jakketabellen.
struct BetsTavlaLink: View {
    var body: some View {
        if BetsFeature.isEnabled {
            NavigationLink {
                BetsTableScreen()
            } label: {
                HStack {
                    Label("Poengtabell for veddemål", systemImage: "die.face.5")
                        .font(.ddBodyEmphasis)
                        .foregroundStyle(Color.ddForestInk)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.ddInkSecondary)
                }
                .contentShape(.rect)
                .ddCard()
            }
            .buttonStyle(.plain)
        }
    }
}

/// Poengtabellen som egen skjerm fra Tavla.
private struct BetsTableScreen: View {
    @Environment(\.clubContext) private var context

    var body: some View {
        if let context {
            BetsTableContent(model: BetsModel(context: context))
        }
    }
}

private struct BetsTableContent: View {
    @State var model: BetsModel

    var body: some View {
        Group {
            if let board = model.board {
                BetPointsTableView(board: board)
            } else if model.state == .disabled {
                ContentUnavailableView("Veddemål kommer", systemImage: "die.face.5",
                                       description: Text("Veddemål med poeng slås på når databasen er klar."))
            } else if case .failed(let message) = model.state {
                ContentUnavailableView("Fikk ikke hentet tabellen", systemImage: "wifi.exclamationmark",
                                       description: Text(message))
            } else {
                ProgressView("Henter tabellen …")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task { await model.load() }
    }
}
