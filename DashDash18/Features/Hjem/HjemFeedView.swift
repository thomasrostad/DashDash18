import SwiftUI

/// Arrangørens knapp på «Neste kveld»: samme ord som neste steg på arrangørsiden og Kvelden.
struct HjemOrganizerStep {
    let title: String
    var isBusy = false
    /// Hva knappen gjør, for VoiceOver: «Åpner oppsettet av runden.»
    var hint: String
    let perform: () -> Void
}

/// Det Hjem kan gjøre fra kortene. `HjemView` kobler dem til modellene og navigasjonen;
/// skjermprøvene lar dem stå tomme.
struct HjemActions {
    var select: (HomeFeedFilter) -> Void = { _ in }
    /// Runden som pågår (baren i feeden på iOS 26.0; ellers står den over fanelinja).
    var openRound: (HomeLive) -> Void = { _ in }
    var openEvening: () -> Void = {}
    var answer: (SignupStatus) -> Void = { _ in }
    var toggle: (String, HomeReactions) -> Void = { _, _ in }
    var hasReacted: (String, HomeReactions) -> Bool = { e, t in t.chips.contains { $0.emoji == e && $0.isMine } }
    /// «Annen emoji …» (sql/050).
    var pickEmoji: ((HomeReactions) -> Void)?
    /// «Hvem har reagert».
    var showWho: ((HomeReactions) -> Void)?
    /// Kommentarene på en hendelse eller melding (sql/050).
    var openComments: ((SocialTarget) -> Void)?
    /// «Ta bilde» på bildeoppfordringen. nil (eller nil fra funksjonen): tråden er ikke her.
    var openPhotoPrompt: ((HomePhotoPromptCard) -> (() -> Void)?)?
    /// Eldre linjer (`feed_page`). nil: ingen sider.
    var loadMore: (() -> Void)?
    var openTable: (UUID) -> Void = { _ in }
    var share: (UUID) -> ResultShare? = { _ in nil }
    /// Arrangørens knapp for neste steg på «Neste kveld» (fase 21). nil: ingen knapp.
    var organizer: HjemOrganizerStep?
    /// «Inviter spillere» for arrangøren mens troppen er liten. nil: ikke noe kort.
    var invite: HjemInvite?
    /// «Start en runde» i den tomme feeden (Spill-fanen). nil: ingen Spill-fane.
    var startRound: (() -> Void)?
}

/// Hjem fra topp til bunn (utbedringsplanen V1 og 4.1): filterpillene, «Neste kveld» som hero og
/// feeden i I dag · I går · Tidligere. Runden som pågår står i baren over fanelinja.
struct HjemFeedView: View {
    let feed: HomeFeed
    var state: HomeFeedModel.LoadState = .loaded
    var answerError: String?
    var actions = HjemActions()
    var onRetry: () -> Void = {}
    /// Skjermprøven av nedre del (`hjembunn`) starter nederst.
    var scrollAnchor: UnitPoint?
    var isLoadingMore = false
    /// «Klubben/Følger» (sql/054) øverst i innholdet. nil: ingen velger.
    var tabPicker: Binding<HjemFeedTab>?
    @Environment(\.liveBarInFeed) private var liveBarInFeed

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let tabPicker {
                    HjemFeedTabPicker(tab: tabPicker)
                }
                if feed.pills.count > 1 {
                    HjemFilterBar(pills: feed.pills, select: actions.select)
                }
                VStack(alignment: .leading, spacing: DDSpacing.cardGap) {
                    top
                    sections
                }
                .padding(.horizontal, DDSpacing.gutter)
                .padding(.top, 12)
                .padding(.bottom, DDSpacing.xxl)
            }
            // Aldri bredere enn skjermen: ble ett kort for bredt (sett etter en avsluttet runde 16.10),
            // kunne hele feeden dras sideveis.
            .containerRelativeFrame(.horizontal)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .defaultScrollAnchor(scrollAnchor)
        .animation(.default, value: feed.filter)
    }

    @ViewBuilder
    private var top: some View {
        // Klubben, som «Neste kveld»: ikke under «Løse runder».
        if let invite = actions.invite, HjemDisplay.showsEvening(filter: feed.filter) {
            HjemInviteCard(invite: invite)
        }
        // iOS 26.0 har ikke tilbehør som kan skrus av: der står baren her (`HjemLiveAccessory`).
        let live = feed.live.filter { HjemDisplay.showsLive($0, filter: feed.filter) }
        if liveBarInFeed, !live.isEmpty {
            HjemLiveRoundBar(live: live, open: actions.openRound)
                .padding(.vertical, 4)
                .glassEffect(.regular, in: .capsule)
        }
        if let evening = feed.evening, HjemDisplay.showsEvening(filter: feed.filter) {
            HjemEveningCard(evening: evening, error: answerError, onOpen: actions.openEvening,
                            onAnswer: actions.answer, organizer: actions.organizer)
        }
    }

    @ViewBuilder
    private var sections: some View {
        switch state {
        case .loading where feed.isEmpty:
            ProgressView("Henter det som har skjedd …")
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
        case .failed(let message) where feed.isEmpty:
            ContentUnavailableView {
                Label("Fikk ikke hentet det som har skjedd", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Prøv igjen", action: onRetry)
                    .buttonStyle(.dd(.secondary, compact: true))
            }
            .padding(.top, DDSpacing.l)
        default:
            if feed.isEmpty {
                HjemEmptyView(filter: feed.filter, startRound: actions.startRound)
                    .padding(.top, DDSpacing.l)
            }
            ForEach(feed.sections) { section in
                DDSectionLabel(section.title)
                    .padding(.top, DDSpacing.l)
                ForEach(section.cards) { card in
                    HjemCardView(card: card, actions: actions)
                }
            }
            if let loadMore = actions.loadMore, !feed.isEmpty {
                HjemLoadMore(isLoading: isLoadingMore, load: loadMore)
            }
        }
    }
}

/// Ett kort i feeden, etter typen.
struct HjemCardView: View {
    let card: HomeFeedCard
    let actions: HjemActions

    var body: some View {
        switch card.content {
        case .myRound(let c):
            HjemMyRoundCardView(card: c, feedCard: card, share: actions.share(c.roundID),
                                reactionsRow: c.reactions.flatMap(visibleRow))
                .modifier(menu(c.reactions))
        case .feat(let c):
            // Bragden har alltid reaksjonsraden (designet), også før noen har reagert.
            HjemFeatCardView(card: c, feedCard: card, reactionsRow: c.reactions.map(row))
                .modifier(menu(c.reactions))
        case .table(let c):
            HjemTableCardView(card: c, feedCard: card, reactionsRow: c.reactions.flatMap(visibleRow)) {
                actions.openTable(c.competitionID)
            }
            .modifier(menu(c.reactions))
        case .photoPrompt(let c):
            HjemPhotoPromptCardView(card: c, feedCard: card, open: actions.openPhotoPrompt?(c))
                .modifier(menu(c.reactions))
        case .lines(let lines):
            HjemLinesCardView(lines: lines, feedCard: card, reactionsRow: visibleRow, menu: menu,
                              openComments: actions.openComments)
        }
    }

    private func row(_ target: HomeReactions) -> HjemReactionsRow {
        HjemReactionsRow(reactions: target, actions: actions)
    }

    /// Raden bare når noen har reagert eller kommentert; ellers holder langt trykk (`menu`).
    private func visibleRow(_ target: HomeReactions) -> HjemReactionsRow? {
        target.chips.isEmpty && (target.commentCount ?? 0) == 0 ? nil : row(target)
    }

    private func menu(_ target: HomeReactions?) -> HjemReactionMenu {
        HjemReactionMenu(target: target, actions: actions)
    }
}

/// Nederst i feeden: henter neste side når den kommer fram, og har en knapp om det stopper.
struct HjemLoadMore: View {
    let isLoading: Bool
    let load: () -> Void

    var body: some View {
        HStack {
            Spacer()
            if isLoading {
                ProgressView("Henter eldre …")
            } else {
                Button("Vis eldre", action: load)
                    .buttonStyle(.dd(.secondary, compact: true))
            }
            Spacer()
        }
        .padding(.top, DDSpacing.l)
        .onAppear(perform: load)
    }
}

/// Tom feed (utbedringsplanen V13): systemets tomtilstand med én handling, «Start en runde».
struct HjemEmptyView: View {
    let filter: HomeFeedFilter
    var startRound: (() -> Void)?

    var body: some View {
        ContentUnavailableView {
            Label(HjemDisplay.emptyTitle, systemImage: HjemDisplay.emptySymbol(filter))
        } description: {
            Text(HjemDisplay.emptyLine(filter))
        } actions: {
            if let startRound {
                Button("Start en runde", action: startRound)
                    .buttonStyle(.dd(.primary, compact: true))
            }
        }
    }
}
