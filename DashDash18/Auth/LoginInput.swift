import Foundation

/// Ren logikk for innloggingsskjemaet: rydding av e-post og kode, og feilmeldinger på norsk.
nonisolated enum LoginInput {
    /// Trimmet og med små bokstaver, eller `nil` hvis det ikke ser ut som en e-postadresse.
    static func normalizedEmail(_ raw: String) -> String? {
        let email = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard email.wholeMatch(of: /[^@\s]+@[^@\s]+\.[^@\s]+/) != nil else { return nil }
        return email
    }

    /// Bare sifre. Lengden er en innstilling i Supabase (6 eller 8), så vi antar ingen fast lengde.
    /// PWA-en klippet en gang en 8-sifret kode med `maxlength="6"` (README).
    static func normalizedCode(_ raw: String) -> String? {
        let code = raw.filter { !$0.isWhitespace && $0 != "-" }
        guard (4...10).contains(code.count), code.allSatisfy(\.isASCII), code.allSatisfy(\.isNumber) else {
            return nil
        }
        return code
    }

    /// Koden når den kom inn i ett jafs: autofyll fra Mail eller Meldinger (`oneTimeCode`)
    /// eller innliming. Da sendes den med en gang. Skriving gir ett tegn om gangen, og da
    /// venter vi på «Logg inn», fordi vi ikke vet om koden har 6 eller 8 sifre.
    static func autoSubmittableCode(previous: String, current: String) -> String? {
        guard current.count - previous.count > 1 else { return nil }
        return normalizedCode(current)
    }

    /// Hvor lenge Supabase vil at vi venter mellom to koder til samme adresse (standard 60 s).
    static let resendInterval: TimeInterval = 60

    /// Sekunder til «Send ny kode» kan trykkes igjen. 0 betyr nå.
    static func secondsUntilResend(lastSent: Date?, now: Date, interval: TimeInterval = resendInterval) -> Int {
        guard let lastSent else { return 0 }
        let left = interval - now.timeIntervalSince(lastSent)
        return left > 0 ? Int(left.rounded(.up)) : 0
    }
}

/// Det brukeren får se når innloggingen feiler.
nonisolated enum LoginError: Error, Equatable {
    case invalidEmail
    case invalidCode
    case wrongOrExpiredCode
    case tooManyAttempts
    case offline
    case appleFailed
    case googleFailed
    case unknown(String)

    var message: String {
        switch self {
        case .invalidEmail: "Det ser ikke ut som en e-postadresse."
        case .invalidCode: "Koden er bare tall. Sjekk at du fikk med alle sifrene."
        case .wrongOrExpiredCode: "Koden er feil eller utløpt. Be om en ny kode."
        case .tooManyAttempts: "For mange forsøk. Vent litt og prøv igjen."
        case .offline: "Ingen kontakt med serveren. Sjekk nettet og prøv igjen."
        case .appleFailed: "Innloggingen med Apple ble ikke fullført. Prøv igjen, eller bruk e-post."
        case .googleFailed: "Innloggingen med Google ble ikke fullført. Prøv igjen, eller bruk e-post."
        case .unknown(let detail): "Noe gikk galt: \(detail)"
        }
    }

    /// Oversetter Supabase sin `error_code`. Kodene står i supabase-swift `ErrorCode`.
    static func from(errorCode: String?, fallback: String) -> LoginError {
        switch errorCode {
        case "otp_expired", "invalid_credentials", "bad_jwt":
            .wrongOrExpiredCode
        case "over_email_send_rate_limit", "over_request_rate_limit", "over_sms_send_rate_limit":
            .tooManyAttempts
        case "email_address_invalid", "validation_failed":
            .invalidEmail
        default:
            .unknown(fallback)
        }
    }
}
