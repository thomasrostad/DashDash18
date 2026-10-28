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

    // MARK: Plasseringspoeng

    private func placementRules(_ scale: [Double]) -> Ruleset {
        var r = Ruleset.golfgutu
        r.table.pointsSource = .placement
        r.table.placementPoints = scale
        return r
    }

    /// Slagspill netto: b 11, a 12, c 16 gir 1., 2. og 3. plass.
    @Test func plasseringspoengEtterFormen() {
        let p = FormPlay.placementPoints(round("slag-netto"), roster: [], rules: placementRules([10, 6, 4]))
        #expect(p == ["b": 10, "a": 6, "c": 4])
    }

    /// Delt plass deler poengene for plassene, og plasser etter skalaen gir 0.
    @Test func deltPlassOgUtenforSkalaen() {
        var r = round("slag-brutto")
        r.holeScores["b"] = [0: 4, 1: 5, 2: 3]   // b går 12 som a
        let p = FormPlay.placementPoints(r, roster: [], rules: placementRules([10, 6]))
        #expect(p == ["a": 8, "b": 8, "c": 0])
    }

    /// Netto stableford har ikke noe formresultat: plassen kommer fra stablefordsummen. Netto: a 4 5 3
    /// (2 + 1 + 3 = 6), b 3 4 4 (3 + 2 + 2 = 7), c 4 5 7 (2 + 1 + 0 = 3).
    @Test func plasseringINettoStableford() {
        // Stablefordveien (`Scoring.roundPoints`) finner spilleren i troppen før spillehandicapet brukes.
        let roster = ["a", "b", "c"].map { Player(id: $0, name: $0.uppercased()) }
        let p = FormPlay.placementPoints(round("stableford"), roster: roster, rules: placementRules([10, 6, 4]))
        #expect(p == ["b": 10, "a": 6, "c": 4])
    }

    /// Uten egen skala gjelder standarden (25, 20, 16 …).
    @Test func standardskala() {
        let p = FormPlay.placementPoints(round("stableford-brutto"), roster: [], rules: placementRules([]))
        #expect(p == ["a": 25, "b": 20, "c": 16])
    }

    /// Tabellen teller plasseringspoengene: to runder slagspill netto (b 10 + 10, a 6 + 6, c 4 + 4).
    @Test func tabellenTellerPlassering() {
        var rules = placementRules([10, 6, 4])
        rules.table.counting = Ruleset.Counting(unit: .round, best: nil)
        var second = round("slag-netto")
        second.id = "slag-netto-2"
        let roster = ["a", "b", "c"].map { Player(id: $0, name: $0.uppercased()) }
        let board = Season(players: roster, rounds: [round("slag-netto"), second], ruleset: rules).jacketBoard()
        #expect(board.map(\.player.id) == ["b", "a", "c"])
        #expect(board.map(\.total) == [20, 12, 8])
    }

    /// Golfgutu skriver ikke de nye feltene, så JSON-en er som før.
    @Test func golfgutuJSONUendret() throws {
        let json = try JSONEncoder().encode(Ruleset.golfgutu.table)
        let text = String(decoding: json, as: UTF8.self)
        #expect(!text.contains("placementPoints") && !text.contains("pointsSource"))
        var r = Ruleset.golfgutu.table
        r.pointsSource = .placement
        r.placementPoints = [10, 6]
        let back = try JSONDecoder().decode(Ruleset.TableRules.self, from: JSONEncoder().encode(r))
        #expect(back == r)
    }

    /// Brutto ser bort fra handicap også når andelen i runden ikke er 0.
    @Test func bruttoUtenHandicapUansettAndel() throws {
        var r = round("slag-brutto")
        r.hcpAllowance = 0.95
        let result = try #require(FormPlay.formResult(r, roster: [], rules: .golfgutu))
        #expect(result.rows.map(\.score) == [12, 14, 22])
    }
}
