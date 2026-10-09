import Foundation
import GolfgutuCore

// Fase 21: arrangørsiden som tidslinje. Kvelden går gjennom fire steg, og arrangøren får én
// hovedknapp for det neste. Samme logikk på arrangørsiden, på Kvelden og på Hjem-kortet.

/// Stegene en kveld går gjennom, i rekkefølge.
nonisolated enum EveningStage: Int, CaseIterable, Comparable, Sendable {
    /// Gjengen svarer på om de kommer.
    case signup
    /// Runden settes opp (kladd).
    case setup
    /// En runde går.
    case playing
    /// Rundene er låst.
    case done

    var title: String {
        switch self {
        case .signup: "Påmelding"
        case .setup: "Oppsett"
        case .playing: "Spilles"
        case .done: "Ferdig"
        }
    }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Neste steg for arrangøren: hovedknappen på arrangørsiden, på Kvelden og på Hjem-kortet.
nonisolated enum TonightAction: Equatable, Sendable {
    /// Ingen kveld i terminlista.
    case noEvening
    /// Noen har ikke svart: purr på dem (antallet).
    case nudge(Int)
    /// Ingen runde ennå.
    case setUp
    /// Kladden (den siste) er ikke startet.
    case continueDraft(UUID)
    case goToRound(UUID)
    /// Alle hull er ført i runden som går.
    case closeEvening(UUID)
    /// Rundene er låst: resultatet står på Tavla.
    case seeResult
    /// Kvelden er passert uten runder. Ingen knapp.
    case notPlayed

    /// Samme ord overalt i appen. nil: ingen knapp. `term`: «kveld» eller «spilledag» (`DayTerm`).
    func buttonTitle(_ term: DayTerm = .evening) -> String? {
        switch self {
        case .noEvening: "Legg inn en \(term.one)"
        case .nudge(let count): "Purr " + Nudge.who(count)
        case .setUp: "Sett opp runden"
        case .continueDraft: "Fortsett kladd"
        case .goToRound: "Gå til runden"
        case .closeEvening: "Avslutt \(term.the)"
        case .seeResult: "Se resultatet"
        case .notPlayed: nil
        }
    }
}

/// Hvor kvelden står og hva som er neste steg.
nonisolated struct EveningProgress: Equatable, Sendable {
    /// nil når det ikke er noen kveld, eller kvelden er passert uten runder.
    let stage: EveningStage?
    let action: TonightAction

    /// Stegrekka med ✓ for det som er gjort og markering av steget kvelden står på.
    var steps: [EveningStepMark] {
        EveningStage.allCases.map { step in
            guard let stage else { return EveningStepMark(stage: step, state: .upcoming) }
            if stage == .done { return EveningStepMark(stage: step, state: .done) }
            if step < stage { return EveningStepMark(stage: step, state: .done) }
            return EveningStepMark(stage: step, state: step == stage ? .current : .upcoming)
        }
    }
}

/// Ett steg i stegrekka.
nonisolated struct EveningStepMark: Equatable, Identifiable, Sendable {
    enum State: Equatable, Sendable { case done, current, upcoming }
    let stage: EveningStage
    let state: State
    var id: EveningStage { stage }
}

/// Seksjonene på Kvelden, i fast rekkefølge: før, under og etter kvelden.
nonisolated enum EveningPart: CaseIterable, Equatable, Sendable {
    case before, during, after

    func title(_ term: DayTerm = .evening) -> String {
        switch self {
        case .before: "Før \(term.the)"
        case .during: "Under \(term.the)"
        case .after: "Etter \(term.the)"
        }
    }

    /// Delen kvelden er i: påmelding er før, oppsett og spill er under, ferdig er etter.
    static func current(_ stage: EveningStage?) -> EveningPart? {
        switch stage {
        case .signup: .before
        case .setup, .playing: .during
        case .done: .after
        case nil: nil
        }
    }
}

nonisolated enum Tonight {
    /// Overskriften over kortet: «I kveld» når kvelden er i dag, «Siste kveld» når den er passert.
    static func sectionTitle(daysUntil: Int?, term: DayTerm = .evening) -> String {
        guard let daysUntil else { return "Neste \(term.one)" }
        if daysUntil == 0 { return term.today }
        return daysUntil < 0 ? "Siste \(term.one)" : "Neste \(term.one)"
    }

    /// Kvelden som står for tur på arrangørsiden: kvelden der en runde går, så kvelden i dag (også
    /// når den er ferdig, så resultatet står øverst resten av dagen), så neste kveld. Er alle
    /// passert, den siste.
    static func focusEvent(_ events: [EventRow], today: String, activeRound: RoundRow?) -> EventRow? {
        if let eventID = activeRound?.eventID, let event = events.first(where: { $0.id == eventID }) {
            return event
        }
        let sorted = events.sorted { $0.eventDate < $1.eventDate }
        return sorted.first { $0.eventDate >= today } ?? sorted.last
    }

    /// Hvor kvelden står og neste steg.
    /// - Parameters:
    ///   - rounds: rundene i klubben (bare kveldens teller).
    ///   - activeRound: runden som går i klubben, og `activeComplete` om alle hull er ført i den.
    ///   - notAnswered: antall i troppen som ikke har svart på kvelden.
    static func progress(event: EventRow?, rounds: [RoundRow], activeRound: RoundRow?, activeComplete: Bool,
                         notAnswered: Int, today: String) -> EveningProgress {
        guard let event else { return EveningProgress(stage: nil, action: .noEvening) }
        let own = rounds.filter { $0.eventID == event.id }
        if let active = own.first(where: { $0.status == .active }) {
            let complete = activeComplete && activeRound?.id == active.id
            return EveningProgress(stage: .playing, action: complete ? .closeEvening(active.id) : .goToRound(active.id))
        }
        if let draft = own.filter({ $0.status == .draft }).max(by: { $0.roundNo < $1.roundNo }) {
            return EveningProgress(stage: .setup, action: .continueDraft(draft.id))
        }
        if own.contains(where: { $0.status == .locked }) {
            return EveningProgress(stage: .done, action: .seeResult)
        }
        if event.eventDate < today { return EveningProgress(stage: nil, action: .notPlayed) }
        // Kvelden i dag settes opp selv om noen ikke har svart.
        if event.eventDate > today && notAnswered > 0 {
            return EveningProgress(stage: .signup, action: .nudge(notAnswered))
        }
        return EveningProgress(stage: .setup, action: .setUp)
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

    /// Kort status for kvelden: «Ikke satt opp», «Kladd lagret · ikke startet», «Runde 1 pågår» …
    static func statusText(action: TonightAction, rounds: [RoundRow], activeTitle: String?,
                           term: DayTerm = .evening) -> String {
        switch action {
        case .noEvening: return "Ingen \(term.one) i terminlista"
        case .nudge(let count): return count == 1 ? "1 har ikke svart" : "\(count) har ikke svart"
        case .setUp: return "Ikke satt opp"
        case .continueDraft: return "Kladd lagret · ikke startet"
        case .goToRound: return (activeTitle ?? "Runden") + " pågår"
        case .closeEvening: return "Alle hull er ført"
        case .seeResult, .notPlayed: return result(rounds)
        }
    }

    /// Resultatlinja for en passert kveld: «Ferdig · 2 runder · Pebble Beach», «Ingen runder spilt».
    /// - Parameter courseName: banenavnet for en runde, når det er kjent.
    static func result(_ rounds: [RoundRow], courseName: (RoundRow) -> String? = { _ in nil }) -> String {
        let locked = rounds.filter { $0.status == .locked }.sorted { $0.roundNo < $1.roundNo }
        guard !locked.isEmpty else { return "Ingen runder spilt" }
        var parts = ["Ferdig", locked.count == 1 ? "1 runde" : "\(locked.count) runder"]
        var names: [String] = []
        for name in locked.compactMap(courseName) where !names.contains(name) { names.append(name) }
        if !names.isEmpty { parts.append(names.joined(separator: ", ")) }
        return parts.joined(separator: " · ")
    }
}

/// Kveldene i tidslinja på arrangørsiden: tidligere over kvelden som står for tur, kommende under.
nonisolated enum EveningTimeline {
    struct Parts: Equatable, Sendable {
        /// Før kvelden som står for tur, eldste først.
        let past: [EventRow]
        /// Kvelden som står for tur (kortet øverst). nil når «Kom i gang» står der.
        let focus: EventRow?
        /// Etter, eldste først.
        let upcoming: [EventRow]
    }

    /// Alt i datorekkefølge. Uten kvelden som står for tur (eller når «Kom i gang» står der) deles
    /// det på i dag: passerte over, i dag og senere under.
    static func parts(_ events: [EventRow], focus: EventRow?, today: String) -> Parts {
        let sorted = events.sorted { $0.eventDate < $1.eventDate }
        guard let focus, sorted.contains(where: { $0.id == focus.id }) else {
            return Parts(past: sorted.filter { $0.eventDate < today }, focus: nil,
                         upcoming: sorted.filter { $0.eventDate >= today })
        }
        let index = sorted.firstIndex { $0.id == focus.id }!
        return Parts(past: Array(sorted[..<index]), focus: focus, upcoming: Array(sorted[(index + 1)...]))
    }
}
