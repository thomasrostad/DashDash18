import Foundation
import GolfgutuCore
import Testing
@testable import DashDash18

private typealias F = ForingFixture
private func id(_ n: Int) -> UUID { F.id(n) }

/// Gunstart (startlista, sql/031–032): kortet åpner på gruppas starthull, og «neste hull» går rundt.
struct ForingStarthullTests {
    /// Bås 1 starter på hull 1, bås 2 (Erik markør) på hull 10.
    private func game(scores: [(Int, Int, Int)] = [], holeCount: Int = 18, starts: [Int: Int] = [1: 1, 2: 10]) -> RoundGame {
        var s = F.snapshot(F.markorPlayers(), round: F.round(holeCount: holeCount), scores: scores)
        s.startHoles = starts
        return RoundGame(s)
    }

    private let erik = F.viewer(F.erik), anders = F.viewer(F.anders)
    private var bay2: [Int] { [F.erik, F.frode, F.gunnar, F.halvor] }

    @Test func kortetAapnerPaaStarthullet() {
        let g = game()
        #expect(g.bayHole(for: erik) == 9)
        #expect(g.bayHole(for: anders) == 0)
        #expect(g.startHoleIndex(for: erik) == 9)
    }

    @Test func utenStartlisteSomFor() {
        let g = game(starts: [:])
        #expect(g.bayHole(for: erik) == 0)
        #expect(g.nextHole(after: 17, for: erik) == nil)
        #expect(g.nextHole(after: 3, for: erik) == 4)
    }

    /// Ført 10–12: båsen er på hull 13. Ført 10–18: neste er hull 1. Alt ført: siste i rekka (hull 9).
    @Test func baasensHullGaarRundt() {
        let tenToTwelve = bay2.flatMap { m in (9...11).map { (m, $0, 4) } }
        #expect(game(scores: tenToTwelve).bayHole(for: erik) == 12)
        let back = bay2.flatMap { m in (9...17).map { (m, $0, 4) } }
        #expect(game(scores: back).bayHole(for: erik) == 0)
        let all = bay2.flatMap { m in (0...17).map { (m, $0, 4) } }
        #expect(game(scores: all).bayHole(for: erik) == 8)
    }

    @Test func nesteHullGaarFra18Til1() {
        let g = game()
        #expect(g.nextHole(after: 17, for: erik) == 0)
        #expect(g.nextHole(after: 9, for: erik) == 10)
        // Hullet før starthullet er det siste i runden.
        #expect(g.nextHole(after: 8, for: erik) == nil)
        #expect(g.nextHole(after: 17, for: anders) == nil)
    }

    @Test func lagreKnappenPaaHull18GaarVidereTilHull1() {
        let card = game().card(hole: 17, drafts: HoleDrafts(), viewer: erik)
        guard case .save(let title, _, _) = card.action else { Issue.record("ventet lagre"); return }
        #expect(title == "Lagre hull 18 og gå videre")
        let last = game().card(hole: 8, drafts: HoleDrafts(), viewer: erik)
        guard case .save(let lastTitle, _, _) = last.action else { Issue.record("ventet lagre"); return }
        #expect(lastTitle == "Lagre hull 9")
    }

    /// Et starthull utenfor runden (9 hull, starthull 12) ses bort fra.
    @Test func starthullUtenforRundenSesBortFra() {
        let g = game(holeCount: 9, starts: [2: 12])
        #expect(g.bayHole(for: erik) == 0)
    }

    @Test func feiringenSierNesteHull() {
        let g = game()
        let c = g.celebration(hole: 17, saved: [(id(F.erik), 1)], viewer: erik)
        #expect(c?.nextHole == 1)
    }
}
