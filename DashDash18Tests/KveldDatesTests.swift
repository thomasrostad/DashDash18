import Foundation
import Testing
@testable import DashDash18

struct KveldDatesTests {
    @Test(arguments: [
        ("2026-10-08", "torsdag 8. oktober"),
        ("2026-10-06", "tirsdag 6. oktober"),
        ("2026-03-29", "søndag 29. mars"),
        ("2026-12-31", "torsdag 31. desember"),
    ])
    func norskDato(_ date: String, _ expected: String) {
        #expect(EveningDates.longText(date) == expected)
        #expect(EveningDates.longText(date, referenceYear: 2026) == expected)
    }

    @Test func aaretTasMedNaarDetErEtAnnet() {
        #expect(EveningDates.longText("2027-01-01", referenceYear: 2026) == "fredag 1. januar 2027")
        #expect(EveningDates.longText("2026-10-08", capitalized: true) == "Torsdag 8. oktober")
        #expect(EveningDates.longText("ikke en dato") == "ikke en dato")
    }

    @Test func dagerTil() {
        #expect(EveningDates.daysBetween("2026-10-06", "2026-10-06") == 0)
        #expect(EveningDates.daysBetween("2026-10-06", "2026-10-08") == 2)
        #expect(EveningDates.daysBetween("2026-10-06", "2026-10-27") == 21)
        #expect(EveningDates.daysBetween("2026-10-06", "2026-09-29") == -7)
        // Over sommertid (29. mars) og vintertid (25. oktober) og nyttår.
        #expect(EveningDates.daysBetween("2026-03-28", "2026-03-30") == 2)
        #expect(EveningDates.daysBetween("2026-10-24", "2026-10-26") == 2)
        #expect(EveningDates.daysBetween("2026-12-31", "2027-01-01") == 1)
        #expect(EveningDates.daysBetween("2026-10-06", "tull") == nil)
    }

    @Test func nedtelling() {
        #expect(EveningDates.countdownText(days: 0) == "I dag")
        #expect(EveningDates.countdownText(days: -3) == "I dag")
        #expect(EveningDates.countdownText(days: 1) == "I morgen")
        #expect(EveningDates.countdownText(days: 21) == "Om 21 dager")
    }

    @Test func dagensDatoErIOsloTid() throws {
        // 5. oktober kl. 22:30 UTC er 6. oktober kl. 00:30 i Oslo (sommertid, UTC+2).
        let utc = try Date("2026-10-05T22:30:00Z", strategy: .iso8601)
        #expect(EveningDates.today(now: utc) == "2026-10-06")
        // Vintertid (UTC+1): 31. desember 23:30 UTC er nyttårsdag i Oslo.
        let winter = try Date("2026-12-31T23:30:00Z", strategy: .iso8601)
        #expect(EveningDates.today(now: winter) == "2027-01-01")
    }

    @Test func datoTilOgFra() throws {
        let date = try #require(EveningDates.date(from: "2026-10-08"))
        #expect(EveningDates.dateString(from: date) == "2026-10-08")
        #expect(EveningDates.date(from: "2026-02-31") == nil)
        #expect(EveningDates.date(from: "2026-13-01") == nil)
    }

    @Test func klokkeslett() throws {
        #expect(EveningDates.timeText("17:00:00") == "17:00")
        #expect(EveningDates.timeText("8:05") == "08:05")
        #expect(EveningDates.timeText(nil) == nil)
        #expect(EveningDates.timeText("25:00") == nil)
        let time = try #require(EveningDates.time(from: "18:30:00"))
        #expect(EveningDates.timeString(from: time) == "18:30:00")
    }

    @Test func norskOpplisting() {
        #expect(NorwegianList.join([]) == "")
        #expect(NorwegianList.join(["Anders"]) == "Anders")
        #expect(NorwegianList.join(["Anders", "Bjørn"]) == "Anders og Bjørn")
        #expect(NorwegianList.join(["Anders", "Bjørn", "Carl"]) == "Anders, Bjørn og Carl")
    }
}
