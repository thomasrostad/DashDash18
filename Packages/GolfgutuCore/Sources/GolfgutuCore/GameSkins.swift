import Foundation

/// Skins (se `SkinsRules`).
///
/// Hvert hull er ett skin. Lavest score (netto eller brutto) alene vinner hullet og får verdien
/// av skinnet fra hver av de andre i spillet. Er laveste score delt, er hullet delt: med
/// carry-over går skinnet videre og legges til neste hull, uten faller det bort. Hullene regnes i
/// rekkefølge til første hull som ikke er ferdig (carry-over gjør rekkefølgen viktig).
///
/// Etter siste hull: skins som står igjen, faller bort (`lapse`, alle har satt like mye, så ingen
/// poeng flytter seg) eller deles av dem som delte siste hull (`split`). Ved deling gir hver av de
/// andre verdien av skinnene, og de som delte, deler potten likt (`PointSplit`).
enum SkinsGame {
    static func evaluate(_ ctx: GameContext, rules r: SkinsRules) -> GameResult {
        let players = ctx.players
        let hcp = ctx.handicaps(r.handicap)
        var holes: [GameHole] = []
        var skins = Dictionary(uniqueKeysWithValues: players.map { ($0, 0.0) })
        var bets: [(winners: [String], losers: [String], value: Int)] = []
        var carry = 0
        var lastLow: [String] = []
        var stopped = false

        for h in 0..<ctx.count {
            if stopped || !ctx.isReady(h) {
                stopped = true
                holes.append(GameHole(hole: h, state: .pending))
                continue
            }
            let nets = players.compactMap { p in ctx.net(p, h, handicaps: hcp).map { (id: p, net: $0) } }
            let low = nets.map(\.net).min()
            let atLow = nets.filter { $0.net == low }.map(\.id)
            if atLow.count == 1 {
                let winner = atLow[0]
                let count = carry + 1
                skins[winner, default: 0] += Double(count)
                bets.append(([winner], players.filter { $0 != winner }, r.valuePerSkin * count))
                holes.append(GameHole(hole: h, state: .won, winners: [winner], value: count))
                carry = 0
            } else {
                carry = r.carryOver ? carry + 1 : 0
                holes.append(GameHole(hole: h, state: .halved, winners: atLow))
            }
            lastLow = atLow
        }

        let finished = !stopped
        if finished, carry > 0, r.leftover == .split, !lastLow.isEmpty {
            for p in lastLow { skins[p, default: 0] += Double(carry) / Double(lastLow.count) }
            bets.append((lastLow, players.filter { !lastLow.contains($0) }, r.valuePerSkin * carry))
            carry = 0
        } else if finished {
            carry = 0
        }

        return GameResult(kind: .skins, holes: holes, scores: skins,
                          settlement: PointSplit.settle(bets, players: players),
                          isFinished: finished, carry: carry)
    }
}
