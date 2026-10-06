import SwiftUI

@main
struct DashDash18App: App {
    private let config = Result { () throws(AppConfig.LoadError) -> AppConfig in
        try AppConfig.load()
    }

    var body: some Scene {
        WindowGroup {
            switch config {
            case .success(let config):
                AppRoot(config: config)
            case .failure(let error):
                ConfigErrorView(error: error)
            }
        }
    }
}
