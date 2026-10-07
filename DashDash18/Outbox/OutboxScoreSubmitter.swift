import Foundation
import SwiftData

/// Utboksen (fase 5, B6): legger seg utenpå en `ScoreSubmitting` og sørger for at ingen hull
/// går tapt uten dekning.
///
/// - Hvert hull lagres i SwiftData før det sendes, og slettes først når serveren har bekreftet det.
/// - Uten kontakt (nettfeil, tidsavbrudd) gir `submit` `.queued`, og hullet sendes senere:
///   ved `start()`, når appen blir aktiv (`flush()`), når nettet kommer tilbake, og med
///   eksponentiell backoff så lenge noe ligger i køen.
/// - Sier serveren nei (tilgang, ugyldig), kastes feilen og hullet merkes som avvist.
/// - En nyere innsending for samme runde, hull og spiller erstatter den eldre i køen
///   (siste `recordedAt` vinner, som `save_hole`).
final class OutboxScoreSubmitter: ScoreSubmitting {
    let status = OutboxStatus()

    private let inner: any ScoreSubmitting
    private let context: ModelContext
    private let clock: any OutboxClock
    private let network: any NetworkMonitoring
    private let backoff: OutboxBackoff
    private let timeout: Duration

    private var isRunning = false
    private var isFlushing = false
    private var flushAgain = false
    /// Poster som er på vei til serveren nå, så de ikke sendes to ganger samtidig.
    private var inFlight: Set<UUID> = []
    /// Feil på rad uten kontakt. Styrer backoff, nullstilles ved suksess og når nettet kommer.
    private(set) var consecutiveFailures = 0
    private var retryTask: Task<Void, Never>?
    /// Den innloggede. Nye hull merkes med den, og bare dens hull sendes.
    private(set) var currentUserID: UUID?
    private var networkTask: Task<Void, Never>?

    init(
        inner: any ScoreSubmitting,
        container: ModelContainer,
        clock: any OutboxClock = SystemOutboxClock(),
        network: any NetworkMonitoring = PathNetworkMonitor(),
        backoff: OutboxBackoff = OutboxBackoff(),
        timeout: Duration = .seconds(20)
    ) {
        self.inner = inner
        context = ModelContext(container)
        context.autosaveEnabled = false
        self.clock = clock
        self.network = network
        self.backoff = backoff
        self.timeout = timeout
        refreshStatus()
    }

    /// Lager lageret for utboksen. Egen fil, deles ikke med noe annet.
    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema([OutboxItem.self])
        if inMemory {
            return try ModelContainer(
                for: schema, configurations: ModelConfiguration("Utboks", schema: schema, isStoredInMemoryOnly: true)
            )
        }
        let directory = URL.applicationSupportDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let configuration = ModelConfiguration("Utboks", schema: schema, url: directory.appending(path: "Utboks.store"))
        return try ModelContainer(for: schema, configurations: configuration)
    }

    // MARK: - Livssyklus

    /// Starter automatisk sending: nå, når nettet kommer tilbake og med backoff.
    /// Kalles når brukeren er innlogget (serveren avviser alt fra uinnloggede).
    func start(userID: UUID? = nil) {
        currentUserID = userID
        refreshStatus()
        guard !isRunning else {
            Task { await flush() }
            return
        }
        isRunning = true
        networkTask = Task { [weak self, network] in
            var wasAvailable: Bool?
            for await available in network.availability() {
                guard let self else { return }
                if available, wasAvailable == false {
                    self.consecutiveFailures = 0
                    await self.flush()
                }
                wasAvailable = available
            }
        }
        Task { await flush() }
    }

    /// Stopper automatisk sending (f.eks. ved utlogging). Køen beholdes.
    func stop() {
        isRunning = false
        currentUserID = nil
        refreshStatus()
        networkTask?.cancel()
        networkTask = nil
        retryTask?.cancel()
        retryTask = nil
    }

    // MARK: - ScoreSubmitting

    func submit(_ submission: HoleSubmission) async throws -> SubmitOutcome {
        guard let id = enqueue(submission) else {
            // Køen har allerede nyere tall for alle spillerne.
            return .queued
        }
        switch await attempt(id) {
        case .saved(let rows):
            if hasPending { Task { await flush() } }
            return .saved(rows)
        case .transient, .skipped:
            scheduleRetry()
            return .queued
        case .rejected(let error):
            throw error
        }
    }

    func pendingHoles(roundID: UUID) -> Set<Int> {
        let pending = OutboxItem.State.pending.rawValue
        let descriptor = FetchDescriptor<OutboxItem>(
            predicate: #Predicate { $0.roundID == roundID && $0.stateRaw == pending }
        )
        return Set(((try? context.fetch(descriptor)) ?? []).filter(belongsToCurrentUser).map(\.holeIndex))
    }

    /// Eldst først, så en nyere innsending for samme spiller legges sist (og vinner).
    func pendingSubmissions(roundID: UUID) -> [HoleSubmission] {
        let pending = OutboxItem.State.pending.rawValue
        let descriptor = FetchDescriptor<OutboxItem>(
            predicate: #Predicate { $0.roundID == roundID && $0.stateRaw == pending },
            sortBy: [SortDescriptor(\.recordedAt), SortDescriptor(\.createdAt)]
        )
        return ((try? context.fetch(descriptor)) ?? []).filter(belongsToCurrentUser).map(\.submission)
    }

    // MARK: - Sending av køen

    /// Sender køen i rekkefølge (eldst `recordedAt` først). Stopper ved første nettfeil.
    func flush() async {
        if isFlushing {
            flushAgain = true
            return
        }
        isFlushing = true
        defer { isFlushing = false }
        repeat {
            flushAgain = false
            for id in pendingIDsInOrder() where !inFlight.contains(id) {
                if case .transient = await attempt(id) {
                    scheduleRetry()
                    return
                }
            }
        } while flushAgain
    }

    /// Avviste hull, til visning.
    func rejectedItems() -> [OutboxItem] {
        let rejected = OutboxItem.State.rejected.rawValue
        let descriptor = FetchDescriptor<OutboxItem>(
            predicate: #Predicate { $0.stateRaw == rejected },
            sortBy: [SortDescriptor(\.recordedAt), SortDescriptor(\.createdAt)]
        )
        return ((try? context.fetch(descriptor)) ?? []).filter(belongsToCurrentUser)
    }

    // MARK: - Internt

    private enum Attempt {
        case saved([HoleScoreRow])
        case transient
        case rejected(DataError)
        /// Posten finnes ikke lenger eller er ikke til sending.
        case skipped
    }

    /// Lagrer innsendingen etter å ha fjernet eldre tall for de samme spillerne.
    /// Gir nil hvis køen har nyere tall for alle spillerne i innsendingen.
    private func enqueue(_ submission: HoleSubmission) -> UUID? {
        let roundID = submission.roundID
        let holeIndex = submission.holeIndex
        let descriptor = FetchDescriptor<OutboxItem>(
            predicate: #Predicate { $0.roundID == roundID && $0.holeIndex == holeIndex }
        )
        var newEntries = submission.entries
        for existing in (try? context.fetch(descriptor)) ?? [] {
            let members = Set(newEntries.map(\.memberID))
            let overlap = existing.entries.filter { members.contains($0.memberID) }
            guard !overlap.isEmpty else { continue }
            if existing.recordedAt <= submission.recordedAt {
                let kept = existing.entries.filter { !members.contains($0.memberID) }
                if kept.isEmpty {
                    context.delete(existing)
                } else {
                    existing.entries = kept
                }
            } else {
                let newer = Set(overlap.map(\.memberID))
                newEntries.removeAll { newer.contains($0.memberID) }
            }
        }
        guard !newEntries.isEmpty else {
            save()
            refreshStatus()
            return nil
        }
        let compacted = HoleSubmission(
            roundID: roundID, holeIndex: holeIndex, entries: newEntries, recordedAt: submission.recordedAt
        )
        guard let item = try? OutboxItem(submission: compacted, createdAt: clock.now, userID: currentUserID) else { return nil }
        context.insert(item)
        save()
        refreshStatus()
        return item.id
    }

    /// Ett forsøk på å sende posten. Posten hentes på nytt etter sending, fordi en nyere
    /// innsending kan ha endret eller slettet den imens.
    private func attempt(_ id: UUID) async -> Attempt {
        guard !inFlight.contains(id), let item = item(id), item.state == .pending else { return .skipped }
        let submission = item.submission
        item.attempts += 1
        item.lastAttemptAt = clock.now
        save()

        inFlight.insert(id)
        defer { inFlight.remove(id) }
        do {
            let outcome = try await sendWithTimeout(submission)
            guard case .saved(let rows) = outcome else {
                return failed(id, message: "Lagt i kø av underliggende sender")
            }
            if let item = self.item(id) { context.delete(item) }
            save()
            consecutiveFailures = 0
            status.didSend(at: clock.now)
            refreshStatus()
            return .saved(rows)
        } catch {
            switch Self.classify(error) {
            case .rejected(let dataError):
                if let item = self.item(id) {
                    item.state = .rejected
                    item.lastError = dataError.message
                }
                save()
                status.didFail(dataError.message)
                refreshStatus()
                return .rejected(dataError)
            case .transient(let message):
                return failed(id, message: message)
            }
        }
    }

    private func failed(_ id: UUID, message: String) -> Attempt {
        item(id)?.lastError = message
        save()
        consecutiveFailures += 1
        status.didFail(message)
        refreshStatus()
        return .transient
    }

    private struct TimedOut: Error {}

    private final class Flag {
        var value = false
    }

    private func sendWithTimeout(_ submission: HoleSubmission) async throws -> SubmitOutcome {
        let inner = inner
        let timeout = timeout
        let send = Task { try await inner.submit(submission) }
        let timedOut = Flag()
        let timer = Task {
            try await Task.sleep(for: timeout)
            timedOut.value = true
            send.cancel()
        }
        defer { timer.cancel() }
        do {
            return try await send.value
        } catch {
            throw timedOut.value ? TimedOut() : error
        }
    }

    private enum Failure {
        case transient(String)
        case rejected(DataError)
    }

    /// Nettfeil, tidsavbrudd og ukjente feil prøves igjen. Tilgang og ugyldige data gjør ikke.
    private static func classify(_ error: any Error) -> Failure {
        if error is TimedOut { return .transient("Tidsavbrudd mot serveren.") }
        if error is CancellationError { return .transient("Avbrutt.") }
        let dataError = DataError.from(error)
        switch dataError {
        case .notAllowed, .invalid, .duplicate:
            return .rejected(dataError)
        case .offline, .unknown:
            return .transient(dataError.message)
        }
    }

    /// Prøver igjen med økende ventetid så lenge noe ligger i køen og utboksen kjører.
    private func scheduleRetry() {
        guard isRunning, retryTask == nil else { return }
        retryTask = Task { [weak self] in
            while let self, self.isRunning, self.hasPending, !Task.isCancelled {
                let delay = self.backoff.delay(afterFailures: self.consecutiveFailures)
                do {
                    try await self.clock.sleep(for: delay)
                } catch {
                    break
                }
                await self.flush()
            }
            self?.retryTask = nil
        }
    }

    private var hasPending: Bool { !pendingIDsInOrder().isEmpty }

    private func pendingIDsInOrder() -> [UUID] {
        let pending = OutboxItem.State.pending.rawValue
        let descriptor = FetchDescriptor<OutboxItem>(
            predicate: #Predicate { $0.stateRaw == pending },
            sortBy: [SortDescriptor(\.recordedAt), SortDescriptor(\.createdAt)]
        )
        return ((try? context.fetch(descriptor)) ?? []).filter(belongsToCurrentUser).map(\.id)
    }

    /// Hull uten bruker (fra før feltet fantes) regnes som den innloggedes.
    private func belongsToCurrentUser(_ item: OutboxItem) -> Bool {
        item.userID == nil || item.userID == currentUserID
    }

    private func item(_ id: UUID) -> OutboxItem? {
        var descriptor = FetchDescriptor<OutboxItem>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func save() {
        do {
            try context.save()
        } catch {
            status.didFail("Fikk ikke lagret utboksen: \(error.localizedDescription)")
        }
    }

    private func refreshStatus() {
        let items = ((try? context.fetch(FetchDescriptor<OutboxItem>())) ?? []).filter(belongsToCurrentUser)
        struct Hole: Hashable { let round: UUID, hole: Int }
        let pending = Set(items.filter { $0.state == .pending }.map { Hole(round: $0.roundID, hole: $0.holeIndex) })
        let rejected = Set(items.filter { $0.state == .rejected }.map { Hole(round: $0.roundID, hole: $0.holeIndex) })
        status.update(pending: pending.count, rejected: rejected.count)
    }
}
