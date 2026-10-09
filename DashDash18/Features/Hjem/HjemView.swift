import GolfgutuCore
import SwiftUI

/// Hvor Hjem kan gå videre.
enum HjemRoute: Hashable {
    /// Runden som går (før Kveld-fanen viste den selv).
    case round
    /// Kveld-skjermen: hvem som kommer, tråden, tipsen og purringen.
    case evening
    /// Kvelden for arrangøren (fase 21): neste steg, påmelding, runder og avslutning.
    case kvelden(UUID)
    case competition(UUID)
}

/// Ber Hjem åpne runden som går (arrangørsidens «Gå til runden»). RootView eier den.
@Observable
final class HjemRouter {
    private(set) var roundRequest = 0

    func showRound() { roundRequest += 1 }
}

/// Hjem-fanen (fase 19): feeden, med «Pågår nå» og «Neste kveld» øverst. Eier modellene for runden
/// og kvelden i klubben, så Hjem gjør alt Kveld-fanen gjorde.
struct HjemView: View {
    let home: HomeFeedModel?
    var router: HjemRouter?
    @Environment(\.clubContext) private var context

    var body: some View {
        if let context, let home {
            HjemClubContent(context: context, home: home, router: router)
        } else {
            ProgressView("Henter Hjem …")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct HjemClubContent: View {
    let home: HomeFeedModel
    let router: HjemRouter?
    let context: ClubContext
    @State private var round: RundeModel
    @State private var kveld: KveldModel
    /// Arrangørens runder og kvelder, for knappen for neste steg. Hentes bare for arrangører.
    @State private var admin: RundeAdminModel
    @State private var adminActions: RoundAdminActions
    @State private var route: HjemRoute?
    /// Runden er bedt om før den var hentet.
    @State private var wantsRound = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.selectTab) private var selectTab

    init(context: ClubContext, home: HomeFeedModel, router: HjemRouter?) {
        self.context = context
        self.home = home
        self.router = router
        _round = State(initialValue: RundeModel(context: context))
        _kveld = State(initialValue: KveldModel(context: context))
        let admin = RundeAdminModel(context: context)
        _admin = State(initialValue: admin)
        _adminActions = State(initialValue: RoundAdminActions(model: admin))
    }

    var body: some View {
        HjemFeedView(feed: home.feed, state: home.state,
                     pendingAnswer: kveld.pendingAnswer.map { SignupUndo.text($0.status) },
                     answerError: kveld.answerError, actions: actions, onRetry: reload)
            .refreshable {
                async let a: Void = home.load()
                async let b: Void = kveld.load()
                async let c: Void = round.load()
                async let d: Void = loadAdmin()
                _ = await (a, b, c, d)
            }
            .navigationDestination(item: $route) { destination($0) }
            // «Sett opp runden» og «Fortsett kladd» åpner oppsettet rett fra Hjem.
            .roundAdminActions(adminActions)
            .task { await loadAdmin() }
            .onChange(of: route) { _, route in if route == nil { Task { await loadAdmin() } } }
            .alert("Noe gikk galt", isPresented: Binding(
                get: { home.errorMessage != nil },
                set: { if !$0 { home.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(home.errorMessage ?? "")
            }
            // Runden: som RundeGate gjorde for Kveld-fanen.
            .followsRound(round)
            .onChange(of: liveInput, initial: true) { _, live in home.live = live }
            .onChange(of: round.hasRound) { _, has in if has { consumeRoundRequest() } }
            .onChange(of: router?.roundRequest) { _, _ in
                wantsRound = true
                consumeRoundRequest()
            }
            // Kvelden: henting, realtime og angre-vinduet.
            .task { await kveld.load() }
            .task { await kveld.followChanges() }
            .onChange(of: eveningInput, initial: true) { _, evening in home.evening = evening }
            // Feeden: realtime stoppes når Hjem forsvinner, og «sist sett» flyttes, så «Siden sist»
            // betyr siden sist. Ved retur hentes alt på nytt.
            .task {
                home.wantsRealtime = true
                await home.load()
            }
            .onAppear { consumeRoundRequest() }
            .onDisappear {
                home.markSeen()
                home.wantsRealtime = false
                Task { await home.stopRealtime() }
            }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .active:
                    home.reopen()
                    Task { await home.load() }
                    Task { await kveld.load() }
                    Task { await loadAdmin() }
                case .background:
                    home.markSeen()
                    // Legges appen bort i angre-vinduet, sendes svaret nå (`angreSendAlle`).
                    Task { await kveld.flush() }
                default:
                    break
                }
            }
    }

    // MARK: Inndata til feeden

    private var liveInput: HomeLiveInput? {
        guard let snapshot = round.snapshot, snapshot.round.status == .active else { return nil }
        return HomeLiveInput(snapshot: snapshot, viewer: round.viewer)
    }

    private var eveningInput: HomeEveningInput? {
        guard let event = kveld.event else { return nil }
        return HomeEveningInput(clubID: context.clubID, clubName: context.membership.club.name, event: event,
                                today: kveld.today, answer: kveld.mySignup?.status,
                                coming: kveld.summary.yes.count, isOrganizer: kveld.isOrganizer)
    }

    // MARK: Handlinger

    private var actions: HjemActions {
        HjemActions(
            select: { home.filter = $0 },
            openRound: { route = .round },
            openEvening: { route = .evening },
            answer: { kveld.answer($0) },
            undoAnswer: { kveld.undoAnswer() },
            toggle: { reaction, target in Task { await home.toggle(reaction, on: target) } },
            hasReacted: { home.hasReacted($0, on: $1) },
            openTable: openTable,
            share: { home.share(round: $0) },
            organizer: organizerStep,
            invite: invite
        )
    }

    /// «Inviter spillere» mens troppen er liten (`ClubInvite.homeCardRosterLimit`). Troppen telles
    /// fra arrangørens henting, så kortet vises ikke før den er klar.
    private var invite: HjemInvite? {
        let club = context.membership.club
        let active = admin.state == .loaded ? admin.members.count : nil
        guard let invite = TroppInvite.invite(club.joinCode),
              ClubInvite.showsHomeCard(isOrganizer: context.isOrganizer, activeMembers: active, hasCode: true),
              let active else { return nil }
        return HjemInvite(clubName: club.name, invite: invite, activeMembers: active)
    }

    // MARK: Arrangøren

    private func loadAdmin() async {
        guard context.isOrganizer else { return }
        await admin.load()
    }

    /// Knappen for neste steg på «Neste kveld», med samme ord som på arrangørsiden. Oppsettet og
    /// runden åpnes rett herfra; purring og avslutning åpner Kvelden, der de spør før de gjør noe.
    /// «Kveld» eller «spilledag» for hovedturneringen (`DayTerm`). Arrangørens henting har regelsettet.
    private var dayTerm: DayTerm { admin.tournament?.rules.day ?? .evening }

    private var organizerStep: HjemOrganizerStep? {
        guard context.isOrganizer, let event = kveld.event else { return nil }
        let openKvelden = { route = .kvelden(event.id) }
        guard admin.state == .loaded else {
            return HjemOrganizerStep(title: DayTerm.capitalized(dayTerm.the), isBusy: admin.state == .loading,
                                     hint: "Åpner \(dayTerm.the).", perform: openKvelden)
        }
        let progress = Tonight.progress(event: event, rounds: admin.allRounds, activeRound: admin.activeRound,
                                        activeComplete: admin.activeComplete,
                                        notAnswered: Nudge.targets(kveld.summary).count, today: kveld.today)
        let title = progress.action.buttonTitle(dayTerm) ?? DayTerm.capitalized(dayTerm.the)
        switch progress.action {
        case .setUp:
            return HjemOrganizerStep(title: title, isBusy: adminActions.isBusy, hint: "Åpner oppsettet av runden.") {
                adminActions.newRound(on: event)
            }
        case .continueDraft(let id):
            return HjemOrganizerStep(title: title, isBusy: adminActions.isBusy, hint: "Åpner kladden.") {
                if let round = admin.allRounds.first(where: { $0.id == id }) { adminActions.edit(round) }
            }
        case .goToRound:
            return HjemOrganizerStep(title: title, hint: "Åpner runden.") { route = .round }
        case .seeResult:
            return HjemOrganizerStep(title: title, hint: "Åpner Tavla.") { selectTab(.tavla) }
        case .nudge, .closeEvening, .notPlayed, .noEvening:
            return HjemOrganizerStep(title: title, hint: "Åpner \(dayTerm.the).", perform: openKvelden)
        }
    }

    private func openTable(_ id: UUID) {
        switch HjemDisplay.tableLink(competitionID: id, competition: home.competition(id), currentClub: context.clubID) {
        case .tavla: selectTab(.tavla)
        case .competition(let id): route = .competition(id)
        }
    }

    private func reload() {
        Task { await home.load() }
    }

    /// «Gå til runden» fra arrangørsiden: åpne runden når Hjem står framme og runden er hentet.
    private func consumeRoundRequest() {
        guard wantsRound, round.hasRound else { return }
        wantsRound = false
        route = .round
    }

    @ViewBuilder
    private func destination(_ route: HjemRoute) -> some View {
        switch route {
        case .round:
            // Følges også her, så hentingen hvert 30. sekund går mens runden står framme.
            RundeView(model: round)
                .followsRound(round)
        case .evening:
            KveldView(model: kveld)
        case .kvelden(let id):
            KveldenView(eventID: id, terminliste: TerminlisteModel(context: context), admin: admin)
                .environment(\.dayTerm, dayTerm)
        case .competition(let id):
            HjemCompetitionScreen(context: context, competitionID: id)
        }
    }
}

/// Turneringen bak «Se tabellen →»: henter lista og viser siden når den er funnet.
private struct HjemCompetitionScreen: View {
    @State private var model: CompetitionsModel
    let competitionID: UUID

    init(context: ClubContext, competitionID: UUID) {
        _model = State(initialValue: CompetitionsModel(context: context))
        self.competitionID = competitionID
    }

    var body: some View {
        Group {
            if let competition = model.all.first(where: { $0.id == competitionID }) {
                CompetitionDetailScreen(list: model, competition: competition)
            } else if model.state == .loading {
                ProgressView("Henter tabellen …")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView("Fant ikke tabellen", systemImage: "trophy",
                                       description: Text("Turneringen er ikke tilgjengelig lenger."))
            }
        }
        .navigationTitle("Tabellen")
        .ddNavigationChrome()
        .task { await model.load() }
    }
}
