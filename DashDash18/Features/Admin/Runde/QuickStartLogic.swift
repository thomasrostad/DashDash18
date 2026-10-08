import Foundation
import GolfgutuCore

// MARK: - Hurtigstart

/// Hvor en mangel rettes: snarveien fra lista over «Start runden».
nonisolated enum QuickStartTarget: Equatable, Sendable {
    /// Banevalget på hurtigstarten.
    case course
    /// Spillerne og gruppene («Spillere og båser»).
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
    /// Banene som passer stedet: simulatorbaner for Simulator, ekte baner for Ekte bane.
    /// Valgt bane blir alltid med, så et bytte av sted ikke tømmer valget.
    static func courses(_ courses: [CourseListItem], for venue: Venue, selected: UUID?) -> [CourseListItem] {
        let kind: CourseKind = venue == .course ? .course : .simulator
        return courses.filter { $0.kind == kind || $0.id == selected }
    }

    // MARK: Forslag fra forrige runde

    /// Forrige runde i sesongen: den siste som er startet (pågår eller låst) på en kveld til og med
    /// denne, i kveldsdato- og rundenummerets rekkefølge. Kladder teller ikke, de kan være forlatt.
    static func previousRound(rounds: [RoundRow], events: [EventRow], upTo event: EventRow) -> RoundRow? {
        let dates = Dictionary(events.map { ($0.id, $0.eventDate) }, uniquingKeysWith: { a, _ in a })
        return rounds
            .filter { $0.status != .draft }
            .compactMap { round in round.eventID.flatMap { dates[$0] }.map { (round, $0) } }
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
        draft.teeID = course.tee(previous.teeID)?.id
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
        // Teen hører til banen.
        draft.teeID = nil
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

