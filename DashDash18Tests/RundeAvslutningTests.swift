import Foundation
import GolfgutuCore
import Testing
@testable import DashDash18

/// «Ferdig? Avslutt runden» i føringen (`RoundEndPrompt`, `RoundEndOffer`): når knappen vises, for hvem,
/// og tekstene. Markør-oppsettet: Anders markør i bås 1, Erik i bås 2, Gunnar arrangør i bås 2.
@MainActor
struct RundeAvslutningTests {
    typealias F = ForingFixture

    static func game(scores: [(Int, Int, Int)], bays: Bool = true, round: RoundRow = F.round(),
                     rules: Ruleset = .golfgutu) -> RoundGame {
        var s = F.snapshot(F.markorPlayers(bays: bays), round: round, scores: scores)
        s.rules = rules
        return RoundGame(s)
    }

    static func full(_ players: [Int], holes: Range<Int> = 0..<18) -> [(Int, Int, Int)] {
        players.flatMap { p in holes.map { (p, $0, F.par[$0]) } }
    }

    static let bay1 = [F.anders, F.bjorn, F.cato, F.dag]
    static let bay2 = [F.erik, F.frode, F.gunnar, F.halvor]

    static let anders = F.viewer(F.anders)
    static let gunnar = F.viewer(F.gunnar)
    /// Arrangøren som ikke spiller.
    static let watcher = Viewer(memberID: F.id(99), isOrganizer: true)

    static func prompt(_ game: RoundGame, _ viewer: Viewer, canEnd: Bool? = nil, isLoose: Bool = false,
                       pending: Set<Int> = [], hole: Int = 17, cardLock: Bool = false) -> RoundEndPrompt? {
        game.endPrompt(viewer: viewer, canEnd: canEnd ?? viewer.isOrganizer, isLoose: isLoose, pending: pending,
                       currentHole: hole, cardLockAvailable: cardLock)
    }

    // MARK: Når knappen vises

    @Test func ingentingFoertIngenKnapp() {
        let game = Self.game(scores: [])
        #expect(Self.prompt(game, Self.anders) == nil)
        #expect(Self.prompt(game, Self.gunnar) == nil)
        #expect(Self.prompt(game, Self.watcher) == nil)
    }

    @Test func spillerSerAtKortetErFerdig() {
        let game = Self.game(scores: Self.full(Self.bay1))
        let prompt = Self.prompt(game, Self.anders)
        #expect(prompt == .cardDone(isLoose: false))
        #expect(RoundEndPrompt.cardDoneTitle == "Kortet ditt er ferdig")
        #expect(prompt?.cardDoneText == "Alle hullene er ført. Arrangøren avslutter runden.")
        // Bjørn fører ikke selv, men kortet til båsen er ferdig.
        #expect(Self.prompt(game, F.viewer(F.bjorn)) == .cardDone(isLoose: false))
        // Bås 2 har ikke ført: ingenting for Erik.
        #expect(Self.prompt(game, F.viewer(F.erik)) == nil)
    }

    @Test func arrangorenAvslutterNaarAlleErFerdige() {
        let game = Self.game(scores: Self.full(Self.bay1 + Self.bay2))
        guard case .offer(let offer)? = Self.prompt(game, Self.gunnar) else {
            Issue.record("Ventet «Ferdig? Avslutt runden»")
            return
        }
        #expect(!offer.hasUnfinished)
        #expect(offer.statusText == "Alle hullene er ført.")
        #expect(offer.extraConfirm == nil)
        #expect(offer.confirmMessage == "Runden låses, og resultatet står. Ingen kan føre mer.")
        #expect(RoundEndOffer.buttonTitle == "Ferdig? Avslutt runden")
        // En spiller som ikke er arrangør, får aldri avslutt-knappen.
        #expect(Self.prompt(game, Self.anders) == .cardDone(isLoose: false))
    }

    @Test func arrangorenSerHvorMangeSomMangler() {
        // Gunnar (bås 2) er ferdig, bås 1 har ikke ført.
        let game = Self.game(scores: Self.full(Self.bay2))
        guard case .offer(let offer)? = Self.prompt(game, Self.gunnar) else {
            Issue.record("Ventet tilbud om å avslutte")
            return
        }
        #expect(offer.unfinishedGroups == 1 && offer.unfinishedPlayers == 0)
        #expect(offer.statusText == "1 bås er ikke ferdig.")
        #expect(offer.extraConfirm?.title == "1 bås er ikke ferdig")
        #expect(offer.extraConfirm?.message == "Hullene de ikke har ført, står tomme i resultatet. Vil du avslutte runden likevel?")
        #expect(offer.confirmMessage == "1 bås er ikke ferdig. Runden låses, og resultatet står. Ingen kan føre mer.")
    }

    @Test func flightPaaEkteBane() {
        var round = F.round()
        round.venue = "course"
        let game = Self.game(scores: Self.full(Self.bay1), round: round)
        // Arrangøren spiller ikke: knappen kommer når minst én er ferdig.
        guard case .offer(let offer)? = Self.prompt(game, Self.watcher) else {
            Issue.record("Ventet tilbud om å avslutte")
            return
        }
        #expect(offer.myMissingHoles == 0)
        #expect(offer.statusText == "1 flight er ikke ferdig.")
        let none = Self.game(scores: Self.full(Self.bay1 + Self.bay2), round: round)
        if case .offer(let all)? = Self.prompt(none, Self.watcher) {
            #expect(all.statusText == "Alle hullene er ført.")
        } else {
            Issue.record("Ventet tilbud om å avslutte")
        }
    }

    @Test func sisteHullFoertMenHullMangler() {
        // Bås 1 har ført hull 2–18, ikke hull 1.
        let game = Self.game(scores: Self.full(Self.bay1, holes: 1..<18))
        let boss = Viewer(memberID: F.id(F.anders), isOrganizer: true)
        guard case .offer(let offer)? = Self.prompt(game, boss, hole: 17) else {
            Issue.record("Ventet tilbud på siste hull")
            return
        }
        #expect(offer.myMissingHoles == 1)
        #expect(offer.statusText == "1 hull mangler på kortet ditt. 2 båser er ikke ferdige.")
        #expect(offer.extraConfirm?.title == "2 båser er ikke ferdige")
        // Ikke på siste hull: ingen knapp ennå.
        #expect(Self.prompt(game, boss, hole: 10) == nil)
        // Spilleren uten rett: kortet er ikke ferdig, ingenting.
        #expect(Self.prompt(game, Self.anders, hole: 17) == nil)
    }

    @Test func ikkeMensHullLiggerIKoEllerFoerPar() {
        let game = Self.game(scores: Self.full(Self.bay1 + Self.bay2))
        #expect(Self.prompt(game, Self.gunnar, pending: [17]) == nil)
        let unconfirmed = Self.game(scores: Self.full(Self.bay1 + Self.bay2), round: F.round(parConfirmed: false))
        #expect(Self.prompt(unconfirmed, Self.gunnar) == nil)
    }

    @Test func avsluttetRundeHarIngenKnapp() {
        let game = Self.game(scores: Self.full(Self.bay1 + Self.bay2), round: F.round(status: .locked))
        #expect(Self.prompt(game, Self.gunnar) == nil)
        #expect(Self.prompt(game, Self.anders) == nil)
        #expect(game.endOffer(viewer: Self.gunnar, canEnd: true, isLoose: false) == nil)
    }

    @Test func menyenGirTilbudOgsaaFoerKortetErFerdig() {
        let game = Self.game(scores: [])
        let offer = game.endOffer(viewer: Self.gunnar, canEnd: true, isLoose: false)
        #expect(offer?.myMissingHoles == 18)
        #expect(offer?.statusText == "18 hull mangler på kortet ditt. 2 båser er ikke ferdige.")
        #expect(game.endOffer(viewer: Self.anders, canEnd: false, isLoose: false) == nil)
    }

    // MARK: Låst kort etter levering

    @Test func leverKortetIStedetNaarKortLaases() {
        var rules = Ruleset.golfgutu
        rules.play.lockSubmittedCards = true
        let game = Self.game(scores: Self.full(Self.bay1 + Self.bay2), rules: rules)
        // Spilleren leverer kortet (`CardSubmissionSection`), ingen «Kortet ditt er ferdig».
        #expect(Self.prompt(game, Self.anders, cardLock: true) == nil)
        // Uten 057 i databasen: som før.
        #expect(Self.prompt(game, Self.anders, cardLock: false) == .cardDone(isLoose: false))
        // Arrangøren avslutter uansett.
        if case .offer? = Self.prompt(game, Self.gunnar, cardLock: true) {} else {
            Issue.record("Ventet tilbud om å avslutte")
        }
    }

    // MARK: Uten båser og løse runder

    @Test func utenBaaserTellesSpillerne() {
        let game = Self.game(scores: Self.full([F.anders]), bays: false)
        guard case .offer(let offer)? = Self.prompt(game, Self.watcher) else {
            Issue.record("Ventet tilbud om å avslutte")
            return
        }
        #expect(offer.unfinishedGroups == 0 && offer.unfinishedPlayers == 7)
        #expect(offer.statusText == "7 spillere er ikke ferdige.")
        let nearly = Self.game(scores: Self.full([1, 2, 3, 4, 5, 6, 7]), bays: false)
        if case .offer(let one)? = Self.prompt(nearly, Self.watcher) {
            #expect(one.statusText == "1 spiller er ikke ferdig.")
        } else {
            Issue.record("Ventet tilbud om å avslutte")
        }
    }

    @Test func blandetBaasOgSpillerUtenBaas() {
        let offer = RoundEndOffer(isLoose: false, myMissingHoles: 0, unfinishedGroups: 1, unfinishedPlayers: 2,
                                  groupTerm: .flight)
        #expect(offer.unfinishedText == "1 flight og 2 spillere er ikke ferdige")
    }

    @Test func losRunde() {
        let game = Self.game(scores: Self.full(Self.bay1 + Self.bay2))
        let owner = Viewer(memberID: F.id(F.anders), isOrganizer: true)
        guard case .offer(let offer)? = Self.prompt(game, owner, isLoose: true) else {
            Issue.record("Ventet tilbud om å avslutte")
            return
        }
        #expect(offer.confirmMessage
                == "Runden låses, og resultatet står. Ingen kan føre mer. Invitasjonen slutter å virke.")
        let player = Self.prompt(game, Self.anders, isLoose: true)
        #expect(player?.cardDoneText == "Alle hullene er ført. Den som startet runden, avslutter den.")
    }

    @Test func avkortetRundeErFerdigVedKuttet() {
        var round = F.round()
        round.cutRule = "common"
        round.cutAfter = 9
        let game = Self.game(scores: Self.full(Self.bay1, holes: 0..<9), round: round)
        #expect(Self.prompt(game, Self.anders, hole: 8) == .cardDone(isLoose: false))
    }
}
