import Foundation
import GolfgutuCore
import Testing
@testable import DashDash18

/// Regelvern (`play` i regelsettet): maks slag per hull i føringen, låst kort etter levering (sql/057)
/// og antall skjulte hull i runde-oppsettet. Med Golfgutu-oppsettet er alt som før.
@MainActor
struct RegelvernTests {
    typealias F = ForingFixture

    static func rules(_ change: (inout Ruleset) -> Void) -> Ruleset {
        var r = Ruleset.golfgutu
        change(&r)
        return r
    }

    /// Markør-oppsettet (Anders markør i bås 1), med regelsettet.
    static func game(_ rules: Ruleset, scores: [(Int, Int, Int)] = [], submitted: Set<Int> = [],
                     status: RoundStatus = .active) -> RoundGame {
        var s = F.snapshot(F.markorPlayers(), round: F.round(status: status), scores: scores)
        s.rules = rules
        s.players = s.players.map { p in
            var p = p
            if submitted.contains(where: { F.id($0) == p.memberID }) { p.cardSubmittedAt = Date(timeIntervalSince1970: 1) }
            return p
        }
        return RoundGame(s)
    }

    /// Alle hullene ført for bås 1.
    static var bay1Full: [(Int, Int, Int)] {
        [F.anders, F.bjorn, F.cato, F.dag].flatMap { p in (0..<18).map { (p, $0, F.par[$0]) } }
    }

    // MARK: Maks slag

    @Test func golfgutuHarIngenGrense() {
        let card = Self.game(.golfgutu).card(hole: 0, drafts: HoleDrafts(), viewer: F.viewer(F.anders))
        #expect(card.rows.allSatisfy { $0.maxStrokes == nil && !$0.isAtMax })
        #expect(StrokeInput.clamp(13, max: nil) == 12)
    }

    @Test func nettoDobbelBogeyStopperStepperen() {
        let game = Self.game(Self.rules { $0.play.maxStrokes = .netDoubleBogey })
        var drafts = HoleDrafts()
        drafts[0, F.id(F.bjorn)] = 9
        let card = game.card(hole: 0, drafts: drafts, viewer: F.viewer(F.anders))
        // Hull 1 er par 4, handicap 0: grensen er 6, og et utkast over grensen står på 6.
        let bjorn = card.rows.first { $0.memberID == F.id(F.bjorn) }!
        #expect(bjorn.maxStrokes == 6 && bjorn.value == 6 && bjorn.isAtMax)
        #expect(StrokeInput.clamp(bjorn.value + 1, max: bjorn.maxStrokes) == 6)
        #expect(StrokeAccessibility.received(bjorn) == "0 slag fått · maks 6")
    }

    @Test func fastGrenseOgKappetScore() {
        let rules = Self.rules { $0.play.maxStrokes = .fixed(5) }
        let game = Self.game(rules, scores: [(F.bjorn, 1, 8)])
        // Hull 2 er par 5: 8 slag teller som 5.
        #expect(game.scores(F.id(F.bjorn))[1] == 5)
        #expect(StrokeInput.clamp(7, max: 5) == 5)
    }

    // MARK: Låst kort

    @Test func leverKortetNaarAltErFoert() {
        let rules = Self.rules { $0.play.lockSubmittedCards = true }
        let half = Self.game(rules, scores: Array(Self.bay1Full.prefix(20)))
        #expect(half.cardSubmission(viewer: F.viewer(F.anders), pending: [], available: true)
                == .notReady(missingHoles: 18, hasPending: false))
        let full = Self.game(rules, scores: Self.bay1Full)
        let members = [F.anders, F.bjorn, F.cato, F.dag].map(F.id)
        #expect(full.cardSubmission(viewer: F.viewer(F.anders), pending: [], available: true) == .ready(members: members))
        #expect(full.cardSubmission(viewer: F.viewer(F.anders), pending: [17], available: true)
                == .notReady(missingHoles: 0, hasPending: true))
        // Av i regelsettet (Golfgutu) eller uten 057: ingenting.
        #expect(Self.game(.golfgutu, scores: Self.bay1Full).cardSubmission(viewer: F.viewer(F.anders), pending: [], available: true) == nil)
        #expect(full.cardSubmission(viewer: F.viewer(F.anders), pending: [], available: false) == nil)
        // Bjørn fører ikke: ingen knapp.
        #expect(full.cardSubmission(viewer: F.viewer(F.bjorn), pending: [], available: true) == nil)
    }

    @Test func levertKortErLaastForMarkorenMenIkkeArrangoren() {
        let rules = Self.rules { $0.play.lockSubmittedCards = true }
        let bay1 = Set([F.anders, F.bjorn, F.cato, F.dag])
        let game = Self.game(rules, scores: Self.bay1Full, submitted: bay1)
        let anders = F.viewer(F.anders)
        #expect(!game.canScore(anders, for: F.id(F.bjorn)))
        #expect(game.canScore(anders, for: F.id(F.bjorn), ignoringSubmission: true))
        #expect(game.card(hole: 0, drafts: HoleDrafts(), viewer: anders).rows.allSatisfy { !$0.editable })
        #expect(game.submission(hole: 0, drafts: HoleDrafts(), viewer: anders, recordedAt: Date()) == nil)
        let members = bay1.map(F.id).sorted { game.name($0) < game.name($1) }
        #expect(game.cardSubmission(viewer: anders, pending: [], available: true)?.isSubmitted == true)
        // Bjørn ser at kortet er levert; arrangøren (Gunnar) kan åpne det igjen.
        #expect(game.cardSubmission(viewer: F.viewer(F.bjorn), pending: [], available: true)
                == .submitted(members: game.cardPlayers(for: F.viewer(F.bjorn)), canReopen: false))
        #expect(game.canScore(F.viewer(F.gunnar), for: F.id(F.bjorn)))
        #expect(game.submittedCards() == [SubmittedCard(title: game.groupTerm.numbered(1), members: members)])
        // Bås 2 er ikke levert: Erik fører som før.
        #expect(game.canScore(F.viewer(F.erik), for: F.id(F.frode)))
    }

    @Test func kolonnenHentesBareMed057() {
        CardLockFeature.set(false)
        #expect(!RoundPlayerRow.columns.contains("card_submitted_at"))
        CardLockFeature.set(true)
        #expect(RoundPlayerRow.columns.contains("card_submitted_at"))
        CardLockFeature.set(false)
    }

    // MARK: Skjul de siste N hullene

    @Test func nyRundeTarAntalletFraRegelsettet() throws {
        let rules = Self.rules { $0.play.hiddenHoles = 5 }
        var draft = RoundDraft.new(eventID: F.eventID, roundNo: 1, teeTime: nil, participants: [], source: .signups, rules: rules)
        #expect(draft.storedHiddenHoles == 0)
        draft.hidesLastHoles = true
        #expect(draft.storedHiddenHoles == 5)
        draft.holeCount = 9
        draft.hiddenHoles = 9
        #expect(draft.storedHiddenHoles == 9)
        let golfgutu = RoundDraft.new(eventID: F.eventID, roundNo: 1, teeTime: nil, participants: [], source: .signups, rules: .golfgutu)
        #expect(golfgutu.hiddenHoles == 3)
    }

    @Test func lagretAntallLesesTilbakeOgGjenbrukes() throws {
        var row = F.round(status: .draft)
        row.hideLastHoles = 6
        let draft = RoundDraft.saved(row, players: [], matches: [], participants: [], source: .signups)
        #expect(draft.hidesLastHoles && draft.hiddenHoles == 6 && draft.storedHiddenHoles == 6)
        let payload = RoundTemplatePayload(draft: draft)
        #expect(payload.hideLastHoles == 6)
        var other = RoundDraft.new(eventID: F.eventID, roundNo: 2, teeTime: nil, participants: [], source: .signups, rules: .golfgutu)
        payload.apply(to: &other, courses: [], rules: .golfgutu, roster: [])
        #expect(other.hidesLastHoles && other.hiddenHoles == 6)
    }

    // MARK: Regel-editoren og ⓘ-arket

    @Test func golfgutuForklaringenErUendret() {
        #expect(RulesetExplanation.playSentences(Ruleset.golfgutu.play).isEmpty)
        for field in PlayField.allCases { #expect(!field.differs(.golfgutu, .golfgutu)) }
    }

    @Test func endringeneVisesOgForklares() {
        var draft = RulesetDraft(.golfgutu)
        draft.maxStrokesKind = .fixed
        #expect(draft.rules.play.maxStrokes == .fixed(RulesetDraft.defaultFixedMaxStrokes))
        draft.fixedMaxStrokes = 8
        draft.rules.play.lockSubmittedCards = true
        draft.rules.play.hiddenHoles = 4
        draft.rules.play.shankPosts = true
        #expect(draft.changedFields == [.other])
        #expect(PlayField.allCases.allSatisfy { draft.changeNote($0) != nil })
        #expect(draft.changeNote(.maxStrokes) == "Endret · standard av")
        let sentences = RulesetExplanation.playSentences(draft.rules.play)
        #expect(sentences.count == 4)
        #expect(sentences.contains { $0.contains("shank") })
        #expect(sentences[0].contains("8 slag"))
        draft.maxStrokesKind = .netDoubleBogey
        #expect(RulesetExplanation.playSentences(draft.rules.play)[0].contains("netto dobbel bogey"))
        draft.rules.play.hiddenHoles = 0
        #expect(draft.issues(in: .play).map(\.field) == ["play.hiddenHoles"])
        #expect(!draft.canSave)
    }
}

extension CardSubmission {
    var isSubmitted: Bool {
        if case .submitted = self { return true }
        return false
    }
}
