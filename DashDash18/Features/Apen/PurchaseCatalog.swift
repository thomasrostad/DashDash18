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

    /// En ledig kreditt å bruke på turneringen, hvis du har en.
    /// Et ledig kjøp som `owner` selv har gjort. Arrangørene ser hverandres kjøp i klubben, men
    /// `assign_purchase` godtar bare egne, så andres kjøp regnes ikke som ledige.
    static func unusedCredit(in entitlements: [EntitlementRow], owner: UUID?) -> EntitlementRow? {
        guard let owner else { return nil }
        return entitlements.first { $0.isUnusedCredit && $0.profileID == owner }
    }
}

/// Hva som venter på serveren: turneringen et kjøp var ment for, til `verify-purchase` har svart.
/// Lagret på telefonen, så et kjøp som ble avbrutt av en krasj, finner turneringen sin igjen.
nonisolated struct PendingPurchaseStore {
    var defaults: UserDefaults = .standard
    private let key = "ventendeKjop"

    /// Turneringen neste kjøp er for (satt før kjøpsarket vises).
    func setTarget(_ competitionID: UUID?) {
        var map = all()
        map["neste"] = competitionID?.uuidString
        defaults.set(map, forKey: key)
    }

    /// Fester målet til transaksjonen når den kommer tilbake fra App Store.
    func attach(transactionID: UInt64) {
        var map = all()
        guard let next = map.removeValue(forKey: "neste") else { return }
        map[String(transactionID)] = next
        defaults.set(map, forKey: key)
    }

    func target(for transactionID: UInt64) -> UUID? {
        all()[String(transactionID)].flatMap(UUID.init(uuidString:))
    }

    func done(transactionID: UInt64) {
        var map = all()
        map[String(transactionID)] = nil
        defaults.set(map, forKey: key)
    }

    private func all() -> [String: String] {
        defaults.dictionary(forKey: key) as? [String: String] ?? [:]
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
