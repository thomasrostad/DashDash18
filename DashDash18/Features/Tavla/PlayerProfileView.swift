import GolfgutuCore
import SwiftUI

/// Spillerprofilen: poengene i tabellen, sesongens tall og runde for runde.
struct PlayerProfileView: View {
    let standings: TavlaStandings
    let memberID: UUID

    var body: some View {
        Group {
            if let profile = standings.profile(memberID) {
                content(profile)
            } else {
                ContentUnavailableView("Fant ikke spilleren", systemImage: "person.crop.circle.badge.questionmark",
                                       description: Text("Gå tilbake og prøv igjen."))
            }
        }
        .navigationTitle(standings.row(memberID)?.name ?? "Spiller")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func content(_ p: PlayerProfile) -> some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(standings.points(p.row.total)) poeng · \(p.row.place). plass")
                        .font(.title2.weight(.semibold).monospacedDigit())
                    if let basis = p.basis(standings) {
                        Text(basis)
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Sesongen") {
                TavlaStatRow(label: "Stableford", value: "\(p.stablefordTotal)")
                TavlaStatRow(label: "Runder", value: "\(p.roundsPlayed)")
                TavlaStatRow(label: "Snitt per runde", value: p.average.map { RuleFormat.number($0) } ?? "—")
                TavlaStatRow(label: "Beste runde", value: p.best.map(String.init) ?? "—")
                TavlaStatRow(label: "Birdies", value: "\(p.birdies)")
                TavlaStatRow(label: "Lengste drive", value: p.longestDrive.map(SidePrizes.formatMeters) ?? "—")
            }

            if let text = p.headToHeadText(name: p.row.name) {
                Section {
                    TavlaStatRow(label: "Mot deg i sesongen", value: text)
                } footer: {
                    Text("Runder der dere begge har poeng, på stableford.")
                }
            }

            Section {
                if p.rounds.isEmpty {
                    Text("Poengene dukker opp her etter første runde.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(p.rounds) { line in
                        RoundLineView(line: line, standings: standings)
                    }
                }
            } header: {
                HStack {
                    Text("Runde for runde")
                    Spacer()
                    Text("duell · stableford")
                }
            }
        }
    }
}

private struct RoundLineView: View {
    let line: PlayerProfile.RoundLine
    let standings: TavlaStandings

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(line.title)
                if line.isOngoing {
                    Text("Pågår")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
            Text("\(line.place).")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Text(line.duel.map(standings.points) ?? "—")
                .font(.body.monospacedDigit().weight(.medium))
                .frame(minWidth: 34, alignment: .trailing)
            Text("\(line.stableford)")
                .font(.body.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 34, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
    }
}

struct TavlaStatRow: View {
    let label: String
    let value: String

    var body: some View {
        LabeledContent(label) {
            Text(value)
                .monospacedDigit()
        }
    }
}
