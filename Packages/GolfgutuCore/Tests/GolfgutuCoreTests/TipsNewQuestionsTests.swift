import Foundation
import Testing
@testable import GolfgutuCore

/// De nye tippespørsmålene (antall birdier, flest birdier, siste ni, vinnerens poeng) og malene.
/// Tall: Fixtures/tips-nye-sporsmaal.json, regnet for hånd fra hullscorene (se «utregning» der).
struct TipsNewQuestionsTests {
    struct Fil: Decodable {
        let standard: Linjer
        let maler: [Mal]
        let kvelder: [Kveld]
        let resultat: Resultat
    }
    struct Linjer: Decodable { let birdieCountLine, winnerPointsLine: Double }
    struct Mal: Decodable { let mal, navn: String; let sporsmaal: [TipsQuestion] }
    struct Forventet: Decodable {
        let birdieCount: Bool?
        let birdies: Int?
        let mostBirdies: [String]?
        let mostBirdiesCount: Int?
        let backNine: [String]?
        let backNineNet: Int?
        let overWinnerPoints: Bool?
        let winnerPoints: Int?
    }
    struct Kveld: Decodable {
        let navn: String
        let linjer: Linjer?
        let spillere: [Player]
        let runder: [TipsTests.Runde]
        let forventet: Forventet
    }
    struct Rad: Decodable { let spiller: String; let poeng: Int }
    struct MalResultat: Decodable {
        let mal: String
        let rader: [Rad]
        let mulige, maks: Int
        let vinnere: [String]
    }
    struct Resultat: Decodable {
        let kveld: String
        let linje: Double
        let kuponger: [TipsCoupon]
        let resultater: [MalResultat]
    }

    let fil: Fil

    init() throws {
        fil = try Fixture.load(Fil.self, "tips-nye-sporsmaal")
    }

    static func rules(_ linjer: Linjer?, questions: [TipsQuestion] = TipsQuestion.catalog) -> Ruleset {
        var r = Ruleset.golfgutu
        r.tips.questions = questions
        if let linjer {
            r.tips.birdieCountLine = linjer.birdieCountLine
            r.tips.winnerPointsLine = linjer.winnerPointsLine
        }
        return r
    }

    @Test func standardlinjene() {
        #expect(Ruleset.golfgutu.tips.birdieCountLine == fil.standard.birdieCountLine)
        #expect(Ruleset.golfgutu.tips.winnerPointsLine == fil.standard.winnerPointsLine)
    }

    /// Klassisk er Golfgutus fem; Full kupong er alle; hver mal kjennes igjen på spørsmålene.
    @Test func malene() throws {
        #expect(fil.maler.count == TipsTemplate.allCases.count)
        for m in fil.maler {
            let t = try #require(TipsTemplate(rawValue: m.mal))
            #expect(t.title == m.navn)
            #expect(t.questions == m.sporsmaal, "\(m.navn)")
            #expect(TipsTemplate.matching(m.sporsmaal) == t)
        }
        #expect(TipsTemplate.classic.questions == Ruleset.TipsRules.golfgutuQuestions)
        #expect(Set(TipsTemplate.full.questions) == Set(TipsQuestion.allCases))
        #expect(TipsTemplate.matching([.over, .winner]) == nil)
        for t in TipsTemplate.allCases {
            #expect(Self.rules(nil, questions: t.questions).validate().isEmpty, "\(t)")
        }
    }

    @Test func fasiten() {
        #expect(fil.kvelder.count == 7)
        for k in fil.kvelder {
            let rules = Self.rules(k.linjer)
            let f = Tips.answerKey(rounds: TipsTests.tipsRounds(k.runder, k.spillere), line: 2.5, rules: rules)
            let e = k.forventet
            #expect(f.birdieCount == e.birdieCount, "\(k.navn): antall birdier")
            #expect(f.birdies == e.birdies, "\(k.navn): birdier")
            #expect(f.mostBirdies == e.mostBirdies, "\(k.navn): flest birdier")
            #expect(f.mostBirdiesCount == e.mostBirdiesCount, "\(k.navn): birdiene til den beste")
            #expect(f.backNine == e.backNine, "\(k.navn): siste ni")
            #expect(f.backNineNet == e.backNineNet, "\(k.navn): netto siste ni")
            #expect(f.overWinnerPoints == e.overWinnerPoints, "\(k.navn): vinnerens poeng")
            #expect(f.winnerPoints == e.winnerPoints, "\(k.navn): vinnerpoeng")
            #expect(f.birdieCountLine == rules.tips.birdieCountLine && f.winnerPointsLine == rules.tips.winnerPointsLine)
            #expect(f.isVoid(.mostBirdies) == (e.mostBirdies == nil), "\(k.navn)")
            #expect(f.figure(.birdieCount) == e.birdies && f.figure(.backNine) == e.backNineNet, "\(k.navn)")
        }
    }

    /// De nye spørsmålene endrer ikke fasiten for de fem gamle (tips.json).
    @Test func deGamleErUendret() {
        let tips = try? Fixture.load(TipsTests.Fil.self, "tips")
        for k in tips?.kvelder ?? [] {
            let rounds = TipsTests.tipsRounds(k.runder, k.spillere)
            let golf = Tips.answerKey(rounds: rounds, line: k.linje)
            let full = Tips.answerKey(rounds: rounds, line: k.linje, rules: Self.rules(nil))
            #expect(golf == full, "\(k.navn)")
            #expect(golf.winner == k.forventet.svar.vinner && golf.over == k.forventet.svar.over, "\(k.navn)")
        }
    }

    /// Resultatlista med hver mal på samme kveld og samme kuponger.
    @Test func resultatetPerMal() throws {
        let r = fil.resultat
        let k = try #require(fil.kvelder.first { $0.navn == r.kveld })
        #expect(r.resultater.count == 3)
        for e in r.resultater {
            let t = try #require(TipsTemplate(rawValue: e.mal))
            let rules = Self.rules(k.linjer, questions: t.questions)
            let key = Tips.answerKey(rounds: TipsTests.tipsRounds(k.runder, k.spillere), line: r.linje, rules: rules)
            let res = Tips.result(coupons: r.kuponger, key: key, players: k.spillere, rules: rules)
            #expect(res.rows.map(\.playerID) == e.rader.map(\.spiller), "\(t): rekkefølge")
            #expect(res.rows.map(\.points) == e.rader.map(\.poeng), "\(t): poeng")
            #expect(res.possible == e.mulige, "\(t): mulige")
            #expect(res.best == e.maks, "\(t): maks")
            #expect(res.winners == e.vinnere, "\(t): vinnere")
            for row in res.rows { #expect(Set(row.correct.keys) == Set(t.questions), "\(t)") }
        }
    }

    /// Titlene med linja, og at den riktige linja brukes per spørsmål.
    @Test func titler() {
        var r = Ruleset.golfgutu
        r.tips.birdieCountLine = 9.5
        #expect(Tips.title(.birdieCount, line: 14.5) == "Over eller under 14,5 birdier?")
        #expect(Tips.title(.winnerPoints, line: 37.5) == "Vinneren: over eller under 37,5 poeng?")
        #expect(Tips.title(.over, line: 2.5) == "Over eller under +2,5?")
        #expect(Tips.title(.backNine, line: 2.5) == TipsQuestion.backNine.title)
        #expect(Tips.line(for: .over, eventLine: 1.5, rules: r) == 1.5)
        #expect(Tips.line(for: .birdieCount, eventLine: 1.5, rules: r) == 9.5)
        #expect(Tips.line(for: .winnerPoints, eventLine: 1.5, rules: r) == 37.5)
        #expect(Tips.line(for: .winner, eventLine: 1.5, rules: r) == nil)
    }

    /// Svarene på de nye spørsmålene settes, leses og sammenlignes som de gamle.
    @Test func kupongen() {
        var c = TipsCoupon(playerID: "a")
        for q in TipsQuestion.allCases {
            if q.kind == .player { c.setPlayer(q, "b") } else { c.setFlag(q, true) }
        }
        #expect(c.isComplete(for: TipsTemplate.full.questions))
        #expect(c.answeredCount(for: TipsTemplate.birdieHunt.questions) == 5)
        var d = c
        #expect(d.hasSameAnswers(as: c))
        d.setFlag(.winnerPoints, false)
        #expect(!d.hasSameAnswers(as: c), "et nytt spørsmål teller i sammenligningen")
        d.setFlag(.winnerPoints, true)
        d.setPlayer(.backNine, nil)
        #expect(!d.isComplete(for: TipsTemplate.full.questions) && d.isComplete(for: TipsTemplate.classic.questions))
        // Kupongen leses fra JSON uten de nye feltene (som i tips.json).
        let gammel = try? JSONDecoder().decode(TipsCoupon.self, from: Data(#"{"playerID": "a", "winner": "b"}"#.utf8))
        #expect(gammel?.mostBirdies == nil && gammel?.winner == "b")
    }

    /// Linjene skrives bare når de ikke er standard, så JSON-en for regelsett fra før er som før.
    @Test func kodingOgValidering() throws {
        let golf = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Ruleset.golfgutu.tips)) as? [String: Any]
        #expect(golf?["birdieCountLine"] == nil && golf?["winnerPointsLine"] == nil)
        var r = Self.rules(Linjer(birdieCountLine: 5.5, winnerPointsLine: 30.5), questions: TipsTemplate.birdieHunt.questions)
        let tilbake = try JSONDecoder().decode(Ruleset.self, from: JSONEncoder().encode(r))
        #expect(tilbake == r)
        #expect(r.changedFields(from: .golfgutu) == ["tips.birdieCountLine", "tips.questions", "tips.winnerPointsLine"])
        #expect(r.validate().isEmpty)
        r.tips.birdieCountLine = 5
        r.tips.winnerPointsLine = 150.5
        r.tips.questions = []
        #expect(Set(r.validate().map(\.field)) == ["tips.birdieCountLine", "tips.winnerPointsLine", "tips.questions"])
        r.tips = .golfgutu
        r.tips.questions = [.winner, .winner]
        #expect(r.validate().map(\.field) == ["tips.questions"])
    }
}
