import Foundation
import Testing
@testable import DashDash18

/// Egne spilledager for liga, cup og morro (sql/033).
struct SpilledagerTurneringTests {
    static let club = UUID(uuidString: "00000000-0000-4000-8000-0000000000c1")!
    static let season = UUID(uuidString: "00000000-0000-4000-8000-0000000000f1")!
    static let seasonComp = UUID(uuidString: "00000000-0000-4000-8000-0000000000f2")!
    static let league = UUID(uuidString: "00000000-0000-4000-8000-0000000000a9")!

    static func event(_ n: Int, _ date: String, season: UUID? = nil, competition: UUID? = nil) -> EventRow {
        EventRow(id: UUID(uuidString: "00000000-0000-4000-8000-00000000000\(n)")!, clubID: club, seasonID: season,
                 eventDate: date, startTime: nil, venue: nil, note: nil, competitionID: competition)
    }

    static let events = [
        event(1, "2026-10-01", season: season, competition: seasonComp),  // sesongens kveld
        event(2, "2026-10-02"),                                             // klubbens egen kveld
        event(3, "2026-10-03", competition: league),                       // ligaens spilledag
    ]

    @Test func sesongenViserIkkeLigaensDager() {
        let ids = Terminliste.eveningsForSeason(Self.events, activeSeasonID: Self.season).map(\.eventDate)
        #expect(ids == ["2026-10-01", "2026-10-02"])
        #expect(Terminliste.eveningsForSeason(Self.events, activeSeasonID: nil).map(\.eventDate) == ["2026-10-02"])
    }

    @Test func ligaensDager() {
        #expect(Terminliste.days(Self.events, competitionID: Self.league).map(\.eventDate) == ["2026-10-03"])
        #expect(Terminliste.days(Self.events, competitionID: Self.seasonComp).map(\.eventDate) == ["2026-10-01"])
    }

    /// Spilledager uten sesong sender turneringen; sesongens kvelder lar triggeren fylle den.
    @Test func detSomSkrives() throws {
        let league = EventWrite(clubID: Self.club, seasonID: nil, competitionID: Self.league, eventDate: "2026-10-03",
                                startTime: nil, venue: nil, note: nil)
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(league)) as! [String: Any]
        #expect(json["competition_id"] as? String == Self.league.uuidString)
        #expect(json["season_id"] is NSNull)
        let season = EventWrite(clubID: Self.club, seasonID: Self.season, eventDate: "2026-10-01",
                                startTime: nil, venue: nil, note: nil)
        let seasonJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(season)) as! [String: Any]
        #expect(seasonJSON["competition_id"] == nil)
    }

    @Test func eldreSvarUtenTurneringskolonne() throws {
        let json = #"{"id": "00000000-0000-4000-8000-000000000001", "club_id": "00000000-0000-4000-8000-0000000000c1", "season_id": null, "event_date": "2026-10-03", "start_time": null, "venue": null, "note": null}"#
        let row = try JSONDecoder().decode(EventRow.self, from: Data(json.utf8))
        #expect(row.competitionID == nil)
    }
}
