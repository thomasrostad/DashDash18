import Supabase
import SwiftUI

/// Velger mellom oppstart, innlogging og selve appen. Ingenting hentes før du er logget inn,
/// fordi databasen avviser alt fra uinnloggede (skjema v1).
struct AppRoot: View {
    let config: AppConfig
    @State private var auth: AuthModel

    init(config: AppConfig) {
        self.config = config
        let client = SupabaseClient(
            supabaseURL: config.supabaseURL,
            supabaseKey: config.publishableKey,
            options: SupabaseClientOptions(auth: .init(emitLocalSessionAsInitialSession: true))
        )
        _auth = State(initialValue: AuthModel(client: client))
    }

    var body: some View {
        Group {
            switch auth.state {
            case .starting:
                ProgressView()
            case .signedOut:
                LoginView()
            case .signedIn(let user):
                RootView(config: config, user: user)
            }
        }
        .environment(auth)
        .task { await auth.observe() }
    }
}
