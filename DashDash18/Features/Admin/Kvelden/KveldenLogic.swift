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

    /// Gruppene som har noen i seg: «Kommer», «Venteliste», «Usikker», «Kommer ikke», «Ikke svart»
    /// (og «Ikke sett» når det er kjent). Gjester står med «(gjest av Anders)».
    static func groups(_ summary: SignupSummary) -> [(title: String, names: [String])] {
        summary.groups.filter { !$0.entries.isEmpty }.map { group in
            (group.title, group.entries.map { entry in
                entry.invitedBy.map { "\(entry.name) (gjest av \($0))" } ?? entry.name
            })
        }
    }

    /// Det arrangøren har slått på for kvelden: «14 av 16 plasser», fristene og gjester.
    static func settingsLines(_ settings: EveningSettingsRow, summary: SignupSummary,
                              includeGuests: Bool = true) -> [String] {
        var lines: [String] = []
        if let text = EveningSignupText.capacity(coming: summary.coming, max: settings.maxPlayers,
                                                 waitlist: summary.waitlist.count) {
            lines.append(text)
        }
        if let date = settings.signupDeadline { lines.append(EveningSignupText.deadline("Påmeldingsfrist", date)) }
        if let date = settings.withdrawDeadline { lines.append(EveningSignupText.deadline("Avmeldingsfrist", date)) }
        if settings.allowGuests && includeGuests { lines.append("Gjester er tillatt") }
        return lines
    }
}
