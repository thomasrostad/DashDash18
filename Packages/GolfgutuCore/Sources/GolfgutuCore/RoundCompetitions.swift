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
    /// - stableford (netto eller brutto) og slagspill, individuelt, fourball og lag (beste ball per hull)
    ///   og sammenlagt (summen per hull). Hull uten score gir ingenting. I slagspill står de med flest
    ///   hull først, så lavest sum;
    /// - skins (individuelt, alle hull): rundespillet med `formPlay.skins`;
    /// - Amerikaner og Københavner (individuelt): `PointsGame` per gruppe.
    /// Ikke ennå (`supported == false`): én ball per lag (foursome, greensome, chapman, scramble),
    /// par/bogey, maksimumscore og matchspill (matchene regnes av `MatchPlay`).
    public static func evaluate(_ round: Round, roster: [Player], competitions: [RoundCompetition],
                                rules: Ruleset) -> [RoundCompetitionResult] {
        competitions.map { evaluate($0, round: round, roster: roster, rules: rules) }
    }

    /// Konkurransene fra øyeblikksbildet: regelsett, hull og handicap slik de var ved start.
    public static func evaluate(_ frozen: FrozenRound, scores: [String: HoleScores], locked: Bool = true,
                                competitions: [RoundCompetition]) -> [RoundCompetitionResult] {
        evaluate(frozen.round(scores: scores, locked: locked), roster: [], competitions: competitions, rules: frozen.ruleset)
    }

    static func evaluate(_ comp: RoundCompetition, round: Round, roster: [Player], rules: Ruleset) -> RoundCompetitionResult {
        let unsupported = RoundCompetitionResult(id: comp.id, supported: false, rows: [])
        if comp.teamForm.playsOneBall { return unsupported }
        let scored = FormPlay.scoredPlayers(round)

        switch comp.scoring {
        case .stableford(let net), .strokePlay(let net):
            let stableford: Bool = if case .stableford = comp.scoring { true } else { false }
            let entrants = comp.entrants ?? scored.map { [$0] }
            let all = entrants.flatMap { $0 }
            let ctx = GameContext(setup: GameSetup(settings: .skins(.standard), players: all), round: round,
                                  roster: roster, rules: rules)
            let hcp = ctx.handicaps(GameHandicap(net: net, allowance: comp.allowance ?? 1, fromLowest: false))
            var rows: [RoundCompetitionResult.Row] = []
            for team in entrants {
                var total = 0, holes = 0
                for h in 0..<ctx.count where comp.holes?.range.contains(h) ?? true {
                    let values: [Int] = team.compactMap { p in
                        guard let n = ctx.net(p, h, handicaps: hcp) else { return nil }
                        return stableford ? max(rules.scoring.minimumPoints, ctx.holes[h].par - n + rules.scoring.netParPoints) : n
                    }
                    guard !values.isEmpty else { continue }
                    holes += 1
                    switch comp.teamForm {
                    case .pairs(.aggregate): total += values.reduce(0, +)
                    default: total += (stableford ? values.max() : values.min())!
                    }
                }
                rows.append(.init(players: team, score: Double(total), holes: holes, rank: 0))
            }
            return ranked(comp.id, rows, higherIsBetter: stableford, byHoles: !stableford)

        case .skins:
            guard comp.teamForm == .individual, comp.holes == nil else { return unsupported }
            let players = comp.entrants?.flatMap { $0 } ?? scored
            guard !players.isEmpty else { return RoundCompetitionResult(id: comp.id, supported: true, rows: []) }
            let setup = GameSetup(settings: .skins(rules.formPlay.skins), players: players)
            let game = Games.evaluate(setup, round: round, roster: roster, rules: rules)
            let done = game.holes.filter { $0.state != .pending }.count
            let rows = players.map { RoundCompetitionResult.Row(players: [$0], score: game.scores[$0] ?? 0, holes: done, rank: 0) }
            return ranked(comp.id, rows, higherIsBetter: true, byHoles: false)

        case .pointsGame(let kind):
            guard comp.teamForm == .individual else { return unsupported }
            let groups = comp.entrants ?? [scored]
            var rows: [RoundCompetitionResult.Row] = []
            for group in groups where !group.isEmpty {
                let r = PointsGame.evaluate(kind, players: group, round: round, roster: roster, rules: rules,
                                            holes: comp.holes?.range)
                let done = r.holes.filter { $0.state == .scored }.count
                rows += group.map { .init(players: [$0], score: r.totals[$0] ?? 0, holes: done, rank: 0) }
            }
            return ranked(comp.id, rows, higherIsBetter: true, byHoles: false)

        case .parBogey, .maximumScore, .matchPlay:
            return unsupported
        }
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
