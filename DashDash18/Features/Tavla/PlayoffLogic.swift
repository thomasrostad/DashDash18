import Foundation
import GolfgutuCore

/// Playoff om førsteplassen (sql/047, `rounds.kind = playoff`). Ren logikk uten nettverk og SwiftUI.
///
/// Playoff-runden har samme bane og antall hull som turneringens runder. `playoff_holes[i]` er
/// rundehullet (0-basert) som spilles som playoff-hull nummer i, og scoren for nummer i lagres med
/// `hole_index = i` (posisjonen). Samme hull kan spilles flere ganger (forslaget er siste, første,
/// siste). Vinneren regnes av `Playoff.decide` og gis til `Season.standings(playoffWinner:)`.
nonisolated struct PlayoffState: Sendable {
    /// Ett playoff-hull: posisjonen i rekkefølgen og hullet på banen.
    struct Hole: Equatable, Sendable, Identifiable {
        /// 0-basert posisjon (`hole_scores.hole_index`).
        let position: Int
        /// Rundens 0-baserte hull.
        let holeIndex: Int
        /// Nummeret på scorekortet.
        let number: Int
        let par: Int
        let strokeIndex: Int

        var id: Int { position }
    }

    let snapshot: RoundSnapshot
    /// De som står likt øverst, i tabellens rekkefølge (bare de som er med i playoffen).
    let players: [UUID]
    let holes: [Hole]
    let decision: Playoff.Decision

    /// - Parameters:
    ///   - snapshot: playoff-runden.
    ///   - tied: de som står likt øverst i tabellen, i tabellens rekkefølge. Tom: spillerne i runden.
    init(snapshot: RoundSnapshot, tied: [UUID] = []) {
        self.snapshot = snapshot
        let inRound = snapshot.players.map(\.memberID)
        let ordered = tied.isEmpty ? inRound : tied.filter(inRound.contains)
        players = ordered
        let game = RoundGame(snapshot)
        let course = game.holes
        holes = (snapshot.round.playoffHoles ?? []).enumerated().compactMap { position, hole in
            guard course.indices.contains(hole) else { return nil }
            return Hole(position: position, holeIndex: hole, number: game.holeNumber(hole),
                        par: course[hole].par, strokeIndex: course[hole].strokeIndex)
        }
        decision = Playoff.decide(players: ordered.map(\.uuidString), holes: snapshot.round.playoffHoles ?? [],
                                  scores: Self.scores(snapshot), round: game.round, roster: game.roster,
                                  rules: snapshot.rules)
    }

    /// Bruttoslag per spiller i posisjonsrekkefølge (posisjon → slag), sammenhengende fra første
    /// posisjon. En posisjon uten score avslutter lista (`Playoff.decide` venter på den).
    static func scores(_ snapshot: RoundSnapshot) -> [String: [Int]] {
        var byMember: [UUID: [Int: Int]] = [:]
        for row in snapshot.scores { byMember[row.memberID, default: [:]][row.holeIndex] = row.strokes }
        return Dictionary(uniqueKeysWithValues: byMember.map { member, positions in
            var list: [Int] = []
            while let strokes = positions[list.count] { list.append(strokes) }
            return (member.uuidString, list)
        })
    }

    /// Vinneren, når playoffen er avgjort.
    var winner: UUID? {
        if case .won(let id, _) = decision { return UUID(uuidString: id) }
        return nil
    }

    /// Posisjonen som venter på score, eller nil (avgjort, eller alle hullene er spilt).
    var nextPosition: Int? {
        if case .pending(_, let next) = decision { return next }
        return nil
    }

    /// De som fortsatt er med.
    var remaining: [UUID] {
        switch decision {
        case .won(let id, _): UUID(uuidString: id).map { [$0] } ?? []
        case .pending(let ids, _): ids.compactMap(UUID.init(uuidString:))
        }
    }

    /// Alle hullene er spilt, og det står fortsatt likt: arrangøren legger til hull.
    var needsMoreHoles: Bool {
        if case .pending(let ids, nil) = decision { return ids.count > 1 }
        return false
    }

    /// Playoff-hullet på posisjonen.
    func hole(at position: Int) -> Hole? {
        holes.indices.contains(position) ? holes[position] : nil
    }

    /// Slagene spilleren har på posisjonen.
    func strokes(_ member: UUID, at position: Int) -> Int? {
        snapshot.scores.first { $0.memberID == member && $0.holeIndex == position }?.strokes
    }

    var isLocked: Bool { snapshot.round.status == .locked }

    /// Status i én linje: «Anders vant på playoff-hull 2», «Playoff-hull 1 (hull 18)», «Fortsatt likt».
    func statusText(name: (UUID) -> String) -> String {
        switch decision {
        case .won(let id, let position):
            let who = UUID(uuidString: id).map(name) ?? "Ukjent"
            return "\(who) vant på playoff-hull \(position + 1)"
        case .pending(_, let next?):
            guard holes.indices.contains(next) else { return "Playoff-hull \(next + 1)" }
            return "Playoff-hull \(next + 1) (hull \(holes[next].number))"
        case .pending:
            return "Fortsatt likt"
        }
    }

    /// Hullene etter at ett til er lagt til: veksler mellom siste og første hull, som forslaget.
    static func extended(_ holes: [Int], holeCount: Int) -> [Int] {
        let last = holeCount - 1
        let next = holes.last == last ? 0 : last
        return holes + [next]
    }
}

/// Hvem som ser «Start playoff», og hvilken playoff som gjelder for tabellen.
nonisolated enum PlayoffRules {
    /// Arrangøren med rettigheten `tournaments` eller `rounds` (create_playoff_round sjekker selv).
    static func canStart(rights: ClubRights) -> Bool {
        rights.has(.tournaments) || rights.has(.rounds)
    }

    /// Playoff-runden for turneringen: den som går, ellers den sist startede (låst). Kladder teller ikke.
    /// - Parameter competitionID: turneringen. nil: alle playoffene i rundene (Tavla henter rundene på
    ///   sesongens kvelder, og en playoff på en kveld hører alltid til kveldens turnering).
    static func current(_ snapshots: [RoundSnapshot], competitionID: UUID?) -> RoundSnapshot? {
        let mine = snapshots.filter {
            $0.round.isPlayoff && $0.round.status != .draft
                && (competitionID == nil || $0.round.playoffFor == competitionID)
        }
        if let active = mine.first(where: { $0.round.status == .active }) { return active }
        return mine.max { ($0.round.startedAt ?? .distantPast) < ($1.round.startedAt ?? .distantPast) }
    }

    /// Spillerne som deler førsteplassen og venter på playoff, i tabellens rekkefølge.
    static func tied(_ standings: [Season.Standing]) -> [String] {
        standings.filter(\.playoffPending).map(\.row.player.id)
    }

    /// Vinneren som skal inn i tabellen: bare når playoffen er avgjort og alle som står likt, var med.
    static func winner(_ playoff: PlayoffState?, tied: [String]) -> String? {
        guard let playoff, let winner = playoff.winner, tied.count > 1 else { return nil }
        let inRound = Set(playoff.snapshot.players.map(\.memberID.uuidString))
        guard tied.allSatisfy(inRound.contains), tied.contains(winner.uuidString) else { return nil }
        return winner.uuidString
    }
}

/// Playoff i liga og morroturnering (sql/047: `create_playoff_round` tillater dem med `tieRule =
/// playoff`). Tabellen regnes av `League.table`, som ikke kjenner playoffen; vinneren settes inn her
/// med samme regel som `Season.standings(playoffWinner:)`: vinneren først med plass 1, resten av
/// gruppa som delte førsteplassen deler andreplassen.
nonisolated enum LeaguePlayoff {
    /// Spilleren i playoff-runden for en deltaker: medlems-id, eller deltakeren med profilen i en
    /// runde uten klubb (`round_roster`).
    static func roundPlayer(_ entrant: Entrant, in snapshot: RoundSnapshot) -> UUID? {
        switch entrant {
        case .member(let id): snapshot.players.contains { $0.memberID == id } ? id : nil
        case .profile(let id): snapshot.loose?.roster.first { $0.profileID == id }?.playerID
        case .guest: nil
        }
    }

    /// Plassene etter playoffen. Uendret uten avgjort playoff, eller når ikke alle som deler
    /// førsteplassen var med.
    static func apply(places: [(entrant: Entrant, place: Int)], playoff snapshot: RoundSnapshot?) -> [Entrant: Int] {
        var out = Dictionary(places.map { ($0.entrant, $0.place) }, uniquingKeysWith: { first, _ in first })
        guard let snapshot else { return out }
        let group = places.filter { $0.place == 1 }.map(\.entrant)
        guard group.count > 1 else { return out }
        let players = group.map { roundPlayer($0, in: snapshot) }
        guard players.allSatisfy({ $0 != nil }) else { return out }
        let state = PlayoffState(snapshot: snapshot, tied: players.compactMap(\.self))
        guard let winner = state.winner, let i = players.firstIndex(of: winner) else { return out }
        for entrant in group { out[entrant] = 2 }
        out[group[i]] = 1
        return out
    }
}
