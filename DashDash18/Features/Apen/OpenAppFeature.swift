import Foundation

// Fase 17, åpent for alle (docs/visjon-apen-app.md): onboarding uten klubb, sletting av konto,
// rapporter og blokker, Google-innlogging, kjøp for å kjøre turnering og «Del regningen».
// Hver del har sitt eget flagg. Med et flagg av oppfører den delen av appen seg som før.

/// Onboarding uten klubb: «Spill med venner» eller «Bli med i/lag en klubb» etter innlogging,
/// og en app med bare Spill og Deg for den som ikke er i en klubb. Krever løse runder (017, 018).
nonisolated enum OpenAppFeature {
    static let flag = false
    static let isEnabled = flag && LooseRoundsFeature.isEnabled
}

/// «Slett konto» under Deg. Krever `sql/019_konto_og_moderering.sql` og at Edge Function
/// `delete-account` er deployet.
nonisolated enum AccountDeletionFeature {
    static let isEnabled = true
}

/// Rapporter og blokker i tråden, «Blokkerte» under Deg, rapportene for arrangøren og godkjenning
/// av vilkårene. Krever `sql/019_konto_og_moderering.sql`.
nonisolated enum ModerationFeature {
    static let isEnabled = true
}

/// Logg inn med Google (B9). Krever OAuth-klient i Google Cloud og Google slått på i Supabase Auth,
/// med `dashdash://login-callback` i «Redirect URLs».
nonisolated enum GoogleLoginFeature {
    static let isEnabled = false
}

/// Kjøp for å kjøre turnering (StoreKit 2). Krever `sql/023_kjop.sql`, Edge Function
/// `verify-purchase` og produktene i App Store Connect.
nonisolated enum PurchaseFeature {
    static let isEnabled = false
}

/// «Del regningen» med Vipps (felles utgifter, aldri veddemål). Trenger ingenting på serveren.
nonisolated enum BillSplitFeature {
    static let isEnabled = true
}

/// Personvernerklæringen og vilkårene (docs/personvern.md og docs/vilkar.md). Fyll inn adressene
/// når de er publisert. Til da vises teksten «publiseres før lansering» i stedet for en lenke.
nonisolated enum LegalLinks {
    static let privacy: URL? = nil
    static let terms: URL? = nil
    /// Hvor folk melder fra om støtende innhold eller spør om personvern.
    static let contactEmail = "personvern@dashdash18.com"
    /// Versjonen av vilkårene. Øk den når vilkårene endres, så alle godtar på nytt.
    static let termsVersion = "2026-10"
    /// Lenkene vises når de er publisert, eller når den åpne appen er slått på. Ellers ser
    /// innloggingen og Deg ut som før.
    static var isVisible: Bool { privacy != nil || terms != nil || OpenAppFeature.isEnabled }
}
