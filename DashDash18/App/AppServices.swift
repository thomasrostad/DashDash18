import Supabase

/// Det appen trenger én av: konfig, Supabase-klienten og tilstandsmodellene.
/// Lages én gang når appen starter.
final class AppServices {
    let config: AppConfig
    let client: SupabaseClient
    let auth: AuthModel
    let club: ClubModel
    /// Lagring av hull. Byttes til utboksen når den er på plass (fase 5).
    let scoreSubmitter: any ScoreSubmitting

    init(config: AppConfig) {
        self.config = config
        client = SupabaseClient(
            supabaseURL: config.supabaseURL,
            supabaseKey: config.publishableKey,
            options: SupabaseClientOptions(auth: .init(emitLocalSessionAsInitialSession: true))
        )
        auth = AuthModel(client: client)
        club = ClubModel(client: client)
        scoreSubmitter = DirectScoreSubmitter(client: client)
    }
}
