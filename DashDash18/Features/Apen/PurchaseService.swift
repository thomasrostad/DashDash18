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
    let profileID: UUID
    private let pending: PendingPurchaseStore
    private let now: @Sendable () -> Date
    @ObservationIgnored private var listener: Task<Void, Never>?
    /// `purchase()` venter på App Store: da hører det ventende målet til det kjøpet, og ingen
    /// transaksjon utenom kan ta det.
    @ObservationIgnored private var isPurchasing = false
    /// Transaksjoner som verifiseres fra `purchase()` akkurat nå. Kommer den samme også i
    /// `Transaction.updates`, tar kjøpsflyten den.
    @ObservationIgnored private var handledByPurchase: Set<UInt64> = []

    init(backend: any PurchaseBackend, profileID: UUID, pending: PendingPurchaseStore = PendingPurchaseStore(),
         now: @escaping @Sendable () -> Date = { .now }) {
        self.backend = backend
        self.profileID = profileID
        self.pending = pending
        self.now = now
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
                await self?.handle(result, source: .background)
            }
            for await result in Transaction.updates {
                await self?.handle(result, source: .background)
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
        if product.kind == .consumable, let competitionID, let credit = CompetitionUnlock.unusedCredit(in: entitlements, owner: profileID) {
            await use(credit: credit, for: competitionID)
            return
        }
        guard let storeProduct = products[product.rawValue] else {
            state = .failed(.productsUnavailable)
            return
        }
        state = .purchasing
        // Målet lagres før arket vises, så et kjøp som avbrytes av en krasj, finner det igjen.
        beginPurchase(product, target: PurchaseTarget(competitionID: competitionID, clubID: clubID))
        defer { isPurchasing = false }
        do {
            // appAccountToken = profil-id-en: serveren sjekker at kjøpet hører til kontoen.
            let result = try await storeProduct.purchase(options: [.appAccountToken(profileID)])
            switch result {
            case .success(let verification):
                await handle(verification, source: .purchase)
            case .pending:
                // Kjøpsforespørsel: målet står til forespørselen er godkjent (kommer i `updates`).
                state = .failed(.pending)
            case .userCancelled:
                pending.cancel()
                state = .idle
            @unknown default:
                state = .idle
            }
        } catch {
            state = .failed(.unknown(error.localizedDescription))
        }
    }

    /// Kobler en ledig kreditt du selv har kjøpt til en turnering som alt finnes (konkurransesiden,
    /// «Bruk kjøpet ditt»). Gir `true` når serveren godtok koblingen; ellers står feilen i `state`.
    func useCredit(for competitionID: UUID) async -> Bool {
        guard let credit = CompetitionUnlock.unusedCredit(in: entitlements, owner: profileID) else {
            state = .failed(.serverRejected("fant ikke noe ledig kjøp"))
            return false
        }
        return await use(credit: credit, for: competitionID)
    }

    /// «Gjenopprett kjøp»: synker med App Store (abonnement), registrerer det som ikke er
    /// registrert, og henter kjøpene fra serveren (der også forbrukbare kjøp står).
    func restore() async {
        state = .restoring
        try? await AppStore.sync()
        for await result in Transaction.currentEntitlements {
            await handle(result, source: .background)
        }
        for await result in Transaction.unfinished {
            await handle(result, source: .background)
        }
        await refreshEntitlements()
        if case .restoring = state { state = .idle }
    }

    func refreshEntitlements() async {
        if let rows = try? await backend.entitlements() { entitlements = rows }
    }

    // MARK: Låst opp?

    /// Serverens svar (fasit).
    func serverIsUnlocked(_ competitionID: UUID) async -> Bool? {
        try? await backend.isUnlocked(competitionID: competitionID)
    }

    // MARK: Internt

    /// Gir `true` når serveren godtok koblingen; ellers står feilen i `state`.
    @discardableResult
    private func use(credit: EntitlementRow, for competitionID: UUID) async -> Bool {
        state = .purchasing
        do {
            try await backend.assign(entitlementID: credit.id, competitionID: competitionID)
            lastUnlocked = competitionID
            await refreshEntitlements()
            state = .idle
            return true
        } catch {
            state = .failed(.serverRejected(DataError.from(error).message))
            return false
        }
    }

    /// Lagrer målet for kjøpet som startes nå.
    func beginPurchase(_ product: PurchaseProduct, target: PurchaseTarget) {
        isPurchasing = true
        pending.prepare(.init(productID: product.rawValue, target: target, profileID: profileID, createdAt: now()))
    }

    private func handle(_ result: VerificationResult<Transaction>, source: PurchaseTransactionSource) async {
        guard case .verified(let transaction) = result else {
            state = .failed(.notVerified)
            return
        }
        let info = PurchaseTransactionInfo(id: transaction.id, originalID: transaction.originalID,
                                           productID: transaction.productID, purchaseDate: transaction.purchaseDate,
                                           appAccountToken: transaction.appAccountToken)
        await register(info, source: source) { await transaction.finish() }
    }

    /// Registrerer en verifisert transaksjon hos serveren og fullfører den når serveren har svart.
    /// Bare transaksjonen fra `purchase()` får turneringen kjøpsarket ble åpnet for; andre får målet
    /// de alt har (eller det ventende, når de tydelig er det samme kjøpet, se `PendingPurchaseStore`).
    func register(_ transaction: PurchaseTransactionInfo, source: PurchaseTransactionSource,
                  finish: () async -> Void) async {
        guard PurchaseProduct.ids.contains(transaction.productID) else { return }
        let target: PurchaseTarget?
        switch source {
        case .purchase:
            target = pending.claimForPurchase(transaction)
            handledByPurchase.insert(transaction.id)
        case .background:
            if handledByPurchase.contains(transaction.id) { return }
            target = pending.claimForBackground(transaction, mayClaim: !isPurchasing)
        }
        defer { if source == .purchase { handledByPurchase.remove(transaction.id) } }
        do {
            let row = try await backend.verify(transactionID: transaction.id, competitionID: target?.competitionID,
                                               clubID: target?.clubID)
            await finish()
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
