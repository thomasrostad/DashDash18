import Foundation
import Observation
import Supabase
import UIKit
import UserNotifications

/// Det `PushAppDelegate` får fra iOS, videre til `PushRegistrar`. iOS kan svare før registraren
/// er klar (oppstart), så det siste svaret tas vare på.
@MainActor
final class PushTokenRelay {
    static let shared = PushTokenRelay()

    private(set) var latest: Result<Data, any Error>?
    private var handler: ((Result<Data, any Error>) -> Void)?

    func deliver(_ result: Result<Data, any Error>) {
        latest = result
        handler?(result)
    }

    /// Setter mottakeren og gir den det som alt har kommet.
    func connect(_ handler: @escaping (Result<Data, any Error>) -> Void) {
        self.handler = handler
        if let latest { handler(latest) }
    }
}

nonisolated private struct DeviceParam: Encodable, Sendable {
    let p_device_id: String
}

/// Det vi sjekker tilbake fra `register_push_device`.
nonisolated private struct RegisteredDevice: Decodable, Sendable {
    let token: String
}

/// Ber om varseltillatelse, registrerer telefonen hos APNs og sender tokenet til
/// `register_push_device` (sql/010_push.sql). Gjør ingenting når `PushFeature.isEnabled` er av.
@Observable
final class PushRegistrar {
    enum Status: Equatable {
        /// Push er slått av i appen (bryteren), eller ikke startet.
        case disabled
        case notDetermined
        case denied
        /// Tillatelse gitt; venter på tokenet fra APNs.
        case registering
        case registered
        case failed(String)
    }

    private(set) var status: Status = .disabled
    private let client: SupabaseClient
    private var userID: UUID?
    private var lastSent: (userID: UUID, token: String)?

    init(client: SupabaseClient) {
        self.client = client
    }

    /// Fast id for telefonen (per leverandør). Brukes til å ta over raden når en annen logger inn.
    private var deviceID: String? { UIDevice.current.identifierForVendor?.uuidString.lowercased() }

    /// Etter innlogging: registrer på nytt hvis tillatelsen alt er gitt (tokenet kan ha endret
    /// seg). Spør ikke om tillatelse her; det gjør `requestAuthorization()` fra innstillingene.
    func start(userID: UUID) async {
        guard PushFeature.isEnabled else { return }
        self.userID = userID
        PushTokenRelay.shared.connect { [weak self] result in
            guard let self else { return }
            Task { await self.receive(result) }
        }
        await refreshAuthorization()
    }

    /// Leser tillatelsen på nytt, f.eks. når du kommer tilbake fra Innstillinger. Er den
    /// nettopp gitt, registreres telefonen hos APNs; er den tatt bort, vises det.
    func refreshAuthorization() async {
        guard PushFeature.isEnabled, userID != nil else { return }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        status = Self.nextStatus(Self.permission(settings.authorizationStatus), current: status)
        if status == .registering {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    /// Ny status etter at tillatelsen er lest. En telefon som alt er registrert i denne
    /// økten, blir stående som registrert.
    static func nextStatus(_ permission: PushPermission, current: Status) -> Status {
        switch permission {
        case .notDetermined: .notDetermined
        case .denied: .denied
        case .allowed: current == .registered ? .registered : .registering
        }
    }

    /// «Slå på varsler»: spør iOS, og registrer hos APNs hvis svaret er ja.
    func requestAuthorization() async {
        guard PushFeature.isEnabled else { return }
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            status = granted ? .registering : .denied
            if granted { UIApplication.shared.registerForRemoteNotifications() }
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    /// Før utlogging: fjern telefonen, så den forrige innloggingen ikke får push her.
    /// Må skje mens økten finnes (RPC-en krever innlogging).
    /// Uten nett gis det opp etter `unregisterTimeLimit`, så utloggingen ikke henger. Raden tas
    /// da over av neste som logger inn på telefonen (`register_push_device`).
    func unregister() async {
        guard PushFeature.isEnabled, let deviceID else { return }
        let client = client
        let call = Task {
            _ = try? await client.rpc("unregister_push_device", params: DeviceParam(p_device_id: deviceID)).execute()
        }
        let timer = Task {
            try? await Task.sleep(for: Self.unregisterTimeLimit)
            call.cancel()
        }
        await call.value
        timer.cancel()
        lastSent = nil
        userID = nil
    }

    static let unregisterTimeLimit: Duration = .seconds(5)

    func stop() {
        userID = nil
        lastSent = nil
    }

    private static func permission(_ authorization: UNAuthorizationStatus) -> PushPermission {
        switch authorization {
        case .denied: .denied
        case .authorized, .provisional, .ephemeral: .allowed
        case .notDetermined: .notDetermined
        @unknown default: .notDetermined
        }
    }

    private func receive(_ result: Result<Data, any Error>) async {
        switch result {
        case .failure(let error):
            status = .failed(error.localizedDescription)
        case .success(let data):
            await send(token: PushToken.hex(data))
        }
    }

    private func send(token: String) async {
        guard PushFeature.isEnabled, let userID, let deviceID, PushToken.isValid(token) else { return }
        // Samme token for samme innlogging er alt sendt i denne økten.
        if let lastSent, lastSent.userID == userID, lastSent.token == token {
            status = .registered
            return
        }
        let registration = PushDeviceRegistration(
            deviceID: deviceID,
            token: token,
            environment: .current,
            bundleID: Bundle.main.bundleIdentifier
        )
        do {
            let rows: [RegisteredDevice] = try await client.rpc("register_push_device", params: registration).execute().value
            // Sjekk raden tilbake (CLAUDE.md): RLS eller en feil kan gi tom liste uten feilkode.
            guard rows.first?.token == token else {
                status = .failed(DataError.notAllowed.message)
                return
            }
            lastSent = (userID, token)
            status = .registered
        } catch {
            status = .failed(DataError.from(error).message)
        }
    }
}

/// Tar imot svaret fra APNs. Koblet inn med `@UIApplicationDelegateAdaptor` i `DashDash18App`.
/// iOS kaller disse bare etter `registerForRemoteNotifications()`, som bare skjer når
/// `PushFeature.isEnabled` er på.
final class PushAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Må settes før oppstarten er ferdig, ellers går et trykk på pushen tapt.
        if PushFeature.isEnabled { UNUserNotificationCenter.current().delegate = self }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        PushTokenRelay.shared.deliver(.success(deviceToken))
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        PushTokenRelay.shared.deliver(.failure(error))
    }
}

/// Push mens appen står åpen, og trykk på en push. Uten denne viser iOS ingenting når appen
/// er framme, og bjella står stille til appen åpnes på nytt.
extension PushAppDelegate: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        let target = PushTarget(userInfo: notification.request.content.userInfo)
        let show = await MainActor.run {
            PushInbox.didReceive()
            return PushForeground.shouldShow(target, visibleThreadEventID: PushInbox.visibleThreadEventID)
        }
        return show ? [.banner, .list, .sound] : []
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        await MainActor.run { PushInbox.didReceive() }
    }
}

/// Det appen trenger å vite når en push kommer: hvilken tråd som står framme, og hvem som vil
/// vite at det kom noe (bjella henter antall uleste på nytt).
enum PushInbox {
    /// Tråden som vises nå (settes av `TradView`).
    static var visibleThreadEventID: UUID?

    static let received = Notification.Name("DashDash18.pushReceived")

    static func didReceive() {
        NotificationCenter.default.post(name: received, object: nil)
    }
}
