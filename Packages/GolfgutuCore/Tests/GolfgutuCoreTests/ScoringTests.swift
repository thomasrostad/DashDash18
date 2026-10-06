import Foundation
import Testing
@testable import GolfgutuCore

/// Slag og poeng. Tall: Fixtures/poeng.json (brutto-, trackman-, seeding-, matchrunde-,
/// baneoppsett-, banebytte- og tropp-test.js; «utledet» er regnet ut av db-nytt.js).
struct ScoringTests {
    struct Fil: Decodable {
        let handicapStrokesForHole: [Slag]
        let pointsForHole: [Poeng]
        let scoreNameForHole: [Navn]
        let baneoppsettPerHull: PerHull
        let roundNetTotal: [RundeSak]
    }
    struct Slag: Decodable { let navn: String; let handicap: Double; let strokeIndex: Int; let antall: Int; let forventet: Int }
    struct Poeng: Decodable { let navn: String; let par: Int; let brutto: Int; let handicap: Double; let strokeIndex: Int; let antall: Int; let forventet: Int }
    struct Navn: Decodable { let par: Int; let brutto: Int; let handicap: Double; let strokeIndex: Int; let antall: Int; let forventet: String }
    struct PerHull: Decodable {
        struct Par: Decodable { let standard: [Int]; let elisefarm: [Int] }
        let slag: [Int]
        let hcp9: Par
        let hcp18: Par
        let elisefarmPar: [Int]
        let elisefarmSi: [Int]
    }
    struct RundeSak: Decodable { let navn: String; let spillere: [Player]; let runde: Round; let forventet: [String: Int] }

    let fil: Fil

    init() throws {
        fil = try Fixture.load(Fil.self, "poeng")
    }

    @Test func handicapStrokesForHole() {
        for s in fil.handicapStrokesForHole {
            #expect(Scoring.handicapStrokes(handicap: s.handicap, strokeIndex: s.strokeIndex, holes: s.antall) == s.forventet, "\(s.navn)")
        }
    }

    /// baneoppsett-test.js: hcp 5 på ni egne Elisefarm-hull gir slag på hull 2, 4, 5, 7 og 8.
    @Test func slagPaaDeFemVanskeligsteAvNi() {
        var holes: [Int: RoundHole] = [:]
        for i in 0..<9 {
            holes[i] = RoundHole(par: fil.baneoppsettPerHull.elisefarmPar[i], strokeIndex: fil.baneoppsettPerHull.elisefarmSi[i])
        }
        let r = Round(holeCount: 9, holes: holes)
        let medSlag = r.courseHoles().enumerated()
            .filter { Scoring.handicapStrokes(handicap: 5, strokeIndex: $0.element.strokeIndex, holes: 9) > 0 }
            .map { $0.offset + 1 }
        #expect(medSlag == [2, 4, 5, 7, 8])
    }

    /// brutto-test.js: hull 2 er par 5 og indeks 1, hull 11 er par 3 og indeks 18.
    @Test func bruttoBanensVanskeligsteOgLetteste() throws {
        let sak = try #require(fil.roundNetTotal.first { $0.navn.hasPrefix("par rundt brutto") })
        let hull = sak.runde.courseHoles()
        #expect(hull[1].par == 5 && hull[1].strokeIndex == 1)
        #expect(hull[10].par == 3 && hull[10].strokeIndex == 18)
        let medSlag = hull.filter { Scoring.handicapStrokes(handicap: 7, strokeIndex: $0.strokeIndex, holes: 18) > 0 }
        #expect(medSlag.map(\.strokeIndex).sorted() == [1, 2, 3, 4, 5, 6, 7])
    }

    @Test func pointsForHole() {
        for p in fil.pointsForHole {
            #expect(Scoring.points(par: p.par, gross: p.brutto, handicap: p.handicap, strokeIndex: p.strokeIndex, holes: p.antall) == p.forventet, "\(p.navn)")
        }
        // trackman-test.js: par betyr noe, og appens påslag oppå Trackman ville gitt flere poeng.
        #expect(Scoring.points(par: 3, gross: 4, handicap: 0, strokeIndex: 1, holes: 9)
                != Scoring.points(par: 5, gross: 4, handicap: 0, strokeIndex: 1, holes: 9))
        #expect(Scoring.points(par: 4, gross: 5, handicap: 17, strokeIndex: 1, holes: 9)
                > Scoring.points(par: 4, gross: 5, handicap: 0, strokeIndex: 1, holes: 9))
    }

    /// Egen: ingen PWA-test. Forventet er regnet ut med scoreNameForHole() i db-nytt.js.
    @Test func scoreNameForHole() {
        for n in fil.scoreNameForHole {
            let svar = Scoring.scoreName(par: n.par, gross: n.brutto, handicap: n.handicap, strokeIndex: n.strokeIndex, holes: n.antall)
            #expect(svar.rawValue == n.forventet, "par \(n.par), \(n.brutto) brutto, hcp \(n.handicap), indeks \(n.strokeIndex)")
        }
        #expect(ScoreName.dobbel.label == "Dobbel")
    }

    /// baneoppsett-test.js: samme slag gir andre poeng på 11 av 18 hull (hcp 9); på hcp 18
    /// lander summen likt, men hullene gjør det ikke.
    @Test func baneoppsettPerHull() {
        let ph = fil.baneoppsettPerHull
        var elise: [Int: RoundHole] = [:]
        for i in 0..<18 { elise[i] = RoundHole(par: ph.elisefarmPar[i], strokeIndex: ph.elisefarmSi[i]) }
        func perHull(_ holes: [Int: RoundHole]?, _ hcp: Double) -> [Int] {
            let c = Round(holeCount: 18, holes: holes).courseHoles()
            return ph.slag.enumerated().map { i, s in
                Scoring.points(par: c[i].par, gross: s, handicap: hcp, strokeIndex: c[i].strokeIndex, holes: 18)
            }
        }
        let a9 = perHull(nil, 9), b9 = perHull(elise, 9)
        #expect(a9 == ph.hcp9.standard && b9 == ph.hcp9.elisefarm)
        #expect(zip(a9, b9).filter { $0 != $1 }.count == 11)
        #expect(a9.reduce(0, +) != b9.reduce(0, +))
        #expect(perHull(nil, 0).reduce(0, +) != perHull(elise, 0).reduce(0, +))
        let a18 = perHull(nil, 18), b18 = perHull(elise, 18)
        #expect(a18 == ph.hcp18.standard && b18 == ph.hcp18.elisefarm)
        #expect(a18.reduce(0, +) == b18.reduce(0, +))
        #expect(zip(a18, b18).contains { $0 != $1 })
    }

    @Test func roundNetTotal() {
        for sak in fil.roundNetTotal {
            for p in sak.spillere {
                let svar = Scoring.roundNetTotal(sak.runde, player: p, roster: sak.spillere)
                #expect(svar == sak.forventet[p.id], "\(sak.navn): \(p.id)")
            }
        }
    }

    /// banebytte-test.js og tropp-test.js: relasjonene testene sjekker.
    @Test func banebytteOgTroppRelasjoner() throws {
        func sum(_ prefix: String) throws -> [String: Int] {
            try #require(fil.roundNetTotal.first { $0.navn.hasPrefix(prefix) }).forventet
        }
        #expect(try sum("banebytte: uten bane") != sum("banebytte: Elisefarm"))
        #expect(try sum("banebytte: flat bane") == sum("banebytte: uten bane"))
        let tropp = try sum("tropp:")
        #expect(tropp["a"]! > tropp["b"]!)
    }

    /// Egen: poengFraHull med en score-ordbok der ingen hull er ført, gir 0. Utledet fra koden (`harNoe`).
    @Test func ingenScoreGirNull() {
        let r = Round(holeCount: 18, avkortRegel: "nettopar")
        #expect(Scoring.points(from: [:], in: r, handicap: 10) == 0)
        #expect(Scoring.roundNetTotal(r, playerID: nil, handicap: 10) == 0)
    }
}
