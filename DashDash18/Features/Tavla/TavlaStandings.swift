import Foundation
import GolfgutuCore

/// Alt Tavla henter for én sesong, slik databasen leverer det. Rene rader, ingen poeng.
nonisolated struct TavlaInput: Equatable, Sendable {
    var season: SeasonRow
    /// Hele troppen, alle statuser (en arkivert spiller kan ha spilt tidligere i sesongen).
    var members: [ClubMemberRow]
    /// Sesongens runder med alt under. Kladder tas ikke med i tabellen.
    var rounds: [RoundSnapshot]
}

/// Tavla for én sesong: tabellen, spillerprofilene og oppsummeringen. Alle tall regnes av
/// GolfgutuCore (`Season`) etter sesongens regelsett. Ren, uten nettverk og SwiftUI.
nonisolated struct TavlaStandings: Sendable {
    /// En rad i tabellen.
    struct Row: Identifiable, Hashable, Sendable {
        let memberID: UUID
        let name: String
        /// 1, 2, 3 … i tabellens rekkefølge (`jakketavle`).
        let place: Int
        /// Duell + sidepremier, avrundet etter regelsettet.
        let total: Double
        let duel: Double
        let side: Double
        /// Tellende matcher.
        let matches: Int
        /// Hulldifferansen i de tellende matchene.
        let holes: Int
        /// Stablefordsummen etter regelsettet (skilletegn).
        let stableford: Int
        /// Kvelder spilleren har poeng i.
        let evenings: Int
        let isMe: Bool

        var id: UUID { memberID }
    }

    let seasonName: String
    let status: SeasonStatus
    let rules: Ruleset
    let rows: [Row]
    /// Kvelder med poeng (to runder samme dato er én kveld).
    let eveningsPlayed: Int
    /// Kvelder i sesongen, fra regelsettet.
    var eveningsTotal: Int { rules.evenings }
    let me: UUID?

    /// Rundene som teller, i tidsrekkefølge (dato, så rundenummer). Samme rekkefølge som i `season`.
    let snapshots: [RoundSnapshot]
    let season: Season
    let claims: [SideClaim]

    init(_ input: TavlaInput, me: UUID?) {
        self.me = me
        seasonName = input.season.name
        status = input.season.status
        rules = input.season.rules

        let snapshots = input.rounds
            .filter { $0.round.status != .draft }
            .sorted { a, b in
                let da = a.eventDate ?? "", db = b.eventDate ?? ""
                return da != db ? da < db : a.round.roundNo < b.round.roundNo
            }
        self.snapshots = snapshots
        let rounds = snapshots.map(RoundGame.makeRound)
        claims = snapshots.flatMap(\.sideClaims).map(TavlaStandings.claim)

        // Troppen: aktive medlemmer, pluss alle som har spilt en runde i sesongen.
        let playedIDs = Set(snapshots.flatMap { $0.players.map(\.memberID) })
        let roster = input.members
            .filter { $0.status == .active || playedIDs.contains($0.id) }
            .sorted { NorwegianSort.areInIncreasingOrder($0.displayName, $1.displayName) }
            .map { m in Player(id: m.id.uuidString, name: m.displayName, handicap: m.handicapIndex, seedGroup: m.seedGroup) }

        // Hver runde regnes med handicapet som ble frosset i den (som Kveld), ikke troppens tall i dag.
        let season = Season(players: roster, rounds: rounds, claims: claims, ruleset: input.season.rules,
                            playingHandicaps: TavlaStandings.playingHandicaps(snapshots))
        self.season = season

        let withPoints = rounds.indices.filter { !season.roundPoints($0).isEmpty }.map { rounds[$0] }
        eveningsPlayed = Season.eveningCount(withPoints)

        rows = season.jacketBoard().enumerated().map { i, r in
            let id = UUID(uuidString: r.player.id)!
            let played = rounds.indices.filter { season.roundPoints($0)[r.player.id] != nil }.map { rounds[$0] }
            return Row(memberID: id, name: r.player.name, place: i + 1, total: r.total, duel: r.duel, side: r.side,
                       matches: r.matches, holes: r.holes, stableford: r.stableford,
                       evenings: Season.eveningCount(played), isMe: id == me)
        }
    }

    // MARK: Hjelpere

    static func claim(_ row: SideClaimRow) -> SideClaim {
        SideClaim(id: row.id.uuidString, kind: row.kind == .drive ? .drive : .kp, playerId: row.memberID.uuidString,
                  roundId: row.roundID.uuidString, meters: row.meters, holeIndex: row.holeIndex, ts: row.timestamp)
    }

    /// Rundens frosne handicap per spiller, runde-id → spiller-id → slag: samme regel som Kveld
    /// (`RoundGame.handicap`): `playing_handicap` når den er lagret, ellers `effectiveHandicap` med
    /// rundens frosne indeks og seedede gruppe fra `round_players`.
    static func playingHandicaps(_ snapshots: [RoundSnapshot]) -> [String: [String: Double]] {
        var out: [String: [String: Double]] = [:]
        for snapshot in snapshots {
            let game = RoundGame(snapshot)
            out[snapshot.round.id.uuidString] = Dictionary(
                snapshot.players.map { ($0.memberID.uuidString, game.handicap($0.memberID)) },
                uniquingKeysWith: { first, _ in first })
        }
        return out
    }

    var isEmpty: Bool { rows.isEmpty }

    /// Minst én kveld har gitt poeng. Før det er tabellen bare troppen i navnerekkefølge: ingen
    /// plasser, ingenting å dele, og ingen topp 3 i widgeten.
    var hasResults: Bool { eveningsPlayed > 0 && !rows.isEmpty }

    /// Plassen slik tabellen viser den: «3.», eller «–» før første kveld.
    func placeText(_ row: Row) -> String {
        hasResults ? "\(row.place)." : "–"
    }

    func row(_ member: UUID) -> Row? {
        rows.first { $0.memberID == member }
    }

    /// `fmtPoeng` med regelsettets avrunding.
    func points(_ x: Double) -> String {
        Season.formatPoints(x, rules: rules)
    }

    /// Rundens navn: det lagrede navnet, ellers «Kveld N» (og «· runde M» når kvelden har flere).
    func roundTitle(_ index: Int) -> String {
        let s = snapshots[index]
        if let name = s.round.name?.trimmingCharacters(in: .whitespaces), !name.isEmpty { return name }
        let number = season.roundNumber(for: s.eventDate)
        let sameEvening = snapshots.filter { $0.eventDate == s.eventDate }.count > 1
        return sameEvening ? "Kveld \(number) · runde \(s.round.roundNo)" : "Kveld \(number)"
    }

    /// Netto birdie eller bedre per hull gjennom sesongen (`profilTall`: netto − par ≤ −1).
    func birdies(_ member: UUID) -> Int {
        let pid = member.uuidString
        let player = season.players.first { $0.id == pid }
        var count = 0
        for round in season.rounds {
            guard let scores = round.holeScores[pid], !scores.isEmpty else { continue }
            let course = round.courseHoles()
            let hcp = Handicap.effective(for: player, in: round, roster: season.players, rules: rules)
            for (hole, gross) in scores where hole >= 0 && hole < course.count {
                let h = course[hole]
                let net = Scoring.netStrokes(gross: gross, handicap: hcp, strokeIndex: h.strokeIndex,
                                             holes: round.numberOfHoles)
                if net - h.par <= -1 { count += 1 }
            }
        }
        return count
    }

    /// Spillerens lengste innmeldte drive i sesongen.
    func longestDrive(_ member: UUID) -> Double? {
        claims.filter { $0.kind == .drive && $0.playerId == member.uuidString }.map(\.meters).max()
    }
}
