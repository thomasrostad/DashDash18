import Foundation
import GolfgutuCore
import Testing
@testable import DashDash18

/// Turneringer med tidsvindu (sql/042).
struct TimeWindowTests {
    @Test func flaggetErAvTil042ErKjørt() {
        #expect(TimeWindowFeature.isEnabled == false)
        #expect(!CompetitionRow.columnsWithSignup.contains("auto_count"))
    }

    @Test func teksten() {
        #expect(TimeWindowText.summary(startsOn: "2026-10-01", endsOn: "2026-10-31", best: 3)
            == "Spill når det passer · 1. oktober–31. oktober · de beste 3 teller")
        #expect(TimeWindowText.summary(startsOn: nil, endsOn: nil, best: nil) == "Spill når det passer · alle runder teller")
        #expect(TimeWindowText.summary(startsOn: nil, endsOn: nil, best: 1).hasSuffix("den beste runden teller"))
    }

    @Test func periodeKreves() {
        var d = CompetitionDraft(clubID: nil, today: "2026-10-10")
        d.name = "Høstvindu"
        d.kind = .league
        d.playsWhenItSuits = true
        d.hasPeriod = false
        // Valget finnes bare med flagget på; da kreves perioden.
        #expect(d.issues().contains("Velg perioden spillerne kan spille i.") == d.allowsPlayWhenItSuits)
    }

    @Test func svaretMedKolonnen() throws {
        let json = #"{"id": "00000000-0000-4000-8000-000000000001", "kind": "league", "name": "Vindu", "club_id": null, "owner_id": null, "season_id": null, "status": "active", "entry": "listed", "rules": {}, "starts_on": "2026-10-01", "ends_on": "2026-10-31", "is_main": false, "requires_purchase": false, "entitlement_id": null, "signup_open": true, "auto_count": true}"#
        let row = try JSONDecoder().decode(CompetitionRow.self, from: Data(json.utf8))
        #expect(row.playsWhenItSuits)
    }
}
