import Foundation
import GolfgutuCore
import Testing
@testable import DashDash18

private typealias F = ForingFixture

/// «Bås» i simulatoren, «flight» på ekte bane (`rounds.venue = course`) i tekstene spillerne og
/// arrangøren ser.
struct FlightPaBaneTests {
    @Test func gruppeordetsFormer() {
        #expect(GroupTerm.bay.definiteGenitive == "båsens")
        #expect(GroupTerm.flight.definiteGenitive == "flightens")
        #expect(GroupTerm.bay.definitePluralTitle == "Båsene")
        #expect(GroupTerm.flight.definitePluralTitle == "Flightene")
    }

    @Test func hullbrikkenSierFlightensHull() {
        var snapshot = F.snapshot(F.markorPlayers())
        snapshot.round.venue = "course"
        let course = RoundGame(snapshot).dots(currentHole: 0, viewer: F.viewer(F.bjorn), pending: [])
        #expect(course.first { $0.isBayHole }?.accessibilityLabel.hasSuffix("flightens hull") == true)

        let sim = RoundGame(F.snapshot(F.markorPlayers())).dots(currentHole: 0, viewer: F.viewer(F.bjorn), pending: [])
        #expect(sim.first { $0.isBayHole }?.accessibilityLabel.hasSuffix("båsens hull") == true)
    }

    @Test func startlistaSinGrenseFolgerStedet() {
        let long = [StartGroupDraft(groupNo: 1, startsAt: nil, startHole: 1,
                                    resourceLabel: String(repeating: "a", count: 41), scorerID: nil, memberIDs: [])]
        #expect(StartList.issues(long, wave: 1, holeCount: 18, staffIDs: [], term: .flight)
                == ["Tee eller startsted kan ha høyst 40 tegn."])
        #expect(StartList.issues(long, wave: 1, holeCount: 18, staffIDs: [], term: .bay)
                == ["Bås eller simulator kan ha høyst 40 tegn."])
    }

    @Test func startlistaNummererFlighter() {
        #expect(StartList.summary(groupNo: 3, saved: nil, venue: "course") == "Flight 3")
        #expect(StartList.summary(groupNo: 3, saved: nil, venue: nil) == "Bås 3")
        #expect(StartList.defaultLabel(3, venue: "course") == "")
        #expect(StartList.defaultLabel(3, venue: "simulator") == "Bås 3")
    }

    @Test func iKveldUtenGrupper() {
        #expect(TonightLive.noGroupsText(.for(stored: "course")) == "Ingen flighter er fordelt i oppsettet.")
        #expect(TonightLive.noGroupsText(.for(stored: nil)) == "Ingen båser er fordelt i oppsettet.")
    }

    @Test func nyRundeIAktiviteten() {
        func text(_ venue: String?, bays: Int) -> String {
            ActivityText.display(.roundStarted(roundNo: 1, courseName: "Losby", holeCount: 18, bays: bays,
                                               ldHole: nil, kpHole: nil, venue: venue),
                                 actor: nil, name: { _ in nil }).text
        }
        #expect(text("course", bays: 3) == "Ny runde: Runde 1 – Losby · 18 hull — 3 flighter")
        #expect(text("course", bays: 1) == "Ny runde: Runde 1 – Losby · 18 hull — 1 flight")
        #expect(text("simulator", bays: 3) == "Ny runde: Runde 1 – Losby · 18 hull — 3 båser")
        #expect(text(nil, bays: 1) == "Ny runde: Runde 1 – Losby · 18 hull — 1 bås")
    }

    @Test func stedetLagresIAktiviteten() throws {
        var snapshot = F.snapshot(F.markorPlayers())
        snapshot.round.venue = "course"
        let event = RoundGame(snapshot).startedEvent
        let data = try JSONEncoder().encode(event.data)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["venue"] as? String == "course")
        let back = try JSONDecoder().decode(ActivityData.self, from: data)
        #expect(ActivityEvent(kind: "round_started", data: back) == event)
        // Eldre rader uten stedet leses som simulator.
        #expect(ActivityEvent(kind: "round_started", data: ActivityData(roundNo: 1, bays: 2))
                == .roundStarted(roundNo: 1, courseName: nil, holeCount: nil, bays: 2, ldHole: nil, kpHole: nil))
    }

    @Test func sletteteksten() {
        let flight = RoundDeleteSummary(holeScores: 0, playersWithScores: 0, sideClaims: 0, isDraft: true,
                                        groupTerm: .flight)
        #expect(flight.message.hasPrefix("Ingen har sett den. Flightene og oppsettet forsvinner med den."))
        let bay = RoundDeleteSummary(holeScores: 0, playersWithScores: 0, sideClaims: 0, isDraft: true)
        #expect(bay.message.hasPrefix("Ingen har sett den. Båsene og oppsettet forsvinner med den."))
    }

    @Test func lagSomIkkeFarPlass() {
        let ids = (1...6).map(F.id)
        let teams = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($1, $0 < 5 ? 1 : 2) })
        let scramble = CompetitionForm.form(id: "scramble-2")
        let flight = TeamPlanner.problem(teams: teams, participants: ids, form: scramble, maxPerBay: 4, term: .flight)
        #expect(flight == "Lag 1 har flere enn 4. Et lag får ikke plass i en flight da.")
        let bay = TeamPlanner.problem(teams: teams, participants: ids, form: scramble, maxPerBay: 4)
        #expect(bay == "Lag 1 har flere enn 4. Et lag får ikke plass i en bås da.")
    }
}
