import Foundation

// Steg 7: regelverdiene for de nye formene (`Ruleset.formPlay`), poengspillene Amerikaner og
// Københavner, og poengene en runde gir i tabellen når tabellen teller formens poeng
// (`table.formPoints`).
//
// Kilde for poengspillene: Norges Golfforbund, «Spilleformer», sist endret 4. oktober 2023
// (golfforbundet.no/files/documents/spilletyper-og-spilleformer-2023.pdf):
// - Amerikaner, side 3: «Fire spiller slagspill og det spilles om 12 poeng på hvert hull. Beste score
//   får 8 poeng, nest beste 4 poeng og resten 0. Er én spiller best og to andre nest best, gis 8, 2, 2,
//   0. Er én spiller best og de tre andre like, gis 9, 1, 1, 1. Er to spillere best, gis 6, 6, 0, 0.
//   Er tre spillere best, gis 4, 4, 4, 0. Er alle like, gis 3, 3, 3, 3.»
// - Københavner, side 4: «Slagspillkonkurranse mellom tre spillere som deler 6 poeng på hvert hull. Den
//   beste får 4 p., den nest beste 2 p. og den dårligste 0 p. Er en spiller best alene og to like, blir
//   poengene 4-1-1. Hvis to er best og en dårligst, blir poengene 3-3-0. Er alle like blir poengene 2-2-2.»
// Dokumentet sier ikke om scorene er netto eller brutto. Standarden her er netto med fullt
// spillehandicap (som resten av appen), og det kan endres i regelsettet (`handicap`).

// MARK: - Regelsettet

/// Ett poengspill: antall spillere i gruppen, handicap og poengene per hull etter likhetsmønster.
public struct PointsGameRules: Codable, Hashable, Sendable {
    /// Spillere i gruppen.
    public var players: Int
    /// Netto eller brutto, og andelen av spillehandicapet.
    public var handicap: GameHandicap
    /// Poengene per hull etter mønsteret av like scorer, best først. Nøkkelen er gruppestørrelsene
    /// fra beste score og nedover, skilt med «-»: «1-2-1» er én best, to like på andreplass og én sist.
    /// Verdien er poengene per plass (beste først). Like scorer får snittet av plassene sine.
    public var points: [String: [Double]]

    public init(players: Int, handicap: GameHandicap, points: [String: [Double]]) {
        self.players = players
        self.handicap = handicap
        self.points = points
    }

    /// Netto med fullt spillehandicap (dokumentet sier ikke noe om handicap).
    static let fullHandicap = GameHandicap(net: true, allowance: 1, fromLowest: false)

    /// Amerikaner etter NGF (side 3): 12 poeng per hull.
    public static let amerikaner = PointsGameRules(players: 4, handicap: fullHandicap, points: [
        "1-1-1-1": [8, 4, 0, 0],
        "1-1-2": [8, 4, 0, 0],
        "1-2-1": [8, 2, 2, 0],
        "1-3": [9, 1, 1, 1],
        "2-1-1": [6, 6, 0, 0],
        "2-2": [6, 6, 0, 0],
        "3-1": [4, 4, 4, 0],
        "4": [3, 3, 3, 3],
    ])

    /// Københavner etter NGF (side 4): 6 poeng per hull.
    public static let kobenhavner = PointsGameRules(players: 3, handicap: fullHandicap, points: [
        "1-1-1": [4, 2, 0],
        "1-2": [4, 1, 1],
        "2-1": [3, 3, 0],
        "3": [2, 2, 2],
    ])

    public static func standard(_ kind: PointsGameKind) -> PointsGameRules {
        switch kind {
        case .amerikaner: amerikaner
        case .kobenhavner: kobenhavner
        }
    }
}

/// Regelverdiene for formene fra steg 7 (`Ruleset.formPlay`). Golfgutu-oppsettet har standarden, og
/// da skrives gruppen ikke i JSON-en.
public struct FormPlayRules: Hashable, Sendable {
    /// Poengspillene etter navn (`PointsGameKind.rawValue`). Mangler et spill, gjelder standarden.
    public var pointsGames: [String: PointsGameRules]
    /// Skins som form: samme regler som rundespillet (`SkinsRules`). Standard: som rundespillet
    /// (netto, fullt handicap, carry-over, det som står igjen etter siste hull faller bort).
    public var skins: SkinsRules
    /// Tabellpoeng per skin vunnet (med `table.formPoints`).
    public var skinPoints: Double
    /// Lag mot lag (Ryder Cup): poeng til siden for seier, delt og tap i en match.
    public var teamMatch: Ruleset.MatchPoints
    /// Par/bogey: verdien av et vunnet, delt og tapt hull mot banen. Standard +1 / 0 / −1 (regel 21.3).
    public var parBogey: ParBogeyRules
    /// Maksimumscore: taket per hull når konkurransen ikke har sitt eget. Standard netto dobbel bogey
    /// (par + 2 + slagene fått på hullet), som WHS bruker (regel 21.2 lar komiteen velge).
    public var maximumScore: Ruleset.MaxStrokes

    public init(pointsGames: [String: PointsGameRules], skins: SkinsRules, skinPoints: Double,
                teamMatch: Ruleset.MatchPoints, parBogey: ParBogeyRules = .standard,
                maximumScore: Ruleset.MaxStrokes = FormPlayRules.standardMaximumScore) {
        self.pointsGames = pointsGames
        self.skins = skins
        self.skinPoints = skinPoints
        self.teamMatch = teamMatch
        self.parBogey = parBogey
        self.maximumScore = maximumScore
    }

    /// Taket i maksimumscore når regelsettet ikke sier noe: netto dobbel bogey.
    public static let standardMaximumScore = Ruleset.MaxStrokes.netDoubleBogey

    /// Standarden: NGF-poengene, skins som rundespillet med 1 tabellpoeng per skin, og 1 / ½ / 0 per
    /// match i lag mot lag (som Ryder Cup).
    public static let standard = FormPlayRules(
        pointsGames: Dictionary(uniqueKeysWithValues: PointsGameKind.allCases.map { ($0.rawValue, PointsGameRules.standard($0)) }),
        skins: .standard,
        skinPoints: 1,
        teamMatch: Ruleset.MatchPoints(win: 1, draw: 0.5, loss: 0)
    )

    /// Reglene for poengspillet.
    public func pointsGame(_ kind: PointsGameKind) -> PointsGameRules {
        pointsGames[kind.rawValue] ?? .standard(kind)
    }
}

extension FormPlayRules: Codable {
    private enum CodingKeys: String, CodingKey { case pointsGames, skins, skinPoints, teamMatch, parBogey, maximumScore }
    private enum GameKeys: String, CodingKey { case players, handicap, points }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let s = FormPlayRules.standard
        var games = s.pointsGames
        if c.contains(.pointsGames) {
            let g = try c.nestedContainer(keyedBy: AnyKey.self, forKey: .pointsGames)
            for key in g.allKeys {
                let base = PointsGameKind(rawValue: key.stringValue).map(PointsGameRules.standard)
                    ?? PointsGameRules(players: 0, handicap: PointsGameRules.fullHandicap, points: [:])
                let n = try g.nestedContainer(keyedBy: GameKeys.self, forKey: key)
                games[key.stringValue] = PointsGameRules(
                    players: try n.decodeIfPresent(Int.self, forKey: .players) ?? base.players,
                    handicap: try GameHandicap.decode(n, .handicap, fallback: base.handicap),
                    points: try n.decodeIfPresent([String: [Double]].self, forKey: .points) ?? base.points)
            }
        }
        pointsGames = games
        skins = try c.decodeIfPresent(SkinsRules.self, forKey: .skins) ?? s.skins
        skinPoints = try c.decodeIfPresent(Double.self, forKey: .skinPoints) ?? s.skinPoints
        teamMatch = try c.decodeIfPresent(Ruleset.MatchPoints.self, forKey: .teamMatch) ?? s.teamMatch
        parBogey = try c.decodeIfPresent(ParBogeyRules.self, forKey: .parBogey) ?? s.parBogey
        maximumScore = try c.decodeIfPresent(Ruleset.MaxStrokes.self, forKey: .maximumScore) ?? s.maximumScore
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(pointsGames, forKey: .pointsGames)
        try c.encode(skins, forKey: .skins)
        try c.encode(skinPoints, forKey: .skinPoints)
        try c.encode(teamMatch, forKey: .teamMatch)
        // Skrives bare når den ikke er standard, så JSON-en for eldre regelsett er som før.
        if parBogey != .standard { try c.encode(parBogey, forKey: .parBogey) }
        if maximumScore != Self.standardMaximumScore { try c.encode(maximumScore, forKey: .maximumScore) }
    }
}

// MARK: - Par/bogey

/// Par/bogey (Golfreglene 2019, regel 21.3): spilleren spiller match mot banen. Hvert hull er vunnet
/// (netto under banens fastsatte score, par), delt (likt) eller tapt (over, eller ingen score).
/// Verdiene ligger i regelsettet (`formPlay.parBogey`); standarden er +1, 0 og −1, så summen er
/// «hull vunnet minus hull tapt» som regel 21.3b sier.
public struct ParBogeyRules: Codable, Hashable, Sendable {
    public var win: Double
    public var halve: Double
    public var loss: Double

    public init(win: Double, halve: Double, loss: Double) {
        self.win = win
        self.halve = halve
        self.loss = loss
    }

    /// Regel 21.3b: vunnet +1, delt 0, tapt −1.
    public static let standard = ParBogeyRules(win: 1, halve: 0, loss: -1)

    private enum CodingKeys: String, CodingKey { case win, halve, loss }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let s = ParBogeyRules.standard
        win = try c.decodeIfPresent(Double.self, forKey: .win) ?? s.win
        halve = try c.decodeIfPresent(Double.self, forKey: .halve) ?? s.halve
        loss = try c.decodeIfPresent(Double.self, forKey: .loss) ?? s.loss
    }
}

public enum ParBogey {
    /// Resultatet på et hull: netto mot par. `nil` (ingen score) er tapt hullet (regel 21.3b),
    /// men bare når runden er ferdig; ellers venter hullet (se `RoundCompetitions`).
    public static func holeValue(net: Int?, par: Int, rules: ParBogeyRules) -> Double {
        guard let net else { return rules.loss }
        if net < par { return rules.win }
        if net == par { return rules.halve }
        return rules.loss
    }
}

/// En nøkkel for ordbøker med vilkårlige navn.
struct AnyKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

// MARK: - Poengspillene

/// Ett hull i et poengspill.
public struct PointsGameHole: Hashable, Sendable {
    public enum State: String, Codable, Hashable, Sendable {
        /// Noen i gruppen mangler score.
        case pending
        /// Poengene er delt ut.
        case scored
        /// Teller ikke: runden er ferdig, og noen mangler score (eller mønsteret finnes ikke i tabellen).
        case void
    }

    /// Rundens 0-baserte hull.
    public var hole: Int
    public var state: State
    /// Likhetsmønsteret («1-2-1»). `nil` uten score.
    public var pattern: String?
    /// Poengene på hullet per spiller. Tom når hullet ikke er regnet.
    public var points: [String: Double]
}

/// Stillingen i et poengspill for én gruppe.
public struct PointsGameResult: Hashable, Sendable {
    public var kind: PointsGameKind
    public var players: [String]
    public var holes: [PointsGameHole]
    /// Sum per spiller (alle i gruppen, også 0).
    public var totals: [String: Double]
    /// Ingen hull venter på score.
    public var isFinished: Bool
}

/// Amerikaner og Københavner: gruppen deler et fast antall poeng per hull etter rangering, med egne
/// poeng ved likt (se `PointsGameRules`).
public enum PointsGame {
    /// Likhetsmønsteret for scorene (lavest er best): gruppestørrelsene fra beste score, skilt med «-».
    public static func pattern(_ scores: [String: Int]) -> String {
        groups(scores).map { String($0.count) }.joined(separator: "-")
    }

    /// Spillerne gruppert etter score, beste først; innen gruppen sortert på id.
    static func groups(_ scores: [String: Int]) -> [[String]] {
        let sorted = scores.sorted { $0.value != $1.value ? $0.value < $1.value : $0.key < $1.key }
        var out: [[String]] = []
        var last: Int?
        for (id, s) in sorted {
            if s == last { out[out.count - 1].append(id) } else { out.append([id]) }
            last = s
        }
        return out
    }

    /// Poengene på ett hull. Hver spiller får snittet av poengene for plassene gruppen hans dekker
    /// (med NGF-tabellene er de like). `nil` når antallet ikke stemmer med spillet, eller mønsteret
    /// mangler i tabellen.
    public static func holePoints(_ scores: [String: Int], rules: PointsGameRules) -> [String: Double]? {
        guard scores.count == rules.players, let table = rules.points[pattern(scores)],
              table.count == rules.players else { return nil }
        var out: [String: Double] = [:]
        var place = 0
        for group in groups(scores) {
            let share = table[place..<(place + group.count)].reduce(0, +) / Double(group.count)
            for id in group { out[id] = share }
            place += group.count
        }
        return out
    }

    /// Poengspillet for en gruppe på runden. Hullene er spillets tellende hull (`Games.countingHoles`),
    /// eventuelt bare `holes` (0-basert, inkludert). Netto etter regelsettets handicap for spillet, med
    /// spillehandicapet i runden (`Handicap.effective`, frosset ved start). Et hull regnes når alle i
    /// gruppen har score. Mangler noen score når runden er ferdig, teller ikke hullet.
    public static func evaluate(_ kind: PointsGameKind, players: [String], round: Round, roster: [Player],
                                rules: Ruleset, holes range: ClosedRange<Int>? = nil) -> PointsGameResult {
        let game = rules.formPlay.pointsGame(kind)
        let ctx = GameContext(setup: GameSetup(settings: .skins(.standard), players: players), round: round,
                              roster: roster, rules: rules)
        let hcp = ctx.handicaps(game.handicap)
        var totals = Dictionary(uniqueKeysWithValues: players.map { ($0, 0.0) })
        var out: [PointsGameHole] = []
        for h in 0..<ctx.count where range?.contains(h) ?? true {
            var nets: [String: Int] = [:]
            for p in players { if let n = ctx.net(p, h, handicaps: hcp) { nets[p] = n } }
            guard nets.count == players.count else {
                out.append(PointsGameHole(hole: h, state: ctx.isFinal ? .void : .pending, pattern: nil, points: [:]))
                continue
            }
            guard let points = holePoints(nets, rules: game) else {
                out.append(PointsGameHole(hole: h, state: .void, pattern: pattern(nets), points: [:]))
                continue
            }
            for (p, v) in points { totals[p, default: 0] += v }
            out.append(PointsGameHole(hole: h, state: .scored, pattern: pattern(nets), points: points))
        }
        return PointsGameResult(kind: kind, players: players, holes: out, totals: totals,
                                isFinished: !out.contains { $0.state == .pending })
    }
}

// MARK: - Tabellpoeng fra formen

public enum FormPlay {
    /// Spillerne med score i runden, sortert på id.
    static func scoredPlayers(_ round: Round) -> [String] {
        round.holeScores.filter { !$0.value.isEmpty }.map(\.key).sorted()
    }

    /// Gruppene i et poengspill: rundens lag (lagnummeret er gruppen/flighten), ellers alle med score
    /// i én gruppe. Spillere med score som ikke står på noe lag, er ikke med.
    public static func groups(in round: Round) -> [[String]] {
        if round.teams.isEmpty { return [scoredPlayers(round)] }
        let numbers = Set(round.teams.values).sorted()
        return numbers.map { n in round.teams.filter { $0.value == n }.map(\.key).sorted() }
    }

    /// Poengene runden gir hver spiller i tabellen når tabellen teller formens poeng (`table.formPoints`):
    /// - skins: skins vunnet · `formPlay.skinPoints` (alle med score spiller mot hverandre, med
    ///   `formPlay.skins` som i rundespillet);
    /// - Amerikaner og Københavner: poengene i gruppen (`groups(in:)`);
    /// - par/bogey: summen av `formPlay.parBogey` per hull (regel 21.3);
    /// - ellers: stablefordpoengene (`Scoring.roundPoints`), som når tabellen teller stableford.
    /// Uvektet; tabellen legger på rundevekten.
    public static func tablePoints(_ round: Round, roster: [Player], rules: Ruleset) -> [String: Double] {
        switch round.form.axes.scoring {
        case .skins:
            let players = scoredPlayers(round)
            guard !players.isEmpty else { return [:] }
            let setup = GameSetup(settings: .skins(rules.formPlay.skins), players: players)
            let result = Games.evaluate(setup, round: round, roster: roster, rules: rules)
            return Dictionary(uniqueKeysWithValues: players.map { ($0, (result.scores[$0] ?? 0) * rules.formPlay.skinPoints) })
        case .pointsGame(let kind):
            var out: [String: Double] = [:]
            for group in groups(in: round) where !group.isEmpty {
                let r = PointsGame.evaluate(kind, players: group, round: round, roster: roster, rules: rules)
                out.merge(r.totals) { _, new in new }
            }
            return out
        case .parBogey:
            // Par/bogey-summen (regel 21.3) med fullt spillehandicap i runden, som hovedkonkurransen.
            var out: [String: Double] = [:]
            for row in formResult(round, roster: roster, rules: rules)?.rows ?? [] {
                for p in row.players { out[p] = row.score }
            }
            return out
        default:
            return Scoring.roundPoints(round, roster: roster, rules: rules).mapValues(Double.init)
        }
    }

    /// Rundens resultat etter formen når den ikke er netto stableford: slagspill (netto eller brutto),
    /// stableford brutto, maksimumscore (regel 21.2) og par/bogey (21.3), regnet som hovedkonkurransen
    /// med fullt spillehandicap i runden (`RoundCompetitions`). Brutto ser bort fra handicap uansett andel.
    /// `nil` for netto stableford (Golfgutu-veien, `Scoring.roundPoints`) og formene som har sin egen vei
    /// (match, skins, poengspill).
    public static func formResult(_ round: Round, roster: [Player], rules: Ruleset) -> RoundCompetitionResult? {
        let axes = round.form.axes
        switch axes.scoring {
        case .strokePlay, .maximumScore, .parBogey, .stableford(net: false): break
        default: return nil
        }
        let comp = RoundCompetition(id: "form", teamForm: axes.teamForm, scoring: axes.scoring)
        return RoundCompetitions.evaluate(round, roster: roster, competitions: [comp], rules: rules)[0]
    }
}
