import Foundation
import Testing
@testable import GolfgutuCore

/// Bane og hull. Tall: Fixtures/bane.json (banepar-test.js, baneoppsett-test.js,
/// banehull-test.js, og egne saker regnet ut av db-nytt.js).
struct CourseTests {
    struct Fil: Decodable {
        let defaultPar: [Int]
        let ektePar: [Int]
        let elisefarmPar: [Int]
        let baneErKlar: [Klar]
        let courseForRound: [RundeSak]
        let banehullFraRader: Rader
        let lengdePasserParet: [Lengde]
    }
    struct Klar: Decodable { let navn: String; let holes: [CourseHole]?; let klar: Bool }
    struct RundeSak: Decodable {
        let navn: String
        let runde: Round
        let forventet: Forventet
    }
    struct Forventet: Decodable {
        let par: [Int]?
        let kortIndeks: [Int]?
        let strokeIndex: [Int]?
        let meters: [Double?]?
        let parSum: Int?
        let meter0: Double?
        let strokeIndexSortert: [Int]?
        let strokeIndex6: Int?
    }
    struct Rader: Decodable {
        let atten, utenLengde, ni, stokket, mangler7, tretten, utenHcp: [CourseHoleRow]
    }
    struct Lengde: Decodable { let par: Int; let meters: Double?; let ok: Bool }

    let fil: Fil

    init() throws {
        fil = try Fixture.load(Fil.self, "bane")
    }

    @Test func standardParErPar72() {
        #expect(Course.defaultPar == fil.defaultPar)
        #expect(Course.defaultPar.reduce(0, +) == 72)
    }

    @Test func parErEtTall() {
        #expect(Course.isValidPar(3))
        #expect(Course.isValidPar(6))
        #expect(!Course.isValidPar(2))
        #expect(!Course.isValidPar(7))
        #expect(!Course.isValidPar(0))
        #expect(!Course.isValidPar(nil))
    }

    @Test func baneErKlar() {
        for sak in fil.baneErKlar {
            #expect(Course(holes: sak.holes).isReady == sak.klar, "\(sak.navn)")
        }
    }

    @Test func courseForRound() {
        #expect(fil.courseForRound.count == 20)
        for sak in fil.courseForRound {
            let hull = sak.runde.courseHoles()
            let f = sak.forventet
            if let par = f.par { #expect(hull.map(\.par) == par, "\(sak.navn): par") }
            if let k = f.kortIndeks { #expect(hull.map(\.cardIndex) == k, "\(sak.navn): kortindeks") }
            if let s = f.strokeIndex { #expect(hull.map(\.strokeIndex) == s, "\(sak.navn): strokeIndex") }
            if let m = f.meters { #expect(hull.map(\.meters) == m, "\(sak.navn): meter") }
            if let sum = f.parSum { #expect(hull.map(\.par).reduce(0, +) == sum, "\(sak.navn): parsum") }
            if let m0 = f.meter0 { #expect(hull[0].meters == m0, "\(sak.navn): meter hull 1") }
            if let s = f.strokeIndexSortert { #expect(hull.map(\.strokeIndex).sorted() == s, "\(sak.navn): rang 1–n") }
            if let s6 = f.strokeIndex6 { #expect(hull[6].strokeIndex == s6, "\(sak.navn): hull 7") }
        }
    }

    /// baneoppsett-test.js: ni egne hull fra Elisefarm-kortet.
    @Test func niHullRangeresOmTilNiSlagplasser() throws {
        let sak = try #require(fil.courseForRound.first { $0.navn.hasPrefix("ni egne hull") })
        let rang = sak.runde.courseHoles().map(\.strokeIndex)
        #expect(rang[6] == 1 && rang[4] == 2 && rang[1] == 3)
        #expect(rang[2] == 9)
        #expect(sak.runde.courseHoles()[3].cardIndex == 9)
    }

    @Test func banehullFraRader() {
        let r = fil.banehullFraRader

        let atten = Course.holesFromRows(r.atten)["m"]!!
        #expect(atten.count == 18)
        #expect(atten.map(\.par) == fil.ektePar.map { Optional($0) })
        #expect(atten[0].si == 1 && atten[17].si == 18)
        #expect(atten[0].meters == 300 && atten[17].meters == 317)
        #expect(Course(holes: atten).isReady)

        let utenLengde = Course.holesFromRows(r.utenLengde)["x"]!!
        #expect(utenLengde[0].meters == nil)
        #expect(Course(holes: utenLengde).isReady)

        #expect(Course.holesFromRows(r.ni)["n"]!!.count == 9)
        #expect(Course.holesFromRows(r.stokket)["s"]!!.map(\.par) == fil.ektePar.map { Optional($0) })

        // Nøkkelen finnes, men verdien er nil: en halv bane.
        let mangler = Course.holesFromRows(r.mangler7)
        #expect(mangler.keys.contains("h"))
        #expect(mangler["h"]! == nil)
        #expect(Course.holesFromRows(r.tretten)["t"]! == nil)
        #expect(Course.holesFromRows([]).isEmpty)

        let utenHcp = Course.holesFromRows(r.utenHcp)["u"]!!
        #expect(Course(holes: utenHcp).isReady)
        #expect(utenHcp[0].si == nil)
    }

    @Test func banehullFraRaderHopperOverRaderUtenBane() {
        let rader = [CourseHoleRow(courseId: nil, holeNumber: 1, par: 4),
                     CourseHoleRow(courseId: "", holeNumber: 1, par: 4)]
        #expect(Course.holesFromRows(rader).isEmpty)
    }

    @Test func lengdePasserParet() {
        for sak in fil.lengdePasserParet {
            #expect(Course.lengthMatchesPar(par: sak.par, meters: sak.meters) == sak.ok, "par \(sak.par) på \(String(describing: sak.meters)) m")
        }
    }

    /// banepar-test.js: en frisk bane gir ingen advarsler; hull 4 som par 4 på 165 m gir én.
    @Test func hullMedRarLengde() {
        var bane = fil.ektePar.enumerated().map { i, p in
            PlayedHole(par: p, cardIndex: i + 1, meters: p == 3 ? 160 : (p == 4 ? 370 : 480), strokeIndex: i + 1)
        }
        #expect(Course.holesWithOddLength(bane).isEmpty)
        bane[3] = PlayedHole(par: 4, cardIndex: 4, meters: 165, strokeIndex: 4)
        let funn = Course.holesWithOddLength(bane)
        #expect(funn.count == 1)
        #expect(funn.first?.number == 4)
        #expect(funn.first?.par == 4 && funn.first?.meters == 165)
    }

    /// Egen: baneHarIndeks (brutto-test.js bruker den bare indirekte). Utledet fra koden:
    /// alle hull må ha `si > 0`; tom eller manglende liste gir false.
    @Test func baneHarIndeks() {
        let medSi = fil.elisefarmPar.enumerated().map { i, p in CourseHole(par: p, si: i + 1) }
        #expect(Course(holes: medSi).hasStrokeIndex)
        var enNull = medSi
        enNull[4].si = 0
        #expect(!Course(holes: enNull).hasStrokeIndex)
        var enMangler = medSi
        enMangler[4].si = nil
        #expect(!Course(holes: enMangler).hasStrokeIndex)
        #expect(!Course(holes: []).hasStrokeIndex)
        #expect(!Course(holes: nil).hasStrokeIndex)
    }

    /// Egen: antallHull. Utledet fra koden: 9 eller 18, alt annet 18.
    @Test func antallHull() {
        #expect(Round(holeCount: 9).numberOfHoles == 9)
        #expect(Round(holeCount: 18).numberOfHoles == 18)
        #expect(Round(holeCount: nil).numberOfHoles == 18)
        #expect(Round(holeCount: 7).numberOfHoles == 18)
        #expect(Round(holeCount: 0).numberOfHoles == 18)
    }
}
