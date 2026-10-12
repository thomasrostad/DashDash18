import Foundation
import GolfgutuCore
import Testing
@testable import DashDash18

// Steg 7 (sql/048): flere konkurranser på samme runde, øyeblikksbildet ved start og lag mot lag.

private typealias F = ForingFixture

private func keys(_ value: some Encodable) throws -> Set<String> {
    let object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
    return Set(object.keys)
}

private func object(_ value: some Encodable) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
}

private func competition(_ n: Int, name: String, main: Bool = false, sort: Int, config: CompetitionConfig?) -> RoundCompetitionRow {
    RoundCompetitionRow(id: F.id(n), roundID: F.roundID, name: name, isMain: main, config: config, sortOrder: sort)
}

private func draft(players: [Int] = [1, 2, 3, 4], formID: String = "stableford") -> RoundDraft {
    var d = RoundDraft.new(eventID: F.eventID, roundNo: 1, teeTime: nil, participants: players.map(F.id),
                           source: .signups, rules: .golfgutu)
    d.formID = formID
    return d
}

// MARK: - Oppsettet (config)

struct KonkurranseConfigTests {
    @Test func noklerSomI048() throws {
        // Hver oppskrift gir bare nøkler 048 godtar.
        var d = draft()
        d.bays = BayPlan(seats: [BaySeat(memberID: F.id(1), bay: 1, isMarker: true), BaySeat(memberID: F.id(2), bay: 1, isMarker: false),
                                 BaySeat(memberID: F.id(3), bay: 2, isMarker: true), BaySeat(memberID: F.id(4), bay: 2, isMarker: false)])
        for recipe in CompetitionRecipe.allCases {
            let config = recipe.make(for: d).config
            #expect(try keys(config).isSubset(of: CompetitionConfig.allowedKeys), "\(recipe)")
        }
        #expect(try keys(CompetitionRecipe.skins.make(for: d).config) == ["form"])
        #expect(try keys(CompetitionRecipe.frontNine.make(for: d).config) == ["form", "holes"])
        #expect(try keys(CompetitionRecipe.bestBallPairs.make(for: d).config) == ["teamForm", "scoring", "entrants"])
        #expect(CompetitionConfig.allowedKeys == ["form", "teamForm", "scoring", "entrants", "holes", "allowance"])
    }

    @Test func jsonForBestballOgHull() throws {
        let config = CompetitionConfig(teamForm: .pairs(.fourball), scoring: .stableford(net: true),
                                       entrants: [["a", "b"]], holes: HoleRange(first: 9, last: 17), allowance: 0.9)
        let json = try object(config)
        #expect(json["teamForm"] as? [String: String] == ["type": "pairs", "pairs": "fourball"])
        let scoring = try #require(json["scoring"] as? [String: Any])
        #expect(scoring["type"] as? String == "stableford")
        #expect(scoring["net"] as? Bool == true)
        #expect(json["holes"] as? [String: Int] == ["first": 9, "last": 17])
        #expect(json["entrants"] as? [[String]] == [["a", "b"]])
        #expect(json["allowance"] as? Double == 0.9)
        let back = try JSONDecoder().decode(CompetitionConfig.self, from: JSONEncoder().encode(config))
        #expect(back == config)
        #expect(back.axes == FormAxes(teamForm: .pairs(.fourball), scoring: .stableford(net: true)))
    }

    @Test func formGirAksene() {
        #expect(CompetitionConfig(form: "skins").axes == FormAxes(teamForm: .individual, scoring: .skins))
        #expect(CompetitionConfig(form: "amerikaner").axes.scoring == .pointsGame(.amerikaner))
    }

    @Test func radenLesesOgUkjentVersjonErIkkeStottet() throws {
        let json = """
        [{"id": "\(F.id(10).uuidString)", "round_id": "\(F.roundID.uuidString)", "name": "Skins",
          "is_main": false, "format_version": 1, "config": {"form": "skins"}, "sort_order": 2},
         {"id": "\(F.id(11).uuidString)", "round_id": "\(F.roundID.uuidString)", "name": "Ny",
          "is_main": false, "format_version": 2, "config": {"form": "skins"}, "sort_order": 3}]
        """
        let rows = try JSONDecoder().decode([RoundCompetitionRow].self, from: Data(json.utf8))
        #expect(rows[0].config == CompetitionConfig(form: "skins"))
        #expect(rows[0].sortOrder == 2)
        #expect(rows[1].config == nil)
    }

    @Test func skrivingenTilRPCen() throws {
        let write = CompetitionWrite(id: nil, name: "Skins", isMain: false, config: CompetitionConfig(form: "skins"), sortOrder: 1)
        #expect(try keys(write) == ["name", "is_main", "format_version", "config", "sort_order"])
        let withID = CompetitionWrite(id: F.id(5), name: "Stableford", isMain: true, config: CompetitionConfig(form: "stableford"), sortOrder: 0)
        let json = try object(withID)
        #expect(json["id"] as? String == F.id(5).uuidString)
        #expect(json["format_version"] as? Int == 1)
        #expect(json["config"] as? [String: String] == ["form": "stableford"])
    }

    @Test func listaTilRundenMedHovedForst() throws {
        var d = draft()
        #expect(CompetitionSetup.writes(d) == nil)  // ingenting nytt og ingen rader fra før
        d.hasSavedCompetitions = true
        #expect(CompetitionSetup.writes(d) == [])  // rader fra før slettes
        d.mainCompetitionID = F.id(20)
        d.competitions = [
            RoundCompetitionDraft(rowID: F.id(21), name: "  Skins ", config: CompetitionConfig(form: "skins",
                entrants: [[F.id(1).uuidString, F.id(9).uuidString]])),
            RoundCompetitionDraft(name: "Første ni", config: CompetitionConfig(form: "stableford", holes: HoleRange(first: 0, last: 8))),
        ]
        let writes = try #require(CompetitionSetup.writes(d))
        #expect(writes.map(\.isMain) == [true, false, false])
        #expect(writes[0].id == F.id(20))
        #expect(writes[0].config == CompetitionConfig(form: "stableford"))
        #expect(writes[0].name == CompetitionForm.form(id: "stableford").name)
        #expect(writes[1].id == F.id(21))
        #expect(writes[1].name == "Skins")
        // Nr. 9 er ikke med i runden.
        #expect(writes[1].config.entrants == [[F.id(1).uuidString]])
        #expect(writes.map(\.sortOrder) == [0, 1, 2])
        #expect(writes[2].id == nil)
    }

    @Test func siste9BareMed18Hull() {
        var d = draft()
        d.holeCount = 9
        #expect(!CompetitionRecipe.backNine.isAvailable(holeCount: 9))
        #expect(CompetitionHoles.choices(holeCount: 9) == [.all])
        d.competitions = [CompetitionRecipe.backNine.make(for: draft())]
        #expect(CompetitionSetup.problem(d) != nil)
        #expect(CompetitionSetup.writes(d)?.last?.config.holes == nil)
    }

    @Test func bestballParFraBaasene() {
        var d = draft(players: [1, 2, 3, 4, 5])
        d.bays = BayPlan(seats: [1, 2, 3].map { BaySeat(memberID: F.id($0), bay: 1, isMarker: $0 == 1) }
                         + [4, 5].map { BaySeat(memberID: F.id($0), bay: 2, isMarker: $0 == 4) })
        let pairs = CompetitionSetup.suggestedPairs(d)
        #expect(pairs == [[F.id(1), F.id(2)], [F.id(3)], [F.id(4), F.id(5)]].map { $0.map(\.uuidString) })
        // Lagene står foran båsene når de er par.
        d.teams = [F.id(1): 1, F.id(4): 1, F.id(2): 2, F.id(3): 2]
        #expect(CompetitionSetup.suggestedPairs(d) == [[F.id(1), F.id(4)].map(\.uuidString).sorted(),
                                                       [F.id(2), F.id(3)].map(\.uuidString).sorted()])
    }

    @Test func kladdenFraRadene() {
        let rows = [competition(30, name: "Stableford", main: true, sort: 0, config: CompetitionConfig(form: "stableford")),
                    competition(31, name: "Skins", sort: 1, config: CompetitionConfig(form: "skins")),
                    competition(32, name: "Ukjent", sort: 2, config: nil)]
        let d = RoundDraft.saved(F.round(status: .draft), players: [], matches: [], participants: [],
                                 source: .saved, competitions: rows)
        #expect(d.mainCompetitionID == F.id(30))
        #expect(d.hasSavedCompetitions)
        #expect(d.competitions.map(\.name) == ["Skins"])
        #expect(d.competitions.first?.rowID == F.id(31))
    }
}

// MARK: - Øyeblikksbildet

struct OyeblikksbildeTests {
    @Test func lesesFraRunden() throws {
        let json = """
        {"rules_snapshot": {"version": 2, "evenings": 5},
         "holes_snapshot": {"holes": [{"hole": 1, "par": null, "cardIndex": 3, "meters": null, "strokeIndex": 2},
                                       {"hole": 2, "par": 3, "cardIndex": 1, "meters": 150, "strokeIndex": 1}],
                            "from": null, "course_id": null, "tee_id": null, "first_hole": 1},
         "snapshot_source": "backfill"}
        """
        let freeze = try JSONDecoder().decode(RoundFreeze.self, from: Data(json.utf8))
        #expect(freeze.rules?.evenings == 5)
        #expect(freeze.holes?.count == 2)
        #expect(freeze.isReconstructed)
        let holes = try #require(RoundCompetitionBoard.snapshotHoles(freeze.holes, count: 2))
        #expect(holes[0].par == Course.defaultPar[0])  // par mangler: standardbanen
        #expect(holes[0].cardIndex == 3)
        #expect(holes[1].par == 3)
        #expect(holes[1].meters == 150)
        #expect(RoundCompetitionBoard.snapshotHoles(freeze.holes, count: 18) == nil)  // feil antall
    }

    @Test func tomtEllerOdelagtGirIngenting() throws {
        let freeze = try JSONDecoder().decode(RoundFreeze.self, from: Data(#"{"rules_snapshot": null, "holes_snapshot": 7, "snapshot_source": null}"#.utf8))
        #expect(freeze.rules == nil && freeze.holes == nil && freeze.source == nil)
    }

    @Test func frossenRundeBrukerOyeblikksbildet() {
        var s = F.snapshot([F.P(n: 1, name: "Anders", playing: 5), F.P(n: 2, name: "Bjørn", handicap: 0)])
        var rules = Ruleset.golfgutu
        rules.scoring.netParPoints = 3
        s.freeze = RoundFreeze(rules: rules,
                               holes: (0..<18).map { RoundFreeze.Hole(hole: $0 + 1, par: 3, cardIndex: 18 - $0, meters: nil, strokeIndex: nil) },
                               source: "start")
        let frozen = RoundCompetitionBoard.frozenRound(RoundGame(s))
        #expect(frozen.ruleset.scoring.netParPoints == 3)
        #expect(frozen.holes.allSatisfy { $0.par == 3 })
        #expect(frozen.holes.first?.cardIndex == 18)
        #expect(frozen.playingHandicaps[F.id(1).uuidString] == 5)
        #expect(frozen.gameType == "stableford")
    }

    @Test func utenOyeblikksbildeBrukesDagensData() {
        let s = F.snapshot([F.P(n: 1, name: "Anders", playing: 5)])
        let game = RoundGame(s)
        let frozen = RoundCompetitionBoard.frozenRound(game)
        #expect(frozen.holes == game.holes)
        #expect(frozen.ruleset == s.rules)
    }
}

// MARK: - Resultatene

struct KonkurranseResultatTests {
    /// To spillere med 0 i handicap. Anders slår 4 på alle hull, Bjørn 5 på de ni første og 3 på resten.
    private func snapshot(par: Int? = nil) -> RoundSnapshot {
        var scores: [(Int, Int, Int)] = []
        for h in 0..<18 {
            scores.append((1, h, 4))
            scores.append((2, h, h < 9 ? 5 : 3))
        }
        var s = F.snapshot([F.P(n: 1, name: "Anders", playing: 0), F.P(n: 2, name: "Bjørn", playing: 0)],
                           round: F.round(status: .locked), scores: scores)
        if let par {
            s.freeze = RoundFreeze(rules: .golfgutu,
                                   holes: (0..<18).map { RoundFreeze.Hole(par: par, cardIndex: $0 + 1, strokeIndex: $0 + 1) },
                                   source: "start")
        }
        s.competitions = [
            competition(40, name: "Siste ni", sort: 2, config: CompetitionConfig(form: "stableford", holes: HoleRange(first: 9, last: 17))),
            competition(41, name: "Stableford", main: true, sort: 0, config: CompetitionConfig(form: "stableford")),
            competition(42, name: "Foursome", sort: 3, config: CompetitionConfig(form: "foursome")),
            competition(43, name: "Første ni", sort: 1, config: CompetitionConfig(form: "stableford", holes: HoleRange(first: 0, last: 8))),
        ]
        return s
    }

    @Test func hverKonkurranseMedStilling() {
        let boards = RoundCompetitionBoard.boards(RoundGame(snapshot(par: 4)))
        #expect(boards.map(\.name) == ["Stableford", "Første ni", "Siste ni", "Foursome"])
        // Par 4 overalt: Anders 2 p per hull = 36. Bjørn 9 · 1 + 9 · 3 = 36.
        #expect(boards[0].lines.map(\.score) == ["36 p", "36 p"])
        #expect(boards[0].lines.map(\.rank) == [1, 1])
        #expect(boards[1].lines.first?.names == "Anders")
        #expect(boards[1].lines.first?.score == "18 p")
        #expect(boards[2].lines.first?.names == "Bjørn")
        #expect(boards[2].lines.first?.score == "27 p")
        #expect(boards[2].detail == CompetitionForm.form(id: "stableford").name + " · hull 10–18")
        #expect(!boards[3].supported)
        #expect(boards[3].lines.isEmpty)
    }

    @Test func oyeblikksbildetStyrerPoengene() {
        // Par 3 i øyeblikksbildet: Anders 1 p per hull = 18, uansett banen i dag (par 4/5/3).
        let boards = RoundCompetitionBoard.boards(RoundGame(snapshot(par: 3)))
        let anders = boards[0].lines.first { $0.names == "Anders" }
        #expect(anders?.score == "18 p")
    }

    @Test func utenRaderIngenSeksjon() {
        var s = snapshot(par: 4)
        s.competitions = []
        #expect(RoundCompetitionBoard.boards(RoundGame(s)).isEmpty)
    }

    @Test func amerikanerGrupperFraBaasene() {
        var s = F.snapshot(F.markorPlayers(), round: F.round(status: .locked),
                           scores: (1...8).flatMap { p in (0..<18).map { (p, $0, p <= 4 ? 3 + p % 2 : 4) } })
        s.competitions = [competition(50, name: "Amerikaner", sort: 1, config: CompetitionConfig(form: "amerikaner"))]
        let comp = RoundCompetitionBoard.competition(for: s.competitions[0], game: RoundGame(s))
        #expect(comp?.entrants?.count == 2)
        #expect(comp?.entrants?.allSatisfy { $0.count == 4 } == true)
        let board = RoundCompetitionBoard.boards(RoundGame(s))[0]
        #expect(board.supported)
        #expect(board.lines.count == 8)
    }
}

// MARK: - Lag mot lag

struct LagMotLagTests {
    @Test func sideneMaaGaaOpp() {
        let ids = [1, 2, 3, 4].map(F.id)
        #expect(TeamVsTeam.problem(sides: [ids[0]: 1, ids[1]: 2], teams: [:], participants: ids) == "Alle må ha en side.")
        #expect(TeamVsTeam.problem(sides: Dictionary(uniqueKeysWithValues: ids.map { ($0, 1) }), teams: [:], participants: ids)
                == "Begge sidene må ha spillere.")
        let teams = [ids[0]: 1, ids[1]: 1, ids[2]: 2, ids[3]: 2]
        #expect(TeamVsTeam.problem(sides: [ids[0]: 1, ids[1]: 2, ids[2]: 2, ids[3]: 1], teams: teams, participants: ids)
                == "Spillerne på samme lag må være på samme side.")
        #expect(TeamVsTeam.problem(sides: [ids[0]: 1, ids[1]: 1, ids[2]: 2, ids[3]: 2], teams: teams, participants: ids) == nil)
    }

    @Test func forslagOgMatcherSideMotSide() {
        let ids = [1, 2, 3, 4].map(F.id)
        let teams = [ids[0]: 1, ids[1]: 1, ids[2]: 2, ids[3]: 2]
        let sides = TeamVsTeam.suggested(participants: ids, teams: teams)
        #expect(sides == [ids[0]: 1, ids[1]: 1, ids[2]: 2, ids[3]: 2])
        #expect(TeamVsTeam.matches(participants: ids, teams: teams, sides: sides, isTeamForm: true) == [.teams(1, 2)])
        let single = TeamVsTeam.suggested(participants: ids, teams: [:])
        #expect(single == [ids[0]: 1, ids[1]: 2, ids[2]: 1, ids[3]: 2])
        #expect(TeamVsTeam.matches(participants: ids, teams: [:], sides: single, isTeamForm: false)
                == [.players(ids[0], ids[1]), .players(ids[2], ids[3])])
    }

    @Test func kladdenMedSider() {
        var d = draft(formID: "fourball")
        d.teams = [F.id(1): 1, F.id(2): 1, F.id(3): 2, F.id(4): 2]
        d.setTeamVsTeam(true, roster: [])
        #expect(d.isTeamVsTeam)
        #expect(d.matches == [.teams(1, 2)])
        // Flytter laget når én spiller flyttes.
        d.setSide(2, for: F.id(1), roster: [])
        #expect(d.sides[F.id(2)] == 2)
        let issues = RoundSetupCheck.issues(d, course: nil, rules: .golfgutu, roster: [], forStart: true)
        #expect(issues.contains(.sides("Begge sidene må ha spillere.")))
        d.setTeamVsTeam(false, roster: [])
        #expect(d.sides.isEmpty)
    }

    @Test func sidenSendesMedNokkel() throws {
        var d = draft()
        d.sides = [F.id(1): 1, F.id(2): 2]
        let roster = [1, 2].map { n in
            ClubMemberRow(id: F.id(n), clubID: F.club, userID: UUID(), displayName: "S\(n)", handicapIndex: 10, seedGroup: nil,
                          isOrganizer: false, isTreasurer: false, status: .active, avatarPath: nil)
        }
        d.participants = roster.map(\.id)
        let with = RoundSetupParams.make(roundID: F.roundID, draft: d, roster: roster, course: nil, rules: .golfgutu,
                                         withPlayingHandicap: false, includeSide: true)
        let first = try object(with.players[0])
        #expect(first["side"] as? Int == 1)
        let without = RoundSetupParams.make(roundID: F.roundID, draft: d, roster: roster, course: nil, rules: .golfgutu,
                                            withPlayingHandicap: false, includeSide: false)
        #expect(try object(without.players[0])["side"] == nil)
        // Uten lag mot lag sendes null (siden tømmes).
        d.sides = [:]
        let cleared = RoundSetupParams.make(roundID: F.roundID, draft: d, roster: roster, course: nil, rules: .golfgutu,
                                            withPlayingHandicap: false, includeSide: true)
        let json = try object(cleared.players[0])
        #expect(json.keys.contains("side"))
        #expect(json["side"] is NSNull)
    }

    @Test func lagpoengFraMatchene() {
        // Anders (side 1) slår 3 på hull 1, Bjørn (side 2) 4; resten likt. Cato (1) og Dag (2) likt overalt.
        var scores: [(Int, Int, Int)] = []
        for h in 0..<18 {
            scores.append((1, h, h == 0 ? 3 : 4))
            scores.append((2, h, 4))
            scores.append((3, h, 4))
            scores.append((4, h, 4))
        }
        var s = F.snapshot([1, 2, 3, 4].map { F.P(n: $0, name: "S\($0)", playing: 0) }, round: F.round(status: .locked),
                           scores: scores)
        for i in s.players.indices { s.players[i].side = [1, 2, 1, 2][i] }
        s.matches = [RoundMatchRow(roundID: F.roundID, matchNo: 1, playerA: F.id(1), playerB: F.id(2), playerC: nil,
                                   teamA: nil, teamB: nil, result: nil),
                     RoundMatchRow(roundID: F.roundID, matchNo: 2, playerA: F.id(3), playerB: F.id(4), playerC: nil,
                                   teamA: nil, teamB: nil, result: nil)]
        let result = TeamVsTeam.result(RoundGame(s))
        let score = TeamVsTeam.score(result?.table ?? [RyderCup.Row]())
        #expect(score.one == 1.5)
        #expect(score.two == 0.5)
        #expect(TeamVsTeam.pointsText(1.5) == "1½")
        #expect(TeamVsTeam.pointsText(0.5) == "½")
        #expect(TeamVsTeam.table([RoundGame(s), RoundGame(s)])?.first == TeamVsTeam.Row(side: 1, points: 3, won: 2, halved: 2, lost: 0))
        // Uten sider: ingen lagkonkurranse.
        for i in s.players.indices { s.players[i].side = nil }
        #expect(TeamVsTeam.result(RoundGame(s)) == nil)
    }
}

// MARK: - Samme som sist og malene

struct FormaterGjenbrukTests {
    @Test func sammeSomSistKopiererKonkurranserOgSider() throws {
        let json = """
        {"round_id": "\(F.id(1).uuidString)", "event_date": "2026-10-08", "round_no": 2, "hole_count": 18,
         "format": "stableford",
         "players": [{"member_id": "\(F.id(1).uuidString)", "bay_no": 1, "is_marker": true, "team_no": null, "side": 1},
                     {"member_id": "\(F.id(2).uuidString)", "bay_no": 1, "is_marker": false, "team_no": null, "side": 2}],
         "matches": [],
         "competitions": [{"name": "Stableford", "is_main": true, "format_version": 1, "config": {"form": "stableford"}, "sort_order": 0},
                          {"name": "Skins", "is_main": false, "format_version": 1, "config": {"form": "skins"}, "sort_order": 1}]}
        """
        let previous = try JSONDecoder().decode(PreviousRoundSetup.self, from: Data(json.utf8))
        #expect(previous.setup.competitions.count == 2)
        let roster = [1, 2].map { n in
            ClubMemberRow(id: F.id(n), clubID: F.club, userID: UUID(), displayName: "S\(n)", handicapIndex: 10, seedGroup: nil,
                          isOrganizer: false, isTreasurer: false, status: .active, avatarPath: nil)
        }
        var d = draft(players: [1, 2])
        d.mainCompetitionID = F.id(77)
        previous.setup.apply(to: &d, courses: [], rules: .golfgutu, roster: roster)
        #expect(d.competitions.map(\.name) == ["Skins"])
        #expect(d.competitions.first?.rowID == nil)  // ny rad
        #expect(d.mainCompetitionID == F.id(77))  // runden beholder sin hovedrad
        previous.applyPlayers(to: &d, roster: roster)
        #expect(d.sides == [F.id(1): 1, F.id(2): 2])
    }

    @Test func malUtenKonkurranserErSomFor() throws {
        let payload = RoundTemplatePayload()
        #expect(try !keys(payload).contains("competitions"))
        var d = draft()
        d.competitions = [CompetitionRecipe.skins.make(for: d)]
        let saved = RoundTemplatePayload(draft: d)
        let back = try JSONDecoder().decode(RoundTemplatePayload.self, from: JSONEncoder().encode(saved))
        #expect(back.competitions.map(\.config) == [CompetitionConfig(form: "skins")])
    }

    @Test func nyeOppsettITurneringen() {
        for t in [RulesetTemplate.amerikanerSeries, .kobenhavnerSeries, .skinsSeries, .teamVsTeam] {
            #expect(!TournamentSetup.allowsPrivate(t))
            #expect(TournamentSetup.target(t, clubID: F.club) == .season)
            #expect(TournamentSetup.templates(inClub: true).contains(t))
            #expect(!TournamentSetup.templates(inClub: false).contains(t))
        }
        #expect(RulesetTemplate.skinsSeries.rules.table.formPoints)
        #expect(RulesetSummary.template(for: RulesetTemplate.amerikanerSeries.rules) == .amerikanerSeries)
    }
}
