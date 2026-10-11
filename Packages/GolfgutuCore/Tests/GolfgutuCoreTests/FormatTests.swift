import Foundation
import Testing
@testable import GolfgutuCore

/// Steg 7: lagform og poengtelling som to akser, Amerikaner og Københavner, skins i tabellen, lag mot
/// lag, flere konkurranser på samme runde og øyeblikksbildet ved start. Tallene: Fixtures/formater.json
/// (regnet for hånd; poengfordelingen etter NGF «Spilleformer» 2023, side 3 og 4).
struct FormatTests {
    struct Fil: Decodable {
        let akser: [Akse]
        let poengspill: [Poengspill]
        let runde: Runde
        let tabell: Tabell
        let lagMotLag: LagMotLag
    }
    struct Akse: Decodable { let id: String; let teamForm: TeamForm; let scoring: ScoringMethod }
    struct Poengspill: Decodable {
        let spill: PointsGameKind
        let monster: String
        let scorer: [String: Int]
        let poeng: [String: Double]
    }
    struct Rad: Decodable { let spillere: [String]; let score: Double; let hull: Int; let plass: Int }
    struct Forventet: Decodable { let id: String; let stottet: Bool; let rader: [Rad] }
    struct SkinsHull: Decodable { let state: String; let winners: [String]; let value: Int }
    struct Runde: Decodable {
        let handicap: [String: Double]
        let scorer: [String: [Int]]
        let konkurranser: [RoundCompetition]
        let forventet: [Forventet]
        let amerikanerHull: [[String: Double]]
        let skinsHull: [SkinsHull]
    }
    struct TabellRunde: Decodable { let id: String; let gameType: String; let date: String }
    struct TabellRad: Decodable { let id: String; let total: Double; let stableford: Int }
    struct Tabell: Decodable {
        let runder: [TabellRunde]
        let navn: [String: String]
        let medFormpoeng: [TabellRad]
        let utenFormpoeng: [TabellRad]
    }
    struct RyderRunde: Decodable { let id: String; let gameType: String; let teams: [String: Int]; let matches: [Match] }
    struct RyderMatch: Decodable {
        let runde: Int
        let matchNo: Int
        let sideA: Int?
        let sideB: Int?
        let state: String
        let utfallA: Double?
        let poengA: Double
        let poengB: Double
    }
    struct RyderRad: Decodable { let side: Int; let poeng: Double; let vunnet: Int; let delt: Int; let tapt: Int }
    struct RyderForventet: Decodable { let matcher: [RyderMatch]; let tabell: [RyderRad] }
    struct Parring: Decodable { let lag: [String: Int]; let sider: [String: Int]; let forventet: [Match] }
    struct LagMotLag: Decodable {
        let sider: [String: Int]
        let runder: [RyderRunde]
        let forventet: RyderForventet
        let parring: Parring
    }

    let fil: Fil

    init() throws {
        fil = try Fixture.load(Fil.self, "formater")
    }

    /// 18 hull, par 4, indeks 1–18.
    static let course = Course(id: "bane", name: "Testbanen", par: 72, courseRating: 72, slopeRating: 113,
                               holes: (0..<18).map { CourseHole(par: 4, si: $0 + 1) })

    func round(id: String = "r", gameType: String = "stableford", locked: Bool = true,
               teams: [String: Int] = [:], matches: [Match] = [], date: String? = nil) -> Round {
        var scores: [String: HoleScores] = [:]
        for (p, list) in fil.runde.scorer {
            scores[p] = Dictionary(uniqueKeysWithValues: list.enumerated().map { ($0.offset, $0.element) })
        }
        return Round(id: id, gameType: gameType, holeCount: 18, holeStart: 0, course: Self.course, hcpAllowance: 1,
                     teams: teams, holeScores: scores, matches: matches, date: date, locked: locked,
                     playingHandicaps: fil.runde.handicap)
    }

    var roster: [Player] {
        ["a", "b", "c", "d"].map { Player(id: $0, name: fil.tabell.navn[$0] ?? $0) }
    }

    // MARK: 1. To akser

    @Test func akseneDekkerHverFormEnTilEn() {
        #expect(fil.akser.map(\.id) == CompetitionForm.catalog.map(\.id))
        for a in fil.akser {
            let form = CompetitionForm.form(id: a.id)
            #expect(form.id == a.id)
            #expect(form.axes == FormAxes(teamForm: a.teamForm, scoring: a.scoring), "\(a.id)")
            #expect(CompetitionForm.form(axes: form.axes)?.id == a.id, "\(a.id): tilbake")
        }
        // Ingen to former har samme akser.
        #expect(Set(CompetitionForm.catalog.map(\.axes)).count == CompetitionForm.catalog.count)
        // Lagstørrelsen på aksen er formens.
        for f in CompetitionForm.catalog { #expect(f.axes.teamForm.size == f.teamSize, "\(f.id)") }
    }

    @Test func akseneSomJSONGarRundt() throws {
        for a in fil.akser {
            let axes = FormAxes(teamForm: a.teamForm, scoring: a.scoring)
            let data = try JSONEncoder().encode(axes)
            #expect(try JSONDecoder().decode(FormAxes.self, from: data) == axes)
        }
    }

    @Test func golfgutuErUendret() throws {
        // De nye formene er ikke med i PWA-katalogen eller Golfgutu-oppsettet.
        #expect(CompetitionForm.all.count == 16)
        #expect(!Ruleset.golfgutu.formats.allowedFormIDs.contains("amerikaner"))
        #expect(Ruleset.golfgutu.formPlay == .standard)
        #expect(!Ruleset.golfgutu.table.formPoints)
        // Regelsettet skriver ingen nye nøkler når formreglene er standard.
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Ruleset.golfgutu)) as! [String: Any]
        #expect(json["formPlay"] == nil)
        #expect((json["table"] as! [String: Any])["formPoints"] == nil)
        // En ukjent id er fortsatt stableford; de nye id-ene finnes.
        #expect(CompetitionForm.form(id: "tull").id == "stableford")
        #expect(CompetitionForm.form(id: "amerikaner").id == "amerikaner")
        #expect(Round(gameType: "Kobenhavner").form.id == "kobenhavner")
    }

    // MARK: 2. Amerikaner og Københavner

    @Test func poengfordelingEtterNGF() {
        let rules = FormPlayRules.standard
        for c in fil.poengspill {
            let game = rules.pointsGame(c.spill)
            #expect(PointsGame.pattern(c.scorer) == c.monster, "\(c.spill) \(c.monster)")
            #expect(PointsGame.holePoints(c.scorer, rules: game) == c.poeng, "\(c.spill) \(c.monster)")
        }
        // Summen er alltid 12 og 6 per hull.
        for (pattern, points) in rules.pointsGame(.amerikaner).points { #expect(points.reduce(0, +) == 12, "\(pattern)") }
        for (pattern, points) in rules.pointsGame(.kobenhavner).points { #expect(points.reduce(0, +) == 6, "\(pattern)") }
    }

    @Test func poengspillTrengerRiktigAntall() {
        let game = FormPlayRules.standard.pointsGame(.amerikaner)
        #expect(PointsGame.holePoints(["a": 3, "b": 4, "c": 5], rules: game) == nil)
    }

    @Test func poengtabellenLesesFraRegelsettet() {
        var game = FormPlayRules.standard.pointsGame(.kobenhavner)
        game.points["1-1-1"] = [5, 1, 0]
        #expect(PointsGame.holePoints(["a": 3, "b": 4, "c": 5], rules: game) == ["a": 5, "b": 1, "c": 0])
    }

    @Test func amerikanerHullForHull() {
        let r = round(gameType: "amerikaner")
        let result = PointsGame.evaluate(.amerikaner, players: ["a", "b", "c", "d"], round: r, roster: [], rules: .golfgutu)
        #expect(result.holes.map(\.points) == fil.runde.amerikanerHull)
        #expect(result.totals == ["a": 53, "b": 55, "c": 47, "d": 61])
        #expect(result.isFinished)
    }

    @Test func amerikanerUferdigHull() {
        var r = round(gameType: "amerikaner", locked: false)
        r.holeScores["c"]?[5] = nil
        let result = PointsGame.evaluate(.amerikaner, players: ["a", "b", "c", "d"], round: r, roster: [], rules: .golfgutu)
        #expect(result.holes[5].state == .pending)
        #expect(result.holes[5].points.isEmpty)
        #expect(!result.isFinished)
        // Hull 6 telte 4 for a, c og d; nå mangler det.
        #expect(result.totals["a"] == 49)
        r.locked = true
        let locked = PointsGame.evaluate(.amerikaner, players: ["a", "b", "c", "d"], round: r, roster: [], rules: .golfgutu)
        #expect(locked.holes[5].state == .void)
        #expect(locked.isFinished)
    }

    @Test func poengspillBrutto() {
        var rules = Ruleset.golfgutu
        rules.formPlay.pointsGames["amerikaner"]?.handicap = .gross
        let r = round(gameType: "amerikaner")
        let result = PointsGame.evaluate(.amerikaner, players: ["a", "b", "c", "d"], round: r, roster: [], rules: rules)
        // Hull 1 brutto: a 3, b 5, c 4, d 5 → 8, 0, 4, 0 (1-1-2).
        #expect(result.holes[0].points == ["a": 8, "b": 0, "c": 4, "d": 0])
    }

    // MARK: 3 og 5. Flere konkurranser på samme runde (med skins)

    @Test func flereKonkurranserPaSammeRunde() {
        let results = RoundCompetitions.evaluate(round(), roster: [], competitions: fil.runde.konkurranser, rules: .golfgutu)
        #expect(results.map(\.id) == fil.runde.forventet.map(\.id))
        for (got, want) in zip(results, fil.runde.forventet) {
            #expect(got.supported == want.stottet, "\(want.id)")
            #expect(got.rows.map(\.players) == want.rader.map(\.spillere), "\(want.id): rekkefølge")
            #expect(got.rows.map(\.score) == want.rader.map(\.score), "\(want.id): score")
            #expect(got.rows.map(\.holes) == want.rader.map(\.hull), "\(want.id): hull")
            #expect(got.rows.map(\.rank) == want.rader.map(\.plass), "\(want.id): plass")
        }
    }

    @Test func skinsGjenbrukerRundespillet() {
        let setup = GameSetup(settings: .skins(Ruleset.golfgutu.formPlay.skins), players: ["a", "b", "c", "d"])
        let game = Games.evaluate(setup, round: round(), roster: [], rules: .golfgutu)
        #expect(game.holes.map(\.state.rawValue) == fil.runde.skinsHull.map(\.state))
        #expect(game.holes.map(\.winners) == fil.runde.skinsHull.map(\.winners))
        #expect(game.holes.map(\.value) == fil.runde.skinsHull.map(\.value))
        #expect(game.scores == ["a": 5, "b": 3, "c": 4, "d": 3])
        // Standard: carry-over som rundespillet, og det som står igjen faller bort.
        #expect(FormPlayRules.standard.skins.carryOver == SkinsRules.standard.carryOver)
        #expect(FormPlayRules.standard.skins.leftover == SkinsRules.standard.leftover)
    }

    @Test func skinsUtenCarryOver() {
        var rules = Ruleset.golfgutu
        rules.formPlay.skins.carryOver = false
        let points = FormPlay.tablePoints(round(gameType: "skins"), roster: [], rules: rules)
        // Uten carry-over: a h1 og h11, b h2 og h13, c h7, d h3 og h15.
        #expect(points == ["a": 2, "b": 2, "c": 1, "d": 2])
    }

    @Test func skinsITabellen() {
        let rules = tableRules(formPoints: true)
        #expect(FormPlay.tablePoints(round(gameType: "skins"), roster: [], rules: rules) == ["a": 5, "b": 3, "c": 4, "d": 3])
        let season = Season(players: roster, rounds: tableRounds(), ruleset: rules)
        let board = season.jacketBoard()
        #expect(board.map(\.player.id) == fil.tabell.medFormpoeng.map(\.id))
        #expect(board.map(\.total) == fil.tabell.medFormpoeng.map(\.total))
        #expect(board.map(\.stableford) == fil.tabell.medFormpoeng.map(\.stableford))

        let plain = Season(players: roster, rounds: tableRounds(), ruleset: tableRules(formPoints: false)).jacketBoard()
        #expect(plain.map(\.player.id) == fil.tabell.utenFormpoeng.map(\.id))
        #expect(plain.map(\.total) == fil.tabell.utenFormpoeng.map(\.total))
    }

    @Test func skinspoengPerSkin() {
        var rules = tableRules(formPoints: true)
        rules.formPlay.skinPoints = 0.5
        #expect(FormPlay.tablePoints(round(gameType: "skins"), roster: [], rules: rules) == ["a": 2.5, "b": 1.5, "c": 2, "d": 1.5])
    }

    @Test func formpoengKreverRundepoengITabellen() {
        var rules = Ruleset.golfgutu
        rules.table.formPoints = true
        #expect(rules.validate().contains { $0.field == "table.formPoints" })
        #expect(tableRules(formPoints: true).validate().isEmpty)
    }

    @Test func formreglerSomJSON() throws {
        var rules = tableRules(formPoints: true)
        rules.formPlay.skinPoints = 2
        rules.formPlay.pointsGames["kobenhavner"]?.points["1-1-1"] = [5, 1, 0]
        let data = try JSONEncoder().encode(rules)
        let back = try JSONDecoder().decode(Ruleset.self, from: data)
        #expect(back == rules)
        // Felt som mangler, får standardverdien.
        let partial = try JSONDecoder().decode(Ruleset.self, from: Data(#"{"version":2,"formPlay":{"skinPoints":3}}"#.utf8))
        #expect(partial.formPlay.skinPoints == 3)
        #expect(partial.formPlay.pointsGames == FormPlayRules.standard.pointsGames)
        #expect(partial.formPlay.teamMatch == FormPlayRules.standard.teamMatch)
    }

    func tableRules(formPoints: Bool) -> Ruleset {
        var r = Ruleset.golfgutu
        r.table.pointsSource = .stableford
        r.table.counting = Ruleset.Counting(unit: .round, best: nil)
        r.table.tiebreaks = [.stableford]
        r.table.formPoints = formPoints
        return r
    }

    func tableRounds() -> [Round] {
        fil.tabell.runder.map { round(id: $0.id, gameType: $0.gameType, date: $0.date) }
    }

    // MARK: 4. Lag mot lag

    @Test func lagMotLag() {
        let l = fil.lagMotLag
        let rounds = l.runder.map { round(id: $0.id, gameType: $0.gameType, teams: $0.teams, matches: $0.matches) }
        let result = RyderCup.evaluate(rounds: rounds, sides: l.sider, roster: [], rules: .golfgutu)
        #expect(result.matches.count == l.forventet.matcher.count)
        for (got, want) in zip(result.matches, l.forventet.matcher) {
            #expect(got.roundIndex == want.runde)
            #expect(got.matchNo == want.matchNo)
            #expect(got.sideA == want.sideA)
            #expect(got.sideB == want.sideB)
            #expect(got.state.rawValue == want.state, "match \(want.runde)/\(want.matchNo)")
            #expect(got.outcomeA == want.utfallA)
            #expect(got.pointsA == want.poengA)
            #expect(got.pointsB == want.poengB)
        }
        #expect(result.table.map(\.side) == l.forventet.tabell.map(\.side))
        #expect(result.table.map(\.points) == l.forventet.tabell.map(\.poeng))
        #expect(result.table.map(\.won) == l.forventet.tabell.map(\.vunnet))
        #expect(result.table.map(\.halved) == l.forventet.tabell.map(\.delt))
        #expect(result.table.map(\.lost) == l.forventet.tabell.map(\.tapt))
    }

    @Test func lagMotLagPoengFraRegelsettet() {
        let l = fil.lagMotLag
        var rules = Ruleset.golfgutu
        rules.formPlay.teamMatch = Ruleset.MatchPoints(win: 2, draw: 1, loss: 0)
        let rounds = l.runder.map { round(id: $0.id, gameType: $0.gameType, teams: $0.teams, matches: $0.matches) }
        let result = RyderCup.evaluate(rounds: rounds, sides: l.sider, roster: [], rules: rules)
        #expect(result.table.map(\.points) == [5, 1])
    }

    @Test func lagMotLagParring() {
        let p = fil.lagMotLag.parring
        #expect(RyderCup.pairings(teams: p.lag, sides: p.sider) == p.forventet)
        #expect(RyderCup.singles(["a", "b"], ["c", "d"]) == [Match(matchNo: 1, playerA: "a", playerB: "c"),
                                                             Match(matchNo: 2, playerA: "b", playerB: "d")])
    }

    // MARK: 6. Øyeblikksbildet ved start

    @Test func oyeblikksbildetHolderResultatet() throws {
        // Troppen med indeks; handicapet regnes fra banen ved start og fryses.
        let people = [Player(id: "a", name: "Anne", handicap: 2.4), Player(id: "b", name: "Bjørn", handicap: 17.8),
                      Player(id: "c", name: "Cecilie", handicap: 9.1), Player(id: "d", name: "Dag", handicap: 25)]
        var live = round(gameType: "stableford", locked: true)
        live.playingHandicaps = [:]
        live.hcpAllowance = 0.95
        let rules = Ruleset.golfgutu
        let frozen = FrozenRound.start(live, roster: people, ruleset: rules)
        for p in people {
            #expect(frozen.playingHandicaps[p.id] == Handicap.effective(for: p, in: live, roster: people, rules: rules))
        }
        #expect(frozen.holes == live.courseHoles())

        let comps = fil.runde.konkurranser
        let before = RoundCompetitions.evaluate(frozen, scores: live.holeScores, competitions: comps)
        let liveBefore = RoundCompetitions.evaluate(live, roster: people, competitions: comps, rules: rules)
        #expect(before == liveBefore)

        // Alt endres etter start: regelsett, handicap og banen.
        var changed = rules
        changed.scoring.netParPoints = 3
        changed.formPlay.pointsGames["amerikaner"]?.points["1-3"] = [12, 0, 0, 0]
        changed.formPlay.skins.carryOver = false
        let newPeople = people.map { var p = $0; p.handicap = 0; return p }
        var newRound = live
        newRound.course?.holes?[0].par = 5
        let liveAfter = RoundCompetitions.evaluate(newRound, roster: newPeople, competitions: comps, rules: changed)
        #expect(liveAfter != liveBefore)

        // Øyeblikksbildet gir samme svar, også etter en tur gjennom JSON.
        let stored = try JSONDecoder().decode(FrozenRound.self, from: JSONEncoder().encode(frozen))
        #expect(stored == frozen)
        #expect(RoundCompetitions.evaluate(stored, scores: live.holeScores, competitions: comps) == before)
    }

    @Test func oyeblikksbildeAv9Hull() {
        var r = round()
        r.holeCount = 9
        r.holeStart = 9
        let frozen = FrozenRound.start(r, roster: [], ruleset: .golfgutu)
        #expect(frozen.holes == r.courseHoles())
        #expect(frozen.round(scores: [:]).courseHoles() == r.courseHoles())
    }
}
