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
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        update(from: settings.authorizationStatus)
        if status == .registering {
            UIApplication.shared.registerForRemoteNotifications()
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
    func unregister() async {
        guard PushFeature.isEnabled, let deviceID else { return }
        _ = try? await client.rpc("unregister_push_device", params: DeviceParam(p_device_id: deviceID)).execute()
        lastSent = nil
        userID = nil
    }

    func stop() {
        userID = nil
        lastSent = nil
    }

    private func update(from authorization: UNAuthorizationStatus) {
        switch authorization {
        case .notDetermined: status = .notDetermined
        case .denied: status = .denied
        case .authorized, .provisional, .ephemeral: status = .registering
        @unknown default: status = .notDetermined
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
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        PushTokenRelay.shared.deliver(.success(deviceToken))
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        PushTokenRelay.shared.deliver(.failure(error))
    }
}
