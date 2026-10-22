import Foundation
import GolfgutuCore

/// Lagtabellen på Tavla: spilles alle rundene i en form med ett kort per lag (scramble, foursome …)
/// med de samme lagene, står hvert lag på én rad («Anders, Bjørn, Cato og Dag») i stedet for at hver
/// spiller står med lagets poeng. Poengene og rekkefølgen er motorens (`Season.standings`); bare
/// visningen slås sammen. Ren, uten SwiftUI.
nonisolated enum TavlaTeams {
    /// Lagene når alle rundene har én ball per lag og de samme lagene, hvert lag sortert på navn.
    /// nil ellers (ingen runder, en runde med hver sin ball, lag som er byttet, eller en uten lag).
    static func fixedTeams(_ snapshots: [RoundSnapshot]) -> [Set<UUID>]? {
        var partition: Set<Set<UUID>>?
        for s in snapshots {
            guard CompetitionForm.form(id: s.round.format).card == .perTeam, !s.players.isEmpty else { return nil }
            var teams: [Int: Set<UUID>] = [:]
            for p in s.players {
                guard let team = p.teamNo else { return nil }
                teams[team, default: []].insert(p.memberID)
            }
            let these = Set(teams.values)
            if let partition, partition != these { return nil }
            partition = these
        }
        guard let partition, partition.contains(where: { $0.count > 1 }) else { return nil }
        return Array(partition)
    }

    /// Radene slått sammen per lag, i tabellens rekkefølge. Laget får plassen blant lagene (delt plass
    /// som før: 1, 1, 3), og navnet er lagets spillere i norsk rekkefølge. Spillere uten lag står alene.
    /// `previous`: plassene før siste kveld, regnet om på samme måte.
    static func merge(_ rows: [TavlaStandings.Row], previous: [UUID: Int]?, teams: [Set<UUID>],
                      me: UUID?) -> (rows: [TavlaStandings.Row], previous: [UUID: Int]?) {
        let teamOf = Dictionary(teams.flatMap { team in team.map { ($0, team) } }, uniquingKeysWith: { a, _ in a })
        var seen: Set<UUID> = []
        var groups: [[TavlaStandings.Row]] = []
        for row in rows where !seen.contains(row.memberID) {
            let members = teamOf[row.memberID] ?? [row.memberID]
            seen.formUnion(members)
            groups.append(rows.filter { members.contains($0.memberID) }
                .sorted { NorwegianSort.areInIncreasingOrder($0.name, $1.name) })
        }

        // Plassen blant lagene: 1 + antall lag med bedre plass hos motoren.
        let leaders = groups.map { $0[0] }
        func rank(_ place: Int, among places: [Int]) -> Int { 1 + places.filter { $0 < place }.count }
        let qualifiedPlaces = leaders.filter(\.qualified).map(\.place)
        // De uten plass (for få kvelder) står nederst, med plassen i rekkefølgen som hos motoren.
        let rows = groups.enumerated().map { i, group -> TavlaStandings.Row in
            let r = group[0]
            return TavlaStandings.Row(
                memberID: r.memberID, name: RuleFormat.list(group.map(\.name)),
                place: r.qualified ? rank(r.place, among: qualifiedPlaces) : i + 1,
                total: r.total, duel: r.duel, side: r.side, matches: r.matches, holes: r.holes,
                stableford: r.stableford, evenings: r.evenings,
                isMe: me.map { me in group.contains { $0.memberID == me } } ?? false,
                roundPoints: r.roundPoints, played: r.played, qualified: r.qualified,
                playoffPending: r.playoffPending, adjustment: r.adjustment)
        }

        let before = previous.map { previous -> [UUID: Int] in
            let places = leaders.compactMap { previous[$0.memberID] }
            return Dictionary(leaders.compactMap { l in previous[l.memberID].map { (l.memberID, rank($0, among: places)) } },
                              uniquingKeysWith: { a, _ in a })
        }
        return (rows, before)
    }
}
