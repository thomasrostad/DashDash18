import GolfgutuCore
import SwiftUI

// Feed-kortene på Hjem (fase 19, docs/hjem-feed.md): din runde, bragd, tabell og kompakte linjer.
// Hvert kort har en kilde-pille og, når det har en aktivitetsrad, reaksjoner.

/// Kilde-pillen: «Jakkeracet», «Morrocupen», «Løs runde». Nøytral chip (utbedringsplanen 4.1):
/// lime er bare for live.
struct HjemSourcePill: View {
    let source: HomeFeedSource

    var body: some View {
        // Krymper med «…» når navnet er langt («Golfgutu Invitational høstsesongen …»). Med fixedSize
        // ble kortet bredere enn skjermen, og hele feeden kunne dras sideveis (16.10.2026).
        DDPill(source.title, tone: .chip)
            .lineLimit(1)
            .accessibilityLabel(source.title)
    }
}

/// Tiden øverst til høyre på kortene. Uten rust-prikk: den betyr bare ulest i Varsler (P2).
struct HjemTimeLabel: View {
    let time: String

    var body: some View {
        Text(time)
            .font(.ddCaption)
            .monospacedDigit()
            .foregroundStyle(Color.ddInkSecondary)
            .lineLimit(1)
            .fixedSize()
    }
}

/// Reaksjonsbrikkene, «Reager» og (etter sql/050) kommentarene.
struct HjemReactionsRow: View {
    let reactions: HomeReactions
    let actions: HjemActions

    var body: some View {
        ReactionBar(chips: reactions.chips,
                    toggle: { actions.toggle($0, reactions) },
                    pickOther: reactions.isSocial ? actions.pickEmoji.map { pick in { pick(reactions) } } : nil,
                    showWho: reactions.chips.isEmpty ? nil : actions.showWho.map { show in { show(reactions) } },
                    comments: comments)
    }

    private var comments: ReactionBarComments? {
        guard let count = reactions.commentCount, let open = actions.openComments else { return nil }
        return ReactionBarComments(count: count, open: { open(reactions.target) })
    }
}

/// Langt trykk på et kort gir hele reaksjonssettet (som i Varsler), også når ingen har reagert ennå,
/// og «Kommenter» etter sql/050.
struct HjemReactionMenu: ViewModifier {
    let target: HomeReactions?
    let actions: HjemActions

    func body(content: Content) -> some View {
        if let target {
            content.contextMenu {
                ReactionMenuItems(isMine: { actions.hasReacted($0, target) }, toggle: { actions.toggle($0, target) },
                                  pickOther: target.isSocial ? actions.pickEmoji.map { pick in { pick(target) } } : nil,
                                  showWho: target.chips.isEmpty ? nil : actions.showWho.map { show in { show(target) } })
                if target.isSocial, let open = actions.openComments {
                    Button(ReactionText.commentsLabel(target.commentCount ?? 0), systemImage: "bubble.left") {
                        open(target.target)
                    }
                }
                let who = target.chips.filter { !$0.names.isEmpty }.map { $0.emoji + " " + NorwegianList.join($0.names) }
                if !who.isEmpty, actions.showWho == nil {
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

// MARK: - Bildeoppfordring

/// «Ta et bilde av gjengen» (sql/050): kameraet åpnes rett i kveldens tråd.
struct HjemPhotoPromptCardView: View {
    let card: HomePhotoPromptCard
    let feedCard: HomeFeedCard
    /// nil: tråden er i en annen klubb enn den Hjem står i.
    let open: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                DDIconTile(systemImage: "camera.fill")
                VStack(alignment: .leading, spacing: 4) {
                    Text(card.title)
                        .font(.ddBodyEmphasis)
                        .foregroundStyle(Color.ddInk)
                    Text(card.detail)
                        .font(.ddCaption)
                        .foregroundStyle(Color.ddInkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                HjemTimeLabel(time: feedCard.time)
                    .padding(.top, 9)
            }
            .accessibilityElement(children: .combine)
            HStack(spacing: 8) {
                HjemSourcePill(source: feedCard.source)
                Spacer(minLength: 8)
                if let open {
                    Button(action: open) {
                        Label(PhotoPrompt.action, systemImage: "camera")
                    }
                    .buttonStyle(.dd(.primary, compact: true))
                    .accessibilityHint("Åpner kameraet i tråden.")
                } else {
                    Text("Åpne klubben for å dele bildet.")
                        .font(.ddCaption)
                        .foregroundStyle(Color.ddInkSecondary)
                }
            }
        }
        .ddCard()
    }
}

// MARK: - Din runde

struct HjemMyRoundCardView: View {
    let card: HomeMyRoundCard
    let feedCard: HomeFeedCard
    let share: ResultShare?
    let reactionsRow: HjemReactionsRow?
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Text("Din runde · \(feedCard.time)")
                    .ddEyebrow()
                    .lineLimit(1)
                Spacer(minLength: 8)
                HjemSourcePill(source: feedCard.source)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(card.title)
                    .font(.ddTitleSmall)
                    .foregroundStyle(Color.ddForestInk)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle = card.subtitle {
                    Text(subtitle)
                        .font(.ddCaption)
                        .foregroundStyle(Color.ddInkSecondary)
                }
            }
            .accessibilityElement(children: .combine)
            // Store tekststørrelser: plassen under poengene, ikke klemt ved siden av.
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                : AnyLayout(HStackLayout(alignment: .bottom))
            layout {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(card.points.map(String.init) ?? card.value)
                        .font(.dd(.sans, size: 52, weight: .light, relativeTo: .largeTitle))
                        .monospacedDigit()
                        .foregroundStyle(Color.ddInk)
                    if card.points != nil {
                        Text(card.unit)
                            .font(.ddCallout)
                            .foregroundStyle(Color.ddInkSecondary)
                    }
                }
                if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }
                VStack(alignment: typeSize.isAccessibilitySize ? .leading : .trailing, spacing: 2) {
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
            // Slagtallet med form (dobbel sirkel for eagle og bedre), som på scorekortet (planen 1.2, 4.1).
            HStack(alignment: .top, spacing: 12) {
                // Fargen følger bragden (eagle og bedre, birdie, shank); formen regnes fra brutto mot par.
                ScoreBadge(strokes: card.strokes, par: card.par, name: HjemDisplay.featScoreName(card.kind), size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(HjemDisplay.featTitle(card))
                        .font(.ddBodyEmphasis)
                        .foregroundStyle(Color.ddInk)
                    Text(HjemDisplay.featLine(card))
                        .font(.ddCaption)
                        .foregroundStyle(Color.ddInkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 2)
                .frame(maxWidth: .infinity, alignment: .leading)
                HjemTimeLabel(time: feedCard.time)
                    .padding(.top, 4)
            }
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
                HjemTimeLabel(time: feedCard.time)
                    .padding(.top, 9)
            }
            .accessibilityElement(children: .combine)
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

/// En rad i minitabellen: plass, navn, ▲/▼ og poeng. Du har «Deg»-merket og er uthevet (`youRow`).
struct HjemMiniTableRow: View {
    let row: HomeTableRow
    @ScaledMetric(relativeTo: .caption) private var placeMetric: CGFloat = 22

    var body: some View {
        HStack(spacing: 10) {
            Text("\(row.place).")
                .font(.ddCaption)
                .monospacedDigit()
                .foregroundStyle(Color.ddInkSecondary)
                .frame(width: min(placeMetric, 40), alignment: .leading)
            HStack(spacing: 6) {
                Text(row.name)
                    .font(row.isMe ? .dd(.sans, size: 16, weight: .semibold, relativeTo: .body) : .ddBody)
                    .foregroundStyle(Color.ddForestInk)
                    .lineLimit(1)
                if row.isMe { DDYouBadge() }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // ▲1 i skog, ▼1 i rust, – når du står stille (planen V4 og 4.1).
            let move = row.move ?? 0
            Text(row.moveText ?? "–")
                .font(.dd(.sans, size: 13, weight: .semibold, relativeTo: .footnote))
                .monospacedDigit()
                .foregroundStyle(move > 0 ? Color.ddForestInk : move < 0 ? Color.ddRustText : Color.ddInkSecondary)
                .frame(minWidth: 28, alignment: .trailing)
                .accessibilityLabel(move > 0 ? "opp \(move)" : move < 0 ? "ned \(-move)" : "ingen endring")
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
                RoundedRectangle(cornerRadius: DDRadius.row, style: .continuous).fill(Color.ddYouRow)
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
    var openComments: ((SocialTarget) -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            ForEach(lines) { line in
                if line.id != lines.first?.id { DDDivider() }
                HStack(alignment: .top, spacing: 12) {
                    DDIconTile(systemImage: line.symbol)
                    VStack(alignment: .leading, spacing: 4) {
                        // Tekst, kontekst og tid leses som én linje; reaksjonene og knappen står for seg.
                        VStack(alignment: .leading, spacing: 4) {
                            Text(line.text)
                                .font(.ddBody)
                                .foregroundStyle(Color.ddInk)
                                .lineSpacing(3)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(line.context)
                                .font(.ddCaption)
                                .foregroundStyle(Color.ddInkSecondary)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityValue(line.time)
                        if let reactions = line.reactions, let row = reactionsRow(reactions) {
                            row.padding(.top, 4)
                        }
                        if let target = line.opens, let openComments {
                            Button("Se kommentarene") { openComments(target) }
                                .font(.dd(.sans, size: 15, weight: .semibold, relativeTo: .body))
                                .foregroundStyle(Color.ddForestInk)
                                .frame(minHeight: 44)
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    HjemTimeLabel(time: line.time)
                        .padding(.top, 9)
                        .accessibilityHidden(true)
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
