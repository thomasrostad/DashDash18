import Foundation
import Testing
@testable import GolfgutuCore

/// Regelsettet (B12). Tall: Fixtures/regelsett.json (konstantene i db-nytt.js og andelen fra
/// handleStartRunde i app-nytt.js) og Fixtures/regelsett-golfgutu.json (malen som JSON).
struct RulesetTests {
    struct Fil: Decodable {
        struct Gruppe: Decodable { let nr: Int; let hcp: Double; let navn: String }
        struct K: Decodable {
            let SESONG_RUNDER: Int
            let TELLENDE_RUNDER: Int
            let TELLENDE_MATCHER: Int
            let POENG_SEIER: Double
            let POENG_DELT: Double
            let POENG_TAP: Double
            let SEEDING_GRUPPER: [Gruppe]
            let SPILLERE_PER_BAAS: Int
            let FORM_STANDARD: String
            let SIDEPREMIE_POENG: Double
            let HCP_EXTERN_NY_RUNDE: Bool
        }
        struct Andel: Decodable { let formId: String; let andel: Double }
        let konstanter: K
        let andelForNyRunde: [Andel]
    }

    @Test func golfgutuGjengirPWA() throws {
        let k = try Fixture.load(Fil.self, "regelsett").konstanter
        let g = Ruleset.golfgutu
        #expect(g.evenings == k.SESONG_RUNDER)
        // TELLENDE_MATCHER = 0 betyr «alle teller» i PWA-en.
        #expect(k.TELLENDE_MATCHER == 0 && g.countingEvenings == nil)
        #expect(g.stablefordCountingEvenings == k.TELLENDE_RUNDER)
        #expect(g.matchPoints == .init(win: k.POENG_SEIER, draw: k.POENG_DELT, loss: k.POENG_TAP))
        #expect(g.seedingGroups.map(\.number) == k.SEEDING_GRUPPER.map(\.nr))
        #expect(g.seedingGroups.map(\.handicap) == k.SEEDING_GRUPPER.map(\.hcp))
        #expect(g.seedingGroups.map(\.name) == k.SEEDING_GRUPPER.map(\.navn))
        #expect(g.maxPerBay == k.SPILLERE_PER_BAAS)
        #expect(g.defaultFormID == k.FORM_STANDARD)
        #expect(g.sidePrizes == .init(enabled: true, points: k.SIDEPREMIE_POENG))
        #expect(g.externalHandicap == k.HCP_EXTERN_NY_RUNDE)
        #expect(g.allowanceOverride == nil)
    }

    /// app-nytt.js linje 7853: `(form.hcpAndel !== null && form.kort === 'per spiller') ? form.hcpAndel : 1`.
    @Test func andelForNyRunde() throws {
        let andeler = try Fixture.load(Fil.self, "regelsett").andelForNyRunde
        #expect(andeler.count == CompetitionForm.all.count)
        for a in andeler {
            #expect(Ruleset.golfgutu.allowance(for: CompetitionForm.form(id: a.formId)) == a.andel, "\(a.formId)")
        }
        var fast = Ruleset.golfgutu
        fast.allowanceOverride = 0.85
        #expect(fast.allowance(for: CompetitionForm.form(id: "stableford")) == 0.85)
    }

    @Test func malenSomJSON() throws {
        let mal = try JSONDecoder().decode(Ruleset.self, from: Fixture.data("regelsett-golfgutu"))
        #expect(mal == Ruleset.golfgutu)
        let rundtur = try JSONDecoder().decode(Ruleset.self, from: JSONEncoder().encode(Ruleset.golfgutu))
        #expect(rundtur == Ruleset.golfgutu)
    }

    /// Golfgutu-regelsettet gir samme svar som standardverdiene i funksjonene (seeding-test.js-tall).
    @Test func regelsettetStyrerFunksjonene() {
        let b = Player(id: "b", handicap: 18.4, seedGroup: 2)
        let r = Round(gameType: "stableford", holeCount: 18,
                      course: Course(par: 72, courseRating: 74.1, slopeRating: 136), hcpAllowance: 0.95)
        #expect(Ruleset.golfgutu.effectiveHandicap(for: b, in: r, roster: [b]) == 5)

        // Egen: andre gruppetall i regelsettet slår igjennom; uten grupper er spilleren useedet.
        // Utledet: round(courseHandicap(18,4; 74,1; 136; 72) · 0,95) = round(24 · 0,95) = 23.
        var annet = Ruleset.golfgutu
        annet.seedingGroups = [SeedingGroup(number: 2, handicap: 7, name: "Gruppe 2")]
        #expect(annet.effectiveHandicap(for: b, in: r, roster: [b]) == 7)
        annet.seedingGroups = []
        #expect(annet.effectiveHandicap(for: b, in: r, roster: [b]) == 23)

        // Maks per bås fra regelsettet.
        #expect(Ruleset.golfgutu.setup(formID: "scramble-4", players: 16).isOK)
        var smaa = Ruleset.golfgutu
        smaa.maxPerBay = 3
        #expect(!smaa.setup(formID: "scramble-4", players: 16).isOK)
        #expect(!smaa.suggestions(players: 16).contains { $0.id == "scramble-4" })
    }
}
