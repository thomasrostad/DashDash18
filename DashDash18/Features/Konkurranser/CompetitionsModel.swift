import Foundation
import GolfgutuCore
import Observation
import Supabase

/// Konkurransene du kan se: lista, velgeren på Tavla, påmelding og «Ny konkurranse».
@Observable
final class CompetitionsModel {
    enum LoadState: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    private(set) var state: LoadState = .loading
    private(set) var overview = CompetitionQueries.Overview()
    /// Konkurransen det jobbes med (påmelding, ny), så knappen kan vise fremdrift.
    private(set) var busy: UUID?
    var error: String?

    let access: CompetitionAccess
    /// Klubben som er valgt i appen, og navnet.
    let clubID: UUID?
    let clubName: String?
    let client: SupabaseClient?

    init(context: ClubContext) {
        client = context.client
        access = context.competitionAccess
        clubID = context.clubID
        clubName = context.membership.club.name
    }

    /// Uten klubb (appen med bare Spill og Deg): de private turneringene du eier eller er med i, og
    /// «Ny turnering» (liga, cup, morro). Serveren krever ingen klubb for dem (sql/017, 022, 026).
    init(client: SupabaseClient, userID: UUID) {
        self.client = client
        access = CompetitionAccess(profileID: userID, memberships: [])
        clubID = nil
        clubName = nil
    }

    #if DEBUG
    /// Skjermprøve uten nett.
    init(preview overview: CompetitionQueries.Overview, access: CompetitionAccess, clubID: UUID?, clubName: String?) {
        client = nil
        self.overview = overview
        self.access = access
        self.clubID = clubID
        self.clubName = clubName
        state = .loaded
    }
    #endif

    func load() async {
        guard let client else { return }
        do {
            overview = try await CompetitionQueries.overview(client: client)
            state = .loaded
        } catch is CancellationError {
        } catch {
            if case .loaded = state { return }
            state = .failed(DataError.from(error).message)
        }
    }

    // MARK: Utvalg

    /// Klubbens hovedturnering (jakkeracet): den aktive, ellers den sist opprettede.
    var main: CompetitionRow? {
        let mains = overview.competitions.filter { $0.isMain && $0.clubID == clubID }
        return mains.first { $0.status == .active } ?? mains.first
    }

    /// Alle du kan se, i lista sin rekkefølge: hovedturneringen, så pågående, planlagte og ferdige,
    /// hver etter navn.
    var all: [CompetitionRow] {
        let visible = overview.competitions.filter { access.canSee($0, overview.participants) }
        func rank(_ c: CompetitionRow) -> Int {
            if c.id == main?.id { return 0 }
            switch c.status {
            case .active: return 1
            case .planned: return 2
            case .finished: return 3
            }
        }
        return visible.sorted { a, b in
            rank(a) != rank(b) ? rank(a) < rank(b) : NorwegianSort.areInIncreasingOrder(a.name, b.name)
        }
    }

    /// Velgeren på Tavla: hovedturneringen og de andre som ikke er ferdige.
    var switcher: [CompetitionRow] {
        all.filter { $0.id == main?.id || ($0.status != .finished && $0.kind != .season) }
    }

    func participants(_ c: CompetitionRow) -> [CompetitionParticipantRow] {
        overview.participants.filter { $0.competitionID == c.id }
    }

    func signup(_ c: CompetitionRow) -> CompetitionAccess.Signup {
        access.signup(c, overview.participants, isDrawn: overview.drawn.contains(c.id))
    }

    func isAdmin(_ c: CompetitionRow) -> Bool { access.isAdmin(c) }

    func canInvite(_ c: CompetitionRow) -> Bool {
        access.canInvite(c, overview.participants, isDrawn: overview.drawn.contains(c.id))
    }

    /// Bare med en klubb: uten klubb gir `canCreate(inClub: nil)` de private.
    var canCreateInClub: Bool { clubID != nil && access.canCreate(inClub: clubID) }
    var canCreate: Bool { canCreateInClub || access.canCreate(inClub: nil) }

    func clubName(of c: CompetitionRow) -> String? {
        c.clubID == clubID ? clubName : nil
    }

    // MARK: Påmelding

    func join(_ c: CompetitionRow) async {
        await run(c.id) { client in
            _ = try await CompetitionQueries.join(client: client, competitionID: c.id)
        }
    }

    func leave(_ c: CompetitionRow) async {
        await run(c.id) { client in
            try await CompetitionQueries.leave(client: client, competitionID: c.id)
        }
    }

    // MARK: Ny konkurranse

    /// Krever den nye konkurransen kjøp som ikke er gjort (vis betalingsveggen)?
    func needsPurchase(_ draft: CompetitionDraft, purchases: PurchaseService?) -> Bool {
        !CompetitionPurchase.isUnlocked(kind: draft.kind, clubID: draft.clubID, userID: access.profileID,
                                        purchases: purchases)
    }

    /// En konkurranse som er laget.
    struct Created: Equatable {
        let id: UUID
        /// `false` når en ledig kreditt skulle kobles, men koblingen feilet: konkurransen er laget,
        /// men låst til arrangøren trykker «Bruk kjøpet ditt».
        var creditLinked = true
    }

    /// Lager konkurransen, og kobler en ledig kreditt til den når typen krever kjøp. Gir id-en og om
    /// kreditten ble koblet, eller nil (feilen står i `error`).
    func create(_ draft: CompetitionDraft, purchases: PurchaseService? = nil) async -> Created? {
        guard let client, !needsPurchase(draft, purchases: purchases) else { return nil }
        if let issue = draft.issues().first {
            error = issue
            return nil
        }
        busy = UUID()
        defer { busy = nil }
        do {
            let id = try await CompetitionQueries.create(client: client, draft.params(main: main?.rules))
            let linked = await linkCredit(to: id, draft: draft, purchases: purchases)
            await load()
            return Created(id: id, creditLinked: linked)
        } catch {
            self.error = DataError.from(error).message
            return nil
        }
    }

    /// Kobler en ledig kreditt til den nye konkurransen (`assign_purchase`) når typen krever kjøp og et
    /// abonnement ikke alt dekker den. `false` bare når koblingen trengtes og feilet.
    func linkCredit(to id: UUID, draft: CompetitionDraft, purchases: PurchaseService?,
                    enabled: Bool = PurchaseFeature.isEnabled) async -> Bool {
        guard let purchases, CompetitionPurchase.needsCredit(kind: draft.kind, clubID: draft.clubID,
                                                              userID: access.profileID,
                                                              entitlements: purchases.entitlements,
                                                              enabled: enabled) else { return true }
        // Kreditten brukes i stedet for et nytt kjøp.
        return await purchases.useCredit(for: id)
    }

    private func run(_ id: UUID, _ action: (SupabaseClient) async throws -> Void) async {
        guard let client, busy == nil else { return }
        busy = id
        defer { busy = nil }
        do {
            try await action(client)
            await load()
        } catch {
            self.error = DataError.from(error).message
        }
    }
}

/// Én konkurranse: tabellen (sesong, liga eller morro) eller cuptreet, og arrangørens handlinger.
@Observable
final class CompetitionDetailModel {
    enum Content {
        case season(TavlaStandings?)
        case league(LeagueStandings)
        case cup(CupStandings)
    }

    enum LoadState: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    private(set) var state: LoadState = .loading
    private(set) var content: Content?
    private(set) var detail: CompetitionQueries.Detail?
    private(set) var isWorking = false
    var error: String?
    /// Serverens svar på om den er låst opp (`competition_is_unlocked`), nil før det har kommet.
    private(set) var serverUnlocked: Bool?
    /// Koblingen av en ledig kreditt pågår, og feilen fra den.
    private(set) var isUnlocking = false
    private(set) var unlockError: String?
    /// Skjermprøve: hva som vises om kjøpet, uten tjeneste og server.
    var lockPreview: CompetitionLockNotice?

    let competition: CompetitionRow
    let access: CompetitionAccess
    /// Klubbens hovedturnering, for seeding etter plassen der.
    let main: CompetitionRow?
    private var participants: [CompetitionParticipantRow]
    private let client: SupabaseClient?

    init(client: SupabaseClient, competition: CompetitionRow, participants: [CompetitionParticipantRow],
         access: CompetitionAccess, main: CompetitionRow?) {
        self.client = client
        self.competition = competition
        self.participants = participants
        self.access = access
        self.main = main
    }

    #if DEBUG
    init(preview competition: CompetitionRow, content: Content, access: CompetitionAccess) {
        client = nil
        self.competition = competition
        self.content = content
        self.access = access
        participants = []
        main = nil
        state = .loaded
    }
    #endif

    var isAdmin: Bool { access.isAdmin(competition) }

    // MARK: Kjøp (låst konkurranse)

    /// Hva siden viser om kjøpet (`CompetitionLock`).
    func lockNotice(purchases: PurchaseService?) -> CompetitionLockNotice {
        if let lockPreview { return lockPreview }
        guard let purchases, purchases.lastUnlocked != competition.id else { return .hidden }
        return CompetitionLock.notice(for: competition, access: access, serverUnlocked: serverUnlocked,
                                      entitlements: purchases.entitlements)
    }

    /// Spør serveren om konkurransen er låst opp. Bare når kjøp er på og den krever kjøp.
    func checkUnlock(purchases: PurchaseService?) async {
        guard PurchaseFeature.isEnabled, competition.requiresPurchase, let purchases else { return }
        if let answer = await purchases.serverIsUnlocked(competition.id) { serverUnlocked = answer }
    }

    /// «Bruk kjøpet ditt»: kobler en ledig kreditt til konkurransen (`assign_purchase`). Gir `true`
    /// når den er låst opp.
    func useCredit(purchases: PurchaseService?) async -> Bool {
        guard let purchases, !isUnlocking else { return false }
        isUnlocking = true
        unlockError = nil
        defer { isUnlocking = false }
        if await purchases.useCredit(for: competition.id) {
            serverUnlocked = true
            return true
        }
        if case .failed(let failure) = purchases.state { unlockError = failure.message }
        return false
    }

    /// Kan du føre (eller endre) resultatet i kampen?
    func recordRight(_ game: CupStandings.Game) -> CupRecording.Right {
        CupRecording.right(game, isAdmin: isAdmin)
    }

    func load() async {
        guard let client else { return }
        do {
            if competition.kind == .season {
                let input = try await CompetitionQueries.season(client: client, competition: competition)
                let me = access.memberships.first { $0.clubID == competition.clubID }?.memberID
                content = .season(input.map { TavlaStandings($0, me: me) })
            } else {
                participants = try await CompetitionQueries.participants(client: client, competitionID: competition.id)
                let detail = try await CompetitionQueries.detail(client: client, competition: competition,
                                                                 participants: participants)
                self.detail = detail
                content = Self.content(detail, access: access)
            }
            state = .loaded
        } catch is CancellationError {
        } catch {
            if case .loaded = state { return }
            state = .failed(DataError.from(error).message)
        }
    }

    static func content(_ d: CompetitionQueries.Detail, access: CompetitionAccess) -> Content {
        if d.competition.kind == .cup {
            let names = Dictionary(d.participants.map { p in
                (p.id, d.scope.entrant(for: p, directory: d.directory).map { d.directory.name($0, fallback: nil) } ?? "")
            }, uniquingKeysWith: { first, _ in first })
            let mine = Set(d.participants.filter(access.isMine).map(\.id))
            return .cup(CupStandings(participants: d.participants, matches: d.matches, names: names, me: mine))
        }
        return .league(LeagueStandings(d.input, me: access.myEntrants))
    }

    // MARK: Cup

    /// Forslaget til resultat for en kamp, fra den siste runden begge spilte.
    func suggestion(for game: CupStandings.Game) -> (roundID: UUID, decision: Cup.Decision)? {
        guard let detail else { return nil }
        let byID = Dictionary(detail.participants.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return CupStandings.suggestion(for: game, input: detail.input) { id in
            byID[id].flatMap { detail.scope.entrant(for: $0, directory: detail.directory) }
        }
    }

    /// Trekker cupen etter reglene (seeding), med et nytt tilfeldig frø.
    func draw() async {
        guard let client, let detail, !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            let rules = competition.rules.competitionRules.cup
            var handicaps: [UUID: Double] = [:]
            var names: [UUID: String] = [:]
            var memberOf: [UUID: UUID] = [:]
            for p in detail.participants {
                guard let e = detail.scope.entrant(for: p, directory: detail.directory) else { continue }
                names[p.id] = detail.directory.name(e, fallback: nil)
                switch e {
                case .member(let id):
                    handicaps[p.id] = detail.directory.members[id]?.handicapIndex
                    memberOf[p.id] = id
                case .profile(let id): handicaps[p.id] = detail.directory.profiles[id]?.handicapIndex
                case .guest: break
                }
            }
            var ranks: [UUID: Int] = [:]
            if rules.seeding == .ranking, let main, let input = try await CompetitionQueries.season(client: client, competition: main) {
                let table = TavlaStandings(input, me: nil)
                let place = Dictionary(table.rows.map { ($0.memberID, $0.place) }, uniquingKeysWith: { first, _ in first })
                ranks = memberOf.compactMapValues { place[$0] }
            }
            let pairings = CupStandings.pairings(participants: detail.participants, names: names, handicaps: handicaps,
                                                 ranks: ranks, rules: rules, seed: UInt64.random(in: .min ... .max))
            try await CompetitionQueries.draw(client: client, competitionID: competition.id, pairings: pairings)
            await load()
        } catch {
            self.error = DataError.from(error).message
        }
    }

    func record(_ game: CupStandings.Game, winner: UUID?, walkover: Bool, result: String?, roundID: UUID?) async -> Bool {
        guard let client, !isWorking else { return false }
        isWorking = true
        defer { isWorking = false }
        do {
            try await CompetitionQueries.record(client: client, competitionID: competition.id, round: game.round,
                                                slot: game.slot, winner: winner, walkover: walkover,
                                                result: result, roundID: roundID)
            await load()
            return true
        } catch {
            self.error = DataError.from(error).message
            return false
        }
    }

    /// Runden kampen ble spilt i, som tekst.
    func roundTitle(_ id: UUID) -> String? {
        detail?.input.rounds.first { $0.round.id == id }.map(LeagueStandings.title)
    }
}
