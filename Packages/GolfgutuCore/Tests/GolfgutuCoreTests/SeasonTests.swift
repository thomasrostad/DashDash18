import Foundation
import Testing
@testable import GolfgutuCore

/// Sesongtabellen. Tall: Fixtures/sesong.json, regnet ut av db-nytt.js på scenarioene fra match-test.js,
/// seier-test.js, sesong-test.js, tropp-test.js, kvelder-test.js og neste-kveld-test.js, pluss egne.
/// `rundePoeng` er PWA-ens `round_points` (regnOmRundePoeng), som vi regner fra scorene.
struct SeasonTests {
    struct Fil: Decodable {
        let saker: [Sak]
        let annetRegelsett: [Annet]
        let fmtPoeng: [Fmt]
        let matchSum: [Sum]
    }
    struct Res: Decodable { let roundId: String; let matchNo: Int?; let poeng: Double; let hull: Int; let trekant: Bool }
    struct SumJS: Decodable { let poeng: Double; let hull: Int; let matcher: Int }
    struct Side: Decodable { let roundId: String; let type: String; let delt: Bool; let poeng: Double }
    struct RS: Decodable { let roundId: String; let poeng: Double }
    struct Tellende: Decodable { let teller: [RS]; let stroket: [RS] }
    struct Per: Decodable {
        let teller: [Res]
        let stroket: [Res]
        let matchSum: SumJS
        let matchHull: Int
        let sidepremier: [Side]
        let sidepremiePoeng: Double
        let rundePoengVektet: [Double?]
        let tellendeRunder: Tellende
        let seasonTotal: Int
    }
    struct Jakke: Decodable { let id: String; let total, duell, side: Double; let matcher, hull, spilte, stableford: Int }
    struct Stableford: Decodable { let id: String; let total, played, teller, stroket: Int }
    struct DatoTall: Decodable {
        let dato: String?; let tall: Int
        init(from decoder: Decoder) throws {
            var c = try decoder.unkeyedContainer()
            dato = try c.decode(String?.self)
            tall = try c.decode(Int.self)
        }
    }
    struct DatoBool: Decodable {
        let dato: String; let ferdig: Bool
        init(from decoder: Decoder) throws {
            var c = try decoder.unkeyedContainer()
            dato = try c.decode(String.self)
            ferdig = try c.decode(Bool.self)
        }
    }
    struct Sak: Decodable {
        let navn: String
        let kilde: String
        let spillere: [Player]
        let runder: [Round]
        let rundePoeng: [[String: Int]]
        let claims: [SideClaim]
        let per: [String: Per]
        let jakketavle: [Jakke]
        let stablefordtavle: [Stableford]
        let kveldsDatoer: [String]
        let antallKvelder: Int
        let rundeNummer: [DatoTall]
        let kveldErFerdig: [DatoBool]
    }
    struct Konstanter: Decodable {
        let POENG_SEIER, POENG_DELT, POENG_TAP: Double?
        let TELLENDE_MATCHER, TELLENDE_RUNDER: Int?
        let TREKANT_POENG: [Double]?
    }
    struct Annet: Decodable { let navn: String; let konstanter: Konstanter; let sak: Sak }
    struct Fmt: Decodable {
        let inn: Double; let ut: String
        init(from decoder: Decoder) throws {
            var c = try decoder.unkeyedContainer()
            // Number(null) = 0, Number('x') = NaN.
            if try c.decodeNil() { inn = 0 } else if let d = try? c.decode(Double.self) { inn = d } else { _ = try c.decode(String.self); inn = .nan }
            ut = try c.decode(String.self)
        }
    }
    struct Sum: Decodable {
        struct Inn: Decodable { let poeng: Double; let hull: Int }
        let inn: [Inn]
        let ut: SumJS
    }

    let fil: Fil

    init() throws {
        fil = try Fixture.load(Fil.self, "sesong")
    }

    /// Sjekker alt i én sak mot db-nytt.js.
    func sjekk(_ sak: Sak, ruleset: Ruleset = .golfgutu, _ hva: String = "") {
        let navn = hva.isEmpty ? sak.navn : hva
        let s = Season(players: sak.spillere, rounds: sak.runder, claims: sak.claims, ruleset: ruleset)
        for i in sak.runder.indices {
            #expect(s.roundPoints(i) == sak.rundePoeng[i], "\(navn): rundepoeng \(sak.runder[i].id ?? "")")
        }
        for p in sak.spillere {
            guard let f = sak.per[p.id] else { Issue.record("\(navn): mangler \(p.id)"); continue }
            let d = s.matchResults(for: p.id)
            func like(_ a: [Season.MatchResult], _ b: [Res]) -> Bool {
                a.count == b.count && zip(a, b).allSatisfy {
                    $0.roundID == $1.roundId && $0.matchNo == $1.matchNo && $0.points == $1.poeng && $0.holes == $1.hull && $0.isTriangle == $1.trekant
                }
            }
            #expect(like(d.counting, f.teller), "\(navn): teller \(p.id)")
            #expect(like(d.dropped, f.stroket), "\(navn): stroket \(p.id)")
            let sum = Season.matchSum(d.counting)
            #expect(sum.points == f.matchSum.poeng && sum.holes == f.matchSum.hull && sum.matches == f.matchSum.matcher, "\(navn): matchSum \(p.id)")
            #expect(s.matchTotals(for: p.id).holes == f.matchHull, "\(navn): matchHullFor \(p.id)")
            let side = s.sidePrizeResults(for: p.id)
            #expect(side.map { $0.roundID ?? "" } == f.sidepremier.map(\.roundId), "\(navn): sidepremier \(p.id)")
            #expect(side.map(\.kind.rawValue) == f.sidepremier.map(\.type), "\(navn): sidepremietype \(p.id)")
            #expect(side.map(\.shared) == f.sidepremier.map(\.delt), "\(navn): delt \(p.id)")
            #expect(side.map(\.points) == f.sidepremier.map(\.poeng), "\(navn): sidepremiepoeng \(p.id)")
            #expect(s.sidePrizePoints(for: p.id) == f.sidepremiePoeng, "\(navn): sidepremiePoengFor \(p.id)")
            #expect(sak.runder.indices.map { s.weightedRoundPoints($0, playerID: p.id) } == f.rundePoengVektet, "\(navn): rundePoengVektet \(p.id)")
            let tr = s.countingRounds(for: p.id)
            #expect(tr.counting.map { $0.roundID ?? "" } == f.tellendeRunder.teller.map(\.roundId), "\(navn): tellende runder \(p.id)")
            #expect(tr.counting.map(\.points) == f.tellendeRunder.teller.map(\.poeng), "\(navn): tellende poeng \(p.id)")
            #expect(tr.dropped.map(\.points) == f.tellendeRunder.stroket.map(\.poeng), "\(navn): strøkne \(p.id)")
            #expect(s.stablefordTotal(for: p.id) == f.seasonTotal, "\(navn): seasonTotalNytt \(p.id)")
        }
        let tavle = s.jacketBoard()
        #expect(tavle.map(\.player.id) == sak.jakketavle.map(\.id), "\(navn): jakketavla rekkefølge")
        for (r, j) in zip(tavle, sak.jakketavle) {
            #expect(r.total == j.total && r.duel == j.duell && r.side == j.side, "\(navn): jakketavla poeng \(j.id)")
            #expect(r.matches == j.matcher && r.holes == j.hull && r.played == j.spilte && r.stableford == j.stableford,
                    "\(navn): jakketavla \(j.id)")
        }
        let st = s.stablefordBoard()
        #expect(st.map(\.player.id) == sak.stablefordtavle.map(\.id), "\(navn): stablefordtavla")
        #expect(st.map(\.total) == sak.stablefordtavle.map(\.total), "\(navn): stablefordtavla sum")
        #expect(st.map(\.played) == sak.stablefordtavle.map(\.played), "\(navn): stablefordtavla spilt")
        #expect(st.map(\.dropped) == sak.stablefordtavle.map(\.stroket), "\(navn): stablefordtavla strøket")
        #expect(Season.eveningDates(sak.runder) == sak.kveldsDatoer, "\(navn): kveldsDatoer")
        #expect(Season.eveningCount(sak.runder) == sak.antallKvelder, "\(navn): antallKvelder")
        for d in sak.rundeNummer {
            #expect(s.roundNumber(for: d.dato) == d.tall, "\(navn): rundeNummerFor \(d.dato ?? "nil")")
        }
        for d in sak.kveldErFerdig {
            #expect(s.isEveningFinished(d.dato) == d.ferdig, "\(navn): kveldErFerdig \(d.dato)")
        }
    }

    @Test func alleSakerGirSammeSvarSomPWA() {
        #expect(fil.saker.count == 22)
        for sak in fil.saker { sjekk(sak) }
    }

    /// Nøkkeltallene fra PWA-testene.
    @Test func pwaTestenesTall() throws {
        func sesong(_ navn: String) throws -> Season {
            let sak = try #require(fil.saker.first { $0.navn == navn })
            return Season(players: sak.spillere, rounds: sak.runder, claims: sak.claims)
        }
        // match-test.js §1: 5 poeng, hull −31, 7 matcher; Bjørn 2 og speilbildet.
        var s = try sesong("fem knepne seire og to knusende tap")
        #expect(s.matchTotals(for: "a") == Season.MatchSum(points: 5, holes: -31, matches: 7))
        #expect(s.matchTotals(for: "b").points == 2 && s.matchTotals(for: "b").holes == 31)
        #expect(s.matchResults(for: "a").dropped.isEmpty)
        // §2: storseieren først.
        s = try sesong("tre seire og fire tap")
        #expect(s.matchResults(for: "a").counting.first?.holes == 18)
        // seier-test.js: lagseier 1 hver, LD 1 til Anders, Anders 2 og Bjørn 1; med KP 3; lik lengde 0,5.
        s = try sesong("lagseier og longest drive")
        #expect(s.matchTotals(for: "a").points == 1 && s.matchTotals(for: "b").points == 1)
        #expect(s.sidePrizePoints(for: "a") == 1 && s.sidePrizePoints(for: "b") == 0)
        #expect(s.jacketBoard().first { $0.player.id == "a" }?.total == 2)
        #expect(try sesong("kvelden er verdt 3").jacketBoard().first { $0.player.id == "a" }?.total == 3)
        s = try sesong("lik lengde deler")
        #expect(s.sidePrizePoints(for: "a") == 0.5 && s.sidePrizePoints(for: "c") == 0.5)
        #expect(s.sidePrizeResults(for: "a").first?.shared == true)
        #expect(try sesong("sju lagseire").matchTotals(for: "a").points == 7)
        #expect(try sesong("seier og delt gir 1,5").matchTotals(for: "a").points == 1.5)
        #expect(try sesong("sesongstart").jacketBoard().allSatisfy { $0.total == 0 })
        s = try sesong("duellen og stablefordet rangerer motsatt")
        #expect(s.stablefordTotal(for: "b") > s.stablefordTotal(for: "a"))
        #expect(s.jacketBoard().first?.player.id == "a")
        let b0 = try #require(try sesong("vekt 0 teller ikke").jacketBoard().first { $0.player.id == "b" })
        #expect(b0.duel == 0 && b0.holes == 0 && b0.side == 0 && b0.played == 0)
        // sesong-test.js: 130; fravær likt; fire runder 108; dobbeltrunden 30 og 104.
        #expect(try sesong("de to svakeste strykes").stablefordTotal(for: "a") == 130)
        s = try sesong("fravær strykes")
        #expect(s.stablefordTotal(for: "b") == s.stablefordTotal(for: "a"))
        #expect(try sesong("det tredje fraværet svir").stablefordTotal(for: "c") == 30 + 28 + 26 + 24)
        s = try sesong("vekten før utvelgelsen")
        #expect(s.countingRounds(for: "a").counting.first?.points == 30)
        #expect(s.stablefordTotal(for: "a") == 104)
        // tropp-test.js: fire på tavla, de som venter med 0 og 0 spilt; handicapet skiller.
        let tropp = try sesong("to som venter").stablefordBoard()
        #expect(tropp.count == 4)
        #expect(tropp.first { $0.player.name == "Strypet" }.map { $0.total == 0 && $0.played == 0 } == true)
        #expect(tropp.map(\.player.name).prefix(2) == ["Rostad", "Næsset"])
        // kvelder-test.js: to runder samme dato er én kveld; to matcher per mann; runde 1 og 2.
        s = try sesong("to konkurranser samme kveld, siste ni går")
        #expect(Season.eveningCount(s.rounds) == 1)
        #expect(s.matchTotals(for: "thuen").matches == 2)
        #expect(s.roundNumber(for: "2026-09-28") == 1 && s.roundNumber(for: "2026-10-05") == 2)
        #expect(!s.isEveningFinished("2026-09-28"))
        // neste-kveld-test.js: begge låst → ferdig.
        #expect(try sesong("to konkurranser samme kveld, begge låst").isEveningFinished("2026-09-28"))
        #expect(Season.eveningCount(try sesong("runde uten dato").rounds) == 1)
    }

    /// Norsk sortering ved helt likt: Øyvind og Zorro står likt på alt, og Zorro kommer først.
    @Test func navnSkillerTilSlutt() throws {
        let sak = try #require(fil.saker.first { $0.navn == "trekant, manuelt resultat og vekt" })
        let tavle = Season(players: sak.spillere, rounds: sak.runder, claims: sak.claims).jacketBoard()
        #expect(tavle.suffix(2).map(\.player.name) == ["Zorro", "Øyvind"])
    }

    /// Andre regelsett gir en annen tabell: db-nytt.js kjørt med konstantene byttet ut.
    @Test func annetRegelsettSomPWAMedAndreKonstanter() {
        #expect(fil.annetRegelsett.count == 8)
        for a in fil.annetRegelsett {
            var r = Ruleset.golfgutu
            let k = a.konstanter
            if let w = k.POENG_SEIER { r.table.matchPoints.win = w }
            if let d = k.POENG_DELT { r.table.matchPoints.draw = d }
            if let l = k.POENG_TAP { r.table.matchPoints.loss = l }
            if let n = k.TELLENDE_MATCHER { r.table.counting = .init(unit: .match, best: n) }
            if let n = k.TELLENDE_RUNDER { r.table.stablefordCounting = .init(unit: .round, best: n) }
            if let t = k.TREKANT_POENG { r.table.trianglePoints = t }
            sjekk(a.sak, ruleset: r, a.sak.navn)
        }
    }

    /// Fase 6-kravet: «beste 3 teller» og «seier = 2» endrer tabellen som forventet.
    @Test func besteTreOgSeierToPoeng() throws {
        let sak = try #require(fil.saker.first { $0.navn == "fem knepne seire og to knusende tap" })
        let golfgutu = Season(players: sak.spillere, rounds: sak.runder)
        #expect(golfgutu.jacketBoard().map(\.total) == [5, 2])

        var tre = Ruleset.golfgutu
        tre.table.counting = .init(unit: .match, best: 3)
        let s3 = Season(players: sak.spillere, rounds: sak.runder, ruleset: tre)
        // Anders: tre knepne seire teller (3 poeng, +3); Bjørn: to store seire og ett knepent tap (2, +35).
        #expect(s3.matchTotals(for: "a") == Season.MatchSum(points: 3, holes: 3, matches: 3))
        #expect(s3.matchTotals(for: "b") == Season.MatchSum(points: 2, holes: 35, matches: 3))
        #expect(s3.matchResults(for: "a").dropped.count == 4)
        #expect(s3.jacketBoard().first { $0.player.id == "a" }?.played == 7)

        var to = Ruleset.golfgutu
        to.table.matchPoints = .init(win: 2, draw: 1, loss: 0)
        #expect(Season(players: sak.spillere, rounds: sak.runder, ruleset: to).jacketBoard().map(\.total) == [10, 4])

        // Sidepremier av, eller 2 poeng per premie (ingen PWA-konstant; utledet: 2 · 1/2 delt).
        let lik = try #require(fil.saker.first { $0.navn == "lik lengde deler" })
        var av = Ruleset.golfgutu
        av.sidePrizes.longestDrive.enabled = false
        av.sidePrizes.closestToPin.enabled = false
        #expect(Season(players: lik.spillere, rounds: lik.runder, claims: lik.claims, ruleset: av).sidePrizePoints(for: "a") == 0)
        var dobbel = Ruleset.golfgutu
        dobbel.sidePrizes.longestDrive.points = 2
        dobbel.sidePrizes.closestToPin.points = 2
        #expect(Season(players: lik.spillere, rounds: lik.runder, claims: lik.claims, ruleset: dobbel).sidePrizePoints(for: "a") == 1)
        // Uten deling får begge på delt førsteplass fullt poeng; premie av for én type påvirker bare den.
        var hel = Ruleset.golfgutu
        hel.sidePrizes.splitTies = false
        let helSesong = Season(players: lik.spillere, rounds: lik.runder, claims: lik.claims, ruleset: hel)
        #expect(helSesong.sidePrizePoints(for: "a") == 1 && helSesong.sidePrizePoints(for: "c") == 1)
        let typer = Set(Season(players: lik.spillere, rounds: lik.runder, claims: lik.claims).sidePrizeResults(for: "a").map(\.kind))
        for kind in typer {
            var en = Ruleset.golfgutu
            en.sidePrizes[kind].enabled = false
            #expect(!Season(players: lik.spillere, rounds: lik.runder, claims: lik.claims, ruleset: en)
                .sidePrizeResults(for: "a").contains { $0.kind == kind })
        }
    }

    /// Tiebreak-rekkefølgen fra regelsettet. Egen (utledet fra fixturen): Anders vinner duellen (hull +2)
    /// men Bjørn har høyere stablefordsum (26 mot 20). Med duellpoeng likt — her gitt ved at seier
    /// og tap begge er 0 — avgjør skilletegnene.
    @Test func tiebreakFraRegelsettet() throws {
        let sak = try #require(fil.saker.first { $0.navn == "duellen og stablefordet rangerer motsatt" })
        var r = Ruleset.golfgutu
        r.table.matchPoints = .init(win: 0, draw: 0, loss: 0)
        #expect(Season(players: sak.spillere, rounds: sak.runder, ruleset: r).jacketBoard().map(\.player.id) == ["a", "b"])
        r.table.tiebreaks = [.stableford, .holeDifference]
        #expect(Season(players: sak.spillere, rounds: sak.runder, ruleset: r).jacketBoard().map(\.player.id) == ["b", "a"])
        r.table.tiebreaks = []
        // Bare navn: Anders før Bjørn.
        #expect(Season(players: sak.spillere, rounds: sak.runder, ruleset: r).jacketBoard().map(\.player.id) == ["a", "b"])
    }

    /// Stablefordsummen med alle runder (`nil`) i stedet for beste 5.
    @Test func alleRunderTellerIStablefordsummen() throws {
        let sak = try #require(fil.saker.first { $0.navn == "de to svakeste strykes" })
        var r = Ruleset.golfgutu
        r.table.stablefordCounting.best = nil
        // Utledet: 30 + 28 + 26 + 24 + 22 + 20 + 18 = 168.
        #expect(Season(players: sak.spillere, rounds: sak.runder, ruleset: r).stablefordTotal(for: "a") == 168)
    }

    @Test func fmtPoengOgMatchSum() {
        for f in fil.fmtPoeng {
            #expect(Season.formatPoints(f.inn) == f.ut, "\(f.inn)")
        }
        for s in fil.matchSum {
            let res = s.inn.enumerated().map { Season.MatchResult(roundIndex: $0.offset, roundID: nil, matchNo: nil, points: $0.element.poeng, holes: $0.element.hull, isTriangle: false) }
            #expect(Season.matchSum(res) == Season.MatchSum(points: s.ut.poeng, holes: s.ut.hull, matches: s.ut.matcher))
        }
    }

    /// trekkMatcher med stillingen fra tabellen.
    @Test func trekningBrukerTabellen() throws {
        let sak = try #require(fil.saker.first { $0.navn == "trekant, manuelt resultat og vekt" })
        let s = Season(players: sak.spillere, rounds: sak.runder, claims: sak.claims)
        var standing: [String: Double] = [:]
        for p in sak.spillere { standing[p.id] = sak.per[p.id]?.matchSum.poeng }
        #expect(s.drawMatches(sak.spillere, round: 0) == Triangle.drawMatches(sak.spillere, round: 0, standing: standing))
    }
}
