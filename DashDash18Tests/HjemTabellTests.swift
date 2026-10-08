import Foundation
import GolfgutuCore
import Testing
@testable import DashDash18

// Plassbytte i tabellen (fase 19, `table_changed`): hvem som står i linja, teksten (lik
// push-send/logic_test.ts «plassbytte»), og hendelsen gjennom databasen og tilbake.

private func id(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))! }
private let anders = id(1), bjorn = id(2), cato = id(3), dag = id(4), thomas = id(9)
private let names = [anders: "Anders", bjorn: "Bjørn", cato: "Cato", dag: "Dag", thomas: "Thomas"]
private func name(_ id: UUID) -> String { names[id] ?? "Noen" }

private func board(_ rows: [(UUID, Int, Double)], results: Bool = true) -> TableBoard {
    TableBoard(standings: rows.map { TableStanding(id: $0.0, place: $0.1, points: $0.2) }, hasResults: results)
}

private func spot(_ member: UUID, _ place: Int, from: Int?, points: Double? = nil) -> ActivityTableSpot {
    ActivityTableSpot(member: member, place: place, from: from, points: points)
}

private let competition = CompetitionRow(
    id: id(500), kind: .season, name: "Jakkeracet", clubID: id(900), ownerID: nil, seasonID: id(501), status: .active,
    entry: .club, rules: .golfgutu, startsOn: nil, endsOn: nil, isMain: true, requiresPurchase: false,
    entitlementID: nil)

struct HjemTabellendringTests {
    @Test func toppTreOgAlleSomFlyttetSeg() throws {
        let before = board([(anders, 1, 50), (bjorn, 2, 48), (cato, 3, 40), (dag, 4, 30), (thomas, 5, 29)])
        let after = board([(anders, 1, 52), (bjorn, 2, 50), (thomas, 3, 49.5), (cato, 4, 41), (dag, 5, 30)])
        let spots = try #require(TableChange.spots(before: before, after: after))
        #expect(spots == [spot(anders, 1, from: 1, points: 52), spot(bjorn, 2, from: 2, points: 50),
                          spot(thomas, 3, from: 5, points: 49.5), spot(cato, 4, from: 3, points: 41),
                          spot(dag, 5, from: 4, points: 30)])
        #expect(spots.map(\.move) == [0, 0, 2, -1, -1])
    }

    @Test func ingenFlyttetSegGirIngenLinje() {
        let before = board([(anders, 1, 50), (bjorn, 2, 48)])
        let after = board([(anders, 1, 54), (bjorn, 2, 49)])
        #expect(TableChange.spots(before: before, after: after) == nil)
        #expect(TableChange.event(competition: competition, roundNo: 3, before: before, after: after) == nil)
    }

    @Test func førsteRundeHarIngenPlassÅKommeFra() throws {
        // Før første runde er plassene bare navnerekkefølgen: ingen «klatret».
        let before = board([(anders, 1, 0), (bjorn, 2, 0), (cato, 3, 0), (dag, 4, 0)], results: false)
        let after = board([(cato, 1, 12), (anders, 2, 10), (dag, 3, 8), (bjorn, 4, 2)])
        let spots = try #require(TableChange.spots(before: before, after: after))
        #expect(spots == [spot(cato, 1, from: nil, points: 12), spot(anders, 2, from: nil, points: 10),
                          spot(dag, 3, from: nil, points: 8)])
        #expect(TableChangeText.headline(table: spots, competitionName: "Jakkeracet", roundNo: 1, name: name)
                == "Cato leder Jakkeracet etter runde 1")
    }

    @Test func tomTabellEtterpåGirIngenLinje() {
        let empty = board([(anders, 1, 0), (bjorn, 2, 0)], results: false)
        #expect(TableChange.spots(before: empty, after: empty) == nil)
    }

    @Test func storeKonkurranserKappesTil40() throws {
        let n = 60
        let before = board((0..<n).map { (id(1000 + $0), $0 + 1, Double(n - $0)) })
        // Alle bytter plass med naboen.
        let after = board((0..<n).map { i in (id(1000 + i), i % 2 == 0 ? i + 2 : i, Double(n - i)) })
        let spots = try #require(TableChange.spots(before: before, after: after))
        #expect(spots.count == TableChange.maxSpots)
        #expect(spots.map(\.place) == Array(1...40))
    }

    @Test func poengeneRundesTilToDesimaler() throws {
        let spots = try #require(TableChange.spots(before: board([(anders, 1, 1), (bjorn, 2, 0.5)]),
                                                   after: board([(bjorn, 1, 3.3333333), (anders, 2, 1)])))
        #expect(spots.first?.points == 3.33)
    }
}

struct HjemTabellTekstTests {
    private let climb = [spot(anders, 1, from: 1, points: 58), spot(bjorn, 2, from: 3, points: 55),
                         spot(cato, 3, from: 5, points: 49.5)]

    @Test func overskriftenErDenSammeForAlle() {
        #expect(TableChangeText.headline(table: climb, competitionName: "Jakkeracet", roundNo: 3, name: name)
                == "Cato klatret til 3. plass i Jakkeracet etter runde 3")
        let newLeader = [spot(bjorn, 1, from: 2), spot(anders, 2, from: 1), spot(cato, 3, from: 6)]
        #expect(TableChangeText.headline(table: newLeader, competitionName: "Jakkeracet", roundNo: 3, name: name)
                == "Bjørn har tatt ledelsen i Jakkeracet etter runde 3")
        // Likt hopp: best plass vinner.
        let tie = [spot(anders, 1, from: 1), spot(bjorn, 2, from: 4), spot(cato, 4, from: 6)]
        #expect(TableChangeText.headline(table: tie, competitionName: "Jakkeracet", roundNo: 3, name: name)
                == "Bjørn klatret til 2. plass i Jakkeracet etter runde 3")
        #expect(TableChangeText.headline(table: [spot(anders, 1, from: 1)], competitionName: "Morrocupen",
                                         roundNo: nil, name: name) == "Tabellen i Morrocupen er oppdatert")
        #expect(TableChangeText.headline(table: [spot(id(77), 1, from: 2)], competitionName: "Jakkeracet",
                                         roundNo: 3, name: name) == "Noen har tatt ledelsen i Jakkeracet etter runde 3")
    }

    @Test func settFraDeg() {
        let me: Set<UUID> = [thomas]
        func personal(_ table: [ActivityTableSpot]) -> String {
            TableChangeText.personal(table: table, competitionName: "Jakkeracet", roundNo: 3, me: me, name: name)
        }
        #expect(personal([spot(anders, 1, from: 1), spot(thomas, 3, from: 5)]) == "Du klatret til 3. plass i Jakkeracet etter runde 3")
        #expect(personal([spot(thomas, 1, from: 2), spot(anders, 2, from: 1)]) == "Du tok ledelsen i Jakkeracet etter runde 3")
        #expect(personal([spot(anders, 2, from: 4), spot(thomas, 3, from: 2)]) == "Anders gikk forbi deg i Jakkeracet etter runde 3")
        #expect(personal([spot(anders, 1, from: 3), spot(bjorn, 2, from: 4), spot(thomas, 4, from: 2)])
                == "Anders og Bjørn gikk forbi deg i Jakkeracet etter runde 3")
        // Falt uten at noen under deg gikk forbi (en annen falt også).
        #expect(personal([spot(thomas, 4, from: 3)]) == "Du falt til 4. plass i Jakkeracet etter runde 3")
        #expect(personal([spot(thomas, 1, from: nil), spot(anders, 2, from: nil)]) == "Du leder Jakkeracet etter runde 3")
        // Ikke i linja, eller står stille: den vanlige teksten.
        #expect(personal(climb) == "Cato klatret til 3. plass i Jakkeracet etter runde 3")
        #expect(personal([spot(thomas, 1, from: 1), spot(cato, 2, from: 4)]) == "Cato klatret til 2. plass i Jakkeracet etter runde 3")
    }

    @Test func oppsummeringenSierBareDetSomAngårDeg() {
        let me: Set<UUID> = [thomas]
        func phrase(_ table: [ActivityTableSpot]) -> String? {
            TableChangeText.summaryPhrase(table: table, competitionName: "Jakkeracet", me: me, name: name)
        }
        #expect(phrase([spot(thomas, 3, from: 5)]) == "du klatret til 3. plass i Jakkeracet")
        #expect(phrase([spot(thomas, 1, from: 2)]) == "du tok ledelsen i Jakkeracet")
        #expect(phrase([spot(anders, 2, from: 4), spot(thomas, 3, from: 2)]) == "Anders gikk forbi deg i Jakkeracet")
        #expect(phrase([spot(thomas, 4, from: 3)]) == "du falt til 4. plass i Jakkeracet")
        #expect(phrase([spot(thomas, 2, from: 2)]) == nil)
        #expect(phrase(climb) == nil)
    }
}

struct HjemTabellHendelseTests {
    private let event = ActivityEvent.tableChanged(
        competition: id(500), competitionName: "Jakkeracet", roundNo: 3,
        table: [spot(anders, 1, from: 1, points: 58), spot(bjorn, 2, from: 3, points: 55),
                spot(cato, 3, from: 5, points: 49.5)])

    @Test func kategorienErRundeneOgTekstenErLikPush() {
        #expect(event.kind == "table_changed")
        #expect(event.category == .round)
        let display = ActivityText.display(event, actor: thomas, name: { names[$0] })
        #expect(display.text == "Cato klatret til 3. plass i Jakkeracet etter runde 3")
        #expect(display.emoji == "📊")
        #expect(display.symbol == "list.number")
    }

    @Test func dataSlikDatabasenFårDem() throws {
        let object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(event.data)) as? [String: Any])
        #expect(Set(object.keys) == ["competition", "competition_name", "round_no", "table"])
        let table = try #require(object["table"] as? [[String: Any]])
        #expect(table[0]["member"] as? String == anders.uuidString)
        #expect(table[2]["from"] as? Int == 5)
        // Første runde: «from» skrives ikke.
        let first = ActivityEvent.tableChanged(competition: id(500), competitionName: "J", roundNo: 1,
                                               table: [spot(anders, 1, from: nil)])
        let o2 = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(first.data)) as? [String: Any])
        #expect((o2["table"] as? [[String: Any]])?.first?.keys.sorted() == ["member", "place"])
    }

    @Test func leserRadenTilbakeOgTålerFeil() throws {
        let json = """
        {"competition":"\(id(500).uuidString)","competition_name":"Jakkeracet","round_no":3,
         "table":[{"member":"\(anders.uuidString)","place":1,"from":2,"points":58}]}
        """
        let data = try JSONDecoder().decode(ActivityData.self, from: Data(json.utf8))
        #expect(ActivityEvent(kind: "table_changed", data: data)
                == .tableChanged(competition: id(500), competitionName: "Jakkeracet", roundNo: 3,
                                 table: [spot(anders, 1, from: 2, points: 58)]))
        let bad = try JSONDecoder().decode(ActivityData.self, from: Data(#"{"competition_name":"J","table":"x"}"#.utf8))
        #expect(ActivityEvent(kind: "table_changed", data: bad) == .unknown(kind: "table_changed"))
        #expect(ActivityEvent(kind: "table_changed", data: ActivityData(competition: id(500), competitionName: "J", table: []))
                == .unknown(kind: "table_changed"))
    }

    @Test func énGangPerRundeOgKonkurranse() {
        let round = id(901)
        #expect(ActivityOnce.key(event, roundID: round) == "table_changed:\(round.uuidString):\(id(500).uuidString)")
        var log = ActivityOnceLog()
        #expect(log.admit([event], roundID: round).count == 1)
        #expect(log.admit([event], roundID: round).isEmpty)
    }

    @Test func hendelsenFraTabellene() throws {
        let before = board([(anders, 1, 50), (bjorn, 2, 40)])
        let after = board([(bjorn, 1, 52), (anders, 2, 50)])
        let made = try #require(TableChange.event(competition: competition, roundNo: 4, before: before, after: after))
        #expect(made == .tableChanged(competition: competition.id, competitionName: "Jakkeracet", roundNo: 4,
                                      table: [spot(bjorn, 1, from: 2, points: 52), spot(anders, 2, from: 1, points: 50)]))
    }

    @Test func loggingenErAvTilPushOgSqlErPåPlass() {
        #expect(HomeFeedFeature.logsTableChanges == false)
    }
}
