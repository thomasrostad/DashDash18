import GolfgutuCore
import SwiftUI

/// Spillerprofilen: poengene i tabellen, sesongens tall og runde for runde.
struct PlayerProfileView: View {
    let standings: TavlaStandings
    let memberID: UUID
    @State private var scorecard: RoundScorecardTarget?

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
        .ddNavigationChrome()
        .sheet(item: $scorecard) { target in
            if let game = standings.game(target.roundID) {
                ScorekortSheet(game: game, memberID: target.memberID)
            }
        }
    }

    private func content(_ p: PlayerProfile) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DDSpacing.cardGap) {
                ProfileHeader(profile: p, standings: standings)
                    .padding(.bottom, DDSpacing.s)

                DDSectionLabel("Turneringen")
                DDTileGrid([
                    DDStatTile("Stableford", value: "\(p.stablefordTotal)", highlight: true),
                    DDStatTile("Runder", value: "\(p.roundsPlayed)"),
                    DDStatTile("Snitt / runde", value: p.average.map { RuleFormat.number($0) } ?? "—"),
                    DDStatTile("Beste runde", value: p.best.map(String.init) ?? "—"),
                    DDStatTile("Birdies", value: "\(p.birdies)"),
                    DDStatTile("Lengste drive", value: p.longestDrive.map(SidePrizes.formatMeters) ?? "—"),
                ])
                if StatsFeature.isEnabled {
                    StatsProfileLink(memberID: memberID, name: p.row.name)
                }

                if let text = p.headToHeadText(name: p.row.name) {
                    VStack(alignment: .leading, spacing: 6) {
                        DDInfoStripe(tone: .earth) {
                            HStack(alignment: .firstTextBaseline) {
                                Text("Mot deg i turneringen")
                                Spacer(minLength: 8)
                                Text(text)
                                    .font(.ddBodyEmphasis)
                                    .monospacedDigit()
                            }
                        }
                        .accessibilityElement(children: .combine)
                        DDFooter("Runder der dere begge har poeng, på stableford.")
                            .padding(.horizontal, 2)
                    }
                    .padding(.top, DDSpacing.m)
                }

                DDSectionLabel("Runde for runde") {
                    Text(standings.roundColumns).ddEyebrow()
                }
                .padding(.top, DDSpacing.l)
                if p.rounds.isEmpty {
                    Text("Poengene dukker opp her etter første runde.")
                        .font(.ddCallout)
                        .foregroundStyle(Color.ddInkSecondary)
                        .frame(maxWidth: .infinity)
                        .ddCard(.empty)
                } else {
                    VStack(spacing: 0) {
                        ForEach(p.rounds) { line in
                            // Trykk gir scorekortet for runden.
                            Button {
                                scorecard = RoundScorecardTarget(roundID: line.roundID, memberID: memberID)
                            } label: {
                                RoundLineView(line: line, standings: standings)
                                    .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Viser scorekortet")
                            if line.id != p.rounds.last?.id { DDDivider() }
                        }
                    }
                    .ddCard(padding: DDSpacing.l)
                }
            }
            .padding(.horizontal, DDSpacing.gutter)
            .padding(.vertical, DDSpacing.l)
        }
    }
}

/// Avatar, poeng og plass øverst på profilen.
private struct ProfileHeader: View {
    let profile: PlayerProfile
    let standings: TavlaStandings

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            DDAvatar(name: profile.row.name, size: 52)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(standings.points(profile.row.total)) poeng")
                    .font(.ddTitle)
                    .monospacedDigit()
                    .foregroundStyle(Color.ddForestInk)
                if let basis = profile.basis(standings) {
                    Text(basis)
                        .font(.ddCallout)
                        .monospacedDigit()
                        .foregroundStyle(Color.ddInkSecondary)
                }
            }
            Spacer(minLength: 8)
            if standings.hasResults {
                DDPill("\(profile.row.place). plass", tone: .sun)
                    .fixedSize()
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct RoundLineView: View {
    let line: PlayerProfile.RoundLine
    let standings: TavlaStandings

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(line.title)
                    .font(.ddBody)
                    .foregroundStyle(Color.ddInk)
                if line.isOngoing {
                    DDPill("Pågår", tone: .live)
                        .fixedSize()
                }
            }
            Spacer(minLength: 8)
            Text("\(line.place).")
                .font(.ddMonoSmall)
                .monospacedDigit()
                .foregroundStyle(Color.ddInkSecondary)
            if !standings.countsStableford {
                Text(line.duel.map(standings.points) ?? "—")
                    .font(.ddNumber)
                    .monospacedDigit()
                    .frame(minWidth: 34, alignment: .trailing)
            }
            Text("\(line.stableford)")
                .font(.ddBody)
                .monospacedDigit()
                .foregroundStyle(Color.ddInkSecondary)
                .frame(minWidth: 34, alignment: .trailing)
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }
}
