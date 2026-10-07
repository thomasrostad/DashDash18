import Foundation

/// Lagring av «Hvor spiller dere?» på runden (`rounds.venue`, sql/015_runde_sted.sql).
/// Av til 015 er godkjent og kjørt: valget vises i oppsettet, men sendes ikke, og kolonnen hentes ikke.
nonisolated enum VenueFeature {
    static let isEnabled = true
}

/// Hvor runden spilles. Samme regler begge steder; bare navnet på gruppene skiller (bås / flight),
/// og Trackman kan bare dele ut slagene i simulatoren.
nonisolated enum Venue: String, CaseIterable, Codable, Sendable {
    case simulator
    case course

    var title: String {
        switch self {
        case .simulator: "Simulator"
        case .course: "Ekte bane"
        }
    }

    /// Kolonneverdien, `nil` (før 015, eller ukjent tekst) er simulator.
    init(stored: String?) {
        self = stored.flatMap(Venue.init(rawValue:)) ?? .simulator
    }
}

/// Ordet for gruppene i en runde: «bås» i simulatoren, «flight» på ekte bane. Markør heter markør begge steder.
nonisolated struct GroupTerm: Equatable, Sendable {
    /// «bås» / «flight»
    let singular: String
    /// «båser» / «flighter»
    let plural: String
    /// «båsen» / «flighten»
    let definite: String
    /// «båsene» / «flightene»
    let definitePlural: String

    static let bay = GroupTerm(singular: "bås", plural: "båser", definite: "båsen", definitePlural: "båsene")
    static let flight = GroupTerm(singular: "flight", plural: "flighter", definite: "flighten",
                                  definitePlural: "flightene")

    static func `for`(_ venue: Venue) -> GroupTerm {
        venue == .course ? .flight : .bay
    }

    /// Rundens kolonneverdi (`rounds.venue`), `nil` = simulator.
    static func `for`(stored: String?) -> GroupTerm {
        .for(Venue(stored: stored))
    }

    /// «markør», uendret på ekte bane.
    var marker: String { "markør" }

    /// «Bås» / «Flight»
    var title: String { singular.prefix(1).uppercased() + singular.dropFirst() }

    /// «Båsen» / «Flighten»
    var definiteTitle: String { definite.prefix(1).uppercased() + definite.dropFirst() }

    /// «Båser» / «Flighter»
    var pluralTitle: String { plural.prefix(1).uppercased() + plural.dropFirst() }

    /// «Bås 2» / «Flight 2»
    func numbered(_ number: Int) -> String { "\(title) \(number)" }

    /// «bås 2» / «flight 2», inne i en setning.
    func numberedLower(_ number: Int) -> String { "\(singular) \(number)" }

    /// «1 bås», «3 båser» / «1 flight», «3 flighter»
    func count(_ n: Int) -> String { "\(n) " + (n == 1 ? singular : plural) }

    /// «Bås 1 og 3» / «Flight 2»
    func numberedList(_ numbers: [Int]) -> String {
        "\(title) " + numbers.map(String.init).joined(separator: " og ")
    }
}
