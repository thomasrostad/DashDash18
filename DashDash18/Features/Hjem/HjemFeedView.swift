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
    var openRound: () -> Void = {}
    var openEvening: () -> Void = {}
    var answer: (SignupStatus) -> Void = { _ in }
    var undoAnswer: () -> Void = {}
    var toggle: (ActivityReaction, HomeReactions) -> Void = { _, _ in }
    var hasReacted: (ActivityReaction, HomeReactions) -> Bool = { r, t in t.chips.contains { $0.reaction == r && $0.isMine } }
    var openTable: (UUID) -> Void = { _ in }
    var share: (UUID) -> ResultShare? = { _ in nil }
    /// Arrangørens knapp for neste steg på «Neste kveld» (fase 21). nil: ingen knapp.
    var organizer: HjemOrganizerStep?
    /// «Inviter spillere» for arrangøren mens troppen er liten. nil: ikke noe kort.
    var invite: HjemInvite?
}

/// Hjem fra topp til bunn (retning 1a med 1b-oppsummeringen): filterpillene, «Siden sist» når noe
/// har skjedd, «Pågår nå», «Neste kveld» og feeden i I dag · I går · Tidligere.
struct HjemFeedView: View {
    let feed: HomeFeed
    var state: HomeFeedModel.LoadState = .loaded
    /// «Svaret ditt: Kommer» mens svaret kan angres.
    var pendingAnswer: String?
    var answerError: String?
    var actions = HjemActions()
    var onRetry: () -> Void = {}
    /// Skjermprøven av nedre del (`hjembunn`) starter nederst.
    var scrollAnchor: UnitPoint?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
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
        }
        .defaultScrollAnchor(scrollAnchor)
        .animation(.default, value: feed.filter)
    }

    @ViewBuilder
    private var top: some View {
        // Klubben, som «Neste kveld»: ikke under «Løse runder».
        if let invite = actions.invite, HjemDisplay.showsEvening(filter: feed.filter) {
            HjemInviteCard(invite: invite)
        }
        if let summary = feed.summary {
            HjemSummaryCard(summary: summary)
        }
        if let live = feed.live, HjemDisplay.showsLive(live, filter: feed.filter) {
            DDSectionLabel("Pågår nå")
                .padding(.top, 6)
            HjemLiveCard(live: live, onContinue: actions.openRound)
        }
        if let evening = feed.evening, HjemDisplay.showsEvening(filter: feed.filter) {
            HjemEveningCard(evening: evening, pendingText: pendingAnswer, error: answerError,
                            onOpen: actions.openEvening, onAnswer: actions.answer, onUndo: actions.undoAnswer,
                            organizer: actions.organizer)
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
            VStack(spacing: 12) {
                Label("Fikk ikke hentet det som har skjedd", systemImage: "wifi.exclamationmark")
                    .font(.ddBodyEmphasis)
                    .foregroundStyle(Color.ddInk)
                Text(message)
                    .font(.ddCallout)
                    .foregroundStyle(Color.ddInkSecondary)
                    .multilineTextAlignment(.center)
                Button("Prøv igjen", action: onRetry)
                    .buttonStyle(.dd(.secondary, compact: true))
            }
            .frame(maxWidth: .infinity)
            .ddCard(.empty)
            .padding(.top, DDSpacing.l)
        default:
            if feed.isEmpty {
                HjemEmptyCard(filter: feed.filter)
                    .padding(.top, DDSpacing.l)
            }
            ForEach(feed.sections) { section in
                DDSectionLabel(section.title)
                    .padding(.top, DDSpacing.l)
                ForEach(section.cards) { card in
                    HjemCardView(card: card, actions: actions)
                }
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
        case .lines(let lines):
            HjemLinesCardView(lines: lines, feedCard: card, reactionsRow: visibleRow, menu: menu)
        }
    }

    private func row(_ target: HomeReactions) -> HjemReactionsRow {
        HjemReactionsRow(reactions: target,
                         hasReacted: { actions.hasReacted($0, target) },
                         toggle: { actions.toggle($0, target) })
    }

    /// Raden bare når noen har reagert; ellers holder langt trykk (`menu`).
    private func visibleRow(_ target: HomeReactions) -> HjemReactionsRow? {
        target.chips.isEmpty ? nil : row(target)
    }

    private func menu(_ target: HomeReactions?) -> HjemReactionMenu {
        HjemReactionMenu(target: target, hasReacted: actions.hasReacted, toggle: actions.toggle)
    }
}

/// «Ingenting her ennå.» med en vennlig linje om hva som kommer.
struct HjemEmptyCard: View {
    let filter: HomeFeedFilter

    var body: some View {
        VStack(spacing: 6) {
            Text(HjemDisplay.emptyTitle)
                .font(.ddBodyEmphasis)
                .foregroundStyle(Color.ddInk)
            Text(HjemDisplay.emptyLine(filter))
                .font(.ddCallout)
                .foregroundStyle(Color.ddInkSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .ddCard(.empty)
        .accessibilityElement(children: .combine)
    }
}
