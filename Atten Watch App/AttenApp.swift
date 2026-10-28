import SwiftUI

/// Klokkeappen: føring av hullet og «Bayen nå» for runden som går på telefonen.
@main
struct AttenWatchApp: App {
    @State private var model = WatchModel()

    var body: some Scene {
        WindowGroup {
            WatchRootView(model: model)
                .task { model.activate() }
        }
    }
}
