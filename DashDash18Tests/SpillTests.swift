import Foundation
import GolfgutuCore
import Testing
@testable import DashDash18

/// Spill på runden i appen (fase 14): radene fra 020, mappingen til regelmotoren, kortene
/// (stilling, linjer, markering, oppgjør) og arket for nytt spill. Regnestykket selv er testet i
/// GolfgutuCore (GamesTests, Fixtures/spill.json).
struct SpillTests {
    typealias F = ForingFixture

    static let a = F.id(1), b = F.id(2), c = F.id(3), d = F.id(4)
    static let players = [
        F.P(n: 1, name: "Anders", bay: 1, marker: true, playing: 0), F.P(n: 2, name: "Bjørn", bay: 1, playing: 0),
        F.P(n: 3, name: "Cato", bay: 1, playing: 0), F.P(n: 4, name: "Dag", bay: 1, playing: 0),
    ]
    static let gameID = F.id(500)
    static let organizer = Viewer(memberID: F.id(9), isOrganizer: true)
    static let marker = Viewer(memberID: a, isOrganizer: false)
    static let bjornViewer = Viewer(memberID: b, isOrganizer: false)

    /// Hull 1: Anders 3, de andre 4. Hull 2: alle 5.
    static func roundGame(holes: Int = 2, status: RoundStatus = .active) -> RoundGame {
        var scores: [(Int, Int, Int)] = []
        for n in 1...4 {
            for h in 0..<holes {
                scores.append((n, h, h == 0 ? (n == 1 ? 3 : 4) : 5))
            }
        }
        return RoundGame(F.snapshot(players, round: F.round(status: status), scores: scores))
    }

    static func input(_ settings: GameSettings, sides: [Int?]? = nil, status: RoundGameRow.Status = .open,
                      createdBy: UUID? = nil, marks: [RoundGameMarkRow] = [],
                      results: [RoundGameResultRow] = []) -> GamesInput {
        let ids = [a, b, c, d]
        return GamesInput(
            games: [RoundGameRow(id: gameID, roundID: F.roundID, settings: settings, status: status, createdBy: createdBy)],
            players: ids.enumerated().map { i, p in
                RoundGamePlayerRow(gameID: gameID, roundID: F.roundID, playerID: p, seat: i + 1, side: sides?[i] ?? nil)
            },
            marks: marks, results: results)
    }

    @Test func flagget() {
        #expect(!GamesFeature.isEnabled)
    }

    // MARK: Kortene

    @Test func skinsUnderveis() throws {
        let board = GamesBoard(Self.input(.skins(.standard)), game: Self.roundGame(), viewer: Self.marker, me: nil, hole: 2)
        let card = try #require(board.cards.first)
        #expect(card.title == "Skins")
        #expect(card.status == "Etter hull 2 · 1 skin står")
        #expect(card.rows.first?.name == "Anders")
        #expect(card.rows.first?.detail == "1 skin")
        #expect(card.rows.first?.points == 30)
        #expect(card.rows.dropFirst().map(\.points) == [-10, -10, -10])
        #expect(card.rows.dropFirst().map(\.name) == ["Bjørn", "Cato", "Dag"])
        #expect(!card.canSettle)
        #expect(card.action == nil)
        #expect(card.summary == "Netto, fullt handicap · 10 poeng per skin · delte hull går videre")
    }

    @Test func wolfValgetPaaHullet() throws {
        let game = Self.roundGame()
        let marker = try #require(GamesBoard(Self.input(.wolf(.standard)), game: game, viewer: Self.marker,
                                             me: nil, hole: 2).cards.first)
        // Rekkefølgen er Anders, Bjørn, Cato, Dag: Cato er wolf på hull 3.
        #expect(marker.action == .wolf(hole: 2, wolf: Self.c, partners: [Self.a, Self.b, Self.d], blindAllowed: true,
                                       current: nil))
        #expect(marker.lines == ["Hull 3: Cato er wolf · Ikke valgt ennå"])
        // Bjørn står i bås med markør og fører ikke selv.
        let bjorn = try #require(GamesBoard(Self.input(.wolf(.standard)), game: game, viewer: Self.bjornViewer,
                                            me: nil, hole: 2).cards.first)
        #expect(bjorn.action == nil)
    }

    @Test func wolfPoengFraMarkeringene() throws {
        // Hull 1: Anders er wolf og spiller alene, 3 mot 4: 4 poeng. Hull 2: Bjørn tar Cato, alle 5: delt.
        let marks = [
            RoundGameMarkRow(gameID: Self.gameID, roundID: F.roundID, holeIndex: 0, award: .wolf, playerID: nil, wolfMode: .alone),
            RoundGameMarkRow(gameID: Self.gameID, roundID: F.roundID, holeIndex: 1, award: .wolf, playerID: Self.c,
                             wolfMode: .partner),
        ]
        let card = try #require(GamesBoard(Self.input(.wolf(.standard), marks: marks), game: Self.roundGame(),
                                           viewer: Self.marker, me: nil, hole: 1).cards.first)
        #expect(card.rows.first?.name == "Anders")
        #expect(card.rows.first?.detail == "4 p")
        #expect(card.rows.map(\.points) == [12, -4, -4, -4])
        #expect(card.status == "2 av 18 hull")
        #expect(card.lines == ["Hull 2: Bjørn er wolf · Partner: Cato"])
    }

    @Test func nassauLinjer() throws {
        let card = try #require(GamesBoard(Self.input(.nassau(.standard), sides: [1, 1, 2, 2]), game: Self.roundGame(),
                                           viewer: Self.marker, me: nil, hole: 2).cards.first)
        #expect(card.lines == [
            "Første ni: Anders og Bjørn 1 opp, 7 igjen",
            "Siste ni: likt, 9 igjen",
            "Totalt: Anders og Bjørn 1 opp, 16 igjen",
        ])
        #expect(card.rows.first(where: { $0.id == Self.a })?.detail == "Lag 1")
        #expect(card.rows.allSatisfy { $0.points == 0 })
    }

    @Test func bingoBangoBongo() throws {
        let marks = [
            RoundGameMarkRow(gameID: Self.gameID, roundID: F.roundID, holeIndex: 0, award: .bingo, playerID: Self.d, wolfMode: nil),
            RoundGameMarkRow(gameID: Self.gameID, roundID: F.roundID, holeIndex: 0, award: .bongo, playerID: Self.d, wolfMode: nil),
        ]
        let card = try #require(GamesBoard(Self.input(.bingoBangoBongo(.standard), marks: marks), game: Self.roundGame(),
                                           viewer: Self.marker, me: nil, hole: 0).cards.first)
        #expect(card.lines == ["Hull 1: bingo Dag, bango –, bongo Dag"])
        #expect(card.rows.first?.points == 6)
        guard case .bingoBangoBongo(let hole, let ps, let current) = card.action else {
            Issue.record("forventet bbb-markering")
            return
        }
        #expect(hole == 0 && ps == [Self.a, Self.b, Self.c, Self.d])
        #expect(current.bingo == Self.d.uuidString && current.bango == nil)
    }

    @Test func oppgjoretNaarRundenErFerdig() throws {
        let game = Self.roundGame(holes: 18, status: .locked)
        let input = Self.input(.skins(.standard), createdBy: Self.b)
        let org = try #require(GamesBoard(input, game: game, viewer: Self.organizer, me: nil, hole: 0).cards.first)
        #expect(org.canSettle)
        #expect(org.status == "Klar til oppgjør")
        // Anders vant hull 1 alene, resten er delt og faller bort: +30, −10 hver.
        #expect(org.settlement == [Self.a: 30, Self.b: -10, Self.c: -10, Self.d: -10])
        let creator = try #require(GamesBoard(input, game: game, viewer: Self.bjornViewer, me: Self.b, hole: 0).cards.first)
        #expect(creator.canSettle)
        let other = try #require(GamesBoard(input, game: game, viewer: Self.marker, me: Self.a, hole: 0).cards.first)
        #expect(!other.canSettle)
        #expect(!other.canDelete)
    }

    @Test func gjortOppViserBanken() throws {
        let results = [Self.a: 5, Self.b: -5, Self.c: 0, Self.d: 0].map {
            RoundGameResultRow(gameID: Self.gameID, roundID: F.roundID, playerID: $0.key, points: $0.value)
        }
        let card = try #require(GamesBoard(Self.input(.skins(.standard), status: .settled, results: results),
                                           game: Self.roundGame(holes: 18, status: .locked), viewer: Self.organizer,
                                           me: nil, hole: 0).cards.first)
        #expect(card.status == "Gjort opp")
        #expect(card.isSettled && !card.canSettle && !card.canDelete)
        #expect(card.rows.map(\.points) == [5, 0, 0, -5])
    }

    // MARK: Radene og RPC-ene

    @Test func spillradenLeserMalen() throws {
        let json = """
        {"id": "\(Self.gameID)", "round_id": "\(F.roundID)", "kind": "nassau", "settings": {"press": true},
         "status": "open", "created_by": null, "settled_at": null}
        """
        let row = try JSONDecoder().decode(RoundGameRow.self, from: Data(json.utf8))
        guard case .nassau(let r) = row.settings else { Issue.record("feil type"); return }
        #expect(r.press && r.front == NassauRules.standard.front && r.handicap == NassauRules.standard.handicap)
    }

    @Test func markeringeneTilRegelmotoren() {
        let input = Self.input(.wolf(.standard), marks: [
            RoundGameMarkRow(gameID: Self.gameID, roundID: F.roundID, holeIndex: 3, award: .wolf, playerID: Self.b,
                             wolfMode: .partner),
            RoundGameMarkRow(gameID: Self.gameID, roundID: F.roundID, holeIndex: 4, award: .wolf, playerID: nil, wolfMode: .blind),
            RoundGameMarkRow(gameID: Self.gameID, roundID: F.roundID, holeIndex: 4, award: .bango, playerID: Self.c, wolfMode: nil),
        ])
        let marks = input.marks(for: Self.gameID)
        #expect(marks.wolf[3] == .partner(Self.b.uuidString))
        #expect(marks.wolf[4] == .blind)
        #expect(marks.bingoBangoBongo[4] == BingoBangoBongoMarks(bango: Self.c.uuidString))
        #expect(input.setup(for: input.games[0]).players == [Self.a, Self.b, Self.c, Self.d].map(\.uuidString))
    }

    @Test func parametreneTilRPCene() throws {
        var draft = GameDraft(kind: .bestBall, roundPlayers: [Self.a, Self.b, Self.c, Self.d])
        draft.bestBall.value = 20
        let data = try JSONEncoder().encode(draft.params(roundID: F.roundID))
        let obj = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(obj["p_kind"] as? String == "best_ball")
        #expect((obj["p_settings"] as? [String: Any])?["value"] as? Int == 20)
        let entries = try #require(obj["p_players"] as? [[String: Any]])
        #expect(entries.map { $0["side"] as? Int } == [1, 2, 1, 2])

        let wolf = GameDraft(kind: .wolf, roundPlayers: [Self.a, Self.b, Self.c])
        let wolfObj = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(wolf.params(roundID: F.roundID)))
                                   as? [String: Any])
        #expect((wolfObj["p_players"] as? [[String: Any]])?.allSatisfy { $0["side"] == nil } == true)

        let settle = SettleGameParams(gameID: Self.gameID, points: [Self.a: 10, Self.b: -10])
        #expect(Set(settle.p_points.keys) == [Self.a.uuidString.lowercased(), Self.b.uuidString.lowercased()])
    }

    @Test func nyttSpillArket() {
        var draft = GameDraft(kind: .skins, roundPlayers: [Self.a, Self.b, Self.c, Self.d], preferred: [Self.c])
        #expect(draft.players == [Self.c, Self.a, Self.b, Self.d])
        #expect(draft.settings == .skins(.standard))
        draft.setKind(.bestBall)
        #expect(draft.settings == .bestBall(.standard))
        #expect(draft.side(1) == [Self.c, Self.b] && draft.side(2) == [Self.a, Self.d])
        #expect(draft.problems().isEmpty)
        draft.toggle(Self.d)
        #expect(draft.problems().contains(.playerCount(.bestBall, 4...4)))
        draft.toggle(Self.d)
        #expect(draft.players.last == Self.d && draft.sides[Self.d] == 2)
        draft.setSide(Self.d, 1)
        #expect(draft.problems() == [.sides])
        #expect(GameTexts.problem(.sides, names: { $0 }).hasPrefix("Velg to sider"))
        draft.setKind(.wolf)
        #expect(draft.sides.isEmpty && draft.problems().isEmpty)
    }

    @Test func tekster() {
        #expect(GameTexts.signed(30) == "+30")
        #expect(GameTexts.signed(-5) == "−5")
        #expect(GameTexts.signed(0) == "0")
        #expect(GameTexts.skins(7.0 / 3) == "2,3 skins")
        #expect(GameTexts.skins(1) == "1 skin")
        #expect(GameTexts.handicap(BestBallRules.standard.matchHandicap) == "Netto, 90 % av handicapet, laveste fra scratch")
        #expect(GameTexts.problem(.playerCount(.bestBall, 4...4), names: { $0 }) == "2 mot 2 best ball er for 4 spillere.")
        for kind in GameKind.allCases {
            #expect(!GameTexts.explanation(kind).isEmpty)
        }
    }

    @Test func feilmeldingene() {
        #expect(GameErrors.text(sqlState: "22023", message: "Oppgjøret må gå i null") == "Oppgjøret må gå i null")
        #expect(GameErrors.text(sqlState: "42501", message: "Du kan ikke føre i dette spillet") == "Du kan ikke føre i dette spillet")
        #expect(GameErrors.text(sqlState: "42501", message: "permission denied for table round_games") == nil)
        #expect(GameErrors.text(sqlState: "23505", message: "duplicate key") == nil)
    }
}
