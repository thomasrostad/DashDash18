import Foundation
import Supabase

/// Fase 25: finn åpne turneringer og meld deg på, også uten klubb. Lista er `public_competitions`
/// (sql/032): bare turneringer med «åpen for alle» og «vis i lista», ikke runder eller tropp.
nonisolated enum FindTournamentsFeature {
    /// På siden 09.10.2026: 032 er kjørt på test, og påmeldingen bruker samme RPC-er som turneringssiden.
    static let isEnabled = true
}

/// En rad fra `public_competitions`.
nonisolated struct PublicCompetitionRow: Decodable, Equatable, Identifiable, Sendable {
    let id: UUID
    let kind: CompetitionKind
    let name: String
    let clubID: UUID?
    let clubName: String?
    let status: SeasonStatus
    let startsOn: String?
    let endsOn: String?
    let venue: String?
    let maxEntrants: Int?
    let entrants: Int
    let waitlist: Int
    let signupOpen: Bool
    let waitlistEnabled: Bool

    enum CodingKeys: String, CodingKey {
        case id, kind, name, status, venue, entrants, waitlist
        case clubID = "club_id"
        case clubName = "club_name"
        case startsOn = "starts_on"
        case endsOn = "ends_on"
        case maxEntrants = "max_entrants"
        case signupOpen = "signup_open"
        case waitlistEnabled = "waitlist_enabled"
    }
}

/// Tekstene og søket i lista. Rent, uten nett.
nonisolated enum FindTournaments {
    /// Søk i navn, klubb og sted, uten forskjell på store og små bokstaver. Tomt søk gir alle.
    static func filter(_ rows: [PublicCompetitionRow], query: String) -> [PublicCompetitionRow] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return rows }
        return rows.filter { row in
            [row.name, row.clubName ?? "", row.venue ?? ""].contains { $0.localizedCaseInsensitiveContains(q) }
        }
    }

    /// «12 av 16 påmeldt · 3 på venteliste», «5 påmeldt», «Fullt».
    static func places(_ row: PublicCompetitionRow) -> String {
        var text: String
        if let max = row.maxEntrants {
            text = row.entrants >= max && !row.waitlistEnabled ? "Fullt · \(row.entrants) av \(max)" : "\(row.entrants) av \(max) påmeldt"
        } else {
            text = "\(row.entrants) påmeldt"
        }
        if row.waitlist > 0 { text += " · \(row.waitlist) på venteliste" }
        return text
    }

    /// «Golfstudio Bryn · 15. okt.–20. des.» av klubb, sted og periode.
    static func subtitle(_ row: PublicCompetitionRow) -> String {
        var parts: [String] = []
        if let club = row.clubName, !club.isEmpty { parts.append(club) }
        if let venue = row.venue?.trimmingCharacters(in: .whitespaces), !venue.isEmpty, venue != row.clubName {
            parts.append(venue)
        }
        if let period = period(row) { parts.append(period) }
        return parts.joined(separator: " · ")
    }

    /// «Fra 15. oktober», «15. oktober–20. desember», eller nil.
    static func period(_ row: PublicCompetitionRow) -> String? {
        let start = row.startsOn.map(EveningDates.dayMonthText)
        let end = row.endsOn.map(EveningDates.dayMonthText)
        switch (start, end) {
        case let (s?, e?): return "\(s)–\(e)"
        case let (s?, nil): return "Fra \(s)"
        case let (nil, e?): return "Til \(e)"
        default: return nil
        }
    }

    static func load(client: SupabaseClient) async throws -> [PublicCompetitionRow] {
        try await client.rpc("public_competitions").execute().value
    }
}
