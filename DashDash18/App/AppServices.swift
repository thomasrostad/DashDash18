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
    /// Push (fase 8).
    let push: PushRegistrar
    /// Feilsporing med MetricKit (fase 17, sql/064).
    let diagnostics: DiagnosticsReporter
    /// Lagring av hull: utboksen utenpå `DirectScoreSubmitter`.
    var scoreSubmitter: any ScoreSubmitting { outbox }

    init(config: AppConfig) {
        self.config = config
        // Før klienten lages: en økt fra en tidligere installasjon skal ikke brukes.
        FreshInstallGuard.run()
        // Byttet mellom test og prod: data fra den andre basen ryddes før utboksen åpnes.
        EnvironmentSwitchGuard.run(currentRef: config.projectRef)
        client = SupabaseClient(
            supabaseURL: config.supabaseURL,
            supabaseKey: config.publishableKey,
            options: SupabaseClientOptions(auth: .init(emitLocalSessionAsInitialSession: true))
        )
        auth = AuthModel(client: client, captchaSiteKey: config.turnstileSiteKey)
        club = ClubModel(client: client)
        outbox = OutboxScoreSubmitter(inner: DirectScoreSubmitter(client: client), container: Self.makeOutboxContainer())
        push = PushRegistrar(client: client)
        diagnostics = DiagnosticsReporter(sender: SupabaseDiagnosticsSender(client: client))
        // Tidlig, så diagnosene fra forrige kjøring (krasj, heng) kommer med en gang.
        diagnostics.subscribe()
        // Før noe vises: klokka kan vekke appen i bakgrunnen med et hull som skal i utboksen.
        WatchRoundController.shared.activate(submitter: outbox)
        GarminLink.shared.start(submitter: outbox)
        // Telefonen fjernes mens økten finnes, så den forrige innloggingen ikke får push her.
        auth.willSignOut = { [push] in await push.unregister() }
        // Slettet konto: hullene som ikke ble sendt, og innstillingene for kontoen, fjernes også her.
        auth.didDeleteAccount = { [outbox] userID in
            outbox.removeAll(userID: userID)
            LocalDataReset.removeAccountData(userID: userID)
        }
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
