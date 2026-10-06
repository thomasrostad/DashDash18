import Foundation
import GolfgutuCore
import Testing
@testable import DashDash18

private typealias F = ForingFixture

/// Runden → Live Activity: bare oppslag i det `RoundGame` regner ut.
struct LiveActivityMappingTests {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)

    /// Bås 1 har ført hull 1–3. Handicap 0 på en par 72-bane: par gir 2, birdie 3, bogey 1.
    /// Anders 4-5-3 (6 p), Bjørn 3-5-3 (7 p), Cato 5-5-3 (5 p), Dag 4-5-3 (6 p).
    static func bay1Game(status: RoundStatus = .active, bays: Bool = true) -> RoundGame {
        let strokes: [Int: [Int]] = [F.anders: [4, 5, 3], F.bjorn: [3, 5, 3], F.cato: [5, 5, 3], F.dag: [4, 5, 3]]
        let scores = strokes.flatMap { member, list in list.enumerated().map { (member, $0.offset, $0.element) } }
        return RoundGame(F.snapshot(F.markorPlayers(bays: bays), round: F.round(status: status), scores: scores))
    }

    @Test func viserBaasensHullScoreOgPlassIBaasen() throws {
        let game = Self.bay1Game()
        let state = try #require(game.liveActivityContent(for: F.viewer(F.anders), now: Self.now))
        #expect(state.holeNumber == 4)
        #expect(state.holeCount == 18)
        #expect(state.holesPlayed == 3)
        #expect(state.strokes == 12)
        #expect(state.points == game.total(F.id(F.anders)))
        #expect(state.points == 6)
        // Bjørn 7, så Anders og Dag på 6 (norsk navnesortering), så Cato.
        #expect(state.bayPlace == 2)
        #expect(state.bayCount == 4)
        #expect(state.bayNumber == 1)
        #expect(state.matchText == nil)
        #expect(state.matchTone == .neutral)
        #expect(state.updatedAt == Self.now)
    }

    @Test func plassenGjelderBareBaasenMin() throws {
        // Bås 2 har ingenting ført: Erik står i en bås på fire uten poeng.
        let state = try #require(Self.bay1Game().liveActivityContent(for: F.viewer(F.erik), now: Self.now))
        #expect(state.bayNumber == 2)
        #expect(state.bayCount == 4)
        #expect(state.holeNumber == 1)
        #expect(state.holesPlayed == 0)
        #expect(state.points == 0)
    }

    @Test func utenBaaserGjelderPlassenHeleRunden() throws {
        let state = try #require(Self.bay1Game(bays: false).liveActivityContent(for: F.viewer(F.bjorn), now: Self.now))
        #expect(state.bayNumber == nil)
        #expect(state.bayPlace == 1)
        #expect(state.bayCount == 8)
    }

    @Test func deSisteNiHarHullnummer10() throws {
        let game = RoundGame(F.snapshot(F.markorPlayers(), round: F.round(holeCount: 9, firstHole: 10)))
        let state = try #require(game.liveActivityContent(for: F.viewer(F.anders), now: Self.now))
        #expect(state.holeNumber == 10)
        #expect(state.holeCount == 9)
    }

    @Test func ingenAktivitetForDenSomIkkeSpiller() {
        let game = Self.bay1Game()
        let outsider = Viewer(memberID: F.id(99), isOrganizer: true)
        #expect(game.liveActivityContent(for: outsider) == nil)
        #expect(!game.wantsLiveActivity(for: outsider))
    }

    @Test func barePaaMensRundenGaar() {
        let viewer = F.viewer(F.anders)
        #expect(Self.bay1Game(status: .active).wantsLiveActivity(for: viewer))
        #expect(!Self.bay1Game(status: .locked).wantsLiveActivity(for: viewer))
        #expect(!Self.bay1Game(status: .draft).wantsLiveActivity(for: viewer))
        // Låst runde: sluttstillingen finnes fortsatt, til avslutningen.
        #expect(Self.bay1Game(status: .locked).liveActivityContent(for: viewer) != nil)
    }

    @Test func attributterMedBaneOgNavn() {
        let attributes = Self.bay1Game().liveActivityAttributes(for: F.viewer(F.anders))
        #expect(attributes.roundID == F.roundID)
        #expect(attributes.courseName == "Testbanen")
        #expect(attributes.playerName == "Anders")
    }

    @Test func matchstillingenFraMatchkortet() throws {
        // matchrunde-test.js hull 1: Erik + Frode vinner hullet mot Geir + Harald.
        let game = MatchrundeTests.game(MatchrundeTests.hull1)
        let erik = Viewer(memberID: F.id(MatchrundeTests.erik), isOrganizer: false)
        let harald = Viewer(memberID: F.id(MatchrundeTests.harald), isOrganizer: false)
        let up = try #require(game.liveActivityContent(for: erik))
        #expect(up.matchText == "1 opp etter 1")
        #expect(up.matchText == game.matchCard(viewer: erik)?.mine.first?.text)
        #expect(up.matchTone == .up)
        let down = try #require(game.liveActivityContent(for: harald))
        #expect(down.matchTone == .down)
    }

    @Test func sammeInnholdUansettTidspunkt() throws {
        let game = Self.bay1Game()
        let a = try #require(game.liveActivityContent(for: F.viewer(F.anders), now: Self.now))
        let b = try #require(game.liveActivityContent(for: F.viewer(F.anders), now: Self.now.addingTimeInterval(60)))
        #expect(a != b)
        #expect(a.sameContent(as: b))
        let other = try #require(game.liveActivityContent(for: F.viewer(F.bjorn), now: Self.now))
        #expect(!a.sameContent(as: other))
    }

    @Test func innholdetKanKodesOgLesesTilbake() throws {
        let state = try #require(Self.bay1Game().liveActivityContent(for: F.viewer(F.anders), now: Self.now))
        let data = try JSONEncoder().encode(state)
        let back = try JSONDecoder().decode(RoundActivityAttributes.ContentState.self, from: data)
        #expect(back == state)
    }
}
