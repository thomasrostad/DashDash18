import SwiftUI

@main
struct DashDash18App: App {
    private let services = Result { () throws(AppConfig.LoadError) -> AppServices in
        AppServices(config: try AppConfig.load())
    }

    var body: some Scene {
        WindowGroup {
            switch services {
            case .success(let services):
                AppRoot(services: services)
            case .failure(let error):
                ConfigErrorView(error: error)
            }
        }
    }
}
