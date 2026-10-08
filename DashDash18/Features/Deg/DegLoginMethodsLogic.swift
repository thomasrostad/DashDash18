import Foundation

// «Innloggingsmåter» under Deg: hvilke identiteter kontoen har i Supabase Auth
// (`user.identities`), og om Apple kan kobles til fra appen. Ren logikk; Supabase-kallene
// ligger i `AuthModel`.

/// Kobling av en ny innloggingsmåte til kontoen fra appen (`linkIdentityWithIdToken`).
/// Krever at «manuell kobling» er slått på i Supabase Auth (konfig, godkjennes først).
/// Til da vises bare hvilke måter kontoen har.
nonisolated enum AccountLinkingFeature {
    static let appleEnabled = false
}

/// Innloggingsmåtene appen kjenner, i rekkefølgen de vises.
nonisolated enum LoginMethod: String, CaseIterable, Sendable {
    case apple
    case email
    case google

    var title: String {
        switch self {
        case .apple: "Apple"
        case .email: "E-postkode"
        case .google: "Google"
        }
    }

    var systemImage: String {
        switch self {
        case .apple: "apple.logo"
        case .email: "envelope"
        case .google: "g.circle"
        }
    }

    /// Google er ikke satt opp i Supabase ennå (B9). Slås på med `GoogleLoginFeature`.
    var isAvailable: Bool { self != .google || GoogleLoginFeature.isEnabled }
}

/// Én rad i lista: måten, om den er koblet, og hva som står til høyre.
nonisolated struct LoginMethodRow: Equatable, Identifiable, Sendable {
    enum Status: Equatable, Sendable {
        case linked(detail: String?)
        /// Ikke koblet. `canLink` = knapp for å koble til.
        case notLinked(canLink: Bool)
        case comingSoon
    }

    let method: LoginMethod
    let status: Status

    var id: LoginMethod { method }

    var trailingText: String {
        switch status {
        case .linked: "Koblet"
        case .notLinked: "Ikke koblet"
        case .comingSoon: "Kommer"
        }
    }
}

/// Det vi trenger fra én identitet (`UserIdentity`), så logikken kan testes uten Supabase.
nonisolated struct LinkedIdentity: Equatable, Sendable {
    let provider: String
    let email: String?

    init(provider: String, email: String? = nil) {
        self.provider = provider
        self.email = email
    }
}

nonisolated enum LoginMethods {
    /// Radene for kontoen. Identiteter fra innloggingsmåter appen ikke kjenner, vises ikke.
    static func rows(identities: [LinkedIdentity], appleLinkingEnabled: Bool = AccountLinkingFeature.appleEnabled) -> [LoginMethodRow] {
        LoginMethod.allCases.map { method in
            let linked = identities.filter { $0.provider.lowercased() == method.rawValue }
            if !linked.isEmpty {
                return LoginMethodRow(method: method, status: .linked(detail: detail(for: method, linked: linked)))
            }
            guard method.isAvailable else { return LoginMethodRow(method: method, status: .comingSoon) }
            // E-postkode kobles ved å logge inn med koden; Apple kan kobles herfra når det er slått på.
            return LoginMethodRow(method: method, status: .notLinked(canLink: method == .apple && appleLinkingEnabled))
        }
    }

    /// E-postadressen bak måten. Apples «skjul e-post»-adresser vises som det.
    static func detail(for method: LoginMethod, linked: [LinkedIdentity]) -> String? {
        guard let email = linked.compactMap(\.email).first(where: { !$0.isEmpty }) else { return nil }
        if method == .apple, email.lowercased().hasSuffix("@privaterelay.appleid.com") {
            return "Skjult e-post"
        }
        return email
    }

    /// Teksten i bekreftelsen før utlogging (PWA: «Logge ut? Du trenger en ny kode på e-post
    /// for å logge inn igjen.»). Sier hvordan du kommer inn igjen, ut fra måtene kontoen har.
    static func signOutMessage(identities: [LinkedIdentity]) -> String {
        let providers = Set(identities.map { $0.provider.lowercased() })
        let hasApple = providers.contains(LoginMethod.apple.rawValue)
        let hasEmail = providers.contains(LoginMethod.email.rawValue)
        switch (hasApple, hasEmail) {
        case (true, true): return "Du logger inn igjen med Apple eller en ny kode på e-post."
        case (true, false): return "Du logger inn igjen med Apple."
        default: return "Du trenger en ny kode på e-post for å logge inn igjen."
        }
    }
}

/// Feil ved kobling av en innloggingsmåte, med norsk tekst.
nonisolated enum LinkIdentityError: Error, Equatable {
    case alreadyUsed
    case notEnabled
    case appleFailed
    case offline
    case unknown(String)

    var message: String {
        switch self {
        case .alreadyUsed: "Denne Apple-ID-en er allerede brukt av en annen konto i Atten."
        case .notEnabled: "Kobling av innloggingsmåter er ikke slått på ennå."
        case .appleFailed: "Fikk ikke svar fra Apple. Prøv igjen."
        case .offline: "Ingen kontakt med serveren. Sjekk nettet og prøv igjen."
        case .unknown(let detail): "Klarte ikke å koble til: \(detail)"
        }
    }

    /// Feilkodene fra Supabase Auth (`error_code`).
    static func from(errorCode: String?, fallback: String) -> LinkIdentityError {
        switch errorCode {
        case "identity_already_exists", "email_exists", "user_already_exists": .alreadyUsed
        case "manual_linking_disabled", "provider_disabled": .notEnabled
        case "bad_jwt", "invalid_credentials": .appleFailed
        default: .unknown(fallback)
        }
    }
}
