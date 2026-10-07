import Foundation
import GolfgutuCore

// MARK: - Hurtigstart

/// Hvor en mangel rettes: snarveien fra lista over «Start runden».
nonisolated enum QuickStartTarget: Equatable, Sendable {
    /// Banevalget på hurtigstarten.
    case course
    /// Spillerne og gruppene (dagens bås-steg).
    case players
    /// «Flere valg»: form, lag, matcher, sidepremier, vekt og handicap.
    case moreOptions

    var shortcutTitle: String {
        switch self {
        case .course: "Velg bane"
        case .players: "Endre spillere"
        case .moreOptions: "Flere valg"
        }
    }
}

/// Én ting som mangler før runden kan starte, med snarvei dit.
nonisolated struct QuickStartProblem: Equatable, Identifiable, Sendable {
    let message: String
    let target: QuickStartTarget?
    var id: String { message }
}

/// Startvalget på hurtigstarten: hull og antall som én rad («Hull 1 · 18 hull»).
nonisolated struct QuickStartStart: Equatable, Hashable, Sendable {
    let firstHole: Int
    let holeCount: Int

    var title: String { "Hull \(firstHole) · \(holeCount) hull" }
}

/// Ren logikk for hurtigstarten: forslag fra forrige runde, automatisk fordeling, startvalg og mangler.
nonisolated enum QuickStart {
    // MARK: Forslag fra forrige runde

    /// Forrige runde i sesongen: den siste som er startet (pågår eller låst) på en kveld til og med
    /// denne, i kveldsdato- og rundenummerets rekkefølge. Kladder teller ikke, de kan være forlatt.
    static func previousRound(rounds: [RoundRow], events: [EventRow], upTo event: EventRow,
                              excluding roundID: UUID? = nil) -> RoundRow? {
        let dates = Dictionary(events.map { ($0.id, $0.eventDate) }, uniquingKeysWith: { a, _ in a })
        return rounds
            .filter { $0.status != .draft && $0.id != roundID }
            .compactMap { round in dates[round.eventID].map { (round, $0) } }
            .filter { $0.1 <= event.eventDate }
            .max { ($0.1, $0.0.roundNo) < ($1.1, $1.0.roundNo) }?
            .0
    }

    /// Fyller inn det forrige runde valgte: sted, bane, start, LD- og KP-hull og vekt. Banen tas bare
    /// når den fortsatt er klar; ellers står regelsettets standard (og første klare bane).
    static func applySuggestion(from previous: RoundRow?, to draft: inout RoundDraft,
                                courses: [CourseListItem], rules: Ruleset) {
        guard let previous else { return }
        draft.setVenue(Venue(stored: previous.venue), rules: rules)
        draft.weight = previous.weight
        guard let course = courses.first(where: { $0.id == previous.courseID && $0.isReady }) else { return }
        draft.courseID = course.id
        draft.holeCount = previous.holeCount
        draft.firstHole = RoundDraft.canStartAtTen(holeCount: previous.holeCount, courseHoles: course.holeCount)
            ? previous.firstHole : 1
        draft.ldHoleIndex = previous.ldHoleIndex.flatMap { $0 < draft.holeCount ? $0 : nil }
        draft.kpHoleIndex = previous.kpHoleIndex.flatMap { $0 < draft.holeCount ? $0 : nil }
    }

    /// Ny runde fordelt automatisk: lag (i lagform) og matcher, så gruppene med duellpartnerne
    /// samlet og så få grupper som rommer alle (`foreslaatteBaaser`).
    static func autoArrange(_ draft: inout RoundDraft, rules: Ruleset, roster: [ClubMemberRow]) {
        draft.prepareSetup(rules: rules, roster: roster)
        draft.reshuffleBays(count: BayPlan.defaultBayCount(players: draft.participants.count,
                                                           maxPerBay: rules.formats.maxPerBay))
    }

    // MARK: Start

    /// Startvalgene for banen: 18 hull fra hull 1, 9 hull fra hull 1, og siste ni på en 18-hullsbane.
    static func startOptions(courseHoles: Int?) -> [QuickStartStart] {
        var options = [QuickStartStart(firstHole: 1, holeCount: 18), QuickStartStart(firstHole: 1, holeCount: 9)]
        if RoundDraft.canStartAtTen(holeCount: 9, courseHoles: courseHoles) {
            options.append(QuickStartStart(firstHole: 10, holeCount: 9))
        }
        return options
    }

    /// Setter start og antall hull. LD og KP går tilbake til forslaget når de havner utenfor runden.
    static func setStart(_ start: QuickStartStart, on draft: inout RoundDraft, courseHoles: Int?) {
        draft.holeCount = start.holeCount
        draft.firstHole = RoundDraft.canStartAtTen(holeCount: start.holeCount, courseHoles: courseHoles)
            ? start.firstHole : 1
        if let ld = draft.ldHoleIndex, ld >= draft.holeCount { draft.ldHoleIndex = nil }
        if let kp = draft.kpHoleIndex, kp >= draft.holeCount { draft.kpHoleIndex = nil }
    }

    /// Ny bane: LD og KP tilbake til forslaget for den banen, og hull 10 bare der det går.
    static func setCourse(_ id: UUID?, on draft: inout RoundDraft, courseHoles: Int?) {
        guard id != draft.courseID else { return }
        draft.courseID = id
        draft.ldHoleIndex = nil
        draft.kpHoleIndex = nil
        if !RoundDraft.canStartAtTen(holeCount: draft.holeCount, courseHoles: courseHoles) { draft.firstHole = 1 }
    }

    // MARK: Tekst

    /// «12 påmeldt · 3 båser», «8 med · 2 flighter».
    static func playersSummary(_ draft: RoundDraft) -> String {
        let count = draft.participants.count
        let who = draft.participantSource == .signups ? "\(count) påmeldt" : "\(count) med"
        var bays = draft.bays
        bays.keepOnly(Set(draft.participants))
        let groups = bays.bayNumbers.count
        return groups > 0 ? who + " · " + draft.groupTerm.count(groups) : who
    }

    /// Hvem er i hvilken gruppe, kort: «Bås 1: Anders (markør), Bjørn, Cato».
    static func groupLines(_ draft: RoundDraft, name: (UUID) -> String) -> [String] {
        var bays = draft.bays
        bays.keepOnly(Set(draft.participants))
        return bays.bayNumbers.map { bay in
            let marker = bays.marker(in: bay)
            let names = bays.members(in: bay).map { $0 == marker ? "\(name($0)) (\(draft.groupTerm.marker))" : name($0) }
            return "\(draft.groupTerm.numbered(bay)): " + names.joined(separator: ", ")
        }
    }

    // MARK: Mangler

    /// Det som stopper «Start runden», med snarvei. En runde som går, står først, uten snarvei:
    /// den må låses (eller denne lagres som kladd).
    static func problems(_ issues: [RoundSetupIssue], term: GroupTerm, blockingTitle: String?) -> [QuickStartProblem] {
        var problems: [QuickStartProblem] = []
        if let blockingTitle {
            problems.append(QuickStartProblem(
                message: "\(blockingTitle) går fortsatt. Lagre denne som kladd, og start den når den andre er låst.",
                target: nil))
        }
        problems += issues.map { QuickStartProblem(message: $0.message(term), target: target(for: $0)) }
        return problems
    }

    static func target(for issue: RoundSetupIssue) -> QuickStartTarget {
        switch issue {
        case .noCourse, .courseNotReady: .course
        case .tooFewPlayers, .bayWithoutMarker: .players
        case .formNotAllowed, .formNotSupported, .teams, .matches, .sidePrizeOutsideRound: .moreOptions
        }
    }
}

// MARK: - Arrangørsiden: «I kveld»

/// Hovedknappen under «I kveld».
nonisolated enum TonightAction: Equatable, Sendable {
    /// Ingen kveld i terminlista.
    case noEvening
    case setUp
    case continueDraft(UUID)
    case goToRound(UUID)
    /// Alle hull er ført i runden som går.
    case closeEvening(UUID)

    var buttonTitle: String {
        switch self {
        case .noEvening: "Legg inn en kveld"
        case .setUp: "Sett opp runden"
        case .continueDraft: "Fortsett kladd"
        case .goToRound: "Gå til runden"
        case .closeEvening: "Avslutt kvelden"
        }
    }
}

nonisolated enum Tonight {
    /// Hva arrangøren trolig vil gjøre nå. En runde som går, vinner (også på en annen kveld); så en
    /// kladd på kvelden (den siste); ellers en ny runde.
    static func action(event: EventRow?, rounds: [RoundRow], activeRound: RoundRow?, activeComplete: Bool) -> TonightAction {
        if let activeRound {
            return activeComplete ? .closeEvening(activeRound.id) : .goToRound(activeRound.id)
        }
        guard let event else { return .noEvening }
        if let draft = rounds.filter({ $0.eventID == event.id && $0.status == .draft }).max(by: { $0.roundNo < $1.roundNo }) {
            return .continueDraft(draft.id)
        }
        return .setUp
    }

    /// Er alle hull ført? Etter avkorting teller bare hullene fram til avkortingen.
    static func isComplete(scoredHoles: Int, players: Int, round: RoundRow) -> Bool {
        let holes = round.cutAfter.map { min($0, round.holeCount) } ?? round.holeCount
        return players > 0 && scoredHoles >= players * holes
    }

    /// «9 av 12 kommer · 1 usikker», eller «Ingen har svart ennå».
    static func signupText(_ signups: [SignupRow], rosterCount: Int) -> String {
        let yes = signups.filter { $0.status == .yes }.count
        let maybe = signups.filter { $0.status == .maybe }.count
        if signups.isEmpty { return "Ingen har svart ennå · \(rosterCount) i troppen" }
        var text = "\(yes) av \(rosterCount) kommer"
        if maybe > 0 { text += " · \(maybe) " + (maybe == 1 ? "usikker" : "usikre") }
        return text
    }

    /// Kort status for kvelden: «Ikke satt opp», «Kladd klar», «Runde 1 pågår» …
    static func statusText(action: TonightAction, rounds: [RoundRow], activeTitle: String?) -> String {
        switch action {
        case .noEvening: return "Ingen kveld i terminlista"
        case .continueDraft: return "Kladd lagret · ikke startet"
        case .goToRound: return (activeTitle ?? "Runden") + " pågår"
        case .closeEvening: return "Alle hull er ført"
        case .setUp:
            let locked = rounds.filter { $0.status == .locked }.count
            if locked == 0 { return "Ikke satt opp" }
            return locked == 1 ? "1 runde ferdig" : "\(locked) runder ferdig"
        }
    }
}
