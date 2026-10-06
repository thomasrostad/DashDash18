import Foundation

/// Avkortet runde (db-nytt.js linje 911–990).
public enum Truncation {
    /// Regelen for uspilte hull (`AVKORT_REGLER`). Rå-verdiene er de som lagres på runden.
    public enum Rule: String, Codable, Sendable, CaseIterable {
        /// Bare hullene alle rakk teller.
        case common = "felles"
        /// Uspilte hull gir netto par (2 poeng).
        case netPar = "nettopar"
        /// Uspilte hull gir 0 poeng. Strengen «null» er en gyldig, valgt regel.
        case zero = "null"
    }

    /// Stableford: netto par er alltid 2 poeng (`POENG_NETTO_PAR`).
    public static let netParPoints = 2

    /// `avkortRegel`: regelen på runden, eller `nil` når runden ikke er avkortet.
    public static func rule(_ round: Round) -> Rule? {
        round.avkortRegel.flatMap(Rule.init(rawValue:))
    }

    /// `erAvkortet`.
    public static func isTruncated(_ round: Round) -> Bool {
        rule(round) != nil
    }

    /// `tellendeHull`: hvor mange hull som teller. Bare `felles` kutter, til
    /// `min(antall, round(avkortetEtter))`. Ugyldig eller under 1 → hele runden.
    public static func countingHoles(_ round: Round) -> Int {
        let count = round.numberOfHoles
        guard rule(round) == .common else { return count }
        guard let after = round.avkortetEtter, after.isFinite, after >= 1 else { return count }
        return min(count, JS.roundInt(after))
    }

    /// `poengForTomtHull`: 2 med `nettopar`, ellers 0.
    public static func pointsForEmptyHole(_ round: Round) -> Int {
        rule(round) == .netPar ? netParPoints : 0
    }
}
