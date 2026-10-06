import Foundation
import Testing
@testable import GolfgutuCore

/// Trekant og trekning. Tall: Fixtures/trekant.json, regnet ut av db-nytt.js på scenarioene fra
/// trekant-test.js, pluss egne (handicap avgjør, og rekkefølgen i trekkMatcher, som PWA-en ikke tester).
struct TriangleTests {
    struct Fil: Decodable {
        let trekanter: [T]
        let trekninger: [Trekk]
    }
    struct T: Decodable {
        let navn: String
        let spillere: [Player]
        let runde: Round
        let poeng: [String: Double]?
        let netto: [String: Int]
        let utfallForA: Double?
    }
    struct Deltaker: Decodable { let id: String; let name: String }
    struct Trekk: Decodable {
        let navn: String
        let deltakere: [Deltaker]
        let stilling: [String: Double]
        let omgang: Int
        let par: [[String]]
    }

    let fil: Fil

    init() throws {
        fil = try Fixture.load(Fil.self, "trekant")
    }

    @Test func trekantPoeng() {
        for t in fil.trekanter {
            let m = t.runde.matches[0]
            for p in t.spillere where t.netto[p.id] != nil {
                #expect(Scoring.roundNetTotal(t.runde, player: p, roster: t.spillere) == t.netto[p.id], "\(t.navn): netto \(p.id)")
            }
            let svar = Triangle.points(m, in: t.runde, roster: t.spillere)
            #expect(svar == t.poeng, "\(t.navn)")
            if let svar { #expect(svar.values.reduce(0, +) == 1.5, "\(t.navn): summen er 1,5") }
            // Hull gjelder ikke i en trekant.
            #expect(MatchPlay.standing(m, from: "a", in: t.runde, roster: t.spillere) == nil)
            #expect(MatchPlay.outcomeForA(m, in: t.runde, roster: t.spillere) == t.utfallForA)
        }
    }

    /// trekant-test.js: 36/18/0 → 1/0,5/0; delt 1.: 0,75/0,75/0; alle likt: 0,5; delt 2.: 1/0,25/0,25.
    @Test func trekantTestensTall() throws {
        func poeng(_ navn: String) throws -> [String: Double]? {
            let t = try #require(fil.trekanter.first { $0.navn == navn })
            return Triangle.points(t.runde.matches[0], in: t.runde, roster: t.spillere)
        }
        #expect(try poeng("36/18/0") == ["a": 1, "b": 0.5, "c": 0])
        #expect(try poeng("delt førsteplass") == ["a": 0.75, "b": 0.75, "c": 0])
        #expect(try poeng("alle likt") == ["a": 0.5, "b": 0.5, "c": 0.5])
        #expect(try poeng("delt andreplass") == ["a": 1, "b": 0.25, "c": 0.25])
        #expect(try poeng("tredjemann mangler") == nil)
    }

    @Test func ikkeTrekantGirNil() {
        let r = Round(holeScores: ["a": [0: 4], "b": [0: 4]])
        #expect(Triangle.points(Match(playerA: "a", playerB: "b"), in: r, roster: []) == nil)
    }

    /// Plasspoengene fra regelsettet. Egen: [3, 1, 0] med delt førsteplass gir 2/2/0.
    @Test func plasspoengFraRegelsettet() throws {
        let t = try #require(fil.trekanter.first { $0.navn == "delt førsteplass" })
        var regler = Ruleset.golfgutu
        #expect(regler.table.trianglePoints == [1, 0.5, 0])
        regler.table.trianglePoints = [3, 1, 0]
        let svar = Triangle.points(t.runde.matches[0], in: t.runde, roster: t.spillere, rules: regler)
        #expect(svar == ["a": 2, "b": 2, "c": 0])
        // Et lagret regelsett uten feltet får Golfgutu-verdien.
        let gammelt = try JSONDecoder().decode(Ruleset.self, from: Data("""
        {"seedingGroups":[],"externalHandicap":false,"defaultFormID":"stableford","maxPerBay":4,"evenings":7,
         "matchPoints":{"win":1,"draw":0.5,"loss":0},"sidePrizes":{"enabled":true,"points":1}}
        """.utf8))
        #expect(gammelt.table.trianglePoints == [1, 0.5, 0])
    }

    @Test func trekkMatcher() {
        for t in fil.trekninger {
            let deltakere = t.deltakere.map { Player(id: $0.id, name: $0.name) }
            #expect(Triangle.drawMatches(deltakere, round: t.omgang, standing: t.stilling) == t.par, "\(t.navn)")
        }
    }

    /// trekant-test.js §1 (antall), og rekkefølgen, som PWA-en ikke tester: stilling synkende,
    /// så norsk navn (æ, ø, å etter z), snudd på oddetall omgang, trekant av de tre siste.
    @Test func trekkMatcherRekkefolge() {
        let fem = ["a", "b", "c", "d", "e"].map { Player(id: $0, name: "Spiller " + $0.uppercased()) }
        let par5 = Triangle.drawMatches(fem, round: 0, standing: [:])
        #expect(par5.count == 2 && par5.filter { $0.count == 3 }.count == 1)
        #expect(par5.flatMap { $0 }.count == 5)
        #expect(Triangle.drawMatches(Array(fem.prefix(4)), round: 0, standing: [:]).allSatisfy { $0.count == 2 })
        #expect(Triangle.drawMatches(Array(fem.prefix(3)), round: 0, standing: [:]) == [["a", "b", "c"]])
        #expect(Triangle.drawMatches(Array(fem.prefix(1)), round: 0, standing: [:]).isEmpty)

        let sju = [("a", "Åse"), ("b", "Øyvind"), ("c", "Ærlig"), ("d", "Zorro"), ("e", "Anders"), ("f", "bjørn"), ("g", "Bjørn")]
            .map { Player(id: $0.0, name: $0.1) }
        // Alle likt: Anders, bjørn, Bjørn, Zorro, Ærlig, Øyvind, Åse.
        #expect(Triangle.drawMatches(sju, round: 0, standing: [:]) == [["e", "f"], ["g", "d"], ["c", "b", "a"]])
        #expect(Triangle.drawMatches(sju, round: 1, standing: [:]) == [["a", "b"], ["c", "d"], ["g", "f", "e"]])
        // Stilling først: f 3; c og a 2 (Ærlig før Åse); g og d 1; b 0,5; e 0.
        let stilling: [String: Double] = ["a": 2, "b": 0.5, "c": 2, "d": 1, "e": 0, "f": 3, "g": 1]
        #expect(Triangle.drawMatches(sju, round: 0, standing: stilling) == [["f", "c"], ["a", "g"], ["d", "b", "e"]])
        #expect(Triangle.drawMatches(sju, round: 2, standing: stilling) == [["f", "c"], ["a", "g"], ["d", "b", "e"]])
    }
}
