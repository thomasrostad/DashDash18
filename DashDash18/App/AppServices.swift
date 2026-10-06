import Supabase
import SwiftData

/// Det appen trenger én av: konfig, Supabase-klienten og tilstandsmodellene.
/// Lages én gang når appen starter.
final class AppServices {
    let config: AppConfig
    let client: SupabaseClient
    let auth: AuthModel
    let club: ClubModel
    /// Utboksen for hull (fase 5). Startes når brukeren er innlogget.
    let outbox: OutboxScoreSubmitter
    /// Lagring av hull: utboksen utenpå `DirectScoreSubmitter`.
    var scoreSubmitter: any ScoreSubmitting { outbox }

    init(config: AppConfig) {
        self.config = config
        client = SupabaseClient(
            supabaseURL: config.supabaseURL,
            supabaseKey: config.publishableKey,
            options: SupabaseClientOptions(auth: .init(emitLocalSessionAsInitialSession: true))
        )
        auth = AuthModel(client: client)
        club = ClubModel(client: client)
        outbox = OutboxScoreSubmitter(inner: DirectScoreSubmitter(client: client), container: Self.makeOutboxContainer())
    }

    /// Egen lagringsfil for utboksen. Går ikke det, brukes minnet så appen likevel starter
    /// (hull i kø overlever da ikke at appen blir drept).
    private static func makeOutboxContainer() -> ModelContainer {
        do {
            return try OutboxScoreSubmitter.makeContainer()
        } catch {
            assertionFailure("Utboksen fikk ikke åpnet lageret: \(error)")
            return try! OutboxScoreSubmitter.makeContainer(inMemory: true)
        }
    }
}
