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
        #expect(k.TELLENDE_MATCHER == 0 && g.table.counting == .init(unit: .match, best: nil))
        #expect(g.table.stablefordCounting == .init(unit: .round, best: k.TELLENDE_RUNDER))
        #expect(g.table.matchPoints == .init(win: k.POENG_SEIER, draw: k.POENG_DELT, loss: k.POENG_TAP))
        #expect(g.handicap.seedingGroups.map(\.number) == k.SEEDING_GRUPPER.map(\.nr))
        #expect(g.handicap.seedingGroups.map(\.handicap) == k.SEEDING_GRUPPER.map(\.hcp))
        #expect(g.handicap.seedingGroups.map(\.name) == k.SEEDING_GRUPPER.map(\.navn))
        #expect(g.formats.maxPerBay == k.SPILLERE_PER_BAAS)
        #expect(g.formats.defaultFormID == k.FORM_STANDARD)
        #expect(g.sidePrizes.longestDrive == .init(enabled: true, points: k.SIDEPREMIE_POENG))
        #expect(g.sidePrizes.closestToPin == .init(enabled: true, points: k.SIDEPREMIE_POENG))
        #expect(g.handicap.externalHandicap == k.HCP_EXTERN_NY_RUNDE)
        #expect(g.handicap.allowanceOverride == nil)
        // Konstantene i db-nytt.js som ikke står i fixturen: POENG_NETTO_PAR = 2 og max(0, …) i
        // pointsForHole, TREKANT_POENG, lagHandicap og matchSlag, fmtPoeng/matchSum til halve,
        // 1 / vinnere.length i sidepremieResultaterFor, og alle 16 former valgbare.
        #expect(g.scoring == .init(netParPoints: 2, minimumPoints: 0))
        #expect(g.table.trianglePoints == [1, 0.5, 0])
        #expect(g.table.roundingStep == 0.5)
        #expect(g.sidePrizes.splitTies)
        #expect(g.formats.matchStrokes == .lowestFromScratch)
        #expect(g.formats.allowedFormIDs == CompetitionForm.all.map(\.id))
        #expect(g.handicap.teamHandicapRule(for: "scramble-4") == .init(method: .weighted, weights: [0.25, 0.20, 0.15, 0.10]))
        for f in CompetitionForm.all where f.teamSize == 2 {
            #expect(g.handicap.teamHandicapRule(for: f.id) == .average, "\(f.id)")
        }
        #expect(g.handicap.teamHandicapRule(for: "fourball-4") == .lowest)
    }

    /// app-nytt.js linje 7853: `(form.hcpAndel !== null && form.kort === 'per spiller') ? form.hcpAndel : 1`.
    @Test func andelForNyRunde() throws {
        let andeler = try Fixture.load(Fil.self, "regelsett").andelForNyRunde
        #expect(andeler.count == CompetitionForm.all.count)
        for a in andeler {
            #expect(Ruleset.golfgutu.allowance(for: CompetitionForm.form(id: a.formId)) == a.andel, "\(a.formId)")
        }
        var fast = Ruleset.golfgutu
        fast.handicap.allowanceOverride = 0.85
        #expect(fast.allowance(for: CompetitionForm.form(id: "stableford")) == 0.85)
    }

    @Test func malenSomJSON() throws {
        let mal = try JSONDecoder().decode(Ruleset.self, from: Fixture.data("regelsett-golfgutu"))
        #expect(mal == Ruleset.golfgutu)
        let rundtur = try JSONDecoder().decode(Ruleset.self, from: JSONEncoder().encode(Ruleset.golfgutu))
        #expect(rundtur == Ruleset.golfgutu)
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Ruleset.golfgutu)) as? [String: Any]
        #expect(json?["version"] as? Int == 2)
    }

    /// Versjon 1 (flat) leses fortsatt, og skjemaets standard `{"version": 1}` blir Golfgutu-oppsettet.
    @Test func versjonEnLesesFortsatt() throws {
        let v1 = try JSONDecoder().decode(Ruleset.self, from: Fixture.data("regelsett-golfgutu-v1"))
        #expect(v1 == Ruleset.golfgutu)
        let tom = try JSONDecoder().decode(Ruleset.self, from: Data(#"{"version": 1}"#.utf8))
        #expect(tom == Ruleset.golfgutu)
        let annet = try JSONDecoder().decode(Ruleset.self, from: Data("""
        {"countingEvenings": 3, "stablefordCountingEvenings": null, "maxPerBay": 3,
         "matchPoints": {"win": 3, "draw": 1, "loss": 0}, "sidePrizes": {"enabled": false, "points": 2}}
        """.utf8))
        #expect(annet.table.counting == .init(unit: .match, best: 3))
        #expect(annet.table.stablefordCounting == .init(unit: .round, best: nil))
        #expect(annet.formats.maxPerBay == 3)
        #expect(annet.table.matchPoints == .init(win: 3, draw: 1, loss: 0))
        #expect(annet.sidePrizes.longestDrive == .init(enabled: false, points: 2))
        #expect(annet.sidePrizes.closestToPin == .init(enabled: false, points: 2))
        // Versjon 2 med bare noen felt: resten fra Golfgutu. `roundingStep: null` er et valg.
        let delvis = try JSONDecoder().decode(Ruleset.self, from: Data("""
        {"version": 2, "evenings": 5, "table": {"roundingStep": null}}
        """.utf8))
        #expect(delvis.evenings == 5)
        #expect(delvis.table.roundingStep == nil)
        #expect(delvis.table.matchPoints == Ruleset.golfgutu.table.matchPoints)
        #expect(delvis.handicap == Ruleset.golfgutu.handicap)
    }

    /// Verdiene som var faste i koden, styres nå av regelsettet. Utledet fra formlene.
    @Test func regelverdierFraRegelsettet() {
        // Stableford: par 4, 5 brutto uten slag = bogey. Golfgutu 1 poeng; netto par 3 gir 2.
        var r = Ruleset.golfgutu
        #expect(Scoring.points(par: 4, gross: 5, handicap: 0, strokeIndex: 1, holes: 18, rules: r) == 1)
        r.scoring.netParPoints = 3
        #expect(Scoring.points(par: 4, gross: 5, handicap: 0, strokeIndex: 1, holes: 18, rules: r) == 2)
        // Bunn: 9 på par 4 gir max(0, 4 − 9 + 2) = 0; med bunn −1: max(−1, −3) = −1.
        r.scoring.netParPoints = 2
        #expect(Scoring.points(par: 4, gross: 9, handicap: 0, strokeIndex: 1, holes: 18, rules: r) == 0)
        r.scoring.minimumPoints = -1
        #expect(Scoring.points(par: 4, gross: 9, handicap: 0, strokeIndex: 1, holes: 18, rules: r) == -1)
        // Tomt hull med nettopar gir poeng for netto par.
        let avkortet = Round(avkortRegel: "nettopar")
        #expect(Truncation.pointsForEmptyHole(avkortet) == 2)
        r.scoring.netParPoints = 3
        #expect(Truncation.pointsForEmptyHole(avkortet, rules: r) == 3)

        // Lagshandicap i scramble-2 (12 og 6 på 18 hull uten bane): snitt 9; laveste · 1: 6;
        // vektet 0,5/0,25 (lavest først): 3 + 3 = 6.
        let a = Player(id: "a", handicap: 12), b = Player(id: "b", handicap: 6)
        let lag = Round(gameType: "scramble-2", holeCount: 18, hcpAllowance: 1)
        #expect(Handicap.teamHandicap(in: lag, members: [a, b]) == 9)
        var laveste = Ruleset.golfgutu
        laveste.handicap.teamHandicap["scramble-2"] = .lowest
        #expect(Handicap.teamHandicap(in: lag, members: [a, b], rules: laveste) == 6)
        laveste.handicap.teamHandicap["scramble-2"] = .init(method: .weighted, weights: [0.5, 0.25])
        #expect(Handicap.teamHandicap(in: lag, members: [a, b], rules: laveste) == 6)

        // Andel per form. Mangler formen i lista: 1.
        var andel = Ruleset.golfgutu
        andel.handicap.formAllowances["stableford"] = 0.9
        #expect(andel.allowance(for: CompetitionForm.form(id: "stableford")) == 0.9)
        andel.handicap.formAllowances["match"] = nil
        #expect(andel.allowance(for: CompetitionForm.form(id: "match")) == 1)

        // Avrunding i tabellen: 1,3 → 1,5 med halve, 1 med hele, 1,3 uten.
        var tabell = Ruleset.golfgutu
        #expect(tabell.roundTablePoints(1.3) == 1.5)
        tabell.table.roundingStep = 1
        #expect(tabell.roundTablePoints(1.3) == 1)
        tabell.table.roundingStep = nil
        #expect(tabell.roundTablePoints(1.3) == 1.3)

        // Tillatte former begrenser forslagene.
        var former = Ruleset.golfgutu
        former.formats.allowedFormIDs = ["stableford", "match"]
        #expect(former.suggestions(players: 8).map(\.id) == ["stableford", "match"])
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
        annet.handicap.seedingGroups = [SeedingGroup(number: 2, handicap: 7, name: "Gruppe 2")]
        #expect(annet.effectiveHandicap(for: b, in: r, roster: [b]) == 7)
        annet.handicap.seedingGroups = []
        #expect(annet.effectiveHandicap(for: b, in: r, roster: [b]) == 23)

        // Maks per bås fra regelsettet.
        #expect(Ruleset.golfgutu.setup(formID: "scramble-4", players: 16).isOK)
        var smaa = Ruleset.golfgutu
        smaa.formats.maxPerBay = 3
        #expect(!smaa.setup(formID: "scramble-4", players: 16).isOK)
        #expect(!smaa.suggestions(players: 16).contains { $0.id == "scramble-4" })
    }

    // MARK: Gyldighetssjekk

    @Test func golfgutuErGyldig() {
        #expect(Ruleset.golfgutu.validate().isEmpty)
    }

    /// Ett problem om gangen, med feltet det gjelder.
    @Test func ugyldigeRegelsett() {
        func felt(_ endre: (inout Ruleset) -> Void) -> [String] {
            var r = Ruleset.golfgutu
            endre(&r)
            return r.validate().map(\.field)
        }
        #expect(felt { $0.evenings = 0 } == ["evenings"])
        // Beste N > antall kvelder, og beste 0.
        #expect(felt { $0.evenings = 5; $0.table.counting = .init(unit: .evening, best: 6) } == ["table.counting.best"])
        #expect(felt { $0.evenings = 5; $0.table.counting = .init(unit: .evening, best: 5) }.isEmpty)
        #expect(felt { $0.table.counting = .init(unit: .match, best: 0) } == ["table.counting.best"])
        #expect(felt { $0.table.counting = .init(unit: .match, best: 12) }.isEmpty)  // matcher kan være flere enn kvelder
        #expect(felt { $0.table.stablefordCounting = .init(unit: .evening, best: 8) } == ["table.stablefordCounting.best"])
        #expect(felt { $0.table.stablefordCounting = .init(unit: .match, best: 5) } == ["table.stablefordCounting.unit"])
        // Negative poeng.
        #expect(felt { $0.table.matchPoints.loss = -1 } == ["table.matchPoints.loss"])
        #expect(felt { $0.table.matchPoints = .init(win: 1, draw: 2, loss: 0) } == ["table.matchPoints"])
        #expect(felt { $0.sidePrizes.closestToPin.points = -1 } == ["sidePrizes.closestToPin.points"])
        #expect(felt { $0.scoring.netParPoints = -2; $0.scoring.minimumPoints = -5 } == ["scoring.netParPoints"])
        #expect(felt { $0.scoring.minimumPoints = 3 } == ["scoring.minimumPoints"])
        // Trekant: tre verdier, ikke negative, synkende.
        #expect(felt { $0.table.trianglePoints = [1, 0] } == ["table.trianglePoints"])
        #expect(felt { $0.table.trianglePoints = [1, 0.5, -1] } == ["table.trianglePoints"])
        #expect(felt { $0.table.trianglePoints = [0, 0.5, 1] } == ["table.trianglePoints"])
        #expect(felt { $0.table.roundingStep = 0 } == ["table.roundingStep"])
        #expect(felt { $0.table.roundingStep = nil }.isEmpty)
        #expect(felt { $0.table.tiebreaks = [.stableford, .stableford] } == ["table.tiebreaks"])
        // Handicap.
        #expect(felt { $0.handicap.allowanceOverride = 1.2 } == ["handicap.allowanceOverride"])
        #expect(felt { $0.handicap.formAllowances["match"] = -0.1 } == ["handicap.formAllowances.match"])
        #expect(felt { $0.handicap.seedingGroups.append(SeedingGroup(number: 1, handicap: 3, name: "X")) } == ["handicap.seedingGroups"])
        #expect(felt { $0.handicap.teamHandicap["scramble-4"] = .init(method: .weighted) } == ["handicap.teamHandicap.scramble-4"])
        // Maks per bås og former.
        #expect(felt { $0.formats.maxPerBay = 0 } == ["formats.maxPerBay"])
        #expect(felt { $0.formats.allowedFormIDs = [] } == ["formats.allowedFormIDs"])
        #expect(felt { $0.formats.allowedFormIDs.append("golfball-bingo") } == ["formats.allowedFormIDs"])
        #expect(felt { $0.formats.allowedFormIDs = ["match"] } == ["formats.defaultFormID"])

        // Meldingene er norske og nevner tallene.
        var r = Ruleset.golfgutu
        r.evenings = 5
        r.table.counting = .init(unit: .evening, best: 6)
        #expect(r.validate().first?.message == "Tabellen: beste 6 kvelder er flere enn de 5 kveldene i sesongen.")
        r = .golfgutu
        r.formats.allowedFormIDs = []
        #expect(r.validate().first?.message == "Minst én konkurranseform må være tillatt.")
    }
}
