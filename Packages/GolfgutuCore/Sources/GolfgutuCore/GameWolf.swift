import Foundation

/// Wolf (se `WolfRules`).
///
/// Spillerne er wolf etter tur i spillets rekkefølge: første spiller på rundens første hull, så
/// neste (`Games.wolf`). Wolfen velger partner etter utslagene, spiller alene, eller melder blind
/// wolf før noen har slått (markeringen per hull). Beste ball (netto) på hver side avgjør hullet;
/// har bare én side score (runden er ferdig), vinner den. Delt hull gir ingen poeng.
///
/// Poeng etter malen: wolf og partner vinner → hver får `partnerWin`; de andre vinner → hver av
/// dem får `opponentsWin`. Alene: vinner → wolfen får `loneWin`; taper → hver av de andre får
/// `loneLoss`. Blind: `blindWin` og `blindLoss` på samme måte. Blind wolf når det ikke er lov,
/// regnes som alene.
///
/// Hullene er uavhengige: et hull uten valg eller score venter (eller teller ikke når runden er
/// ferdig), og de andre hullene regnes likevel. Oppgjøret er parvis på wolf-poengene.
enum WolfGame {
    static func evaluate(_ ctx: GameContext, rules r: WolfRules, marks: [Int: WolfChoice]) -> GameResult {
        let players = ctx.players
        let hcp = ctx.handicaps(r.handicap)
        var points = Dictionary(uniqueKeysWithValues: players.map { ($0, 0) })
        var holes: [GameHole] = []

        for h in 0..<ctx.count {
            guard let wolf = Games.wolf(on: h, players: players) else { break }
            let choice = marks[h].flatMap { valid($0, wolf: wolf, players: players) }
            guard ctx.isReady(h), let choice else {
                holes.append(GameHole(hole: h, state: ctx.isFinal ? .void : .pending, wolf: wolf))
                continue
            }
            var mode = choice.mode
            if mode == .blind && !r.blindAllowed { mode = .alone }
            let wolfSide = [wolf] + (mode == .partner ? [choice.partner!] : [])
            let others = players.filter { !wolfSide.contains($0) }
            let a = GameContext.best(wolfSide.map { ctx.net($0, h, handicaps: hcp) })
            let b = GameContext.best(others.map { ctx.net($0, h, handicaps: hcp) })
            let wolfWins: Bool?
            switch (a, b) {
            case let (x?, y?): wolfWins = x < y ? true : (y < x ? false : nil)
            case (_?, nil): wolfWins = true
            case (nil, _?): wolfWins = false
            default: wolfWins = nil
            }
            guard let wolfWins else {
                holes.append(GameHole(hole: h, state: .halved, wolf: wolf))
                continue
            }
            var award: [String: Int] = [:]
            switch (mode, wolfWins) {
            case (.partner, true): for p in wolfSide { award[p] = r.partnerWin }
            case (.partner, false): for p in others { award[p] = r.opponentsWin }
            case (.alone, true): award[wolf] = r.loneWin
            case (.alone, false): for p in others { award[p] = r.loneLoss }
            case (.blind, true): award[wolf] = r.blindWin
            case (.blind, false): for p in others { award[p] = r.blindLoss }
            }
            for (p, v) in award { points[p, default: 0] += v }
            holes.append(GameHole(hole: h, state: .won, winners: wolfWins ? wolfSide : others,
                                  value: award.values.reduce(0, +), points: award, wolf: wolf))
        }

        return GameResult(kind: .wolf, holes: holes, scores: points.mapValues(Double.init),
                          settlement: PointSplit.pairwise(points, players: players, value: r.pointValue),
                          isFinished: holes.allSatisfy { $0.state != .pending })
    }

    /// Valget, eller `nil` når partneren ikke er en annen spiller i spillet.
    private static func valid(_ c: WolfChoice, wolf: String, players: [String]) -> WolfChoice? {
        guard c.mode == .partner else { return c }
        guard let p = c.partner, p != wolf, players.contains(p) else { return nil }
        return c
    }
}

/// Bingo-bango-bongo (se `BingoBangoBongoRules`).
///
/// Poengene settes for hånd per hull: bingo (først på green), bango (nærmest hullet når alle er
/// på green) og bongo (først i hullet). Scorene brukes ikke. Et hull uten markering venter, og
/// teller ikke når runden er ferdig. Oppgjøret er parvis på poengene.
enum BingoBangoBongoGame {
    static func evaluate(_ ctx: GameContext, rules r: BingoBangoBongoRules,
                         marks: [Int: BingoBangoBongoMarks]) -> GameResult {
        let players = ctx.players
        var points = Dictionary(uniqueKeysWithValues: players.map { ($0, 0) })
        var holes: [GameHole] = []
        for h in 0..<ctx.count {
            let m = marks[h] ?? BingoBangoBongoMarks()
            var award: [String: Int] = [:]
            var winners: [String] = []
            for (id, value) in [(m.bingo, r.bingo), (m.bango, r.bango), (m.bongo, r.bongo)] {
                guard let id, players.contains(id) else { continue }
                award[id, default: 0] += value
                if !winners.contains(id) { winners.append(id) }
            }
            if winners.isEmpty {
                holes.append(GameHole(hole: h, state: ctx.isFinal ? .void : .pending))
                continue
            }
            for (p, v) in award { points[p, default: 0] += v }
            holes.append(GameHole(hole: h, state: .won, winners: winners, value: award.values.reduce(0, +),
                                  points: award))
        }
        return GameResult(kind: .bingoBangoBongo, holes: holes, scores: points.mapValues(Double.init),
                          settlement: PointSplit.pairwise(points, players: players, value: r.pointValue),
                          isFinished: ctx.isFinal || holes.allSatisfy { $0.state != .pending })
    }
}
