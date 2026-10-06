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
        pointsByRound = rounds.map { Scoring.roundPoints($0, roster: players, rules: ruleset) }
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

    /// Sidepremiene som teller, og de som er strøket.
    public struct SidePrizeSelection: Hashable, Sendable {
        public var counting: [SidePrizeResult]
        public var dropped: [SidePrizeResult]
    }

    /// Det som teller i tabellen: matcher og sidepremier.
    public struct TableSelection: Hashable, Sendable {
        public var matches: MatchSelection
        public var sidePrizes: SidePrizeSelection
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
        /// Duell + sidepremier, avrundet etter regelsettet (Golfgutu: nærmeste halve).
        public var total: Double
        public var duel: Double
        /// Tellende sidepremier.
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
    /// Sortert på poeng, så hulldifferanse; regelsettets «beste N» (`table.counting`) stryker resten.
    public func matchResults(for playerID: String) -> MatchSelection {
        tableSelection(for: playerID).matches
    }

    /// Det som teller i tabellen for spilleren, etter `table.counting`:
    /// - `match` (Golfgutu, `TELLENDE_MATCHER`): de N beste matchene. Sidepremiene strykes aldri.
    /// - `evening` / `round`: spillerens tabellpoeng (matcher og sidepremier) summeres per kveld
    ///   (rundene med samme dato) eller per runde, og de N beste teller. Likt avgjøres av
    ///   hulldifferansen, så den tidligste.
    /// `best` `nil` (eller under 1): alt teller.
    public func tableSelection(for playerID: String) -> TableSelection {
        let chronological = matchResultsInOrder(for: playerID)
        let all = chronological.enumerated().sorted { x, y in
            if x.element.points != y.element.points { return x.element.points > y.element.points }
            if x.element.holes != y.element.holes { return x.element.holes > y.element.holes }
            return x.offset < y.offset
        }.map(\.element)
        let side = sidePrizeResults(for: playerID)
        let counting = ruleset.table.counting
        guard let n = counting.best, n > 0 else {
            return TableSelection(matches: MatchSelection(counting: all, dropped: []),
                                  sidePrizes: SidePrizeSelection(counting: side, dropped: []))
        }
        if counting.unit == .match {
            return TableSelection(matches: MatchSelection(counting: Array(all.prefix(n)), dropped: Array(all.dropFirst(n))),
                                  sidePrizes: SidePrizeSelection(counting: side, dropped: []))
        }
        let items = chronological.map { (key: groupKey($0.roundIndex, counting.unit), round: $0.roundIndex, points: $0.points, holes: $0.holes) }
            + side.map { (key: groupKey($0.roundIndex, counting.unit), round: $0.roundIndex, points: $0.points, holes: 0) }
        let keep = Self.bestGroups(items, best: n)
        let inMatches = all.map { keep.contains(groupKey($0.roundIndex, counting.unit)) }
        let inSide = side.map { keep.contains(groupKey($0.roundIndex, counting.unit)) }
        return TableSelection(
            matches: MatchSelection(counting: zip(all, inMatches).filter(\.1).map(\.0),
                                    dropped: zip(all, inMatches).filter { !$0.1 }.map(\.0)),
            sidePrizes: SidePrizeSelection(counting: zip(side, inSide).filter(\.1).map(\.0),
                                           dropped: zip(side, inSide).filter { !$0.1 }.map(\.0)))
    }

    /// Matchene i rundenes rekkefølge, før sortering og utvalg.
    private func matchResultsInOrder(for playerID: String) -> [MatchResult] {
        var all: [MatchResult] = []
        for (i, round) in rounds.enumerated() {
            let weight = Self.weight(round)
            if weight == 0 { continue }
            for m in round.matches where MatchPlay.involves(m, playerID: playerID, in: round) {
                if m.isTriangle {
                    guard let tp = Triangle.points(m, in: round, roster: players, rules: ruleset)?[playerID] else { continue }
                    all.append(MatchResult(roundIndex: i, roundID: round.id, matchNo: m.matchNo,
                                           points: tp * weight, holes: 0, isTriangle: true))
                    continue
                }
                guard let toA = MatchPlay.outcomeForA(m, in: round, roster: players, rules: ruleset) else { continue }
                let onA = MatchPlay.sides(of: m, in: round).a.contains(playerID)
                let mine = onA ? toA : 1 - toA
                let st = m.result == nil ? MatchPlay.standing(m, from: playerID, in: round, roster: players, rules: ruleset) : nil
                let holes = (st.map { $0.played > 0 } ?? false) ? st!.up : 0
                all.append(MatchResult(roundIndex: i, roundID: round.id, matchNo: m.matchNo,
                                       points: MatchPlay.points(forOutcome: mine, ruleset.table.matchPoints) * weight,
                                       holes: holes, isTriangle: false))
            }
        }
        return all
    }

    /// Nøkkelen en runde telles under: kvelden (`kveldsDatoer`-nøkkelen) eller runden selv.
    func groupKey(_ roundIndex: Int, _ unit: Ruleset.Counting.Unit) -> String {
        unit == .evening ? Self.eveningKey(rounds[roundIndex]) : "runde \(roundIndex)"
    }

    /// Nøklene til de N beste gruppene: summen av poengene, så hulldifferansen, så den tidligste runden.
    static func bestGroups(_ items: [(key: String, round: Int, points: Double, holes: Int)], best n: Int) -> Set<String> {
        var groups: [String: (round: Int, points: Double, holes: Int)] = [:]
        for item in items {
            var g = groups[item.key] ?? (round: item.round, points: 0, holes: 0)
            g.round = min(g.round, item.round)
            g.points += item.points
            g.holes += item.holes
            groups[item.key] = g
        }
        let ranked = groups.sorted { x, y in
            if x.value.points != y.value.points { return x.value.points > y.value.points }
            if x.value.holes != y.value.holes { return x.value.holes > y.value.holes }
            return x.value.round < y.value.round
        }
        return Set(ranked.prefix(max(0, n)).map(\.key))
    }

    /// `matchSum`: poengene avrundet etter regelsettet (Golfgutu: nærmeste halve), hulldifferansen
    /// og antall matcher.
    public static func matchSum(_ results: [MatchResult], rules: Ruleset = .golfgutu) -> MatchSum {
        MatchSum(points: rules.roundTablePoints(results.reduce(0) { $0 + $1.points }),
                 holes: results.reduce(0) { $0 + $1.holes },
                 matches: results.count)
    }

    /// `matchPoengFor` / `matchHullFor`: summen av de tellende matchene.
    public func matchTotals(for playerID: String) -> MatchSum {
        Self.matchSum(matchResults(for: playerID).counting, rules: ruleset)
    }

    // MARK: Sidepremier

    /// `sidepremieResultaterFor`: premiene spilleren har vunnet, vektet med runden. Lik lengde deler
    /// når regelsettet sier det. Vekt 0 hopper over runden. Premie av i regelsettet: ingen.
    public func sidePrizeResults(for playerID: String) -> [SidePrizeResult] {
        var out: [SidePrizeResult] = []
        for (i, round) in rounds.enumerated() {
            let weight = Self.weight(round)
            if weight == 0 { continue }
            for kind in [SideClaim.Kind.drive, .kp] where ruleset.sidePrizes[kind].enabled {
                let winners = SidePrizes.winners(SidePrizes.claims(kind, in: round, claims: claims))
                guard winners.contains(playerID) else { continue }
                let share = ruleset.sidePrizes.splitTies ? Double(winners.count) : 1
                out.append(SidePrizeResult(roundIndex: i, roundID: round.id, kind: kind, shared: winners.count > 1,
                                           points: (ruleset.sidePrizes[kind].points / share) * weight))
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
    /// utvelgelsen), etter `table.stablefordCounting`: de N beste rundene (Golfgutu, `TELLENDE_RUNDER`),
    /// eller rundene i de N beste kveldene (summen av kveldens runder). `best` `nil`: alle.
    public func countingRounds(for playerID: String) -> RoundSelection {
        let chronological = rounds.indices.compactMap { i in
            weightedRoundPoints(i, playerID: playerID).map { RoundScore(roundIndex: i, roundID: rounds[i].id, points: $0) }
        }
        let all = chronological.enumerated().sorted { x, y in
            x.element.points != y.element.points ? x.element.points > y.element.points : x.offset < y.offset
        }.map(\.element)
        let counting = ruleset.table.stablefordCounting
        guard let n = counting.best else { return RoundSelection(counting: all, dropped: []) }
        guard counting.unit == .evening else {
            return RoundSelection(counting: Array(all.prefix(n)), dropped: Array(all.dropFirst(n)))
        }
        let keep = Self.bestGroups(chronological.map {
            (key: groupKey($0.roundIndex, .evening), round: $0.roundIndex, points: $0.points, holes: 0)
        }, best: n)
        return RoundSelection(counting: all.filter { keep.contains(groupKey($0.roundIndex, .evening)) },
                              dropped: all.filter { !keep.contains(groupKey($0.roundIndex, .evening)) })
    }

    /// `seasonTotalNytt`: summen av de tellende rundene, avrundet som JS.
    public func stablefordTotal(for playerID: String) -> Int {
        JS.roundInt(countingRounds(for: playerID).counting.reduce(0) { $0 + $1.points })
    }

    // MARK: Tabellene

    /// `jakketavle`: duellpoeng pluss sidepremier, alle i troppen, med det som teller etter regelsettet.
    /// Sortert på total, så regelsettets skilletegn (Golfgutu: hulldifferanse, stablefordsum), så navn (norsk).
    public func jacketBoard() -> [JacketRow] {
        let rows = players.map { p -> JacketRow in
            let selection = tableSelection(for: p.id)
            let d = selection.matches
            let s = Self.matchSum(d.counting, rules: ruleset)
            let side = selection.sidePrizes.counting.reduce(0) { $0 + $1.points }
            return JacketRow(player: p, total: ruleset.roundTablePoints(s.points + side), duel: s.points, side: side,
                             matches: s.matches, holes: s.holes, played: d.counting.count + d.dropped.count,
                             stableford: stablefordTotal(for: p.id))
        }
        return rows.sorted { a, b in
            if a.total != b.total { return a.total > b.total }
            for t in ruleset.table.tiebreaks {
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
        Array(Set(rounds.map(eveningKey))).sorted()
    }

    /// Kvelden runden hører til: datoen, eller «uten dato <id>» (en runde uten dato er sin egen kveld).
    static func eveningKey(_ round: Round) -> String {
        round.date.flatMap { $0.isEmpty ? nil : $0 } ?? "uten dato " + (round.id ?? "undefined")
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

    /// `fmtPoeng`: avrundet etter regelsettet (Golfgutu: nærmeste halve), desimalkomma. «4», ikke «4,0».
    public static func formatPoints(_ x: Double, rules: Ruleset = .golfgutu) -> String {
        JS.norwegianString(rules.roundTablePoints(x.isNaN ? 0 : x))
    }

    /// Rundevekten. NaN regnes som 0 (`if(!vekt)` i JS).
    static func weight(_ round: Round) -> Double {
        round.weight.isNaN ? 0 : round.weight
    }
}
