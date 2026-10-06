import Foundation

/// Avrunding og sortering som gir nøyaktig samme svar som PWA-en (JavaScript).
///
/// Swifts `.rounded()` runder bort fra null (-2,5 → -3), mens JS `Math.round`
/// runder mot pluss uendelig (-2,5 → -2). All avrunding i regelmotoren skal gå
/// gjennom disse hjelperne. Se SPEC 4.0.
public enum JS {
    /// JS `Math.round(x)`: `floor(x + 0.5)`.
    @inlinable
    public static func round(_ x: Double) -> Double {
        (x + 0.5).rounded(.down)
    }

    /// JS `Math.round(x)` som heltall. Forutsetter et endelig tall.
    @inlinable
    public static func roundInt(_ x: Double) -> Int {
        Int(round(x))
    }

    /// `rund2` i db-nytt.js: `Math.round(x * 100) / 100`.
    @inlinable
    public static func round2(_ x: Double) -> Double {
        round(x * 100) / 100
    }

    /// Nærmeste halve: `Math.round(x * 2) / 2` (fmtPoeng, matchSum, jakketavle).
    @inlinable
    public static func roundHalf(_ x: Double) -> Double {
        round(x * 2) / 2
    }
}

/// Norsk sortering, som `a.localeCompare(b, 'no')` i PWA-en: æ, ø og å etter z.
public enum NorwegianSort {
    /// Bokmål. `'no'` i JS løses opp til samme kollasjon.
    public static let locale = Locale(identifier: "nb")

    /// Sammenlikner som `localeCompare(…, 'no')`. `.orderedSame` når strengene er like.
    public static func compare(_ a: String, _ b: String) -> ComparisonResult {
        a.compare(b, options: [], range: nil, locale: locale)
    }

    /// `true` når `a` skal stå før `b`. Til bruk i `sorted(by:)`.
    public static func areInIncreasingOrder(_ a: String, _ b: String) -> Bool {
        compare(a, b) == .orderedAscending
    }
}
