import Foundation
import Testing
@testable import DashDash18

struct KveldCalendarTests {
    private func event(_ date: String, time: String? = "17:00:00", venue: String? = "Bærum GK",
                       note: String? = nil) -> EventRow {
        EventRow(id: UUID(), clubID: UUID(), seasonID: nil, eventDate: date, startTime: time,
                 venue: venue, note: note)
    }

    /// ISO 8601 med fast offset, så forventningen ikke avhenger av tidssonen på maskinen.
    private func instant(_ iso: String) -> Date {
        try! Date(iso, strategy: .iso8601)
    }

    @Test func sommertidIOsloErUtcPlussTo() throws {
        let entry = try #require(KveldCalendar.entry(for: event("2026-06-11"), tournament: "GolfGutu Invitational",
                                                     number: 5))
        #expect(entry.start == instant("2026-06-11T15:00:00Z"))
        #expect(entry.end == entry.start.addingTimeInterval(KveldCalendar.defaultDuration))
        #expect(!entry.isAllDay)
        #expect(entry.timeZone.identifier == "Europe/Oslo")
    }

    @Test func vintertidIOsloErUtcPlussEn() throws {
        let entry = try #require(KveldCalendar.entry(for: event("2026-11-05"), tournament: "GG", number: 1))
        #expect(entry.start == instant("2026-11-05T16:00:00Z"))
    }

    @Test func rundtOmleggingene() throws {
        // Sommertid fra 29. mars 2026, vintertid fra 25. oktober 2026.
        let before = try #require(KveldCalendar.entry(for: event("2026-03-26", time: "18:30:00"), tournament: "", number: nil))
        let after = try #require(KveldCalendar.entry(for: event("2026-04-02", time: "18:30:00"), tournament: "", number: nil))
        #expect(before.start == instant("2026-03-26T17:30:00Z"))
        #expect(after.start == instant("2026-04-02T16:30:00Z"))

        let lastSummer = try #require(KveldCalendar.entry(for: event("2026-10-22"), tournament: "", number: nil))
        let firstWinter = try #require(KveldCalendar.entry(for: event("2026-10-29"), tournament: "", number: nil))
        #expect(lastSummer.start == instant("2026-10-22T15:00:00Z"))
        #expect(firstWinter.start == instant("2026-10-29T16:00:00Z"))
    }

    @Test func tittelStedOgVarsel() throws {
        let entry = try #require(KveldCalendar.entry(for: event("2026-10-08", venue: "  Bærum GK "),
                                                     tournament: "GolfGutu Invitational", number: 7))
        #expect(entry.title == "GolfGutu Invitational – kveld 7")
        #expect(entry.location == "Bærum GK")
        #expect(entry.alarmOffset == KveldCalendar.alarmOffset)
        #expect(entry.notes == nil)
    }

    @Test func tittelUtenNavnEllerNummer() {
        #expect(KveldCalendar.title(tournament: "GolfGutu Invitational", number: nil) == "GolfGutu Invitational – kveld")
        #expect(KveldCalendar.title(tournament: " ", number: 3) == "Kveld 3")
        #expect(KveldCalendar.title(tournament: "", number: nil) == "Kveld")
    }

    @Test func notaterMedKomiteOgMerknad() throws {
        let entry = try #require(KveldCalendar.entry(for: event("2026-10-08", venue: "", note: "Grilling etterpå"),
                                                     tournament: "GG", number: 1, committee: ["Ola", "Kari"]))
        #expect(entry.notes == "Sosialkomité: Ola og Kari\n\nGrilling etterpå")
        #expect(entry.location == nil)
    }

    @Test func utenKlokkeslettBlirHeldag() throws {
        let entry = try #require(KveldCalendar.entry(for: event("2026-10-25", time: nil), tournament: "GG", number: 1))
        #expect(entry.isAllDay)
        #expect(entry.alarmOffset == nil)
        // Dagen vintertiden kommer har 25 timer i Oslo.
        #expect(entry.start == instant("2026-10-24T22:00:00Z"))
        #expect(entry.end == instant("2026-10-25T23:00:00Z"))
    }

    @Test func ugyldigDatoGirIngenting() {
        #expect(KveldCalendar.entry(for: event("tull"), tournament: "GG", number: 1) == nil)
    }

    @Test func kveldsnummerISesongen() {
        let dates = ["2026-05-14", "2026-04-30", "2026-05-28", "2026-05-14"]
        #expect(KveldCalendar.number(of: "2026-04-30", in: dates) == 1)
        #expect(KveldCalendar.number(of: "2026-05-14", in: dates) == 2)
        #expect(KveldCalendar.number(of: "2026-05-28", in: dates) == 3)
        #expect(KveldCalendar.number(of: "2026-06-11", in: dates) == nil)
    }
}
