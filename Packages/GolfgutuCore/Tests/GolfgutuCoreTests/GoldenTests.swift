import Foundation
import Testing
@testable import GolfgutuCore

/// Goldenfiler for TypeScript-motoren (`web/golfgutu-core`): hele sesongtabeller og alt motoren regner
/// per runde, for fixturene og noen regelsett til, skrevet som JSON med sorterte nøkler.
///
/// Vanlig kjøring sammenligner med filene i `Fixtures/golden/`, så de alltid stemmer med Swift-motoren.
/// Endres motoren med vilje, skrives filene på nytt med `GOLDEN_WRITE=1 swift test --filter GoldenTests`,
/// og TS-testene sjekker at TypeScript gir de samme tallene.
struct GoldenTests {
    // MARK: Utdata

    struct Selection<T: Encodable>: Encodable {
        let counting: [T]
        let dropped: [T]
    }

    struct MatchResultDump: Encodable {
        let roundIndex: Int
        let roundID: String?
        let matchNo: Int?
        let points: Double
        let holes: Int
        let isTriangle: Bool
    }

    struct SideDump: Encodable {
        let roundIndex: Int
        let roundID: String?
        let kind: String
        let shared: Bool
        let points: Double
    }

    struct RoundScoreDump: Encodable {
        let roundIndex: Int
        let roundID: String?
        let points: Double
    }

    struct SumDump: Encodable {
        let points: Double
        let holes: Int
        let matches: Int
    }

    struct PlayerDump: Encodable {
        let id: String
        let tableMatches: Selection<MatchResultDump>
        let tableSidePrizes: Selection<SideDump>
        let tableRounds: Selection<RoundScoreDump>
        let matchTotals: SumDump
        let sidePrizePoints: Double
        let weightedRoundPoints: [Double?]
        let countingRounds: Selection<RoundScoreDump>
        let stablefordTotal: Int
    }

    struct JacketDump: Encodable {
        let id: String
        let name: String
        let total: Double
        let duel: Double
        let side: Double
        let matches: Int
        let holes: Int
        let played: Int
        let stableford: Int
        let roundPoints: Double
        let totalText: String
    }

    struct StablefordDump: Encodable {
        let id: String
        let total: Int
        let played: Int
        let counting: Int
        let dropped: Int
    }

    struct SeasonDump: Encodable {
        let name: String
        let variant: String
        /// Regelsettet slik `Ruleset` skriver det; TS leser det herfra.
        let rules: Ruleset
        let roundPoints: [[String: Int]]
        let players: [PlayerDump]
        let jacketBoard: [JacketDump]
        let stablefordBoard: [StablefordDump]
        let eveningDates: [String]
        let roundNumbers: [Int]
        let draw: [[String]]
    }

    struct StandingDump: Encodable {
        let up: Int
        let played: Int
        let remaining: Int
        let decided: Bool
        let opponents: [String]
        let text: String
        let shortText: String
    }

    struct DiffDump: Encodable {
        let up: Int
        let played: Int
    }

    struct MatchDump: Encodable {
        let a: [String]
        let b: [String]
        let c: [String]?
        let strokeOffset: Double
        let holeWinners: [Int?]
        let holeDiff: DiffDump?
        let outcomeForA: Double?
        let standings: [String: StandingDump]
        let triangle: [String: Double]?
    }

    struct RoundDump: Encodable {
        let name: String
        let courseHoles: [PlayedHole]
        let countingHoles: Int
        let lowestCommonHole: Int
        let effective: [String: Double]
        let courseHandicap: [String: Double]
        let teamBasis: [String: Double]
        let netTotal: [String: Int]
        let roundPoints: [String: Int]
        let matches: [MatchDump]
        let ldHole: Int?
        let kpHole: Int?
        let suggestedLD: Int
        let suggestedKP: Int
    }

    // MARK: Regelsettene

    /// Variantene hver sesong regnes med. Regelsettet står i goldenfila, så TS trenger ikke å kjenne dem.
    static let variants: [(String, Ruleset)] = {
        var eveningBest2 = Ruleset.golfgutu
        eveningBest2.table.counting = .init(unit: .evening, best: 2)
        eveningBest2.table.stablefordCounting = .init(unit: .evening, best: 2)
        eveningBest2.table.roundingStep = nil

        var roundBest3 = Ruleset.golfgutu
        roundBest3.table.counting = .init(unit: .round, best: 3)
        roundBest3.table.matchPoints = .init(win: 2, draw: 1, loss: 0)
        roundBest3.table.trianglePoints = [3, 1, 0]
        roundBest3.table.tiebreaks = [.stableford, .holeDifference]
        roundBest3.formats.matchStrokes = .fullHandicap
        roundBest3.sidePrizes.splitTies = false
        roundBest3.scoring = .init(netParPoints: 3, minimumPoints: 0)

        var stablefordRounds = RulesetTemplate.stablefordSeries.rules
        stablefordRounds.table.counting = .init(unit: .round, best: 2)
        stablefordRounds.table.roundingStep = 1
        stablefordRounds.sidePrizes.longestDrive = .init(enabled: true, points: 2)
        stablefordRounds.sidePrizes.closestToPin = .init(enabled: true, points: 0.5)

        return [("golfgutu", .golfgutu), ("stablefordSeries", RulesetTemplate.stablefordSeries.rules),
                ("eveningBest2", eveningBest2), ("roundBest3", roundBest3), ("stablefordRoundBest2", stablefordRounds)]
    }()

    // MARK: Dump

    static func dump(_ name: String, _ variant: String, _ s: Season) -> SeasonDump {
        func sel<A, B: Encodable>(_ c: [A], _ d: [A], _ f: (A) -> B) -> Selection<B> {
            Selection(counting: c.map(f), dropped: d.map(f))
        }
        func m(_ r: Season.MatchResult) -> MatchResultDump {
            MatchResultDump(roundIndex: r.roundIndex, roundID: r.roundID, matchNo: r.matchNo, points: r.points,
                            holes: r.holes, isTriangle: r.isTriangle)
        }
        func sd(_ r: Season.SidePrizeResult) -> SideDump {
            SideDump(roundIndex: r.roundIndex, roundID: r.roundID, kind: r.kind.rawValue, shared: r.shared, points: r.points)
        }
        func rs(_ r: Season.RoundScore) -> RoundScoreDump {
            RoundScoreDump(roundIndex: r.roundIndex, roundID: r.roundID, points: r.points)
        }
        let players = s.players.map { p -> PlayerDump in
            let t = s.tableSelection(for: p.id)
            let sum = s.matchTotals(for: p.id)
            let cr = s.countingRounds(for: p.id)
            return PlayerDump(
                id: p.id,
                tableMatches: sel(t.matches.counting, t.matches.dropped, m),
                tableSidePrizes: sel(t.sidePrizes.counting, t.sidePrizes.dropped, sd),
                tableRounds: sel(t.rounds.counting, t.rounds.dropped, rs),
                matchTotals: SumDump(points: sum.points, holes: sum.holes, matches: sum.matches),
                sidePrizePoints: s.sidePrizePoints(for: p.id),
                weightedRoundPoints: s.rounds.indices.map { s.weightedRoundPoints($0, playerID: p.id) },
                countingRounds: sel(cr.counting, cr.dropped, rs),
                stablefordTotal: s.stablefordTotal(for: p.id))
        }
        return SeasonDump(
            name: name, variant: variant, rules: s.ruleset,
            roundPoints: s.rounds.indices.map(s.roundPoints),
            players: players,
            jacketBoard: s.jacketBoard().map {
                JacketDump(id: $0.player.id, name: $0.player.name, total: $0.total, duel: $0.duel, side: $0.side,
                           matches: $0.matches, holes: $0.holes, played: $0.played, stableford: $0.stableford,
                           roundPoints: $0.roundPoints, totalText: Season.formatPoints($0.total, rules: s.ruleset))
            },
            stablefordBoard: s.stablefordBoard().map {
                StablefordDump(id: $0.player.id, total: $0.total, played: $0.played, counting: $0.counting, dropped: $0.dropped)
            },
            eveningDates: Season.eveningDates(s.rounds),
            roundNumbers: s.rounds.map { s.roundNumber(for: $0.date) },
            draw: s.drawMatches(s.players, round: 1))
    }

    static func dump(_ name: String, _ round: Round, roster: [Player], rules: Ruleset = .golfgutu) -> RoundDump {
        func perPlayer<T>(_ f: (Player) -> T) -> [String: T] {
            Dictionary(roster.map { ($0.id, f($0)) }, uniquingKeysWith: { first, _ in first })
        }
        let matches = round.matches.map { m -> MatchDump in
            let s = MatchPlay.sides(of: m, in: round)
            let d = MatchPlay.holeDiff(m, in: round, roster: roster, rules: rules)
            var standings: [String: StandingDump] = [:]
            for pid in s.all {
                guard let st = MatchPlay.standing(m, from: pid, in: round, roster: roster, rules: rules) else { continue }
                standings[pid] = StandingDump(up: st.up, played: st.played, remaining: st.remaining, decided: st.decided,
                                              opponents: st.opponents, text: MatchPlay.text(st),
                                              shortText: MatchPlay.shortText(st))
            }
            return MatchDump(
                a: s.a, b: s.b, c: s.c,
                strokeOffset: MatchPlay.strokeOffset(for: m, in: round, roster: roster, rules: rules),
                holeWinners: (0..<round.numberOfHoles).map {
                    MatchPlay.holeWinner(m, hole: $0, in: round, roster: roster, rules: rules)
                },
                holeDiff: d.map { DiffDump(up: $0.up, played: $0.played) },
                outcomeForA: MatchPlay.outcomeForA(m, in: round, roster: roster, rules: rules),
                standings: standings,
                triangle: Triangle.points(m, in: round, roster: roster, rules: rules))
        }
        return RoundDump(
            name: name,
            courseHoles: round.courseHoles(),
            countingHoles: Truncation.countingHoles(round),
            lowestCommonHole: Truncation.lowestCommonHole(round),
            effective: perPlayer { Handicap.effective(for: $0, in: round, roster: roster, rules: rules) },
            courseHandicap: perPlayer { Handicap.courseHandicap(for: $0, in: round, rules: rules) },
            teamBasis: perPlayer { Handicap.teamBasis(for: $0, in: round, rules: rules) },
            netTotal: perPlayer { Scoring.roundNetTotal(round, player: $0, roster: roster, rules: rules) },
            roundPoints: Scoring.roundPoints(round, roster: roster, rules: rules),
            matches: matches,
            ldHole: SidePrizes.longestDriveHole(round),
            kpHole: SidePrizes.closestToPinHole(round),
            suggestedLD: SidePrizes.suggestedLongestDriveHole(round),
            suggestedKP: SidePrizes.suggestedClosestToPinHole(round))
    }

    // MARK: Filene

    static func seasons() throws -> [SeasonDump] {
        let fil = try Fixture.load(SeasonTests.Fil.self, "sesong")
        let saker = fil.saker + fil.annetRegelsett.map(\.sak)
        var out: [SeasonDump] = []
        for sak in saker {
            for (variant, rules) in variants {
                let s = Season(players: sak.spillere, rounds: sak.runder, claims: sak.claims, ruleset: rules)
                out.append(dump(sak.navn, variant, s))
            }
        }
        // Stableford-tabellen (runder bygd av poengene, se StablefordTableTests) med sakens regelsett.
        let sf = try Fixture.load(StablefordTableTests.Fil.self, "sesong-stableford")
        let sfRounds = StablefordTableTests.rounds(sf)
        for sak in sf.saker {
            out.append(dump("sesong-stableford: \(sak.navn)", "fixture",
                            Season(players: sf.spillere, rounds: sfRounds, claims: sf.claims, ruleset: sak.regelsett.ruleset)))
        }
        for (variant, rules) in variants {
            out.append(dump("sesong-stableford", variant,
                            Season(players: sf.spillere, rounds: sfRounds, claims: sf.claims, ruleset: rules)))
        }
        // Frosset handicap, med og uten.
        let fh = try Fixture.load(FrozenHandicapTests.Fil.self, "frosset-handicap")
        out.append(dump("frosset-handicap", "troppen", Season(players: fh.spillere, rounds: fh.runder)))
        out.append(dump("frosset-handicap", "frosset",
                        Season(players: fh.spillere, rounds: fh.runder, playingHandicaps: fh.spillehandicap)))
        return out
    }

    static func rounds() throws -> [RoundDump] {
        var out: [RoundDump] = []
        let sesong = try Fixture.load(SeasonTests.Fil.self, "sesong")
        for sak in sesong.saker + sesong.annetRegelsett.map(\.sak) {
            for (i, r) in sak.runder.enumerated() { out.append(dump("sesong: \(sak.navn) #\(i)", r, roster: sak.spillere)) }
        }
        let match = try Fixture.load(MatchTests.Fil.self, "match")
        for sak in match.saker { out.append(dump("match: \(sak.navn)", sak.runde, roster: sak.spillere)) }
        let avk = try Fixture.load(TruncationTests.Fil.self, "avkorting")
        for sak in avk.saker { out.append(dump("avkorting: \(sak.navn)", sak.runde, roster: avk.spillere)) }
        out.append(dump("avkorting: koster", avk.avkortingenKoster.runde, roster: avk.avkortingenKoster.spillere))
        let hcp = try Fixture.load(HandicapTests.Fil.self, "handicap")
        for sak in hcp.saker { out.append(dump("handicap: \(sak.navn)", sak.runde, roster: sak.spillere)) }
        let tre = try Fixture.load(TriangleTests.Fil.self, "trekant")
        for t in tre.trekanter { out.append(dump("trekant: \(t.navn)", t.runde, roster: t.spillere)) }
        let fh = try Fixture.load(FrozenHandicapTests.Fil.self, "frosset-handicap")
        for (i, r) in fh.runder.enumerated() { out.append(dump("frosset: #\(i)", r, roster: fh.spillere)) }
        return out
    }

    static let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("Fixtures/golden", isDirectory: true)

    static func encoded<T: Encodable>(_ value: T) throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try e.encode(value)
    }

    /// Skriver fila med `GOLDEN_WRITE=1`, ellers sammenligner den byte for byte.
    static func check(_ name: String, _ data: Data) throws {
        let url = directory.appendingPathComponent("\(name).json")
        if ProcessInfo.processInfo.environment["GOLDEN_WRITE"] == "1" {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: url)
            return
        }
        let existing = try Data(contentsOf: url)
        #expect(existing == data, "Fixtures/golden/\(name).json stemmer ikke med motoren. Kjør GOLDEN_WRITE=1 swift test --filter GoldenTests.")
    }

    @Test func sesongtabeller() throws {
        try Self.check("sesonger", Self.encoded(Self.seasons()))
    }

    @Test func runder() throws {
        try Self.check("runder", Self.encoded(Self.rounds()))
    }
}
