import ConnectIQ
import Foundation
import Observation

/// Garmin vises bare i test-bygg (TestFlight fra main) til Garmin-appen er i Connect IQ Store
/// (docs/plan-garmin.md). Kan slås av fra serveren: `ios_flags.garmin` (sql/068).
nonisolated enum GarminFeature {
    static var isEnabled: Bool { AppEnvironment.current == .test && !KillSwitch.isOff("garmin") }
}

/// Atten og Garmin-appen (`garmin/`) via Garmins Connect IQ Mobile SDK. Garmin får det samme hullet
/// som Apple Watch (`WatchRound`, ett hull om gangen), og hull fra Garmin går i utboksen som hull fra
/// Apple Watch og hullkortet. Klokkene velges i Garmin Connect (Deg → Garmin-klokke) og huskes her.
@MainActor
@Observable
final class GarminLink {
    static let shared = GarminLink()

    /// URL-skjemaet Garmin Connect svarer til med klokkene (Info.plist).
    static let urlScheme = "atten-garmin"
    /// Garmin-appens id (`garmin/manifest.xml`).
    static let appID = UUID(uuidString: "df4f21f2-5266-49f4-baac-635fdd298301")!
    /// Betaen i Connect IQ Store har egen id (`garmin/tools/build.sh beta`). Atten snakker med begge,
    /// så klokka virker uansett hvilken som er installert.
    static let betaAppID = UUID(uuidString: "944279ed-9285-4eb2-b674-f1b9b70a14c3")!

    /// En klokke slik «Deg» viser den.
    struct Watch: Identifiable, Equatable {
        let id: UUID
        let name: String
        var isConnected: Bool
    }

    private(set) var watches: [Watch] = []

    /// Minst én klokke er koblet til: da regnes klokkerunden også uten Apple Watch.
    var isActive: Bool { watches.contains(where: \.isConnected) }

    @ObservationIgnored private var devices: [UUID: IQDevice] = [:]
    @ObservationIgnored private var delegate: GarminDelegate?
    @ObservationIgnored private var submitter: (any ScoreSubmitting)?
    @ObservationIgnored private var started = false
    @ObservationIgnored private var round: WatchRound?
    /// Hullet hver klokke viser, så en ny runde fra telefonen ikke flytter den.
    @ObservationIgnored private var shownHole: [UUID: Int] = [:]
    /// Det hver klokke sist fikk, så like meldinger ikke sendes på nytt over Bluetooth.
    @ObservationIgnored private var lastSent: [UUID: NSDictionary] = [:]

    private static let devicesKey = "garminDevices"

    /// Kalles én gang når appen starter (`AppServices`), også når Bluetooth vekker den i bakgrunnen.
    func start(submitter: any ScoreSubmitting) {
        guard GarminFeature.isEnabled, !started else { return }
        started = true
        self.submitter = submitter
        let delegate = GarminDelegate(
            status: { [weak self] id, connected in Task { @MainActor in self?.status(id, connected: connected) } },
            received: { [weak self] id, incoming in Task { @MainActor in await self?.receive(incoming, from: id) } }
        )
        self.delegate = delegate
        ConnectIQ.sharedInstance().initialize(withUrlScheme: Self.urlScheme, uiOverrideDelegate: nil,
                                              stateRestorationIdentifier: Self.urlScheme)
        use(Self.restoredDevices())
    }

    /// «Koble til Garmin-klokke»: Garmin Connect åpnes, og svarer med klokkene til `handle`.
    func chooseWatches() {
        ConnectIQ.sharedInstance().showDeviceSelection()
    }

    /// Svaret fra Garmin Connect. Gir false for lenker som ikke er Garmins.
    func handle(_ url: URL) -> Bool {
        guard url.scheme == Self.urlScheme else { return false }
        let chosen = (ConnectIQ.sharedInstance().parseDeviceSelectionResponse(from: url) as? [IQDevice]) ?? []
        Self.save(chosen)
        use(chosen)
        return true
    }

    /// Runden fra `WatchRoundController`, slik den sendes til Apple Watch. Nil: ingen runde.
    func publish(_ round: WatchRound?) {
        if self.round?.roundID != round?.roundID { shownHole = [:] }
        self.round = round
        for id in devices.keys { send(to: id) }
    }

    // MARK: Klokkene

    private func use(_ chosen: [IQDevice]) {
        guard let delegate else { return }
        ConnectIQ.sharedInstance().unregister(forAllDeviceEvents: delegate)
        ConnectIQ.sharedInstance().unregister(forAllAppMessages: delegate)
        devices = Dictionary(chosen.map { ($0.uuid, $0) }, uniquingKeysWith: { a, _ in a })
        lastSent = [:]
        for device in chosen {
            ConnectIQ.sharedInstance().register(forDeviceEvents: device, delegate: delegate)
            for app in apps(device) {
                ConnectIQ.sharedInstance().register(forAppMessages: app, delegate: delegate)
            }
        }
        watches = chosen.map { device in
            Watch(id: device.uuid, name: device.friendlyName ?? device.modelName ?? "Garmin",
                  isConnected: ConnectIQ.sharedInstance().getDeviceStatus(device) == .connected)
        }
        WatchRoundController.shared.resync()
    }

    private func status(_ id: UUID, connected: Bool) {
        guard let i = watches.firstIndex(where: { $0.id == id }) else { return }
        watches[i].isConnected = connected
        if connected {
            lastSent[id] = nil
            // Telefonen regner klokkerunden bare når en klokke er koblet til.
            WatchRoundController.shared.resync()
            send(to: id)
        }
    }

    /// Appen og betaen på klokka. Den som ikke er installert, får bare en feil tilbake.
    private func apps(_ device: IQDevice) -> [IQApp] {
        [Self.appID, Self.betaAppID].map { IQApp(uuid: $0, store: $0, device: device) }
    }

    // MARK: Meldinger

    private func receive(_ incoming: GarminMessage.Incoming, from id: UUID) async {
        switch incoming {
        case .hello:
            lastSent[id] = nil
        case .get(let roundID, let hole):
            guard roundID == round?.roundID else { break }
            shownHole[id] = hole
            lastSent[id] = nil
        case .save(let entry):
            if let count = round?.holes.count, entry.roundID == round?.roundID {
                shownHole[id] = min(entry.holeIndex + 1, count - 1)
            }
            lastSent[id] = nil
            // Utboksen tar seg av resten, som for Apple Watch og hullkortet.
            _ = try? await submitter?.submit(HoleSubmission(watch: entry))
            NotificationCenter.default.post(name: WatchRoundController.received, object: entry.roundID)
        }
        send(to: id)
    }

    private func send(to id: UUID) {
        guard let device = devices[id], ConnectIQ.sharedInstance().getDeviceStatus(device) == .connected else { return }
        let message: [String: Any]
        if let round {
            message = GarminMessage.hole(round, index: shownHole[id] ?? round.currentHole) ?? GarminMessage.none
        } else {
            message = GarminMessage.none
        }
        let dictionary = message as NSDictionary
        guard lastSent[id] != dictionary else { return }
        lastSent[id] = dictionary
        let targets = apps(device)
        let tally = SendTally(count: targets.count)
        for app in targets {
            ConnectIQ.sharedInstance().sendMessage(message, to: app, progress: nil) { [weak self] result in
                Task { @MainActor in
                    // Kom den ikke fram til noen av dem: prøv igjen neste gang runden endres eller klokka spør.
                    if tally.finish(success: result == .success) == false { self?.lastSent[id] = nil }
                }
            }
        }
    }

    // MARK: Lagring av klokkene

    private static func restoredDevices() -> [IQDevice] {
        guard let data = UserDefaults.standard.data(forKey: devicesKey) else { return [] }
        let classes: [AnyClass] = [NSArray.self, IQDevice.self, NSUUID.self, NSString.self]
        return (try? NSKeyedUnarchiver.unarchivedObject(ofClasses: classes, from: data) as? [IQDevice]) ?? []
    }

    /// Garmin Connect sier hvilke klokker brukeren har valgt: bare de huskes, som Garmin anbefaler.
    private static func save(_ devices: [IQDevice]) {
        let data = try? NSKeyedArchiver.archivedData(withRootObject: devices, requiringSecureCoding: true)
        UserDefaults.standard.set(data, forKey: devicesKey)
    }
}

/// Sendingen til appen og betaen: den ene er som regel ikke installert.
@MainActor
private final class SendTally {
    private var remaining: Int
    private var delivered = false

    init(count: Int) { remaining = count }

    /// Nil til alle har svart, så om noen fikk meldingen.
    func finish(success: Bool) -> Bool? {
        remaining -= 1
        delivered = delivered || success
        return remaining == 0 ? delivered : nil
    }
}

/// Connect IQ kaller utenfor hovedtråden. Meldingen tolkes her, og bare verdier sendes videre.
private nonisolated final class GarminDelegate: NSObject, IQDeviceEventDelegate, IQAppMessageDelegate {
    private let status: @Sendable (UUID, Bool) -> Void
    private let received: @Sendable (UUID, GarminMessage.Incoming) -> Void

    init(status: @escaping @Sendable (UUID, Bool) -> Void,
         received: @escaping @Sendable (UUID, GarminMessage.Incoming) -> Void) {
        self.status = status
        self.received = received
    }

    func deviceStatusChanged(_ device: IQDevice, status: IQDeviceStatus) {
        self.status(device.uuid, status == .connected)
    }

    func receivedMessage(_ message: Any, from app: IQApp) {
        guard let incoming = GarminMessage.incoming(message, now: .now) else { return }
        received(app.device.uuid, incoming)
    }
}
