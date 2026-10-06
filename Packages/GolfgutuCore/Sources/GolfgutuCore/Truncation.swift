import Foundation

/// Avkortet runde (db-nytt.js linje 911–990).
public enum Truncation {
    /// Regelen for uspilte hull (`AVKORT_REGLER`). Rå-verdiene er de som lagres på runden.
    public enum Rule: String, Codable, Sendable, CaseIterable {
        /// Bare hullene alle rakk teller.
        case common = "felles"
        /// Uspilte hull gir netto par (Golfgutu: 2 poeng).
        case netPar = "nettopar"
        /// Uspilte hull gir 0 poeng. Strengen «null» er en gyldig, valgt regel.
        case zero = "null"
    }

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

    /// `poengForTomtHull`: poeng for netto par (`POENG_NETTO_PAR`, Golfgutu 2) med `nettopar`, ellers 0.
    public static func pointsForEmptyHole(_ round: Round, rules: Ruleset = .golfgutu) -> Int {
        rule(round) == .netPar ? rules.scoring.netParPoints : 0
    }

    /// `lavesteFellesHull`: så langt alle som har begynt har kommet, talt som sammenhengende
    /// førte hull fra hull 1. Spillere uten score teller ikke. Ingen score i det hele tatt → 0.
    public static func lowestCommonHole(_ round: Round) -> Int {
        let started = round.holeScores.values.filter { !$0.isEmpty }
        if started.isEmpty { return 0 }
        let count = round.numberOfHoles
        var lowest = count
        for scores in started {
            var n = 0
            while n < count, scores[n] != nil { n += 1 }
            lowest = min(lowest, n)
        }
        return lowest
    }

    /// Én spiller som får en annen sum med avkortingen.
    public struct Change: Hashable, Sendable {
        public var playerID: String
        public var before: Int
        public var after: Int
        public var diff: Int { after - before }
    }

    /// Hva avkortingen koster (`avkortingenKoster`, uten de hengende veddemålene).
    public struct Cost: Hashable, Sendable {
        /// Tellende hull med avkortingen.
        public var countingHoles: Int
        /// Antall hull i runden.
        public var holes: Int
        /// Spillerne som får en annen sum, størst tap først.
        public var changes: [Change]
    }

    /// `avkortingenKoster`: summen per spiller før og etter en tenkt avkorting, for spillerne
    /// i troppen som har ført noe. Sortert på endring, størst tap først (stabil på troppens rekkefølge).
    public static func cost(of round: Round, after: Double, rule: Rule?, roster: [Player],
                            rules: Ruleset = .golfgutu) -> Cost {
        var draft = round
        draft.avkortetEtter = after.isFinite ? JS.round(after) : nil
        draft.avkortRegel = rule?.rawValue

        var changes: [(index: Int, change: Change)] = []
        for (index, player) in roster.enumerated() {
            guard let scores = round.holeScores[player.id], !scores.isEmpty else { continue }
            let hcp = Handicap.effective(for: player, in: round, roster: roster, rules: rules)
            let before = Scoring.points(from: scores, in: round, handicap: hcp, rules: rules)
            let afterPoints = Scoring.points(from: scores, in: draft, handicap: hcp, rules: rules)
            if before != afterPoints {
                changes.append((index, Change(playerID: player.id, before: before, after: afterPoints)))
            }
        }
        changes.sort { $0.change.diff != $1.change.diff ? $0.change.diff < $1.change.diff : $0.index < $1.index }
        return Cost(countingHoles: countingHoles(draft), holes: round.numberOfHoles, changes: changes.map(\.change))
    }
}

extension Truncation.Rule {
    /// Navnet i `AVKORT_REGLER`.
    public var name: String {
        switch self {
        case .common: "Tell til laveste felles hull"
        case .netPar: "Uspilte hull gir netto par"
        case .zero: "Uspilte hull gir 0 poeng"
        }
    }

    /// Hjelpeteksten i `AVKORT_REGLER`.
    public var help: String {
        switch self {
        case .common: "Bare hullene alle rakk teller, for alle. Rettferdig, men de som rakk lengst mister poengene sine fra de siste hullene."
        case .netPar: "Hele runden teller. Hvert hull uten score gir 2 poeng, som om det ble spilt til netto par."
        case .zero: "Hele runden teller. Hull uten score gir ingenting — den som rakk flest hull vinner mest på det."
        }
    }
}
