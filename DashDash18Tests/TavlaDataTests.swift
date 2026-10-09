import Foundation
import GolfgutuCore
import Testing
@testable import DashDash18

/// Tavla-data i én RPC (fase 24, sql/036): svaret fra `tavla_data` gir samme grunnlag som spørringene.
struct TavlaDataTests {
    static let club = "00000000-0000-0000-0000-000000000001"
    static let season = "00000000-0000-0000-0000-000000000002"
    static let event = "00000000-0000-0000-0000-000000000003"
    static let course = "00000000-0000-0000-0000-000000000004"
    static let r1 = "00000000-0000-0000-0000-000000000005"
    static let r2 = "00000000-0000-0000-0000-000000000006"
    static let anna = "00000000-0000-0000-0000-00000000000a"
    static let bo = "00000000-0000-0000-0000-00000000000b"

    /// Slik `tavla_data` svarer: kolonnene fra `…Row.columns`, ekstra felt (venue, tee) med.
    static let json = """
    {"events": [{"id": "\(event)", "club_id": "\(club)", "season_id": "\(season)", "event_date": "2026-10-08",
                 "start_time": "17:00:00", "venue": null, "note": null}],
     "members": [
       {"id": "\(anna)", "club_id": "\(club)", "user_id": null, "display_name": "Anna", "handicap_index": 12.4,
        "seed_group": 1, "is_organizer": true, "is_treasurer": false, "status": "active", "avatar_path": null},
       {"id": "\(bo)", "club_id": "\(club)", "user_id": null, "display_name": "Bo", "handicap_index": 20,
        "seed_group": 2, "is_organizer": false, "is_treasurer": false, "status": "active", "avatar_path": null}],
     "rounds": [
       {"id": "\(r1)", "club_id": "\(club)", "event_id": "\(event)", "course_id": "\(course)", "round_no": 1,
        "name": null, "status": "locked", "hole_count": 2, "first_hole": 1, "tee_time": null, "format": "stableford",
        "handicap_allowance": 1, "external_handicap": false, "weight": 1, "ld_enabled": false, "ld_hole_index": null,
        "kp_enabled": false, "kp_hole_index": null, "cut_rule": null, "cut_after": null, "par_confirmed_by": null,
        "par_confirmed_at": null, "started_at": null, "locked_at": null, "venue": "Bås 1", "tee_id": null,
        "tee_name": null, "course_rating": null, "slope_rating": null, "tee_par": null},
       {"id": "\(r2)", "club_id": "\(club)", "event_id": "\(event)", "course_id": null, "round_no": 2,
        "name": null, "status": "active", "hole_count": 2, "first_hole": 1, "tee_time": null, "format": "stableford",
        "handicap_allowance": 1, "external_handicap": false, "weight": 1, "ld_enabled": false, "ld_hole_index": null,
        "kp_enabled": false, "kp_hole_index": null, "cut_rule": null, "cut_after": null, "par_confirmed_by": null,
        "par_confirmed_at": null, "started_at": null, "locked_at": null, "venue": null, "tee_id": null,
        "tee_name": null, "course_rating": null, "slope_rating": null, "tee_par": null}],
     "round_holes": [
       {"round_id": "\(r1)", "hole_index": 0, "par": 4, "stroke_index": 1, "length_m": 350},
       {"round_id": "\(r1)", "hole_index": 1, "par": 3, "stroke_index": 2, "length_m": 150}],
     "players": [
       {"round_id": "\(r1)", "member_id": "\(anna)", "club_id": "\(club)", "handicap_index": 12.4, "seed_group": 1,
        "playing_handicap": 12, "bay_no": 1, "is_marker": true, "team_no": null},
       {"round_id": "\(r2)", "member_id": "\(bo)", "club_id": "\(club)", "handicap_index": 20, "seed_group": 2,
        "playing_handicap": 20, "bay_no": 1, "is_marker": true, "team_no": null}],
     "matches": [],
     "claims": [],
     "courses": [{"id": "\(course)", "club_id": "\(club)", "name": "Losby", "external_name": null,
                  "course_rating": 71.2, "slope_rating": 130, "in_use": true, "confirmed_by": null, "confirmed_at": null}],
     "course_holes": [
       {"course_id": "\(course)", "hole_number": 1, "par": 4, "stroke_index": 1, "length_m": 350},
       {"course_id": "\(course)", "hole_number": 2, "par": 3, "stroke_index": 2, "length_m": 150}],
     "scores": [
       {"round_id": "\(r1)", "member_id": "\(anna)", "hole_index": 0, "strokes": 5,
        "recorded_at": null, "updated_by": null, "updated_at": null},
       {"round_id": "\(r1)", "member_id": "\(anna)", "hole_index": 1, "strokes": 3,
        "recorded_at": null, "updated_by": null, "updated_at": null}]}
    """

    static func decoded() throws -> TavlaData {
        try JSONDecoder().decode(TavlaData.self, from: Data(json.utf8))
    }

    static func seasonRow() -> SeasonRow {
        SeasonRow(id: UUID(uuidString: season)!, clubID: UUID(uuidString: club)!, name: "Høst 2026",
                  status: .active, rules: .golfgutu)
    }

    @Test func flaggetErPå() {
        #expect(TavlaRPCFeature.isEnabled == true)
    }

    @Test func svaretLesesInn() throws {
        let data = try Self.decoded()
        #expect(data.events.count == 1 && data.members.count == 2 && data.rounds.count == 2)
        #expect(data.roundHoles.count == 2 && data.players.count == 2 && data.scores.count == 2)
        #expect(data.courses.first?.name == "Losby" && data.courseHoles.count == 2)
        #expect(data.rounds.first?.venue == "Bås 1")
    }

    @Test func rundeneFårSineEgneRader() throws {
        let input = try Self.decoded().input(season: Self.seasonRow())
        #expect(input.members.count == 2)
        let first = try #require(input.rounds.first { $0.round.id.uuidString.lowercased() == Self.r1 })
        #expect(first.roundHoles.count == 2 && first.players.count == 1 && first.scores.count == 2)
        #expect(first.course?.name == "Losby" && first.courseHoles.count == 2)
        #expect(first.eventDate == "2026-10-08")
        #expect(first.names[UUID(uuidString: Self.anna)!] == "Anna")
        let second = try #require(input.rounds.first { $0.round.id.uuidString.lowercased() == Self.r2 })
        #expect(second.scores.isEmpty && second.roundHoles.isEmpty && second.course == nil)
        #expect(second.players.map(\.memberID) == [UUID(uuidString: Self.bo)!])
    }

    /// Rekkefølgen på scorene i svaret spiller ingen rolle for hvilken runde de havner i.
    @Test func scoreneGrupperesPerRunde() throws {
        var data = try Self.decoded()
        data.scores.reverse()
        let input = data.input(season: Self.seasonRow())
        let first = try #require(input.rounds.first { $0.round.id.uuidString.lowercased() == Self.r1 })
        #expect(Set(first.scores.map(\.holeIndex)) == [0, 1])
    }

    @Test func tomSesong() {
        let input = TavlaData().input(season: Self.seasonRow())
        #expect(input.rounds.isEmpty && input.members.isEmpty)
    }
}

/// Mengdebaserte RPC-er (fase 24, sql/037).
struct SetQueriesFeatureTests {
    @Test func flaggetErPå() {
        #expect(SetQueriesFeature.isEnabled == true)
    }
}
