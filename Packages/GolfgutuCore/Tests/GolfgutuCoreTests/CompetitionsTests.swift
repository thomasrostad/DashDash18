import Foundation
import Testing
@testable import GolfgutuCore

/// Fase 15: liga, morroturnering og cup (Competitions.swift). Fasit: `Fixtures/konkurranser.json`.
struct CompetitionsTests {
    struct Fil: Decodable {
        struct Liga: Decodable {
            struct Rad: Decodable {
                let id: String
                let plass: Int
                let total: Double
                let spilt: Int
                let seire: Int
                let beste: Double?
                let stableford: Int
                /// [runde, plass, poeng, teller]
                let runder: [[Verdi]]
            }

            let navn: String
            /// Overstyringer av malen, som i regelsettet.
            struct Regler: Codable {
                var placementPoints: [Double]?
                var participationPoints: Double?
                var bestRounds: Int?
            }

            let regler: Regler
            let malen: String
            let pameldte: [String]
            let runder: [League.Round]
            let forventet: [Rad]
        }

        struct Seeding: Decodable {
            let navn: String
            let regler: CupRules
            let frø: UInt64
            let deltakere: [Cup.Entrant]
            let forventet: [String]
        }

        struct Tre: Decodable {
            struct Forventet: Decodable {
                /// Per runde: [a, b, vinner].
                let runder: [[[String?]]]
                let mester: String?
                let klare: [[Int]]
                let motstander: [String: String?]
                let ute: [String]
            }

            let navn: String
            let seedet: [String]
            let forsteRunde: [Cup.Pairing]
            let resultater: [Cup.Result]
            let forventet: Forventet
        }

        let liga: [Liga]
        let seedplasser: [String: [Int]]
        let seeding: [Seeding]
        let tre: [Tre]
    }

    /// Tall, streng eller sannhetsverdi i JSON-lister.
    enum Verdi: Decodable, Equatable {
        case number(Double)
        case string(String)
        case bool(Bool)

        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let b = try? c.decode(Bool.self) { self = .bool(b) }
            else if let d = try? c.decode(Double.self) { self = .number(d) }
            else { self = .string(try c.decode(String.self)) }
        }
    }

    static let fil: Fil = try! Fixture.load(Fil.self, "konkurranser")

    static func rules(_ l: Fil.Liga) throws -> LeagueRules {
        let base: LeagueRules = l.malen == "fun" ? .fun : .league
        // Overstyringene leses som i regelsettet: feltene som mangler, får malen.
        let overrides = try JSONSerialization.jsonObject(with: JSONEncoder().encode(l.regler))
        let json = try JSONSerialization.data(withJSONObject: ["competition": [l.malen: overrides], "version": 2])
        let ruleset = try JSONDecoder().decode(Ruleset.self, from: json)
        let decoded = l.malen == "fun" ? ruleset.competitionRules.fun : ruleset.competitionRules.league
        if (overrides as? [String: Any])?.isEmpty == true { #expect(decoded == base) }
        return decoded
    }

    // MARK: Liga og morroturnering

    @Test(arguments: fil.liga.indices)
    func ligatabell(_ i: Int) throws {
        let l = Self.fil.liga[i]
        let rows = League.table(entrants: l.pameldte, rounds: l.runder, rules: try Self.rules(l))
        #expect(rows.map(\.playerID) == l.forventet.map(\.id), "\(l.navn)")
        for (row, f) in zip(rows, l.forventet) {
            #expect(row.place == f.plass, "\(l.navn): \(f.id) plass")
            #expect(abs(row.total - f.total) < 1e-9, "\(l.navn): \(f.id) total \(row.total)")
            #expect(row.played == f.spilt && row.wins == f.seire && row.stableford == f.stableford, "\(l.navn): \(f.id)")
            #expect(row.bestRound == f.beste, "\(l.navn): \(f.id) beste")
            let results = row.results.map { r -> [Verdi] in
                [.string(r.roundID), .number(Double(r.place)), .number(r.points), .bool(r.counted)]
            }
            #expect(results == f.runder, "\(l.navn): \(f.id) runder")
        }
    }

    @Test func ikkePameldtTarIngenPlass() {
        let round = League.Round(id: "r", stableford: ["x": 45, "a": 20, "b": 10])
        let p = League.placings(round, entrants: ["a", "b"], rules: .league)
        #expect(p["a"] == League.Placing(place: 1, points: 11))
        #expect(p["b"] == League.Placing(place: 2, points: 9))
        #expect(p["x"] == nil)
    }

    @Test func beste1VelgerTidligsteVedLikt() {
        var rules = LeagueRules.league
        rules.bestRounds = 1
        let rows = League.table(entrants: ["a", "b"], rounds: [
            League.Round(id: "r1", stableford: ["a": 30, "b": 20]),
            League.Round(id: "r2", stableford: ["a": 25, "b": 20]),
        ], rules: rules)
        // a vinner begge (11 og 11): den første teller.
        #expect(rows[0].results.map(\.counted) == [true, false])
        #expect(rows[0].stableford == 30)
    }

    // MARK: Regelsettet

    @Test func golfgutuHarIngenKonkurranseregler() throws {
        #expect(Ruleset.golfgutu.competition == nil)
        #expect(Ruleset.golfgutu.competitionRules == .standard)
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Ruleset.golfgutu)) as? [String: Any]
        #expect(json?["competition"] == nil)
        // Malens JSON for sesongen (fixturen) gir fortsatt Golfgutu-oppsettet.
        #expect(try JSONDecoder().decode(Ruleset.self, from: Fixture.data("regelsett-golfgutu")) == .golfgutu)
    }

    @Test func konkurransereglerRundtur() throws {
        var r = Ruleset.golfgutu
        r.competition = CompetitionRules(league: LeagueRules(scoring: .stableford, placementPoints: [5, 3, 1],
                                                             participationPoints: 2, bestRounds: nil, tiebreaks: [.stableford]),
                                         fun: .fun, cup: CupRules(seeding: .ranking, tie: .countback))
        let rundtur = try JSONDecoder().decode(Ruleset.self, from: JSONEncoder().encode(r))
        #expect(rundtur == r)
        // Delvis: resten fra malene. `bestRounds: null` er et valg.
        let delvis = try JSONDecoder().decode(Ruleset.self, from: Data("""
        {"version": 2, "competition": {"league": {"bestRounds": 4}, "cup": {"tie": "higherSeed"}}}
        """.utf8))
        #expect(delvis.competitionRules.league.bestRounds == 4)
        #expect(delvis.competitionRules.league.placementPoints == LeagueRules.league.placementPoints)
        #expect(delvis.competitionRules.fun == .fun)
        #expect(delvis.competitionRules.cup == CupRules(seeding: .random, tie: .higherSeed))
        let alle = try JSONDecoder().decode(Ruleset.self, from: Data("""
        {"version": 2, "competition": {"fun": {"bestRounds": null}}}
        """.utf8))
        #expect(alle.competitionRules.fun.bestRounds == nil)
        // Versjon 1 har ingen konkurranseregler.
        #expect(try JSONDecoder().decode(Ruleset.self, from: Data(#"{"version": 1}"#.utf8)).competition == nil)
    }

    @Test func validering() {
        #expect(CompetitionRules.standard.validate().isEmpty)
        var c = CompetitionRules.standard
        c.league.placementPoints = [5, 8]
        c.league.bestRounds = 0
        c.fun.participationPoints = -1
        c.fun.tiebreaks = [.wins, .wins]
        let felt = Set(c.validate().map(\.field))
        #expect(felt == ["competition.league.placementPoints", "competition.league.bestRounds",
                         "competition.fun.participationPoints", "competition.fun.tiebreaks"])
    }

    // MARK: Cup

    @Test func seedplasser() {
        for (size, forventet) in Self.fil.seedplasser {
            #expect(Cup.seedPositions(size: Int(size)!) == forventet)
        }
        #expect(Cup.bracketSize(entrants: 2) == 2)
        #expect(Cup.bracketSize(entrants: 3) == 4)
        #expect(Cup.bracketSize(entrants: 5) == 8)
        #expect(Cup.bracketSize(entrants: 8) == 8)
        #expect(Cup.bracketSize(entrants: 9) == 16)
    }

    @Test(arguments: fil.seeding.indices)
    func seeding(_ i: Int) {
        let s = Self.fil.seeding[i]
        #expect(Cup.seeded(s.deltakere, rules: s.regler, randomSeed: s.frø) == s.forventet, "\(s.navn)")
        // Trekningen er gjentakbar.
        #expect(Cup.seeded(s.deltakere.reversed(), rules: s.regler, randomSeed: s.frø) == s.forventet, "\(s.navn) baklengs")
    }

    @Test func splitMix64Referanse() {
        var g = SplitMix64(seed: 0)
        #expect(g.next() == 0xE220_A839_7B1D_CDAF)
    }

    @Test(arguments: fil.tre.indices)
    func tre(_ i: Int) {
        let t = Self.fil.tre[i]
        let draw = Cup.draw(seeded: t.seedet)
        #expect(draw == t.forsteRunde, "\(t.navn): første runde")
        let b = Cup.bracket(draw: draw, results: t.resultater)
        let runder = b.rounds.map { $0.map { [$0.a, $0.b, $0.winner] } }
        #expect(runder == t.forventet.runder, "\(t.navn): treet")
        #expect(b.champion == t.forventet.mester, "\(t.navn): mester")
        #expect(b.readyMatches.map { [$0.round, $0.slot] } == t.forventet.klare, "\(t.navn): klare")
        for (spiller, motstander) in t.forventet.motstander {
            #expect(b.opponent(of: spiller) == motstander, "\(t.navn): motstander for \(spiller)")
        }
        let alle = Set(t.seedet)
        #expect(Set(alle.filter(b.isEliminated)) == Set(t.forventet.ute), "\(t.navn): ute")
    }

    @Test func forFaDeltakere() {
        #expect(Cup.draw(seeded: ["a"]).isEmpty)
        #expect(Cup.bracket(draw: [], results: []).rounds.isEmpty)
    }

    /// Rader som ikke passer (to kamper på samme plass, et hull i rekken), gir et tre uten krasj.
    @Test func ugyldigTrekningKrasjerIkke() {
        let b = Cup.bracket(draw: [Cup.Pairing(slot: 0, a: "a", b: "b"), Cup.Pairing(slot: 0, a: "c", b: "d"),
                                   Cup.Pairing(slot: 2, a: "e", b: nil)],
                            results: [Cup.Result(round: 1, slot: 0, winner: "c")])
        #expect(b.rounds.map(\.count) == [4, 2, 1])
        #expect(b.rounds[0].map(\.a) == ["c", nil, "e", nil])
        #expect(b.rounds[1][0].a == "c" && b.rounds[1][1].a == "e" && b.rounds[1][1].b == nil)
    }

    // MARK: Kampen i en runde

    /// 9 hull uten bane (indeks = hullnummer), frosset spillehandicap.
    static func round(_ a: [Int], _ b: [Int], hcp: (Double, Double) = (0, 0)) -> Round {
        Round(holeCount: 9,
              holeScores: ["a": Dictionary(uniqueKeysWithValues: a.enumerated().map { ($0, $1) }),
                           "b": Dictionary(uniqueKeysWithValues: b.enumerated().map { ($0, $1) })],
              playingHandicaps: ["a": hcp.0, "b": hcp.1])
    }

    static func rules(tie: CupRules.Tie) -> Ruleset {
        var r = Ruleset.golfgutu
        r.competition = CompetitionRules(cup: CupRules(seeding: .random, tie: tie))
        return r
    }

    static let roster = [Player(id: "a"), Player(id: "b")]

    @Test func avgjortFor18() {
        // a vinner de tre første og deler de fire neste: 3 opp med 2 igjen = 3&2.
        let r = Self.round([4, 4, 4, 4, 4, 4, 4], [5, 5, 5, 4, 4, 4, 4])
        #expect(Cup.decide(a: "a", b: "b", in: r, roster: Self.roster, rules: Self.rules(tie: .suddenDeath))
                == .won(winner: "a", up: 3, remaining: 2, tie: nil))
    }

    @Test func pagarOgIkkeStartet() {
        let r = Self.round([4, 4, 4], [5, 4, 4])
        #expect(Cup.decide(a: "a", b: "b", in: r, roster: Self.roster, rules: .golfgutu)
                == .inProgress(up: 1, played: 3, remaining: 6))
        #expect(Cup.decide(a: "b", b: "a", in: r, roster: Self.roster, rules: .golfgutu)
                == .inProgress(up: -1, played: 3, remaining: 6))
        #expect(Cup.decide(a: "a", b: "b", in: Self.round([], []), roster: Self.roster, rules: .golfgutu) == .notStarted)
    }

    @Test func likEtterSisteHull() {
        // a vinner hull 1, b vinner hull 8, hull 9 er delt.
        let r = Self.round([4, 4, 4, 4, 4, 4, 4, 5, 4], [5, 4, 4, 4, 4, 4, 4, 4, 4])
        #expect(Cup.decide(a: "a", b: "b", in: r, roster: Self.roster, rules: Self.rules(tie: .suddenDeath)) == .tied)
        #expect(Cup.decide(a: "a", b: "b", in: r, roster: Self.roster, rules: Self.rules(tie: .countback))
                == .won(winner: "b", up: 0, remaining: 0, tie: .countback))
        #expect(Cup.decide(a: "a", b: "b", in: r, roster: Self.roster, rules: Self.rules(tie: .higherSeed),
                           seeds: ["a": 3, "b": 2]) == .won(winner: "b", up: 0, remaining: 0, tie: .higherSeed))
        #expect(Cup.decide(a: "a", b: "b", in: r, roster: Self.roster, rules: Self.rules(tie: .higherSeed)) == .tied)
        #expect(Cup.decide(a: "a", b: "b", in: r, roster: Self.roster, rules: Self.rules(tie: .lowerHandicap)) == .tied)
    }

    @Test func lavestHandicapVedLikt() {
        // b får to slag (hull med indeks 1 og 2) og bruker dem: alle hull delt netto.
        let r = Self.round([4, 4, 4, 4, 4, 4, 4, 4, 4], [5, 5, 4, 4, 4, 4, 4, 4, 4], hcp: (10, 12))
        #expect(Cup.decide(a: "a", b: "b", in: r, roster: Self.roster, rules: Self.rules(tie: .lowerHandicap))
                == .won(winner: "a", up: 0, remaining: 0, tie: .lowerHandicap))
        // Countback finner ikke noe hull som ikke er delt.
        #expect(Cup.decide(a: "a", b: "b", in: r, roster: Self.roster, rules: Self.rules(tie: .countback)) == .tied)
    }
}
