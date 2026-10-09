import Foundation
import GolfgutuCore
import Testing
@testable import DashDash18

/// Slette en turnering (sql/038).
struct TournamentDeletionTests {
    @Test func flaggetErAvTil038ErKjørt() {
        #expect(TournamentDeletionFeature.isEnabled == false)
    }

    @Test func navnetMåSkrivesInn() {
        #expect(TournamentDeletion.nameMatches(" høst 2026 ", name: "Høst 2026"))
        #expect(!TournamentDeletion.nameMatches("Høst", name: "Høst 2026"))
        #expect(!TournamentDeletion.nameMatches("", name: ""))
    }

    @Test func meldingen() throws {
        let json = #"{"name": "Høst 2026", "rounds": 9, "events": 7}"#
        let r = try JSONDecoder().decode(TournamentDeletion.Result.self, from: Data(json.utf8))
        #expect(TournamentDeletion.message(r) == "Høst 2026 er slettet, med 7 kvelder og 9 runder.")
        #expect(TournamentDeletion.message(.init(name: "Vårcup", rounds: 1, events: 0), term: .playingDay)
            == "Vårcup er slettet, med 1 runde.")
        #expect(TournamentDeletion.message(.init(name: "Tom", rounds: 0, events: 0)) == "Tom er slettet.")
    }
}
