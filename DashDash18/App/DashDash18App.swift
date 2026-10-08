import SwiftUI

@main
struct DashDash18App: App {
    /// Tar imot APNs-tokenet (fase 8). Gjør ingenting når `PushFeature` er av.
    @UIApplicationDelegateAdaptor(PushAppDelegate.self) private var pushDelegate
    private let services = Result { () throws(AppConfig.LoadError) -> AppServices in
        AppServices(config: try AppConfig.load())
    }

    init() {
        DDAppearance.configure()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-DDDesignCatalog") {
                    // Bare for utvikling: åpner designkatalogen uten innlogging (skjermbilder).
                    NavigationStack { DesignCatalogView() }
                } else if let i = ProcessInfo.processInfo.arguments.firstIndex(of: "-DDDesignScreen"),
                          i + 1 < ProcessInfo.processInfo.arguments.count,
                          let screen = DesignScreenSamples.Screen(rawValue: ProcessInfo.processInfo.arguments[i + 1]) {
                    DesignScreenSamples(screen: screen)
                } else {
                    content
                }
                #else
                content
                #endif
            }
            .ddAppStyle()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch services {
        case .success(let services):
            AppRoot(services: services)
        case .failure(let error):
            ConfigErrorView(error: error)
        }
    }
}
