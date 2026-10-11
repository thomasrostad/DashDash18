import Foundation
import Testing
@testable import GolfgutuCore

/// Tabellregler og playoff (steg 6): minste antall kvelder, navngitte poengtabeller, snitt, kveld som
/// ikke teller, playoff om førsteplassen, «skjul de siste hullene» og trekningsvalg. Tall:
/// Fixtures/tabellregler.json (regnet for hånd) og Fixtures/trekning.json (trekningen, fra Swift-motoren).
struct TableRulesTests {
    struct Fil: Decodable {
        let spillere: [Player]
        let runder: [Runde]
        let saker: [Sak]
        let playoff: PlayoffFil
        let skjul: SkjulFil
        let manuell: ManuellFil
        let møter: MøterFil
    }
    struct Runde: Decodable {
        let id: String
        let dato: String
        let vekt: Double
        let poeng: [String: Int]
        let teller: Bool?
        let poengtabell: String?
    }
    struct Rad: Decodable { let id: String; let plass: Int?; let total: Double; let kvelder: Int; let playoff: String? }
    struct Sak: Decodable {
        let navn: String
        let regelsett: StablefordTableTests.AnyJSON
        let playoffVinner: String?
        let tavle: [Rad]
    }
    struct PlayoffFil: Decodable {
        let spillere: [Player]
        let saker: [PlayoffSak]
    }
    struct PlayoffSak: Decodable {
        let navn: String
        let andel: Double
        let spillere: [String]
        let hull: [Int]
        let slag: [String: [Int]]
        let forventet: Forventet
        struct Forventet: Decodable { let vinner: String?; let avgjort: Int?; let igjen: [String]?; let neste: Int? }
    }
    struct SkjulFil: Decodable { let saker: [SkjulSak] }
    struct SkjulSak: Decodable {
        let navn: String
        let holeCount: Int
        let holeStart: Int
        let hideLastHoles: Int
        let locked: Bool
        let skjulte: [Int]
        let viser: [String]
        let poeng: [String: Int]
    }
    struct ManuellFil: Decodable { let saker: [ManuellSak] }
    struct ManuellSak: Decodable { let navn: String; let deltakere: [String]; let grupper: [[String]]; let feil: [String] }
    struct MøterFil: Decodable {
        let runder: [Round]
        let forventet: [String: Int]
        let gjentakelser: Gjentakelser
        struct Gjentakelser: Decodable { let grupper: [[String]]; let antall: Int }
    }

    static func rounds(_ fil: Fil) -> [Round] {
        fil.runder.map { r in
            Round(id: r.id, gameType: "stableford", holeCount: 18, holeStart: 0, course: StablefordTableTests.course,
                  hcpAllowance: 1, holeScores: r.poeng.mapValues(StablefordTableTests.scores(for:)),
                  weight: r.vekt, date: r.dato, locked: true, counts: r.teller ?? true, pointsTable: r.poengtabell)
        }
    }

    static func fil() throws -> Fil { try Fixture.load(Fil.self, "tabellregler") }

    // MARK: Tabellen

    @Test func tabellreglene() throws {
        let fil = try Self.fil()
        let rounds = Self.rounds(fil)
        for sak in fil.saker {
            let rules = sak.regelsett.ruleset
            #expect(rules.validate().isEmpty, "\(sak.navn): \(rules.validate())")
            let season = Season(players: fil.spillere, rounds: rounds, ruleset: rules)
            let table = season.standings(playoffWinner: sak.playoffVinner)
            #expect(table.map(\.row.player.id) == sak.tavle.map(\.id), "\(sak.navn): rekkefølge")
            for (got, want) in zip(table, sak.tavle) {
                #expect(got.place == want.plass, "\(sak.navn) \(want.id): plass")
                #expect(got.row.total == want.total, "\(sak.navn) \(want.id): total")
                #expect(got.row.evenings == want.kvelder, "\(sak.navn) \(want.id): kvelder")
                #expect(got.row.qualified == (want.plass != nil), "\(sak.navn) \(want.id): kvalifisert")
                let playoff: String? = got.playoffPending ? "venter" : got.wonPlayoff ? "vant" : nil
                #expect(playoff == want.playoff, "\(sak.navn) \(want.id): playoff")
            }
            // Jakketavla har samme rekkefølge uten playoff-resultat.
            if sak.playoffVinner == nil {
                #expect(season.jacketBoard().map(\.player.id) == sak.tavle.map(\.id), "\(sak.navn): jakketavla")
            }
        }
    }

    /// En kveld som ikke teller, er det samme som vekt 0.
    @Test func kveldSomIkkeTellerErVektNull() throws {
        let fil = try Self.fil()
        let rules = fil.saker[0].regelsett.ruleset
        let notCounting = Self.rounds(fil)
        let weightZero = notCounting.map { r -> Round in
            var r = r
            if !r.counts { r.counts = true; r.weight = 0 }
            return r
        }
        let a = Season(players: fil.spillere, rounds: notCounting, ruleset: rules)
        let b = Season(players: fil.spillere, rounds: weightZero, ruleset: rules)
        #expect(a.jacketBoard() == b.jacketBoard())
        #expect(a.stablefordBoard() == b.stablefordBoard())
        // Også med Golfgutu-regelsettet (stablefordsummen).
        let g1 = Season(players: fil.spillere, rounds: notCounting)
        let g2 = Season(players: fil.spillere, rounds: weightZero)
        #expect(g1.stablefordBoard() == g2.stablefordBoard())
    }

    /// Poengtabellen ganges med rundevekten: vekt 2 og «finale» 2 gir 4.
    @Test func poengtabellOgVekt() throws {
        let fil = try Self.fil()
        var rules = fil.saker[1].regelsett.ruleset
        rules.table.pointsTables["halv"] = .init(multiplier: 0.5)
        var rounds = Self.rounds(fil)
        rounds[3].weight = 2
        rounds[0].pointsTable = "halv"
        let season = Season(players: fil.spillere, rounds: rounds, ruleset: rules)
        #expect(season.effectiveWeight(rounds[3]) == 4)
        #expect(season.effectiveWeight(rounds[0]) == 0.5)
        // Anne: 30 · 0,5 + 40 + 20 + 35 · 4 = 215.
        #expect(season.jacketBoard().first { $0.player.id == "A" }?.total == 215)
        // Ukjent tabell: 1. Kvelden teller ikke: 0, uansett tabell.
        rounds[1].pointsTable = "finnes ikke"
        rounds[4].pointsTable = "finale"
        let s2 = Season(players: fil.spillere, rounds: rounds, ruleset: rules)
        #expect(s2.effectiveWeight(rounds[1]) == 1)
        #expect(s2.effectiveWeight(rounds[4]) == 0)
    }

    /// Snitt med «beste N»: delt på kveldene som teller, ikke på alle spilte.
    @Test func snittMedBesteN() throws {
        let fil = try Self.fil()
        var rules = fil.saker[0].regelsett.ruleset
        rules.table.aggregation = .average
        rules.table.counting = .init(unit: .evening, best: 2)
        let season = Season(players: fil.spillere, rounds: Self.rounds(fil), ruleset: rules)
        let rows = Dictionary(uniqueKeysWithValues: season.jacketBoard().map { ($0.player.id, $0) })
        // Anne: beste to kvelder 40 + 35 = 75 / 2. Bjørn: 36 + 34 = 70 / 2. Dag: 25 + 20 = 45 / 2.
        #expect(rows["A"]?.total == 37.5)
        #expect(rows["B"]?.total == 35)
        #expect(rows["D"]?.total == 22.5)
        // Kvelder er fortsatt de spilte.
        #expect(rows["A"]?.evenings == 4)
    }

    /// Golfgutu-oppsettet: standardverdiene endrer ingenting (paritetssakene står i SeasonTests og GoldenTests).
    @Test func golfgutuHarStandardverdiene() {
        let t = Ruleset.golfgutu.table
        #expect(t.minEvenings == nil)
        #expect(t.aggregation == .sum)
        #expect(t.pointsTables.isEmpty)
        #expect(t.tieRule == .tiebreaks)
        #expect(Ruleset.golfgutu.formats.drawMethod == .standings)
        let r = Round()
        #expect(r.counts)
        #expect(r.pointsTable == nil)
        #expect(r.hideLastHoles == 0)
    }

    // MARK: JSON

    @Test func jsonFramOgTilbake() throws {
        var rules = Ruleset.golfgutu
        rules.table.minEvenings = 3
        rules.table.aggregation = .average
        rules.table.pointsTables = ["finale": .init(multiplier: 2), "trening": .init(multiplier: 0)]
        rules.table.tieRule = .playoff
        rules.formats.drawMethod = .avoidRepeats
        let data = try JSONEncoder().encode(rules)
        let back = try JSONDecoder().decode(Ruleset.self, from: data)
        #expect(back == rules)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let table = try #require(json["table"] as? [String: Any])
        #expect(table["minEvenings"] as? Int == 3)
        #expect(table["aggregation"] as? String == "average")
        #expect(table["tieRule"] as? String == "playoff")
        #expect((table["pointsTables"] as? [String: Any])?["finale"] as? [String: Double] == ["multiplier": 2])
        #expect((json["formats"] as? [String: Any])?["drawMethod"] as? String == "avoidRepeats")
        #expect(Set(rules.changedFields(from: .golfgutu)) == [
            "formats.drawMethod", "table.aggregation", "table.minEvenings", "table.pointsTables", "table.tieRule",
        ])
    }

    /// Standardverdiene skrives ikke, så Golfgutu-JSON-en er byte for byte som før.
    @Test func standardverdieneSkrivesIkke() throws {
        let data = try JSONEncoder().encode(Ruleset.golfgutu)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let table = try #require(json["table"] as? [String: Any])
        for key in ["minEvenings", "aggregation", "pointsTables", "tieRule"] { #expect(table[key] == nil, "\(key)") }
        #expect((json["formats"] as? [String: Any])?["drawMethod"] == nil)
    }

    @Test func rundensNyeFelt() throws {
        let json = #"{"id":"r","counts":false,"pointsTable":"finale","hideLastHoles":3}"#
        let r = try JSONDecoder().decode(Round.self, from: Data(json.utf8))
        #expect(!r.counts)
        #expect(r.pointsTable == "finale")
        #expect(r.hideLastHoles == 3)
        let back = try JSONDecoder().decode(Round.self, from: JSONEncoder().encode(r))
        #expect(back == r)
        let old = try JSONDecoder().decode(Round.self, from: Data(#"{"id":"r"}"#.utf8))
        #expect(old.counts && old.pointsTable == nil && old.hideLastHoles == 0)
    }

    @Test func gyldighetssjekk() {
        var rules = Ruleset.golfgutu
        rules.table.minEvenings = 8
        rules.table.pointsTables = ["finale": .init(multiplier: -1), "": .init(multiplier: 1)]
        let fields = Set(rules.validate().map(\.field))
        #expect(fields.contains("table.minEvenings"))
        #expect(fields.contains("table.pointsTables.finale"))
        #expect(fields.contains("table.pointsTables"))
        rules.table.minEvenings = -1
        #expect(rules.validate().contains { $0.field == "table.minEvenings" })
        rules.table.minEvenings = 0
        rules.table.pointsTables = [:]
        #expect(rules.validate().isEmpty)
    }

    // MARK: Playoff

    @Test func playoff() throws {
        let fil = try Self.fil().playoff
        for sak in fil.saker {
            let round = Round(id: "playoff", gameType: "stableford", holeCount: 18, holeStart: 0,
                              course: StablefordTableTests.course, hcpAllowance: sak.andel)
            let d = Playoff.decide(players: sak.spillere, holes: sak.hull, scores: sak.slag, round: round,
                                   roster: fil.spillere)
            if let vinner = sak.forventet.vinner {
                #expect(d == .won(winner: vinner, position: sak.forventet.avgjort!), "\(sak.navn)")
            } else {
                #expect(d == .pending(remaining: sak.forventet.igjen!, next: sak.forventet.neste), "\(sak.navn)")
            }
        }
    }

    @Test func playoffForslag() {
        #expect(Playoff.suggestedHoles(Round(holeCount: 18)) == [17, 0, 17])
        #expect(Playoff.suggestedHoles(Round(holeCount: 9)) == [8, 0, 8])
    }

    /// Playoff-vinneren som ikke er blant dem på delt førsteplass, endrer ingenting.
    @Test func playoffVinnerUtenforGruppen() throws {
        let fil = try Self.fil()
        let sak = fil.saker[2]
        let season = Season(players: fil.spillere, rounds: Self.rounds(fil), ruleset: sak.regelsett.ruleset)
        let table = season.standings(playoffWinner: "C")
        #expect(table.prefix(2).allSatisfy { $0.place == 1 && $0.playoffPending })
    }

    // MARK: Skjul de siste hullene

    @Test func skjulDeSisteHullene() throws {
        let fil = try Self.fil().skjul
        let players = [Player(id: "A", name: "Anne"), Player(id: "B", name: "Bjørn")]
        for sak in fil.saker {
            let round = Round(id: "r", gameType: "stableford", holeCount: sak.holeCount, holeStart: sak.holeStart,
                              course: StablefordTableTests.course, hcpAllowance: 1,
                              holeScores: ["A": StablefordTableTests.scores(for: 36), "B": StablefordTableTests.scores(for: 36)],
                              locked: sak.locked, hideLastHoles: sak.hideLastHoles)
            #expect(Array(round.hiddenHoleIndices) == sak.skjulte, "\(sak.navn)")
            let view = round.hidingLastHoles(revealedTo: Set(sak.viser))
            #expect(Scoring.roundPoints(view, roster: players) == sak.poeng, "\(sak.navn)")
        }
    }

    // MARK: Trekning

    @Test func manuellTrekning() throws {
        for sak in try Self.fil().manuell.saker {
            #expect(Draw.validate(groups: sak.grupper, participants: sak.deltakere).map(\.code) == sak.feil, "\(sak.navn)")
        }
        #expect(DrawIssue.duplicate("A").message.contains("A"))
    }

    @Test func tidligereMøter() throws {
        let m = try Self.fil().møter
        #expect(Draw.meetings(in: m.runder) == m.forventet)
        #expect(Draw.repeats(m.gjentakelser.grupper, previous: m.forventet) == m.gjentakelser.antall)
    }

    struct TrekningFil: Decodable {
        let spillere: [Player]
        let omganger: Int
        let tabell: [[[String]]]
        let utenGjentakelser: [[[String]]]
        let gjentakelserTabell: Int
        let gjentakelserUten: Int
        let oddetall: Oddetall
        let lag: Lag
        struct Oddetall: Decodable { let spillere: [Player]; let frø: UInt64; let grupper: [[String]] }
        struct Lag: Decodable { let spillere: [String]; let størrelse: Int; let frø: UInt64; let lag: [String: Int] }
    }

    /// En sesong med 8 spillere og 7 omganger: trekningen etter tabellen (alle står likt) gir de samme
    /// parene igjen og igjen; uten gjentakelser gir færre. Gruppene er fasit for TypeScript.
    @Test func utenGjentakelserGirFærre() throws {
        let fil = try Fixture.load(TrekningFil.self, "trekning")
        var prevTable: [String: Int] = [:], prevAvoid: [String: Int] = [:]
        var repTable = 0, repAvoid = 0
        var table: [[[String]]] = [], avoid: [[[String]]] = []
        for k in 0..<fil.omganger {
            let t = Triangle.drawMatches(fil.spillere, round: k, standing: [:])
            let a = Draw.avoidingRepeats(fil.spillere, previous: prevAvoid, seed: UInt64(k + 1))
            repTable += Draw.repeats(t, previous: prevTable)
            repAvoid += Draw.repeats(a, previous: prevAvoid)
            Draw.addMeetings(t, to: &prevTable)
            Draw.addMeetings(a, to: &prevAvoid)
            table.append(t)
            avoid.append(a)
            #expect(a.flatMap { $0 }.sorted() == fil.spillere.map(\.id).sorted(), "omgang \(k): alle én gang")
        }
        #expect(repAvoid < repTable)
        #expect(table == fil.tabell)
        #expect(avoid == fil.utenGjentakelser)
        #expect(repTable == fil.gjentakelserTabell)
        #expect(repAvoid == fil.gjentakelserUten)

        let odd = Draw.avoidingRepeats(fil.oddetall.spillere, previous: [:], seed: fil.oddetall.frø)
        #expect(odd == fil.oddetall.grupper)
        #expect(odd.filter { $0.count == 3 }.count == 1)
        #expect(Draw.validate(groups: odd, participants: fil.oddetall.spillere.map(\.id)).isEmpty)

        let teams = Teams.random(fil.lag.spillere, teamSize: fil.lag.størrelse, seed: fil.lag.frø)
        #expect(teams == fil.lag.lag)
    }

    @Test func gjentakbarMedFrø() {
        let players = (1...6).map { Player(id: "p\($0)", name: "Spiller \($0)") }
        let prev = ["p1|p2": 1, "p3|p4": 2]
        #expect(Draw.avoidingRepeats(players, previous: prev, seed: 7) == Draw.avoidingRepeats(players, previous: prev, seed: 7))
        // Med seks spillere og to kjente par finnes en trekning uten gjentakelser.
        #expect(Draw.repeats(Draw.avoidingRepeats(players, previous: prev, seed: 7), previous: prev) == 0)
        #expect(Draw.avoidingRepeats(Array(players.prefix(1)), previous: [:], seed: 1).isEmpty)
    }

    /// Sesongen trekker etter regelsettets `formats.drawMethod`. Manuelt: ingen trekning.
    @Test func sesongensTrekning() throws {
        let m = try Self.fil().møter
        let players = ["A", "B", "C", "D"].map { Player(id: $0, name: $0) }
        var rules = Ruleset.golfgutu
        let standings = Season(players: players, rounds: m.runder, ruleset: rules)
        #expect(standings.draw(players, round: 0, seed: 1) == standings.drawMatches(players, round: 0))
        rules.formats.drawMethod = .avoidRepeats
        let avoid = Season(players: players, rounds: m.runder, ruleset: rules)
        let groups = try #require(avoid.draw(players, round: 0, seed: 1))
        #expect(Draw.repeats(groups, previous: Draw.meetings(in: m.runder)) == 0)
        rules.formats.drawMethod = .manual
        #expect(Season(players: players, rounds: m.runder, ruleset: rules).draw(players, round: 0, seed: 1) == nil)
    }

    @Test func byttLag() {
        let teams = ["A": 1, "B": 1, "C": 2, "D": 2]
        #expect(Teams.swap(teams, "A", "C") == ["A": 2, "B": 1, "C": 1, "D": 2])
        #expect(Teams.swap(teams, "A", "B") == teams)
        #expect(Teams.swap(teams, "A", "X") == teams)
        let random = Teams.random(["A", "B", "C", "D", "E"], teamSize: 2, seed: 3)
        #expect(random.keys.sorted() == ["A", "B", "C", "D", "E"])
        #expect(Dictionary(grouping: random.values, by: { $0 }).mapValues(\.count).values.sorted() == [1, 2, 2])
    }
}
