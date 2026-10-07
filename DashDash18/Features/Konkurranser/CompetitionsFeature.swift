import Foundation

/// Flere konkurranser samtidig (fase 15): liga, cup og morroturnering ved siden av jakkeracet,
/// «Teller også i …» i hurtigstarten og ny løs runde, konkurransevelger på Tavla og morrokvelder
/// på Kveld. Av til `sql/022_konkurranser.sql` er godkjent og kjørt på test (åpen påmelding,
/// cupkampene og RPC-ene). Forutsetter `FoundationFeature` (017). Med flagget av er appen som før.
nonisolated enum CompetitionsFeature {
    static let isEnabled = false

    /// Begge flaggene må være på.
    static var isActive: Bool { isEnabled && FoundationFeature.isEnabled }
}

/// Betaling for å kjøre en turnering (B, «gratis med kjøp i appen»). Fase 17 kobler StoreKit inn
/// her; til da er alt låst opp. Ren funksjon, så den kan kalles fra views og tester.
nonisolated enum CompetitionPurchase {
    /// Kan brukeren lage (og kjøre) en konkurranse av typen, i klubben eller privat?
    static func isUnlocked(kind: CompetitionKind, clubID: UUID?, userID: UUID?) -> Bool {
        true
    }
}
