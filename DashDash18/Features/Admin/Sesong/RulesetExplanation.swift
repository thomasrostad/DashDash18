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

        out.append("Turneringen har \(rules.day.count(rules.evenings)).")

        let mp = table.matchPoints
        if table.pointsSource == .stableford {
            out.append("Stablefordpoengene i hver runde er tabellpoengene.")
        } else if mp.loss == 0 {
            out.append("Seier gir \(RuleFormat.number(mp.win)) poeng, uavgjort \(RuleFormat.number(mp.draw)).")
        } else {
            out.append("Seier gir \(RuleFormat.number(mp.win)) poeng, uavgjort \(RuleFormat.number(mp.draw)) og tap \(RuleFormat.number(mp.loss)).")
        }
        if table.pointsSource == .matches, !table.trianglePoints.isEmpty {
            let places = table.trianglePoints.map(RuleFormat.number).joined(separator: " / ")
            out.append("Trekanten gir \(places) poeng etter plass.")
        }

        out.append(countingSentence(table.counting, term: rules.day))
        out.append(contentsOf: tableRuleSentences(table, term: rules.day))
        out.append(contentsOf: sidePrizeSentences(rules.sidePrizes))

        if let step = table.roundingStep {
            out.append("Tabellpoengene rundes til nærmeste \(RuleFormat.number(step)).")
        }
        if table.tieRule == .playoff {
            out.append("Står flere likt på første plass, avgjøres det med playoff. Annet likt er delt plass.")
        } else if !table.tiebreaks.isEmpty {
            out.append("Ved likt poeng skiller \(RuleFormat.list(table.tiebreaks.map(RuleNames.inSentence), last: "så")).")
        }
        out.append(stablefordSentence(table.stablefordCounting, term: rules.day))

        out.append("Netto par gir \(rules.scoring.netParPoints) stablefordpoeng.")
        if rules.scoring.minimumPoints != 0 {
            out.append("Laveste poeng på et hull er \(rules.scoring.minimumPoints).")
        }

        out.append(contentsOf: handicapSentences(rules.handicap, matches: table.pointsSource == .matches))
        out.append(contentsOf: formatSentences(rules.formats))
        out.append(contentsOf: playSentences(rules.play))
        return out
    }

    /// Føring og visning (regelvern), bare det som ikke er standard (Golfgutu har ingen).
    static func playSentences(_ play: Ruleset.PlayRules) -> [String] {
        var out: [String] = []
        switch play.maxStrokes {
        case .off: break
        case .netDoubleBogey:
            out.append("Du kan føre høyst netto dobbel bogey på et hull (par + 2 + slagene du får). Et høyere tall teller som grensen.")
        case .fixed(let n):
            out.append("Du kan føre høyst \(n) slag på et hull. Et høyere tall teller som grensen.")
        }
        if play.lockSubmittedCards {
            out.append("Når markøren har levert kortet, kan bare arrangøren endre det eller åpne det igjen.")
        }
        if play.shankPosts {
            out.append("Firedobbel bogey eller verre (brutto) står i feeden som en shank, uten varsel.")
        }
        if play.hiddenHoles != Ruleset.PlayRules.standard.hiddenHoles {
            out.append("Skjuler arrangøren de siste hullene i en runde, er det de \(play.hiddenHoles) siste: stillingen vises uten dem til runden er låst.")
        }
        return out
    }

    /// «av», «netto dobbel bogey» eller «10 slag».
    static func maxStrokesText(_ m: Ruleset.MaxStrokes) -> String {
        switch m {
        case .off: "av"
        case .netDoubleBogey: "netto dobbel bogey"
        case .fixed(let n): "\(n) slag"
        }
    }

    // MARK: Deler

    private static func countingSentence(_ c: Ruleset.Counting, term: DayTerm) -> String {
        let noun = RuleNames.nouns(c.unit, term: term)
        guard let best = c.best else { return "Alle \(noun.plural) teller." }
        return best == 1 ? "Den beste \(noun.definite) teller." : "De \(best) beste \(noun.definitePlural) teller."
    }

    /// Tabellreglene fra steg 6, bare når de er i bruk (Golfgutu har ingen).
    private static func tableRuleSentences(_ table: Ruleset.TableRules, term: DayTerm) -> [String] {
        var out: [String] = []
        if table.aggregation == .average {
            out.append("Tabellen viser snittet per \(term.one) som teller.")
        }
        for (name, t) in table.pointsTables.sorted(by: { $0.key < $1.key }) {
            out.append("\(name) teller \(RuleFormat.number(t.multiplier)) ganger.")
        }
        if let min = table.minEvenings, min > 0 {
            out.append("Du må ha spilt minst \(term.count(min)) for å få plass i tabellen.")
        }
        return out
    }

    private static func stablefordSentence(_ c: Ruleset.Counting, term: DayTerm) -> String {
        let noun = RuleNames.nouns(c.unit, term: term)
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

    private static func handicapSentences(_ h: Ruleset.HandicapRules, matches: Bool) -> [String] {
        var out: [String] = []
        if let a = h.allowanceOverride {
            out.append("Alle spiller med \(RuleFormat.percent(a)) av handicapet.")
        } else {
            out.append("Handicapandelen følger formen.")
        }
        let groups = h.seedingGroups.sorted { $0.number < $1.number }
        if matches, !groups.isEmpty {
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
        out.append(f.maxPerBay == 1 ? "Høyst 1 spiller per bås eller flight." : "Høyst \(f.maxPerBay) spillere per bås eller flight.")
        switch f.matchStrokes {
        case .lowestFromScratch: out.append("I match spiller den laveste fra scratch.")
        case .fullHandicap: out.append("I match spiller alle på fullt handicap.")
        }
        switch f.drawMethod {
        case .standings: break
        case .avoidRepeats: out.append("Matchene trekkes tilfeldig, med færrest mulig gjentakelser.")
        case .manual: out.append("Arrangøren setter opp matchene.")
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

    /// `term`: «kveld» eller «spilledag» for enheten `evening` (`DayTerm`).
    static func nouns(_ unit: Ruleset.Counting.Unit, term: DayTerm = .evening) -> Nouns {
        switch unit {
        case .match: Nouns(plural: "matcher", definite: "matchen", definitePlural: "matchene")
        case .round: Nouns(plural: "runder", definite: "runden", definitePlural: "rundene")
        case .evening: Nouns(plural: term.many, definite: term.the, definitePlural: term.theMany)
        }
    }

    static func title(_ unit: Ruleset.Counting.Unit, term: DayTerm = .evening) -> String {
        switch unit {
        case .match: "Matcher"
        case .round: "Runder"
        case .evening: DayTerm.capitalized(term.many)
        }
    }

    static func title(_ source: Ruleset.TablePointsSource) -> String {
        switch source {
        case .matches: "Matcher"
        case .stableford: "Stableford"
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

    static func title(_ aggregation: Ruleset.Aggregation) -> String {
        switch aggregation {
        case .sum: "Sum"
        case .average: "Snitt"
        }
    }

    static func title(_ rule: Ruleset.TieRule) -> String {
        switch rule {
        case .tiebreaks: "Skilletegn"
        case .playoff: "Playoff"
        }
    }

    static func title(_ method: Ruleset.DrawMethod) -> String {
        switch method {
        case .standings: "Etter tabellen"
        case .avoidRepeats: "Tilfeldig uten gjentakelser"
        case .manual: "Manuelt"
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
