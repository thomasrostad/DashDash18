import SwiftUI

// Feed-kortene på Hjem (fase 19, docs/hjem-feed.md): din runde, bragd, tabell og kompakte linjer.
// Hvert kort har en kilde-pille og, når det har en aktivitetsrad, reaksjoner.

/// Kilde-pillen: «Jakkeracet» (lime), «Morrocupen» (sol), «Løs runde» (earth).
struct HjemSourcePill: View {
    let source: HomeFeedSource

    var body: some View {
        DDPill(source.title, tone: source.tone.ddTone)
            .lineLimit(1)
            .fixedSize()
    }
}

/// Tid og ulest-prikk øverst til høyre på kortene.
struct HjemTimeLabel: View {
    let time: String
    var isUnread = false

    var body: some View {
        HStack(spacing: 6) {
            if isUnread {
                DDUnreadDot().accessibilityLabel("Ulest")
            }
            Text(time)
                .font(.ddCaption)
                .monospacedDigit()
                .foregroundStyle(Color.ddInkSecondary)
                .lineLimit(1)
                .fixedSize()
        }
    }
}

/// Reaksjonsbrikkene, med en knapp for å legge til en ny.
struct HjemReactionsRow: View {
    let reactions: HomeReactions
    let hasReacted: (ActivityReaction) -> Bool
    let toggle: (ActivityReaction) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ReactionChipsView(chips: reactions.chips, onTap: toggle)
            Menu {
                ForEach(ActivityReaction.allCases, id: \.self) { reaction in
                    Button {
                        toggle(reaction)
                    } label: {
                        Text(reaction.rawValue + "  " + (hasReacted(reaction) ? "Fjern" : reaction.accessibilityName))
                    }
                }
            } label: {
                Image(systemName: "face.smiling")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.ddInkSecondary)
                    .frame(width: 32, height: 32)
                    .background(Circle().strokeBorder(Color.ddHairline, lineWidth: 1))
                    .contentShape(Circle())
            }
            .accessibilityLabel("Reager")
        }
    }
}

/// Langt trykk på et kort gir hele reaksjonssettet (som i Varsler), også når ingen har reagert ennå.
struct HjemReactionMenu: ViewModifier {
    let target: HomeReactions?
    let hasReacted: (ActivityReaction, HomeReactions) -> Bool
    let toggle: (ActivityReaction, HomeReactions) -> Void

    func body(content: Content) -> some View {
        if let target {
            content.contextMenu {
                ForEach(ActivityReaction.allCases, id: \.self) { reaction in
                    Button {
                        toggle(reaction, target)
                    } label: {
                        Text(reaction.rawValue + "  "
                             + (hasReacted(reaction, target) ? "Fjern" : reaction.accessibilityName))
                    }
                }
                let who = target.chips.map { $0.reaction.rawValue + " " + NorwegianList.join($0.names) }
                if !who.isEmpty {
                    Section("Har reagert") {
                        ForEach(who, id: \.self) { Text($0) }
                    }
                }
            }
        } else {
            content
        }
    }
}

// MARK: - Din runde

struct HjemMyRoundCardView: View {
    let card: HomeMyRoundCard
    let feedCard: HomeFeedCard
    let share: ResultShare?
    let reactionsRow: HjemReactionsRow?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Text("Din runde · \(feedCard.time)")
                    .ddEyebrow()
                    .lineLimit(1)
                if feedCard.isUnread { DDUnreadDot().accessibilityLabel("Ulest") }
                Spacer(minLength: 8)
                HjemSourcePill(source: feedCard.source)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(card.title)
                    .font(.ddTitleSmall)
                    .foregroundStyle(Color.ddForestInk)
                if let subtitle = card.subtitle {
                    Text(subtitle)
                        .font(.ddCaption)
                        .foregroundStyle(Color.ddInkSecondary)
                }
            }
            .accessibilityElement(children: .combine)
            HStack(alignment: .bottom) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(card.points.map(String.init) ?? card.value)
                        .font(.dd(.sans, size: 52, weight: .light, relativeTo: .largeTitle))
                        .monospacedDigit()
                        .foregroundStyle(Color.ddInk)
                    if card.points != nil {
                        Text("poeng")
                            .font(.ddCallout)
                            .foregroundStyle(Color.ddInkSecondary)
                    }
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    if let place = card.placeText {
                        Text(place)
                            .font(.ddNumberLarge)
                            .foregroundStyle(Color.ddInk)
                    }
                    Text(card.ofText)
                        .font(.ddCaption)
                        .foregroundStyle(Color.ddInkSecondary)
                }
            }
            if !card.marks.isEmpty {
                HjemFlow(spacing: 6) {
                    ForEach(card.marks, id: \.label) { mark in
                        DDChip(mark.label, tone: mark.name.tone)
                    }
                }
            }
            if let insight = card.insight {
                DDInfoStripe(insight)
            }
            if let reactionsRow { reactionsRow }
            VStack(spacing: 0) {
                DDDivider()
                HStack(spacing: 8) {
                    Text(card.winner ?? "")
                        .font(.ddCaption)
                        .foregroundStyle(Color.ddInkSecondary)
                        .lineLimit(2)
                    Spacer(minLength: 8)
                    if let share {
                        ResultShareButton(share: share)
                            .font(.dd(.sans, size: 15, weight: .semibold, relativeTo: .body))
                            .foregroundStyle(Color.ddForestInk)
                            .frame(minHeight: 44)
                    }
                }
                .padding(.top, 2)
            }
        }
        .ddCard(.large)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(HjemDisplay.myRoundLabel(card))
    }
}

// MARK: - Bragd

struct HjemFeatCardView: View {
    let card: HomeFeatCard
    let feedCard: HomeFeedCard
    let reactionsRow: HjemReactionsRow?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                DDAvatar(name: card.name, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.isMe ? "\(card.name) (deg)" : card.name)
                        .font(.ddBodyEmphasis)
                        .foregroundStyle(Color.ddInk)
                    Text(card.place)
                        .font(.ddCaption)
                        .foregroundStyle(Color.ddInkSecondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                HjemTimeLabel(time: feedCard.time, isUnread: feedCard.isUnread)
            }
            HStack(spacing: 14) {
                Text("\(card.strokes)")
                    .font(.dd(.sans, size: 44, weight: .light, relativeTo: .largeTitle))
                    .monospacedDigit()
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.headline)
                        .font(.dd(.sans, size: 17, weight: .semibold, relativeTo: .headline))
                    Text(card.detail)
                        .font(.ddCallout)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(Color.ddSunInk)
            .padding(14)
            .background(Color.ddSunBackground, in: .rect(cornerRadius: DDRadius.input))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(HjemDisplay.featLabel(card, time: feedCard.time))
            HStack(spacing: 8) {
                if let reactionsRow { reactionsRow }
                Spacer(minLength: 8)
                HjemSourcePill(source: feedCard.source)
            }
        }
        .ddCard()
    }
}

// MARK: - Tabell

struct HjemTableCardView: View {
    let card: HomeTableCard
    let feedCard: HomeFeedCard
    let reactionsRow: HjemReactionsRow?
    let openTable: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                DDIconTile(systemImage: "chart.line.uptrend.xyaxis")
                Text(card.text)
                    .font(.ddBody)
                    .foregroundStyle(Color.ddInk)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HjemTimeLabel(time: feedCard.time, isUnread: feedCard.isUnread)
                    .padding(.top, 9)
            }
            VStack(spacing: 0) {
                ForEach(card.rows) { row in
                    HjemMiniTableRow(row: row)
                }
            }
            .padding(.leading, 48)
            if let reactionsRow {
                reactionsRow.padding(.leading, 48)
            }
            HStack(spacing: 8) {
                HjemSourcePill(source: feedCard.source)
                Spacer(minLength: 8)
                Button(action: openTable) {
                    Text("Se tabellen →")
                        .font(.dd(.sans, size: 15, weight: .semibold, relativeTo: .body))
                        .foregroundStyle(Color.ddForestInk)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Se tabellen i \(card.competitionName)")
            }
            .padding(.leading, 48)
        }
        .ddCard()
    }
}

/// En rad i minitabellen: plass, navn, ↑/↓ og poeng. Du er uthevet (`youRow`).
struct HjemMiniTableRow: View {
    let row: HomeTableRow

    var body: some View {
        HStack(spacing: 10) {
            Text("\(row.place).")
                .font(.ddCaption)
                .monospacedDigit()
                .foregroundStyle(Color.ddInkSecondary)
                .frame(width: 22, alignment: .leading)
            Text(row.name)
                .font(row.isMe ? .dd(.sans, size: 16, weight: .semibold, relativeTo: .body) : .ddBody)
                .foregroundStyle(Color.ddForestInk)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let move = row.move, let text = row.moveText {
                let up = HjemDisplay.isUp(move)
                Text(text)
                    .font(.dd(.sans, size: 12, weight: .semibold, relativeTo: .caption))
                    .foregroundStyle(up ? Color.ddLimeInk : Color.ddBlushInk)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(up ? Color.ddLimeBackground : Color.ddBlushBackground))
                    .accessibilityLabel(up ? "opp \(move)" : "ned \(-move)")
            }
            if let points = row.points {
                Text(points)
                    .font(.ddBodyEmphasis)
                    .monospacedDigit()
                    .foregroundStyle(Color.ddInk)
                    .frame(minWidth: 30, alignment: .trailing)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background {
            if row.isMe {
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.ddYouRow)
            }
        }
        .padding(.horizontal, -10)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Kompakte linjer

struct HjemLinesCardView: View {
    let lines: [HomeLine]
    let feedCard: HomeFeedCard
    let reactionsRow: (HomeReactions) -> HjemReactionsRow?
    let menu: (HomeReactions?) -> HjemReactionMenu

    var body: some View {
        VStack(spacing: 0) {
            ForEach(lines) { line in
                if line.id != lines.first?.id { DDDivider() }
                HStack(alignment: .top, spacing: 12) {
                    DDIconTile(systemImage: line.symbol)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(line.text)
                            .font(.ddBody)
                            .foregroundStyle(Color.ddInk)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(line.context)
                            .font(.ddCaption)
                            .foregroundStyle(Color.ddInkSecondary)
                        if let reactions = line.reactions, let row = reactionsRow(reactions) {
                            row.padding(.top, 4)
                        }
                    }
                    .padding(.top, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    HjemTimeLabel(time: line.time, isUnread: feedCard.isUnread && line.id == lines.first?.id)
                        .padding(.top, 9)
                }
                .padding(.vertical, 12)
                .contentShape(Rectangle())
                .modifier(menu(line.reactions))
            }
        }
        // 6 over og under og 18 på sidene (designet), ikke kortets vanlige 18 rundt.
        .padding(.horizontal, 18)
        .padding(.vertical, 6)
        .ddCard(padding: 0)
    }
}

/// Enkel flytende rad (scoremerkene): bryter til ny linje når det ikke er plass.
struct HjemFlow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let extra = rows[rows.count - 1].indices.isEmpty ? size.width : size.width + spacing
            if rows[rows.count - 1].width + extra > width, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            let isFirst = rows[rows.count - 1].indices.isEmpty
            rows[rows.count - 1].indices.append(index)
            rows[rows.count - 1].width += isFirst ? size.width : size.width + spacing
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
        }
        return rows.filter { !$0.indices.isEmpty }
    }
}
