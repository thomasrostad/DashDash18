import Foundation
import GolfgutuCore

/// «Samme som sist» og rundemaler i oppsettet (sql/049).
extension RundeAdminModel {
    /// Oppsettet fra forrige startede runde i turneringen (`previous_round_setup`).
    func previousSetup(for eventID: UUID) async -> ReuseService.Previous {
        await ReuseService.previousRoundSetup(client: clubContext.client, eventID: eventID)
    }

    /// Klubbens rundemaler, for den som har rettigheten `rounds`. nil: ingen maler i oppsettet.
    func roundTemplates() -> SetupTemplateStore? {
        guard clubContext.can(.rounds) else { return nil }
        return SetupTemplateStore(client: clubContext.client, clubID: clubContext.clubID, kind: .round)
    }

    /// Fyller inn oppsettet (fra forrige runde eller en mal). Spillerne står; lag, matcher og grupper
    /// legges på nytt når formen skiftet.
    func apply(_ setup: RoundTemplatePayload, to draft: inout RoundDraft) {
        let form = draft.formID
        setup.apply(to: &draft, courses: courses, rules: rules, roster: members, plan: drawPlan(for: draft))
        if draft.teeID == nil { draft.teeID = suggestedTeeID(for: course(draft.courseID)) }
        if draft.formID != form {
            QuickStart.autoArrange(&draft, rules: rules, roster: members, plan: drawPlan(for: draft))
        }
    }

    /// «Samme spillere»: spillerne, gruppene, lagene og matchene fra forrige runde.
    func applyPlayers(from previous: PreviousRoundSetup, to draft: inout RoundDraft) {
        previous.applyPlayers(to: &draft, roster: members)
        draft.prepareSetup(rules: rules, roster: members, plan: drawPlan(for: draft))
    }

    /// «Ny trekning»: de påmeldte, nye lag og matcher, og gruppene fordelt på nytt.
    func freshDraw(_ draft: inout RoundDraft) {
        let (ids, source) = RoundParticipants.initial(roster: members, signups: signups)
        draft.participants = ids
        draft.participantSource = source
        draft.teams = [:]
        draft.matches = []
        draft.prepareSetup(rules: rules, roster: members, plan: drawPlan(for: draft))
        if rules.table.pointsSource == .matches {
            draft.redrawMatches(roster: members, plan: drawPlan(for: draft))
        }
        draft.reshuffleBays(count: BayPlan.defaultBayCount(players: draft.participants.count,
                                                           maxPerBay: rules.formats.maxPerBay))
    }
}
