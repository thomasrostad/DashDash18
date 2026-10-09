import Foundation

/// Tavla-data i én RPC (fase 24, `sql/036_tavla_data.sql`).
nonisolated enum TavlaRPCFeature {
    /// På siden 09.10.2026: 036 er kjørt på test, og svaret er sjekket mot RLS-spørringene som medlem
    /// (alle rader like, 13 ms). Med flagget av henter Tavla som før, med ett kall per tabell og runde.
    static let isEnabled = true
}

/// Mengdebaserte RPC-er (fase 24, `sql/037_mengde_rpc.sql`): «folk du kjenner», dine løse runder,
/// turneringslista og Hjem-feeden hentes som mengder i stedet for at RLS sjekker hver rad i tabellen.
nonisolated enum SetQueriesFeature {
    /// Av til 037 er kjørt. Med flagget av hentes det rett fra tabellene som før.
    static let isEnabled = false
}

/// Rådata for én sesong, slik `tavla_data` gir dem og slik spørringene henter dem hver for seg.
/// Tabellen regnes fortsatt på telefonen, så samme rader gir samme Tavla uansett vei.
nonisolated struct TavlaData: Decodable, Equatable, Sendable {
    var events: [EventRow] = []
    var members: [ClubMemberRow] = []
    var rounds: [RoundRow] = []
    var roundHoles: [RoundHoleRow] = []
    var players: [RoundPlayerRow] = []
    var matches: [RoundMatchRow] = []
    var claims: [SideClaimRow] = []
    var courses: [CourseRow] = []
    var courseHoles: [CourseHoleRecord] = []
    var scores: [HoleScoreRow] = []

    enum CodingKeys: String, CodingKey {
        case events, members, rounds, players, matches, claims, courses, scores
        case roundHoles = "round_holes"
        case courseHoles = "course_holes"
    }

    /// Rundene som `RoundSnapshot`, med samme mapping som Kveld (`RoundGame.makeRound`).
    func input(season: SeasonRow) -> TavlaInput {
        let names = Dictionary(members.map { ($0.id, $0.displayName) }, uniquingKeysWith: { a, _ in a })
        let dates = Dictionary(events.map { ($0.id, $0.eventDate) }, uniquingKeysWith: { a, _ in a })
        let scoresByRound = Dictionary(grouping: scores, by: \.roundID)
        let snapshots = rounds.map { round in
            var s = RoundSnapshot(round: round)
            s.roundHoles = roundHoles.filter { $0.roundID == round.id }
            s.players = players.filter { $0.roundID == round.id }
            s.matches = matches.filter { $0.roundID == round.id }
            s.scores = scoresByRound[round.id] ?? []
            s.sideClaims = claims.filter { $0.roundID == round.id }
            s.course = courses.first { $0.id == round.courseID }
            s.courseHoles = courseHoles.filter { $0.courseID == round.courseID }
            s.eventDate = round.eventID.flatMap { dates[$0] }
            s.rules = season.rules
            s.names = names
            return s
        }
        return TavlaInput(season: season, members: members, rounds: snapshots)
    }
}
