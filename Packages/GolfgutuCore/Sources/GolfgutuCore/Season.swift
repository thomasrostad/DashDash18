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
    /// Tilleggspoeng gitt for hånd (`PointAdjustment`), i lagret rekkefølge.
    public let adjustments: [PointAdjustment]
    public let ruleset: Ruleset
    /// `round_points` per runde, regnet én gang.
    private let pointsByRound: [[String: Int]]
    /// Rundepoengene i tabellen når den teller formens poeng (`table.formPoints`), regnet én gang. Tom ellers.
    private let formPointsByRound: [[String: Double]]

    /// - Parameter playingHandicaps: rundens frosne spillehandicap, runde-id → spiller-id → handicap
    ///   i hele slag. Legges på rundene (`Round.playingHandicaps`, og vinner over det som står der fra før)
    ///   og er fasit for poeng og matcher i den runden. Endrer en spiller handicap midt i sesongen,
    ///   regnes hver runde med det spilleren hadde da. Tom (standard): alt regnes fra troppen.
    /// - Parameter adjustments: tilleggspoeng gitt for hånd. Tom (standard): tabellen er som før.
    public init(players: [Player], rounds: [Round], claims: [SideClaim] = [], ruleset: Ruleset = .golfgutu,
                playingHandicaps: [String: [String: Double]] = [:], adjustments: [PointAdjustment] = []) {
        self.players = players
        let rounds = rounds.map { round -> Round in
            var r = round
            if let id = round.id, let frozen = playingHandicaps[id], !frozen.isEmpty {
                r.playingHandicaps.merge(frozen) { _, new in new }
            }
            // Maks slag per hull (`play.maxStrokes`): scorer over grensen teller som grensen. Av: uendret.
            return r.cappingStrokes(roster: players, rules: ruleset)
        }
        self.rounds = rounds
        self.claims = claims
        self.adjustments = adjustments
        self.ruleset = ruleset
        pointsByRound = rounds.map { Scoring.roundPoints($0, roster: players, rules: ruleset) }
        formPointsByRound = switch ruleset.table.pointsSource {
        case .placement: rounds.map { FormPlay.placementPoints($0, roster: players, rules: ruleset) }
        case .stableford where ruleset.table.formPoints:
            rounds.map { FormPlay.tablePoints($0, roster: players, rules: ruleset) }
        default: []
        }
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

    /// Det som teller i tabellen: matcher og sidepremier, eller (når tabellen teller stableford)
    /// runder og sidepremier.
    public struct TableSelection: Hashable, Sendable {
        /// Tom når tabellen teller stableford.
        public var matches: MatchSelection
        public var sidePrizes: SidePrizeSelection
        /// Rundenes stablefordpoeng (vektet) når tabellen teller stableford, best først. Tom når
        /// tabellen teller matcher (stablefordsummen står da i `countingRounds`).
        public var rounds: RoundSelection = RoundSelection(counting: [], dropped: [])
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
        /// Duell (eller stablefordpoeng) + sidepremier + tilleggspoeng, avrundet etter regelsettet
        /// (Golfgutu: nærmeste halve).
        public var total: Double
        /// Tellende matchpoeng. 0 når tabellen teller stableford.
        public var duel: Double
        /// Tellende sidepremier.
        public var side: Double
        /// Tellende matcher.
        public var matches: Int
        public var holes: Int
        /// Spilte matcher, også strøkne. Når tabellen teller stableford: spilte runder, også strøkne.
        public var played: Int
        /// Stablefordsummen (skilletegn).
        public var stableford: Int
        /// Tellende stablefordpoeng i tabellen (vektet, før avrunding) når tabellen teller stableford.
        /// 0 når tabellen teller matcher.
        public var roundPoints: Double = 0
        /// Kveldene spilleren har spilt som teller (score eller match i en runde med vekt over 0).
        public var evenings: Int = 0
        /// Har spilt nok kvelder til å rangeres (`table.minEvenings`). Alltid sann uten grense.
        public var qualified: Bool = true
        /// Tilleggspoeng gitt for hånd (`adjustmentPoints`). 0 uten.
        public var adjustment: Double = 0
    }

    /// En rad i tabellen med plass (`standings(playoffWinner:)`).
    public struct Standing: Hashable, Sendable {
        public var row: JacketRow
        /// 1, 1, 3 …: delt plass har samme nummer. `nil`: ikke kvalifisert (for få kvelder), står under
        /// de rangerte.
        public var place: Int?
        /// Delt førsteplass med `tieRule` `playoff`, og playoffen er ikke avgjort.
        public var playoffPending: Bool
        /// Vant playoffen om førsteplassen.
        public var wonPlayoff: Bool
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
    /// Med `table.pointsSource` `stableford` teller rundenes stablefordpoeng i stedet for matchene
    /// (se `stablefordTableSelection`).
    public func tableSelection(for playerID: String) -> TableSelection {
        if ruleset.table.pointsSource.countsRounds { return stablefordTableSelection(for: playerID) }
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

    /// Tabellen når den teller stableford: spillerens stablefordpoeng per runde ganget med vekten
    /// (som i stablefordsummen) pluss sidepremiene, og de N beste rundene eller kveldene teller etter
    /// `table.counting` (`match` regnes som `round`). Runder med vekt 0 hopper over, som for matcher.
    /// Likt avgjøres av den tidligste runden. Matcher og trekanter gir ingen tabellpoeng.
    private func stablefordTableSelection(for playerID: String) -> TableSelection {
        let side = sidePrizeResults(for: playerID)
        let chronological = rounds.indices.compactMap { i -> RoundScore? in
            guard effectiveWeight(rounds[i]) != 0, let p = weightedTableRoundPoints(i, playerID: playerID) else { return nil }
            return RoundScore(roundIndex: i, roundID: rounds[i].id, points: p)
        }
        let all = chronological.enumerated().sorted { x, y in
            x.element.points != y.element.points ? x.element.points > y.element.points : x.offset < y.offset
        }.map(\.element)
        let none = MatchSelection(counting: [], dropped: [])
        let counting = ruleset.table.counting
        guard let n = counting.best, n > 0 else {
            return TableSelection(matches: none, sidePrizes: SidePrizeSelection(counting: side, dropped: []),
                                  rounds: RoundSelection(counting: all, dropped: []))
        }
        let unit: Ruleset.Counting.Unit = counting.unit == .evening ? .evening : .round
        let items = chronological.map { (key: groupKey($0.roundIndex, unit), round: $0.roundIndex, points: $0.points, holes: 0) }
            + side.map { (key: groupKey($0.roundIndex, unit), round: $0.roundIndex, points: $0.points, holes: 0) }
        let keep = Self.bestGroups(items, best: n)
        let inRounds = all.map { keep.contains(groupKey($0.roundIndex, unit)) }
        let inSide = side.map { keep.contains(groupKey($0.roundIndex, unit)) }
        return TableSelection(
            matches: none,
            sidePrizes: SidePrizeSelection(counting: zip(side, inSide).filter(\.1).map(\.0),
                                           dropped: zip(side, inSide).filter { !$0.1 }.map(\.0)),
            rounds: RoundSelection(counting: zip(all, inRounds).filter(\.1).map(\.0),
                                   dropped: zip(all, inRounds).filter { !$0.1 }.map(\.0)))
    }

    /// Matchene i rundenes rekkefølge, før sortering og utvalg.
    private func matchResultsInOrder(for playerID: String) -> [MatchResult] {
        var all: [MatchResult] = []
        for (i, round) in rounds.enumerated() {
            let weight = effectiveWeight(round)
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
            let weight = effectiveWeight(round)
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

    // MARK: Tilleggspoeng

    /// Spillerens tilleggspoeng, i lagret rekkefølge.
    public func adjustments(for playerID: String) -> [PointAdjustment] {
        adjustments.filter { $0.playerId == playerID }
    }

    /// Summen av spillerens tilleggspoeng. Uvektet, og strykes aldri av «beste N».
    public func adjustmentPoints(for playerID: String) -> Double {
        adjustments(for: playerID).reduce(0) { $0 + $1.points }
    }

    // MARK: Stablefordsummen

    /// Rundens poeng (`round.points`), regnet fra scorene.
    public func roundPoints(_ roundIndex: Int) -> [String: Int] {
        pointsByRound[roundIndex]
    }

    /// `rundePoengVektet`: rundens poeng ganget med vekten. `nil` når spilleren ikke har poeng i runden.
    public func weightedRoundPoints(_ roundIndex: Int, playerID: String) -> Double? {
        guard let p = pointsByRound[roundIndex][playerID] else { return nil }
        return Double(p) * effectiveWeight(rounds[roundIndex])
    }

    /// Rundens poeng i tabellen, uvektet: plasseringspoeng (`table.pointsSource` `placement`), formens poeng
    /// (`table.formPoints`), ellers stablefordpoengene. Det rundeoversikten på Tavla viser.
    public func tableRoundPoints(_ roundIndex: Int) -> [String: Double] {
        formPointsByRound.isEmpty ? pointsByRound[roundIndex].mapValues(Double.init) : formPointsByRound[roundIndex]
    }

    /// Rundens poeng i tabellen ganget med vekten: formens poeng med `table.formPoints`, ellers
    /// stablefordpoengene (`weightedRoundPoints`).
    func weightedTableRoundPoints(_ roundIndex: Int, playerID: String) -> Double? {
        guard !formPointsByRound.isEmpty else { return weightedRoundPoints(roundIndex, playerID: playerID) }
        guard let p = formPointsByRound[roundIndex][playerID] else { return nil }
        return p * effectiveWeight(rounds[roundIndex])
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

    /// `jakketavle`: duellpoeng (eller stablefordpoeng, etter `table.pointsSource`) pluss sidepremier,
    /// alle i troppen, med det som teller etter regelsettet. Tilleggspoeng (`adjustments`) legges på
    /// totalen før avrundingen; med snitt legges de på snittet. Uten tilleggspoeng: som PWA-en.
    /// Sortert på total, så regelsettets skilletegn (Golfgutu: hulldifferanse, stablefordsum), så navn (norsk).
    public func jacketBoard() -> [JacketRow] {
        let table = ruleset.table
        let minEvenings = table.minEvenings ?? 0
        let rows = players.map { p -> JacketRow in
            let selection = tableSelection(for: p.id)
            let d = selection.matches
            let s = Self.matchSum(d.counting, rules: ruleset)
            let side = selection.sidePrizes.counting.reduce(0) { $0 + $1.points }
            let played = playedEvenings(for: p.id)
            let extra = adjustmentPoints(for: p.id)
            var row: JacketRow
            if table.pointsSource.countsRounds {
                let r = selection.rounds
                let points = r.counting.reduce(0) { $0 + $1.points }
                row = JacketRow(player: p, total: ruleset.roundTablePoints(points + side + extra), duel: 0, side: side,
                                matches: 0, holes: 0, played: r.counting.count + r.dropped.count,
                                stableford: stablefordTotal(for: p.id), roundPoints: points)
            } else {
                row = JacketRow(player: p, total: ruleset.roundTablePoints(s.points + side + extra), duel: s.points, side: side,
                                matches: s.matches, holes: s.holes, played: d.counting.count + d.dropped.count,
                                stableford: stablefordTotal(for: p.id))
            }
            row.adjustment = extra
            row.evenings = played.count
            row.qualified = minEvenings <= 0 || played.count >= minEvenings
            if table.aggregation == .average {
                // Snitt per spilte kveld som teller: kvelder der alt ble strøket av «beste N», regnes ikke.
                let counted = selection.matches.counting.map(\.roundIndex) + selection.rounds.counting.map(\.roundIndex)
                    + selection.sidePrizes.counting.map(\.roundIndex)
                let dropped = selection.matches.dropped.map(\.roundIndex) + selection.rounds.dropped.map(\.roundIndex)
                    + selection.sidePrizes.dropped.map(\.roundIndex)
                let droppedEvenings = Set(dropped.map { Self.eveningKey(rounds[$0]) })
                    .subtracting(counted.map { Self.eveningKey(rounds[$0]) })
                let divisor = played.subtracting(droppedEvenings).count
                let raw = d.counting.reduce(0) { $0 + $1.points } + selection.rounds.counting.reduce(0) { $0 + $1.points } + side
                let average = divisor > 0 ? raw / Double(divisor) : 0
                row.total = ruleset.roundTablePoints(average + extra)
            }
            return row
        }
        return rows.sorted { a, b in
            if a.qualified != b.qualified { return a.qualified }
            if a.total != b.total { return a.total > b.total }
            if table.tieRule == .tiebreaks {
                for t in table.tiebreaks {
                    switch t {
                    case .holeDifference where a.holes != b.holes: return a.holes > b.holes
                    case .stableford where a.stableford != b.stableford: return a.stableford > b.stableford
                    default: continue
                    }
                }
            }
            return NorwegianSort.areInIncreasingOrder(a.player.name, b.player.name)
        }
    }

    /// Kveldene (nøklene) spilleren har spilt som teller: runder med vekt over 0 der spilleren har
    /// poeng eller er med i en match.
    func playedEvenings(for playerID: String) -> Set<String> {
        Set(rounds.indices.filter { i in
            effectiveWeight(rounds[i]) != 0
                && (pointsByRound[i][playerID] != nil
                    || rounds[i].matches.contains { MatchPlay.involves($0, playerID: playerID, in: rounds[i]) })
        }.map { Self.eveningKey(rounds[$0]) })
    }

    /// Tabellen med plass. Rekkefølgen er jakketavlas, med disse tilleggene:
    /// - Like på total (og på alle skillene med `tieRule` `tiebreaks`) gir delt plass: 1, 1, 3.
    /// - Ikke kvalifisert (`table.minEvenings`): ingen plass, under de rangerte.
    /// - `tieRule` `playoff`: står flere likt øverst (og minst én har spilt), er playoffen ventende
    ///   (`playoffPending`) til `playoffWinner` er gitt. Vinneren (fra `Playoff.decide`) står først med
    ///   plass 1; de andre i gruppa deler andreplassen. En vinner utenfor gruppa endrer ingenting.
    public func standings(playoffWinner: String? = nil) -> [Standing] {
        let table = ruleset.table
        var rows = jacketBoard()
        func same(_ a: JacketRow, _ b: JacketRow) -> Bool {
            guard a.total == b.total else { return false }
            if table.tieRule == .playoff { return true }
            return table.tiebreaks.allSatisfy { t in
                switch t {
                case .holeDifference: a.holes == b.holes
                case .stableford: a.stableford == b.stableford
                }
            }
        }
        var pending = false
        var winner: String?
        let ranked = rows.prefix { $0.qualified }
        if table.tieRule == .playoff, ranked.count >= 2, same(ranked[0], ranked[1]), ranked[0].evenings > 0 {
            let group = ranked.prefix { same($0, ranked[0]) }
            if let w = playoffWinner, let i = group.firstIndex(where: { $0.player.id == w }) {
                rows.insert(rows.remove(at: i), at: 0)
                winner = w
            } else {
                pending = true
            }
        }
        var out: [Standing] = []
        for (i, row) in rows.enumerated() {
            guard row.qualified else {
                out.append(Standing(row: row, place: nil, playoffPending: false, wonPlayoff: false))
                continue
            }
            let previous = i > 0 ? rows[i - 1] : nil
            let shares = previous.map { same(row, $0) && $0.player.id != winner } ?? false
            let place = shares ? out[i - 1].place : i + 1
            out.append(Standing(row: row, place: place, playoffPending: pending && place == 1,
                                wonPlayoff: row.player.id == winner))
        }
        return out
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

    /// Trekningen etter regelsettets `formats.drawMethod`: etter tabellen (`drawMatches`), uten
    /// gjentakelser (færrest mulig møter fra rundene i sesongen, gjentakbar med `seed`), eller `nil` for
    /// manuell (arrangøren setter opp matchene; sjekk dem med `Draw.validate`).
    public func draw(_ participants: [Player], round: Int, seed: UInt64) -> [[String]]? {
        switch ruleset.formats.drawMethod {
        case .standings: drawMatches(participants, round: round)
        case .avoidRepeats: Draw.avoidingRepeats(participants, previous: Draw.meetings(in: rounds), seed: seed)
        case .manual: nil
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

    /// Vekten runden teller med: 0 når kvelden ikke teller (`counts`), ellers rundevekten ganget med
    /// poengtabellen den peker på (`table.pointsTables`; ukjent eller ingen: 1). Med Golfgutu-oppsettet
    /// er dette rundevekten.
    public func effectiveWeight(_ round: Round) -> Double {
        guard round.counts else { return 0 }
        let multiplier = round.pointsTable.flatMap { ruleset.table.pointsTables[$0]?.multiplier } ?? 1
        return Self.weight(round) * multiplier
    }
}
