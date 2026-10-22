import Foundation
import Testing
@testable import GolfgutuCore

/// Spørsmålene på kupongen kommer fra regelsettet (`Ruleset.TipsRules.questions`).
/// Tall: Fixtures/tips-sporsmaal.json, avledet av tips.json (riktig/feil per spørsmål fra db-nytt.js).
struct TipsQuestionsTests {
    struct Fil: Decodable {
        let standard: [TipsQuestion]
        let utvalg: [Utvalg]
        let kuponger: [Kupong]
        let json: [JSONSak]
    }
    struct Rad: Decodable { let spiller: String; let poeng: Int; let riktig: [String: Bool?] }
    struct Forventet: Decodable {
        let resultat: String
        let rader: [Rad]
        let mulige, maks: Int
        let vinnere: [String]
    }
    struct Utvalg: Decodable { let navn: String; let sporsmaal: [TipsQuestion]; let resultater: [Forventet] }
    struct Kupong: Decodable {
        let navn: String
        let kupong: TipsCoupon
        let sporsmaal: [TipsQuestion]
        let besvart: Int
        let komplett: Bool
    }
    struct JSONSak: Decodable { let navn: String; let sporsmaal: [TipsQuestion] }

    let fil: Fil
    let tips: TipsTests.Fil

    init() throws {
        fil = try Fixture.load(Fil.self, "tips-sporsmaal")
        tips = try Fixture.load(TipsTests.Fil.self, "tips")
    }

    static func rules(_ questions: [TipsQuestion]) -> Ruleset {
        var r = Ruleset.golfgutu
        r.tips.questions = questions
        return r
    }

    /// Standarden er PWA-ens fem, i kupongens rekkefølge.
    @Test func standardenErDeFem() {
        #expect(Ruleset.golfgutu.tips.questions == fil.standard)
        #expect(Ruleset.TipsRules.golfgutuQuestions == fil.standard)
        #expect(tips.sporsmaal.map { TipsTests.felt[$0.felt] } == fil.standard)
        for t in RulesetTemplate.allCases {
            #expect(t.rules.tips.questions == fil.standard, "\(t)")
        }
    }

    /// Golfgutu-oppsettet gir nøyaktig det samme som før, også når regelsettet sendes med.
    @Test func golfgutuErUendret() {
        for r in tips.resultater {
            let key = Tips.answerKey(rounds: TipsTests.tipsRounds(r.runder, r.spillere), line: r.linje)
            let uten = Tips.result(coupons: r.kuponger, key: key, players: r.spillere)
            let med = Tips.result(coupons: r.kuponger, key: key, players: r.spillere, rules: .golfgutu)
            #expect(med == uten, "\(r.navn)")
            #expect(med.possible == r.forventet.mulige, "\(r.navn)")
        }
    }

    /// Færre spørsmål: bare de i regelsettet gir poeng og teller i «mulige».
    @Test func faerreSporsmaal() throws {
        #expect(fil.utvalg.count == 3)
        for u in fil.utvalg {
            let rules = Self.rules(u.sporsmaal)
            for e in u.resultater {
                let r = try #require(tips.resultater.first { $0.navn == e.resultat })
                let key = Tips.answerKey(rounds: TipsTests.tipsRounds(r.runder, r.spillere), line: r.linje)
                let res = Tips.result(coupons: r.kuponger, key: key, players: r.spillere, rules: rules)
                let navn = "\(u.navn) / \(e.resultat)"
                #expect(res.rows.map(\.playerID) == e.rader.map(\.spiller), "\(navn): rekkefølge")
                #expect(res.rows.map(\.points) == e.rader.map(\.poeng), "\(navn): poeng")
                for (row, js) in zip(res.rows, e.rader) {
                    #expect(Set(row.correct.keys) == Set(u.sporsmaal), "\(navn): bare regelsettets spørsmål")
                    for (q, verdi) in js.riktig {
                        let q = try #require(TipsQuestion(rawValue: q))
                        #expect(row.correct[q] == .some(verdi), "\(navn): \(row.playerID) \(q)")
                    }
                }
                #expect(res.possible == e.mulige, "\(navn): mulige")
                #expect(res.best == e.maks, "\(navn): maks")
                #expect(res.winners == e.vinnere, "\(navn): vinnere")
            }
        }
    }

    /// `tipsKomplett` og antall besvarte gjelder bare spørsmålene på kupongen.
    @Test func kompletMedFaerre() {
        for k in fil.kuponger {
            #expect(k.kupong.isComplete(for: k.sporsmaal) == k.komplett, "\(k.navn)")
            #expect(k.kupong.answeredCount(for: k.sporsmaal) == k.besvart, "\(k.navn)")
        }
        let c = fil.kuponger[0].kupong
        #expect(c.isComplete(for: Ruleset.golfgutu.tips.questions) == c.isComplete)
        #expect(c.answeredCount(for: Ruleset.golfgutu.tips.questions) == c.answeredCount)
    }

    /// Mangler `questions`, gjelder standarden; et ukjent spørsmål stopper ikke regelsettet.
    @Test func dekoding() throws {
        // `tips` leses rått fra fixturen og legges i et regelsett.
        let raw = try #require(try JSONSerialization.jsonObject(with: Fixture.data("tips-sporsmaal")) as? [String: Any])
        let saker = try #require(raw["json"] as? [[String: Any]])
        #expect(saker.count == fil.json.count)
        for (obj, sak) in zip(saker, fil.json) {
            let data = try JSONSerialization.data(withJSONObject: ["version": 2, "tips": obj["tips"] ?? [:]])
            let r = try JSONDecoder().decode(Ruleset.self, from: data)
            #expect(r.tips.questions == sak.sporsmaal, "\(sak.navn)")
        }
        let uten = try JSONDecoder().decode(Ruleset.self, from: Data(#"{"version": 2}"#.utf8))
        #expect(uten.tips.questions == fil.standard)
    }

    /// Standarden skrives ikke (JSON-en er som før); en annen liste skrives og leses tilbake.
    @Test func koding() throws {
        let golf = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Ruleset.golfgutu.tips)) as? [String: Any]
        #expect(golf?["questions"] == nil)
        let r = Self.rules([.over, .winner])
        let tilbake = try JSONDecoder().decode(Ruleset.self, from: JSONEncoder().encode(r))
        #expect(tilbake == r && tilbake.tips.questions == [.over, .winner])
        #expect(r.changedFields(from: .golfgutu) == ["tips.questions"])
    }
}
