import Foundation
import GolfgutuCore
import Testing
@testable import DashDash18

// Gjennomføringsplanen steg 3 (sql/035): appen leser sesongene fra turneringsraden (`competitions` med
// `season_id`), ikke fra `seasons`. Radtypen er den samme, så Tavla, Vedd og arrangørsiden er uendret.

struct SesongSomViewTests {
    @Test func kolonneneHenterIdFraSeasonID() {
        // PostgREST: `id:season_id` gir sesongens id under nøkkelen `id`, som SeasonRow leser.
        #expect(SeasonRow.columns == "id:season_id, club_id, name, status, rules")
        #expect(!SeasonRow.columns.contains("created_at"))
    }

    @Test func svaretFraCompetitionsGirSammeRadSomSeasons() throws {
        // Svaret fra `competitions?select=id:season_id,…` og fra `seasons?select=id,…` har samme form.
        let json = #"""
        [{"id": "5eeeeeee-0000-0000-0000-000000002026", "club_id": "aaaaaaaa-0000-0000-0000-000000000001",
          "name": "Sesong 2026", "status": "active", "rules": {"version": 1, "preset": "golfgutu"}}]
        """#
        let rows = try JSONDecoder().decode([SeasonRow].self, from: Data(json.utf8))
        #expect(rows.count == 1)
        #expect(rows[0].id == UUID(uuidString: "5eeeeeee-0000-0000-0000-000000002026"))
        #expect(rows[0].status == .active)
        #expect(rows[0].name == "Sesong 2026")
    }

    @Test func nySesongSenderIdSomKanLesesTilbake() throws {
        // Ny sesong skrives uten å lese svaret fra `seasons`; id-en lages i appen og leses tilbake
        // fra `competitions.season_id`.
        let club = UUID()
        let payload = NewSeasonPayload(clubID: club, name: "Vinter", status: .planned, rules: .golfgutu)
        let json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(payload)) as? [String: Any])
        #expect((json["id"] as? String).flatMap(UUID.init(uuidString:)) == payload.id)
        #expect(json["club_id"] as? String == club.uuidString)
        #expect(Set(json.keys) == ["id", "club_id", "name", "status", "rules"])
        #expect(NewSeasonPayload(clubID: club, name: "Vinter", status: .planned, rules: .golfgutu).id != payload.id)
    }
}
