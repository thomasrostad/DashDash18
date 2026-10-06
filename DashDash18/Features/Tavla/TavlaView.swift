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
                    .buttonStyle(.dd(.primary))
            }
        case .loaded:
            if let standings = model.standings {
                TavlaList(standings: standings)
            } else {
                // ScrollView, så «dra ned for å hente på nytt» virker også her.
                ScrollView {
                    NoSeasonView()
                        .ddCard(.empty)
                        .padding(.horizontal, DDSpacing.gutter)
                        .padding(.vertical, DDSpacing.l)
                }
            }
        }
    }
}

/// Tabellen, «Slik telles det» og veien til oppsummeringen.
struct TavlaList: View {
    let standings: TavlaStandings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DDSpacing.cardGap) {
                if standings.status == .finished, standings.summary != nil {
                    NavigationLink {
                        SeasonSummaryView(standings: standings)
                    } label: {
                        FinishedSeasonCard()
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, DDSpacing.m)
                }

                DDSectionLabel("Jakkeracet · \(standings.seasonName)") {
                    Text("\(standings.eveningsPlayed) av \(standings.eveningsTotal) \(standings.eveningsTotal == 1 ? "kveld" : "kvelder") spilt")
                        .ddEyebrow()
                }
                if standings.isEmpty {
                    ContentUnavailableView("Ingen spillere ennå", systemImage: "person.3",
                                           description: Text("Troppen står her når arrangøren har lagt den inn."))
                        .ddCard(.empty)
                } else {
                    VStack(spacing: 0) {
                        ForEach(standings.rows) { row in
                            NavigationLink {
                                PlayerProfileView(standings: standings, memberID: row.memberID)
                            } label: {
                                TavlaRowView(row: row, standings: standings)
                            }
                            .buttonStyle(.plain)
                            if row.id != standings.rows.last?.id { DDDivider() }
                        }
                    }
                    .ddCard(padding: DDSpacing.l)
                }

                RulesExplanationCard(rules: standings.rules)
                    .padding(.top, DDSpacing.m)
            }
            .padding(.horizontal, DDSpacing.gutter)
            .padding(.vertical, DDSpacing.l)
        }
    }
}

/// Hero-kortet over tabellen når sesongen er ferdig: jakka og veien til oppsummeringen.
private struct FinishedSeasonCard: View {
    var body: some View {
        HStack(spacing: 14) {
            DDJacketIcon()
                .stroke(Color.ddGold, style: StrokeStyle(lineWidth: 1.6, lineJoin: .round))
                .frame(width: 30, height: 36)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Sesongen er ferdig")
                    .font(.ddTitleSmall)
                Text("Se mesteren, pallen og sesongens tall.")
                    .font(.ddCallout)
                    .foregroundStyle(Color.ddOnDark.opacity(0.8))
            }
            Spacer(minLength: 8)
            Image(systemName: "arrow.right")
                .foregroundStyle(Color.ddGold)
                .accessibilityHidden(true)
        }
        .ddCard(.hero)
        .accessibilityElement(children: .combine)
    }
}

/// «Slik telles det»: regelsettet i setninger, sammenfoldet.
private struct RulesExplanationCard: View {
    let rules: Ruleset

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(RulesetExplanation.sentences(for: rules).enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.ddCallout)
                        .foregroundStyle(Color.ddInkSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.top, 10)
        } label: {
            Text("Slik telles det")
                .font(.ddBodyEmphasis)
                .foregroundStyle(Color.ddForestInk)
        }
        .tint(Color.ddForestInk)
        .ddCard()
    }
}

struct TavlaRowView: View {
    let row: TavlaStandings.Row
    let standings: TavlaStandings

    var body: some View {
        DDRankRow(place: "\(row.place).", name: row.name, detail: detail, isMe: row.isMe) {
            HStack(spacing: 10) {
                DDRankValue(standings.points(row.total))
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.ddInkSecondary)
                    .accessibilityHidden(true)
            }
        }
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
