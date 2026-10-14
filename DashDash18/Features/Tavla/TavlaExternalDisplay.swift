import Observation
import SwiftUI
import UIKit

/// Tavla på en TV via AirPlay eller kabel (V5). Når telefonen speiler skjermen, lager iOS en egen scene
/// med rollen `windowExternalDisplayNonInteractive`. Den viser TV-tavla i liggende format i stedet for
/// et speilbilde av telefonen. Tabellen er den Tavla sist viste (`model`); uten den står en kort
/// beskjed om å åpne Tavla.
///
/// Ingen endring i prosjektfilen trengs: scenen settes opp i koden (`PushAppDelegate`, som er appens
/// `UIApplicationDelegateAdaptor`), ikke i scene-manifestet i Info.plist.
@Observable
final class TavlaExternalDisplay {
    static let shared = TavlaExternalDisplay()

    /// Tavla-modellen som sist ble vist på telefonen.
    var model: TavlaModel?
    /// Er en ekstern skjerm koblet til nå?
    private(set) var isConnected = false

    /// Hvor ofte TV-en henter tabellen selv. Mens Tavla er åpen på telefonen, kommer endringene
    /// i tillegg med en gang via realtime.
    static let reloadInterval: Duration = .seconds(30)

    fileprivate func connected(_ on: Bool) {
        isConnected = on
        // Telefonen skal ikke låse seg mens den sender Tavla til TV-en: da stopper overføringen.
        UIApplication.shared.isIdleTimerDisabled = on
    }
}

/// Scenen på den eksterne skjermen.
final class TavlaExternalSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = UIHostingController(rootView: TavlaExternalRoot().ddAppStyle())
        window.isHidden = false
        self.window = window
        TavlaExternalDisplay.shared.connected(true)
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        window = nil
        TavlaExternalDisplay.shared.connected(false)
    }
}

extension PushAppDelegate {
    /// Den eksterne skjermen får TV-tavla (V5). Alle andre scener settes opp av SwiftUI som før.
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        if connectingSceneSession.role == .windowExternalDisplayNonInteractive {
            configuration.delegateClass = TavlaExternalSceneDelegate.self
        }
        return configuration
    }
}

/// Innholdet på TV-en: tavla, eller en beskjed når Tavla ikke er åpnet ennå.
struct TavlaExternalRoot: View {
    private let display = TavlaExternalDisplay.shared

    var body: some View {
        if let model = display.model {
            TavlaTVView(model: model, external: true)
                .task(id: ObjectIdentifier(model)) {
                    while !Task.isCancelled {
                        try? await Task.sleep(for: TavlaExternalDisplay.reloadInterval)
                        guard !Task.isCancelled else { break }
                        await model.load()
                    }
                }
        } else {
            VStack(spacing: 16) {
                Text("Atten")
                    .font(.system(size: 64, weight: .semibold))
                Text("Åpne Tavla på telefonen for å vise tabellen her.")
                    .font(.system(size: 30))
                    .opacity(0.85)
            }
            .foregroundStyle(Color.ddOnDark)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.ddForestDeep)
            .preferredColorScheme(.dark)
        }
    }
}
