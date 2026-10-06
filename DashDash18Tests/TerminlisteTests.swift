import Foundation
import Testing
@testable import DashDash18

/// Faste id-er: medlem n og kveld n.
private func member(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))! }
private func eveningID(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0001-%012d", n))! }

struct CommitteeDrawTests {
    /// PWA-ens kommentar: «Tolv mann og sju runder gir fjorten plasser — tolv får én, to får to.»
    @Test func alleFaarEnTurFoerNoenFaarTo() {
        let members = (1...12).map(member)
        let evenings = (1...7).map { CommitteeDraw.Evening(id: eveningID($0), date: "2027-0\($0)-01", committee: []) }
        let plan = CommitteeDraw.draw(evenings: evenings, members: members, chooseIndex: { _ in 0 })

        #expect(plan.count == 7)
        #expect(plan.map(\.memberIDs) == [
            [member(1), member(2)], [member(3), member(4)], [member(5), member(6)],
            [member(7), member(8)], [member(9), member(10)], [member(11), member(12)],
            [member(1), member(2)],
        ])
        let turns = Dictionary(grouping: plan.flatMap(\.memberIDs), by: { $0 }).mapValues(\.count)
        #expect(turns.values.filter { $0 == 1 }.count == 10)
        #expect(turns.values.filter { $0 == 2 }.count == 2)
    }

    @Test func tilfeldigBlantLikeMedInjisertValg() {
        let members = (1...4).map(member)
        let evenings = [CommitteeDraw.Evening(id: eveningID(1), date: "2027-05-01", committee: [])]
        var asked: [Int] = []
        let plan = CommitteeDraw.draw(evenings: evenings, members: members, chooseIndex: { n in
            asked.append(n)
            return n - 1  // siste blant de likestilte
        })
        // Først fire kandidater med 0 turer, så tre.
        #expect(asked == [4, 3])
        #expect(plan.first?.memberIDs == [member(4), member(3)])
    }

    @Test func tidligereTurerTellerOgFulleKvelderRoresIkke() {
        let members = (1...4).map(member)
        let evenings = [
            CommitteeDraw.Evening(id: eveningID(1), date: "2027-05-01", committee: [member(1), member(2)]),
            CommitteeDraw.Evening(id: eveningID(2), date: "2027-05-22", committee: [member(3)]),
            CommitteeDraw.Evening(id: eveningID(3), date: "2027-06-12", committee: []),
        ]
        let plan = CommitteeDraw.draw(evenings: evenings, members: members, chooseIndex: { _ in 0 })

        #expect(plan.map(\.eventID) == [eveningID(2), eveningID(3)])
        // Kveld 2 har medlem 3 og fylles med den eneste uten tur: 4.
        #expect(plan[0].memberIDs == [member(3), member(4)])
        #expect(plan[0].added == [member(4)])
        // Alle har nå én tur, så første to.
        #expect(plan[1].memberIDs == [member(1), member(2)])
    }

    @Test func medlemmerSomIkkeErITroppenTellesIkke() {
        let members = [member(1), member(2), member(3)]
        let evenings = [
            CommitteeDraw.Evening(id: eveningID(1), date: "2027-05-01", committee: [member(9), member(1)]),
            CommitteeDraw.Evening(id: eveningID(2), date: "2027-05-22", committee: []),
        ]
        let plan = CommitteeDraw.draw(evenings: evenings, members: members, chooseIndex: { _ in 0 })
        #expect(plan.map(\.memberIDs) == [[member(2), member(3)]])
    }

    @Test func bareKvelderFraOgMedDatoFylles() {
        let members = (1...4).map(member)
        let evenings = [
            CommitteeDraw.Evening(id: eveningID(1), date: "2026-09-01", committee: []),
            CommitteeDraw.Evening(id: eveningID(2), date: "2026-10-08", committee: []),
        ]
        let plan = CommitteeDraw.draw(evenings: evenings, members: members, fillFrom: "2026-10-06", chooseIndex: { _ in 0 })
        #expect(plan.map(\.eventID) == [eveningID(2)])
    }

    @Test func forFaaMedlemmerGirIngenTrekning() {
        let plan = CommitteeDraw.draw(
            evenings: [CommitteeDraw.Evening(id: eveningID(1), date: "2027-05-01", committee: [])],
            members: [member(1)],
            chooseIndex: { _ in 0 }
        )
        #expect(plan.isEmpty)
    }

    @Test func antallPerKveldErValgfritt() {
        let members = (1...6).map(member)
        let evenings = [CommitteeDraw.Evening(id: eveningID(1), date: "2027-05-01", committee: [])]
        let plan = CommitteeDraw.draw(evenings: evenings, members: members, perEvening: 3, chooseIndex: { _ in 0 })
        #expect(plan.first?.memberIDs == [member(1), member(2), member(3)])
        #expect(CommitteeDraw.draw(evenings: evenings, members: members, perEvening: 0).isEmpty)
    }

    @Test func standardTilfeldighetGirGyldigTrekning() {
        let members = (1...5).map(member)
        let evenings = (1...3).map { CommitteeDraw.Evening(id: eveningID($0), date: "2027-0\($0)-01", committee: []) }
        let plan = CommitteeDraw.draw(evenings: evenings, members: members)
        #expect(plan.count == 3)
        #expect(plan.allSatisfy { Set($0.memberIDs).count == 2 })
        // Fem medlemmer, seks plasser: alle får minst én tur.
        #expect(Set(plan.flatMap(\.memberIDs)).count == 5)
    }
}

struct TerminlisteTests {
    private func event(_ n: Int, _ date: String, season: UUID? = nil) -> EventRow {
        EventRow(id: eveningID(n), clubID: member(99), seasonID: season, eventDate: date,
                 startTime: nil, venue: nil, note: nil)
    }

    @Test func kommendeOgTidligere() {
        let events = [event(1, "2026-10-08"), event(2, "2026-09-17"), event(3, "2026-10-06"), event(4, "2026-08-27")]
        let (upcoming, past) = Terminliste.split(events, today: "2026-10-06")
        // I dag er en kommende kveld.
        #expect(upcoming.map(\.eventDate) == ["2026-10-06", "2026-10-08"])
        #expect(past.map(\.eventDate) == ["2026-09-17", "2026-08-27"])
    }

    @Test func aktivSesongOgKvelderUtenSesong() {
        let active = UUID(), old = UUID()
        let events = [event(1, "2026-10-08", season: active), event(2, "2026-05-01", season: old), event(3, "2026-11-01")]
        #expect(Terminliste.eveningsForSeason(events, activeSeasonID: active).map(\.id) == [eveningID(1), eveningID(3)])
        #expect(Terminliste.eveningsForSeason(events, activeSeasonID: nil).map(\.id) == [eveningID(3)])
    }

    @Test func feilmeldinger() {
        // Samme dato to ganger: databasen har unik på (klubb, dato).
        #expect(Terminliste.saveErrorMessage(sqlState: "23505", fallback: .duplicate, date: "2026-10-08")
            == "Det finnes allerede en kveld torsdag 8. oktober.")
        #expect(Terminliste.saveErrorMessage(sqlState: "42501", fallback: .notAllowed, date: "2026-10-08")
            == DataError.notAllowed.message)
        // Runder på kvelden: on delete restrict.
        #expect(Terminliste.deleteErrorMessage(sqlState: "23503", fallback: .invalid("fk"))
            == "Kvelden har runder og kan ikke slettes. Slett rundene først.")
        #expect(Terminliste.deleteErrorMessage(sqlState: nil, fallback: .offline) == DataError.offline.message)
    }

    @Test func tekstfelt() throws {
        #expect(try EventInput.text("  Golfhallen  ", max: 80, field: "Sted").get() == "Golfhallen")
        #expect(try EventInput.text("   ", max: 80, field: "Sted").get() == nil)
        #expect(try EventInput.text(String(repeating: "x", count: 80), max: 80, field: "Sted").get()?.count == 80)
        guard case .failure(let error) = EventInput.text(String(repeating: "x", count: 81), max: 80, field: "Sted") else {
            Issue.record("81 tegn skulle vært avvist")
            return
        }
        #expect(error == .invalid("Sted kan være høyst 80 tegn."))
    }

    @Test func radenSomSkrivesSenderNull() throws {
        let write = EventWrite(clubID: member(1), seasonID: nil, eventDate: "2026-10-08",
                               startTime: nil, venue: "Hallen", note: nil)
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(write)) as? [String: Any]
        // Tomme felt må sendes som null, ellers blir gamle verdier stående ved endring.
        #expect(json?["start_time"] is NSNull)
        #expect(json?["note"] is NSNull)
        #expect(json?["season_id"] is NSNull)
        #expect(json?["venue"] as? String == "Hallen")
        #expect(json?["event_date"] as? String == "2026-10-08")
    }
}
