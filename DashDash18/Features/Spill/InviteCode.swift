import Foundation

/// Invitasjonskoden til en løs runde (`round_invites.code`, sql/018): 10 tegn Crockford base32
/// (0–9 og A–Z uten I, L, O og U), 50 bit. Lenken er `dashdash://runde/<KODE>`.
///
/// Det som skrives inn, tolkes som databasen gjør (`round_invite_normalize`): store bokstaver,
/// uten mellomrom og bindestrek, O blir 0 og I/L blir 1.
nonisolated struct InviteCode: Equatable, Hashable, Sendable {
    let value: String

    static let alphabet = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
    static let length = 10
    /// URL-skjemaet appen må registrere (Xcode → target → Info → URL Types).
    static let scheme = "dashdash"
    static let host = "runde"

    /// En kode som skrevet inn, eller nil når den ikke kan være en kode.
    init?(_ raw: String) {
        let cleaned = raw.uppercased()
            .filter { !$0.isWhitespace && $0 != "-" }
            .map { char -> Character in
                switch char {
                case "O": "0"
                case "I", "L": "1"
                default: char
                }
            }
        let code = String(cleaned)
        guard code.count == Self.length, code.allSatisfy({ Self.alphabet.contains($0) }) else { return nil }
        value = code
    }

    /// Koden fra en lenke: `dashdash://runde/KODE` (også `dashdash://runde?kode=KODE`) eller den
    /// universelle `https://dashdash18.com/runde/KODE`. Med `host` for andre lenker med samme kode,
    /// f.eks. `dashdash://konkurranse/KODE` (sql/022).
    init?(url: URL, host: String = InviteCode.host) {
        let url = UniversalLink.appURL(url) ?? url
        guard url.scheme?.lowercased() == Self.scheme, url.host()?.lowercased() == host else { return nil }
        let fromPath = url.pathComponents.first { $0 != "/" }
        let fromQuery = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "kode" }?.value
        guard let raw = fromPath ?? fromQuery, let code = InviteCode(raw) else { return nil }
        self = code
    }

    /// Det som limes inn: en lenke eller en kode.
    static func parse(_ text: String, host: String = InviteCode.host) -> InviteCode? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = trimmed.lowercased()
        if lowered.hasPrefix(scheme + ":") || lowered.hasPrefix("https:"), let url = URL(string: trimmed) {
            return InviteCode(url: url, host: host)
        }
        return InviteCode(trimmed)
    }

    /// `dashdash://runde/KODE`.
    var url: URL { url(host: Self.host) }

    /// `dashdash://<host>/KODE`.
    func url(host: String) -> URL { URL(string: "\(Self.scheme)://\(host)/\(value)")! }

    /// Lenken som deles: `https://dashdash18.com/<host>/KODE` med universelle lenker, ellers
    /// `dashdash://<host>/KODE`.
    func shareURL(host: String, universal: Bool = UniversalLinksFeature.isEnabled) -> URL {
        universal ? UniversalLink.url(path: host, code: value) : url(host: host)
    }

    /// «ABCDE-FGHJK»: lettere å lese høyt og skrive av.
    var display: String {
        let middle = value.index(value.startIndex, offsetBy: Self.length / 2)
        return value[..<middle] + "-" + value[middle...]
    }

    /// Teksten som deles: hva det er, lenken og koden (for den som skriver den inn).
    func shareText(courseName: String?, universal: Bool = UniversalLinksFeature.isEnabled) -> String {
        let what = courseName.map { "Bli med på runden på \($0) i Atten." } ?? "Bli med på runden i Atten."
        let link = shareURL(host: Self.host, universal: universal)
        return "\(what)\n\(link.absoluteString)\nEller skriv inn koden \(display) under Spill → Bli med."
    }
}

/// Hva en invitasjon gjelder: en løs runde (sql/018) eller en privat konkurranse (sql/022). Samme
/// kode, ulik lenke og tekst.
nonisolated enum InviteTarget: Equatable, Sendable {
    case round(courseName: String?)
    case competition(name: String)

    /// `dashdash://konkurranse/<KODE>`.
    static let competitionHost = "konkurranse"

    var host: String {
        switch self {
        case .round: InviteCode.host
        case .competition: Self.competitionHost
        }
    }

    func url(_ code: InviteCode) -> URL { code.url(host: host) }

    /// Teksten som deles: hva det er, lenken og koden.
    func shareText(_ code: InviteCode, universal: Bool = UniversalLinksFeature.isEnabled) -> String {
        switch self {
        case .round(let courseName):
            return code.shareText(courseName: courseName, universal: universal)
        case .competition(let name):
            return "Bli med i \(name) i Atten.\n\(code.shareURL(host: host, universal: universal).absoluteString)\n"
                + "Eller skriv inn koden \(code.display) under Turneringer → Bli med med kode."
        }
    }

    var qrLabel: String {
        switch self {
        case .round: "QR-kode til runden"
        case .competition: "QR-kode til turneringen"
        }
    }

    var help: String {
        switch self {
        case .round:
            "Skann QR-koden med kameraet, eller trykk på lenken i meldingen. Uten lenke: skriv inn koden under "
                + "Spill → Bli med med kode. Koden virker i 7 dager, og til runden avsluttes."
        case .competition:
            "Skann QR-koden med kameraet, eller trykk på lenken i meldingen. Uten lenke: skriv inn koden under "
                + "Turneringer → Bli med med kode. Den som blir med, meldes på. Koden virker i 7 dager, og til "
                + "turneringen er ferdig."
        }
    }
}

/// En lenke appen åpnes med: invitasjon til en løs runde eller til en konkurranse. Hver type virker
/// bare når flagget sitt er på.
nonisolated enum AppLink: Equatable, Identifiable, Sendable {
    case round(InviteCode)
    case competition(InviteCode)

    var id: String {
        switch self {
        case .round(let code): "runde:\(code.value)"
        case .competition(let code): "konkurranse:\(code.value)"
        }
    }

    static func parse(_ url: URL, rounds: Bool, competitions: Bool) -> AppLink? {
        if rounds, let code = InviteCode(url: url) { return .round(code) }
        if competitions, let code = InviteCode(url: url, host: InviteTarget.competitionHost) { return .competition(code) }
        return nil
    }
}
