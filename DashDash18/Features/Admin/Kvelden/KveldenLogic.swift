import Foundation

/// Hvor langt kvelden har kommet med rundene, til lista «Kveldene»: «Ingen runder»,
/// «2 runder · 1 pågår», «1 runde · kladd», «Ferdig».
nonisolated enum EveningRounds {
    enum Phase: Equatable, Sendable {
        /// Ingen runder satt opp.
        case none
        /// Bare kladder (og kanskje låste runder), ingen går.
        case draft
        /// En runde går.
        case active
        /// Alle rundene er låst.
        case done
    }

    static func phase(_ rounds: [RoundRow]) -> Phase {
        if rounds.isEmpty { return .none }
        if rounds.contains(where: { $0.status == .active }) { return .active }
        if rounds.allSatisfy({ $0.status == .locked }) { return .done }
        return .draft
    }

    static func text(_ rounds: [RoundRow]) -> String {
        switch phase(rounds) {
        case .none: return "Ingen runder"
        case .done: return "Ferdig"
        case .draft, .active:
            var parts = [rounds.count == 1 ? "1 runde" : "\(rounds.count) runder"]
            let active = rounds.filter { $0.status == .active }.count
            let drafts = rounds.filter { $0.status == .draft }.count
            if active > 0 { parts.append("\(active) pågår") }
            if drafts > 0 { parts.append(drafts == 1 ? "1 kladd" : "\(drafts) kladder") }
            return parts.joined(separator: " · ")
        }
    }
}

/// Det Kvelden-skjermen viser om påmeldingen.
nonisolated enum EveningSignup {
    /// Purring gir mening for kvelder som ikke er passert, når noen mangler svar.
    static func offersNudge(eventDate: String, today: String, summary: SignupSummary) -> Bool {
        eventDate >= today && Nudge.isOffered(isOrganizer: true, summary: summary)
    }

    /// Gruppene som har noen i seg: «Kommer», «Usikker», «Kommer ikke», «Ikke svart».
    static func groups(_ summary: SignupSummary) -> [(title: String, names: [String])] {
        summary.groups.filter { !$0.entries.isEmpty }.map { ($0.title, $0.entries.map(\.name)) }
    }
}
