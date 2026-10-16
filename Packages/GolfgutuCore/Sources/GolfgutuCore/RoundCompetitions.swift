import Foundation

// Steg 7: flere konkurranser på samme runde, og øyeblikksbildet av regelsett og hull ved start.
//
// Alle konkurransene leser de samme hullscorene. En konkurranse er to akser (lagform og poengtelling),
// hvem som er med (lag eller grupper) og eventuelt et utvalg hull (første ni, siste ni). Eksempel:
// Stableford individuelt, bestball i par, skins og egne premier på første og siste ni fra samme runde.

/// Et utvalg hull, 0-basert og inkludert (`first...last`).
public struct HoleRange: Codable, Hashable, Sendable {
    public var first: Int
    public var last: Int

    public init(first: Int, last: Int) {
        self.first = first
        self.last = last
    }

    public var range: ClosedRange<Int> { first...max(first, last) }
}

/// Én konkurranse på runden.
public struct RoundCompetition: Codable, Hashable, Sendable {
    public var id: String
    public var teamForm: TeamForm
    public var scoring: ScoringMethod
    /// Sidene (lag) eller gruppene, hver en liste spiller-id-er. `nil`: hver spiller med score for seg
    /// (individuelt), eller alle med score i én gruppe (skins og poengspill).
    public var entrants: [[String]]?
    /// Hullene som teller. `nil`: rundens tellende hull.
    public var holes: HoleRange?
    /// Andelen av spillehandicapet i runden. `nil`: 1 (fullt). Skins bruker `formPlay.skins.handicap`,
    /// poengspillene `formPlay.pointsGames`.
    public var allowance: Double?

    public init(id: String, teamForm: TeamForm, scoring: ScoringMethod, entrants: [[String]]? = nil,
                holes: HoleRange? = nil, allowance: Double? = nil) {
        self.id = id
        self.teamForm = teamForm
        self.scoring = scoring
        self.entrants = entrants
        self.holes = holes
        self.allowance = allowance
    }
}

/// Resultatet av én konkurranse.
public struct RoundCompetitionResult: Hashable, Sendable {
    public struct Row: Hashable, Sendable {
        /// Spilleren, eller spillerne på laget.
        public var players: [String]
        /// Poeng (stableford, skins, poengspill) eller slag (slagspill).
        public var score: Double
        /// Hull som er regnet for raden.
        public var holes: Int
        /// Plassen. Like deler plass (1, 1, 3).
        public var rank: Int
        /// Verdien per regnet hull (rundens 0-baserte hull): poeng, slag eller par/bogey (+1, 0, −1).
        /// Bare for stableford, slagspill, par/bogey, maksimumscore og match (+1 vunnet, 0 delt, −1 tapt).
        public var holeValues: [Int: Double] = [:]
        /// Match: stillingen sett fra raden (siden). `score` er hull opp (negativt = ned).
        public var match: MatchStanding? = nil
    }

    public var id: String
    /// `false`: motoren regner ikke denne kombinasjonen ennå (se `RoundCompetitions.evaluate`).
    public var supported: Bool
    /// Beste først; likt sortert på spiller-id.
    public var rows: [Row]
}

public enum RoundCompetitions {
    /// Alle konkurransene fra samme runde. Handicap: spillehandicapet i runden (`Handicap.effective`,
    /// frosset ved start) ganget med andelen og rundet som JS.
    ///
    /// Støttet:
    /// - stableford (netto eller brutto), slagspill og par/bogey, individuelt, fourball og lag (beste ball
    ///   per hull) og sammenlagt (summen per hull). Hull uten score gir ingenting. I slagspill står de med
    ///   flest hull først, så lavest sum;
    /// - én ball per lag (foursome, greensome, chapman, scramble) med de samme poengtellingene, når runden
    ///   spilles i den lagformen: da føres lagets score på alle på laget (`ForingLogic.recipients` i appen),
    ///   og lagets handicap er spillehandicapet i runden (`Handicap.teamHandicap` med regelsettets
    ///   `handicap.teamHandicap`, frosset ved start). Hullet tar første spiller (id-rekkefølge) med score,
    ///   som `Scoring.teamPoints`. Lagene er rundens lag;
    /// - par/bogey (Golfreglene 2019, regel 21.3): netto mot par per hull, `formPlay.parBogey` for vunnet,
    ///   delt og tapt. Når runden er ferdig, er et hull uten score tapt (21.3b);
    /// - skins (individuelt, alle hull): rundespillet med `formPlay.skins`;
    /// - Amerikaner og Københavner (individuelt): `PointsGame` per gruppe.
    /// - maksimumscore (regel 21.2): slagspill der hvert hull kappes til taket (`play.maxStrokes`-typen:
    ///   netto dobbel bogey eller et fast tall; konkurransens eget, ellers `formPlay.maximumScore`).
    ///   Netto dobbel bogey regnes med slagene fra konkurransens andel, også i brutto. Hull uten score
    ///   som i slagspill: de teller ikke, og flest hull står først;
    /// - match (to sider, `entrants` med to lister): hull for hull med `MatchPlay` (slagene som rundens
    ///   matcher: `formats.matchStrokes`, beste netto på siden). Matchen er over når en side er flere hull
    ///   opp enn det er igjen (regel 3.2a(3)); hullene etter teller ikke. Stillingen står i `Row.match`;
    /// - match med én ball per lag (foursome, greensome, chapman, scramble) når runden spilles i lagformen:
    ///   lag mot lag med lagets ene score, lagets handicap og slagene etter `formats.matchStrokes` (WHS
    ///   Appendix C: foursome-match 50 % av lagets samlede banehandicap, laveste lag fra scratch). Uten
    ///   `entrants`: rundens to lag.
    /// Ikke ennå (`supported == false`): én ball per lag når runden ikke spilles i den lagformen (scorene er
    /// da hver spillers egne), match sammenlagt, og skins og poengspill i lag.
    public static func evaluate(_ round: Round, roster: [Player], competitions: [RoundCompetition],
                                rules: Ruleset) -> [RoundCompetitionResult] {
        competitions.map { evaluate($0, round: round, roster: roster, rules: rules) }
    }

    /// Konkurransene fra øyeblikksbildet: regelsett, hull og handicap slik de var ved start.
    public static func evaluate(_ frozen: FrozenRound, scores: [String: HoleScores], locked: Bool = true,
                                competitions: [RoundCompetition]) -> [RoundCompetitionResult] {
        evaluate(frozen.round(scores: scores, locked: locked), roster: [], competitions: competitions, rules: frozen.ruleset)
    }

    /// Motoren regner kombinasjonen (uten å se på runden). Én ball per lag krever i tillegg at runden
    /// spilles i lagformen (se `evaluate`).
    public static func supports(_ axes: FormAxes) -> Bool {
        switch axes.scoring {
        case .stableford, .strokePlay, .parBogey, .maximumScore: true
        case .skins, .pointsGame: axes.teamForm == .individual
        case .matchPlay: axes.teamForm != .pairs(.aggregate)
        }
    }

    static func evaluate(_ comp: RoundCompetition, round: Round, roster: [Player], rules: Ruleset) -> RoundCompetitionResult {
        let unsupported = RoundCompetitionResult(id: comp.id, supported: false, rows: [])
        guard supports(FormAxes(teamForm: comp.teamForm, scoring: comp.scoring)) else { return unsupported }
        let scored = FormPlay.scoredPlayers(round)

        switch comp.scoring {
        case .stableford, .strokePlay, .parBogey, .maximumScore:
            return holeByHole(comp, round: round, roster: roster, rules: rules, scored: scored) ?? unsupported

        case .matchPlay:
            return matchPlay(comp, round: round, roster: roster, rules: rules) ?? unsupported

        case .skins:
            guard comp.holes == nil else { return unsupported }
            let players = comp.entrants?.flatMap { $0 } ?? scored
            guard !players.isEmpty else { return RoundCompetitionResult(id: comp.id, supported: true, rows: []) }
            let setup = GameSetup(settings: .skins(rules.formPlay.skins), players: players)
            let game = Games.evaluate(setup, round: round, roster: roster, rules: rules)
            let done = game.holes.filter { $0.state != .pending }.count
            let rows = players.map { RoundCompetitionResult.Row(players: [$0], score: game.scores[$0] ?? 0, holes: done, rank: 0) }
            return ranked(comp.id, rows, higherIsBetter: true, byHoles: false)

        case .pointsGame(let kind):
            let groups = comp.entrants ?? [scored]
            var rows: [RoundCompetitionResult.Row] = []
            for group in groups where !group.isEmpty {
                let r = PointsGame.evaluate(kind, players: group, round: round, roster: roster, rules: rules,
                                            holes: comp.holes?.range)
                let done = r.holes.filter { $0.state == .scored }.count
                rows += group.map { .init(players: [$0], score: r.totals[$0] ?? 0, holes: done, rank: 0) }
            }
            return ranked(comp.id, rows, higherIsBetter: true, byHoles: false)
        }
    }

    /// Lagene i runden (lagnummer over 0), i lagnummerets rekkefølge, spillerne sortert på id. Bare lag
    /// der noen har score.
    static func roundTeams(_ round: Round) -> [[String]] {
        let numbers = Set(round.teams.values.filter { $0 != 0 }).sorted()
        return numbers.map { n in round.teams.filter { $0.value == n }.map(\.key).sorted() }
            .filter { team in team.contains { !(round.holeScores[$0] ?? [:]).isEmpty } }
    }

    /// Rundens lag (lagnummer over 0) når det er nøyaktig to, i lagnummerets rekkefølge, spillerne sortert
    /// på id. Ellers ingen.
    static func twoTeams(_ round: Round) -> [[String]] {
        let numbers = Set(round.teams.values.filter { $0 != 0 }).sorted()
        guard numbers.count == 2 else { return [] }
        return numbers.map { n in round.teams.filter { $0.value == n }.map(\.key).sorted() }
    }

    /// Stableford, slagspill, par/bogey og maksimumscore hull for hull. `nil` når én ball per lag ikke kan regnes
    /// (runden spilles ikke i lagformen, eller et lag er ikke ett av rundens lag).
    static func holeByHole(_ comp: RoundCompetition, round: Round, roster: [Player], rules: Ruleset,
                           scored: [String]) -> RoundCompetitionResult? {
        let oneBall = comp.teamForm.playsOneBall
        let entrants: [[String]]
        if oneBall {
            guard round.form.axes.teamForm == comp.teamForm else { return nil }
            entrants = comp.entrants ?? roundTeams(round)
            for team in entrants {
                let numbers = Set(team.map { round.teams[$0] ?? 0 })
                guard numbers.count == 1, numbers.first != 0 else { return nil }
            }
        } else {
            entrants = comp.entrants ?? scored.map { [$0] }
        }

        let net: Bool
        switch comp.scoring {
        case .stableford(let n), .strokePlay(let n), .maximumScore(let n, _): net = n
        default: net = true
        }
        let ctx = GameContext(setup: GameSetup(settings: .skins(.standard), players: entrants.flatMap { $0 }), round: round,
                              roster: roster, rules: rules)
        let hcp = ctx.handicaps(GameHandicap(net: net, allowance: comp.allowance ?? 1, fromLowest: false))
        let parBogey = rules.formPlay.parBogey
        // Maksimumscore: taket, og slagene fått som taket regnes med (konkurransens andel, også i brutto).
        var cap: Ruleset.MaxStrokes?
        var capHandicaps: [String: Int] = [:]
        if case .maximumScore(_, let own) = comp.scoring {
            cap = own ?? rules.formPlay.maximumScore
            capHandicaps = ctx.handicaps(GameHandicap(net: true, allowance: comp.allowance ?? 1, fromLowest: false))
        }

        var rows: [RoundCompetitionResult.Row] = []
        for team in entrants {
            var total = 0.0, holes = 0
            var perHole: [Int: Double] = [:]
            for h in 0..<ctx.count where comp.holes?.range.contains(h) ?? true {
                let par = ctx.holes[h].par
                // Én ball: lagets score er den første på laget (id-rekkefølge) som har ført hullet.
                let balls: [String] = oneBall ? [team.sorted().first { ctx.gross($0, h) != nil } ?? team.sorted()[0]] : team
                let nets = balls.map { ctx.net($0, h, handicaps: hcp) }
                let values: [Double]
                switch comp.scoring {
                case .stableford:
                    values = nets.compactMap { $0 }.map { Double(max(rules.scoring.minimumPoints, par - $0 + rules.scoring.netParPoints)) }
                case .parBogey:
                    // Regel 21.3b: uten score er hullet tapt, men først når runden er ferdig.
                    values = ctx.isFinal
                        ? nets.map { ParBogey.holeValue(net: $0, par: par, rules: parBogey) }
                        : nets.compactMap { $0 }.map { ParBogey.holeValue(net: $0, par: par, rules: parBogey) }
                case .maximumScore:
                    values = balls.compactMap { p in
                        guard let gross = ctx.gross(p, h) else { return nil }
                        let limit = cap?.limit(par: par, strokesReceived: ctx.strokes(p, h, handicaps: capHandicaps))
                        return Double(min(gross, limit ?? gross) - ctx.strokes(p, h, handicaps: hcp))
                    }
                default:
                    values = nets.compactMap { $0 }.map(Double.init)
                }
                guard !values.isEmpty else { continue }
                holes += 1
                let value = switch comp.teamForm {
                case .pairs(.aggregate): values.reduce(0, +)
                default: (comp.scoring.higherIsBetter ? values.max() : values.min())!
                }
                total += value
                perHole[h] = value
            }
            rows.append(.init(players: team, score: total, holes: holes, rank: 0, holeValues: perHole))
        }
        let higher = comp.scoring.higherIsBetter
        return ranked(comp.id, rows, higherIsBetter: higher, byHoles: !higher)
    }

    /// Match mellom to sider (`entrants`: to lister, én spiller eller flere med beste ball) med
    /// `MatchPlay`: handicapet er spillehandicapet i runden, med konkurransens andel (rundet som JS) når den
    /// er satt, og slagene som i rundens matcher (`formats.matchStrokes`). Hullene tas i rundens rekkefølge,
    /// og matchen stopper når en side er flere hull opp enn det er igjen. Uten to sider: ingen rader.
    ///
    /// Én ball per lag: sidene er to av rundens lag (uten `entrants`: rundens to lag), og runden må spilles
    /// i lagformen. Hullet tar lagets ene score (første på laget i id-rekkefølge som har ført, som
    /// `holeByHole`), og handicapet er lagets (spillehandicapet i runden er lagshandicapet,
    /// `handicap.teamHandicap`). `nil` når én ball ikke kan regnes.
    static func matchPlay(_ comp: RoundCompetition, round: Round, roster: [Player], rules: Ruleset) -> RoundCompetitionResult? {
        let oneBall = comp.teamForm.playsOneBall
        if oneBall, round.form.axes.teamForm != comp.teamForm { return nil }
        let sides = (comp.entrants ?? (oneBall ? twoTeams(round) : [])).filter { !$0.isEmpty }
        guard sides.count == 2, Set(sides[0]).isDisjoint(with: sides[1]) else {
            return RoundCompetitionResult(id: comp.id, supported: true, rows: [])
        }
        if oneBall {
            for team in sides {
                let numbers = Set(team.map { round.teams[$0] ?? 0 })
                guard numbers.count == 1, numbers.first != 0 else { return nil }
            }
        }
        let (a, b) = (sides[0], sides[1])
        var handicaps: [String: Double] = [:]
        for p in a + b {
            // Som `GameContext.handicaps`: uten troppen (øyeblikksbildet) er det frosne handicapet spillerens.
            let own = Handicap.effective(for: roster.first { $0.id == p } ?? Player(id: p), in: round,
                                         roster: roster, rules: rules)
            handicaps[p] = comp.allowance.map { JS.round(own * $0) } ?? own
        }
        let handicap: (String) -> Double = { handicaps[$0] ?? 0 }
        let offset = MatchPlay.strokeOffset(a: a, b: b, rules: rules, handicap: handicap)
        let count = min(Truncation.countingHoles(round), round.courseHoles().count)
        let holes = (0..<count).filter { comp.holes?.range.contains($0) ?? true }

        var up = 0, played = 0
        var perHole: [Int: Double] = [:]
        for h in holes {
            if played > 0, abs(up) > holes.count - played { break }
            // Én ball: lagets score er den første på laget (id-rekkefølge) som har ført hullet.
            func ball(_ side: [String]) -> [String] {
                guard oneBall else { return side }
                let order = side.sorted()
                return [order.first { round.holeScores[$0]?[h] != nil } ?? order[0]]
            }
            guard let v = MatchPlay.holeWinner(a: ball(a), b: ball(b), hole: h, offset: offset, in: round,
                                               handicap: handicap) else { continue }
            played += 1
            up += v
            perHole[h] = Double(v)
        }
        let remaining = holes.count - played
        func standing(_ mine: Int, _ opponents: [String]) -> MatchStanding {
            MatchStanding(up: mine, played: played, remaining: remaining,
                          decided: abs(mine) > remaining && played > 0, opponents: opponents)
        }
        let rows = [
            RoundCompetitionResult.Row(players: a, score: Double(up), holes: played, rank: 0, holeValues: perHole,
                                       match: standing(up, b)),
            RoundCompetitionResult.Row(players: b, score: Double(-up), holes: played, rank: 0,
                                       holeValues: perHole.mapValues { 0 - $0 }, match: standing(-up, a)),
        ]
        return ranked(comp.id, rows, higherIsBetter: true, byHoles: false)
    }

    /// Sorterer og gir plass. Med `byHoles` står de med flest hull først (slagspill).
    static func ranked(_ id: String, _ rows: [RoundCompetitionResult.Row], higherIsBetter: Bool,
                       byHoles: Bool) -> RoundCompetitionResult {
        func better(_ a: RoundCompetitionResult.Row, _ b: RoundCompetitionResult.Row) -> Bool? {
            if byHoles, a.holes != b.holes { return a.holes > b.holes }
            if a.score != b.score { return higherIsBetter ? a.score > b.score : a.score < b.score }
            return nil
        }
        var sorted = rows.sorted { a, b in
            better(a, b) ?? (a.players.joined(separator: ",") < b.players.joined(separator: ","))
        }
        for i in sorted.indices {
            sorted[i].rank = i > 0 && better(sorted[i - 1], sorted[i]) == nil ? sorted[i - 1].rank : i + 1
        }
        return RoundCompetitionResult(id: id, supported: true, rows: sorted)
    }
}

// MARK: - Øyeblikksbildet ved start

/// Regelsett, hull og spillehandicap frosset da runden startet. Lagres ved start (steg 7, sql 048), og
/// resultatene regnes fra det, så endringer i regelsettet, banen eller handicapet etterpå ikke endrer
/// en runde som er spilt.
public struct FrozenRound: Codable, Hashable, Sendable {
    /// Regelsettet slik det var ved start.
    public var ruleset: Ruleset
    /// Hullene slik de spilles (`Round.courseHoles()` ved start).
    public var holes: [PlayedHole]
    /// Spillehandicapet per spiller ved start (`Handicap.effective`).
    public var playingHandicaps: [String: Double]
    /// Formen (`Round.gameType`) og lagene ved start.
    public var gameType: String?
    public var teams: [String: Int]

    public init(ruleset: Ruleset, holes: [PlayedHole], playingHandicaps: [String: Double], gameType: String?,
                teams: [String: Int]) {
        self.ruleset = ruleset
        self.holes = holes
        self.playingHandicaps = playingHandicaps
        self.gameType = gameType
        self.teams = teams
    }

    /// Øyeblikksbildet når runden starter: regelsettet, rundens hull og spillehandicapet til hver i
    /// troppen (de som er med). Ren funksjon; lagringen gjør appen.
    public static func start(_ round: Round, roster: [Player], ruleset: Ruleset) -> FrozenRound {
        var handicaps: [String: Double] = [:]
        for p in roster { handicaps[p.id] = Handicap.effective(for: p, in: round, roster: roster, rules: ruleset) }
        return FrozenRound(ruleset: ruleset, holes: round.courseHoles(), playingHandicaps: handicaps,
                           gameType: round.gameType, teams: round.teams)
    }

    /// Runden bygd fra øyeblikksbildet og scorene. Hullene står som en bane med kortindeksen, så
    /// `courseHoles()` gir de samme hullene (også for 9 hull fra hull 10).
    public func round(scores: [String: HoleScores], locked: Bool = true) -> Round {
        let course = Course(holes: holes.map { CourseHole(par: $0.par, si: $0.cardIndex, meters: $0.meters) })
        return Round(gameType: gameType, holeCount: holes.count, holeStart: nil, course: course, hcpAllowance: 1,
                     teams: teams, holeScores: scores, locked: locked, playingHandicaps: playingHandicaps)
    }
}
