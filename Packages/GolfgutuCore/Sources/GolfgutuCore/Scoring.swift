import Foundation

/// Hvordan et hull gikk, netto mot par (`scoreNameForHole`).
public enum ScoreName: String, Codable, Sendable, CaseIterable {
    case eagle, birdie, par, bogey, dobbel, blowup

    /// `SCORE_LABEL`.
    public var label: String {
        switch self {
        case .eagle: "Eagle"
        case .birdie: "Birdie"
        case .par: "Par"
        case .bogey: "Bogey"
        case .dobbel: "Dobbel"
        case .blowup: "Blowup"
        }
    }
}

/// Slag og stablefordpoeng (db-nytt.js linje 823–836, 906–909, 992–1050).
public enum Scoring {
    /// `handicapStrokesForHole`: slag fått på hullet. Fordeles over antall hull (9 eller 18, ellers 18).
    /// Handicap rundes som JS og kan ikke bli negativt.
    public static func handicapStrokes(handicap: Double, strokeIndex: Int, holes: Int) -> Int {
        let n = (holes == 9 || holes == 18) ? holes : 18
        let h = max(0, JS.roundInt(handicap.isNaN ? 0 : handicap))
        return h / n + (strokeIndex <= h % n ? 1 : 0)
    }

    /// `netStrokesForHole`.
    public static func netStrokes(gross: Int, handicap: Double, strokeIndex: Int, holes: Int) -> Int {
        gross - handicapStrokes(handicap: handicap, strokeIndex: strokeIndex, holes: holes)
    }

    /// `pointsForHole`: stableford, `max(bunn, par − netto + poeng for netto par)` fra regelsettet
    /// (Golfgutu: `max(0, par − netto + 2)`).
    public static func points(par: Int, gross: Int, handicap: Double, strokeIndex: Int, holes: Int,
                              rules: Ruleset = .golfgutu) -> Int {
        let net = netStrokes(gross: gross, handicap: handicap, strokeIndex: strokeIndex, holes: holes)
        return max(rules.scoring.minimumPoints, par - net + rules.scoring.netParPoints)
    }

    /// `scoreNameForHole`: netto − par. ≤ −2 eagle, −1 birdie, 0 par, 1 bogey, 2 dobbel, ellers blowup.
    public static func scoreName(par: Int, gross: Int, handicap: Double, strokeIndex: Int, holes: Int) -> ScoreName {
        let diff = netStrokes(gross: gross, handicap: handicap, strokeIndex: strokeIndex, holes: holes) - par
        switch diff {
        case ...(-2): return .eagle
        case -1: return .birdie
        case 0: return .par
        case 1: return .bogey
        case 2: return .dobbel
        default: return .blowup
        }
    }

    /// `poengFraHull`: stablefordsummen over de tellende hullene.
    ///
    /// Hull uten score gir `poengForTomtHull`. Har spilleren ingen score i det hele tatt, er svaret 0,
    /// også med `nettopar`. Nøkkelen er rundens 0-baserte hullindeks.
    public static func points(from scores: HoleScores, in round: Round, handicap: Double,
                              rules: Ruleset = .golfgutu) -> Int {
        if scores.isEmpty { return 0 }
        let course = round.courseHoles()
        let count = round.numberOfHoles
        let counting = Truncation.countingHoles(round)
        let empty = Truncation.pointsForEmptyHole(round, rules: rules)
        var total = 0
        for i in 0..<counting where i < course.count {
            let hole = course[i]
            if let gross = scores[i] {
                total += points(par: hole.par, gross: gross, handicap: handicap, strokeIndex: hole.strokeIndex, holes: count,
                                rules: rules)
            } else {
                total += empty
            }
        }
        return total
    }

    /// `roundNetTotal`: summen for én spiller med et gitt handicap.
    public static func roundNetTotal(_ round: Round, playerID: String?, handicap: Double,
                                     rules: Ruleset = .golfgutu) -> Int {
        points(from: playerID.flatMap { round.holeScores[$0] } ?? [:], in: round, handicap: handicap, rules: rules)
    }

    /// `roundNetTotalForPlayer`: summen med spillerens `effectiveHandicap` i runden.
    public static func roundNetTotal(_ round: Round, player: Player?, roster: [Player],
                                     rules: Ruleset = .golfgutu) -> Int {
        roundNetTotal(round, playerID: player?.id,
                      handicap: Handicap.effective(for: player, in: round, roster: roster, rules: rules), rules: rules)
    }

    /// Rundens poeng per spiller, slik PWA-en lagrer dem i `round_points` (`regnOmRundePoeng`).
    ///
    /// Spillere som har ført noe får sin stablefordsum. Er spilleren på et lag med flere, får hele
    /// laget lagets sum (`skrivLagpoeng`), også de på laget som ikke har ført. Lagets sum går over de
    /// tellende hullene: `sum-netto` summerer, `beste-netto` tar beste, og formene med ett kort tar
    /// første spiller som har ført hullet (id-rekkefølge; i PWA-en er det radrekkefølgen, og tallene
    /// er like når laget fører ett kort). Hull uten score gir `poengForTomtHull`.
    public static func roundPoints(_ round: Round, roster: [Player],
                                   rules: Ruleset = .golfgutu) -> [String: Int] {
        var out: [String: Int] = [:]
        for pid in round.holeScores.keys.sorted() where !(round.holeScores[pid] ?? [:]).isEmpty {
            if out[pid] != nil { continue }
            if let mates = Handicap.teammates(of: pid, in: round), mates.count > 1 {
                let total = teamPoints(round, members: mates, roster: roster, rules: rules)
                for m in mates { out[m] = total }
                continue
            }
            let hcp = Handicap.effective(for: roster.first { $0.id == pid }, in: round, roster: roster, rules: rules)
            out[pid] = roundNetTotal(round, playerID: pid, handicap: hcp, rules: rules)
        }
        return out
    }

    /// `skrivLagpoeng`: lagets sum etter formens regning.
    static func teamPoints(_ round: Round, members: [String], roster: [Player], rules: Ruleset) -> Int {
        let course = round.courseHoles()
        let count = round.numberOfHoles
        let form = round.form
        var perHole: [Int: [Int]] = [:]
        for pid in members {
            guard let scores = round.holeScores[pid] else { continue }
            let hcp = Handicap.effective(for: roster.first { $0.id == pid }, in: round, roster: roster, rules: rules)
            for (h, gross) in scores.sorted(by: { $0.key < $1.key }) where h >= 0 && h < course.count {
                let hole = course[h]
                perHole[h, default: []].append(points(par: hole.par, gross: gross, handicap: hcp,
                                                      strokeIndex: hole.strokeIndex, holes: count, rules: rules))
            }
        }
        let empty = Truncation.pointsForEmptyHole(round, rules: rules)
        var total = 0
        for h in 0..<Truncation.countingHoles(round) {
            guard let p = perHole[h], let first = p.first else { total += empty; continue }
            switch form.scoring {
            case "sum-netto": total += p.reduce(0, +)
            case "beste-netto": total += p.max() ?? first
            default: total += first
            }
        }
        return total
    }
}
