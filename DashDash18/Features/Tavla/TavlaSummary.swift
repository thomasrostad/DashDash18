import Foundation
import GolfgutuCore

/// Sesongoppsummeringen (`seasonHighlights` / `renderOppsummering`): mester, pall og sesongens tall.
/// Rangert på samme tabell som Tavla, så mesteren er den Tavla har vist hele sesongen.
nonisolated struct SeasonSummary: Sendable {
    struct Highlight: Hashable, Sendable {
        let memberID: UUID
        let name: String
        let value: String
        /// Tilleggslinje, f.eks. runden.
        let detail: String?
    }

    let champion: TavlaStandings.Row
    /// «bærer den grønne jakka» med Golfgutu-oppsettet, ellers nil (bare «Mester»).
    let championLine: String?
    /// «4,5 fra 5 dueller · 1 fra sidepremier».
    let championBasis: String
    /// De tre første.
    let podium: [TavlaStandings.Row]
    let rest: [TavlaStandings.Row]
    let bestRound: Highlight?
    let mostBirdies: Highlight?
    let longestDrive: Highlight?
    let eveningsPlayed: Int
    let eveningsTotal: Int
}

nonisolated extension TavlaStandings {
    /// Nil når ingen kveld er spilt («Ingenting å oppsummere ennå»).
    var summary: SeasonSummary? {
        guard let champion = rows.first, eveningsPlayed > 0 else { return nil }

        var basis = "\(points(champion.duel)) fra \(champion.matches == 1 ? "én duell" : "\(champion.matches) dueller")"
        if champion.side > 0 { basis += " · \(points(champion.side)) fra sidepremier" }
        if countsStableford { basis = self.basis(champion) ?? basis }

        // Sesongens runde: flest stablefordpoeng i én runde. Likt: den tidligste, så tabellens rekkefølge.
        var best: (points: Int, member: UUID, round: Int)?
        for i in season.rounds.indices {
            let all = season.roundPoints(i)
            for r in rows {
                guard let p = all[r.memberID.uuidString] else { continue }
                if best == nil || p > best!.points { best = (p, r.memberID, i) }
            }
        }
        let bestRound = best.map { b in
            SeasonSummary.Highlight(memberID: b.member, name: row(b.member)?.name ?? "", value: "\(b.points) p",
                                    detail: roundTitle(b.round))
        }

        // Flest birdies (netto). Likt: tabellens rekkefølge.
        var birdie: (count: Int, row: Row)?
        for r in rows {
            let n = birdies(r.memberID)
            if n > 0 && (birdie == nil || n > birdie!.count) { birdie = (n, r) }
        }
        let mostBirdies = birdie.map {
            SeasonSummary.Highlight(memberID: $0.row.memberID, name: $0.row.name, value: "\($0.count)", detail: nil)
        }

        let drive = SidePrizes.seasonLongestDrive(claims).first.flatMap { c -> SeasonSummary.Highlight? in
            guard let id = UUID(uuidString: c.playerId) else { return nil }
            let roundIndex = snapshots.firstIndex { $0.round.id.uuidString == c.roundId }
            return SeasonSummary.Highlight(memberID: id, name: row(id)?.name ?? "", value: SidePrizes.formatMeters(c.meters),
                                           detail: roundIndex.map(roundTitle))
        }

        return SeasonSummary(champion: champion,
                             championLine: rules == .golfgutu ? "bærer den grønne jakka" : nil,
                             championBasis: basis,
                             podium: Array(rows.prefix(3)), rest: Array(rows.dropFirst(3)),
                             bestRound: bestRound, mostBirdies: mostBirdies, longestDrive: drive,
                             eveningsPlayed: eveningsPlayed, eveningsTotal: eveningsTotal)
    }
}
