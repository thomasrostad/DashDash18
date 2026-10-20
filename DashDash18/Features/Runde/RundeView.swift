import GolfgutuCore
import Supabase
import SwiftUI

/// Føringen under runden (utbedringsplanen 4.2): fullskjerm uten fanelinje, med «Lukk føringen»,
/// tittel og bås i verktøylinja, og segmentene «Føring | Stilling | Spill».
/// Føring: hero for hullet, hullvelgeren og hullkortet, med «Lagre hull» i bunnlinja.
/// Stilling: «Bayen nå» (eller matchene når runden avgjøres hull for hull).
/// Spill: matcher, konkurranser og spill på runden (skins, wolf og de andre).
struct RundeView: View {
    @Environment(\.dayTerm) private var dayTerm
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: RundeModel
    @State private var scorecardFor: ScorecardTarget?
    /// Valgt segment. nil: det skjermen åpner på (`RundeSegment.initial`).
    @State private var chosenSegment: RundeSegment?
    /// Spillene i runden, hentet her så segmentet kan vise hvor mange det er.
    @State private var games: GamesModel?
    @State private var showsRules = false
    /// Konflikten arket viser (K6/6.3).
    @State private var conflictSheet: HoleConflictRow?
    /// «Ferdig? Avslutt runden» (`RoundEndPrompt`): bekreftelsen, låsingen og feilen.
    @State private var confirmsEnd = false
    @State private var isEnding = false
    @State private var endError: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            if let game = model.game {
                VStack(alignment: .leading, spacing: 14) {
                    if game.status == .locked, model.looseContext != nil {
                        DDInfoStripe("Runden er avsluttet. Resultatet står under, og du kan dele det.")
                    }
                    DDSegmentedControl([
                        (RundeSegment.scoring, "Føring"),
                        (RundeSegment.standing, "Stilling"),
                        (RundeSegment.extras, RundeSegment.extrasTitle(count: extrasCount(game))),
                    ], selection: segmentBinding(game))
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .accessibilityLabel("Visning")
                    switch segment(game) {
                    case .scoring: scoring(game)
                    case .standing: standing(game)
                    case .extras: extras(game)
                    }
                }
                .padding(.horizontal, DDSpacing.gutter)
                .padding(.vertical, DDSpacing.l)
                .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: model.currentHole)
            }
        }
        .refreshable { await model.load() }
        .safeAreaInset(edge: .bottom) {
            if let game = model.game, segment(game) == .scoring, !model.needsParConfirmation,
               let prompt = endLinePrompt {
                RundeAvslutningLinje(
                    prompt: prompt,
                    isEnding: isEnding,
                    onScorecard: game.isPlaying(model.viewer.memberID)
                        ? { scorecardFor = ScorecardTarget(memberID: model.viewer.memberID) } : nil,
                    onEnd: { confirmsEnd = true }
                )
            } else if let game = model.game, segment(game) == .scoring, !model.needsParConfirmation,
               let card = model.card, card.action != .none {
                FoeringBunnlinje(
                    card: card,
                    isSaving: model.isSaving,
                    error: model.saveError,
                    sync: game.syncStatus(viewer: model.viewer, pending: model.pendingHoles),
                    onSave: { Task { await model.saveCurrentHole() } },
                    onGoTo: { model.goTo(hole: $0) },
                    onScorecard: { scorecardFor = ScorecardTarget(memberID: model.viewer.memberID) }
                )
            }
        }
        .navigationTitle(scoringTitle.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .tabBar)
        .hidesLiveRoundBar()
        .ddNavigationChrome()
        .toolbar { toolbar }
        .sheet(item: $scorecardFor) { target in
            if let game = model.game {
                ScorekortSheet(game: game, memberID: target.memberID)
            }
        }
        .sheet(item: $conflictSheet) { conflict in
            if let game = model.game {
                MarkorKonfliktArk(
                    title: "Hull \(game.holeNumber(conflict.holeIndex)) · \(game.name(conflict.memberID))",
                    options: model.options(conflict)
                ) { (strokes: Int) async throws(DataError) in
                    try await model.resolve(conflict, strokes: strokes)
                }
            }
        }
        .roundEndConfirmation(isPresented: $confirmsEnd, offer: model.endOffer, perform: endRound)
        .alert("Runden ble ikke avsluttet", isPresented: Binding(
            get: { endError != nil }, set: { if !$0 { endError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(endError ?? "")
        }
        .sheet(isPresented: $showsRules) {
            if let game = model.game {
                RundeReglerArk(rules: game.rules)
            }
        }
        .overlay {
            if let celebration = model.celebration {
                FeiringOverlay(celebration: celebration) {
                    model.celebration = nil
                }
            }
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.32), value: model.celebration?.id)
        .task(id: model.game?.roundID) { await loadGames() }
        // Nye scorer og låsing: hent markeringene og oppgjøret på nytt.
        .task(id: gamesReloadKey) { await games?.load() }
    }

    // MARK: Verktøylinja

    private var scoringTitle: ScoringTitle {
        model.game?.scoringTitle(viewer: model.viewer)
            ?? ScoringTitle(title: model.looseContext == nil ? DayTerm.capitalized(dayTerm.the) : "Runden", subtitle: nil)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.down")
            }
            .tint(Color.ddForestInk)
            .accessibilityLabel("Lukk føringen")
        }
        ToolbarItem(placement: .principal) {
            VStack(spacing: 1) {
                Text(scoringTitle.title)
                    .font(.dd(.sans, size: 17, weight: .semibold, relativeTo: .headline))
                    .foregroundStyle(Color.ddInk)
                if let subtitle = scoringTitle.subtitle {
                    Text(subtitle)
                        .font(.ddStatus)
                        .foregroundStyle(Color.ddInkSecondary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                if let game = model.game {
                    if game.isPlaying(model.viewer.memberID) {
                        Button("Scorekortet ditt", systemImage: "list.number") {
                            scorecardFor = ScorecardTarget(memberID: model.viewer.memberID)
                        }
                    }
                    Button("Reglene i runden", systemImage: "info.circle") { showsRules = true }
                    if model.endOffer != nil {
                        Button(RoundEndOffer.menuTitle, systemImage: "flag.checkered") { confirmsEnd = true }
                            .disabled(isEnding)
                    }
                    if !game.snapshot.players.isEmpty {
                        ResultShareButton(share: game.share(viewer: model.viewer))
                    }
                }
                Button("Hent på nytt", systemImage: "arrow.clockwise") { Task { await model.load() } }
            } label: {
                Image(systemName: "ellipsis")
            }
            .tint(Color.ddForestInk)
            .accessibilityLabel("Mer")
        }
    }

    // MARK: Avslutningen

    /// Avslutningslinja i stedet for «Lagre hull»: når kortet er ferdig og ingenting venter på å bli
    /// lagret på hullet du står på (en retting vises som vanlig).
    private var endLinePrompt: RoundEndPrompt? {
        guard let prompt = model.endPrompt else { return nil }
        if let card = model.card, case .save = card.action { return nil }
        return prompt
    }

    /// Låser runden. En løs runde blir stående med resultatet; en klubbrunde går ikke lenger, så
    /// føringen lukkes og Hjem henter på nytt (runden åpnes ikke igjen).
    private func endRound() {
        isEnding = true
        endError = nil
        Task {
            defer { isEnding = false }
            do throws(DataError) {
                try await model.endRound()
            } catch {
                endError = error.message
                return
            }
            if model.looseContext == nil {
                dismiss()
                await model.load()
            }
        }
    }

    // MARK: Segmentene

    private func segment(_ game: RoundGame) -> RundeSegment {
        chosenSegment ?? RundeSegment.initial(isLocked: game.status == .locked, hasCard: model.card != nil)
    }

    private func segmentBinding(_ game: RoundGame) -> Binding<RundeSegment> {
        Binding(get: { segment(game) }, set: { chosenSegment = $0 })
    }

    /// Matcher (når de ikke er stillingen), konkurranser og spill på runden.
    private func extrasCount(_ game: RoundGame) -> Int {
        let matches = (!game.isDecidedHoleByHole && game.matchCard(viewer: model.viewer) != nil) ? 1 : 0
        let boards = RoundCompetitionBoard.boards(game).count + (TeamVsTeam.result(game) == nil ? 0 : 1)
        let spill = games?.roundID == game.roundID ? (games?.input.games.count ?? 0) : 0
        return matches + boards + spill
    }

    @ViewBuilder
    private func scoring(_ game: RoundGame) -> some View {
        if game.status == .locked, model.looseContext != nil {
            if let card = model.card {
                HullprikkerView(dots: game.dots(currentHole: model.currentHole, viewer: model.viewer,
                                                pending: model.pendingHoles)) { model.goTo(hole: $0) }
                HullHeroView(card: card) { model.goTo(hole: $0) }
                hullkort(card)
            }
        } else if model.needsParConfirmation {
            ParBekreftelseCard(game: game, canConfirm: model.canConfirmPar) {
                try await model.confirmPar()
            }
        } else {
            playing(game)
        }
    }

    @ViewBuilder
    private func standing(_ game: RoundGame) -> some View {
        if game.isDecidedHoleByHole, let matches = game.matchCard(viewer: model.viewer) {
            MatchkortSection(card: matches)
        }
        BayenNaaListe(rows: game.bayenNaa(viewer: model.viewer), term: game.groupTerm) { member in
            scorecardFor = ScorecardTarget(memberID: member)
        }
        if model.hidesLastHoles {
            DDInfoStripe(HiddenHoles.note + ".")
        }
        // Leverte kort (sql/057): arrangøren kan åpne dem igjen.
        if model.viewer.isOrganizer, game.status == .active, case let cards = game.submittedCards(), !cards.isEmpty {
            SubmittedCardsSection(model: model, cards: cards)
        }
        if model.looseContext != nil {
            LooseRoundActions(model: model)
        }
        // «Følg medspillerne» når runden er ferdig (sql/054).
        if game.status == .locked, let follow = followAccess {
            FollowCoPlayersSection(client: follow.client, userID: follow.userID, snapshot: game.snapshot)
                .id(game.snapshot.round.id)
        }
    }

    @ViewBuilder
    private func extras(_ game: RoundGame) -> some View {
        if !game.isDecidedHoleByHole, let matches = game.matchCard(viewer: model.viewer) {
            MatchkortSection(card: matches)
        }
        CompetitionBoardsSection(game: game)
        if GamesFeature.isEnabled, let games, games.roundID == game.roundID {
            SpillSeksjon(model: games, game: game, hole: model.currentHole, viewer: model.viewer,
                         me: model.statsAccess?.userID)
        }
        if let context = model.clubContext, let eventID = game.snapshot.round.eventID {
            KveldExtrasButtons(model: KveldExtrasModel(context: context, eventID: eventID))
                .id(eventID)
        }
        // Veddemål i turneringen runden teller i, eller i rundens egen bank (sql/052).
        if let bets = betsAccess {
            // Eieren av en løs runde slår veddemål på for runden (egen bank).
            VeddKnapp(game: game, me: model.viewer.memberID, client: bets.client, viewer: bets.viewer,
                      ownsRound: model.looseContext.map { game.snapshot.loose?.ownerID == $0.userID } ?? false)
                .id(game.snapshot.round.id)
        }
    }

    // MARK: Spillene

    private func loadGames() async {
        guard GamesFeature.isEnabled, let game = model.game, let access = model.statsAccess else { return }
        if games?.roundID == game.roundID { return }
        let fresh = GamesModel(client: access.client, roundID: game.roundID)
        games = fresh
        await fresh.load()
    }

    private var gamesReloadKey: String {
        guard let game = model.game else { return "" }
        return "\(game.snapshot.scores.count)-\(game.status.rawValue)-\(model.currentHole)"
    }

    /// Klienten og deg for veddemålene: klubben som er valgt, eller profilen i en løs runde.
    private var betsAccess: (client: SupabaseClient, viewer: BetViewer)? {
        if let context = model.clubContext { return (context.client, context.betViewer) }
        if let loose = model.looseContext { return (loose.client, BetViewer(userID: loose.userID)) }
        return nil
    }

    /// Klienten og innloggingen for «Følg medspillerne».
    private var followAccess: (client: SupabaseClient, userID: UUID)? {
        if let context = model.clubContext { return (context.client, context.user.id) }
        if let loose = model.looseContext { return (loose.client, loose.userID) }
        return nil
    }

    // MARK: Føringen

    private func hullkort(_ card: HoleCard) -> some View {
        HullkortView(
            card: card,
            isPending: model.pendingHoles.contains(card.holeIndex),
            onStep: { model.step($0, member: $1) },
            onConfirm: { model.confirm(member: $0) },
            onScorecard: { scorecardFor = ScorecardTarget(memberID: $0 ?? model.viewer.memberID) },
            conflicts: MarkerConflicts.members(onHole: card.holeIndex, in: model.conflicts),
            onConflict: { member in
                conflictSheet = model.conflict(hole: card.holeIndex, member: member)
            }
        )
    }

    @ViewBuilder
    private func playing(_ game: RoundGame) -> some View {
        if game.hasBays, game.bay(of: model.viewer.memberID) == nil, let line = game.markerLine(for: model.viewer) {
            // «Du står ikke i noen bås …»: resten av markørlinja står i verktøylinja.
            DDInfoStripe(line)
        }
        if let text = model.rejectedText {
            AvvisteHullStripe(text: text) { model.acknowledgeRejectedHoles() }
        }
        if let text = MarkerConflicts.stripeText(model.conflicts, holeNumber: game.holeNumber, name: game.name) {
            MarkorKonfliktStripe(text: text) {
                guard let conflict = MarkerConflicts.first(model.conflicts, preferring: model.currentHole) else { return }
                model.goTo(hole: conflict.holeIndex)
                conflictSheet = conflict
            }
        }
        if let stripe = game.bayStripe(currentHole: model.currentHole, viewer: model.viewer) {
            DDInfoStripe(tone: .sun) {
                HStack {
                    Text(stripe.text)
                    Spacer(minLength: 8)
                    Button(stripe.button) { model.goTo(hole: stripe.hole) }
                        .buttonStyle(.dd(.primary, compact: true))
                }
            }
            .accessibilityElement(children: .contain)
        }
        if let card = model.card {
            HullHeroView(card: card) { model.goTo(hole: $0) }
        }
        HullprikkerView(dots: game.dots(currentHole: model.currentHole, viewer: model.viewer,
                                        pending: model.pendingHoles)) { model.goTo(hole: $0) }
        if let card = model.card {
            hullkort(card)
            // Låst kort etter levering (sql/057).
            if let submission = model.cardSubmission {
                CardSubmissionSection(model: model, submission: submission)
            }
            if StatsFeature.isEnabled, game.isPlaying(model.viewer.memberID), let par = game.statsPar(card.holeIndex),
               let access = model.statsAccess {
                HoleStatsSlot(client: access.client, userID: access.userID, roundID: game.roundID,
                              memberID: model.viewer.memberID, holeIndex: card.holeIndex, par: par)
            }
        } else {
            DDInfoStripe("Du er ikke med i denne runden. Du ser stillingen under «Stilling».")
        }
        let lines = game.holeMatchLines(hole: model.currentHole, viewer: model.viewer)
        if !lines.isEmpty {
            HullMatchLinjer(lines: lines)
        }
        ForEach([SideClaimKind.drive, .kp], id: \.self) { kind in
            if let box = game.sidePrizeBox(kind, hole: model.currentHole, viewer: model.viewer) {
                SidepremieBoks(
                    box: box,
                    viewer: model.viewer.memberID,
                    names: game.snapshot.names,
                    existing: { game.sideClaim(kind, for: $0)?.meters },
                    onSubmit: { try await model.submitSideClaim(kind, member: $0, text: $1) },
                    onDelete: { try await model.deleteSideClaim($0) }
                )
            }
        }
    }
}

/// Reglene i runden, fra ⋯-menyen i føringen.
private struct RundeReglerArk: View {
    let rules: Ruleset
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            DDForm {
                RulesetSummarySection(rules: rules, title: "Reglene i runden")
            }
            .navigationTitle("Reglene")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                DDConfirmToolbarItem {
                    Button("Ferdig") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

struct ScorecardTarget: Identifiable {
    let memberID: UUID
    var id: UUID { memberID }
}
