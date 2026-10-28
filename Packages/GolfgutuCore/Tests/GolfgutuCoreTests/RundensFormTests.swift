import Foundation
import Testing
@testable import GolfgutuCore

/// Rundens resultat etter formen (`FormPlay.formResult`): slagspill, stableford brutto og maksimumscore
/// regnes etter Golfreglene (regel 21), ikke som stableford. Tallene: Fixtures/rundens-form.json (regnet
/// for hånd). Stableford netto (Golfgutu) gir ikke noe formresultat, så den veien er uendret.
struct RundensFormTests {
    struct Rad: Decodable { let spiller: String; let score: Double; let hull: Int; let plass: Int }
    struct Form: Decodable { let gameType: String; let rader: [Rad]? }
    struct Fil: Decodable {
        let spillehandicap: [String: Double]
        let scorer: [String: [Int]]
        let former: [Form]
    }

    let fil: Fil

    init() throws {
        fil = try Fixture.load(Fil.self, "rundens-form")
    }

    static let course = Course(id: "bane", name: "Testbanen", par: 72, courseRating: 72, slopeRating: 113,
                               holes: (0..<18).map { CourseHole(par: 4, si: $0 + 1) })

    func round(_ gameType: String) -> Round {
        var scores: [String: HoleScores] = [:]
        for (p, list) in fil.scorer {
            scores[p] = Dictionary(uniqueKeysWithValues: list.enumerated().map { ($0, $1) })
        }
        return Round(id: gameType, gameType: gameType, holeCount: 18, holeStart: 0, course: Self.course,
                     hcpAllowance: 1, holeScores: scores, locked: false, playingHandicaps: fil.spillehandicap)
    }

    @Test func formResultatet() {
        for form in fil.former {
            let result = FormPlay.formResult(round(form.gameType), roster: [], rules: .golfgutu)
            guard let want = form.rader else {
                #expect(result == nil, "\(form.gameType)")
                continue
            }
            guard let result else { Issue.record("\(form.gameType): mangler resultat"); continue }
            #expect(result.rows.map(\.players) == want.map { [$0.spiller] }, "\(form.gameType): rekkefølge")
            #expect(result.rows.map(\.score) == want.map(\.score), "\(form.gameType): sum")
            #expect(result.rows.map(\.holes) == want.map(\.hull), "\(form.gameType): hull")
            #expect(result.rows.map(\.rank) == want.map(\.plass), "\(form.gameType): plass")
        }
    }

    /// Brutto ser bort fra handicap også når andelen i runden ikke er 0.
    @Test func bruttoUtenHandicapUansettAndel() throws {
        var r = round("slag-brutto")
        r.hcpAllowance = 0.95
        let result = try #require(FormPlay.formResult(r, roster: [], rules: .golfgutu))
        #expect(result.rows.map(\.score) == [12, 14, 22])
    }
}
