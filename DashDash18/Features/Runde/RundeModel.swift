import Foundation
import GolfgutuCore
import Observation
import Supabase

/// Hvilken runde skjermen viser: klubbens runde som går, eller en løs runde (fase 13).
enum RundeSource {
    case club(ClubContext)
    case loose(LooseRoundContext)
}

/// En løs runde (sql/017–018): runden og den innloggede.
struct LooseRoundContext {
    let client: SupabaseClient
    let userID: UUID
    let roundID: UUID
}

/// Kveld-skjermen under spill: runden som går, hullkortet for båsen og «Bayen nå».
/// Lagring går gjennom `ScoreSubmitting` (aldri rett til `save_hole`).
@Observable
final class RundeModel {
    enum LoadState: Equatable {
        /// Første henting pågår.
        case checking
        /// Ingen runde går.
        case none
        case loaded
        case failed(String)
    }

    private(set) var state: LoadState = .checking
    /// Runden slik serveren har den.
    private(set) var snapshot: RoundSnapshot?
    /// Runden slik den vises: serveren pluss hull som ligger i kø.
    private(set) var game: RoundGame?
    var currentHole = 0 {
        didSet { if currentHole != oldValue { holeChangedAt = .now } }
    }
    /// Når kortet sist byttet hull (`SaveTapGuard`).
    private var holeChangedAt = Date.distantPast
    private(set) var drafts = HoleDrafts()
    private(set) var pendingHoles: Set<Int> = []
    private(set) var isSaving = false
    var saveError: String?
    var celebration: Celebration?
    /// Realtime-kanalen er oppe. Når den ikke er det, henter skjermen hvert 30. sekund.
    private(set) var isLive = false

    var submitter: (any ScoreSubmitting)?

    private let source: RundeSource
    /// Hull i kø som ble ført for første gang: logges når serveren har dem (store scorer, ledelsen).
    private var queuedFresh: [Int: [RoundGame.FreshScore]] = [:]
    /// Det denne telefonen har logget i runden, så samme hendelse ikke går to ganger.
    private var loggedOnce = ActivityOnceLog()
    private var placedRound: UUID?
    private var isLoading = false
    private var reloadAgain = false
    private var channel: RealtimeChannelV2?
    private var channelRound: UUID?
    private var listenTasks: [Task<Void, Never>] = []

    init(context: ClubContext) {
        source = .club(context)
    }

    /// En løs runde (fase 13): hentes på id, også når den er avsluttet.
    init(loose: LooseRoundContext) {
        source = .loose(loose)
    }

    #if DEBUG
    /// Skjermprøve av en løs runde som alt er hentet (`-DDDesignScreen losrunde`). Ingen henting.
    init(previewLoose snapshot: RoundSnapshot, context: LooseRoundContext) {
        source = .loose(context)
        self.snapshot = snapshot
        game = RoundGame(snapshot)
        placedRound = snapshot.round.id
        if let game { currentHole = game.bayHole(for: viewer) }
        state = .loaded
    }
    #endif

    private var client: SupabaseClient {
        switch source {
        case .club(let context): context.client
        case .loose(let loose): loose.client
        }
    }

    /// Klubben, når runden er en klubbrunde.
    var clubContext: ClubContext? {
        if case .club(let context) = source { return context }
        return nil
    }

    /// Den løse runden, når skjermen viser en.
    var looseContext: LooseRoundContext? {
        if case .loose(let loose) = source { return loose }
        return nil
    }

    var viewer: Viewer {
        switch source {
        case .club(let context):
            Viewer(memberID: context.memberID, isOrganizer: context.isOrganizer)
        case .loose(let loose):
            LooseRoundRights.viewer(info: snapshot?.loose, userID: loose.userID)
        }
    }
    var hasRound: Bool { game != nil }

    var card: HoleCard? {
        guard let game, game.holes.indices.contains(currentHole),
              !game.cardPlayers(for: viewer).isEmpty else { return nil }
        return game.card(hole: currentHole, drafts: drafts, viewer: viewer)
    }

    /// Par-bekreftelsen tar plassen til hullkortet til noen har bekreftet.
    var needsParConfirmation: Bool { snapshot?.round.parConfirmedAt == nil }
    /// Arrangøren, eller en markør i runden som går (`confirm_round_par`).
    var canConfirmPar: Bool { game?.canConfirmPar(viewer) ?? viewer.isOrganizer }

    // MARK: Henting

    /// Henter runden som går, eller finner at ingen gjør det. Kommer et nytt kall mens
    /// en henting pågår (realtime gir flere hendelser per hull), kjøres én til etterpå.
    func load() async {
        if isLoading { reloadAgain = true; return }
        isLoading = true
        defer { isLoading = false }
        repeat {
            reloadAgain = false
            await fetch()
        } while reloadAgain
    }

    private func fetch() async {
        do {
            guard let fresh = try await fetchSnapshot() else {
                snapshot = nil
                game = nil
                state = .none
                RoundActivityController.shared.sync(game: nil, viewer: viewer)
                await stopRealtime()
                return
            }
            let before = followingBay
            snapshot = fresh
            rebuild()
            place(following: before)
            state = .loaded
            await startRealtime(roundID: fresh.round.id)
        } catch {
            // Behold det som vises når en oppfrisking feiler.
            if snapshot != nil { return }
            state = .failed(DataError.from(error).message)
        }
    }

    /// Klubbens runde som går, eller den løse runden.
    private func fetchSnapshot() async throws -> RoundSnapshot? {
        switch source {
        case .club(let context):
            try await RundeQueries.activeRound(client: client, clubID: context.clubID)
        case .loose(let loose):
            try await LooseRoundQueries.snapshot(client: client, roundID: loose.roundID)
        }
    }

    private func rebuild() {
        // Live Activity følger runden slik den vises (med hull i kø).
        defer { RoundActivityController.shared.sync(game: game, viewer: viewer) }
        guard let snapshot else { game = nil; return }
        // Køen leses fra utboksen hver gang, ikke fra minnet: hull som ble lagt i kø før appen
        // ble startet på nytt, skal fortsatt stå (ellers står hullet tomt med par, og «Lagre»
        // ville erstattet tallet i køen). Bekreftede hull er ute av køen og står hos serveren.
        let pending = submitter?.pendingSubmissions(roundID: snapshot.round.id) ?? []
        pendingHoles = Set(pending.map(\.holeIndex))
        logConfirmedQueuedHoles(server: snapshot)
        game = RoundGame(snapshot.overlaying(pending.map(QueuedHole.init)))
    }

    /// `folgerBaasen`: står kortet på båsens hull før hentingen?
    private var followingBay: Bool {
        guard let game else { return false }
        return currentHole == game.bayHole(for: viewer)
    }

    /// `plasserHull`: første gang en runde lastes, står kortet på båsens hull. Sto du på
    /// båsens hull, følger du med. Har du gått til et annet hull for å se, blir du der.
    private func place(following: Bool) {
        guard let game else { return }
        if placedRound != game.roundID {
            placedRound = game.roundID
            drafts = HoleDrafts()
            queuedFresh = [:]
            loggedOnce = ActivityOnceLog()
            currentHole = game.bayHole(for: viewer)
        } else if following {
            currentHole = game.bayHole(for: viewer)
        }
        currentHole = min(max(0, currentHole), game.holeCount - 1)
    }

    // MARK: Realtime

    private func startRealtime(roundID: UUID) async {
        guard channelRound != roundID else { return }
        await stopRealtime()
        let channel = client.channel("runde-\(roundID.uuidString)")
        let changes = channel.postgresChange(AnyAction.self, schema: "public", table: "hole_scores",
                                             filter: .eq("round_id", value: roundID))
        // Longest drive og nærmest pinnen meldes fra hver sin telefon: ledelsen skal følge med.
        let claimChanges = channel.postgresChange(AnyAction.self, schema: "public", table: "side_claims",
                                                  filter: .eq("round_id", value: roundID))
        let statuses = channel.statusChange
        self.channel = channel
        channelRound = roundID
        listenTasks = [
            Task { [weak self] in
                for await status in statuses {
                    self?.isLive = status == .subscribed
                }
            },
            Task { [weak self] in
                for await _ in changes {
                    await self?.load()
                }
            },
            Task { [weak self] in
                for await _ in claimChanges {
                    await self?.load()
                }
            },
            Task {
                try? await channel.subscribeWithError()
            },
        ]
    }

    func stopRealtime() async {
        listenTasks.forEach { $0.cancel() }
        listenTasks = []
        if let channel { await client.removeChannel(channel) }
        channel = nil
        channelRound = nil
        isLive = false
    }

    // MARK: Føring

    func goTo(hole: Int) {
        guard let game, (0..<game.holeCount).contains(hole) else { return }
        currentHole = hole
        saveError = nil
    }

    /// − og +: justerer og bekrefter samtidig.
    func step(_ delta: Int, member: UUID) {
        guard let card, let row = card.rows.first(where: { $0.memberID == member }), row.editable else { return }
        drafts[currentHole, member] = StrokeInput.clamp(row.value + delta)
    }

    /// Trykk på tallet bekrefter det som står (par når ingenting er ført).
    func confirm(member: UUID) {
        guard let card, let row = card.rows.first(where: { $0.memberID == member }), row.editable else { return }
        drafts[currentHole, member] = row.value
    }

    /// «Lagre hull N → hull N+1»: alle radene i én innsending, med tastetiden.
    func saveCurrentHole() async {
        guard let game, let submitter, !isSaving, let card, case .save(_, true, _) = card.action,
              SaveTapGuard.allows(now: .now, holeChangedAt: holeChangedAt) else { return }
        let hole = currentHole
        guard let submission = game.submission(hole: hole, drafts: drafts, viewer: viewer, recordedAt: Date()) else {
            drafts.clear(hole: hole)
            advance(from: hole)
            return
        }
        let onCard = Set(game.cardPlayers(for: viewer))
        let fresh = submission.entries.compactMap { e -> (member: UUID, strokes: Int)? in
            guard onCard.contains(e.memberID), game.scores(e.memberID)[hole] == nil, let s = e.strokes else { return nil }
            return (e.memberID, s)
        }

        isSaving = true
        saveError = nil
        defer { isSaving = false }
        do {
            let outcome = try await submitter.submit(submission)
            switch outcome {
            case .saved(let rows):
                snapshot?.apply(saved: rows, hole: hole, members: submission.entries.map(\.memberID))
            case .queued:
                // Varsler bare for det serveren har: hullet logges når køen er sendt (rebuild).
                if !fresh.isEmpty { queuedFresh[hole] = fresh }
            }
            drafts.clear(hole: hole)
            rebuild()
            if let updated = self.game {
                celebration = updated.celebration(hole: hole, saved: fresh)
                if case .saved = outcome {
                    logAfterSaving(hole: hole, fresh: fresh, in: updated)
                }
            }
            advance(from: hole)
        } catch {
            saveError = "Hull \(game.holeNumber(hole)) ble ikke lagret: \(DataError.from(error).message) Prøv igjen."
        }
    }

    /// Store scorer med en gang. Ledelsen ved et sjekkpunkt regnes på runden slik serveren har
    /// den nå (de andre båsene kan ha ført siden siste realtime-henting); feiler hentingen, brukes
    /// runden slik den vises.
    private func logAfterSaving(hole: Int, fresh: [RoundGame.FreshScore], in game: RoundGame) {
        logQuietly(game.bigScoreEventsAfterSaving(hole: hole, fresh: fresh), in: game)
        guard game.shouldCheckLead(afterSaving: hole, fresh: fresh) else { return }
        let client = client, round = game.snapshot.round
        Task {
            let server = try? await RundeQueries.snapshot(client: client, round: round)
            let current = server.map { RoundGame($0) } ?? game
            if let lead = current.leadEventIfActive(afterSaving: hole) {
                logQuietly([lead], in: current)
            }
        }
    }

    /// Hull i kø som serveren nå har: logges som om de nettopp ble lagret. Kalles før `queued`
    /// ryddes, med runden slik serveren har den.
    private func logConfirmedQueuedHoles(server snapshot: RoundSnapshot) {
        guard !queuedFresh.isEmpty else { return }
        guard placedRound == snapshot.round.id else { queuedFresh = [:]; return }
        let server = RoundGame(snapshot)
        for hole in queuedFresh.keys.sorted() where !pendingHoles.contains(hole) {
            let fresh = server.confirmed(queuedFresh.removeValue(forKey: hole) ?? [], hole: hole)
            logQuietly(server.eventsAfterSaving(hole: hole, fresh: fresh), in: server)
        }
    }

    /// Logger i bakgrunnen, så føringen ikke venter på varslene. En feil stopper ingenting.
    /// Det som bare skal stå én gang per runde (`ActivityOnce`), og alt er logget fra denne
    /// telefonen, sendes ikke igjen.
    private func logQuietly(_ events: [ActivityEvent], in game: RoundGame) {
        // Aktiviteten hører til klubb og kveld (sql/008). Løse runder logger ikke ennå.
        guard case .club(let context) = source, let eventID = game.snapshot.round.eventID else { return }
        let events = loggedOnce.admit(events, roundID: game.roundID)
        guard !events.isEmpty else { return }
        let log = ActivityLog(client: client, clubID: context.clubID)
        let roundID = game.roundID
        Task {
            for event in events {
                await log.logQuietly(event, eventID: eventID, roundID: roundID)
            }
        }
    }

    private func advance(from hole: Int) {
        guard let game else { return }
        currentHole = min(game.holeCount - 1, hole + 1)
    }

    // MARK: Par

    /// «Stemmer · start føringen» (arrangør eller markør).
    func confirmPar() async throws(DataError) {
        guard let round = snapshot?.round, canConfirmPar else { return }
        do {
            try await RundeQueries.confirmPar(client: client, roundID: round.id)
        } catch {
            throw ParConfirmation.error(DataError.from(error))
        }
        await load()
    }

    // MARK: Løs runde (fase 13)

    /// Eieren og deltakerne med profil kan invitere, så lenge runden ikke er avsluttet.
    var canInvite: Bool {
        guard let loose = looseContext, let snapshot else { return false }
        return LooseRoundRights.canInvite(info: snapshot.loose, userID: loose.userID, status: snapshot.round.status)
    }

    /// Bare eieren avslutter.
    var canFinish: Bool {
        guard let loose = looseContext, let snapshot else { return false }
        return LooseRoundRights.canFinish(info: snapshot.loose, userID: loose.userID, status: snapshot.round.status)
    }

    /// «Avslutt runden» (`finish_loose_round`, sql/018). Resultatet står etterpå.
    func finish() async throws(DataError) {
        guard let loose = looseContext, canFinish else { return }
        do {
            try await LooseRoundQueries.finish(client: client, roundID: loose.roundID)
        } catch {
            throw DataError.from(error)
        }
        await load()
    }

    // MARK: Longest drive og nærmest pinnen

    /// «Meld inn» / «Oppdater» for `member` (meg, eller hvem som helst for arrangøren).
    func submitSideClaim(_ kind: SideClaimKind, member: UUID, text: String) async throws(DataError) {
        guard let game else { return }
        let draft: SideClaimDraft
        switch game.sideClaimDraft(kind, member: member, text: text, viewer: viewer) {
        case .success(let d): draft = d
        case .failure(let error): throw error
        }
        do {
            let row = try await RundeQueries.saveSideClaim(client: client, draft)
            snapshot?.apply(claim: row)
            rebuild()
        } catch {
            throw DataError.from(error)
        }
        if let updated = self.game,
           let event = updated.sidePrizeEventAfterClaim(kind, member: member, before: game) {
            logQuietly([event], in: updated)
        }
    }

    /// «Slett» på en innmelding (egen i runden som går, eller arrangør).
    func deleteSideClaim(_ id: UUID) async throws(DataError) {
        do {
            try await RundeQueries.deleteSideClaim(client: client, id: id)
            snapshot?.removeClaim(id)
            rebuild()
        } catch {
            throw DataError.from(error)
        }
    }
}
