import GolfgutuCore
import SwiftUI

/// «Laget ditt» under «Neste kveld» (sql/076): laget og båsen din så snart arrangøren har vist
/// oppstillingen, før runden starter. Trykk åpner hele oppstillingen.
struct HjemLineupCard: View {
    let lineup: EveningLineup
    @State private var showsAll = false

    var body: some View {
        Button { showsAll = true } label: {
            DDInfoStripe(tone: .lime) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(lineup.title)
                            .ddEyebrow()
                        if lineup.mine.isEmpty {
                            Text(lineup.notInLineupText)
                                .font(.ddBodyEmphasis)
                        }
                        ForEach(lineup.mine) { mine in
                            VStack(alignment: .leading, spacing: 2) {
                                if lineup.showsRoundTitles {
                                    Text(mine.roundTitle)
                                        .font(.ddCaption)
                                }
                                Text(mine.summary)
                                    .font(.ddBodyEmphasis)
                                if let marker = mine.markerText {
                                    Text(marker)
                                }
                            }
                        }
                        Text("Se hele oppstillingen")
                            .font(.ddCaption)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Viser hele oppstillingen.")
        .sheet(isPresented: $showsAll) {
            EveningLineupSheet(lineup: lineup)
        }
    }
}

/// Hele oppstillingen: runde for runde, bås for bås, lag for lag. Du står uthevet.
struct EveningLineupSheet: View {
    let lineup: EveningLineup
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DDSpacing.m) {
                    ForEach(lineup.rounds) { round in
                        DDSectionLabel(round.detail.map { "\(round.title) · \($0)" } ?? round.title)
                            .padding(.top, DDSpacing.s)
                        ForEach(round.groups) { group in
                            EveningLineupGroupCard(title: round.groupTitle(group), group: group, term: round.term)
                        }
                    }
                }
                .padding(.horizontal, DDSpacing.gutter)
                .padding(.vertical, DDSpacing.l)
            }
            .navigationTitle("Oppstillingen")
            .ddNavigationChrome()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                DDConfirmToolbarItem {
                    Button("Ferdig") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Color.ddBackground)
    }
}

/// Én bås: lagene med spillerne, markøren merket.
private struct EveningLineupGroupCard: View {
    let title: String
    let group: EveningLineup.Group
    let term: GroupTerm

    var body: some View {
        VStack(alignment: .leading, spacing: DDSpacing.s) {
            Text(title)
                .font(.ddBodyEmphasis)
                .foregroundStyle(Color.ddInk)
            ForEach(group.teams) { team in
                VStack(alignment: .leading, spacing: 4) {
                    if let teamTitle = team.title {
                        Text(teamTitle)
                            .ddEyebrow()
                    }
                    ForEach(team.players) { player in
                        HStack(spacing: 6) {
                            Text(player.isMe ? "\(player.name) (deg)" : player.name)
                                .fontWeight(player.isMe ? .semibold : .regular)
                            if player.isMarker {
                                DDPill(DayTerm.capitalized(term.marker), tone: .earth)
                                    .fixedSize()
                            }
                        }
                        .font(.ddCallout)
                        .foregroundStyle(player.isMe ? Color.ddForestInk : Color.ddInk)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .ddCard()
    }
}
