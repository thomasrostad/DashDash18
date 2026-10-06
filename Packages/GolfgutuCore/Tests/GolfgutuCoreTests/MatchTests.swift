import Foundation
import Testing
@testable import GolfgutuCore

/// Match hull for hull. Tall: Fixtures/match.json, regnet ut av db-nytt.js på scenarioene fra
/// match-test.js, matchrunde-test.js, skjevt-lag-test.js, parspill-test.js og seeding-test.js
/// («egen» i fixturen = scenario uten PWA-test, tallene er fortsatt fra db-nytt.js).
struct MatchTests {
    struct Fil: Decodable {
        let saker: [Sak]
        let tekster: [Tekst]
        let poengForUtfall: [Utfall]
    }
    struct Sak: Decodable {
        let navn: String
        let kilde: String
        let spillere: [Player]
        let runde: Round
        let tellendeHull: Int
        let matcher: [M]
        let hullMatch: [String: Int?]
        let avgjoresHullForHull: Bool
    }
    struct Sider: Decodable { let a: [String]; let b: [String]; let c: [String]? }
    struct Diff: Decodable { let opp: Int; let spilt: Int }
    struct St: Decodable {
        let opp, spilt, igjen: Int
        let avgjort: Bool
        let motstandere: [String]
        let tekst, kort: String
    }
    struct M: Decodable {
        let sider: Sider
        let trekant: Bool
        let gjelder: [String: Bool]
        let sideHandicapA, sideHandicapB, matchSlag: Double
        let hullVinner: [Int?]
        let sideNettoA, sideNettoB: [Int?]
        let hullDiff: Diff?
        let utfallForA: Double?
        let stilling: [String: St?]
    }
    struct StIn: Decodable { let opp, spilt, igjen: Int; let avgjort: Bool }
    struct Tekst: Decodable { let stilling: StIn?; let tekst, kort: String }
    struct Utfall: Decodable { let utfall: Double?; let poeng: Double }

    let fil: Fil

    init() throws {
        fil = try Fixture.load(Fil.self, "match")
    }

    @Test func alleSakerGirSammeSvarSomPWA() {
        #expect(fil.saker.count == 27)
        for sak in fil.saker {
            let r = sak.runde
            let roster = sak.spillere
            #expect(Truncation.countingHoles(r) == sak.tellendeHull, "\(sak.navn)")
            #expect(MatchPlay.isDecidedHoleByHole(r) == sak.avgjoresHullForHull, "\(sak.navn): avgjoresHullForHull")
            for p in roster {
                #expect(MatchPlay.holeMatch(for: p.id, in: r)?.matchNo == sak.hullMatch[p.id] ?? nil, "\(sak.navn): hullMatchFor \(p.id)")
            }
            #expect(MatchPlay.matches(in: r).count == sak.matcher.count)
            for (m, js) in zip(MatchPlay.matches(in: r), sak.matcher) {
                let navn = "\(sak.navn) match \(m.matchNo ?? 0)"
                let s = MatchPlay.sides(of: m, in: r)
                // JS følger radrekkefølgen i round_teams; vi sorterer på id.
                #expect(s.a.sorted() == js.sider.a.sorted(), "\(navn): side A")
                #expect(s.b.sorted() == js.sider.b.sorted(), "\(navn): side B")
                #expect(s.c == js.sider.c, "\(navn): side C")
                #expect(m.isTriangle == js.trekant, "\(navn): trekant")
                for (pid, gjelder) in js.gjelder {
                    #expect(MatchPlay.involves(m, playerID: pid, in: r) == gjelder, "\(navn): gjelder \(pid)")
                }
                #expect(MatchPlay.sideHandicap(s.a, in: r, roster: roster) == js.sideHandicapA, "\(navn): sideHandicap A")
                #expect(MatchPlay.sideHandicap(s.b, in: r, roster: roster) == js.sideHandicapB, "\(navn): sideHandicap B")
                let lav = MatchPlay.strokeOffset(for: m, in: r, roster: roster)
                #expect(lav == js.matchSlag, "\(navn): matchSlag")
                for h in 0..<js.hullVinner.count {
                    #expect(MatchPlay.holeWinner(m, hole: h, in: r, roster: roster) == js.hullVinner[h], "\(navn): hull \(h + 1)")
                    #expect(MatchPlay.sideNet(s.a, hole: h, extraStrokes: lav, in: r, roster: roster) == js.sideNettoA[h], "\(navn): netto A hull \(h + 1)")
                    #expect(MatchPlay.sideNet(s.b, hole: h, extraStrokes: lav, in: r, roster: roster) == js.sideNettoB[h], "\(navn): netto B hull \(h + 1)")
                }
                let d = MatchPlay.holeDiff(m, in: r, roster: roster)
                #expect(d?.up == js.hullDiff?.opp && d?.played == js.hullDiff?.spilt, "\(navn): hullDiff")
                #expect(MatchPlay.outcomeForA(m, in: r, roster: roster) == js.utfallForA, "\(navn): utfallForA")
                for (pid, forventet) in js.stilling {
                    let st = MatchPlay.standing(m, from: pid, in: r, roster: roster)
                    guard let f = forventet else {
                        #expect(st == nil, "\(navn): stilling \(pid)")
                        continue
                    }
                    #expect(st?.up == f.opp && st?.played == f.spilt && st?.remaining == f.igjen && st?.decided == f.avgjort,
                            "\(navn): stilling \(pid)")
                    #expect(st?.opponents.sorted() == f.motstandere.sorted(), "\(navn): motstandere \(pid)")
                    #expect(MatchPlay.text(st) == f.tekst, "\(navn): tekst \(pid)")
                    #expect(MatchPlay.shortText(st) == f.kort, "\(navn): kort \(pid)")
                }
            }
        }
    }

    /// Nøkkeltallene fra PWA-testene, skrevet ut så de er lette å finne igjen.
    @Test func pwaTestenesTall() throws {
        func sak(_ navn: String) throws -> Sak { try #require(fil.saker.first { $0.navn == navn }) }

        // match-test.js §3: 16 førte hull, −12; avkortet til 14: spilt 14, −14, ingen igjen, «Vunnet …».
        let uten = try sak("16 hull uavkortet")
        let m = uten.runde.matches[0]
        #expect(MatchPlay.holeDiff(m, in: uten.runde, roster: uten.spillere) == MatchHoleDiff(up: -12, played: 16))
        #expect(MatchPlay.standing(m, from: "b", in: uten.runde, roster: uten.spillere)?.remaining == 2)
        let med = try sak("avkortet felles etter 14")
        #expect(MatchPlay.holeDiff(m, in: med.runde, roster: med.spillere) == MatchHoleDiff(up: -14, played: 14))
        let st = MatchPlay.standing(m, from: "b", in: med.runde, roster: med.spillere)
        #expect(st?.remaining == 0)
        #expect(MatchPlay.text(st).hasPrefix("Vunnet"))
        let np = try sak("nettopar etter 14")
        #expect(MatchPlay.holeDiff(m, in: np.runde, roster: np.spillere)?.played == 16)

        // matchrunde-test.js: lag 3 vant hull 1 på beste ball; Erik 1 opp, Harald 1 ned, Anders «—».
        let h1 = try sak("hull 1 fourball")
        let ms = h1.runde.matches
        #expect(MatchPlay.holeWinner(ms[1], hole: 0, in: h1.runde, roster: h1.spillere) == 1)
        #expect(MatchPlay.holeWinner(ms[0], hole: 0, in: h1.runde, roster: h1.spillere) == nil)
        #expect(MatchPlay.shortText(MatchPlay.standing(ms[1], from: "e", in: h1.runde, roster: h1.spillere)) == "1 opp")
        #expect(MatchPlay.shortText(MatchPlay.standing(ms[1], from: "h", in: h1.runde, roster: h1.spillere)) == "1 ned")
        #expect(MatchPlay.shortText(MatchPlay.standing(ms[0], from: "a", in: h1.runde, roster: h1.spillere)) == "—")
        let tre = try sak("bare trekant")
        #expect(MatchPlay.isDecidedHoleByHole(tre.runde) == false)
        #expect(MatchPlay.holeMatch(for: "a", in: tre.runde) == nil)

        // skjevt-lag-test.js §4: Rostad 5 ned over 9; to mot tre: −1.
        let rb = try sak("Rostad mot Breivik, lag på én")
        let rbSt = MatchPlay.standing(rb.runde.matches[0], from: "rostad", in: rb.runde, roster: rb.spillere)
        #expect(rbSt?.up == -5 && rbSt?.played == 9)
        let tt = try sak("to mot tre")
        #expect(MatchPlay.standing(tt.runde.matches[0], from: "alm", in: tt.runde, roster: tt.spillere)?.up == -1)

        // parspill-test.js: lag på 5 mot lag på 5. seeding-test.js §5: gruppe 2 mot 3 → 5.
        let ps = try sak("scramble-2: lag på 5 mot lag på 5")
        #expect(MatchPlay.strokeOffset(for: ps.runde.matches[0], in: ps.runde, roster: ps.spillere) == 5)
        #expect(MatchPlay.sideHandicap(["g2a", "g2b"], in: ps.runde, roster: ps.spillere) == 5)
        #expect(MatchPlay.sideHandicap(["g3", "g1"], in: ps.runde, roster: ps.spillere) == 5)
        let sd = try sak("gruppe 2 mot gruppe 3")
        #expect(MatchPlay.strokeOffset(for: sd.runde.matches[0], in: sd.runde, roster: sd.spillere) == 5)
    }

    /// Alle grenene i `matchTekst` og `matchStillingKort`, med eksakt tekst fra db-nytt.js.
    @Test func matchTekstAlleGrener() {
        #expect(fil.tekster.count == 15)
        for t in fil.tekster {
            let st = t.stilling.map { MatchStanding(up: $0.opp, played: $0.spilt, remaining: $0.igjen, decided: $0.avgjort) }
            #expect(MatchPlay.text(st) == t.tekst, "\(String(describing: t.stilling))")
            #expect(MatchPlay.shortText(st) == t.kort, "\(String(describing: t.stilling))")
        }
        // Em dash, ikke bindestrek; «&» uten mellomrom.
        #expect(MatchPlay.shortText(nil) == "\u{2014}")
        #expect(MatchPlay.text(MatchStanding(up: 3, played: 16, remaining: 2, decided: true)) == "Vunnet 3&2")
    }

    @Test func poengForUtfall() {
        for u in fil.poengForUtfall {
            #expect(MatchPlay.points(forOutcome: u.utfall) == u.poeng, "\(String(describing: u.utfall))")
        }
        // Regelsettet styrer verdiene.
        let annen = Ruleset.MatchPoints(win: 2, draw: 1, loss: 0)
        #expect(MatchPlay.points(forOutcome: 1, annen) == 2)
        #expect(MatchPlay.points(forOutcome: 0.5, annen) == 1)
    }

    /// Manuelt resultat: PWA-ens `A`/`B`/annet og skjemaets `a`/`b`/`halved`. Tom tekst er ikke et resultat.
    @Test func manueltResultat() throws {
        #expect(Match.Result(stored: "A") == .a)
        #expect(Match.Result(stored: "b") == .b)
        #expect(Match.Result(stored: "halved") == .halved)
        #expect(Match.Result(stored: "H") == .halved)
        #expect(Match.Result(stored: "") == nil)
        #expect(Match.Result(stored: nil) == nil)
        let m = try JSONDecoder().decode(Match.self, from: Data(#"{"playerA":"a","playerB":"b","result":""}"#.utf8))
        #expect(m.result == nil && !m.isTriangle)
        let rundtur = try JSONDecoder().decode(Match.self, from: JSONEncoder().encode(Match(playerA: "a", playerB: "b", result: .halved)))
        #expect(rundtur.result == .halved)
    }
}
