import Foundation

// Fase 17, åpent for alle (docs/visjon-apen-app.md): onboarding uten klubb, sletting av konto,
// rapporter og blokker, Google-innlogging, kjøp for å kjøre turnering og «Del regningen».
// Sletting av konto og rapporter og blokker (sql/019) er alltid på (flaggene ryddet 28.10.2026).
// De andre delene har sitt eget flagg. Med et flagg av oppfører den delen av appen seg som før.

/// Onboarding uten klubb: «Spill med venner» eller «Bli med i/lag en klubb» etter innlogging,
/// og en app med bare Spill og Deg for den som ikke er i en klubb. Krever løse runder (017, 018).
/// På siden 09.10.2026 (Thomas): en ny bruker skal kunne spille uten å bli med i en klubb først.
nonisolated enum OpenAppFeature {
    static let flag = true
    static let isEnabled = flag && LooseRoundsFeature.isEnabled
}

/// «Rapporter» på baner i det felles biblioteket (en annen har lagt dem inn) og på turneringer i
/// «Finn turneringer» (1.0.1, App Review 1.2). Det du har rapportert, skjules for deg. Krever
/// `sql/066_rapporter_baner_turneringer.sql` (typene `course` og `competition` i `report_content`
/// og `my_hidden_content`). Av til 066 er kjørt på test og prod; uten 066 ville rapporten feile.
nonisolated enum PublicContentReportFeature {
    /// På 21.10.2026: 066 er kjørt på test og prod, og report-alert er deployet begge steder.
    static let flag = true
    static let isEnabled = flag
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

/// «Del regningen» med Vipps (felles utgifter, aldri veddemål). Lagring og «Mine oppgjør» krever
/// sql/051; uten den deles regningen som før, uten lagring.
nonisolated enum BillSplitFeature {
    /// Kan slås av fra serveren: `ios_flags.bill_split` (sql/068).
    static var isEnabled: Bool { !KillSwitch.isOff("bill_split") }
}

/// Personvernerklæringen og vilkårene, publisert på dashdash18.com av workeren `atten-lenker`
/// (generert fra `docs/personvern.md` og `docs/vilkar.md`).
nonisolated enum LegalLinks {
    static let privacy: URL? = URL(string: "https://dashdash18.com/personvern")
    static let terms: URL? = URL(string: "https://dashdash18.com/vilkar")
    /// Hvor folk melder fra om støtende innhold eller spør om personvern.
    static let contactEmail = "personvern@dashdash18.com"
    /// Versjonen av vilkårene. Øk den når vilkårene endres, så alle godtar på nytt.
    static let termsVersion = "2026-10"
    /// Lenkene vises når de er publisert, eller når den åpne appen er slått på. Ellers ser
    /// innloggingen og Deg ut som før.
    static var isVisible: Bool { privacy != nil || terms != nil || OpenAppFeature.isEnabled }
}
