import Foundation
import GolfgutuCore
import Testing
@testable import DashDash18

struct RowsTests {
    @Test func sesongMedStandardRegelsettBlirGolfgutu() throws {
        // Skjemaets standardverdi for rules er {"version": 1}.
        let json = """
        {"id":"7d6c8a51-2f0e-4a5b-9a1c-0d2b3c4e5f60","club_id":"1b2c3d4e-5f60-4718-8a9b-0c1d2e3f4a5b",
         "name":"Sesongen 2027","status":"planned","rules":{"version":1}}
        """
        let season = try JSONDecoder().decode(SeasonRow.self, from: Data(json.utf8))
        #expect(season.rules == .golfgutu)
        #expect(season.status == .planned)
    }

    @Test func kveldOgPamelding() throws {
        let kveld = try JSONDecoder().decode(EventRow.self, from: Data("""
        {"id":"7d6c8a51-2f0e-4a5b-9a1c-0d2b3c4e5f60","club_id":"1b2c3d4e-5f60-4718-8a9b-0c1d2e3f4a5b",
         "season_id":null,"event_date":"2026-10-08","start_time":"17:00:00","venue":"Hallen","note":null}
        """.utf8))
        #expect(kveld.eventDate == "2026-10-08")
        #expect(kveld.startTime == "17:00:00")

        let svar = try JSONDecoder().decode(SignupRow.self, from: Data("""
        {"event_id":"7d6c8a51-2f0e-4a5b-9a1c-0d2b3c4e5f60","member_id":"1b2c3d4e-5f60-4718-8a9b-0c1d2e3f4a5b",
         "club_id":"1b2c3d4e-5f60-4718-8a9b-0c1d2e3f4a5b","status":"maybe","comment":"Kommer kanskje sent"}
        """.utf8))
        #expect(svar.status.title == "Usikker")
    }

    @Test func medlemOgBane() throws {
        let medlem = try JSONDecoder().decode(ClubMemberRow.self, from: Data("""
        {"id":"7d6c8a51-2f0e-4a5b-9a1c-0d2b3c4e5f60","club_id":"1b2c3d4e-5f60-4718-8a9b-0c1d2e3f4a5b",
         "user_id":null,"display_name":"Per","handicap_index":18.4,"seed_group":2,
         "is_organizer":false,"is_treasurer":false,"status":"active","avatar_path":null}
        """.utf8))
        #expect(medlem.isOpen)
        #expect(medlem.handicapIndex == 18.4)

        let hull = try JSONDecoder().decode(CourseHoleRecord.self, from: Data("""
        {"course_id":"7d6c8a51-2f0e-4a5b-9a1c-0d2b3c4e5f60","hole_number":4,"par":3,"stroke_index":17,"length_m":155}
        """.utf8))
        #expect(hull.par == 3)
    }

    @Test func feilFraDatabasen() {
        #expect(DataError.from(sqlState: "42501", message: "") == .notAllowed)
        #expect(DataError.from(sqlState: "23505", message: "") == .duplicate)
        #expect(DataError.from(sqlState: "23514", message: "sjekk") == .invalid("sjekk"))
    }
}
