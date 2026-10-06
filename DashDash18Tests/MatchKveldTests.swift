import Foundation
import GolfgutuCore
import Testing
@testable import DashDash18

private typealias F = ForingFixture
private func id(_ n: Int) -> UUID { F.id(n) }

/// Felles for matchtestene: matcher som rader, slik de kommer fra `round_matches`.
private enum MatchFixture {
    static func duel(_ no: Int, _ a: Int, _ b: Int, c: Int? = nil, result: String? = nil) -> RoundMatchRow {
        RoundMatchRow(roundID: F.roundID, matchNo: no, playerA: id(a), playerB: id(b), playerC: c.map(id),
                      teamA: nil, teamB: nil, result: result)
    }

    static func team(_ no: Int, _ a: Int, _ b: Int) -> RoundMatchRow {
        RoundMatchRow(roundID: F.roundID, matchNo: no, playerA: nil, playerB: nil, playerC: nil,
                      teamA: a, teamB: b, result: nil)
    }

    /// Scorer som `[spiller: [brutto per hull fra hull 1]]`.
    static func scores(_ map: [Int: [Int]]) -> [(Int, Int, Int)] {
        map.flatMap { member, list in list.enumerated().map { (member, $0.offset, $0.element) } }
    }
}

/// matchrunde-test.js: fourball over ni hull på Adare Manor, Trackman fordeler slagene.
/// Lag 1 a+b, 2 c+d, 3 e+f, 4 g+h, 5 i, 6 j. Matcher lag 1–2, 3–4 og 5–6. ME = Erik.
struct MatchrundeTests {
    static let par9 = [4, 4, 3, 4, 5, 3, 4, 4, 5]
    static let names = ["Anders", "Bjørn", "Cato", "Dag", "Erik", "Frode", "Geir", "Harald", "Ivar", "Jon"]
    static let teams = [1, 1, 2, 2, 3, 3, 4, 4, 5, 6]
    static let erik = 5, frode = 6, geir = 7, harald = 8, ivar = 9, jon = 10, anders = 1

    static func game(_ scores: [Int: [Int?]], format: String = "fourball", matches: [RoundMatchRow]? = nil,
                     teams useTeams: Bool = true, bays: [Int: Int] = [:]) -> RoundGame {
        let players = names.enumerated().map { i, n in
            F.P(n: i + 1, name: n, handicap: 10, bay: bays[i + 1], team: useTeams ? teams[i] : nil)
        }
        var s = F.snapshot(players, round: F.round(holeCount: 9, format: format, externalHandicap: true))
        s.courseHoles = par9.enumerated().map { i, p in
            CourseHoleRecord(courseID: F.courseID, holeNumber: i + 1, par: p, strokeIndex: i + 1, lengthM: nil)
        }
        s.matches = matches ?? [MatchFixture.team(1, 1, 2), MatchFixture.team(2, 3, 4), MatchFixture.team(3, 5, 6)]
        s.scores = scores.flatMap { member, list in
            list.enumerated().compactMap { i, v in
                v.map { HoleScoreRow(roundID: F.roundID, memberID: id(member), holeIndex: i, strokes: $0,
                                     recordedAt: nil, updatedBy: nil, updatedAt: nil) }
            }
        }
        return RoundGame(s)
    }

    /// Hull 1 slik det ble ført: lag 3 (Erik 3, Frode 5) mot lag 4 (Geir 6, Harald 5), Ivar 4 mot Jon 5.
    static let hull1: [Int: [Int?]] = [erik: [3], frode: [5], geir: [6], harald: [5], ivar: [4], jon: [5]]
    let erikSer = Viewer(memberID: id(erik), isOrganizer: false)

    @Test func rundenAvgjoresHullForHull() {
        let g = Self.game(Self.hull1)
        #expect(g.isDecidedHoleByHole)
        #expect(g.holeMatchStanding(id(Self.erik)).map(MatchPlay.shortText) == "1 opp")
        #expect(g.holeMatchStanding(id(Self.harald)).map(MatchPlay.shortText) == "1 ned")
        #expect(g.holeMatchStanding(id(Self.anders)).map(MatchPlay.shortText) == "—")
    }

    @Test func hullkortetSierHvemSomVantHullet() {
        let g = Self.game(Self.hull1)
        let lines = g.holeMatchLines(hole: 0, viewer: erikSer)
        #expect(lines.count == 1)
        #expect(lines.first?.what == "Hull 1 til Erik + Frode")
        #expect(lines.first?.standing == "1 opp etter 1")
        #expect(lines.first?.tone == .up)
    }

    @Test func hullkortetSierHvorMatchenStarFoerHulletErFoert() {
        let lines = Self.game(Self.hull1).holeMatchLines(hole: 1, viewer: erikSer)
        #expect(lines.first?.what == "Matchen")
        #expect(lines.first?.standing == "1 opp etter 1")
    }

    @Test func haraldSerSinMatchFraSinSide() {
        let g = Self.game(Self.hull1)
        let lines = g.holeMatchLines(hole: 0, viewer: Viewer(memberID: id(Self.harald), isOrganizer: false))
        #expect(lines.first?.standing == "1 ned etter 1")
        #expect(lines.first?.tone == .down)
    }

    @Test func andresMatchPaaKortetViserHvemSomLeder() {
        // Anders og Erik i samme bås, uten markør: Anders ser begge matchene på kortet.
        let g = Self.game(Self.hull1, bays: [Self.anders: 1, Self.erik: 1])
        let lines = g.holeMatchLines(hole: 0, viewer: Viewer(memberID: id(Self.anders), isOrganizer: false))
        #expect(lines.map(\.matchNo) == [1, 2])
        #expect(lines[0].what == "Matchen")
        #expect(lines[0].standing == "Ikke startet")
        #expect(lines[1].what == "Hull 1 til Erik + Frode")
        #expect(lines[1].standing == "Erik + Frode 1 opp")
        #expect(lines[1].tone == .neutral)
    }

    @Test func laveSlagVinnerOgsaaNaarStablefordSierLikt() {
        // 6 mot 7 på en par 4 gir 0 poeng begge, men hullet er vunnet.
        let g = Self.game([Self.erik: [6], Self.frode: [6], Self.geir: [7], Self.harald: [7]])
        #expect(g.holeMatchLines(hole: 0, viewer: erikSer).first?.what == "Hull 1 til Erik + Frode")
        #expect(Scoring.points(par: 4, gross: 6, handicap: 0, strokeIndex: 1, holes: 9)
                == Scoring.points(par: 4, gross: 7, handicap: 0, strokeIndex: 1, holes: 9))
    }

    @Test func liktBesteBallErDelt() {
        let g = Self.game([Self.erik: [4], Self.frode: [5], Self.geir: [4], Self.harald: [6]])
        #expect(g.holeMatchStanding(id(Self.erik)).map(MatchPlay.shortText) == "Delt")
        #expect(g.holeMatchLines(hole: 0, viewer: erikSer).first?.what == "Hull 1 delt")
    }

    @Test func treHullVunnetTaptDelt() {
        let g = Self.game([Self.erik: [3, 5, 3], Self.frode: [5, 5, 4], Self.geir: [6, 4, 3], Self.harald: [5, 6, 4]])
        let card = g.matchCard(viewer: erikSer)
        let mine = card?.mine.first
        #expect(mine?.title == "Mot Geir + Harald")
        #expect(mine?.text == "Delt etter 3")
        #expect(mine?.holes.prefix(4).map(\.result) == [.won, .lost, .halved, .open])
        #expect(mine?.holes.count == 9)
        #expect(card?.decidedHint == nil)
        #expect(card?.others.count == 2)
    }

    @Test func bayenViserStillingIkkePoeng() {
        let rows = Self.game(Self.hull1).bayenNaa(viewer: erikSer)
        #expect(rows.count == 10)
        #expect(rows.allSatisfy { $0.place == nil })
        #expect(rows.first { $0.memberID == id(Self.erik) }?.value == "1 opp")
        #expect(rows.first { $0.memberID == id(Self.harald) }?.value == "1 ned")
        #expect(rows.first { $0.memberID == id(Self.anders) }?.value == "—")
        #expect(!rows.contains { $0.value.hasSuffix(" p") || Int($0.value) != nil })
        // Flest hull opp først.
        let order = rows.map(\.name)
        let up = [order.firstIndex(of: "Erik")!, order.firstIndex(of: "Ivar")!]
        let down = [order.firstIndex(of: "Harald")!, order.firstIndex(of: "Jon")!]
        #expect(up.max()! < down.min()!)
    }

    @Test func birdieIMatchrundeViserStillingen() {
        let g = Self.game([Self.erik: [3], Self.geir: [5], Self.harald: [5], Self.frode: [5]])
        let c = g.celebration(hole: 0, saved: [(id(Self.erik), 3)])
        #expect(c?.level == .birdie)
        #expect(c?.matchText == "1 opp etter 1")
        #expect(c?.points == nil)
        #expect(c?.place == nil)
    }

    @Test func utenMatcherErAltSomFoer() {
        var all: [Int: [Int?]] = [:]
        for n in 1...10 { all[n] = [4, 4, 3] }
        all[Self.erik] = [3, 3, 2]
        let g = Self.game(all, format: "stableford", matches: [], teams: false)
        #expect(!g.isDecidedHoleByHole)
        #expect(g.matchCard(viewer: erikSer) == nil)
        let rows = g.bayenNaa(viewer: erikSer)
        #expect(rows.first?.memberID == id(Self.erik))
        #expect(rows.first?.place == 1)
        #expect(rows.first?.value == "\(g.total(id(Self.erik)))")
        #expect(g.celebration(hole: 0, saved: [(id(Self.erik), 3)])?.points != nil)
        #expect(g.celebration(hole: 0, saved: [(id(Self.erik), 3)])?.matchText == nil)
    }

    @Test func bareTrekantAvgjoresPaaPoeng() {
        let g = Self.game([1: [4], 2: [5], 3: [6]], format: "stableford",
                          matches: [MatchFixture.duel(1, 1, 2, c: 3)], teams: false)
        #expect(!g.isDecidedHoleByHole)
        #expect(g.holeMatchStanding(id(1)) == nil)
        #expect(g.holeMatchLines(hole: 0, viewer: Viewer(memberID: id(1), isOrganizer: false)).isEmpty)
        #expect(g.bayenNaa(viewer: erikSer).first?.place == 1)
    }
}

/// match-test.js §3: Anders mot Bjørn, begge hcp 0, 16 hull ført.
struct MatchTekstTests {
    static let a = 1, b = 2, c = 3
    static let anders = [5, 6, 4, 5, 5, 4, 6, 5, 5, 5, 4, 6, 5, 5, 2, 3]
    static let bjorn = [4, 5, 3, 4, 4, 3, 5, 4, 4, 4, 3, 5, 4, 4, 3, 4]

    static func game(cut: (String, Int)? = nil, result: String? = nil) -> RoundGame {
        var round = F.round(format: "match")
        round.cutRule = cut?.0
        round.cutAfter = cut?.1
        var s = F.snapshot([F.P(n: a, name: "Anders"), F.P(n: b, name: "Bjørn"), F.P(n: c, name: "Cato")],
                           round: round, scores: MatchFixture.scores([a: anders, b: bjorn]))
        s.matches = [MatchFixture.duel(1, a, b, result: result)]
        return RoundGame(s)
    }

    @Test func tapt12og2() {
        let g = Self.game()
        let card = g.matchCard(viewer: Viewer(memberID: id(Self.a), isOrganizer: false))
        let mine = card?.mine.first
        #expect(mine?.title == "Mot Bjørn")
        #expect(mine?.text == "Tapt 12&2")
        #expect(mine?.tone == .down)
        #expect(card?.decidedHint == "Matchen er avgjort. Resten av hullene endrer den ikke.")
        let results = mine?.holes.map(\.result) ?? []
        #expect(results.filter { $0 == .lost }.count == 14)
        #expect(Array(results[14...]) == [.won, .won, .open, .open])
    }

    @Test func vunnet12og2FraBjorn() {
        let mine = Self.game().matchCard(viewer: Viewer(memberID: id(Self.b), isOrganizer: false))?.mine.first
        #expect(mine?.title == "Mot Anders")
        #expect(mine?.text == "Vunnet 12&2")
        #expect(mine?.tone == .up)
    }

    @Test func andresMatchSierMarginOgLeder() {
        let card = Self.game().matchCard(viewer: Viewer(memberID: id(Self.c), isOrganizer: false))
        #expect(card?.mine.isEmpty == true)
        let other = card?.others.first
        #expect(other?.title == "Anders")
        #expect(other?.opponent == "Bjørn")
        #expect(other?.leader == .b)
        #expect(other?.text == "12&2")
        #expect(card?.decidedHint == nil)
    }

    @Test func avkortetFellesEtter14() {
        let g = Self.game(cut: ("common", 14))
        let mine = g.matchCard(viewer: Viewer(memberID: id(Self.a), isOrganizer: false))?.mine.first
        #expect(mine?.text == "Tapt 14 ned")
        #expect(mine?.holes.count == 14)
        #expect(g.matchCard(viewer: Viewer(memberID: id(Self.c), isOrganizer: false))?.others.first?.text == "14 opp")
        #expect(g.holeMatchStanding(id(Self.b)).map(MatchPlay.shortText) == "14 opp")
    }

    @Test func ikkeStartet() {
        var s = F.snapshot([F.P(n: Self.a, name: "Anders"), F.P(n: Self.b, name: "Bjørn")], round: F.round(format: "match"))
        s.matches = [MatchFixture.duel(1, Self.a, Self.b)]
        let g = RoundGame(s)
        #expect(g.matchCard(viewer: Viewer(memberID: id(Self.a), isOrganizer: false))?.mine.first?.text == "Ikke startet")
        #expect(g.bayenNaa(viewer: Viewer(memberID: id(Self.a), isOrganizer: false)).map(\.value) == ["—", "—"])
    }
}

/// trekant-test.js: tre spillere, hcp 0, 18 hull. Slag over par på hvert hull 0/1/2 gir 36/18/0.
struct MatchTrekantTests {
    static func game(_ over: [Int: Int?]) -> RoundGame {
        let players = [1, 2, 3].map { F.P(n: $0, name: "Spiller " + ["A", "B", "C"][$0 - 1]) }
        var scores: [Int: [Int]] = [:]
        for (p, o) in over { if let o { scores[p] = F.par.map { $0 + o } } }
        var s = F.snapshot(players, scores: MatchFixture.scores(scores))
        s.matches = [MatchFixture.duel(1, 1, 2, c: 3)]
        return RoundGame(s)
    }

    let me = Viewer(memberID: id(1), isOrganizer: false)

    @Test func rangertPaaPoengsum() {
        let line = Self.game([1: 0, 2: 1, 3: 2]).matchCard(viewer: me)?.mine.first
        #expect(line?.isTriangle == true)
        #expect(line?.title == "Spiller A · Spiller B · Spiller C")
        #expect(line?.text == "1 · 0,5 · 0")
        #expect(line?.subtitle == "Trekant · 1 / 0,5 / 0 etter poengsum")
        #expect(line?.holes.isEmpty == true)
    }

    @Test func rekkefolgenErEtterPoengsum() {
        let line = Self.game([1: 2, 2: 0, 3: 1]).matchCard(viewer: me)?.mine.first
        #expect(line?.title == "Spiller B · Spiller C · Spiller A")
        #expect(line?.text == "1 · 0,5 · 0")
    }

    // Poengene er 0,75/0,75/0 og 1/0,25/0,25 (trekant-test.js), men kortet viser dem med
    // fmtPoeng som PWA-en, avrundet til nærmeste halve etter regelsettet.
    @Test func deltForsteplass() {
        #expect(Self.game([1: 0, 2: 0, 3: 2]).matchCard(viewer: me)?.mine.first?.text == "1 · 1 · 0")
    }

    @Test func deltAndreplass() {
        #expect(Self.game([1: 0, 2: 2, 3: 2]).matchCard(viewer: me)?.mine.first?.text == "1 · 0,5 · 0,5")
    }

    @Test func alleLikt() {
        #expect(Self.game([1: 1, 2: 1, 3: 1]).matchCard(viewer: me)?.mine.first?.text == "0,5 · 0,5 · 0,5")
    }

    @Test func manglerTredjemannErIkkeAvgjort() {
        let g = Self.game([1: 0, 2: 1, 3: nil])
        #expect(g.matchCard(viewer: me)?.mine.first?.text == "Ikke avgjort")
        #expect(g.holeMatchStanding(id(1)) == nil)
    }

    @Test func plasspoengeneKommerFraRegelsettet() {
        var g = Self.game([1: 0, 2: 1, 3: 2]).snapshot
        g.rules.table.trianglePoints = [3, 1, 0]
        let line = RoundGame(g).matchCard(viewer: me)?.mine.first
        #expect(line?.text == "3 · 1 · 0")
        #expect(line?.subtitle == "Trekant · 3 / 1 / 0 etter poengsum")
    }
}

/// Lagformer med ett kort per lag: én rad per lag i «Bayen nå», med lagets sum.
struct MatchLagformTests {
    @Test func scrambleViserLagetsSum() {
        let players = [F.P(n: 1, name: "Anders", team: 1), F.P(n: 2, name: "Bjørn", team: 1),
                       F.P(n: 3, name: "Cato", team: 2), F.P(n: 4, name: "Dag", team: 2)]
        // Laget fører ett tall: samme brutto på hele laget.
        let scores = MatchFixture.scores([1: [4, 5, 3], 2: [4, 5, 3], 3: [5, 6, 4], 4: [5, 6, 4]])
        let g = RoundGame(F.snapshot(players, round: F.round(format: "scramble-2"), scores: scores))
        let rows = g.bayenNaa(viewer: Viewer(memberID: id(2), isOrganizer: false))
        #expect(rows.map(\.name) == ["Anders + Bjørn", "Cato + Dag"])
        #expect(rows.first?.isMe == true)
        #expect(rows.first?.thru == 3)
        let points = Scoring.roundPoints(g.round, roster: g.roster, rules: g.rules)
        #expect(rows.first?.total == points[id(1).uuidString])
        #expect(rows.last?.total == points[id(3).uuidString])
        #expect(rows.map(\.place) == [1, 2])
    }

    @Test func fourballHarEnRadPerSpiller() {
        let players = [F.P(n: 1, name: "Anders", team: 1), F.P(n: 2, name: "Bjørn", team: 1)]
        let g = RoundGame(F.snapshot(players, round: F.round(format: "fourball")))
        #expect(g.bayenNaa(viewer: F.viewer(1)).count == 2)
    }
}
