import Foundation
import Testing
@testable import GolfgutuCore

/// Ordet for en dag i turneringen (09.10.2026): «kveld» for Golfgutu, «spilledag» for nye turneringer.
struct DayTermTests {
    @Test func ordformene() {
        #expect([DayTerm.evening.one, DayTerm.evening.the, DayTerm.evening.many, DayTerm.evening.theMany]
            == ["kveld", "kvelden", "kvelder", "kveldene"])
        #expect([DayTerm.playingDay.one, DayTerm.playingDay.the, DayTerm.playingDay.many, DayTerm.playingDay.theMany]
            == ["spilledag", "spilledagen", "spilledager", "spilledagene"])
        #expect(DayTerm.evening.today == "I kveld" && DayTerm.playingDay.today == "I dag")
        #expect(DayTerm.playingDay.title == "Spilledag")
        #expect(DayTerm.capitalized("kvelden") == "Kvelden")
        #expect(DayTerm.playingDay.possessive == "spilledagens" && DayTerm.evening.possessive == "kveldens")
        #expect(DayTerm.evening.count(1) == "1 kveld" && DayTerm.playingDay.count(3) == "3 spilledager")
    }

    @Test func golfgutuSierKveld() {
        #expect(Ruleset.golfgutu.dayTerm == nil)
        #expect(Ruleset.golfgutu.day == .evening)
    }

    /// Regelsett fra før har ikke feltet, og JSON-en for Golfgutu er som før.
    @Test func jsonUtenFeltetErSomFør() throws {
        let data = try JSONEncoder().encode(Ruleset.golfgutu)
        let text = String(decoding: data, as: UTF8.self)
        #expect(!text.contains("dayTerm"))
        #expect(try JSONDecoder().decode(Ruleset.self, from: data).day == .evening)
    }

    @Test func ordetLagresOgLesesIgjen() throws {
        var rules = RulesetTemplate.stablefordSeries.rules
        rules.dayTerm = .playingDay
        let back = try JSONDecoder().decode(Ruleset.self, from: JSONEncoder().encode(rules))
        #expect(back == rules && back.day == .playingDay)
    }

    /// Ordet er ikke en regel: oppsettet kjennes igjen, og det står ikke som en endring.
    @Test func ordetErIkkeEnEndringFraOppsettet() {
        var rules = Ruleset.golfgutu
        rules.dayTerm = .playingDay
        #expect(RulesetTemplate.matching(rules) == .matchSeries)
        #expect(RulesetTemplate.matchSeries.differences(in: rules).isEmpty)
        #expect(RulesetTemplate.closest(to: rules) == .matchSeries)
    }
}
