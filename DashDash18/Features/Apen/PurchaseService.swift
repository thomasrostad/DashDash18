import Foundation
import Observation
import StoreKit
import Supabase

/// Det `PurchaseService` trenger fra serveren. Egen protokoll, så flyten kan prøves uten nett.
nonisolated protocol PurchaseBackend: Sendable {
    /// Edge Function `verify-purchase`: serveren henter transaksjonen fra App Store og skriver
    /// `entitlements`. Gir raden tilbake.
    func verify(transactionID: UInt64, competitionID: UUID?, clubID: UUID?) async throws -> EntitlementRow
    /// Mine kjøp (RLS: egne og klubbens som arrangør).
    func entitlements() async throws -> [EntitlementRow]
    /// Koble en ledig kreditt til en turnering (`assign_purchase`, sql/023).
    func assign(entitlementID: UUID, competitionID: UUID) async throws
    /// Serverens svar på om turneringen er låst opp (`competition_is_unlocked`).
    func isUnlocked(competitionID: UUID) async throws -> Bool
}

nonisolated struct SupabasePurchaseBackend: PurchaseBackend {
    let client: SupabaseClient

    private struct VerifyBody: Encodable {
        let transactionId: String
        let competitionId: UUID?
        let clubId: UUID?
    }

    private struct VerifyResponse: Decodable {
        let ok: Bool
        let entitlement: EntitlementRow?
        let error: String?
    }

    func verify(transactionID: UInt64, competitionID: UUID?, clubID: UUID?) async throws -> EntitlementRow {
        do {
            let response: VerifyResponse = try await client.functions.invoke(
                "verify-purchase",
                options: FunctionInvokeOptions(body: VerifyBody(
                    transactionId: String(transactionID), competitionId: competitionID, clubId: clubID
                ))
            )
            guard response.ok, let row = response.entitlement else {
                throw PurchaseError.serverRejected(response.error ?? "ukjent svar")
            }
            return row
        } catch let FunctionsError.httpError(_, data) {
            let response = try? JSONDecoder().decode(VerifyResponse.self, from: data)
            throw PurchaseError.serverRejected(response?.error ?? "serveren sa nei")
        }
    }

    func entitlements() async throws -> [EntitlementRow] {
        try await client.from("entitlements").select(EntitlementRow.columns).execute().value
    }

    func assign(entitlementID: UUID, competitionID: UUID) async throws {
        struct Params: Encodable {
            let p_entitlement_id: UUID
            let p_competition_id: UUID
        }
        try await client.rpc("assign_purchase", params: Params(p_entitlement_id: entitlementID, p_competition_id: competitionID))
            .execute()
    }

    func isUnlocked(competitionID: UUID) async throws -> Bool {
        struct Params: Encodable { let p_competition_id: UUID }
        return try await client.rpc("competition_is_unlocked", params: Params(p_competition_id: competitionID))
            .execute().value
    }
}

/// Kjøp i appen med StoreKit 2: produktene med pris fra App Store, kjøp, gjenoppretting og en
/// lytter på transaksjoner som kommer utenom kjøpsarket (Kjøpsforespørsel, fornyelser, refusjon,
/// kjøp på en annen enhet). En transaksjon fullføres (`finish()`) først når serveren har
/// registrert den, så et kjøp aldri går tapt.
///
/// Koblingen til fase 15: `CompetitionPurchase.isUnlocked(…, purchases:)` leser `entitlements`
/// (abonnement eller ledig kreditt), «Ny konkurranse» viser `PaywallView` for liga og cup som ikke
/// er låst opp, og kreditten kobles til turneringen når den er laget.
@Observable
final class PurchaseService {
    enum State: Equatable {
        case idle
        case loadingProducts
        case purchasing
        case restoring
        case failed(PurchaseError)
    }

    private(set) var products: [String: Product] = [:]
    private(set) var entitlements: [EntitlementRow] = []
    private(set) var state: State = .idle
    /// Siste kjøp som ble registrert (for «Takk»-teksten).
    private(set) var lastUnlocked: UUID?

    private let backend: any PurchaseBackend
    private let profileID: UUID
    private let pending: PendingPurchaseStore
    @ObservationIgnored private var listener: Task<Void, Never>?

    init(backend: any PurchaseBackend, profileID: UUID, pending: PendingPurchaseStore = PendingPurchaseStore()) {
        self.backend = backend
        self.profileID = profileID
        self.pending = pending
    }

    convenience init(client: SupabaseClient, profileID: UUID) {
        self.init(backend: SupabasePurchaseBackend(client: client), profileID: profileID)
    }

    // MARK: Lytteren

    /// Startes én gang når du er logget inn (og `PurchaseFeature` er på). Tar også transaksjoner
    /// som ikke ble fullført sist (appen ble lukket før serveren svarte).
    func start() {
        guard listener == nil else { return }
        listener = Task { [weak self] in
            for await result in Transaction.unfinished {
                await self?.handle(result)
            }
            for await result in Transaction.updates {
                await self?.handle(result)
            }
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    // MARK: Produkter

    func loadProducts() async {
        guard products.isEmpty else { return }
        state = .loadingProducts
        do {
            let loaded = try await Product.products(for: PurchaseProduct.ids)
            products = Dictionary(loaded.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            state = loaded.isEmpty ? .failed(.productsUnavailable) : .idle
        } catch {
            state = .failed(.productsUnavailable)
        }
    }

    /// Prisen slik App Store viser den (riktig valuta og avgift), eller nil før produktene er hentet.
    func displayPrice(_ product: PurchaseProduct) -> String? {
        products[product.rawValue]?.displayPrice
    }

    // MARK: Kjøp

    /// Kjøp for en turnering (forbrukbar) eller abonnement (for deg, eller klubben når `clubID` er satt).
    /// Har du en ledig kreditt, brukes den i stedet for et nytt kjøp.
    func purchase(_ product: PurchaseProduct, competitionID: UUID?, clubID: UUID? = nil) async {
        if product.kind == .consumable, let competitionID, let credit = CompetitionUnlock.unusedCredit(in: entitlements) {
            await use(credit: credit, for: competitionID)
            return
        }
        guard let storeProduct = products[product.rawValue] else {
            state = .failed(.productsUnavailable)
            return
        }
        state = .purchasing
        pending.setTarget(competitionID)
        do {
            // appAccountToken = profil-id-en: serveren sjekker at kjøpet hører til kontoen.
            let result = try await storeProduct.purchase(options: [.appAccountToken(profileID)])
            switch result {
            case .success(let verification):
                await handle(verification, clubID: clubID)
            case .pending:
                state = .failed(.pending)
            case .userCancelled:
                pending.setTarget(nil)
                state = .idle
            @unknown default:
                state = .idle
            }
        } catch {
            state = .failed(.unknown(error.localizedDescription))
        }
    }

    /// «Gjenopprett kjøp»: synker med App Store (abonnement), registrerer det som ikke er
    /// registrert, og henter kjøpene fra serveren (der også forbrukbare kjøp står).
    func restore() async {
        state = .restoring
        try? await AppStore.sync()
        for await result in Transaction.currentEntitlements {
            await handle(result)
        }
        for await result in Transaction.unfinished {
            await handle(result)
        }
        await refreshEntitlements()
        if case .restoring = state { state = .idle }
    }

    func refreshEntitlements() async {
        if let rows = try? await backend.entitlements() { entitlements = rows }
    }

    // MARK: Låst opp?

    /// Fra kjøpene som er hentet (virker uten nett).
    func isUnlocked(_ competition: CompetitionPurchaseInfo, now: Date = .now) -> Bool {
        CompetitionUnlock.isUnlocked(competition, entitlements: entitlements, now: now)
    }

    /// Serverens svar (fasit).
    func serverIsUnlocked(_ competitionID: UUID) async -> Bool? {
        try? await backend.isUnlocked(competitionID: competitionID)
    }

    // MARK: Internt

    private func use(credit: EntitlementRow, for competitionID: UUID) async {
        state = .purchasing
        do {
            try await backend.assign(entitlementID: credit.id, competitionID: competitionID)
            lastUnlocked = competitionID
            await refreshEntitlements()
            state = .idle
        } catch {
            state = .failed(.serverRejected(DataError.from(error).message))
        }
    }

    private func handle(_ result: VerificationResult<Transaction>, clubID: UUID? = nil) async {
        guard case .verified(let transaction) = result else {
            state = .failed(.notVerified)
            return
        }
        guard PurchaseProduct.ids.contains(transaction.productID) else { return }
        pending.attach(transactionID: transaction.id)
        let competitionID = pending.target(for: transaction.id)
        do {
            let row = try await backend.verify(transactionID: transaction.id, competitionID: competitionID, clubID: clubID)
            await transaction.finish()
            pending.done(transactionID: transaction.id)
            if let unlocked = row.competitionID { lastUnlocked = unlocked }
            await refreshEntitlements()
            if state == .purchasing { state = .idle }
        } catch let error as PurchaseError {
            state = .failed(error)
        } catch is URLError {
            // Ikke fullført: lytteren tar den igjen neste gang appen starter.
            state = .failed(.offline)
        } catch {
            state = .failed(.unknown(error.localizedDescription))
        }
    }
}
