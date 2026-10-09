import Foundation
import Testing
@testable import DashDash18

/// Fase 25: finn åpne turneringer.
struct FindTournamentsTests {
    static func row(name: String = "Vinterserien", club: String? = "Golfstudio Bryn", venue: String? = nil,
                    from: String? = "2026-10-15", to: String? = "2026-12-17", max: Int? = 24, entrants: Int = 18,
                    waitlist: Int = 0, waitlistEnabled: Bool = true) throws -> PublicCompetitionRow {
        var object: [String: Any] = ["id": UUID().uuidString, "kind": "league", "name": name, "status": "active",
                                     "entrants": entrants, "waitlist": waitlist, "signup_open": true,
                                     "waitlist_enabled": waitlistEnabled]
        object["club_name"] = club; object["venue"] = venue; object["starts_on"] = from; object["ends_on"] = to
        object["max_entrants"] = max
        let data = try JSONSerialization.data(withJSONObject: object)
        return try JSONDecoder().decode(PublicCompetitionRow.self, from: data)
    }

    @Test func svaretFraPublicCompetitions() throws {
        let json = #"[{"id": "00000000-0000-0000-0000-000000000001", "kind": "cup", "name": "Bryn Cup", "club_id": "00000000-0000-0000-0000-000000000002", "club_name": "Golfstudio Bryn", "club_kind": "simulator_center", "status": "planned", "starts_on": "2026-11-01", "ends_on": null, "venue": null, "max_entrants": 16, "entrants": 16, "waitlist": 3, "signup_open": true, "waitlist_enabled": true, "signup_opens_at": null, "signup_closes_at": null}]"#
        let rows = try JSONDecoder().decode([PublicCompetitionRow].self, from: Data(json.utf8))
        #expect(rows.first?.kind == .cup && rows.first?.entrants == 16)
    }

    @Test func plassene() throws {
        #expect(FindTournaments.places(try Self.row()) == "18 av 24 påmeldt")
        #expect(FindTournaments.places(try Self.row(max: nil, entrants: 5)) == "5 påmeldt")
        #expect(FindTournaments.places(try Self.row(max: 16, entrants: 16, waitlist: 3)) == "16 av 16 påmeldt · 3 på venteliste")
        #expect(FindTournaments.places(try Self.row(max: 16, entrants: 16, waitlistEnabled: false)) == "Fullt · 16 av 16")
    }

    @Test func undertekstOgPeriode() throws {
        #expect(FindTournaments.subtitle(try Self.row(venue: "Golfstudio Bryn")) == "Golfstudio Bryn · 15. oktober–17. desember")
        #expect(FindTournaments.period(try Self.row(to: nil)) == "Fra 15. oktober")
        #expect(FindTournaments.period(try Self.row(from: nil, to: nil)) == nil)
    }

    @Test func søk() throws {
        let rows = [try Self.row(name: "Vinterserien"), try Self.row(name: "Fredagsmorro", club: "Losby Golfklubb")]
        #expect(FindTournaments.filter(rows, query: "  ").count == 2)
        #expect(FindTournaments.filter(rows, query: "losby").map(\.name) == ["Fredagsmorro"])
        #expect(FindTournaments.filter(rows, query: "VINTER").map(\.name) == ["Vinterserien"])
    }
}
