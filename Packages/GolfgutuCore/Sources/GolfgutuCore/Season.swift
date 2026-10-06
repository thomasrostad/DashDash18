import Foundation

/// Sesongen: tabellen (jakketavla), stablefordsummen og kveldene (db-nytt.js linje 380–775,
/// 1052–1095 og 2307–2342), styrt av regelsettet.
///
/// Med `Ruleset.golfgutu` gir alt samme svar som PWA-en. Rundens poeng regnes fra scorene
/// (`Scoring.roundPoints`), ikke fra en lagret tabell.
public struct Season: Sendable {
    /// Troppen (`STATE.players`). Alle står i tabellen, også de som ikke har spilt.
    public let players: [Player]
    /// Sesongens runder, i lagret rekkefølge.
    public let rounds: [Round]
    /// Innmeldinger til longest drive og nærmest pinnen.
    public let claims: [SideClaim]
    public let ruleset: Ruleset
    /// `round_points` per runde, regnet én gang.
    private let pointsByRound: [[String: Int]]

    public init(players: [Player], rounds: [Round], claims: [SideClaim] = [], ruleset: Ruleset = .golfgutu) {
        self.players = players
        self.rounds = rounds
        self.claims = claims
        self.ruleset = ruleset
        pointsByRound = rounds.map { Scoring.roundPoints($0, roster: players, groups: ruleset.seedingGroups) }
    }

    // MARK: Typer

    /// Én match for én spiller, vektet med runden.
    public struct MatchResult: Hashable, Sendable {
        /// Indeksen i `rounds`.
        public var roundIndex: Int
        public var roundID: String?
        public var matchNo: Int?
        public var points: Double
        /// Hulldifferansen. 0 for trekant og manuelt resultat.
        public var holes: Int
        public var isTriangle: Bool
    }

    /// Matchene som teller, og de som er strøket (`{ teller, stroket }`).
    public struct MatchSelection: Hashable, Sendable {
        public var counting: [MatchResult]
        public var dropped: [MatchResult]
    }

    /// `matchSum`.
    public struct MatchSum: Hashable, Sendable {
        /// Til nærmeste halve.
        public var points: Double
        public var holes: Int
        public var matches: Int
    }

    /// Én sidepremie vunnet (helt eller delt), vektet med runden.
    public struct SidePrizeResult: Hashable, Sendable {
        public var roundIndex: Int
        public var roundID: String?
        public var kind: SideClaim.Kind
        public var shared: Bool
        public var points: Double
    }

    /// Én runde i stablefordsummen, vektet.
    public struct RoundScore: Hashable, Sendable {
        public var roundIndex: Int
        public var roundID: String?
        public var points: Double
    }

    /// Rundene som teller i stablefordsummen, og de som er strøket.
    public struct RoundSelection: Hashable, Sendable {
        public var counting: [RoundScore]
        public var dropped: [RoundScore]
    }

    /// En rad i jakketavla.
    public struct JacketRow: Hashable, Sendable {
        public var player: Player
        /// Duell + sidepremier, til nærmeste halve.
        public var total: Double
        public var duel: Double
        public var side: Double
        /// Tellende matcher.
        public var matches: Int
        public var holes: Int
        /// Spilte matcher, også strøkne.
        public var played: Int
        /// Stablefordsummen (skilletegn).
        public var stableford: Int
    }

    /// En rad i stablefordtavla (`seasonBoardNytt`).
    public struct StablefordRow: Hashable, Sendable {
        public var player: Player
        public var total: Int
        public var played: Int
        public var counting: Int
        public var dropped: Int
    }

    // MARK: Matcher

    /// `matchResultaterFor`: spillerens matcher gjennom sesongen, vektet med runden. Vekt 0 hopper over
    /// hele runden. Trekant gir plasspoeng og 0 i hulldifferanse; manuelt resultat gir 0 i hulldifferanse.
    /// Sortert på poeng, så hulldifferanse; regelsettets «beste N» stryker resten.
    public func matchResults(for playerID: String) -> MatchSelection {
        var all: [MatchResult] = []
        let groups = ruleset.seedingGroups
        for (i, round) in rounds.enumerated() {
            let weight = Self.weight(round)
            if weight == 0 { continue }
            for m in round.matches where MatchPlay.involves(m, playerID: playerID, in: round) {
                if m.isTriangle {
                    guard let tp = Triangle.points(m, in: round, roster: players, groups: groups,
                                                   placePoints: ruleset.trianglePoints)?[playerID] else { continue }
                    all.append(MatchResult(roundIndex: i, roundID: round.id, matchNo: m.matchNo,
                                           points: tp * weight, holes: 0, isTriangle: true))
                    continue
                }
                guard let toA = MatchPlay.outcomeForA(m, in: round, roster: players, groups: groups) else { continue }
                let onA = MatchPlay.sides(of: m, in: round).a.contains(playerID)
                let mine = onA ? toA : 1 - toA
                let st = m.result == nil ? MatchPlay.standing(m, from: playerID, in: round, roster: players, groups: groups) : nil
                let holes = (st.map { $0.played > 0 } ?? false) ? st!.up : 0
                all.append(MatchResult(roundIndex: i, roundID: round.id, matchNo: m.matchNo,
                                       points: MatchPlay.points(forOutcome: mine, ruleset.matchPoints) * weight,
                                       holes: holes, isTriangle: false))
            }
        }
        all = all.enumerated().sorted { x, y in
            if x.element.points != y.element.points { return x.element.points > y.element.points }
            if x.element.holes != y.element.holes { return x.element.holes > y.element.holes }
            return x.offset < y.offset
        }.map(\.element)
        guard let n = ruleset.countingEvenings, n > 0 else { return MatchSelection(counting: all, dropped: []) }
        return MatchSelection(counting: Array(all.prefix(n)), dropped: Array(all.dropFirst(n)))
    }

    /// `matchSum`: poengene til nærmeste halve, hulldifferansen og antall matcher.
    public static func matchSum(_ results: [MatchResult]) -> MatchSum {
        MatchSum(points: JS.roundHalf(results.reduce(0) { $0 + $1.points }),
                 holes: results.reduce(0) { $0 + $1.holes },
                 matches: results.count)
    }

    /// `matchPoengFor` / `matchHullFor`: summen av de tellende matchene.
    public func matchTotals(for playerID: String) -> MatchSum {
        Self.matchSum(matchResults(for: playerID).counting)
    }

    // MARK: Sidepremier

    /// `sidepremieResultaterFor`: premiene spilleren har vunnet, vektet med runden. Lik lengde deler.
    /// Vekt 0 hopper over runden. Av i regelsettet: ingen.
    public func sidePrizeResults(for playerID: String) -> [SidePrizeResult] {
        guard ruleset.sidePrizes.enabled else { return [] }
        var out: [SidePrizeResult] = []
        for (i, round) in rounds.enumerated() {
            let weight = Self.weight(round)
            if weight == 0 { continue }
            for kind in [SideClaim.Kind.drive, .kp] {
                let winners = SidePrizes.winners(SidePrizes.claims(kind, in: round, claims: claims))
                guard winners.contains(playerID) else { continue }
                out.append(SidePrizeResult(roundIndex: i, roundID: round.id, kind: kind, shared: winners.count > 1,
                                           points: (ruleset.sidePrizes.points / Double(winners.count)) * weight))
            }
        }
        return out
    }

    /// `sidepremiePoengFor`.
    public func sidePrizePoints(for playerID: String) -> Double {
        sidePrizeResults(for: playerID).reduce(0) { $0 + $1.points }
    }

    // MARK: Stablefordsummen

    /// Rundens poeng (`round.points`), regnet fra scorene.
    public func roundPoints(_ roundIndex: Int) -> [String: Int] {
        pointsByRound[roundIndex]
    }

    /// `rundePoengVektet`: rundens poeng ganget med vekten. `nil` når spilleren ikke har poeng i runden.
    public func weightedRoundPoints(_ roundIndex: Int, playerID: String) -> Double? {
        guard let p = pointsByRound[roundIndex][playerID] else { return nil }
        return Double(p) * Self.weight(rounds[roundIndex])
    }

    /// `tellendeRunderFor`: rundene som teller i stablefordsummen, best først (vekten legges på før
    /// utvelgelsen).
    public func countingRounds(for playerID: String) -> RoundSelection {
        let all = rounds.indices.compactMap { i in
            weightedRoundPoints(i, playerID: playerID).map { RoundScore(roundIndex: i, roundID: rounds[i].id, points: $0) }
        }.enumerated().sorted { x, y in
            x.element.points != y.element.points ? x.element.points > y.element.points : x.offset < y.offset
        }.map(\.element)
        guard let n = ruleset.stablefordCountingEvenings else { return RoundSelection(counting: all, dropped: []) }
        return RoundSelection(counting: Array(all.prefix(n)), dropped: Array(all.dropFirst(n)))
    }

    /// `seasonTotalNytt`: summen av de tellende rundene, avrundet som JS.
    public func stablefordTotal(for playerID: String) -> Int {
        JS.roundInt(countingRounds(for: playerID).counting.reduce(0) { $0 + $1.points })
    }

    // MARK: Tabellene

    /// `jakketavle`: duellpoeng pluss sidepremier, alle i troppen. Sortert på total, så regelsettets
    /// skilletegn (Golfgutu: hulldifferanse, stablefordsum), så navn (norsk).
    public func jacketBoard() -> [JacketRow] {
        let rows = players.map { p -> JacketRow in
            let d = matchResults(for: p.id)
            let s = Self.matchSum(d.counting)
            let side = sidePrizePoints(for: p.id)
            return JacketRow(player: p, total: JS.roundHalf(s.points + side), duel: s.points, side: side,
                             matches: s.matches, holes: s.holes, played: d.counting.count + d.dropped.count,
                             stableford: stablefordTotal(for: p.id))
        }
        return rows.sorted { a, b in
            if a.total != b.total { return a.total > b.total }
            for t in ruleset.tiebreaks {
                switch t {
                case .holeDifference where a.holes != b.holes: return a.holes > b.holes
                case .stableford where a.stableford != b.stableford: return a.stableford > b.stableford
                default: continue
                }
            }
            return NorwegianSort.areInIncreasingOrder(a.player.name, b.player.name)
        }
    }

    /// `seasonBoardNytt`: stablefordsummen, alle i troppen. Sortert på sum, så navn (norsk).
    public func stablefordBoard() -> [StablefordRow] {
        players.map { p -> StablefordRow in
            let d = countingRounds(for: p.id)
            return StablefordRow(player: p, total: stablefordTotal(for: p.id), played: d.counting.count + d.dropped.count,
                                 counting: d.counting.count, dropped: d.dropped.count)
        }.sorted { a, b in
            a.total != b.total ? a.total > b.total : NorwegianSort.areInIncreasingOrder(a.player.name, b.player.name)
        }
    }

    /// `trekkMatcher` med stillingen fra tabellen (`matchPoengFor`).
    public func drawMatches(_ participants: [Player], round: Int) -> [[String]] {
        var standing: [String: Double] = [:]
        for p in participants { standing[p.id] = matchTotals(for: p.id).points }
        return Triangle.drawMatches(participants, round: round, standing: standing)
    }

    // MARK: Kvelder

    /// `kveldsDatoer`: kveldene, sortert. To runder samme dato er én kveld; en runde uten dato er sin egen.
    public static func eveningDates(_ rounds: [Round]) -> [String] {
        Array(Set(rounds.map { $0.date.flatMap { $0.isEmpty ? nil : $0 } ?? "uten dato " + ($0.id ?? "undefined") })).sorted()
    }

    /// `antallKvelder`.
    public static func eveningCount(_ rounds: [Round]) -> Int {
        eveningDates(rounds).count
    }

    /// `rundeNummerFor`: kveldens nummer for en dato. En ny dato får plassen sin i rekkefølgen;
    /// uten dato: neste ledige.
    public func roundNumber(for date: String?) -> Int {
        var dates = Self.eveningDates(rounds)
        guard let date, !date.isEmpty else { return dates.count + 1 }
        if !dates.contains(date) {
            dates.append(date)
            dates.sort()
        }
        return (dates.firstIndex(of: date) ?? dates.count) + 1
    }

    /// `kveldErFerdig`: kvelden har runder, og alle er låst.
    public func isEveningFinished(_ date: String) -> Bool {
        let evening = rounds.filter { $0.date == date }
        return !evening.isEmpty && evening.allSatisfy(\.locked)
    }

    // MARK: Hjelpere

    /// `fmtPoeng`: til nærmeste halve, desimalkomma. «4», ikke «4,0».
    public static func formatPoints(_ x: Double) -> String {
        JS.norwegianString(JS.roundHalf(x.isNaN ? 0 : x))
    }

    /// Rundevekten. NaN regnes som 0 (`if(!vekt)` i JS).
    static func weight(_ round: Round) -> Double {
        round.weight.isNaN ? 0 : round.weight
    }
}
