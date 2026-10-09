import Foundation

/// Hva en dag i turneringen heter i appen (09.10.2026). Golfgutu-oppsettet sier «kveld» som PWA-en;
/// nye turneringer sier «spilledag», som passer for golfklubber og simulatorsentre. Bare ord: regelmotoren
/// bruker det ikke, og det teller ikke som en endring fra et oppsett (`Ruleset.changedFields`).
public enum DayTerm: String, Codable, Hashable, Sendable, CaseIterable {
    case evening
    case playingDay

    /// «kveld», «spilledag».
    public var one: String {
        switch self {
        case .evening: "kveld"
        case .playingDay: "spilledag"
        }
    }

    /// «kvelden», «spilledagen».
    public var the: String { one + "en" }

    /// «kvelder», «spilledager».
    public var many: String { one + "er" }

    /// «kveldene», «spilledagene».
    public var theMany: String { one + "ene" }

    /// Overskriften for dagen som er i dag: «I kveld», «I dag».
    public var today: String {
        switch self {
        case .evening: "I kveld"
        case .playingDay: "I dag"
        }
    }

    /// Navnet i valget: «Kveld», «Spilledag».
    public var title: String { DayTerm.capitalized(one) }

    /// Stor forbokstav: «kvelden» → «Kvelden».
    public static func capitalized(_ word: String) -> String {
        word.prefix(1).uppercased() + word.dropFirst()
    }
}
