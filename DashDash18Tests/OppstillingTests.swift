import Foundation
import Testing
@testable import DashDash18

// Oppstillingen før start (sql/076): «Laget ditt» på Hjem fra radene i `event_lineups`.

private func id(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))! }
private let me = id(1)
private let roundOne = id(100), roundTwo = id(200)

private func row(_ member: Int, _ name: String, bay: Int?, team: Int?, marker: Bool = false,
                 round: UUID = roundOne, roundNo: Int = 1, format: String? = "fourball",
                 venue: String? = nil) -> EventLineupRow {
    EventLineupRow(roundID: round, roundNo: roundNo, roundName: nil, format: format, teeTime: "18:00:00",
                   memberID: id(member), name: name, bayNo: bay, teamNo: team, isMarker: marker, sharedAt: nil,
                   venue: venue)
}

/// To båser med fourball: Thomas og Preben (lag 3) mot Sebastian og Thomas Seim (lag 4) i bås 2.
private let fourball = [
    row(5, "Ola", bay: 1, team: 1), row(6, "Kari", bay: 1, team: 1, marker: true),
    row(7, "Even", bay: 1, team: 2), row(8, "Bjørn", bay: 1, team: 2),
    row(1, "Thomas Rostad", bay: 2, team: 3, marker: true), row(2, "Preben Huseby", bay: 2, team: 3),
    row(4, "Thomas Seim Breivik", bay: 2, team: 4), row(3, "Sebastian Thuen", bay: 2, team: 4),
]

struct OppstillingTests {
    @Test func ingenRaderGirIngentingAaVise() {
        #expect(EveningLineup(rows: [], viewer: [me]) == nil)
    }

    @Test func lagetDittMedLagkameratOgMotstanderneIBaasen() throws {
        let lineup = try #require(EveningLineup(rows: fourball, viewer: [me]))
        #expect(lineup.title == "Laget ditt")
        let mine = try #require(lineup.mine.first)
        #expect(mine.teammates == ["Preben Huseby"])
        #expect(mine.opponents.map(\.number) == [4])
        #expect(mine.summary
                == "Lag 3 med Preben Huseby · Bås 2 mot Lag 4 (Sebastian Thuen og Thomas Seim Breivik)")
        #expect(mine.markerText == "Du er markør i båsen")
        #expect(!lineup.showsRoundTitles)
    }

    @Test func heleOppstillingenGruppertPaaBaasOgLag() throws {
        let lineup = try #require(EveningLineup(rows: fourball.reversed(), viewer: [me]))
        let round = try #require(lineup.rounds.first)
        #expect(round.title == "Runde 1")
        #expect(round.detail == "Fourball (beste ball) · kl. 18:00")
        #expect(round.groups.map(\.number) == [1, 2])
        #expect(round.groupTitle(round.groups[1]) == "Bås 2")
        #expect(round.groups[1].teams.map(\.title) == ["Lag 3", "Lag 4"])
        // Norsk sortering i laget, og du er merket.
        #expect(round.groups[1].teams[1].players.map(\.name) == ["Sebastian Thuen", "Thomas Seim Breivik"])
        #expect(round.groups[1].teams[0].players.first { $0.isMe }?.name == "Thomas Rostad")
        #expect(round.groups[0].teams[0].players.first { $0.isMarker }?.name == "Kari")
    }

    @Test func flereLagIBaasenRamsesOppMedOg() throws {
        let rows = [row(1, "Thomas", bay: 1, team: 1), row(2, "Ola", bay: 1, team: 2), row(3, "Kari", bay: 1, team: 3)]
        let mine = try #require(EveningLineup(rows: rows, viewer: [me])?.mine.first)
        #expect(mine.summary == "Lag 1 · Bås 1 mot Lag 2 (Ola) og Lag 3 (Kari)")
        #expect(mine.markerText == nil)
    }

    @Test func individuellFormViserBaaskameratene() throws {
        let rows = [row(1, "Thomas", bay: 2, team: nil, format: "stableford"), row(3, "Øystein", bay: 2, team: nil),
                    row(2, "Anders", bay: 2, team: nil), row(4, "Kari", bay: 1, team: nil)]
        let lineup = try #require(EveningLineup(rows: rows, viewer: [me]))
        #expect(lineup.title == "Båsen din")
        let mine = try #require(lineup.mine.first)
        #expect(mine.bayMates == ["Anders", "Øystein"])
        #expect(mine.opponents.isEmpty)
        #expect(mine.summary == "Bås 2 med Anders og Øystein")
        #expect(lineup.rounds[0].groups[1].teams.map(\.title) == [nil])
    }

    @Test func paaEkteBaneHeterDetFlight() throws {
        let rows = [row(1, "Thomas", bay: 1, team: nil, marker: true, venue: "course"),
                    row(2, "Anders", bay: 1, team: nil, venue: "course")]
        let lineup = try #require(EveningLineup(rows: rows, viewer: [me]))
        #expect(lineup.title == "Flighten din")
        #expect(lineup.mine.first?.summary == "Flight 1 med Anders")
        #expect(lineup.mine.first?.markerText == "Du er markør i flighten")
    }

    @Test func utenBaasViserBareLaget() throws {
        let rows = [row(1, "Thomas", bay: nil, team: 2), row(2, "Preben", bay: nil, team: 2),
                    row(3, "Ola", bay: nil, team: 1), row(4, "Kari", bay: 1, team: 1)]
        let lineup = try #require(EveningLineup(rows: rows, viewer: [me]))
        let mine = try #require(lineup.mine.first)
        #expect(mine.summary == "Lag 2 med Preben")
        #expect(mine.opponents.isEmpty)
        // Uten bås står sist.
        let round = lineup.rounds[0]
        #expect(round.groups.map(\.number) == [1, nil])
        #expect(round.groupTitle(round.groups[1]) == "Uten bås")
    }

    @Test func utenBaasOgLag() throws {
        let rows = [row(1, "Thomas", bay: nil, team: nil), row(2, "Ola", bay: nil, team: nil)]
        let lineup = try #require(EveningLineup(rows: rows, viewer: [me]))
        #expect(lineup.title == "Oppstillingen")
        #expect(lineup.mine.first?.summary == "Du er satt opp i runde 1")
    }

    @Test func ikkeIOppstillingenViserBareHele() throws {
        let lineup = try #require(EveningLineup(rows: fourball, viewer: [id(99)]))
        #expect(lineup.mine.isEmpty)
        #expect(lineup.title == "Oppstillingen")
        #expect(lineup.notInLineupText == "Oppstillingen for runde 1 er klar.")
        #expect(lineup.rounds.first?.groups.count == 2)
    }

    @Test func flereRunderSortertPaaNummer() throws {
        let second = [row(1, "Thomas", bay: 1, team: nil, round: roundTwo, roundNo: 2, format: "stableford"),
                      row(9, "Ola", bay: 1, team: nil, round: roundTwo, roundNo: 2, format: "stableford")]
        let lineup = try #require(EveningLineup(rows: second + fourball, viewer: [me]))
        #expect(lineup.rounds.map(\.number) == [1, 2])
        #expect(lineup.showsRoundTitles)
        #expect(lineup.mine.map(\.roundTitle) == ["Runde 1", "Runde 2"])
        #expect(lineup.mine.last?.summary == "Bås 1 med Ola")
        #expect(lineup.notInLineupText == "Oppstillingen for runde 1 og runde 2 er klar.")
    }

    @Test func rundenavnetBrukesNaarDetFinnes() throws {
        let rows = [EventLineupRow(roundID: roundOne, roundNo: 1, roundName: "Finalen", format: nil, teeTime: nil,
                                   memberID: me, name: "Thomas", bayNo: 1, teamNo: nil, isMarker: false, sharedAt: nil)]
        let round = try #require(EveningLineup(rows: rows, viewer: [me])?.rounds.first)
        #expect(round.title == "Finalen")
        #expect(round.detail == nil)
    }

    @Test func raderFraRpcenDekodes() throws {
        let json = """
        [{"round_id":"00000000-0000-0000-0000-000000000100","round_no":1,"round_name":null,"format":"fourball",
          "tee_time":"18:00:00","member_id":"00000000-0000-0000-0000-000000000001","name":"Thomas",
          "bay_no":2,"team_no":3,"is_marker":true,"shared_at":null}]
        """
        let rows = try JSONDecoder().decode([EventLineupRow].self, from: Data(json.utf8))
        #expect(rows == [row(1, "Thomas", bay: 2, team: 3, marker: true)])
        #expect(rows.first?.venue == nil)
    }
}
