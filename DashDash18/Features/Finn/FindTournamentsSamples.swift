#if DEBUG
import Foundation

/// Oppdiktede åpne turneringer til skjermprøven `finn`.
enum FindTournamentsSamples {
    static let rows: [PublicCompetitionRow] = [
        row(1, .league, "Vinterserien", club: "Golfstudio Bryn", venue: "Golfstudio Bryn", from: "2026-10-15",
            to: "2026-12-17", max: 24, entrants: 18, waitlist: 0),
        row(2, .cup, "Bryn Cup", club: "Golfstudio Bryn", venue: nil, from: "2026-11-01", to: nil, max: 16,
            entrants: 16, waitlist: 3),
        row(3, .fun, "Fredagsmorro", club: "Losby Golfklubb", venue: "Losby simulatorsenter", from: nil, to: nil,
            max: nil, entrants: 7, waitlist: 0),
    ]

    private static func row(_ n: Int, _ kind: CompetitionKind, _ name: String, club: String, venue: String?,
                            from: String?, to: String?, max: Int?, entrants: Int, waitlist: Int) -> PublicCompetitionRow {
        let json = """
        {"id": "00000000-0000-0000-0000-00000000000\(n)", "kind": "\(kind.rawValue)", "name": "\(name)",
         "club_id": null, "club_name": "\(club)", "status": "active",
         "starts_on": \(from.map { "\"\($0)\"" } ?? "null"), "ends_on": \(to.map { "\"\($0)\"" } ?? "null"),
         "venue": \(venue.map { "\"\($0)\"" } ?? "null"), "max_entrants": \(max.map(String.init) ?? "null"),
         "entrants": \(entrants), "waitlist": \(waitlist), "signup_open": true, "waitlist_enabled": true}
        """
        return try! JSONDecoder().decode(PublicCompetitionRow.self, from: Data(json.utf8))
    }
}
#endif
