import Foundation
import GolfgutuCore

/// Spillerprofilen (`profilTall` / `renderProfil`): alt avledet av sesongens runder.
nonisolated struct PlayerProfile: Sendable {
    struct RoundLine: Identifiable, Hashable, Sendable {
        let roundID: UUID
        let title: String
        /// `YYYY-MM-DD`.
        let date: String?
        /// Plass i runden på stableford (1 + antall med flere poeng).
        let place: Int
        /// Duellpoeng i runden (vektet), eller nil uten match.
        let duel: Double?
        /// Rundens stablefordpoeng (uvektet, som `round.points`).
        let stableford: Int
        let isOngoing: Bool

        var id: UUID { roundID }
    }

    /// Runder der begge har poeng: hvem fikk flest stablefordpoeng.
    struct HeadToHead: Hashable, Sendable {
        /// Runder spilleren slo deg.
        let them: Int
        /// Runder du slo spilleren.
        let me: Int
    }

    let row: TavlaStandings.Row
    let stablefordTotal: Int
    let roundsPlayed: Int
    /// Snitt stablefordpoeng per runde, én desimal (`Math.round(snitt*10)/10`).
    let average: Double?
    let best: Int?
    let birdies: Int
    let longestDrive: Double?
    /// Nyeste først.
    let rounds: [RoundLine]
    /// Nil for deg selv, og når ingen runde skilte dere.
    let headToHead: HeadToHead?
}

nonisolated extension TavlaStandings {
    func profile(_ member: UUID) -> PlayerProfile? {
        guard let row = row(member) else { return nil }
        let pid = member.uuidString

        var duelByRound: [Int: Double] = [:]
        let selection = season.tableSelection(for: pid).matches
        for m in selection.counting + selection.dropped {
            duelByRound[m.roundIndex, default: 0] += m.points
        }

        let played = season.rounds.indices.filter { season.roundPoints($0)[pid] != nil }
        let points = played.compactMap { season.roundPoints($0)[pid] }
        let average = points.isEmpty ? nil : JS.round(Double(points.reduce(0, +)) / Double(points.count) * 10) / 10

        let lines = played.reversed().map { i -> PlayerProfile.RoundLine in
            let all = season.roundPoints(i)
            let mine = all[pid] ?? 0
            let rosterIDs = Set(season.players.map(\.id))
            let better = all.filter { rosterIDs.contains($0.key) && $0.value > mine }.count
            let s = snapshots[i]
            return PlayerProfile.RoundLine(roundID: s.round.id, title: roundTitle(i), date: s.eventDate,
                                           place: better + 1, duel: duelByRound[i], stableford: mine,
                                           isOngoing: s.round.status == .active)
        }

        var headToHead: PlayerProfile.HeadToHead?
        if let me, me != member {
            let mid = me.uuidString
            var them = 0, mine = 0
            for i in played {
                guard let p = season.roundPoints(i)[pid], let q = season.roundPoints(i)[mid] else { continue }
                if p > q { them += 1 } else if q > p { mine += 1 }
            }
            if them + mine > 0 { headToHead = .init(them: them, me: mine) }
        }

        return PlayerProfile(row: row, stablefordTotal: season.stablefordTotal(for: pid), roundsPlayed: played.count,
                             average: average, best: points.max(), birdies: birdies(member),
                             longestDrive: longestDrive(member), rounds: lines, headToHead: headToHead)
    }
}

nonisolated extension PlayerProfile {
    /// «4,5 fra 5 dueller · 1 fra sidepremier · +3 hull» (`TavlaStandings.basis`).
    func basis(_ standings: TavlaStandings) -> String? {
        standings.basis(row)
    }

    /// «2–1 til Bjørn», «1–2 til deg», «1–1 · uavgjort».
    func headToHeadText(name: String) -> String? {
        guard let h = headToHead else { return nil }
        if h.them == h.me { return "\(h.them)–\(h.me) · uavgjort" }
        return h.them > h.me ? "\(h.them)–\(h.me) til \(name)" : "\(h.me)–\(h.them) til deg"
    }
}
