import Foundation
import Testing
@testable import GolfgutuCore

/// Avrunding og sortering som i JS. Tall: Fixtures/hjelpere.json.
struct HelperTests {
    struct Fil: Decodable {
        struct Sortert: Decodable { let inn: [String]; let ut: [String] }
        let jsRound: [[Double]]
        let rund2: [[Double]]
        let naermesteHalve: [[Double]]
        let localeCompare: [Sammenlikning]
        let sortert: Sortert
    }

    /// `[a, b, forventet]` der forventet er -1, 0 eller 1.
    struct Sammenlikning: Decodable {
        let a: String, b: String, forventet: Int
        init(from decoder: Decoder) throws {
            var c = try decoder.unkeyedContainer()
            a = try c.decode(String.self)
            b = try c.decode(String.self)
            forventet = try c.decode(Int.self)
        }
    }

    let fil: Fil

    init() throws {
        fil = try Fixture.load(Fil.self, "hjelpere")
    }

    @Test func mathRoundErFloorPlussEnHalv() {
        for par in fil.jsRound {
            #expect(JS.round(par[0]) == par[1], "Math.round(\(par[0]))")
        }
        #expect(JS.roundInt(-2.5) == -2)
        #expect(JS.roundInt(2.5) == 3)
    }

    @Test func rund2() {
        for par in fil.rund2 {
            #expect(JS.round2(par[0]) == par[1], "rund2(\(par[0]))")
        }
    }

    @Test func naermesteHalve() {
        for par in fil.naermesteHalve {
            #expect(JS.roundHalf(par[0]) == par[1], "nærmeste halve av \(par[0])")
        }
    }

    @Test func norskLocaleCompare() {
        for s in fil.localeCompare {
            let svar = NorwegianSort.compare(s.a, s.b)
            let tall = svar == .orderedAscending ? -1 : (svar == .orderedSame ? 0 : 1)
            #expect(tall == s.forventet, "'\(s.a)'.localeCompare('\(s.b)', 'no')")
        }
    }

    @Test func norskSorteringAvNavn() {
        let ut = fil.sortert.inn.sorted(by: NorwegianSort.areInIncreasingOrder)
        #expect(ut == fil.sortert.ut)
    }
}
