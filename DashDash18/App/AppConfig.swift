import Foundation

/// Hvilken Supabase appen snakker med. Prod finnes ikke ennå (ROADMAP fase 9).
nonisolated enum AppEnvironment: String, Sendable {
    case test
    case prod

    var displayName: String {
        switch self {
        case .test: "Test"
        case .prod: "Prod"
        }
    }

    /// Navnet på konfigfila i appen, f.eks. `Supabase-Test.plist`.
    var configFileName: String { "Supabase-\(displayName)" }

    /// Miljøet dette bygget bruker. Alle bygg går mot test til prod er satt opp og godkjent.
    static let current: AppEnvironment = .test
}

/// Miljøkonfig lest fra `Config/Supabase-<Miljø>.plist`. Fila er holdt utenfor git.
nonisolated struct AppConfig: Equatable, Sendable {
    let environment: AppEnvironment
    let supabaseURL: URL
    let publishableKey: String

    /// Prosjekt-ref-en, f.eks. `tsekialrxuhrugscosgi`.
    var projectRef: String {
        supabaseURL.host()?.split(separator: ".").first.map(String.init) ?? ""
    }

    enum LoadError: Error, Equatable {
        case missingFile(String)
        case unreadable
        case missingValue(String)
        case wrongEnvironment(expected: AppEnvironment, found: String)
        case secretKey
    }

    static func load(_ environment: AppEnvironment = .current, bundle: Bundle = .main) throws(LoadError) -> AppConfig {
        guard let url = bundle.url(forResource: environment.configFileName, withExtension: "plist") else {
            throw .missingFile("\(environment.configFileName).plist")
        }
        guard let data = try? Data(contentsOf: url) else { throw .unreadable }
        return try AppConfig(plistData: data, expecting: environment)
    }

    init(plistData: Data, expecting environment: AppEnvironment) throws(LoadError) {
        guard let dict = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any] else {
            throw .unreadable
        }
        guard let found = dict["Environment"] as? String else { throw .missingValue("Environment") }
        // Hindrer at en prod-fil havner bak et test-navn, eller omvendt.
        guard found == environment.rawValue else {
            throw .wrongEnvironment(expected: environment, found: found)
        }
        guard let urlString = dict["SupabaseURL"] as? String, let url = URL(string: urlString), url.scheme == "https" else {
            throw .missingValue("SupabaseURL")
        }
        guard let key = dict["SupabasePublishableKey"] as? String, !key.isEmpty else {
            throw .missingValue("SupabasePublishableKey")
        }
        // Den hemmelige nøkkelen skal aldri inn i appen.
        guard !Self.isSecretKey(key) else { throw .secretKey }

        self.environment = environment
        self.supabaseURL = url
        self.publishableKey = key
    }

    /// Ny hemmelig nøkkel (`sb_secret_…`) eller gammel JWT-nøkkel med rollen `service_role`.
    /// Begge går forbi RLS og skal bare finnes på serveren.
    static func isSecretKey(_ key: String) -> Bool {
        if key.hasPrefix("sb_secret_") { return true }
        let parts = key.split(separator: ".")
        guard key.hasPrefix("eyJ"), parts.count == 3 else { return false }
        var payload = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload),
              let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return claims["role"] as? String == "service_role"
    }
}
