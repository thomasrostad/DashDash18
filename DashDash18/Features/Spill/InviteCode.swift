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

    /// Koden fra en lenke: `dashdash://runde/KODE` (også `dashdash://runde?kode=KODE`).
    init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme, url.host()?.lowercased() == Self.host else { return nil }
        let fromPath = url.pathComponents.first { $0 != "/" }
        let fromQuery = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "kode" }?.value
        guard let raw = fromPath ?? fromQuery, let code = InviteCode(raw) else { return nil }
        self = code
    }

    /// Det som limes inn: en lenke eller en kode.
    static func parse(_ text: String) -> InviteCode? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix(scheme + ":"), let url = URL(string: trimmed) {
            return InviteCode(url: url)
        }
        return InviteCode(trimmed)
    }

    /// `dashdash://runde/KODE`.
    var url: URL { URL(string: "\(Self.scheme)://\(Self.host)/\(value)")! }

    /// «ABCDE-FGHJK»: lettere å lese høyt og skrive av.
    var display: String {
        let middle = value.index(value.startIndex, offsetBy: Self.length / 2)
        return value[..<middle] + "-" + value[middle...]
    }

    /// Teksten som deles: hva det er, lenken og koden (for den som skriver den inn).
    func shareText(courseName: String?) -> String {
        let what = courseName.map { "Bli med på runden på \($0) i DashDash." } ?? "Bli med på runden i DashDash."
        return "\(what)\n\(url.absoluteString)\nEller skriv inn koden \(display) under Spill → Bli med."
    }
}
