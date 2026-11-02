import Foundation

/// En seedet gruppe med fast turneringshandicap (`SEEDING_GRUPPER`).
public struct SeedingGroup: Codable, Hashable, Sendable {
    public var number: Int
    public var handicap: Double
    public var name: String

    public init(number: Int, handicap: Double, name: String) {
        self.number = number
        self.handicap = handicap
        self.name = name
    }

    /// Golfgutu-oppsettet: gruppe 1/2/3 spiller på 0/5/10.
    public static let golfgutu: [SeedingGroup] = [
        SeedingGroup(number: 1, handicap: 0, name: "Gruppe 1"),
        SeedingGroup(number: 2, handicap: 5, name: "Gruppe 2"),
        SeedingGroup(number: 3, handicap: 10, name: "Gruppe 3"),
    ]
}

/// Handicap og tildeling, som i db-nytt.js linje 58–344.
///
/// Alle funksjonene som leser seeding eller lagshandicap tar inn regelsettet, med
/// Golfgutu-oppsettet som standard.
public enum Handicap {
    // MARK: Seeding

    /// `seedingGruppe`: gruppa med dette nummeret, eller `nil`.
    public static func seedingGroup(_ number: Int?, rules: Ruleset = .golfgutu) -> SeedingGroup? {
        guard let number else { return nil }
        return rules.handicap.seedingGroups.first { $0.number == number }
    }

    /// `gruppeHandicap`: gruppas faste tall, eller `nil` når spilleren ikke er seedet.
    /// `nil` er noe annet enn 0: gruppe 1 spiller på 0.
    public static func groupHandicap(for player: Player?, rules: Ruleset = .golfgutu) -> Double? {
        seedingGroup(player?.seedGroup, rules: rules)?.handicap
    }

    /// `erSeedet`.
    public static func isSeeded(_ player: Player?, rules: Ruleset = .golfgutu) -> Bool {
        groupHandicap(for: player, rules: rules) != nil
    }

    // MARK: WHS

    /// `courseHandicap`: `round(indeks · slope/113 + (rating − par))`, avrundet som JS.
    /// Mangler rating, brukes par. Mangler slope, brukes 113. Mangler par (eller 0), brukes 72.
    public static func courseHandicap(index: Double?, courseRating: Double?, slopeRating: Double?, par: Double?) -> Double {
        let idx = jsNumber(index)
        let p = jsNumber(par) == 0 ? 72 : jsNumber(par)
        let rating = courseRating ?? p
        let slope = slopeRating ?? 113
        return JS.round(idx * (slope / 113) + (rating - p))
    }

    /// `rundeAndel`: tildelingen lagret på runden. Et tall ≥ 0 brukes (0 er brutto), ellers 1.
    public static func allowance(_ round: Round) -> Double {
        if let a = round.hcpAllowance, a >= 0 { return a }
        return 1
    }

    /// `banehandicap`: seedet → gruppetallet. Uten tildeling.
    ///
    /// Som PWA-en (`pwa`): banehandicapet for 18 hull når runden har bane, og rå indeks (ikke avrundet)
    /// uten bane. Antall hull regnes inn senere (`teamBasis`, `effective`).
    /// Golfreglene (`whs`): banehandicapet for hullene som spilles, avrundet (`whsCourseHandicap`).
    public static func courseHandicap(for player: Player?, in round: Round,
                                      rules: Ruleset = .golfgutu) -> Double {
        if let gh = groupHandicap(for: player, rules: rules) { return gh }
        let idx = jsNumber(player?.handicap)
        if rules.handicap.calculation == .whs { return Double(whsCourseHandicap(index: idx, in: round)) }
        if let course = round.course {
            return courseHandicap(index: idx, courseRating: course.courseRating, slopeRating: course.slopeRating,
                                  par: course.par.map(Double.init))
        }
        return idx
    }

    /// Banehandicap etter golfreglene for hullene runden spiller (regel 6.1a og 6.1b, `WHS.courseHandicap`).
    ///
    /// - Course rating og slope er banens (teens tall frosset på runden). Ratingen gjelder 9 hull når banen
    ///   har 9 hull, ellers 18. Mangler rating, er den lik par; mangler slope, brukes 113.
    /// - Par: banens par når runden spiller like mange hull som ratingen gjelder, ellers summen av par på
    ///   hullene som spilles (`courseHoles`). Ni hull på en 18-hullsbane: halve CR mot par for de ni.
    /// - Uten bane: indeksen for hullene (slope 113, CR = par).
    public static func whsCourseHandicap(index: Double, in round: Round) -> Int {
        let holes = round.numberOfHoles
        let playedPar = round.courseHoles().reduce(0) { $0 + $1.par }
        guard let course = round.course else {
            return WHS.roundWhole(index * Double(holes) / 18)
        }
        let rated = course.holes?.count == 9 ? 9 : 18
        let par = (holes == rated ? course.par.flatMap { $0 > 0 ? $0 : nil } : nil) ?? playedPar
        // Uten rating: lik par for hullene ratingen gjelder, så CR − par blir 0.
        let rating = course.courseRating ?? Double(par) * Double(rated) / Double(holes)
        return WHS.courseHandicap(index: index, slope: course.slopeRating ?? WHS.standardSlope,
                                  courseRating: rating, ratedHoles: rated, par: par, holes: holes)
    }

    /// `lagGrunnlag`: det én mann tar med inn i laget. Seedet → gruppetallet (halveres ikke).
    /// Som PWA-en: banehandicap · antall hull / 18, ikke avrundet. Golfreglene: banehandicapet for
    /// hullene som spilles (allerede for 9 eller 18 hull, avrundet; WHS appendiks C).
    public static func teamBasis(for player: Player?, in round: Round,
                                 rules: Ruleset = .golfgutu) -> Double {
        if let gh = groupHandicap(for: player, rules: rules) { return gh }
        let ch = courseHandicap(for: player, in: round, rules: rules)
        return rules.handicap.calculation == .whs ? ch : ch * (Double(round.numberOfHoles) / 18)
    }

    /// `lagHandicap`: lagets ene handicap.
    ///
    /// Regelen for formen står i regelsettet (Golfgutu: toerformer snittet av grunnlagene,
    /// `scramble-4` 25/20/15/10 % lavest først, ellers laveste grunnlag · tildeling).
    /// Ett avrundingstrinn til slutt (`HandicapCalculation.roundWhole`). Brutto (tildeling 0) gir 0.
    /// - Parameter members: spillerne på laget. `nil` er en id som ikke finnes i troppen.
    public static func teamHandicap(in round: Round, members: [Player?],
                                    rules: Ruleset = .golfgutu) -> Double {
        let basis = members.map { teamBasis(for: $0, in: round, rules: rules) }.sorted()
        if basis.isEmpty { return 0 }
        if allowance(round) == 0 { return 0 }
        let rule = rules.handicap.teamHandicapRule(for: round.form.id)
        let sum: Double
        switch rule.method {
        case .average:
            sum = basis.reduce(0, +) / Double(basis.count)
        case .weighted:
            sum = zip(rule.weights ?? [], basis).reduce(0) { $0 + $1.0 * $1.1 }
        case .lowest:
            sum = basis[0] * allowance(round)
        }
        return rules.handicap.calculation.roundWhole(sum)
    }

    /// `lagHandicap` med spiller-id-er slått opp i troppen.
    public static func teamHandicap(in round: Round, memberIDs: [String], roster: [Player],
                                    rules: Ruleset = .golfgutu) -> Double {
        teamHandicap(in: round, members: memberIDs.map { id in roster.first { $0.id == id } }, rules: rules)
    }

    /// `lagFor`: lagkameratene (inkludert spilleren selv), eller `nil` uten lag.
    /// Lagnummer 0 regnes som «ikke på lag», som i JS.
    public static func teammates(of playerID: String, in round: Round) -> [String]? {
        guard let number = round.teams[playerID], number != 0 else { return nil }
        return round.teams.filter { $0.value == number }.map(\.key).sorted()
    }

    /// `effectiveHandicap`: spillerens handicap i denne runden, i hele slag.
    ///
    /// 1. Simulatoren deler ut slagene (`hcpExtern`) → 0.
    /// 1b. Rundens frosne spillehandicap (`round.playingHandicaps`) for spilleren → det.
    /// 2. Lagform med ett kort per lag, eller toerform, og spilleren har lag → lagets handicap.
    /// 3. Seedet → gruppetallet (0 når tildelingen er 0).
    /// 4. Ellers som PWA-en `round(banehandicap · tildeling · antall hull / 18)`, eller etter golfreglene
    ///    `round(banehandicap for hullene · tildeling)` (regel 6.2), ,5 bort fra null.
    public static func effective(for player: Player?, in round: Round, roster: [Player],
                                 rules: Ruleset = .golfgutu) -> Double {
        if round.hcpExtern { return 0 }
        if let id = player?.id, let frozen = round.playingHandicaps[id] { return frozen }
        let form = round.form
        if form.card == .perTeam || form.teamSize == 2, let player,
           let mates = teammates(of: player.id, in: round), !mates.isEmpty {
            return teamHandicap(in: round, memberIDs: mates, roster: roster, rules: rules)
        }
        if let gh = groupHandicap(for: player, rules: rules) {
            return allowance(round) > 0 ? gh : 0
        }
        let ch = courseHandicap(for: player, in: round, rules: rules)
        switch rules.handicap.calculation {
        case .pwa: return JS.round(ch * allowance(round) * (Double(round.numberOfHoles) / 18))
        case .whs: return Double(WHS.roundWhole(ch * allowance(round)))
        }
    }

    /// `Number(x) || 0`: `nil` og NaN blir 0.
    static func jsNumber(_ x: Double?) -> Double {
        guard let x, !x.isNaN else { return 0 }
        return x
    }
}
