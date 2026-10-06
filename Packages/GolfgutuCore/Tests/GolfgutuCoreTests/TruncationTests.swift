import Foundation
import Testing
@testable import GolfgutuCore

/// Avkorting. Tall: Fixtures/avkorting.json (avkorting-test.js; «egen»/«utledet» er regnet ut av db-nytt.js).
struct TruncationTests {
    struct Fil: Decodable {
        let regler: [Regel]
        let spillere: [Player]
        let saker: [Sak]
        let lavesteFellesHull: [LFH]
        let avkortingenKoster: Koster
    }
    struct Regel: Decodable { let id, navn, hjelp: String }
    struct Sak: Decodable { let navn: String; let runde: Round; let forventet: Forventet }
    struct Forventet: Decodable {
        let tellendeHull: Int
        let erAvkortet: Bool
        let poengForTomtHull: Int?
        let poeng: [String: Int]
    }
    struct LFH: Decodable { let navn: String; let holeScores: [String: HoleScores]; let holeCount: Int; let forventet: Int }
    struct Koster: Decodable {
        struct Endring: Decodable { let spiller: String; let `for`: Int; let etter: Int; let diff: Int }
        struct KSak: Decodable { let etter: Double; let regel: String; let tellende: Int; let av: Int; let endring: [Endring] }
        let spillere: [Player]
        let runde: Round
        let saker: [KSak]
    }

    let fil: Fil

    init() throws {
        fil = try Fixture.load(Fil.self, "avkorting")
    }

    @Test func reglerErLikePWA() {
        #expect(Truncation.Rule.allCases.map(\.rawValue) == fil.regler.map(\.id))
        for (r, js) in zip(Truncation.Rule.allCases, fil.regler) {
            #expect(r.name == js.navn)
            #expect(r.help == js.hjelp)
        }
    }

    /// Strengen «null» er en gyldig regel; JS-null (nil) betyr ikke avkortet.
    @Test func avkortRegel() {
        #expect(Truncation.rule(Round(avkortRegel: "null")) == .zero)
        #expect(Truncation.rule(Round(avkortRegel: nil)) == nil)
        #expect(Truncation.rule(Round(avkortRegel: "felles")) == .common)
        #expect(Truncation.rule(Round(avkortRegel: "")) == nil)
    }

    @Test func tellendeHullOgPoeng() {
        #expect(fil.saker.count == 10)
        for sak in fil.saker {
            let f = sak.forventet
            #expect(Truncation.countingHoles(sak.runde) == f.tellendeHull, "\(sak.navn): tellendeHull")
            #expect(Truncation.isTruncated(sak.runde) == f.erAvkortet, "\(sak.navn): erAvkortet")
            if let tomt = f.poengForTomtHull {
                #expect(Truncation.pointsForEmptyHole(sak.runde) == tomt, "\(sak.navn): poengForTomtHull")
            }
            for p in fil.spillere {
                #expect(Scoring.roundNetTotal(sak.runde, player: p, roster: fil.spillere) == f.poeng[p.id], "\(sak.navn): \(p.name)")
            }
        }
    }

    @Test func lavesteFellesHull() {
        for sak in fil.lavesteFellesHull {
            let r = Round(holeCount: sak.holeCount, holeScores: sak.holeScores)
            #expect(Truncation.lowestCommonHole(r) == sak.forventet, "\(sak.navn)")
        }
    }

    @Test func avkortingenKoster() {
        let k = fil.avkortingenKoster
        for sak in k.saker {
            let svar = Truncation.cost(of: k.runde, after: sak.etter, rule: Truncation.Rule(rawValue: sak.regel), roster: k.spillere)
            let navn = "\(sak.regel) etter \(sak.etter)"
            #expect(svar.countingHoles == sak.tellende, "\(navn): tellende")
            #expect(svar.holes == sak.av, "\(navn): av")
            #expect(svar.changes.map(\.playerID) == sak.endring.map(\.spiller), "\(navn): rekkefølge")
            #expect(svar.changes.map(\.before) == sak.endring.map(\.for), "\(navn): før")
            #expect(svar.changes.map(\.after) == sak.endring.map(\.etter), "\(navn): etter")
            #expect(svar.changes.map(\.diff) == sak.endring.map(\.diff), "\(navn): diff")
        }
        // avkorting-test.js: to taper på felles, Anders mest (−8); nettopar koster ingen noe.
        let felles = Truncation.cost(of: k.runde, after: 14, rule: .common, roster: k.spillere)
        #expect(felles.changes.count == 2)
        #expect(felles.changes.first?.playerID == "a" && felles.changes.first?.diff == -8)
        #expect(Truncation.cost(of: k.runde, after: 14, rule: .netPar, roster: k.spillere).changes.allSatisfy { $0.diff >= 0 })
    }
}
