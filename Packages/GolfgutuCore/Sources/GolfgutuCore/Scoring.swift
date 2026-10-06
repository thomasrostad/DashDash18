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

    /// `pointsForHole`: stableford, `max(0, par − netto + 2)`.
    public static func points(par: Int, gross: Int, handicap: Double, strokeIndex: Int, holes: Int) -> Int {
        max(0, par - netStrokes(gross: gross, handicap: handicap, strokeIndex: strokeIndex, holes: holes) + 2)
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
    public static func points(from scores: HoleScores, in round: Round, handicap: Double) -> Int {
        if scores.isEmpty { return 0 }
        let course = round.courseHoles()
        let count = round.numberOfHoles
        let counting = Truncation.countingHoles(round)
        let empty = Truncation.pointsForEmptyHole(round)
        var total = 0
        for i in 0..<counting where i < course.count {
            let hole = course[i]
            if let gross = scores[i] {
                total += points(par: hole.par, gross: gross, handicap: handicap, strokeIndex: hole.strokeIndex, holes: count)
            } else {
                total += empty
            }
        }
        return total
    }

    /// `roundNetTotal`: summen for én spiller med et gitt handicap.
    public static func roundNetTotal(_ round: Round, playerID: String?, handicap: Double) -> Int {
        points(from: playerID.flatMap { round.holeScores[$0] } ?? [:], in: round, handicap: handicap)
    }

    /// `roundNetTotalForPlayer`: summen med spillerens `effectiveHandicap` i runden.
    public static func roundNetTotal(_ round: Round, player: Player?, roster: [Player],
                                     groups: [SeedingGroup] = SeedingGroup.golfgutu) -> Int {
        roundNetTotal(round, playerID: player?.id,
                      handicap: Handicap.effective(for: player, in: round, roster: roster, groups: groups))
    }
}
