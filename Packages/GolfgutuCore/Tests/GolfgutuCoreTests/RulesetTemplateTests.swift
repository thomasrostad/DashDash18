import Foundation
import Testing
@testable import GolfgutuCore

/// Oppsettene i «Ny turnering» (fase 18) og `table.pointsSource` i JSON-en.
struct RulesetTemplateTests {
    @Test func oppsetteneErGyldige() {
        for t in RulesetTemplate.allCases {
            #expect(t.rules.validate().isEmpty, "\(t)")
            #expect(t.rules.competitionRules.validate().isEmpty, "\(t)")
            #expect(!t.title.isEmpty && !t.summary.isEmpty)
        }
    }

    @Test func matchspillSerienErGolfgutu() {
        #expect(RulesetTemplate.matchSeries.rules == Ruleset.golfgutu)
        #expect(Ruleset.golfgutu.table.pointsSource == .matches)
    }

    /// Cup og morro: det «Ny konkurranse» lagrer med malen (`CompetitionDraft.rules`).
    @Test func cupOgMorroErKonkurransemalen() {
        var expected = Ruleset.golfgutu
        expected.competition = CompetitionRules(league: .league, fun: .fun, cup: .standard)
        #expect(RulesetTemplate.cup.rules == expected)
        #expect(RulesetTemplate.fun.rules == expected)
    }

    @Test func stablefordSerien() {
        let r = RulesetTemplate.stablefordSeries.rules
        let g = Ruleset.golfgutu
        #expect(r.table.pointsSource == .stableford)
        #expect(r.table.counting == .init(unit: .evening, best: 5))
        #expect(r.table.stablefordCounting == .init(unit: .evening, best: 5))
        #expect(r.evenings == g.evenings)
        #expect(!r.sidePrizes.longestDrive.enabled && !r.sidePrizes.closestToPin.enabled)
        #expect(r.handicap.seedingGroups.isEmpty)
        #expect(r.formats.defaultFormID == "stableford")
        #expect(r.formats.maxPerBay == g.formats.maxPerBay)
        #expect(r.allowance(for: CompetitionForm.form(id: "stableford")) == 0.95)
        #expect(r.competition == nil)
        #expect(RulesetTemplate.stablefordSeries.differences(in: g) == [
            "handicap.seedingGroups", "sidePrizes.closestToPin.enabled", "sidePrizes.longestDrive.enabled",
            "table.counting.best", "table.counting.unit", "table.pointsSource",
            "table.stablefordCounting.unit", "table.tiebreaks",
        ])
    }

    @Test func gjenkjenning() {
        #expect(RulesetTemplate.matching(.golfgutu) == .matchSeries)
        #expect(RulesetTemplate.matching(RulesetTemplate.stablefordSeries.rules) == .stablefordSeries)
        // Cup og morro har samme regelsett; typen skiller dem.
        #expect(RulesetTemplate.matching(RulesetTemplate.fun.rules, among: [.fun]) == .fun)
        #expect(RulesetTemplate.matching(RulesetTemplate.fun.rules, among: [.cup]) == .cup)
        #expect(RulesetTemplate.matching(.golfgutu, among: [.stablefordSeries]) == nil)

        var tilpasset = RulesetTemplate.stablefordSeries.rules
        tilpasset.evenings = 10
        tilpasset.table.counting.best = 7
        #expect(RulesetTemplate.matching(tilpasset) == nil)
        #expect(RulesetTemplate.stablefordSeries.differences(in: tilpasset) == ["evenings", "table.counting.best"])
        #expect(RulesetTemplate.closest(to: tilpasset, among: [.stablefordSeries, .matchSeries]) == .stablefordSeries)

        var golf = Ruleset.golfgutu
        golf.table.matchPoints.win = 2
        #expect(RulesetTemplate.matchSeries.differences(in: golf) == ["table.matchPoints.win"])
        #expect(RulesetTemplate.closest(to: golf, among: [.stablefordSeries, .matchSeries]) == .matchSeries)
        #expect(RulesetTemplate.closest(to: golf, among: []) == nil)
    }

    @Test func endringerISmåFelt() {
        var r = Ruleset.golfgutu
        #expect(r.changedFields(from: .golfgutu).isEmpty)
        r.handicap.formAllowances["stableford"] = 1
        r.competition = .standard
        r.tips.defaultStakePoints += 1
        #expect(r.changedFields(from: .golfgutu) == [
            "competition", "handicap.formAllowances.stableford", "tips.defaultStakePoints",
        ])
    }

    // MARK: JSON

    /// Golfgutu skriver ikke `pointsSource`, og JSON-en er den samme som fixturen.
    @Test func golfgutuJSONErUendret() throws {
        let encoded = try JSONEncoder().encode(Ruleset.golfgutu)
        let object = try #require(try JSONSerialization.jsonObject(with: encoded) as? NSDictionary)
        let fixture = try #require(try JSONSerialization.jsonObject(with: Fixture.data("regelsett-golfgutu")) as? NSDictionary)
        // Fixturen har gruppene fra før tips og veddemål kom; de skal være like.
        for case let key as String in fixture.allKeys {
            #expect((object[key] as AnyObject).isEqual(fixture[key]), "\(key)")
        }
        #expect((object["table"] as? NSDictionary)?["pointsSource"] == nil)
        // Byte for byte (sorterte nøkler) som før fase 18: regelsett-golfgutu-hel.json er skrevet av
        // JSONEncoder med `.sortedKeys` på commiten før `pointsSource` kom.
        let sortedBefore = JSONEncoder()
        sortedBefore.outputFormatting = .sortedKeys
        #expect(try sortedBefore.encode(Ruleset.golfgutu) == Fixture.data("regelsett-golfgutu-hel"))
        #expect(try JSONDecoder().decode(Ruleset.self, from: Fixture.data("regelsett-golfgutu-hel")) == .golfgutu)
        // Samme byte etter en rundtur.
        let again = try JSONEncoder().encode(JSONDecoder().decode(Ruleset.self, from: encoded))
        let sorted = JSONEncoder()
        sorted.outputFormatting = .sortedKeys
        #expect(try sorted.encode(Ruleset.golfgutu) == sorted.encode(JSONDecoder().decode(Ruleset.self, from: again)))
    }

    @Test func pointsSourceRundtur() throws {
        for t in RulesetTemplate.allCases {
            let data = try JSONEncoder().encode(t.rules)
            #expect(try JSONDecoder().decode(Ruleset.self, from: data) == t.rules, "\(t)")
        }
        let data = try JSONEncoder().encode(RulesetTemplate.stablefordSeries.rules)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect((json["table"] as? [String: Any])?["pointsSource"] as? String == "stableford")
        // Eldre JSON uten feltet: matcher.
        let eldre = try JSONDecoder().decode(Ruleset.self, from: Data(#"{"version": 2, "table": {"tiebreaks": []}}"#.utf8))
        #expect(eldre.table.pointsSource == .matches)
        let v1 = try JSONDecoder().decode(Ruleset.self, from: Fixture.data("regelsett-golfgutu-v1"))
        #expect(v1.table.pointsSource == .matches)
    }

    @Test func valideringAvPointsSource() {
        var r = RulesetTemplate.stablefordSeries.rules
        r.table.counting = .init(unit: .match, best: nil)
        #expect(r.validate().map(\.field) == ["table.counting.unit"])
        r.table.pointsSource = .matches
        #expect(r.validate().isEmpty)
    }
}
