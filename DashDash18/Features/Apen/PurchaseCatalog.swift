import Foundation

// Kjøp for å kjøre turnering (besluttet 07.10.2026: gratis å bruke, betaling for å kjøre
// turnering, som kjøp i appen). Ren logikk her; StoreKit ligger i `PurchaseService`.
//
// Produktene (docs/app-store.md, DashDash.storekit, sql/023 og verify-purchase):
//   no.atten.turnering.sesong      forbrukbar: låser opp én turnering så lenge den varer.
//   no.atten.turnering.ar          årsabonnement (valgfritt): alle turneringene eieren eller
//                                  klubben kjører, så lenge det løper.
// Hvorfor forbrukbar og ikke ikke-forbrukbar: en ikke-forbrukbar kan bare kjøpes én gang per
// Apple-ID, og da kunne ingen kjøre turnering nummer to. Et forbrukbart kjøp gjenopprettes ikke
// av App Store, så serverens `entitlements` er fasiten, og et kjøp som ikke ble koblet, står
// som en ledig kreditt.

nonisolated enum PurchaseProduct: String, CaseIterable, Sendable {
    case tournament = "no.atten.turnering.sesong"
    case yearly = "no.atten.turnering.ar"

    enum Kind: String, Sendable {
        case consumable
        case subscription
    }

    var kind: Kind {
        switch self {
        case .tournament: .consumable
        case .yearly: .subscription
        }
    }

    var title: String {
        switch self {
        case .tournament: "Kjør turneringen"
        case .yearly: "Arrangør i ett år"
        }
    }

    var subtitle: String {
        switch self {
        case .tournament: "Én turnering, så lenge den varer"
        case .yearly: "Alle turneringene dine i ett år. Fornyes til du sier opp."
        }
    }

    static let ids: Set<String> = Set(allCases.map(\.rawValue))
}

/// En rad i `entitlements` (sql/017 + 023). Appen leser bare; serveren skriver.
nonisolated struct EntitlementRow: Codable, Equatable, Identifiable, Sendable {
    enum Status: String, Codable, Sendable {
        case active, expired, revoked, refunded
    }

    let id: UUID
    var profileID: UUID?
    var clubID: UUID?
    var competitionID: UUID?
    var productID: String
    var productKind: String
    var status: Status
    var expiresAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, status
        case profileID = "profile_id"
        case clubID = "club_id"
        case competitionID = "competition_id"
        case productID = "product_id"
        case productKind = "product_kind"
        case expiresAt = "expires_at"
    }

    static let columns = "id, profile_id, club_id, competition_id, product_id, product_kind, status, expires_at"

    var isSubscription: Bool { productKind == "subscription" }

    func isActive(now: Date) -> Bool {
        guard status == .active else { return false }
        if isSubscription, let expiresAt { return expiresAt > now }
        return true
    }

    /// En ledig kreditt: forbrukbart, aktivt og ikke koblet til noen turnering.
    var isUnusedCredit: Bool {
        status == .active && productKind == "consumable" && competitionID == nil
    }
}

/// Det som avgjør om en turnering er låst opp (samme regel som `competition_unlocked_by_purchase`
/// i sql/023, så appen kan svare uten nett).
nonisolated struct CompetitionPurchaseInfo: Equatable, Sendable {
    let id: UUID
    var requiresPurchase: Bool
    var entitlementID: UUID?
    var ownerID: UUID?
    var clubID: UUID?
}

nonisolated enum CompetitionUnlock {
    static func isUnlocked(_ competition: CompetitionPurchaseInfo, entitlements: [EntitlementRow], now: Date) -> Bool {
        guard competition.requiresPurchase else { return true }
        let active = entitlements.filter { $0.isActive(now: now) }
        if active.contains(where: { $0.competitionID == competition.id || $0.id == competition.entitlementID }) {
            return true
        }
        return active.contains { e in
            guard e.isSubscription else { return false }
            if let club = competition.clubID { return e.clubID == club }
            return e.clubID == nil && e.profileID != nil && e.profileID == competition.ownerID
        }
    }

    /// Et ledig kjøp som `owner` selv har gjort. Arrangørene ser hverandres kjøp i klubben (RLS), men
    /// `assign_purchase` godtar bare egne, så andres kjøp regnes ikke som ledige.
    static func unusedCredit(in entitlements: [EntitlementRow], owner: UUID?) -> EntitlementRow? {
        guard let owner else { return nil }
        return entitlements.first { $0.isUnusedCredit && $0.profileID == owner }
    }
}

/// Det appen vet om en transaksjon fra App Store når den skal avgjøre hvilken turnering den er for.
/// Egen type, så regelen kan prøves uten StoreKit.
nonisolated struct PurchaseTransactionInfo: Equatable, Sendable {
    let id: UInt64
    let originalID: UInt64
    let productID: String
    let purchaseDate: Date
    /// Profil-id-en appen satte på kjøpet (`appAccountToken`).
    let appAccountToken: UUID?

    /// En fornyelse av et abonnement (ikke det første kjøpet).
    var isRenewal: Bool { id != originalID }
}

/// Turneringen (og klubben, for et abonnement) et kjøp er ment for.
nonisolated struct PurchaseTarget: Codable, Equatable, Sendable {
    var competitionID: UUID?
    var clubID: UUID?
}

/// Hvor transaksjonen kom fra.
nonisolated enum PurchaseTransactionSource: Sendable {
    /// Svaret fra `product.purchase()`: kjøpet brukeren nettopp gjorde.
    case purchase
    /// Alt annet: `Transaction.updates`, uferdige transaksjoner ved start og «Gjenopprett»
    /// (fornyelser, en godkjent Kjøpsforespørsel, kjøp på en annen enhet).
    case background
}

/// Hva som venter på serveren: turneringen et kjøp var ment for, til `verify-purchase` har svart.
/// Lagret på telefonen, så et kjøp som ble avbrutt av en krasj, finner turneringen sin igjen.
///
/// Målet lagres før kjøpsarket vises (`prepare`) og festes til transaksjonen som kommer tilbake fra
/// `purchase()` (`claimForPurchase`). En transaksjon som kommer utenom (`claimForBackground`), får
/// det ventende målet bare når den tydelig er det samme kjøpet (`matches`): samme produkt og konto,
/// første kjøp (ikke en fornyelse), og gjort etter at målet ble satt og innen `maxAge`. Det dekker
/// en krasj mellom kjøpet og verifiseringen, og en Kjøpsforespørsel som godkjennes senere. Alt annet
/// verifiseres uten turnering (eller med målet det alt har fått), så et kjøp aldri kobles til feil
/// turnering.
nonisolated struct PendingPurchaseStore {
    /// Kjøpet som er startet, men ikke kommet tilbake ennå.
    struct Pending: Codable, Equatable, Sendable {
        var productID: String
        var target: PurchaseTarget
        var profileID: UUID
        var createdAt: Date
    }

    /// Hvor lenge etter at målet ble satt et kjøp utenom kjøpsarket kan få det. En Kjøpsforespørsel
    /// utløper etter et døgn hos Apple.
    static let maxAge: TimeInterval = 2 * 24 * 3600
    /// Klokka på telefonen og hos Apple kan gå litt ulikt.
    static let clockSkew: TimeInterval = 5 * 60

    var defaults: UserDefaults = .standard
    private let key = "ventendeKjop"

    private struct Stored: Codable {
        var next: Pending?
        var attached: [String: PurchaseTarget] = [:]
    }

    /// Målet for kjøpet som startes nå (satt før kjøpsarket vises).
    func prepare(_ next: Pending) {
        var stored = load()
        stored.next = next
        save(stored)
    }

    /// Brukeren avbrøt kjøpet.
    func cancel() {
        var stored = load()
        stored.next = nil
        save(stored)
    }

    /// Kjøpet som venter på å komme tilbake, om noe.
    var next: Pending? { load().next }

    /// Transaksjonen fra `purchase()`: målet den alt har, ellers det som ble satt før arket.
    func claimForPurchase(_ transaction: PurchaseTransactionInfo) -> PurchaseTarget? {
        var stored = load()
        if let target = stored.attached[String(transaction.id)] { return target }
        guard let next = stored.next, next.productID == transaction.productID else { return nil }
        stored.next = nil
        stored.attached[String(transaction.id)] = next.target
        save(stored)
        return next.target
    }

    /// En transaksjon utenom kjøpsarket: målet den alt har, eller det ventende målet når det er det
    /// samme kjøpet. `mayClaim` er usann mens `purchase()` venter på svar; da hører det ventende
    /// målet til det kjøpet.
    func claimForBackground(_ transaction: PurchaseTransactionInfo, mayClaim: Bool = true) -> PurchaseTarget? {
        var stored = load()
        if let target = stored.attached[String(transaction.id)] { return target }
        guard mayClaim, let next = stored.next, Self.matches(next, transaction) else { return nil }
        stored.next = nil
        stored.attached[String(transaction.id)] = next.target
        save(stored)
        return next.target
    }

    /// Er transaksjonen kjøpet som ble startet med `pending`?
    static func matches(_ pending: Pending, _ transaction: PurchaseTransactionInfo) -> Bool {
        guard pending.productID == transaction.productID,
              transaction.appAccountToken == pending.profileID,
              !transaction.isRenewal else { return false }
        let age = transaction.purchaseDate.timeIntervalSince(pending.createdAt)
        return age >= -clockSkew && age <= maxAge
    }

    func target(for transactionID: UInt64) -> PurchaseTarget? {
        load().attached[String(transactionID)]
    }

    /// Serveren har registrert kjøpet.
    func done(transactionID: UInt64) {
        var stored = load()
        guard stored.attached.removeValue(forKey: String(transactionID)) != nil else { return }
        save(stored)
    }

    private func load() -> Stored {
        guard let data = defaults.data(forKey: key),
              let stored = try? JSONDecoder().decode(Stored.self, from: data) else { return Stored() }
        return stored
    }

    private func save(_ stored: Stored) {
        if stored.next == nil && stored.attached.isEmpty {
            defaults.removeObject(forKey: key)
        } else if let data = try? JSONEncoder().encode(stored) {
            defaults.set(data, forKey: key)
        }
    }
}

/// Feil ved kjøp, med norsk tekst.
nonisolated enum PurchaseError: Error, Equatable {
    case productsUnavailable
    case pending
    case notVerified
    case serverRejected(String)
    case offline
    case unknown(String)

    var message: String {
        switch self {
        case .productsUnavailable: "Fikk ikke kontakt med App Store. Prøv igjen litt senere."
        case .pending: "Kjøpet venter på godkjenning (for eksempel Kjøpsforespørsel). Turneringen låses opp når det er godkjent."
        case .notVerified: "App Store kunne ikke bekrefte kjøpet. Du er ikke belastet for noe som ikke ble bekreftet."
        case .serverRejected(let detail): "Kjøpet ble ikke registrert: \(detail). Trykk «Gjenopprett kjøp» for å prøve igjen."
        case .offline: "Ingen kontakt med serveren. Kjøpet er tatt vare på og registreres når du har nett."
        case .unknown(let detail): "Noe gikk galt: \(detail)"
        }
    }
}
