import Foundation

/// Flere konkurranser samtidig (fase 15): liga, cup og morroturnering ved siden av jakkeracet,
/// «Teller også i …» i hurtigstarten og ny løs runde, konkurransevelger på Tavla og morrokvelder
/// på Kveld. Av til `sql/022_konkurranser.sql` er godkjent og kjørt på test (åpen påmelding,
/// cupkampene og RPC-ene). Forutsetter `FoundationFeature` (017). Med flagget av er appen som før.
nonisolated enum CompetitionsFeature {
    static let isEnabled = true

    /// Begge flaggene må være på.
    static var isActive: Bool { isEnabled && FoundationFeature.isEnabled }
}

/// Betaling for å kjøre en turnering (besluttet 07.10.2026): liga og cup krever kjøp i appen
/// (sql/023, `competitions_require_purchase`). Morroturneringer, sesongen og spill på runden er
/// gratis. Med `PurchaseFeature` av er alt låst opp, som før. Ren logikk; StoreKit ligger i
/// `PurchaseService` (fase 17).
nonisolated enum CompetitionPurchase {
    /// Typene som krever kjøp. Samme liste som triggeren i sql/023.
    static func requiresPurchase(_ kind: CompetitionKind) -> Bool {
        kind == .league || kind == .cup
    }

    /// Kan brukeren lage (og kjøre) en ny konkurranse av typen, i klubben eller privat? Gratis type,
    /// et løpende abonnement som dekker den (ditt for en privat, klubbens for en klubbkonkurranse),
    /// eller en ledig kreditt (et kjøp som ikke er koblet til noen turnering ennå).
    static func isUnlocked(kind: CompetitionKind, clubID: UUID?, userID: UUID?, entitlements: [EntitlementRow],
                           enabled: Bool = PurchaseFeature.isEnabled, now: Date = .now) -> Bool {
        guard enabled, requiresPurchase(kind) else { return true }
        return coveredBySubscription(clubID: clubID, userID: userID, entitlements: entitlements, now: now)
            || CompetitionUnlock.unusedCredit(in: entitlements) != nil
    }

    /// Fra kjøpene `PurchaseService` har hentet. Uten tjenesten (ikke logget inn ennå) er en
    /// betalt type låst når kjøp er på.
    @MainActor
    static func isUnlocked(kind: CompetitionKind, clubID: UUID?, userID: UUID?, purchases: PurchaseService?,
                           enabled: Bool = PurchaseFeature.isEnabled, now: Date = .now) -> Bool {
        isUnlocked(kind: kind, clubID: clubID, userID: userID, entitlements: purchases?.entitlements ?? [],
                   enabled: enabled, now: now)
    }

    /// Skal en ledig kreditt kobles til den nye turneringen (`assign_purchase`)? Bare når typen
    /// krever kjøp og et abonnement ikke alt dekker den.
    static func needsCredit(kind: CompetitionKind, clubID: UUID?, userID: UUID?, entitlements: [EntitlementRow],
                            enabled: Bool = PurchaseFeature.isEnabled, now: Date = .now) -> Bool {
        guard enabled, requiresPurchase(kind) else { return false }
        return !coveredBySubscription(clubID: clubID, userID: userID, entitlements: entitlements, now: now)
            && CompetitionUnlock.unusedCredit(in: entitlements) != nil
    }

    /// Linja under typen i «Ny konkurranse», eller nil når kjøp er av.
    static func note(_ kind: CompetitionKind, enabled: Bool = PurchaseFeature.isEnabled) -> String? {
        guard enabled else { return nil }
        return requiresPurchase(kind)
            ? "Liga og cup krever kjøp i appen. Morroturneringer er gratis."
            : "Gratis å lage og kjøre."
    }

    /// Et abonnement dekker en ny turnering med denne eieren (samme regel som `CompetitionUnlock`).
    private static func coveredBySubscription(clubID: UUID?, userID: UUID?, entitlements: [EntitlementRow],
                                              now: Date) -> Bool {
        let info = CompetitionPurchaseInfo(id: UUID(), requiresPurchase: true, ownerID: clubID == nil ? userID : nil,
                                           clubID: clubID)
        return CompetitionUnlock.isUnlocked(info, entitlements: entitlements, now: now)
    }
}
