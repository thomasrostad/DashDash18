import Foundation
import Testing
@testable import GolfgutuCore

/// Rundens frosne spillehandicap i sesongen. Tall: Fixtures/frosset-handicap.json (regnet med reglene i
/// db-nytt.js). Uten frosset handicap regnes alt fra troppen, som før.
struct FrozenHandicapTests {
    struct Fil: Decodable {
        let spillere: [Player]
        let runder: [Round]
        let spillehandicap: [String: [String: Double]]
        let frosset: Forventet
        let troppen: Forventet
    }
    struct Res: Decodable, Hashable { let roundId: String; let poeng: Double; let hull: Int }
    struct Jakke: Decodable { let id: String; let total, duell, side: Double; let matcher, hull, spilte, stableford: Int }
    struct Forventet: Decodable {
        let rundePoeng: [[String: Int]]
        let matcher: [String: [Res]]
        let jakketavle: [Jakke]
    }

    let fil: Fil

    init() throws {
        fil = try Fixture.load(Fil.self, "frosset-handicap")
    }

    func check(_ season: Season, _ f: Forventet) {
        #expect(season.rounds.indices.map(season.roundPoints) == f.rundePoeng)
        for (pid, expected) in f.matcher {
            let got = season.matchResults(for: pid).counting.map { Res(roundId: $0.roundID ?? "", poeng: $0.points, hull: $0.holes) }
            #expect(Set(got) == Set(expected), "matcher for \(pid)")
        }
        let board = season.jacketBoard()
        #expect(board.map(\.player.id) == f.jakketavle.map(\.id))
        for (row, e) in zip(board, f.jakketavle) {
            #expect(row.total == e.total && row.duel == e.duell && row.side == e.side, "\(e.id)")
            #expect(row.matches == e.matcher && row.holes == e.hull && row.played == e.spilte, "\(e.id)")
            #expect(row.stableford == e.stableford, "\(e.id)")
        }
    }

    @Test func utenFrossetHandicapRegnesFraTroppen() {
        check(Season(players: fil.spillere, rounds: fil.runder), fil.troppen)
    }

    @Test func frossetHandicapGjelderPerRunde() {
        check(Season(players: fil.spillere, rounds: fil.runder, playingHandicaps: fil.spillehandicap), fil.frosset)
    }

    @Test func frossetHandicapPaaRundenGirSammeSvar() {
        let rounds = fil.runder.map { r -> Round in
            var r = r
            r.playingHandicaps = fil.spillehandicap[r.id ?? ""] ?? [:]
            return r
        }
        check(Season(players: fil.spillere, rounds: rounds), fil.frosset)
    }

    @Test func overstyringenVinnerOverRunden() {
        // Runden har et annet tall lagret; sesongens overstyring er fasit.
        var r1 = fil.runder[0]
        r1.playingHandicaps = ["b": 9]
        let season = Season(players: fil.spillere, rounds: [r1, fil.runder[1]], playingHandicaps: fil.spillehandicap)
        #expect(season.roundPoints(0) == fil.frosset.rundePoeng[0])
    }

    @Test func spillereUtenFrossetTallRegnesFraTroppen() {
        // Bare Bjørn i kveld 1 er frosset; Anders (0 i troppen) og kveld 2 (9 i troppen) regnes som før.
        let season = Season(players: fil.spillere, rounds: fil.runder, playingHandicaps: ["r1": ["b": 18]])
        #expect(season.roundPoints(0) == fil.frosset.rundePoeng[0])
        #expect(season.roundPoints(1) == fil.troppen.rundePoeng[1])
    }

    @Test func simulatorenGirFortsattNull() {
        var r = fil.runder[0]
        r.hcpExtern = true
        r.playingHandicaps = ["b": 18]
        let b = fil.spillere[1]
        #expect(Handicap.effective(for: b, in: r, roster: fil.spillere) == 0)
    }

    @Test func frossetTallErEffektivtHandicap() {
        var r = fil.runder[0]
        r.playingHandicaps = ["b": 18]
        #expect(Handicap.effective(for: fil.spillere[1], in: r, roster: fil.spillere) == 18)
        #expect(Handicap.effective(for: fil.spillere[0], in: r, roster: fil.spillere) == 0)
    }

    @Test func dekodesUtenFeltet() throws {
        let r = try JSONDecoder().decode(Round.self, from: Data(#"{"id":"x"}"#.utf8))
        #expect(r.playingHandicaps.isEmpty)
    }
}
