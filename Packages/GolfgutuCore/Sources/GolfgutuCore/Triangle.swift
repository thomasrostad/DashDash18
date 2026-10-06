import Foundation

/// Trekanten og trekningen av matcher (db-nytt.js linje 537–566 og 779–803).
public enum Triangle {
    /// `trekantPoeng`: tre spillere rangert på rundens stablefordsum, med plasspoengene fra
    /// regelsettet. Delt plass deler summen av plassene, så summen er alltid den samme.
    /// `nil` når matchen ikke er en trekant, eller når en av de tre ikke har ført noe.
    public static func points(_ match: Match, in round: Round, roster: [Player],
                              rules: Ruleset = .golfgutu) -> [String: Double]? {
        let placePoints = rules.table.trianglePoints
        guard match.isTriangle, let a = match.playerA, let b = match.playerB, let c = match.playerC else { return nil }
        let ids = [a, b, c]
        var totals: [Int] = []
        for pid in ids {
            guard let scores = round.holeScores[pid], !scores.isEmpty else { return nil }
            totals.append(Scoring.roundNetTotal(round, player: roster.first { $0.id == pid }, roster: roster, rules: rules))
        }
        // Høyest først. Ved likt beholdes rekkefølgen A, B, C (JS-sorteringen er stabil).
        let ranked = ids.indices.sorted { totals[$0] != totals[$1] ? totals[$0] > totals[$1] : $0 < $1 }
        var out: [String: Double] = [:]
        var i = 0
        while i < ranked.count {
            var j = i
            while j + 1 < ranked.count, totals[ranked[j + 1]] == totals[ranked[i]] { j += 1 }
            let shared = (i...j).reduce(0.0) { $0 + ($1 < placePoints.count ? placePoints[$1] : 0) }
            let each = shared / Double(j - i + 1)
            for n in i...j { out[ids[ranked[n]]] = each }
            i = j + 1
        }
        return out
    }

    /// `trekkMatcher`: sveitsisk trekning. Sorter på stilling (høyest først), så navn (norsk).
    /// Oddetall omgang snur rekka, så andre match ikke gir samme motstander. Oddetall spillere:
    /// de tre siste blir en trekant. Under to spillere: ingen matcher.
    /// - Parameters:
    ///   - standing: tabellpoeng per spiller-id (`matchPoengFor(id).poeng`). Mangler = 0.
    ///   - round: omgangen, 0-basert.
    /// - Returns: spiller-id-er per match, to eller tre.
    public static func drawMatches(_ participants: [Player], round: Int, standing: [String: Double]) -> [[String]] {
        var order = participants.enumerated().sorted { x, y in
            let sx = standing[x.element.id] ?? 0, sy = standing[y.element.id] ?? 0
            if sx != sy { return sx > sy }
            let byName = NorwegianSort.compare(x.element.name, y.element.name)
            if byName != .orderedSame { return byName == .orderedAscending }
            return x.offset < y.offset
        }.map(\.element)
        if round % 2 == 1 { order.reverse() }

        var pairs: [[String]] = []
        if order.count < 2 { return pairs }
        let triangle = order.count % 2 == 1
        let end = triangle ? order.count - 3 : order.count
        var i = 0
        while i + 1 < end {
            pairs.append([order[i].id, order[i + 1].id])
            i += 2
        }
        if triangle {
            pairs.append(order.suffix(3).map(\.id))
        }
        return pairs
    }
}
