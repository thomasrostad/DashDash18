import SwiftUI

@main
struct DashDash18App: App {
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
