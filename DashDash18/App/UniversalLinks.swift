import Foundation

/// Universelle lenker: `https://dashdash18.com/klubb/KODE`, `/runde/KODE` og `/konkurranse/KODE`
/// åpner appen (eller invitasjonssiden i `web/atten-lenker` for den som ikke har den).
///
/// Av til AASA-filen er ute på dashdash18.com og «Associated Domains» (`applinks:dashdash18.com`)
/// er slått på i Xcode. Med flagget av deles `dashdash://`-lenker som før, og appen tar ikke imot
/// universelle lenker. Lenkene tolkes uansett når de limes inn.
nonisolated enum UniversalLinksFeature {
    static let isEnabled = false
}

/// Oversetter mellom `https://dashdash18.com/<type>/KODE` og `dashdash://<type>/KODE`, slik at
/// begge går gjennom de samme parserne (`InviteCode`, `ClubInvite`).
nonisolated enum UniversalLink {
    static let domain = "dashdash18.com"
    static let hosts: Set<String> = [domain, "www." + domain]
    /// Stiene AASA-filen gir appen: klubb, løs runde og konkurranse.
    static let paths: Set<String> = [ClubInvite.host, InviteCode.host, InviteTarget.competitionHost]

    /// `https://dashdash18.com/runde/KODE` → `dashdash://runde/KODE`. nil for alt annet.
    static func appURL(_ url: URL) -> URL? {
        guard url.scheme?.lowercased() == "https", let host = url.host()?.lowercased(), hosts.contains(host) else {
            return nil
        }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count == 2, paths.contains(parts[0]) else { return nil }
        var components = URLComponents()
        components.scheme = InviteCode.scheme
        components.host = parts[0]
        components.path = "/" + parts[1]
        return components.url
    }

    /// `https://dashdash18.com/<path>/<KODE>`.
    static func url(path: String, code: String) -> URL {
        URL(string: "https://\(domain)/\(path)/\(code)")!
    }
}
