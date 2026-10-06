import Foundation
import Testing
@testable import GolfgutuCore

/// Tippekupongen. Tall: Fixtures/tips.json (oppsettet i tippekupong-test.js, forventet regnet av
/// db-nytt.js: tipsStarttid, tipsFrist, tipsFasit, tipsResultat og potten i tipsOppgjor).
struct TipsTests {
    struct Fil: Decodable {
        let standard: Standard
        let sporsmaal: [Sporsmaal]
        let frister: [Frist]
        let kvelder: [Kveld]
        let resultater: [Resultat]
    }
    struct Standard: Decodable { let innsats: Int; let linje: Double; let start: String; let innsatsValg: [Int] }
    struct Sporsmaal: Decodable { let felt, type, tittel, under: String }
    struct Frist: Decodable { let dato, tid, start, frist: String }
    struct Runde: Decodable { let round: Round; let isDraft: Bool }
    struct Svar: Decodable {
        let vinner, forsteNi, flestPar: [String]?
        let birdie, over: Bool?
    }
    struct Tall: Decodable {
        let vinner, forsteNi, flestPar: Int?
        let snitt: Double?
        let linje: Double
    }
    struct Fasit: Decodable { let ferdig: Bool; let felt: [String]; let svar: Svar; let tall: Tall }
    struct Kveld: Decodable { let navn: String; let linje: Double; let spillere: [Player]; let runder: [Runde]; let forventet: Fasit }
    struct Rad: Decodable { let spiller: String; let poeng: Int; let riktig: [String: Bool?] }
    struct ResultatForventet: Decodable {
        let ferdig: Bool
        let rader: [Rad]
        let mulige, maks: Int
        let vinnere: [String]
        let pott, deltakere: Int
    }
    struct Resultat: Decodable {
        let navn: String
        let innsats: Int
        let linje: Double
        let spillere: [Player]
        let runder: [Runde]
        let kuponger: [TipsCoupon]
        let forventet: ResultatForventet
    }

    let fil: Fil

    init() throws {
        fil = try Fixture.load(Fil.self, "tips")
    }

    /// PWA-ens felt → spørsmålet.
    static let felt: [String: TipsQuestion] = [
        "vinner": .winner, "forsteNi": .frontNine, "flestPar": .mostPars, "birdie": .birdie, "over": .over,
    ]

    static func tipsRounds(_ runder: [Runde], _ spillere: [Player]) -> [TipsRound] {
        runder.map { TipsRound(round: $0.round, roster: spillere, isDraft: $0.isDraft) }
    }

    @Test func standardeneErGolfgutu() {
        let t = Ruleset.golfgutu.tips
        #expect(t.defaultStakePoints == fil.standard.innsats)
        #expect(t.defaultLine == fil.standard.linje)
        #expect(t.defaultStartTime == fil.standard.start)
        #expect(t.stakeOptions == fil.standard.innsatsValg)
        #expect(Tips.stake(nil) == 50 && Tips.line(nil) == 2.5)
        #expect(Tips.stake(0) == 0, "0 er for æra, ikke standarden")
        #expect(Tips.stake(20) == 20 && Tips.line(-1.5) == -1.5)
    }

    @Test func sporsmaaleneErLikePWA() {
        #expect(fil.sporsmaal.count == TipsQuestion.allCases.count)
        for (q, js) in zip(TipsQuestion.allCases, fil.sporsmaal) {
            #expect(Self.felt[js.felt] == q)
            #expect(q.title == js.tittel)
            #expect(q.subtitle == js.under)
            let type: TipsQuestion.Kind = js.type == "spiller" ? .player : js.type == "janei" ? .yesNo : .overUnder
            #expect(q.kind == type)
        }
        #expect(Tips.title(.over, line: 2.5) == "Over eller under +2,5?")
        #expect(Tips.title(.over, line: -1.5) == "Over eller under −1,5?")
        #expect(Tips.formatSigned(2.25, decimals: 2) == "+2,25")
        #expect(Tips.formatSigned(0, decimals: 1) == "±0,0")
    }

    @Test func fristenIOsloTid() {
        let iso = ISO8601DateFormatter()
        #expect(fil.frister.count == 9)
        for f in fil.frister {
            #expect(Tips.startTime(f.tid) == f.start, "\(f.tid)")
            #expect(Tips.deadline(date: f.dato, startTime: f.tid) == iso.date(from: f.frist), "\(f.dato) \(f.tid)")
        }
        #expect(Tips.startTime(nil) == "17:00")
        #expect(Tips.deadline(date: nil, startTime: "17:00") == nil)
        #expect(Tips.deadline(date: "", startTime: "17:00") == nil)
    }

    /// Fristen kommer fra regelsettet når kvelden ikke har klokkeslett.
    @Test func fristenFraRegelsettet() {
        var r = Ruleset.golfgutu
        r.tips.defaultStartTime = "18:30"
        #expect(Tips.startTime(nil, rules: r) == "18:30")
        #expect(Tips.startTime("19:00:00", rules: r) == "19:00")
        let iso = ISO8601DateFormatter()
        #expect(Tips.deadline(date: "2026-10-08", startTime: nil, rules: r) == iso.date(from: "2026-10-08T16:30:00Z"))
    }

    /// tippekupong-test.js, «Låsen»: 14:59Z åpen, 15:00Z låst, første score låser.
    @Test func laasen() {
        let iso = ISO8601DateFormatter()
        let frist = Tips.deadline(date: "2026-10-08", startTime: "17:00–20:00")
        let foer = iso.date(from: "2026-10-08T14:59:00Z")!, etter = iso.date(from: "2026-10-08T15:00:00Z")!
        #expect(Tips.isOpen(deadline: frist, now: foer, hasScore: false))
        #expect(!Tips.isOpen(deadline: frist, now: etter, hasScore: false))
        let tidlig = TipsRound(round: Round(holeScores: ["a": [0: 4]]), roster: [])
        let tom = TipsRound(round: Round(holeScores: ["a": [:]]), roster: [])
        let kladd = TipsRound(round: Round(holeScores: ["a": [0: 4]]), roster: [], isDraft: true)
        #expect(Tips.hasScore([tidlig]))
        #expect(!Tips.hasScore([tom]), "en tom scorerad låser ikke")
        #expect(Tips.hasScore([kladd]), "en score i en kladd låser, som i databasen")
        #expect(!Tips.isOpen(deadline: frist, now: foer, hasScore: Tips.hasScore([tidlig])))
        #expect(!Tips.isOpen(deadline: nil, now: foer, hasScore: false))
    }

    @Test func fasiten() {
        #expect(fil.kvelder.count == 14)
        for k in fil.kvelder {
            let f = Tips.answerKey(rounds: Self.tipsRounds(k.runder, k.spillere), line: k.linje)
            let e = k.forventet
            #expect(f.finished == e.ferdig, "\(k.navn): ferdig")
            #expect(f.field == e.felt.sorted(), "\(k.navn): felt")
            #expect(f.winner == e.svar.vinner, "\(k.navn): vinner")
            #expect(f.frontNine == e.svar.forsteNi, "\(k.navn): første ni")
            #expect(f.mostPars == e.svar.flestPar, "\(k.navn): flest par")
            #expect(f.birdie == e.svar.birdie, "\(k.navn): birdie")
            #expect(f.over == e.svar.over, "\(k.navn): over")
            #expect(f.winnerPoints == e.tall.vinner, "\(k.navn): vinnerpoeng")
            #expect(f.frontNineNet == e.tall.forsteNi, "\(k.navn): netto første ni")
            #expect(f.mostParsHoles == e.tall.flestPar, "\(k.navn): parhull")
            #expect(f.average == e.tall.snitt, "\(k.navn): snitt")
            #expect(f.line == e.tall.linje, "\(k.navn): linje")
        }
    }

    /// Hovedkvelden i tippekupong-test.js, med tallene skrevet ut.
    @Test func hovedkvelden() throws {
        let k = try #require(fil.kvelder.first)
        let f = Tips.answerKey(rounds: Self.tipsRounds(k.runder, k.spillere), line: 2.5)
        #expect(f.winner == ["a", "d"] && f.winnerPoints == 36)
        #expect(f.frontNine == ["d"] && f.frontNineNet == 35)
        #expect(f.mostPars == ["a"] && f.mostParsHoles == 18)
        #expect(f.birdie == true)
        #expect(f.average == 2.25 && f.over == false)
        // Rekkefølgen inn spiller ingen rolle: siste ni først gir samme fasit.
        let snudd = Tips.answerKey(rounds: Self.tipsRounds(k.runder.reversed(), k.spillere), line: 2.5)
        #expect(snudd == f)
    }

    /// Lagret spillehandicap går foran det regnede.
    @Test func fastsattHandicap() throws {
        let k = try #require(fil.kvelder.first { $0.navn.hasPrefix("appens slag") })
        var r = Self.tipsRounds(k.runder, k.spillere)
        #expect(Tips.answerKey(rounds: r, line: 0.5).frontNineNet == 35)
        r[0].handicaps = ["e": 0]
        let f = Tips.answerKey(rounds: r, line: 0.5)
        #expect(f.frontNineNet == 44)
        #expect(f.average == 8.5 && f.over == true)
    }

    @Test func resultatet() {
        #expect(fil.resultater.count == 4)
        for r in fil.resultater {
            let key = Tips.answerKey(rounds: Self.tipsRounds(r.runder, r.spillere), line: r.linje)
            let res = Tips.result(coupons: r.kuponger, key: key, players: r.spillere)
            let e = r.forventet
            #expect(res.finished == e.ferdig, "\(r.navn): ferdig")
            #expect(res.rows.map(\.playerID) == e.rader.map(\.spiller), "\(r.navn): rekkefølge")
            #expect(res.rows.map(\.points) == e.rader.map(\.poeng), "\(r.navn): poeng")
            for (row, js) in zip(res.rows, e.rader) {
                for (felt, verdi) in js.riktig {
                    let q = Self.felt[felt]!
                    #expect(row.correct[q] == .some(verdi), "\(r.navn): \(row.playerID) \(felt)")
                }
            }
            #expect(res.possible == e.mulige, "\(r.navn): mulige")
            #expect(res.best == e.maks, "\(r.navn): maks")
            #expect(res.winners == e.vinnere, "\(r.navn): vinnere")
            let pot = Tips.pot(res, stake: r.innsats)
            #expect(pot.total == e.pott, "\(r.navn): pott")
            #expect(pot.entries == e.deltakere, "\(r.navn): deltakere")
        }
    }

    @Test func forAera() {
        let res = TipsResult(finished: true, answerKey: Tips.answerKey(rounds: [], line: 2.5), rows: [],
                             possible: 0, best: 0, winners: [])
        let pot = Tips.pot(res, stake: 0)
        #expect(pot.isForHonour && pot.total == 0)
    }

    /// `tipsBeste`: likt er likt, sortert på navn (norsk, æ/ø/å etter z).
    @Test func beste() {
        let names = ["x": "Øystein", "y": "Anders", "z": "Zeb"]
        #expect(Tips.best(["x": 5, "y": 5, "z": 5], lowest: false, names: names) == ["y", "z", "x"])
        #expect(Tips.best(["x": 3, "y": 5], lowest: true, names: names) == ["x"])
        #expect(Tips.best([:], lowest: false) == nil)
    }

    /// `tipsRiktig` og `tipsKomplett`.
    @Test func riktigOgKomplett() {
        let key = TipsAnswerKey(finished: false, field: ["a"], winner: ["a", "d"], frontNine: nil, mostPars: ["a"],
                                birdie: true, over: false, winnerPoints: 36, frontNineNet: nil, mostParsHoles: 18,
                                average: 2.25, line: 2.5)
        let c = TipsCoupon(playerID: "b", winner: "d", frontNine: "d", mostPars: nil, birdie: true, over: true)
        #expect(Tips.isCorrect(.winner, coupon: c, key: key) == true, "delt topp: begge er riktige")
        #expect(Tips.isCorrect(.frontNine, coupon: c, key: key) == nil, "strøket")
        #expect(Tips.isCorrect(.mostPars, coupon: c, key: key) == false, "ikke svart")
        #expect(Tips.isCorrect(.birdie, coupon: c, key: key) == true)
        #expect(Tips.isCorrect(.over, coupon: c, key: key) == false)
        #expect(Tips.isCorrect(.winner, coupon: nil, key: key) == false)
        #expect(!c.isComplete && c.answeredCount == 4)
        var full = c
        full.mostPars = "a"
        #expect(full.isComplete)
        full.winner = ""
        #expect(!full.isComplete, "tom id er ikke et svar")
    }

    @Test func regelsettetMedTips() throws {
        // Mangler `tips`, gjelder Golfgutu.
        let uten = try JSONDecoder().decode(Ruleset.self, from: Data(#"{"version": 2}"#.utf8))
        #expect(uten.tips == .golfgutu)
        let delvis = try JSONDecoder().decode(Ruleset.self, from: Data(#"{"version": 2, "tips": {"defaultLine": 1.5}}"#.utf8))
        #expect(delvis.tips.defaultLine == 1.5 && delvis.tips.defaultStakePoints == 50)
        var r = Ruleset.golfgutu
        r.tips = .init(defaultStartTime: "18:00", defaultStakePoints: 0, stakeOptions: [0, 10], defaultLine: 0.5, lineStep: 1)
        #expect(try JSONDecoder().decode(Ruleset.self, from: JSONEncoder().encode(r)) == r)
        #expect(r.validate().isEmpty)
        #expect(Ruleset.golfgutu.validate().isEmpty)
    }

    @Test func ugyldigeTips() {
        var r = Ruleset.golfgutu
        r.tips = .init(defaultStartTime: "25:00", defaultStakePoints: -1, stakeOptions: [], defaultLine: 2, lineStep: 0.5)
        let felt = Set(r.validate().map(\.field))
        #expect(felt == ["tips.defaultStartTime", "tips.defaultStakePoints", "tips.stakeOptions", "tips.defaultLine", "tips.lineStep"])
        #expect(Tips.isValidLine(2.5) && Tips.isValidLine(-9.5) && !Tips.isValidLine(19.5) && !Tips.isValidLine(2))
    }
}
