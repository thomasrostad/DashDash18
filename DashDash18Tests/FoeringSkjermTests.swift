import Foundation
import GolfgutuCore
import Testing
@testable import DashDash18

private typealias F = ForingFixture
private func id(_ n: Int) -> UUID { F.id(n) }

/// Føringen som egen skjerm (utbedringsplanen 4.2): tittelen, segmentene og hero-kortet.
struct FoeringSkjermTests {
    let game = RoundGame(F.snapshot(F.markorPlayers()))

    @Test func tittelenHarBanenOgRunden() {
        #expect(game.scoringTitle(viewer: F.viewer(F.anders)) == ScoringTitle(title: "Testbanen · runde 1",
                                                                              subtitle: "Du fører for bås 1"))
        #expect(game.scoringTitle(viewer: F.viewer(F.bjorn)).subtitle == "Bås 1 · Anders fører")
        // Gunnar er arrangør i bås 2 uten å være markør.
        #expect(game.scoringTitle(viewer: F.viewer(F.gunnar)).subtitle == "Bås 2 · Erik fører")
    }

    @Test func undertittelenUtenBaasOgEtterRunden() {
        let uten = RoundGame(F.snapshot(F.markorPlayers(bays: false)))
        #expect(uten.scoringTitle(viewer: F.viewer(F.bjorn)).subtitle == "Du fører ditt eget kort")
        let locked = RoundGame(F.snapshot(F.markorPlayers(), round: F.round(status: .locked)))
        #expect(locked.scoringTitle(viewer: F.viewer(F.anders)).subtitle == "Runden er ferdig")
        let tilskuer = Viewer(memberID: id(99), isOrganizer: false)
        #expect(game.scoringTitle(viewer: tilskuer).subtitle == "Du ser på")
    }

    @Test func kortBanenavn() {
        #expect(RoundGame.shortCourseName("Losby Golfklubb") == "Losby")
        #expect(RoundGame.shortCourseName("Oslo GK") == "Oslo")
        #expect(RoundGame.shortCourseName("Pebble Beach Golf Links") == "Pebble Beach Golf Links")
        #expect(RoundGame.shortCourseName("Golfklubb") == "Golfklubb")
    }

    @Test func segmentetSkjermenAapnerPaa() {
        #expect(RundeSegment.initial(isLocked: false, hasCard: true) == .scoring)
        #expect(RundeSegment.initial(isLocked: true, hasCard: true) == .standing)
        #expect(RundeSegment.initial(isLocked: false, hasCard: false) == .standing)
        #expect(RundeSegment.extrasTitle(count: 0) == "Spill")
        #expect(RundeSegment.extrasTitle(count: 2) == "Spill · 2")
    }

    @Test func heroKortetForHullet() {
        let card = game.card(hole: 2, drafts: HoleDrafts(), viewer: F.viewer(F.anders))
        #expect(card.number == 3 && card.par == 3 && card.holeCount == 18)
        #expect(card.parLine == "Par 3")
        #expect(card.indexLine == "Indeks 3")
        #expect(card.hasPrevious && card.hasNext)
        #expect(card.actionAdvances)

        let first = game.card(hole: 0, drafts: HoleDrafts(), viewer: F.viewer(F.anders))
        #expect(!first.hasPrevious)
        let last = game.card(hole: 17, drafts: HoleDrafts(), viewer: F.viewer(F.anders))
        #expect(!last.hasNext)
        #expect(!last.actionAdvances)   // «Lagre hull 18»

        let ekstern = RoundGame(F.snapshot(F.markorPlayers(), round: F.round(externalHandicap: true)))
        #expect(ekstern.card(hole: 0, drafts: HoleDrafts(), viewer: F.viewer(F.anders)).indexLine == nil)
    }

    @Test func parLinjaMedMeter() {
        var s = F.snapshot(F.markorPlayers())
        s.courseHoles[6] = CourseHoleRecord(courseID: F.courseID, holeNumber: 7, par: 3, strokeIndex: 17, lengthM: 155)
        let card = RoundGame(s).card(hole: 6, drafts: HoleDrafts(), viewer: F.viewer(F.anders))
        #expect(card.parLine == "Par 3 · 155 m")
        #expect(card.indexLine == "Indeks 17")
    }
}

/// Hullvelgeren (V15): brikkenes tilstand og det VoiceOver leser.
struct HullbrikkeTests {
    let bay = [F.anders, F.bjorn, F.cato, F.dag]

    @Test func brikkenesTilstand() {
        let scores = bay.map { ($0, 0, 4) } + [(F.anders, 1, 5)]
        let g = RoundGame(F.snapshot(F.markorPlayers(), scores: scores))
        let dots = g.dots(currentHole: 2, viewer: F.viewer(F.bjorn), pending: [0])
        #expect(dots[0].chipStyle == .saved)
        #expect(dots[1].chipStyle == .partial)
        #expect(dots[2].chipStyle == .current)
        #expect(dots[3].chipStyle == .upcoming)
        // Nåværende vinner over lagret.
        #expect(g.dots(currentHole: 0, viewer: F.viewer(F.bjorn), pending: [])[0].chipStyle == .current)
    }

    @Test func sidepremieGirGullPrikk() {
        let g = RoundGame(F.snapshot(F.markorPlayers()))
        let dots = g.dots(currentHole: 0, viewer: F.viewer(F.anders), pending: [])
        // LD på hull 7 og KP på hull 6 (forslagene).
        #expect(dots[6].hasSidePrize && dots[5].hasSidePrize)
        #expect(!dots[0].hasSidePrize)
    }

    @Test func voiceOverLeserNaavaerendeOgSidepremie() {
        let dot = HoleDot(index: 6, number: 7, state: .upcoming, isCurrent: true, isPending: false,
                          isLongestDrive: false, isClosestToPin: true, isBayHole: false)
        #expect(dot.accessibilityLabel == "Hull 7, nåværende, nærmest pinnen")
        let saved = HoleDot(index: 2, number: 3, state: .done, isCurrent: false, isPending: true,
                            isLongestDrive: false, isClosestToPin: false, isBayHole: true)
        #expect(saved.accessibilityLabel == "Hull 3, lagret, ikke sendt ennå, båsens hull")
        let next = HoleDot(index: 7, number: 8, state: .upcoming, isCurrent: false, isPending: false,
                           isLongestDrive: false, isClosestToPin: false, isBayHole: false)
        #expect(next.accessibilityLabel == "Hull 8, ikke lagret")
    }
}

/// VoiceOver på stepperen (V7): «Kåre, 4 slag» og «2 poeng».
struct StepperTilgjengelighetTests {
    @Test func etikettOgVerdi() {
        let row = HoleCard.Row(memberID: id(1), name: "Kåre", isMe: false, editable: true, confirmed: true, saved: nil,
                               value: 4, strokesReceived: 1, calculation: nil, scoreName: .par, points: 2)
        #expect(StrokeAccessibility.label(row) == "Kåre, 4 slag")
        #expect(StrokeAccessibility.value(row) == "2 poeng")
        let forvalgt = HoleCard.Row(memberID: id(2), name: "Thomas", isMe: true, editable: true, confirmed: false,
                                    saved: nil, value: 3, strokesReceived: 0, calculation: nil, scoreName: .par,
                                    points: nil)
        #expect(StrokeAccessibility.value(forvalgt) == "forvalgt par")
    }
}
