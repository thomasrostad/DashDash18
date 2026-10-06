import Foundation
import SwiftData
import Testing
@testable import DashDash18

// MARK: - Testdobler

/// Underliggende sender uten nett. `mode` styrer hva neste forsøk gir.
@MainActor
final class FakeSender: ScoreSubmitting {
    enum Mode {
        case ok
        case offline
        case fail(DataError)
        /// Svarer aldri (til den blir avbrutt).
        case hang
    }

    var mode: Mode = .ok
    /// Alle forsøk.
    private(set) var calls: [HoleSubmission] = []
    /// Forsøk serveren tok imot.
    private(set) var saved: [HoleSubmission] = []
    var onSubmit: ((HoleSubmission) -> Void)?

    func submit(_ submission: HoleSubmission) async throws -> SubmitOutcome {
        calls.append(submission)
        onSubmit?(submission)
        switch mode {
        case .ok:
            saved.append(submission)
            return .saved(submission.entries.compactMap { entry in
                entry.strokes.map {
                    HoleScoreRow(roundID: submission.roundID, memberID: entry.memberID,
                                 holeIndex: submission.holeIndex, strokes: $0, recordedAt: submission.recordedAt)
                }
            })
        case .offline:
            throw URLError(.notConnectedToInternet)
        case .fail(let error):
            throw error
        case .hang:
            try await Task.sleep(for: .seconds(30))
            throw CancellationError()
        }
    }

    func pendingHoles(roundID: UUID) -> Set<Int> { [] }
}

/// Klokke der ventetid står stille til testen sier `advance()`.
@MainActor
final class TestClock: OutboxClock {
    var now = Date(timeIntervalSince1970: 1_800_000_000)
    private(set) var sleeps: [Duration] = []
    private var waiters: [CheckedContinuation<Void, any Error>] = []

    func sleep(for duration: Duration) async throws {
        sleeps.append(duration)
        try await withCheckedThrowingContinuation { waiters.append($0) }
    }

    func advance() {
        guard !waiters.isEmpty else { return }
        waiters.removeFirst().resume()
    }
}

@MainActor
final class FakeNetwork: NetworkMonitoring {
    private let stream: AsyncStream<Bool>
    private let continuation: AsyncStream<Bool>.Continuation

    init() {
        (stream, continuation) = AsyncStream.makeStream(of: Bool.self)
    }

    func availability() -> AsyncStream<Bool> { stream }
    func send(_ available: Bool) { continuation.yield(available) }
}

// MARK: - Tester

@MainActor
@Suite(.serialized)
struct OutboxTests {
    let roundID = UUID()
    let anna = UUID()
    let bjorn = UUID()
    let base = Date(timeIntervalSince1970: 1_800_000_000)

    let container: ModelContainer
    let sender = FakeSender()
    let clock = TestClock()
    let network = FakeNetwork()

    init() throws {
        container = try OutboxScoreSubmitter.makeContainer(inMemory: true)
    }

    func makeOutbox(timeout: Duration = .seconds(20)) -> OutboxScoreSubmitter {
        OutboxScoreSubmitter(inner: sender, container: container, clock: clock, network: network, timeout: timeout)
    }

    func hole(_ index: Int, round: UUID? = nil, at seconds: TimeInterval = 0,
              _ entries: [(UUID, Int?)]) -> HoleSubmission {
        HoleSubmission(
            roundID: round ?? roundID,
            holeIndex: index,
            entries: entries.map { HoleSubmission.Entry(memberID: $0.0, strokes: $0.1) },
            recordedAt: base.addingTimeInterval(seconds)
        )
    }

    /// Lar andre oppgaver på MainActor kjøre til vilkåret holder.
    func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<2_000 where !condition() {
            await Task.yield()
        }
    }

    @Test func lagresForDenSendes() async throws {
        let outbox = makeOutbox()
        var seenInStore: Set<Int>?
        sender.onSubmit = { [container, roundID] _ in
            // En annen kontekst på samme lager ser hullet mens det sendes.
            let other = OutboxScoreSubmitter(inner: FakeSender(), container: container,
                                             clock: TestClock(), network: FakeNetwork())
            seenInStore = other.pendingHoles(roundID: roundID)
        }
        _ = try await outbox.submit(hole(4, [(anna, 5)]))
        #expect(seenInStore == [4])
    }

    @Test func suksessTommerKoen() async throws {
        let outbox = makeOutbox()
        let outcome = try await outbox.submit(hole(0, [(anna, 4), (bjorn, nil)]))
        guard case .saved(let rows) = outcome else {
            Issue.record("Ventet .saved, fikk \(outcome)")
            return
        }
        #expect(rows.map(\.strokes) == [4])
        #expect(outbox.pendingHoles(roundID: roundID).isEmpty)
        #expect(outbox.status.pendingCount == 0)
        #expect(outbox.status.lastSentAt == clock.now)
        #expect(outbox.status.summary == nil)
    }

    @Test func utenNettLeggesIKoOgSendesSeneriRekkefolge() async throws {
        let outbox = makeOutbox()
        sender.mode = .offline
        #expect(try await outbox.submit(hole(1, at: 10, [(anna, 3)])) == .queued)
        #expect(try await outbox.submit(hole(2, at: 20, [(anna, 4)])) == .queued)
        // Tastet tidligere, men kommer inn sist.
        #expect(try await outbox.submit(hole(0, at: 0, [(anna, 5)])) == .queued)
        #expect(outbox.pendingHoles(roundID: roundID) == [0, 1, 2])
        #expect(outbox.status.summary == "3 hull venter på nett")

        sender.mode = .ok
        await outbox.flush()
        #expect(sender.saved.map(\.holeIndex) == [0, 1, 2])
        #expect(outbox.pendingHoles(roundID: roundID).isEmpty)
        #expect(outbox.status.pendingCount == 0)
    }

    @Test func flushStopperVedForsteNettfeil() async throws {
        let outbox = makeOutbox()
        sender.mode = .offline
        _ = try await outbox.submit(hole(0, at: 0, [(anna, 5)]))
        _ = try await outbox.submit(hole(1, at: 10, [(anna, 5)]))
        let before = sender.calls.count
        await outbox.flush()
        // Bare det eldste prøves; resten venter på tur.
        #expect(sender.calls.count == before + 1)
        #expect(sender.calls.last?.holeIndex == 0)
    }

    @Test func nyereInnsendingErstatterEldrePerSpiller() async throws {
        let outbox = makeOutbox()
        sender.mode = .offline
        _ = try await outbox.submit(hole(0, at: 0, [(anna, 4), (bjorn, 5)]))
        _ = try await outbox.submit(hole(0, at: 10, [(anna, 3)]))
        // Eldre enn det som ligger i køen for Anna: overskriver ikke.
        #expect(try await outbox.submit(hole(0, at: 5, [(anna, 7)])) == .queued)
        // Annen runde komprimeres ikke.
        let otherRound = UUID()
        _ = try await outbox.submit(hole(0, round: otherRound, at: 20, [(anna, 6)]))

        sender.mode = .ok
        await outbox.flush()
        let sent = sender.saved.map { s in s.entries.map { "\(s.roundID == otherRound ? "R2" : "R1"):\($0.memberID == anna ? "A" : "B")=\($0.strokes ?? 0)" } }
        #expect(sent == [["R1:B=5"], ["R1:A=3"], ["R2:A=6"]])
        #expect(outbox.status.pendingCount == 0)
    }

    @Test func avvistStopperNyeForsok() async throws {
        let outbox = makeOutbox()
        outbox.start()
        sender.mode = .fail(.notAllowed)
        await #expect(throws: DataError.notAllowed) {
            try await outbox.submit(hole(3, [(anna, 4)]))
        }
        #expect(outbox.pendingHoles(roundID: roundID).isEmpty)
        #expect(outbox.status.rejectedCount == 1)
        #expect(outbox.status.summary == "1 hull ble avvist")
        #expect(outbox.rejectedItems().map(\.holeIndex) == [3])
        #expect(outbox.rejectedItems().first?.lastError == DataError.notAllowed.message)

        sender.mode = .ok
        let calls = sender.calls.count
        await outbox.flush()
        #expect(sender.calls.count == calls)
        #expect(clock.sleeps.isEmpty)
        outbox.stop()
    }

    @Test func ugyldigKastesOgAvvises() async throws {
        let outbox = makeOutbox()
        sender.mode = .fail(.invalid("Ugyldig hull"))
        await #expect(throws: DataError.invalid("Ugyldig hull")) {
            try await outbox.submit(hole(30, [(anna, 4)]))
        }
        #expect(outbox.status.rejectedCount == 1)
    }

    @Test func nyRettingErstatterAvvistHull() async throws {
        let outbox = makeOutbox()
        sender.mode = .fail(.notAllowed)
        _ = try? await outbox.submit(hole(3, at: 0, [(anna, 4)]))
        sender.mode = .ok
        _ = try await outbox.submit(hole(3, at: 10, [(anna, 5)]))
        #expect(outbox.status.rejectedCount == 0)
    }

    @Test func overleverOmstart() async throws {
        sender.mode = .offline
        do {
            let outbox = makeOutbox()
            #expect(try await outbox.submit(hole(5, [(anna, 4)])) == .queued)
        }
        // «Appen drept»: ny utboks på samme lager.
        sender.mode = .ok
        let restarted = makeOutbox()
        #expect(restarted.pendingHoles(roundID: roundID) == [5])
        #expect(restarted.status.pendingCount == 1)
        restarted.start()
        await waitUntil { restarted.pendingHoles(roundID: roundID).isEmpty }
        #expect(sender.saved.map(\.holeIndex) == [5])
        #expect(restarted.pendingHoles(roundID: roundID).isEmpty)
        restarted.stop()
    }

    @Test func koenErKnyttetTilBruker() async throws {
        let thomas = UUID(), per = UUID()
        sender.mode = .offline
        do {
            let outbox = makeOutbox()
            outbox.start(userID: thomas)
            #expect(try await outbox.submit(hole(2, [(anna, 4)])) == .queued)
            outbox.stop()
        }
        // En annen logger inn på samme telefon: Thomas sine hull vises ikke og sendes ikke.
        sender.mode = .ok
        let outbox = makeOutbox()
        outbox.start(userID: per)
        await waitUntil { !sender.calls.isEmpty }
        #expect(sender.saved.isEmpty)
        #expect(outbox.pendingHoles(roundID: roundID).isEmpty)
        #expect(outbox.status.pendingCount == 0)
        outbox.stop()

        // Thomas logger inn igjen: hullet sendes.
        outbox.start(userID: thomas)
        await waitUntil { !sender.saved.isEmpty }
        #expect(sender.saved.map(\.holeIndex) == [2])
        outbox.stop()
    }

    @Test func advarselVedUtlogging() {
        #expect(SignOutButton.warning(pending: 1) == "1 hull er ikke sendt ennå. De sendes neste gang du logger inn på denne telefonen.")
        #expect(SignOutButton.warning(pending: 3).hasPrefix("3 hull er ikke sendt"))
    }

    @Test func backoffTider() {
        let backoff = OutboxBackoff()
        let seconds = (1...9).map { backoff.delay(afterFailures: $0) }
        #expect(seconds == [1, 2, 4, 8, 16, 32, 60, 60, 60].map { Duration.seconds($0) })
        #expect(backoff.delay(afterFailures: 0) == .seconds(1))
        #expect(backoff.delay(afterFailures: 1_000) == .seconds(60))
    }

    @Test func provIgjenMedBackoffTilKoenErTom() async throws {
        let outbox = makeOutbox()
        outbox.start()
        sender.mode = .offline
        #expect(try await outbox.submit(hole(0, [(anna, 4)])) == .queued)

        await waitUntil { clock.sleeps.count == 1 }
        clock.advance()
        await waitUntil { clock.sleeps.count == 2 }
        clock.advance()
        await waitUntil { clock.sleeps.count == 3 }
        #expect(clock.sleeps == [.seconds(1), .seconds(2), .seconds(4)])

        sender.mode = .ok
        clock.advance()
        await waitUntil { sender.saved.count == 1 }
        await waitUntil { outbox.status.pendingCount == 0 }
        for _ in 0..<50 { await Task.yield() }
        // Tom kø: ingen flere forsøk.
        #expect(clock.sleeps.count == 3)
        #expect(outbox.consecutiveFailures == 0)
        outbox.stop()
    }

    @Test func sendesNarNettetKommerTilbake() async throws {
        let outbox = makeOutbox()
        outbox.start()
        network.send(false)
        sender.mode = .offline
        #expect(try await outbox.submit(hole(7, [(anna, 4)])) == .queued)

        sender.mode = .ok
        network.send(true)
        await waitUntil { outbox.pendingHoles(roundID: roundID).isEmpty }
        #expect(sender.saved.map(\.holeIndex) == [7])
        #expect(outbox.pendingHoles(roundID: roundID).isEmpty)
        outbox.stop()
    }

    @Test func tidsavbruddGirKo() async throws {
        let outbox = makeOutbox(timeout: .milliseconds(50))
        sender.mode = .hang
        #expect(try await outbox.submit(hole(0, [(anna, 4)])) == .queued)
        #expect(outbox.pendingHoles(roundID: roundID) == [0])
        #expect(outbox.status.lastError == "Tidsavbrudd mot serveren.")
    }

    @Test func ukjentFeilProvesIgjen() async throws {
        let outbox = makeOutbox()
        sender.mode = .fail(.unknown("500"))
        #expect(try await outbox.submit(hole(0, [(anna, 4)])) == .queued)
        #expect(outbox.status.rejectedCount == 0)
    }

    @Test func pendingHolesPerRunde() async throws {
        let outbox = makeOutbox()
        let otherRound = UUID()
        sender.mode = .offline
        _ = try await outbox.submit(hole(0, [(anna, 4)]))
        _ = try await outbox.submit(hole(2, [(anna, 4)]))
        _ = try await outbox.submit(hole(1, round: otherRound, [(anna, 4)]))
        sender.mode = .fail(.notAllowed)
        _ = try? await outbox.submit(hole(5, [(anna, 4)]))

        #expect(outbox.pendingHoles(roundID: roundID) == [0, 2])
        #expect(outbox.pendingHoles(roundID: otherRound) == [1])
        #expect(outbox.status.pendingCount == 3)
        #expect(outbox.status.rejectedCount == 1)
    }
}
