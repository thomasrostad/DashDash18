import Foundation
import Testing
@testable import GolfgutuCore

/// Handicapregningen i regelsettet (`handicap.calculation`): golfreglene (WHS) og som PWA-en.
/// Tall: Fixtures/handicap-whs.json (regnet ut fra WHS-reglene og db-nytt.js, se `_kilde`).
struct HandicapWHSTests {
    struct Fil: Decodable {
        let slag: [Slag]
        let nettoDobbelBogey: [NDB]
        let dekoding: [Dekoding]
        let saker: [Sak]
    }
    struct Slag: Decodable { let handicap: Double; let strokeIndex: Int; let antall: Int; let pwa: Int; let whs: Int }
    struct NDB: Decodable { let par: Int; let slag: Int; let forventet: Int }
    struct Dekoding: Decodable { let navn: String; let forventet: Ruleset.HandicapCalculation }
    struct Sak: Decodable {
        let navn: String
        let regning: Ruleset.HandicapCalculation
        let spillere: [Player]
        let runde: Round
        let sjekker: [HandicapTests.Sjekk]

        var rules: Ruleset {
            var r = Ruleset.golfgutu
            r.handicap.calculation = regning
            return r
        }
    }

    let fil: Fil

    init() throws {
        fil = try Fixture.load(Fil.self, "handicap-whs")
    }

    @Test func slagPerHull() {
        for s in fil.slag {
            for (calc, forventet) in [(Ruleset.HandicapCalculation.pwa, s.pwa), (.whs, s.whs)] {
                var rules = Ruleset.golfgutu
                rules.handicap.calculation = calc
                #expect(Scoring.handicapStrokes(handicap: s.handicap, strokeIndex: s.strokeIndex, holes: s.antall,
                                                rules: rules) == forventet,
                        "\(calc): hcp \(s.handicap), indeks \(s.strokeIndex) av \(s.antall)")
            }
        }
    }

    /// Standard er som PWA-en, så kall uten regelsett gir dagens tall.
    @Test func utenRegelsettErSomPWA() {
        for s in fil.slag {
            #expect(Scoring.handicapStrokes(handicap: s.handicap, strokeIndex: s.strokeIndex, holes: s.antall) == s.pwa)
        }
    }

    @Test func nettoDobbelBogey() {
        for n in fil.nettoDobbelBogey {
            #expect(Ruleset.MaxStrokes.netDoubleBogey.limit(par: n.par, strokesReceived: n.slag) == n.forventet)
        }
    }

    @Test func dekoding() throws {
        let raw = try JSONSerialization.jsonObject(with: Fixture.data("handicap-whs")) as! [String: Any]
        let saker = raw["dekoding"] as! [[String: Any]]
        #expect(saker.count == fil.dekoding.count)
        for (sak, d) in zip(saker, fil.dekoding) {
            let data = try JSONSerialization.data(withJSONObject: sak["regelsett"]!)
            let rules = try JSONDecoder().decode(Ruleset.self, from: data)
            #expect(rules.handicap.calculation == d.forventet, "\(d.navn)")
        }
    }

    /// Feltet skrives bare når det er golfreglene, så Golfgutu-JSON-en er som før.
    @Test func skrivesBareForWHS() throws {
        let golfgutu = String(decoding: try JSONEncoder().encode(Ruleset.golfgutu), as: UTF8.self)
        #expect(!golfgutu.contains("calculation"))
        var whs = Ruleset.golfgutu
        whs.handicap.calculation = .whs
        let data = try JSONEncoder().encode(whs)
        #expect(String(decoding: data, as: UTF8.self).contains("\"calculation\":\"whs\""))
        #expect(try JSONDecoder().decode(Ruleset.self, from: data) == whs)
    }

    @Test func sakerFraFixture() {
        #expect(fil.saker.count >= 20)
        #expect(Set(fil.saker.map(\.regning)) == [.pwa, .whs])
        for sak in fil.saker {
            let rules = sak.rules
            let spiller: (String?) -> Player? = { id in sak.spillere.first { $0.id == id } }
            for s in sak.sjekker {
                let svar: Double
                switch s.fn {
                case "effectiveHandicap":
                    svar = Handicap.effective(for: spiller(s.spiller), in: sak.runde, roster: sak.spillere, rules: rules)
                case "banehandicap":
                    svar = Handicap.courseHandicap(for: spiller(s.spiller), in: sak.runde, rules: rules)
                case "lagGrunnlag":
                    svar = Handicap.teamBasis(for: spiller(s.spiller), in: sak.runde, rules: rules)
                case "lagHandicap":
                    svar = Handicap.teamHandicap(in: sak.runde, memberIDs: s.spillere ?? [], roster: sak.spillere,
                                                 rules: rules)
                case "stableford":
                    svar = Double(Scoring.roundNetTotal(sak.runde, player: spiller(s.spiller), roster: sak.spillere,
                                                        rules: rules))
                default:
                    Issue.record("ukjent funksjon \(s.fn)")
                    continue
                }
                #expect(svar == s.forventet, "\(sak.navn): \(s.fn)(\(s.spiller ?? s.spillere?.joined(separator: ",") ?? ""))")
            }
        }
    }

    /// Sakene med `pwa` gir det samme som motoren uten regelsett (Golfgutu-oppsettet), altså dagens tall.
    @Test func pwaErDagensTall() {
        for sak in fil.saker where sak.regning == .pwa {
            for p in sak.spillere {
                #expect(Handicap.effective(for: p, in: sak.runde, roster: sak.spillere, rules: sak.rules)
                        == Handicap.effective(for: p, in: sak.runde, roster: sak.spillere), "\(sak.navn): \(p.id)")
            }
        }
    }
}
