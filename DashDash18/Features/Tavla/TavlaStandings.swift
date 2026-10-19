import Foundation
import GolfgutuCore

/// Alt Tavla henter for én sesong, slik databasen leverer det. Rene rader, ingen poeng.
nonisolated struct TavlaInput: Equatable, Sendable {
    var season: SeasonRow
    /// Hele troppen, alle statuser (en arkivert spiller kan ha spilt tidligere i sesongen).
    var members: [ClubMemberRow]
    /// Sesongens runder med alt under. Kladder tas ikke med i tabellen.
    var rounds: [RoundSnapshot]
    /// Neste kveld i sesongen som ikke er spilt (`YYYY-MM-DD`), fra `events`. Nil uten en.
    var nextEventDate: String? = nil
}

/// Tavla for én sesong: tabellen, spillerprofilene og oppsummeringen. Alle tall regnes av
/// GolfgutuCore (`Season`) etter sesongens regelsett. Ren, uten nettverk og SwiftUI.
nonisolated struct TavlaStandings: Sendable {
    /// En rad i tabellen.
    struct Row: Identifiable, Hashable, Sendable {
        let memberID: UUID
        let name: String
        /// Plassen fra `Season.standings`: delt plass har samme nummer (1, 1, 3). For en som ikke er
        /// kvalifisert (`table.minEvenings`): plassen i rekkefølgen, under de rangerte (vises som «–»).
        let place: Int
        /// Duell (eller stablefordpoeng) + sidepremier, avrundet etter regelsettet.
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
        /// Tellende stablefordpoeng (vektet) når tabellen teller stableford, ellers 0.
        var roundPoints: Double = 0
        /// Spilte runder når tabellen teller stableford (spilte matcher ellers).
        var played: Int = 0
        /// Har spilt nok kvelder til å få plass (`table.minEvenings`). Alltid sann uten grense.
        var qualified: Bool = true
        /// Delt førsteplass som skal avgjøres med playoff (`tieRule` `playoff`).
        var playoffPending: Bool = false

        var id: UUID { memberID }
    }

    let seasonName: String
    /// Sesongens id (TV-koden finner turneringen fra den, sql/041).
    let seasonID: UUID
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

    /// Playoff-runden om førsteplassen (sql/047), når den finnes. Står ikke blant `snapshots`.
    let playoff: PlayoffState?
    /// De som deler førsteplassen og venter på playoff, i tabellens rekkefølge.
    let tiedForFirst: [UUID]
    /// En runde som går, skjuler de siste hullene for deg (sql/047).
    let hidesLastHoles: Bool
    /// Plassene før siste kveld (samme regelmotor, uten den kvelden), for bevegelsen i tabellen.
    /// Nil før andre kveld, og når tabellen før den ikke hadde plasser.
    let previousPlaces: [UUID: Int]?
    /// Neste kveld som ikke er spilt (`YYYY-MM-DD`).
    let nextEventDate: String?
    /// Radene slik tabellen på Tavla viser dem: ett lag per rad når alle rundene spilles med én ball
    /// per lag og de samme lagene (`TavlaTeams`), ellers `rows`.
    let boardRows: [Row]
    /// `previousPlaces` for `boardRows` (plassen blant lagene i lagtabellen).
    let boardPreviousPlaces: [UUID: Int]?
    /// Tabellen står med ett lag per rad.
    let isTeamBoard: Bool

    /// - Parameter viewer: den som ser på. Med «skjul de tre siste hullene» ser andre enn båsen din og
    ///   arrangøren (`isOrganizer`: rettigheten `rounds`) rundene uten de siste hullene til de er låst.
    ///   nil: alt vises (tabellen regnes for et varsel etter låsing).
    /// - Parameter comparesPrevious: regn også tabellen før siste kveld (`previousPlaces`). Av som standard:
    ///   det er en ekstra utregning av sesongen, og bare Tavla viser bevegelsen.
    init(_ input: TavlaInput, me: UUID?, viewer: Viewer? = nil, comparesPrevious: Bool = false) {
        self.me = me
        nextEventDate = input.nextEventDate
        seasonName = input.season.name
        seasonID = input.season.id
        status = input.season.status
        rules = input.season.rules

        // En playoff (sql/047) er ingen vanlig runde: den teller ikke og står ikke i «Alle runder».
        let visible = input.rounds.map { HiddenHoles.apply($0, viewer: viewer) }
        hidesLastHoles = input.rounds.contains { HiddenHoles.isHiding($0, viewer: viewer) }
        let snapshots = visible.ordinary
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

        let withPointsIndices = rounds.indices.filter { !season.roundPoints($0).isEmpty }
        let withPoints = withPointsIndices.map { rounds[$0] }
        eveningsPlayed = Season.eveningCount(withPoints)

        // Tabellen før siste kveld: de samme rundene uten den kvelden (og uten playoff), regnet likt.
        if comparesPrevious, eveningsPlayed >= 2,
           let last = withPointsIndices.compactMap({ snapshots[$0].eventDate }).max() {
            var before = input
            before.rounds = input.rounds.ordinary.filter { ($0.eventDate ?? "") < last }
            let earlier = TavlaStandings(before, me: me, viewer: viewer, comparesPrevious: false)
            previousPlaces = earlier.hasResults
                ? Dictionary(earlier.rows.filter(\.qualified).map { ($0.memberID, $0.place) }, uniquingKeysWith: { a, _ in a })
                : nil
        } else {
            previousPlaces = nil
        }

        // Plassene fra motoren: delt plass (1, 1, 3), de uten nok kvelder nederst, og playoff om
        // førsteplassen. Vinneren av playoff-runden (`Playoff.decide`) går inn i tabellen.
        let pending = season.standings()
        let tied = PlayoffRules.tied(pending)
        tiedForFirst = tied.compactMap(UUID.init(uuidString:))
        let playoff = PlayoffRules.current(input.rounds, competitionID: nil).map {
            PlayoffState(snapshot: $0, tied: tied.compactMap(UUID.init(uuidString:)))
        }
        self.playoff = playoff
        let winner = PlayoffRules.winner(playoff, tied: tied)
        let standings = winner.map { season.standings(playoffWinner: $0) } ?? pending
        rows = standings.enumerated().map { i, s in
            let r = s.row
            let id = UUID(uuidString: r.player.id)!
            let played = rounds.indices.filter { season.roundPoints($0)[r.player.id] != nil }.map { rounds[$0] }
            return Row(memberID: id, name: r.player.name, place: s.place ?? i + 1, total: r.total, duel: r.duel,
                       side: r.side, matches: r.matches, holes: r.holes, stableford: r.stableford,
                       evenings: Season.eveningCount(played), isMe: id == me, roundPoints: r.roundPoints,
                       played: r.played, qualified: s.place != nil, playoffPending: s.playoffPending)
        }
        if let teams = TavlaTeams.fixedTeams(snapshots) {
            let merged = TavlaTeams.merge(rows, previous: previousPlaces, teams: teams, me: me)
            boardRows = merged.rows
            boardPreviousPlaces = merged.previous
            isTeamBoard = true
        } else {
            boardRows = rows
            boardPreviousPlaces = previousPlaces
            isTeamBoard = false
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

    /// Teller tabellen stableford (en stableford-serie)? Da finnes ingen dueller, matcher eller hull.
    var countsStableford: Bool { rules.table.pointsSource == .stableford }

    /// Linja under navnet: «+3 hull · 112 stableford · 4 kvelder» med matcher, og «6 kvelder · beste 5
    /// teller» med stableford. «Playoff · » foran ved delt førsteplass som avgjøres med playoff, og
    /// «· minst 4 kvelder for plass» bak for en som ikke har spilt nok.
    func detail(_ row: Row) -> String {
        var text = baseDetail(row)
        if row.playoffPending { text = "Playoff · " + text }
        if !row.qualified, let min = rules.table.minEvenings {
            text += " · minst \(rules.day.count(min)) for plass"
        }
        return text
    }

    private func baseDetail(_ row: Row) -> String {
        let evenings = rules.day.count(row.evenings)
        guard countsStableford else {
            let holes = row.holes > 0 ? "+\(row.holes)" : "\(row.holes)"
            return "\(holes) hull · \(row.stableford) stableford · \(evenings)"
        }
        let counting = rules.table.counting
        guard let best = counting.best else { return evenings }
        let noun = RuleNames.nouns(counting.unit, term: rules.day)
        return best == 1 ? "\(evenings) · beste \(noun.definite) teller" : "\(evenings) · beste \(best) teller"
    }

    /// Kolonnene i «Runde for runde» på profilen.
    var roundColumns: String { countsStableford ? "plass · stableford" : "plass · duell · stableford" }

    /// Hva poengene kommer fra: «4,5 fra 5 dueller · 1 fra sidepremier · +3 hull», eller med
    /// stableford «98 fra 5 runder · 1 fra sidepremier». Nil uten poeng.
    func basis(_ row: Row) -> String? {
        var parts: [String] = []
        if countsStableford {
            guard row.played > 0 || row.side > 0 else { return nil }
            if row.played > 0 {
                parts.append("\(points(row.roundPoints)) fra \(row.played == 1 ? "én runde" : "\(row.played) runder")")
            }
            if row.side > 0 { parts.append("\(points(row.side)) fra sidepremier") }
            return parts.joined(separator: " · ")
        }
        guard row.matches > 0 || row.side > 0 else { return nil }
        if row.matches > 0 {
            parts.append("\(points(row.duel)) fra \(row.matches == 1 ? "én duell" : "\(row.matches) dueller")")
        }
        if row.side > 0 { parts.append("\(points(row.side)) fra sidepremier") }
        if row.matches > 0 { parts.append("\(row.holes > 0 ? "+" : "")\(row.holes) hull") }
        return parts.joined(separator: " · ")
    }

    /// Minst én kveld har gitt poeng. Før det er tabellen bare troppen i navnerekkefølge: ingen
    /// plasser, ingenting å dele, og ingen topp 3 i widgeten.
    var hasResults: Bool { eveningsPlayed > 0 && !rows.isEmpty }

    /// Plassen slik tabellen viser den: «3.» (delt plass: «1.», «1.», «3.»), eller «–» før første kveld
    /// og for en som ikke har spilt nok kvelder.
    func placeText(_ row: Row) -> String {
        hasResults && row.qualified ? "\(row.place)." : "–"
    }

    /// Står spilleren på pallen (plass 1–3)? Ikke de uten plass.
    func isOnPodium(_ row: Row) -> Bool {
        row.qualified && row.place <= 3
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
        let day = DayTerm.capitalized(rules.day.one)
        return sameEvening ? "\(day) \(number) · runde \(s.round.roundNo)" : "\(day) \(number)"
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
