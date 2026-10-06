import Foundation
import Testing
@testable import GolfgutuCore

/// Handicap. Tall: Fixtures/handicap.json (seeding-, parspill-, brutto-, trackman-,
/// tropp-, banebytte- og skjevt-lag-test.js; «utledet» er regnet ut av db-nytt.js).
struct HandicapTests {
    struct Fil: Decodable {
        let seedingGrupper: [Gruppe]
        let courseHandicap: [CH]
        let saker: [Sak]
    }
    struct Gruppe: Decodable { let nr: Int; let hcp: Double; let navn: String }
    struct CH: Decodable { let inn: [Double?]; let forventet: Double }
    struct Sak: Decodable {
        let navn: String
        let spillere: [Player]
        let runde: Round
        let sjekker: [Sjekk]
    }
    struct Sjekk: Decodable {
        let fn: String
        let spiller: String?
        let spillere: [String]?
        let forventet: Double
    }

    let fil: Fil

    init() throws {
        fil = try Fixture.load(Fil.self, "handicap")
    }

    @Test func seedingGrupperErGolfgutu() {
        #expect(SeedingGroup.golfgutu.map(\.number) == fil.seedingGrupper.map(\.nr))
        #expect(SeedingGroup.golfgutu.map(\.handicap) == fil.seedingGrupper.map(\.hcp))
        #expect(SeedingGroup.golfgutu.map(\.name) == fil.seedingGrupper.map(\.navn))
    }

    /// seeding-test.js: ukjent gruppe er ingen gruppe; uten feltet er man ikke seedet.
    /// Gruppe 1 gir 0, og 0 er ikke det samme som «ikke seedet».
    @Test func gruppeHandicapNullErIkkeNull() {
        #expect(Handicap.seedingGroup(7) == nil)
        #expect(!Handicap.isSeeded(Player(id: "y", handicap: 3)))
        #expect(Handicap.groupHandicap(for: Player(id: "a", seedGroup: 1)) == 0)
        #expect(Handicap.groupHandicap(for: Player(id: "d", seedGroup: nil)) == nil)
        #expect(Handicap.groupHandicap(for: nil) == nil)
    }

    @Test func courseHandicapWHS() {
        for c in fil.courseHandicap {
            let svar = Handicap.courseHandicap(index: c.inn[0], courseRating: c.inn[1], slopeRating: c.inn[2], par: c.inn[3])
            #expect(svar == c.forventet, "courseHandicap\(c.inn)")
        }
    }

    @Test func sakerFraFixture() {
        #expect(fil.saker.count > 40)
        for sak in fil.saker {
            let spiller: (String?) -> Player? = { id in sak.spillere.first { $0.id == id } }
            for s in sak.sjekker {
                let svar: Double
                switch s.fn {
                case "effectiveHandicap":
                    svar = Handicap.effective(for: spiller(s.spiller), in: sak.runde, roster: sak.spillere)
                case "banehandicap":
                    svar = Handicap.courseHandicap(for: spiller(s.spiller), in: sak.runde)
                case "lagGrunnlag":
                    svar = Handicap.teamBasis(for: spiller(s.spiller), in: sak.runde)
                case "lagHandicap":
                    svar = Handicap.teamHandicap(in: sak.runde, memberIDs: s.spillere ?? [], roster: sak.spillere)
                case "rundeAndel":
                    svar = Handicap.allowance(sak.runde)
                default:
                    Issue.record("ukjent funksjon \(s.fn)")
                    continue
                }
                #expect(svar == s.forventet, "\(sak.navn): \(s.fn)(\(s.spiller ?? s.spillere?.joined(separator: ",") ?? ""))")
            }
        }
    }

    /// banebytte-test.js: ingen får færre slag på en vanskeligere bane, høyt handicap får flest ekstra,
    /// og CR 72 / slope 113 er det samme som ingen bane.
    @Test func banebytteRelasjoner() throws {
        let uten = try #require(fil.saker.first { $0.navn.hasPrefix("banebytte: uten bane") })
        let elise = try #require(fil.saker.first { $0.navn.hasPrefix("banebytte: Elisefarm") })
        let flat = try #require(fil.saker.first { $0.navn.hasPrefix("banebytte: flat") })
        func hcp(_ sak: Sak, _ id: String) -> Double {
            Handicap.effective(for: sak.spillere.first { $0.id == id }, in: sak.runde, roster: sak.spillere)
        }
        for id in ["p1", "p2", "p3"] {
            #expect(hcp(elise, id) >= hcp(uten, id))
            #expect(hcp(flat, id) == hcp(uten, id))
        }
        #expect(hcp(elise, "p2") > hcp(uten, "p2") && hcp(elise, "p3") > hcp(uten, "p3"))
        #expect(hcp(elise, "p3") - hcp(uten, "p3") > hcp(elise, "p1") - hcp(uten, "p1"))
    }

    /// Egen: seeding-gruppene kommer fra regelsettet. Utledet fra koden: gruppas tall brukes rått.
    @Test func egneSeedingGrupper() {
        let grupper = [SeedingGroup(number: 1, handicap: 2, name: "A"), SeedingGroup(number: 2, handicap: 8, name: "B")]
        let p = Player(id: "x", handicap: 20, seedGroup: 2)
        let r = Round(gameType: "stableford", holeCount: 9, hcpAllowance: 0.95)
        #expect(Handicap.effective(for: p, in: r, roster: [p], groups: grupper) == 8)
        #expect(Handicap.effective(for: Player(id: "z", handicap: 20, seedGroup: 3), in: r, roster: [], groups: grupper)
                == JS.round(20 * 0.95 * 0.5))
    }
}
