import Foundation

/// Lag mot lag (Ryder Cup) som oppskrift: to sider, flere matcher per kveld (singel, fourball eller
/// foursome), poeng til siden per match vunnet eller delt (`formPlay.teamMatch`) og en lagtabell.
///
/// Matchene er rundens vanlige matcher (`Round.matches`) og regnes med matchspillet (`MatchPlay`):
/// singel er spiller mot spiller, fourball og foursome er lag mot lag (rundens lag, `Round.teams`).
/// I foursome fører laget én ball på kortet til én av spillerne, og beste netto på siden er da den
/// ballen. Hvilken side en spiller er på, står i `sides` (spiller-id → 1 eller 2). En match der
/// spillerne ikke hører til hver sin side, teller ikke (`invalid`). Runder som ikke teller
/// (`counts == false` eller vekt 0) hoppes over. Poengene vektes ikke.
public enum RyderCup {
    /// Én match sett fra lagkonkurransen.
    public struct MatchResult: Hashable, Sendable {
        public enum State: String, Codable, Hashable, Sendable {
            /// Ingen hull spilt ennå.
            case pending
            /// Utfallet er satt (eller stillingen nå, før runden er låst).
            case decided
            /// Spillerne hører ikke til hver sin side.
            case invalid
        }

        /// Indeksen i `rounds`.
        public var roundIndex: Int
        public var roundID: String?
        public var matchNo: Int?
        /// Sidene til matchens A og B (1 eller 2). `nil` når matchen ikke teller.
        public var sideA: Int?
        public var sideB: Int?
        public var state: State
        /// Utfallet for A: 1 seier, 0,5 delt, 0 tap (`MatchPlay.outcomeForA`).
        public var outcomeA: Double?
        /// Lagpoengene til A og B sin side.
        public var pointsA: Double
        public var pointsB: Double
    }

    /// Én side i lagtabellen.
    public struct Row: Hashable, Sendable {
        public var side: Int
        public var points: Double
        public var won: Int
        public var halved: Int
        public var lost: Int
    }

    public struct Result: Hashable, Sendable {
        public var matches: [MatchResult]
        /// Sidene, flest poeng først (så lavest sidenummer).
        public var table: [Row]
    }

    /// Lagkonkurransen over rundene.
    public static func evaluate(rounds: [Round], sides: [String: Int], roster: [Player],
                                rules: Ruleset) -> Result {
        let points = rules.formPlay.teamMatch
        // `MatchPlay` slår opp spilleren i troppen for å finne det frosne handicapet; de som mangler, legges til.
        let known = Set(roster.map(\.id))
        let missing = Set(rounds.flatMap { r in r.matches.flatMap { MatchPlay.sides(of: $0, in: r).all } })
            .subtracting(known).sorted().map { Player(id: $0) }
        let roster = roster + missing
        var matches: [MatchResult] = []
        var rows: [Int: Row] = [:]
        for side in Set(sides.values).sorted() { rows[side] = Row(side: side, points: 0, won: 0, halved: 0, lost: 0) }

        for (i, round) in rounds.enumerated() where round.counts && round.weight != 0 {
            for m in round.matches where !m.isTriangle {
                let s = MatchPlay.sides(of: m, in: round)
                let aSides = Set(s.a.map { sides[$0] })
                let bSides = Set(s.b.map { sides[$0] })
                guard aSides.count == 1, bSides.count == 1, let sa = aSides.first!, let sb = bSides.first!, sa != sb else {
                    matches.append(MatchResult(roundIndex: i, roundID: round.id, matchNo: m.matchNo, sideA: nil, sideB: nil,
                                               state: .invalid, outcomeA: nil, pointsA: 0, pointsB: 0))
                    continue
                }
                guard let outcome = MatchPlay.outcomeForA(m, in: round, roster: roster, rules: rules) else {
                    matches.append(MatchResult(roundIndex: i, roundID: round.id, matchNo: m.matchNo, sideA: sa, sideB: sb,
                                               state: .pending, outcomeA: nil, pointsA: 0, pointsB: 0))
                    continue
                }
                let pa = MatchPlay.points(forOutcome: outcome, points)
                let pb = MatchPlay.points(forOutcome: 1 - outcome, points)
                matches.append(MatchResult(roundIndex: i, roundID: round.id, matchNo: m.matchNo, sideA: sa, sideB: sb,
                                           state: .decided, outcomeA: outcome, pointsA: pa, pointsB: pb))
                for (side, mine, p) in [(sa, outcome, pa), (sb, 1 - outcome, pb)] {
                    var row = rows[side] ?? Row(side: side, points: 0, won: 0, halved: 0, lost: 0)
                    row.points += p
                    if mine == 1 { row.won += 1 } else if mine == 0 { row.lost += 1 } else { row.halved += 1 }
                    rows[side] = row
                }
            }
        }
        let table = rows.values.sorted { $0.points != $1.points ? $0.points > $1.points : $0.side < $1.side }
        return Result(matches: matches, table: table)
    }

    /// Lag mot lag for en fourball- eller foursome-kveld: side 1 sine lag mot side 2 sine, i
    /// lagnummerets rekkefølge (første mot første), som `MatchPlanner.teamMatches` i appen parer 1 mot 2.
    /// Et lag hører til siden til spilleren med lavest id. Lag til overs får ingen match.
    public static func pairings(teams: [String: Int], sides: [String: Int]) -> [Match] {
        let numbers = Set(teams.values).sorted()
        func side(of team: Int) -> Int? {
            teams.filter { $0.value == team }.map(\.key).sorted().first.flatMap { sides[$0] }
        }
        let one = numbers.filter { side(of: $0) == 1 }
        let two = numbers.filter { side(of: $0) == 2 }
        return zip(one, two).map { Match(teamA: $0, teamB: $1) }
    }

    /// Singler: første mot første, andre mot andre, nummerert fra 1.
    public static func singles(_ a: [String], _ b: [String]) -> [Match] {
        zip(a, b).enumerated().map { Match(matchNo: $0.offset + 1, playerA: $0.element.0, playerB: $0.element.1) }
    }
}
