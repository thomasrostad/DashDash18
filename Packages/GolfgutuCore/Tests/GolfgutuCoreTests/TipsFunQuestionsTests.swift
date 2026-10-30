import Foundation
import Testing
@testable import GolfgutuCore

/// De morsomme tippespørsmålene (sist, brutto, comeback, blanke hull, par 3 og 5, rekke, eagle, ekte
/// birdie, lederen, delt seier, høyt handicap og fire over/under) og Moro-kupongen.
/// Tall: Fixtures/tips-moro-sporsmaal.json, regnet for hånd fra hullscorene (se «utregning» der).
struct TipsFunQuestionsTests {
    struct Fil: Decodable {
        let standard: [String: Double]
        let maler: [TipsNewQuestionsTests.Mal]
        let kvelder: [Kveld]
    }
    struct Forventet: Decodable {
        let sporsmaal: TipsQuestion
        let spillere: [String]?
        let svar: Bool?
        let tall: Double?
        let linje: Double?
        let strøket: Bool?
    }
    struct Kveld: Decodable {
        let navn: String
        let linjer: [String: Double]?
        let spillere: [Player]
        let runder: [TipsTests.Runde]
        let forventet: [Forventet]
    }

    let fil: Fil

    init() throws {
        fil = try Fixture.load(Fil.self, "tips-moro-sporsmaal")
    }

    static func rules(_ linjer: [String: Double]?) -> Ruleset {
        var r = Ruleset.golfgutu
        r.tips.questions = TipsQuestion.catalog
        for (k, v) in linjer ?? [:] {
            if let q = TipsQuestion(rawValue: k) { r.tips.setLine(q, v) }
        }
        return r
    }

    @Test func standardlinjene() {
        #expect(fil.standard.count == Ruleset.TipsRules.golfgutuLines.count - 1, "pluss lengste drive (sidepremiene)")
        for (k, v) in fil.standard {
            let q = TipsQuestion(rawValue: k)
            #expect(q.flatMap { Ruleset.golfgutu.tips.line($0) } == v, "\(k)")
        }
    }

    /// Alle malene, også Moro-kupongen, kjennes igjen; Full kupong er de ni fra før.
    @Test func malene() throws {
        #expect(fil.maler.count == TipsTemplate.allCases.count)
        for m in fil.maler {
            let t = try #require(TipsTemplate(rawValue: m.mal))
            #expect(t.title == m.navn && t.questions == m.sporsmaal, "\(m.navn)")
            #expect(TipsTemplate.matching(m.sporsmaal) == t)
            // Rekkefølgen er katalogens, så malen står seg når et spørsmål slås av og på igjen.
            #expect(TipsQuestion.catalog.filter(t.questions.contains) == t.questions, "\(m.navn)")
        }
        #expect(Set(TipsQuestion.catalog) == Set(TipsQuestion.allCases) && TipsQuestion.catalog.count == TipsQuestion.allCases.count)
    }

    @Test func fasiten() {
        #expect(fil.kvelder.count == 3)
        for k in fil.kvelder {
            let f = Tips.answerKey(rounds: TipsTests.tipsRounds(k.runder, k.spillere), line: 2.5, rules: Self.rules(k.linjer))
            #expect(Set(k.forventet.map(\.sporsmaal)).count == 16, "\(k.navn): alle fra hullscorene")
            for e in k.forventet {
                let q = e.sporsmaal
                if e.strøket == true {
                    #expect(f.isVoid(q), "\(k.navn): \(q) strøket")
                    continue
                }
                #expect(!f.isVoid(q), "\(k.navn): \(q)")
                if q.kind == .player {
                    #expect(f.players(q) == e.spillere, "\(k.navn): \(q)")
                } else {
                    #expect(f.flag(q) == e.svar, "\(k.navn): \(q)")
                }
                #expect(f.outcomes[q]?.figure == e.tall, "\(k.navn): \(q) tall")
                #expect(f.outcomes[q]?.line == e.linje, "\(k.navn): \(q) linje")
            }
        }
    }

    /// De nye spørsmålene endrer ikke fasiten for de fem gamle (tips.json) eller de fire fra før.
    @Test func deGamleErUendret() throws {
        let tips = try Fixture.load(TipsTests.Fil.self, "tips")
        for k in tips.kvelder {
            let rounds = TipsTests.tipsRounds(k.runder, k.spillere)
            var golf = Tips.answerKey(rounds: rounds, line: k.linje)
            let alle = Tips.answerKey(rounds: rounds, line: k.linje, rules: Self.rules(nil))
            golf.outcomes = alle.outcomes
            #expect(golf == alle, "\(k.navn)")
        }
    }

    /// Kupongen tar svar på alle spørsmålene og leser og skriver dem som før (ett felt per spørsmål).
    @Test func kupongen() throws {
        var c = TipsCoupon(playerID: "a")
        for q in TipsQuestion.allCases {
            if q.kind == .player { c.setPlayer(q, "b") } else { c.setFlag(q, false) }
        }
        #expect(c.isComplete(for: TipsQuestion.catalog))
        c.setFlag(.lastPlace, true)
        c.setPlayer(.eagle, "b")
        #expect(c.player(.lastPlace) == "b" && c.flag(.eagle) == false, "feil type ignoreres")
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(c)) as? [String: Any]
        #expect(json?["lastPlace"] as? String == "b" && json?["eagle"] as? Bool == false && json?["playerID"] as? String == "a")
        #expect(try JSONDecoder().decode(TipsCoupon.self, from: JSONEncoder().encode(c)) == c)
        let ukjent = try JSONDecoder().decode(TipsCoupon.self, from: Data(#"{"playerID": "a", "nyttSpm": true, "eagle": "x"}"#.utf8))
        #expect(ukjent == TipsCoupon(playerID: "a"), "ukjent spørsmål og feil type hoppes over")
    }

    /// Titlene med linja, og at den riktige linja brukes per spørsmål.
    @Test func titler() {
        var r = Ruleset.golfgutu
        r.tips.setLine(.blankHoles, 9.5)
        #expect(Tips.title(.lastPlacePoints, line: 25.5) == "Sistemann: over eller under 25,5 poeng?")
        #expect(Tips.title(.winningMargin, line: 2.5) == "Seiersmarginen: over eller under 2,5 poeng?")
        #expect(Tips.title(.blankHoles, line: 9.5) == "Over eller under 9,5 blanke hull?")
        #expect(Tips.title(.parOrBetterPlayers, line: 2.5) == "Over eller under 2,5 spillere på par?")
        #expect(Tips.title(.eagle, line: 2.5) == TipsQuestion.eagle.title)
        #expect(Tips.line(for: .blankHoles, eventLine: 1.5, rules: r) == 9.5)
        #expect(Tips.line(for: .winningMargin, eventLine: 1.5, rules: r) == 2.5)
        #expect(Tips.line(for: .lastPlace, eventLine: 1.5, rules: r) == nil)
        for q in TipsQuestion.allCases {
            #expect((Tips.lineLimits(for: q) != nil) == (q.kind == .overUnder && q != .over), "\(q)")
            #expect(!q.title.isEmpty && !q.subtitle.isEmpty)
        }
    }

    /// Linjene skrives bare når de er endret; standarden lagres ikke.
    @Test func kodingOgValidering() throws {
        let golf = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Ruleset.golfgutu.tips)) as? [String: Any]
        #expect(golf?["lines"] == nil)
        var r = Self.rules(["blankHoles": 9.5])
        r.tips.questions = TipsTemplate.fun.questions
        #expect(r.tips.lines == [.blankHoles: 9.5])
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(r.tips)) as? [String: Any]
        #expect(json?["lines"] as? [String: Double] == ["blankHoles": 9.5])
        #expect(try JSONDecoder().decode(Ruleset.self, from: JSONEncoder().encode(r)) == r)
        r.tips.setLine(.blankHoles, 20.5)
        #expect(r.tips.lines.isEmpty, "tilbake på standarden")
        #expect(r.validate().isEmpty)
        r.tips.setLine(.winningMargin, 3)
        r.tips.setLine(.lastPlacePoints, 200.5)
        #expect(Set(r.validate().map(\.field)) == ["tips.lines.winningMargin", "tips.lines.lastPlacePoints"])
        r.tips = .golfgutu
        r.tips.questions = Array(TipsQuestion.catalog.prefix(TipsQuestion.maxPerCoupon + 1))
        #expect(r.validate().map(\.field) == ["tips.questions"])
        r.tips.questions = Array(TipsQuestion.catalog.prefix(TipsQuestion.maxPerCoupon))
        #expect(r.validate().isEmpty)
        let ukjent = try JSONDecoder().decode(Ruleset.TipsRules.self,
                                              from: Data(#"{"lines": {"nyttSpm": 1.5, "winner": 2.5, "blankHoles": 3.5}}"#.utf8))
        #expect(ukjent.lines == [.blankHoles: 3.5], "ukjent spørsmål og spørsmål uten linje hoppes over")
    }

    // MARK: Sidepremiene (Fixtures/tips-sidepremier.json)

    struct SideFil: Decodable {
        let standardLinje: Double
        let spillere: [Player]
        let kvelder: [SideKveld]
    }
    struct SideForventet: Decodable {
        let longestDrive, closestToPin: [String]?
        let lengste, naermest: Double?
        let over: Bool?
    }
    struct SideKveld: Decodable {
        let navn: String
        let linje: Double?
        let runder: [TipsTests.Runde]
        let krav: [SideClaim]
        let forventet: SideForventet
    }

    @Test func sidepremiene() throws {
        let fil = try Fixture.load(SideFil.self, "tips-sidepremier")
        #expect(Ruleset.golfgutu.tips.line(.longestDriveMeters) == fil.standardLinje)
        #expect(fil.kvelder.count == 4)
        for k in fil.kvelder {
            var rules = Self.rules(nil)
            if let l = k.linje { rules.tips.setLine(.longestDriveMeters, l) }
            let rounds = k.runder.map { r in
                TipsRound(round: r.round, roster: fil.spillere, isDraft: r.isDraft,
                          sideClaims: k.krav.filter { $0.roundId == r.round.id })
            }
            let f = Tips.answerKey(rounds: rounds, line: 2.5, rules: rules)
            let e = k.forventet
            #expect(f.players(.longestDrive) == e.longestDrive, "\(k.navn): longest drive")
            #expect(f.players(.closestToPin) == e.closestToPin, "\(k.navn): nærmest pinnen")
            #expect(f.outcomes[.longestDrive]?.figure == e.lengste, "\(k.navn): lengste")
            #expect(f.outcomes[.closestToPin]?.figure == e.naermest, "\(k.navn): nærmest")
            #expect(f.flag(.longestDriveMeters) == e.over, "\(k.navn): over/under")
            #expect(f.isVoid(.longestDriveMeters) == (e.over == nil), "\(k.navn)")
            #expect(f.outcomes[.longestDriveMeters]?.line == (e.over == nil ? nil : rules.tips.line(.longestDriveMeters)))
        }
        #expect(Tips.title(.longestDriveMeters, line: 250.5) == "Longest drive: over eller under 250,5 m?")
    }

    // MARK: Kveldens hull og forrige kvelds vinner (Fixtures/tips-kveldens-hull.json)

    struct HullFil: Decodable {
        let standardHull: Int
        let hull: [HullKveld]
        let forrige: [ForrigeSak]
    }
    struct HullSak: Decodable { let hull: Int; let spillere: [String]?; let tall: Double? }
    struct HullKveld: Decodable { let kveld: String; let saker: [HullSak] }
    struct ForrigeSak: Decodable { let kveld: String; let forrige: [String]?; let svar: Bool? }

    @Test func kveldensHullOgForrigeVinner() throws {
        let fil = try Fixture.load(HullFil.self, "tips-kveldens-hull")
        #expect(Ruleset.golfgutu.tips.featuredHole == fil.standardHull)
        func kveld(_ navn: String) throws -> Kveld { try #require(self.fil.kvelder.first { $0.navn == navn }) }
        for k in fil.hull {
            let kv = try kveld(k.kveld)
            for sak in k.saker {
                var rules = Self.rules(kv.linjer)
                rules.tips.featuredHole = sak.hull
                let f = Tips.answerKey(rounds: TipsTests.tipsRounds(kv.runder, kv.spillere), line: 2.5, rules: rules)
                #expect(f.players(.featuredHole) == sak.spillere, "\(k.kveld): hull \(sak.hull)")
                #expect(f.outcomes[.featuredHole]?.figure == sak.tall, "\(k.kveld): hull \(sak.hull)")
                #expect(Tips.title(.featuredHole, line: 2.5, rules: rules) == "Lavest netto på hull \(sak.hull)?")
            }
        }
        for sak in fil.forrige {
            let kv = try kveld(sak.kveld)
            let f = Tips.answerKey(rounds: TipsTests.tipsRounds(kv.runder, kv.spillere), line: 2.5, rules: Self.rules(nil),
                                   previousWinners: sak.forrige)
            #expect(f.flag(.previousWinnerWins) == sak.svar, "\(sak.kveld): forrige \(sak.forrige ?? [])")
            #expect(f.isVoid(.previousWinnerWins) == (sak.svar == nil))
        }
        // Lagres bare når det ikke er standard, og valideres.
        var r = Ruleset.golfgutu
        #expect(try JSONSerialization.jsonObject(with: JSONEncoder().encode(r.tips)) as? [String: Any] != nil)
        r.tips.featuredHole = 7
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(r.tips)) as? [String: Any]
        #expect(json?["featuredHole"] as? Int == 7)
        #expect(try JSONDecoder().decode(Ruleset.self, from: JSONEncoder().encode(r)) == r)
        #expect(r.validate().isEmpty)
        r.tips.featuredHole = 19
        #expect(r.validate().map(\.field) == ["tips.featuredHole"])
        let golf = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Ruleset.golfgutu.tips)) as? [String: Any]
        #expect(golf?["featuredHole"] == nil)
    }
}
