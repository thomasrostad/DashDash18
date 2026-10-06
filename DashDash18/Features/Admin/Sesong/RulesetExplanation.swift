import Foundation
import GolfgutuCore

/// «Slik telles det»: en kort norsk forklaring av et regelsett, laget av verdiene i regelsettet.
/// Ren funksjon uten SwiftUI, så teksten kan testes.
nonisolated enum RulesetExplanation {
    /// Forklaringen som én tekst.
    static func text(for rules: Ruleset) -> String {
        sentences(for: rules).joined(separator: " ")
    }

    /// Forklaringen setning for setning: tabellen først, så handicap og former.
    static func sentences(for rules: Ruleset) -> [String] {
        var out: [String] = []
        let table = rules.table

        out.append(rules.evenings == 1 ? "Sesongen har 1 kveld." : "Sesongen har \(rules.evenings) kvelder.")

        let mp = table.matchPoints
        if mp.loss == 0 {
            out.append("Seier gir \(RuleFormat.number(mp.win)) poeng, uavgjort \(RuleFormat.number(mp.draw)).")
        } else {
            out.append("Seier gir \(RuleFormat.number(mp.win)) poeng, uavgjort \(RuleFormat.number(mp.draw)) og tap \(RuleFormat.number(mp.loss)).")
        }
        if !table.trianglePoints.isEmpty {
            let places = table.trianglePoints.map(RuleFormat.number).joined(separator: " / ")
            out.append("Trekanten gir \(places) poeng etter plass.")
        }

        out.append(countingSentence(table.counting))
        out.append(contentsOf: sidePrizeSentences(rules.sidePrizes))

        if let step = table.roundingStep {
            out.append("Tabellpoengene rundes til nærmeste \(RuleFormat.number(step)).")
        }
        if !table.tiebreaks.isEmpty {
            out.append("Ved likt poeng skiller \(RuleFormat.list(table.tiebreaks.map(RuleNames.inSentence), last: "så")).")
        }
        out.append(stablefordSentence(table.stablefordCounting))

        out.append("Netto par gir \(rules.scoring.netParPoints) stablefordpoeng.")
        if rules.scoring.minimumPoints != 0 {
            out.append("Laveste poeng på et hull er \(rules.scoring.minimumPoints).")
        }

        out.append(contentsOf: handicapSentences(rules.handicap))
        out.append(contentsOf: formatSentences(rules.formats))
        return out
    }

    // MARK: Deler

    private static func countingSentence(_ c: Ruleset.Counting) -> String {
        let noun = RuleNames.nouns(c.unit)
        guard let best = c.best else { return "Alle \(noun.plural) teller." }
        return best == 1 ? "Den beste \(noun.definite) teller." : "De \(best) beste \(noun.definitePlural) teller."
    }

    private static func stablefordSentence(_ c: Ruleset.Counting) -> String {
        let noun = RuleNames.nouns(c.unit)
        guard let best = c.best else { return "Stablefordsummen tar med alle \(noun.plural)." }
        return best == 1
            ? "Stablefordsummen er den beste \(noun.definite)."
            : "Stablefordsummen er de \(best) beste \(noun.definitePlural)."
    }

    private static func sidePrizeSentences(_ s: Ruleset.SidePrizeRules) -> [String] {
        let ld = s.longestDrive, kp = s.closestToPin
        var out: [String] = []
        switch (ld.enabled, kp.enabled) {
        case (false, false):
            return ["Ingen sidepremier."]
        case (true, true) where ld.points == kp.points:
            out.append("Longest drive og nærmest pinnen gir \(RuleFormat.number(ld.points)) poeng hver.")
        case (true, true):
            out.append("Longest drive gir \(RuleFormat.number(ld.points)) poeng og nærmest pinnen \(RuleFormat.number(kp.points)).")
        case (true, false):
            out.append("Longest drive gir \(RuleFormat.number(ld.points)) poeng. Ingen premie for nærmest pinnen.")
        case (false, true):
            out.append("Nærmest pinnen gir \(RuleFormat.number(kp.points)) poeng. Ingen premie for longest drive.")
        }
        out.append(s.splitTies ? "Likt deler poenget." : "Ved likt får alle på delt førsteplass fullt.")
        return out
    }

    private static func handicapSentences(_ h: Ruleset.HandicapRules) -> [String] {
        var out: [String] = []
        if let a = h.allowanceOverride {
            out.append("Alle spiller med \(RuleFormat.percent(a)) av handicapet.")
        } else {
            out.append("Handicapandelen følger formen.")
        }
        let groups = h.seedingGroups.sorted { $0.number < $1.number }
        if !groups.isEmpty {
            let parts = groups.enumerated().map { i, g in
                i == 0 ? "\(g.name) spiller på \(RuleFormat.number(g.handicap))" : "\(g.name) på \(RuleFormat.number(g.handicap))"
            }
            out.append("Seeding: \(RuleFormat.list(parts)).")
        }
        if h.externalHandicap { out.append("Simulatoren deler ut slagene.") }
        return out
    }

    private static func formatSentences(_ f: Ruleset.FormatRules) -> [String] {
        var out: [String] = []
        let catalog = CompetitionForm.all
        let allowed = catalog.filter { f.allowedFormIDs.contains($0.id) }
        let standard = catalog.first { $0.id == f.defaultFormID }?.name ?? f.defaultFormID
        if allowed.count == catalog.count {
            out.append("\(standard) er standardformen, og alle \(catalog.count) former er tillatt.")
        } else if allowed.count == 1 {
            out.append("\(standard) er standardformen og den eneste tillatte formen.")
        } else {
            out.append("\(standard) er standardformen, og \(allowed.count) av \(catalog.count) former er tillatt.")
        }
        out.append(f.maxPerBay == 1 ? "Høyst 1 spiller per bås." : "Høyst \(f.maxPerBay) spillere per bås.")
        switch f.matchStrokes {
        case .lowestFromScratch: out.append("I match spiller den laveste fra scratch.")
        case .fullHandicap: out.append("I match spiller alle på fullt handicap.")
        }
        return out
    }
}

// MARK: - Norske navn og tall

/// Norske navn på valgene i regelsettet. Samlet her (ikke som extensions på regelmotorens typer),
/// så de ikke kolliderer med navn andre deler av appen gir de samme typene.
nonisolated enum RuleNames {
    struct Nouns {
        let plural: String
        let definite: String
        let definitePlural: String
    }

    static func nouns(_ unit: Ruleset.Counting.Unit) -> Nouns {
        switch unit {
        case .match: Nouns(plural: "matcher", definite: "matchen", definitePlural: "matchene")
        case .round: Nouns(plural: "runder", definite: "runden", definitePlural: "rundene")
        case .evening: Nouns(plural: "kvelder", definite: "kvelden", definitePlural: "kveldene")
        }
    }

    static func title(_ unit: Ruleset.Counting.Unit) -> String {
        switch unit {
        case .match: "Matcher"
        case .round: "Runder"
        case .evening: "Kvelder"
        }
    }

    static func title(_ tiebreak: Ruleset.Tiebreak) -> String {
        switch tiebreak {
        case .holeDifference: "Hulldifferanse"
        case .stableford: "Stablefordsum"
        }
    }

    static func inSentence(_ tiebreak: Ruleset.Tiebreak) -> String {
        switch tiebreak {
        case .holeDifference: "hulldifferanse"
        case .stableford: "stablefordsummen"
        }
    }

    static func title(_ strokes: Ruleset.MatchStrokes) -> String {
        switch strokes {
        case .lowestFromScratch: "Laveste fra scratch"
        case .fullHandicap: "Fullt handicap"
        }
    }

    static func title(_ method: Ruleset.TeamHandicapRule.Method) -> String {
        switch method {
        case .average: "Snitt"
        case .weighted: "Vektet"
        case .lowest: "Laveste"
        }
    }
}

/// Tall i norsk form: desimalkomma og ingen overflødige nuller (0,5, 1, 0,25).
nonisolated enum RuleFormat {
    private static let locale = Locale(identifier: "nb_NO")

    static func number(_ x: Double) -> String {
        x.formatted(.number.locale(locale).precision(.fractionLength(0...2)).grouping(.never))
    }

    /// 0,95 → «95 %».
    static func percent(_ x: Double) -> String {
        "\(number(x * 100)) %"
    }

    /// «a», «a og b», «a, b og c». `last` er ordet før det siste leddet.
    static func list(_ items: [String], last: String = "og") -> String {
        guard items.count > 1 else { return items.first ?? "" }
        let separator = last == "og" ? ", " : ", \(last) "
        return items.dropLast().joined(separator: separator) + (last == "og" ? " og " : ", \(last) ") + items.last!
    }
}
