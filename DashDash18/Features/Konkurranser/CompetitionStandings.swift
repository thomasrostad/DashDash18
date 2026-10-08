import Foundation
import GolfgutuCore

// Tabellene for liga, morroturnering og cup, regnet av GolfgutuCore (Competitions.swift) fra
// grunnlaget `CompetitionScope` lager. Sesongen (jakkeracet) bruker `TavlaStandings` som før.
// Ren logikk, uten nettverk og SwiftUI.

/// Liga og morroturnering: poeng per runde og beste N, etter konkurransens regler.
nonisolated struct LeagueStandings: Sendable {
    struct Row: Identifiable, Hashable, Sendable {
        let entrant: Entrant
        let name: String
        let place: Int
        let total: Double
        let played: Int
        let wins: Int
        let bestRound: Double?
        let stableford: Int
        let results: [League.RoundResult]
        let isMe: Bool

        var id: Entrant { entrant }
    }

    let competition: CompetitionRow
    let rules: LeagueRules
    let rows: [Row]
    /// Rundene som teller, i tidsrekkefølge: id → «1. okt · Pebble Beach».
    let roundTitles: [String: String]
    let roundCount: Int

    init(_ input: CompetitionInput, me: Set<Entrant>) {
        competition = input.competition
        let rules = input.competition.kind == .fun
            ? input.competition.rules.competitionRules.fun
            : input.competition.rules.competitionRules.league
        self.rules = rules
        let season = CompetitionBoard.season(input)
        let rounds = input.rounds.indices.map { i in
            League.Round(id: input.rounds[i].round.id.uuidString, stableford: season.roundPoints(i))
        }
        roundCount = rounds.count
        roundTitles = Dictionary(input.rounds.map { ($0.round.id.uuidString, Self.title($0)) },
                                 uniquingKeysWith: { first, _ in first })
        let byKey = Dictionary(zip(input.roster.map(\.id), zip(input.entrants, input.roster)),
                               uniquingKeysWith: { first, _ in first })
        rows = League.table(entrants: input.roster.map(\.id), rounds: rounds, rules: rules).compactMap { r in
            guard let (entrant, player) = byKey[r.playerID] else { return nil }
            return Row(entrant: entrant, name: player.name, place: r.place, total: r.total, played: r.played,
                       wins: r.wins, bestRound: r.bestRound, stableford: r.stableford, results: r.results,
                       isMe: me.contains(entrant))
        }
    }

    /// Minst én runde er spilt av en i tabellen.
    var hasResults: Bool { rows.contains { $0.played > 0 } }

    func placeText(_ row: Row) -> String { hasResults ? "\(row.place)." : "–" }

    /// Poeng uten unødvendige desimaler: «11», «6,5», «6,33».
    static func points(_ x: Double) -> String {
        let rounded = (x * 100).rounded() / 100
        if rounded == rounded.rounded() { return String(Int(rounded)) }
        return String(format: "%.2f", rounded)
            .replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: ".", with: ",")
    }

    func detail(_ row: Row) -> String {
        guard row.played > 0 else { return "Ingen runder ennå" }
        var parts = [row.played == 1 ? "1 runde" : "\(row.played) runder"]
        if let best = rules.bestRounds, row.played > best { parts.append("beste \(best) teller") }
        if row.wins > 0 { parts.append(row.wins == 1 ? "1 seier" : "\(row.wins) seire") }
        parts.append("\(row.stableford) stableford")
        return parts.joined(separator: " · ")
    }

    /// «Plassering 10–8–6 … + 1 for å spille · alle runder teller».
    var rulesSummary: String {
        var parts: [String] = []
        switch rules.scoring {
        case .placement:
            let list = rules.placementPoints.prefix(3).map(Self.points).joined(separator: "–")
            parts.append("Plassering \(list)\(rules.placementPoints.count > 3 ? " …" : "")")
        case .stableford:
            parts.append("Stablefordpoeng")
        }
        if rules.participationPoints > 0 { parts.append("+ \(Self.points(rules.participationPoints)) for å spille") }
        parts.append(rules.bestRounds.map { "beste \($0) runder teller" } ?? "alle runder teller")
        return parts.joined(separator: " · ")
    }

    static func title(_ s: RoundSnapshot) -> String {
        let date = s.eventDate.map(CompetitionText.shortDate)
        let own = s.round.name?.trimmingCharacters(in: .whitespaces)
        let name = own?.isEmpty == false ? own : s.course?.name
        return [date, name].compactMap(\.self).joined(separator: " · ")
    }
}

/// Cupen: treet fra trekningen og resultatene, med navn og «din neste kamp».
nonisolated struct CupStandings: Sendable {
    struct Side: Hashable, Sendable {
        let participantID: UUID
        let name: String
        let seed: Int?
        let isMe: Bool
    }

    struct Game: Identifiable, Hashable, Sendable {
        let round: Int
        let slot: Int
        let a: Side?
        let b: Side?
        let winner: UUID?
        let isBye: Bool
        let walkover: Bool
        let result: String?
        let state: Cup.Match.State

        var id: String { "\(round):\(slot)" }
    }

    let rounds: [[Game]]
    let champion: Side?
    var isDrawn: Bool { !rounds.isEmpty }
    /// Din neste kamp (klar eller venter på motstander).
    let myNext: Game?
    let bracket: Cup.Bracket

    /// `names`: påmeldt → navn. `me`: påmeldingene dine.
    init(participants: [CompetitionParticipantRow], matches: [CompetitionMatchRow], names: [UUID: String], me: Set<UUID>) {
        let first = matches.filter { $0.roundNo == 1 }.sorted { $0.slot < $1.slot }
        let draw = first.compactMap { m in m.playerA.map { Cup.Pairing(slot: m.slot, a: $0.uuidString, b: m.playerB?.uuidString) } }
        let results = matches.filter { $0.winner != nil && !($0.roundNo == 1 && $0.playerB == nil) }.map {
            Cup.Result(round: $0.roundNo, slot: $0.slot, winner: $0.winner!.uuidString, walkover: $0.walkover)
        }
        let bracket = Cup.bracket(draw: draw, results: results)
        self.bracket = bracket

        // Seedene følger plassene i første runde (seedPositions).
        let positions = Cup.seedPositions(size: bracket.size)
        var seeds: [String: Int] = [:]
        for p in draw where p.slot * 2 + 1 < positions.count {
            let x = min(positions[p.slot * 2], positions[p.slot * 2 + 1])
            let y = max(positions[p.slot * 2], positions[p.slot * 2 + 1])
            seeds[p.a] = x
            if let b = p.b { seeds[b] = y }
        }
        let texts = Dictionary(matches.map { ("\($0.roundNo):\($0.slot)", $0.result) }, uniquingKeysWith: { first, _ in first })
        func side(_ id: String?) -> Side? {
            guard let id, let uuid = UUID(uuidString: id) else { return nil }
            return Side(participantID: uuid, name: names[uuid] ?? "Ukjent", seed: seeds[id], isMe: me.contains(uuid))
        }
        let games = bracket.rounds.map { round in
            round.map { m in
                Game(round: m.round, slot: m.slot, a: side(m.a), b: side(m.b), winner: m.winner.flatMap(UUID.init),
                     isBye: m.isBye, walkover: m.walkover, result: texts["\(m.round):\(m.slot)"] ?? nil, state: m.state)
            }
        }
        rounds = games
        champion = side(bracket.champion)
        let next = me.map(\.uuidString).sorted().lazy.compactMap { id in bracket.nextMatch(for: id) }.first
        myNext = next.map { games[$0.round - 1][$0.slot] }
    }

    var roundTitles: [String] {
        rounds.indices.map { CompetitionText.cupRound($0 + 1, of: rounds.count) }
    }

    /// Første runde for trekningen: de aktive påmeldte seedet etter cupens regel.
    /// `handicaps` og `ranks` per påmeldt; `seed` gjør trekningen gjentakbar.
    static func pairings(participants: [CompetitionParticipantRow], names: [UUID: String], handicaps: [UUID: Double],
                         ranks: [UUID: Int], rules: CupRules, seed: UInt64) -> [CupPairingParam] {
        let entrants = participants.filter { $0.status == .active }.map { p in
            Cup.Entrant(id: p.id.uuidString, name: names[p.id] ?? "", handicap: handicaps[p.id], rank: ranks[p.id])
        }
        let seeded = Cup.seeded(entrants, rules: rules, randomSeed: seed)
        return Cup.draw(seeded: seeded).compactMap { p in
            guard let a = UUID(uuidString: p.a) else { return nil }
            return CupPairingParam(slot: p.slot, a: a, b: p.b.flatMap(UUID.init))
        }
    }

    /// Forslaget til resultat fra den siste tellende runden begge spilte, som matchspill etter
    /// konkurransens regler. Nil når de ikke har spilt sammen.
    static func suggestion(for game: Game, input: CompetitionInput, entrantOf: (UUID) -> Entrant?)
        -> (roundID: UUID, decision: Cup.Decision)? {
        guard let a = game.a, let b = game.b, let ea = entrantOf(a.participantID), let eb = entrantOf(b.participantID)
        else { return nil }
        let seeds = [ea.key: a.seed, eb.key: b.seed].compactMapValues(\.self)
        for snapshot in input.rounds.reversed() {
            let ids = Set(snapshot.players.map(\.memberID))
            guard ids.contains(ea.id), ids.contains(eb.id) else { continue }
            let game = RoundGame(snapshot)
            let decision = Cup.decide(a: ea.key, b: eb.key, in: game.round, roster: game.roster,
                                      rules: input.competition.rules, seeds: seeds)
            return (snapshot.round.id, decision)
        }
        return nil
    }
}
