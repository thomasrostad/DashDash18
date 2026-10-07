import Foundation

/// Nassau og 2 mot 2 best ball (se `NassauRules` og `BestBallRules`).
///
/// Begge er veddemål mellom to sider der sidens score på et hull er beste ball (laveste netto,
/// eller høyeste stableford). Hullene regnes i rekkefølge til første hull som ikke er ferdig.
///
/// Match: siden med lavest netto vinner hullet. Har bare én side score (runden er ferdig), vinner
/// den. Et veddemål er avgjort når en side leder med flere hull enn det er igjen, eller når alle
/// hullene er spilt. Likt etter siste hull er delt (ingen poeng).
///
/// Slag (Nassau): lavest sum over hullene vinner. En side som mangler score på et hull (runden er
/// ferdig), taper; mangler begge, teller veddemålet ikke.
///
/// Nassau har tre veddemål på 18 hull: første ni (hull 1–9 i runden), siste ni (10–18) og hele
/// runden. En 9-hullsrunde (også med start på hull 10) har bare hele runden. En avkortet runde
/// kutter veddemålene ved avkortingen; et veddemål uten hull teller ikke.
///
/// Press (bare match): når en side ligger `pressTrigger` hull under i det siste veddemålet på en
/// ni (eller i hele runden på 9 hull), starter et nytt veddemål på neste hull og varer ut nien.
/// Hvert press kan selv utløse et nytt.
enum NassauGame {
    static func evaluate(_ ctx: GameContext, rules r: NassauRules) -> GameResult {
        let hcp = ctx.handicaps(r.handicap)
        let sides = SideHoles(ctx, handicaps: hcp)
        let full = ctx.round.numberOfHoles
        var segments: [(GameBet.Segment, ClosedRange<Int>, Int)] = []
        if full == 18 {
            segments = [(.front, 0...8, r.front), (.back, 9...17, r.back), (.total, 0...17, r.total)]
        } else {
            segments = [(.total, 0...(full - 1), r.total)]
        }

        var bets: [GameBet] = []
        for (segment, range, value) in segments {
            let holes = range.filter { $0 < ctx.count }
            guard let first = holes.first, let last = holes.last else {
                bets.append(GameBet(segment: segment, firstHole: range.lowerBound, lastHole: range.upperBound,
                                    state: .void, value: value))
                continue
            }
            switch r.scoring {
            case .match:
                bets.append(sides.match(segment, first: first, last: last, value: value))
                let pressable = full == 18 ? segment != .total : true
                if r.press, pressable {
                    bets += sides.presses(of: segment, first: first, last: last, trigger: r.pressTrigger,
                                          value: r.pressValue)
                }
            case .stroke:
                bets.append(sides.stroke(segment, first: first, last: last, value: value))
            }
        }

        let items = bets.compactMap(sides.settlementItem)
        return GameResult(kind: .nassau, holes: sides.holeResults(match: r.scoring == .match), bets: bets,
                          settlement: PointSplit.settle(items, players: ctx.players),
                          isFinished: bets.allSatisfy { $0.state != .pending })
    }
}

enum BestBallGame {
    static func evaluate(_ ctx: GameContext, rules r: BestBallRules) -> GameResult {
        let hcp = ctx.handicaps(r.handicap)
        let sides = SideHoles(ctx, handicaps: hcp)
        let last = ctx.count - 1
        let bet: GameBet
        var scores: [String: Double] = [:]
        if last < 0 {
            bet = GameBet(segment: .match, firstHole: 0, lastHole: 0, state: ctx.isFinal ? .void : .pending,
                          value: r.value)
        } else {
            switch r.scoring {
            case .match:
                bet = sides.match(.match, first: 0, last: last, value: r.value)
            case .stableford:
                bet = sides.stableford(first: 0, last: last, value: r.value)
                let totals = sides.stablefordTotals(first: 0, last: last)
                for p in ctx.players {
                    scores[p] = Double(ctx.setup.sides[p] == 1 ? totals.0 : totals.1)
                }
            }
        }
        let items = [bet].compactMap(sides.settlementItem)
        return GameResult(kind: .bestBall, holes: sides.holeResults(match: r.scoring == .match,
                                                                    stableford: r.scoring == .stableford),
                          bets: [bet], scores: scores,
                          settlement: PointSplit.settle(items, players: ctx.players),
                          isFinished: bet.state != .pending)
    }
}

/// Hullene sett fra to sider: beste ball per side og hvem som vant hvert hull.
struct SideHoles {
    let ctx: GameContext
    let side1: [String]
    let side2: [String]
    let handicaps: [String: Int]
    /// Første hull som ikke er ferdig (alle hull før det er regnet). `ctx.count` når alle er ferdige.
    let firstPending: Int

    init(_ ctx: GameContext, handicaps: [String: Int]) {
        self.ctx = ctx
        self.handicaps = handicaps
        side1 = ctx.setup.side(1)
        side2 = ctx.setup.side(2)
        var h = 0
        while h < ctx.count, ctx.isReady(h, for: side1 + side2) { h += 1 }
        firstPending = h
    }

    func bestNet(_ side: [String], _ h: Int) -> Int? {
        GameContext.best(side.map { ctx.net($0, h, handicaps: handicaps) })
    }

    func bestPoints(_ side: [String], _ h: Int) -> Int? {
        side.compactMap { ctx.stableford($0, h, handicaps: handicaps) }.max()
    }

    /// Vinneren av hullet i match: 1, 2 eller 0 (delt).
    func matchWinner(_ h: Int) -> Int {
        switch (bestNet(side1, h), bestNet(side2, h)) {
        case let (a?, b?): a < b ? 1 : (b < a ? 2 : 0)
        case (_?, nil): 1
        case (nil, _?): 2
        default: 0
        }
    }

    func players(of side: Int) -> [String] { side == 1 ? side1 : side2 }

    /// Ett matchveddemål over hullene `first...last`.
    func match(_ segment: GameBet.Segment, pressOf: GameBet.Segment? = nil, first: Int, last: Int,
               value: Int) -> GameBet {
        var up = 0
        var played = 0
        for h in first...last where h < firstPending {
            switch matchWinner(h) {
            case 1: up += 1
            case 2: up -= 1
            default: break
            }
            played += 1
        }
        let remaining = last - first + 1 - played
        let state: GameBet.State
        var winner: Int?
        if abs(up) > remaining || (remaining == 0 && up != 0) {
            state = .won
            winner = up > 0 ? 1 : 2
        } else if remaining == 0 {
            state = .halved
        } else {
            state = .pending
        }
        return GameBet(segment: segment, pressOf: pressOf, firstHole: first, lastHole: last, state: state,
                       winner: winner, margin: up, played: played, remaining: remaining, value: value)
    }

    /// Pressene på en ni: et nytt veddemål starter på neste hull hver gang en side ligger
    /// `trigger` hull under i det siste veddemålet, så lenge det er hull igjen.
    func presses(of segment: GameBet.Segment, first: Int, last: Int, trigger: Int, value: Int) -> [GameBet] {
        var starts: [Int] = []
        var up = 0
        for h in first...last where h < firstPending {
            switch matchWinner(h) {
            case 1: up += 1
            case 2: up -= 1
            default: break
            }
            if abs(up) >= trigger, h < last {
                starts.append(h + 1)
                up = 0
            }
        }
        return starts.map { match(.press, pressOf: segment, first: $0, last: last, value: value) }
    }

    /// Slagspill over `first...last`: lavest sum av beste ball vinner.
    func stroke(_ segment: GameBet.Segment, first: Int, last: Int, value: Int) -> GameBet {
        var sum1 = 0, sum2 = 0
        var complete1 = true, complete2 = true
        var played = 0
        for h in first...last where h < firstPending {
            if let a = bestNet(side1, h) { sum1 += a } else { complete1 = false }
            if let b = bestNet(side2, h) { sum2 += b } else { complete2 = false }
            played += 1
        }
        let remaining = last - first + 1 - played
        guard remaining == 0 else {
            return GameBet(segment: segment, firstHole: first, lastHole: last, state: .pending,
                           margin: sum2 - sum1, played: played, remaining: remaining, value: value)
        }
        let state: GameBet.State
        var winner: Int?
        switch (complete1, complete2) {
        case (true, false): state = .won; winner = 1
        case (false, true): state = .won; winner = 2
        case (false, false): state = .void
        case (true, true):
            if sum1 == sum2 { state = .halved } else { state = .won; winner = sum1 < sum2 ? 1 : 2 }
        }
        return GameBet(segment: segment, firstHole: first, lastHole: last, state: state, winner: winner,
                       margin: sum2 - sum1, played: played, remaining: 0, value: value)
    }

    /// Summen av lagets beste stablefordpoeng per hull (hull uten score: 0).
    func stablefordTotals(first: Int, last: Int) -> (Int, Int) {
        var t1 = 0, t2 = 0
        for h in first...last where h < firstPending {
            t1 += bestPoints(side1, h) ?? 0
            t2 += bestPoints(side2, h) ?? 0
        }
        return (t1, t2)
    }

    /// Stableford over `first...last`: høyest sum av lagets beste poeng vinner.
    func stableford(first: Int, last: Int, value: Int) -> GameBet {
        let (t1, t2) = stablefordTotals(first: first, last: last)
        let played = max(0, min(firstPending, last + 1) - first)
        let remaining = last - first + 1 - played
        let state: GameBet.State
        var winner: Int?
        if remaining > 0 {
            state = .pending
        } else if t1 == t2 {
            state = .halved
        } else {
            state = .won
            winner = t1 > t2 ? 1 : 2
        }
        return GameBet(segment: .match, firstHole: first, lastHole: last, state: state, winner: winner,
                       margin: t1 - t2, played: played, remaining: remaining, value: value)
    }

    /// Hullene: hvem som vant (match) eller fikk flest poeng (stableford), og stillingen etter hullet.
    func holeResults(match: Bool, stableford: Bool = false) -> [GameHole] {
        var up = 0
        return (0..<ctx.count).map { h in
            guard h < firstPending else { return GameHole(hole: h, state: .pending) }
            if stableford {
                let a = bestPoints(side1, h) ?? 0, b = bestPoints(side2, h) ?? 0
                var points: [String: Int] = [:]
                for p in side1 + side2 { points[p] = ctx.stableford(p, h, handicaps: handicaps) }
                let winners = a > b ? side1 : (b > a ? side2 : [])
                return GameHole(hole: h, state: a == b ? .halved : .won, winners: winners, points: points)
            }
            let w = matchWinner(h)
            if w == 1 { up += 1 } else if w == 2 { up -= 1 }
            return GameHole(hole: h, state: w == 0 ? .halved : .won, winners: w == 0 ? [] : players(of: w),
                            up: match ? up : nil)
        }
    }

    /// Oppgjøret for et avgjort veddemål: taperne gir verdien, vinnerne deler.
    func settlementItem(_ bet: GameBet) -> (winners: [String], losers: [String], value: Int)? {
        guard bet.state == .won, let w = bet.winner else { return nil }
        return (players(of: w), players(of: w == 1 ? 2 : 1), bet.value)
    }
}
