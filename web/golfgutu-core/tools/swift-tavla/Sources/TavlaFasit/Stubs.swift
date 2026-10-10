import Foundation
import GolfgutuCore

// Det app-filene trenger fra resten av appen, kopiert ordrett der det påvirker tallene og tekstene
// (RuleNames.nouns, TeeHoles.coursePar, CompetitionText), ellers bare det som trengs for å kompilere.

nonisolated enum MemberStatus: String, Codable, Sendable {
    case active
    case pending
    case archived
}

nonisolated enum SlopeNoFeature {
    static let isEnabled = true
    static let usesHoles = true
}

nonisolated struct LooseRoundInfo: Equatable, Sendable {
    var ownerID: UUID?
    var roster: [RoundRosterRow]
}

/// TeeHoles.coursePar (Features/Admin/Baner/SlopeNoHoles.swift).
nonisolated enum TeeHoles {
    static func coursePar(holesPar: Int?, teePar: Int?) -> Int? {
        teePar ?? holesPar
    }
}

/// RuleNames.nouns (Features/Admin/Sesong/RulesetExplanation.swift).
nonisolated enum RuleNames {
    struct Nouns {
        let plural: String
        let definite: String
        let definitePlural: String
    }

    static func nouns(_ unit: Ruleset.Counting.Unit, term: DayTerm = .evening) -> Nouns {
        switch unit {
        case .match: Nouns(plural: "matcher", definite: "matchen", definitePlural: "matchene")
        case .round: Nouns(plural: "runder", definite: "runden", definitePlural: "rundene")
        case .evening: Nouns(plural: term.many, definite: term.the, definitePlural: term.theMany)
        }
    }
}

/// CompetitionText (Features/Konkurranser/CompetitionLogic.swift), delene tabellene bruker.
nonisolated enum CompetitionText {
    static func tie(_ t: CupRules.Tie) -> String {
        switch t {
        case .suddenDeath: "Sudden death"
        case .countback: "Siste hull som ikke var delt"
        case .higherSeed: "Beste seed går videre"
        case .lowerHandicap: "Lavest handicap går videre"
        }
    }

    static func cupRound(_ round: Int, of count: Int) -> String {
        switch count - round {
        case 0: "Finale"
        case 1: "Semifinale"
        case 2: "Kvartfinale"
        default: "\(round). runde"
        }
    }

    static func shortDate(_ date: String) -> String {
        let parts = date.split(separator: "-").compactMap { Int($0) }
        let months = ["jan", "feb", "mar", "apr", "mai", "jun", "jul", "aug", "sep", "okt", "nov", "des"]
        guard parts.count == 3, (1...12).contains(parts[1]) else { return date }
        return "\(parts[2]). \(months[parts[1] - 1])"
    }
}

/// Features/Konkurranser/CompetitionRows.swift.
nonisolated struct CompetitionMatchRow: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let competitionID: UUID
    var roundNo: Int
    var slot: Int
    var playerA: UUID?
    var playerB: UUID?
    var winner: UUID?
    var walkover: Bool
    var result: String?
    var roundID: UUID?
}

nonisolated struct CupPairingParam: Encodable, Equatable, Sendable {
    let slot: Int
    let a: UUID
    let b: UUID?
}

nonisolated enum TimeWindowFeature {
    static let isEnabled = true
}
