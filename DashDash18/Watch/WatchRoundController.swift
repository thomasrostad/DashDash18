import Foundation
import WatchConnectivity

/// Bryter for klokka. Kan slås av fra serveren: `ios_flags.watch` (sql/068).
nonisolated enum WatchFeature {
    static var isEnabled: Bool { !KillSwitch.isOff("watch") }
}

/// Sender runden som går til klokka (Apple Watch, og Garmin via `GarminLink`), og legger hull fra
/// klokka i utboksen. `RundeModel` kaller
/// `sync` hver gang runden er bygd på nytt (henting, realtime, lagring), som for Live Activity.
/// Feil tas stille: klokka er et tillegg, føringen på telefonen skal aldri stoppe av den.
@MainActor
final class WatchRoundController {
    static let shared = WatchRoundController()

    /// Et hull fra klokka er lagt i utboksen. Runde-skjermen henter, så hullet står og klokka får
    /// en nyere runde.
    static let received = Notification.Name("WatchRoundController.received")

    private var submitter: (any ScoreSubmitting)?
    private var delegate: SessionDelegate?
    /// Runden sist `sync` ble kalt, så den kan sendes når forbindelsen til klokka er klar.
    private var latest: (game: RoundGame?, viewer: Viewer)?
    /// Bare den nyeste utregningen sendes.
    private var generation = 0
    private var lastRound: WatchRound?
    /// Klokka har sendt et hull siden sist: neste runde sendes selv om innholdet er likt, så klokka
    /// ser at telefonen har tatt imot det.
    private var owesFreshRound = false

    /// Kalles én gang når appen starter (`AppServices`), også når klokka vekker den i bakgrunnen.
    func activate(submitter: any ScoreSubmitting) {
        guard WCSession.isSupported(), delegate == nil else { return }
        self.submitter = submitter
        let delegate = SessionDelegate(
            activated: { [weak self] in Task { @MainActor in self?.activated() } },
            received: { [weak self] entry in Task { @MainActor in await self?.receive(entry) } }
        )
        self.delegate = delegate
        WCSession.default.delegate = delegate
        WCSession.default.activate()
    }

    func sync(game: RoundGame?, viewer: Viewer) {
        guard WatchFeature.isEnabled else { return }
        latest = (game, viewer)
        // Uten klokke med appen regnes ingenting (de fleste telefonene).
        guard hasWatch || GarminLink.shared.isActive else { return }
        generation += 1
        let current = generation
        Task {
            let round = await Self.watchRound(game, viewer: viewer)
            guard current == generation else { return }
            publish(round)
        }
    }

    /// Hullkortet regnes for hvert hull og slagantall, så det skjer utenfor hovedtråden.
    @concurrent private nonisolated static func watchRound(_ game: RoundGame?, viewer: Viewer) async -> WatchRound? {
        game?.watchRound(for: viewer)
    }

    private func publish(_ round: WatchRound?) {
        if !owesFreshRound {
            switch (round, lastRound) {
            case (nil, nil): return
            case let (new?, old?) where new.sameContent(as: old): return
            default: break
            }
        }
        owesFreshRound = false
        lastRound = round
        send(round)
        GarminLink.shared.publish(round)
    }

    /// Ved utlogging: klokka viser ingen runde.
    func clear() {
        latest = nil
        generation += 1
        lastRound = nil
        send(nil)
        GarminLink.shared.publish(nil)
    }

    /// En klokke er koblet til (Garmin): regn runden på nytt og send den.
    func resync() {
        activated()
    }

    /// Forbindelsen er klar (også etter bytte av klokke): send runden slik den er nå.
    private func activated() {
        guard let latest else { return }
        lastRound = nil
        sync(game: latest.game, viewer: latest.viewer)
    }

    private var hasWatch: Bool {
        let session = WCSession.default
        return WCSession.isSupported() && session.activationState == .activated
            && session.isPaired && session.isWatchAppInstalled
    }

    private func send(_ round: WatchRound?) {
        guard hasWatch else { return }
        let session = WCSession.default
        let payload = round.flatMap { WatchMessage.payload($0, key: WatchMessage.round) } ?? [:]
        try? session.updateApplicationContext(payload)
    }

    private func receive(_ entry: WatchHoleEntry) async {
        guard let submitter else { return }
        owesFreshRound = true
        // Utboksen tar seg av resten: lagres før sending, nye forsøk uten nett, avvisning og konflikter.
        _ = try? await submitter.submit(HoleSubmission(watch: entry))
        NotificationCenter.default.post(name: Self.received, object: entry.roundID)
    }
}

private nonisolated extension WatchRound {
    /// Likt innhold, uansett når den ble laget.
    func sameContent(as other: WatchRound) -> Bool {
        roundID == other.roundID && title == other.title && currentHole == other.currentHole
            && holes == other.holes && standings == other.standings
    }
}

/// WatchConnectivity kaller på en egen kø. Meldingen pakkes ut her, og bare verdier sendes videre.
private nonisolated final class SessionDelegate: NSObject, WCSessionDelegate {
    private let activated: @Sendable () -> Void
    private let received: @Sendable (WatchHoleEntry) -> Void

    init(activated: @escaping @Sendable () -> Void, received: @escaping @Sendable (WatchHoleEntry) -> Void) {
        self.activated = activated
        self.received = received
    }

    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: (any Error)?) {
        if state == .activated { activated() }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    /// Brukeren har byttet klokke: koble til den nye.
    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let entry = WatchMessage.value(WatchHoleEntry.self, key: WatchMessage.hole, in: userInfo) else { return }
        received(entry)
    }
}
